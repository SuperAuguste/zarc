//! ~~Some~~ Most code taken from `https://github.com/mattnite/tar/blob/main/src/main.zig`, thanks Matt!
//! This does NOT implement the `Pre-POSIX.1-1988 (i.e. v7)` tar specification as nobody uses it anymore.

const std = @import("std");
const simd = @import("../utils/simd.zig");

const FileTypeFlag = enum(u8) {
    regular = '0',
    hard_link = '1',
    symbolic_link = '2',
    character = '3',
    block = '4',
    directory = '5',
    fifo = '6',
    reserved = '7',
    pax_global = 'g',
    extended = 'x',
    _,
};

pub const TarEntry = struct {
    /// Numeric values are encoded in octal numbers using ASCII digits, with leading zeroes. For historical reasons, a final NUL or space character should also be used.
    pub const Data = extern struct {
        name: [100]u8,
        mode: [7:0]u8,
        uid: [7:0]u8,
        gid: [7:0]u8,
        size: [11:0]u8,
        mtime: [11:0]u8,
        checksum: [8]u8,
        type_flag: FileTypeFlag,
        link_name: [100]u8,
        magic: [5:0]u8,
        version: [2]u8,
        uname: [31:0]u8,
        gname: [31:0]u8,
        devmajor: [7:0]u8,
        devminor: [7:0]u8,
        prefix: [155]u8,
        pad: [12]u8,

        /// Get the value of a numeric field.
        pub fn getNumeric(self: *Data, comptime T: type, comptime field: []const u8) !T {
            return simd.parseOctal(T, @field(self, field).len, &@field(self, field));
        }

        pub fn getSize(self: *Data) !u33 {
            var size = try self.getNumeric(u64, "size");

            return @intCast(u33, ((size + 511) / 512) * 512);
        }

        pub fn getFilename(self: *Data, buf: []u8) void {
            var prefix = std.mem.span(@ptrCast([*:0]u8, &self.prefix));
            var principal = std.mem.span(@ptrCast([*:0]u8, &self.name));
            std.mem.copy(u8, buf[0..prefix.len], prefix);
            std.mem.copy(u8, buf[prefix.len..], principal);
        }

        /// Used to verify and set the checksum of a tar.
        pub fn calculateChecksum(self: *Data, buf: []u8) !void {
            const offset = @offsetOf(Data, "checksum");
            var checksum: usize = 0;

            for (std.mem.asBytes(self)) |val, i| {
                // When generating the checksum, the checksum field
                // is interpreted as full of spaces to not fudge things up.
                checksum += if (i >= offset and i < offset + @sizeOf(@TypeOf(self.checksum)))
                    ' '
                else
                    val;
            }

            _ = try std.fmt.bufPrint(buf, "{o:0>6}", .{checksum});
            buf[6] = 0;
            buf[7] = ' ';
        }

        pub fn verifyChecksum(self: *Data) bool {
            var checksum_buf: [8]u8 = undefined;
            try self.calculateChecksum(&checksum_buf);
            return @bitCast(u64, checksum_buf) == @bitCast(u64, self.checksum);
        }
    };

    filename: [255]u8,

    mode: u21,
    uid: u21,
    gid: u21,
    size: u33,
    last_modified: u33,

    checksum: [8]u8,
    type_flag: FileTypeFlag,
    version: [2]u8, // "00"

    owner_user_name: [31]u8,
    owner_group_name: [31]u8,
    devmajor: u21,
    devminor: u21,

    data_offset: u64,

    // This SIMD hack saves ~7ms on ~10,000 file tars on my machine
    const Processor = simd.OctalGroupParser(usize, struct {
        mode: [7]u8,
        uid: [7]u8,
        gid: [7]u8,
        size: [11]u8,
        last_modified: [11]u8,
    });

    pub fn parse(self: *TarEntry, parser: *Parser, offset: *u64) !void {
        var data = try parser.reader.readStruct(Data);
        self.data_offset = offset.* + 512;

        data.getFilename(&self.filename);

        var out = Processor.process(.{
            .mode = data.mode,
            .uid = data.uid,
            .gid = data.gid,
            .size = data.size,
            .last_modified = data.mtime,
        });

        self.mode = @intCast(u21, out.mode);
        self.uid = @intCast(u21, out.uid);
        self.gid = @intCast(u21, out.gid);
        self.size = @intCast(u33, ((out.size + 511) / 512) * 512);
        self.last_modified = @intCast(u33, out.last_modified);

        // self.mode = @intCast(u21, try data.getNumeric(usize, "mode"));
        // self.uid = @intCast(u21, try data.getNumeric(usize, "uid"));
        // self.gid = @intCast(u21, try data.getNumeric(usize, "gid"));
        // self.size = try data.getSize();
        // self.last_modified = @intCast(u33, try data.getNumeric(usize, "mtime"));

        self.checksum = data.checksum;
        self.type_flag = data.type_flag;
        self.version = data.version;

        self.owner_user_name = data.uname;
        self.owner_group_name = data.gname;
        self.devmajor = if (data.devmajor[0] == 0) 0 else @intCast(u21, try data.getNumeric(usize, "devmajor"));
        self.devminor = if (data.devminor[0] == 0) 0 else @intCast(u21, try data.getNumeric(usize, "devminor"));

        offset.* += @intCast(u64, self.size) + 512;
        try parser.file.seekTo(offset.*);
    }
};

const PreloadPass = struct {
    parser: *Parser,
    entry_count: usize = 0,

    fn preload(self: *PreloadPass) !void {
        while (true) {
            var data = try self.parser.reader.readStruct(TarEntry.Data);

            if (@enumToInt(data.type_flag) == 0) return;

            var size = try data.getSize();
            try self.parser.file.seekBy(@intCast(i64, size));

            self.entry_count += 1;
        }
    }
};

pub const Parser = struct {
    allocator: *std.mem.Allocator,

    file: std.fs.File,
    reader: std.fs.File.Reader,

    entries: std.ArrayListUnmanaged(TarEntry) = .{},

    pub fn init(allocator: *std.mem.Allocator, file: std.fs.File) Parser {
        return .{
            .allocator = allocator,

            .file = file,
            .reader = file.reader(),
        };
    }

    /// Loads a tar file.
    /// The best solution for loading with our file-tree system in mind seems to be a two-pass one:
    /// - On the first (PreloadPass) pass, count the number of entries and total length of filenames so we can pre-allocate them
    /// - On the second (LoadPass) pass, we can actually store things in our entries ArrayList
    pub fn load(self: *Parser) !void {
        var preload_pass = PreloadPass{ .parser = self };
        try preload_pass.preload();

        try self.entries.ensureTotalCapacity(self.allocator, preload_pass.entry_count);

        try self.file.seekTo(0);

        var offset: u64 = 0;
        var index: usize = 0;

        while (index < preload_pass.entry_count) : (index += 1) {
            var entry = self.entries.addOneAssumeCapacity();
            try entry.parse(self, &offset);
        }
    }

    pub fn deinit(self: *Parser) void {
        self.entries.deinit(self.allocator);
    }
};
