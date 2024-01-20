//! This is a very incomplete implementation. You have been warned.

const std = @import("std");
const utils = @import("../utils.zig");

pub const TypeFlag = enum(u8) {
    aregular = 0,
    regular = '0',
    link = '1',
    symlink = '2',
    char = '3',
    block = '4',
    directory = '5',
    fifo = '6',
    continuous = '7',
    ext_header = 'x',
    ext_global_header = 'g',
    gnu_longname = 'L',
    gnu_longlink = 'K',
    gnu_sparse = 'S',
    _,
};

fn truncate(str: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, str, 0)) |i| {
        return str[0..i];
    } else return str;
}

pub const Header = struct {
    const empty = [_]u8{0} ** 512;

    pub const OldHeader = extern struct {
        name: [100]u8,
        mode: [8]u8,
        uid: [8]u8,
        gid: [8]u8,
        size: [12]u8,
        mtime: [12]u8,
        checksum: [8]u8,
        typeflag: TypeFlag,
        linkname: [100]u8,

        __padding: [255]u8,
    };

    pub const UstarHeader = extern struct {
        name: [100]u8,
        mode: [8]u8,
        uid: [8]u8,
        gid: [8]u8,
        size: [12]u8,
        mtime: [12]u8,
        checksum: [8]u8,
        typeflag: TypeFlag,
        linkname: [100]u8,

        magic: [6]u8,
        version: [2]u8,
        uname: [32]u8,
        gname: [32]u8,
        dev_major: [8]u8,
        dev_minor: [8]u8,
        prefix: [155]u8,

        __padding: [12]u8,
    };

    pub const GnuHeader = extern struct {
        pub const SparseHeader = extern struct {
            offset: [12]u8,
            numbytes: [12]u8,
        };

        name: [100]u8,
        mode: [8]u8,
        uid: [8]u8,
        gid: [8]u8,
        size: [12]u8,
        mtime: [12]u8,
        checksum: [8]u8,
        typeflag: TypeFlag,
        linkname: [100]u8,

        magic: [6]u8,
        version: [2]u8,
        uname: [32]u8,
        gname: [32]u8,
        dev_major: [8]u8,
        dev_minor: [8]u8,
        atime: [12]u8,
        ctime: [12]u8,
        offset: [12]u8,
        long_names: [4]u8,
        __unused: u8,
        sparse: [4]SparseHeader,
        is_extended: u8,
        real_size: [12]u8,

        __padding: [17]u8,
    };

    pub const GnuExtSparseHeader = extern struct {
        sparse: [21]GnuHeader.SparseHeader,
        is_extended: u8,

        __padding: [7]u8,
    };

    comptime {
        std.debug.assert(@sizeOf(OldHeader) == 512 and @bitSizeOf(OldHeader) == 512 * 8);
        std.debug.assert(@sizeOf(UstarHeader) == 512 and @bitSizeOf(UstarHeader) == 512 * 8);
        std.debug.assert(@sizeOf(GnuHeader) == 512 and @bitSizeOf(GnuHeader) == 512 * 8);
        std.debug.assert(@sizeOf(GnuHeader.SparseHeader) == 24 and @bitSizeOf(GnuHeader.SparseHeader) == 24 * 8);
        std.debug.assert(@sizeOf(GnuExtSparseHeader) == 512 and @bitSizeOf(GnuExtSparseHeader) == 512 * 8);
    }

    buffer: [512]u8,
    offset: usize = 0,

    longname: ?[]const u8 = null,
    longlink: ?[]const u8 = null,

    pub fn asOld(self: Header) *const OldHeader {
        return @ptrCast(&self.buffer);
    }

    pub fn asUstar(self: Header) *const UstarHeader {
        return @ptrCast(&self.buffer);
    }

    pub fn asGnu(self: Header) *const GnuHeader {
        return @ptrCast(&self.buffer);
    }

    pub fn isUstar(self: Header) bool {
        const header = self.asUstar();

        return std.mem.eql(u8, &header.magic, "ustar\x00") and std.mem.eql(u8, &header.version, "00");
    }

    pub fn isGnu(self: Header) bool {
        const header = self.asGnu();

        return std.mem.eql(u8, &header.magic, "ustar ") and std.mem.eql(u8, &header.version, " \x00");
    }

    pub fn filename(self: Header) []const u8 {
        if (self.longname) |name| return name;

        const header = self.asOld();
        return truncate(&header.name);
    }

    pub fn kind(self: Header) TypeFlag {
        const header = self.asOld();

        return header.typeflag;
    }

    pub fn mode(self: Header) !std.os.mode_t {
        const header = self.asOld();

        const str = truncate(&header.mode);
        return if (str.len == 0) 0 else try std.fmt.parseUnsigned(std.os.mode_t, str, 8);
    }

    pub fn entrySize(self: Header) !u64 {
        const header = self.asOld();

        const str = truncate(&header.size);
        return if (str.len == 0) 0 else try std.fmt.parseUnsigned(u64, str, 8);
    }

    pub fn alignedEntrySize(self: Header) !u64 {
        return std.mem.alignForward(u64, try self.entrySize(), 512);
    }

    pub fn realSize(self: Header) !u64 {
        if (self.kind() == .gnu_sparse) {
            const header = self.asGnu();

            const str = truncate(&header.real_size);
            return if (str.len == 0) 0 else try std.fmt.parseUnsigned(u64, str, 8);
        } else return try self.entrySize();
    }

    pub fn preprocess(parser: *Parser, reader: anytype, strings: *usize, entries: *usize) !usize {
        var header = Header{
            .buffer = undefined,
        };

        const read = try reader.readAll(&header.buffer);
        if (read != 512) return error.InvalidHeader;

        if (std.mem.eql(u8, &header.buffer, &Header.empty)) return 512;

        switch (header.kind()) {
            .gnu_longname, .gnu_longlink => {
                strings.* += try header.realSize();
            },
            else => {
                entries.* += 1;
            },
        }

        const total_data_len = try header.alignedEntrySize();
        try parser.file.seekBy(@intCast(total_data_len));

        return total_data_len + 512;
    }

    pub fn parse(self: *Header, parser: *Parser, reader: anytype, offset: usize) !usize {
        const read = try reader.readAll(&self.buffer);
        if (read != 512) return error.InvalidHeader;

        if (std.mem.eql(u8, &self.buffer, &Header.empty)) return 512;

        self.offset = offset;

        const total_data_len = try self.alignedEntrySize();
        switch (self.kind()) {
            .gnu_longname => {
                const size = try self.entrySize();

                parser.last_longname = truncate(try parser.readString(reader, size));
                parser.reuse_last_entry = true;

                try parser.file.seekBy(@intCast(total_data_len - size));
            },
            .gnu_longlink => {
                const size = try self.entrySize();

                parser.last_longlink = truncate(try parser.readString(reader, size));
                parser.reuse_last_entry = true;

                try parser.file.seekBy(@intCast(total_data_len - size));
            },
            else => {
                if (parser.last_longname) |name| {
                    self.longname = name;

                    parser.last_longname = null;
                } else {
                    self.longname = null;
                }

                if (parser.last_longlink) |name| {
                    self.longlink = name;

                    parser.last_longlink = null;
                } else {
                    self.longlink = null;
                }

                try parser.file.seekBy(@intCast(total_data_len));
            },
        }

        return total_data_len + 512;
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,

    file: std.fs.File,
    reader: std.fs.File.Reader,

    entries: std.ArrayListUnmanaged(Header) = .{},
    string_buffer: std.ArrayListUnmanaged(u8) = .{},

    reuse_last_entry: bool = false,
    last_longname: ?[]const u8 = null,
    last_longlink: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, file: std.fs.File) Parser {
        return .{
            .allocator = allocator,

            .file = file,
            .reader = file.reader(),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.entries.deinit(self.allocator);
        self.string_buffer.deinit(self.allocator);
    }

    // TODO: update
    /// Loads a tar file.
    /// The best solution for loading with our file-tree system in mind seems to be a two-pass one:
    /// - On the first (PreloadPass) pass, count the number of entries and total length of filenames so we can pre-allocate them
    /// - On the second (LoadPass) pass, we can actually store things in our entries ArrayList
    pub fn load(self: *Parser) !void {
        var num_entries: usize = 0;
        var num_strings: usize = 0;

        const filesize = try self.file.getEndPos();
        var pos: usize = 0;

        while (pos < filesize) {
            pos += try Header.preprocess(self, self.reader, &num_strings, &num_entries);
        }

        try self.entries.ensureTotalCapacity(self.allocator, num_entries);
        try self.string_buffer.ensureTotalCapacity(self.allocator, num_strings);

        try self.file.seekTo(0);
        var index: usize = 0;
        pos = 0;

        while (index < num_entries) : (index += 1) {
            var entry = blk: {
                if (self.reuse_last_entry) {
                    self.reuse_last_entry = false;
                    index -= 1;

                    break :blk &self.entries.items[self.entries.items.len - 1];
                } else {
                    break :blk self.entries.addOneAssumeCapacity();
                }
            };

            pos += try entry.parse(self, self.reader, pos);
        }
    }

    fn readString(self: *Parser, reader: anytype, len: usize) ![]const u8 {
        if (len == 0) return "";

        try self.string_buffer.ensureUnusedCapacity(self.allocator, len);
        const prev_len = self.string_buffer.items.len;
        self.string_buffer.items.len += len;

        const buf = self.string_buffer.items[prev_len..][0..len];
        _ = try reader.readAll(buf);

        return buf;
    }

    pub fn getFileIndex(self: Parser, filename: []const u8) !usize {
        for (self.directory.items, 0..) |*hdr, i| {
            if (std.mem.eql(u8, hdr.filename, filename)) {
                return i;
            }
        }

        return error.FileNotFound;
    }

    pub fn readFileAlloc(self: Parser, allocator: std.mem.Allocator, index: usize) ![]const u8 {
        const header = self.directory[index];

        try self.seekTo(self.start_offset + header.local_header.offset);

        const buffer = try allocator.alloc(header.uncompressed_size);
        errdefer allocator.free(buffer);

        var read_buffered = std.io.BufferedReader(8192, std.fs.File.Reader){ .unbuffered_reader = self.reader };
        var limited_reader = utils.LimitedReader(std.io.BufferedReader(8192, std.fs.File.Reader).Reader).init(read_buffered.reader(), header.compressed_size);
        const reader = limited_reader.reader();

        var write_stream = std.io.fixedBufferStream(buffer);
        const writer = write_stream.writer();

        var fifo = std.fifo.LinearFifo(u8, .{ .Static = 8192 }).init();

        switch (header.compression) {
            .none => {
                try fifo.pump(reader, writer);
            },
            .deflated => {
                var window: [0x8000]u8 = undefined;
                var stream = std.compress.deflate.inflateStream(reader, &window);

                try fifo.pump(stream.reader(), writer);
            },
            else => return error.CompressionUnsupported,
        }
    }

    pub const ExtractOptions = struct {
        skip_components: u16 = 0,
    };

    pub fn extract(self: *Parser, dir: std.fs.Dir, options: ExtractOptions) !void {
        try self.file.seekTo(0);

        var buffered = std.io.BufferedReader(8192, std.fs.File.Reader){ .unbuffered_reader = self.reader };
        const reader = buffered.reader();

        var buffer: [8192]u8 = undefined;

        var index: usize = 0;
        extract: while (index < self.entries.items.len) : (index += 1) {
            const header = self.entries.items[index];

            const full_filename = header.filename();
            const entry_size = try header.entrySize();
            const aligned_entry_size = try header.alignedEntrySize();

            const new_filename = blk: {
                var component: usize = 0;
                var last_pos: usize = 0;
                while (component < options.skip_components) : (component += 1) {
                    last_pos = std.mem.indexOfPos(u8, full_filename, last_pos, "/") orelse {
                        try reader.skipBytes(aligned_entry_size, .{ .buf_size = 4096 });
                        continue :extract;
                    };
                }

                if (last_pos + 1 == full_filename.len) continue :extract;

                break :blk full_filename[last_pos + 1 ..];
            };

            switch (header.kind()) {
                .aregular, .regular => {
                    const dirname = std.fs.path.dirname(new_filename);
                    if (dirname) |name| try dir.makePath(name);

                    const fd = try dir.createFile(new_filename, .{ .mode = try header.mode() });
                    defer fd.close();

                    const writer = fd.writer();

                    var size_read: usize = 0;
                    while (size_read < entry_size) {
                        const needed = @min(buffer.len, entry_size - size_read);

                        const read = try reader.readAll(buffer[0..needed]);
                        if (read == 0) return error.Unknown;

                        size_read += read;

                        try writer.writeAll(buffer[0..read]);
                    }

                    try reader.skipBytes(aligned_entry_size - entry_size, .{ .buf_size = 4096 });
                    continue;
                },
                .directory => {
                    try dir.makePath(new_filename);

                    try reader.skipBytes(aligned_entry_size, .{ .buf_size = 4096 });
                    continue;
                },
                else => {
                    try reader.skipBytes(aligned_entry_size, .{ .buf_size = 4096 });
                    continue;
                },
            }
        }
    }
};
