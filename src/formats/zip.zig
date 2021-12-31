const std = @import("std");

const utils = @import("../utils.zig");

pub const CompressionMethod = enum(u16) {
    none = 0,
    shrunk,
    reduced1,
    reduced2,
    reduced3,
    reduced4,
    imploded,
    deflated = 8,
    enhanced_deflated,
    dcl_imploded,
    bzip2 = 12,
    lzma = 14,
    ibm_terse = 18,
    ibm_lz77_z,
    zstd_deprecated,
    zstd = 93,
    mp3,
    xz,
    jepg,
    wavpack,
    ppmd_1_1,
    aex_encryption,

    pub fn read(self: *CompressionMethod, reader: anytype) !void {
        const data = try reader.readIntLittle(u16);

        self.* = @intToEnum(CompressionMethod, data);
    }

    pub fn write(self: CompressionMethod, writer: anytype) !void {
        const data = @enumToInt(self);

        try writer.writeIntLittle(u16, data);
    }
};

pub const Version = struct {
    pub const Vendor = enum(u8) {
        dos = 0,
        amiga,
        openvms,
        unix,
        vm,
        atari,
        os2_hpfs,
        macintosh,
        z_system,
        cp_m,
        ntfs,
        mvs,
        vse,
        acorn,
        vfat,
        alt_mvs,
        beos,
        tandem,
        os400,
        osx,
        _,
    };

    vendor: Vendor,
    major: u8,
    minor: u8,

    pub fn read(self: *Version, reader: anytype) !void {
        const data = try reader.readIntLittle(u16);

        self.major = @truncate(u8, data) / 10;
        self.minor = @truncate(u8, data) % 10;
        self.vendor = @intToEnum(Vendor, @truncate(u8, data >> 8));
    }

    pub fn write(self: Version, writer: anytype) !void {
        const version = @as(u16, self.major * 10 + self.minor);
        const vendor = @as(u16, @enumToInt(self.vendor)) << 8;
        try writer.writeIntLittle(u16, version | vendor);
    }
};

pub const GeneralPurposeBitFlag = packed struct {
    encrypted: bool,
    compression1: u1,
    compression2: u1,
    data_descriptor: bool,
    enhanced_deflation: u1,
    compressed_patched: bool,
    strong_encryption: bool,
    __7_reserved: u1,
    __8_reserved: u1,
    __9_reserved: u1,
    __10_reserved: u1,
    is_utf8: bool,
    __12_reserved: u1,
    mask_headers: bool,
    __14_reserved: u1,
    __15_reserved: u1,

    pub fn read(self: *GeneralPurposeBitFlag, reader: anytype) !void {
        const data = try reader.readIntLittle(u16);

        self.* = @bitCast(GeneralPurposeBitFlag, data);
    }

    pub fn write(self: GeneralPurposeBitFlag, writer: anytype) !void {
        const data = @bitCast(u16, self);

        try writer.writeIntLittle(u16, data);
    }
};

pub const InternalAttributes = packed struct {
    apparent_text: bool,
    __1_reserved: u1,
    control_before_logical: bool,
    __3_7_reserved: u5,
    __8_15_reserved: u8,

    pub fn read(self: *InternalAttributes, reader: anytype) !void {
        const data = try reader.readIntLittle(u16);

        self.* = @bitCast(GeneralPurposeBitFlag, data);
    }

    pub fn write(self: InternalAttributes, writer: anytype) !void {
        const data = @bitCast(u16, self);

        try writer.writeIntLittle(u16, data);
    }
};

pub const DosTimestamp = struct {
    second: u6,
    minute: u6,
    hour: u5,
    day: u5,
    month: u4,
    year: u12,

    pub fn read(self: *DosTimestamp, reader: anytype) !void {
        const time = try reader.readIntLittle(u16);

        self.second = @as(u6, @truncate(u5, time)) << 1;
        self.minute = @truncate(u6, time >> 5);
        self.hour = @truncate(u5, time >> 11);

        const date = try reader.readIntLittle(u16);

        self.day = @truncate(u5, date);
        self.month = @truncate(u4, date >> 5);
        self.year = @as(u12, @truncate(u7, date >> 9)) + 1980;
    }

    pub fn write(self: DosTimestamp, writer: anytype) !void {
        const second = @as(u16, @truncate(u5, self.second >> 1));
        const minute = @as(u16, @truncate(u5, self.minute) << 5);
        const hour = @as(u16, @truncate(u5, self.hour) << 11);

        try writer.writeIntLittle(u16, second | minute | hour);

        const day = self.day;
        const month = self.month << 5;
        const year = (self.year - 1980) << 11;

        try writer.writeIntLittle(u16, day | month | year);
    }
};

pub const LocalFileHeader = struct {
    pub const Signature = 0x04034b50;
    pub const size = 26;

    version_needed: Version,
    flags: GeneralPurposeBitFlag,
    compression: CompressionMethod,
    mtime: DosTimestamp,

    checksum: u32,
    compressed_size: u64,
    uncompressed_size: u64,

    filename_len: u16,
    extrafield_len: u16,

    central_header: *const CentralDirectoryHeader,
    data_descriptor: ?DataDescriptor,

    offset: usize,

    const ReadError = error{ MalformedLocalFileHeader, MultidiskUnsupported };
    pub fn read(self: *LocalFileHeader, central_header: *const CentralDirectoryHeader, seeker: anytype, reader: anytype) !void {
        const Seek = Seeker(@TypeOf(seeker));

        try self.version_needed.read(reader);
        try self.flags.read(reader);
        try self.compression.read(reader);
        try self.mtime.read(reader);

        self.checksum = try reader.readIntLittle(u32);
        self.compressed_size = try reader.readIntLittle(u32);
        self.uncompressed_size = try reader.readIntLittle(u32);

        self.filename_len = try reader.readIntLittle(u16);
        self.extrafield_len = try reader.readIntLittle(u16);

        self.offset = central_header.offset + 30 + self.filename_len + self.extrafield_len;

        self.central_header = central_header;

        if (self.filename_len != central_header.filename_len) return error.MalformedLocalFileHeader;
        try Seek.seekBy(seeker, reader.context, @intCast(i64, self.filename_len));

        var is_zip64 = false;
        var extra_read: u32 = 0;

        const needs_uncompressed_size = self.uncompressed_size == 0xFFFFFFFF;
        const needs_compressed_size = self.compressed_size == 0xFFFFFFFF;

        const required_zip64_size = (@as(u5, @boolToInt(needs_uncompressed_size)) + @as(u5, @boolToInt(needs_compressed_size))) * 8;

        while (extra_read < self.extrafield_len) {
            const field_id = try reader.readIntLittle(u16);
            const field_size = try reader.readIntLittle(u16);
            extra_read += 4;

            if (field_id == 0x0001) {
                if (field_size < required_zip64_size) return error.MalformedExtraField;
                if (needs_uncompressed_size) self.uncompressed_size = try reader.readIntLittle(u64);
                if (needs_compressed_size) self.compressed_size = try reader.readIntLittle(u64);

                extra_read += required_zip64_size;

                try Seek.seekBy(seeker, reader.context, field_size - required_zip64_size);

                break;
            } else {
                try Seek.seekBy(seeker, reader.context, field_size);

                extra_read += field_size;
            }
        }

        const left = self.extrafield_len - extra_read;

        if (self.flags.data_descriptor) {
            try Seek.seekBy(seeker, reader.context, @intCast(i64, left + self.compressed_size));

            self.data_descriptor = @as(DataDescriptor, undefined);
            try self.data_descriptor.?.read(reader, is_zip64);
        }
    }
};

pub const DataDescriptor = struct {
    pub const Signature = 0x04034b50;
    pub const size = 12;

    checksum: u64,
    compressed_size: u64,
    uncompressed_size: u64,

    pub fn read(self: *DataDescriptor, reader: anytype, zip64: bool) !void {
        const signature = try reader.readIntLittle(u32);
        if (signature == DataDescriptor.Signature) {
            if (zip64) {
                self.checksum = try reader.readIntLittle(u64);
                self.compressed_size = try reader.readIntLittle(u64);
                self.uncompressed_size = try reader.readIntLittle(u64);
            } else {
                self.checksum = try reader.readIntLittle(u32);
                self.compressed_size = try reader.readIntLittle(u32);
                self.uncompressed_size = try reader.readIntLittle(u32);
            }
        } else {
            if (zip64) {
                const next_u32 = try reader.readIntLittle(u32);
                self.checksum = @as(u64, next_u32) << 32 | signature;
                self.compressed_size = try reader.readIntLittle(u64);
                self.uncompressed_size = try reader.readIntLittle(u64);
            } else {
                self.checksum = signature;
                self.compressed_size = try reader.readIntLittle(u32);
                self.uncompressed_size = try reader.readIntLittle(u32);
            }
        }
    }
};

pub const CentralDirectoryHeader = struct {
    pub const Signature = 0x02014b50;
    pub const size = 42;

    version_made: Version,
    version_needed: Version,
    flags: GeneralPurposeBitFlag,
    compression: CompressionMethod,

    mtime: DosTimestamp,

    checksum: u32,
    compressed_size: u64,
    uncompressed_size: u64,

    disk_start: u16,
    internal_attributes: InternalAttributes,
    external_attributes: u32,
    offset: u64,

    filename_len: u16,
    extrafield_len: u16,
    file_comment_len: u16,

    filename: []const u8,

    local_header: LocalFileHeader,

    pub fn readInitial(self: *CentralDirectoryHeader, reader: anytype) !void {
        try self.version_made.read(reader);
        try self.version_needed.read(reader);
        try self.flags.read(reader);
        try self.compression.read(reader);
        try self.mtime.read(reader);

        self.checksum = try reader.readIntLittle(u32);
        self.compressed_size = try reader.readIntLittle(u32);
        self.uncompressed_size = try reader.readIntLittle(u32);

        self.filename_len = try reader.readIntLittle(u16);
        self.extrafield_len = try reader.readIntLittle(u16);
        self.file_comment_len = try reader.readIntLittle(u16);

        self.disk_start = try reader.readIntLittle(u16);
        try self.internal_attributes.read(reader);
        self.external_attributes = try reader.readIntLittle(u32);
        self.offset = try reader.readIntLittle(u32);
    }

    const ReadSecondaryError = error{MalformedExtraField};
    pub fn readSecondary(self: *CentralDirectoryHeader, seeker: anytype, reader: anytype) !void {
        const Seek = Seeker(@TypeOf(seeker));

        const needs_uncompressed_size = self.uncompressed_size == 0xFFFFFFFF;
        const needs_compressed_size = self.compressed_size == 0xFFFFFFFF;
        const needs_header_offset = self.offset == 0xFFFFFFFF;

        const required_zip64_size = (@as(u5, @boolToInt(needs_uncompressed_size)) + @as(u5, @boolToInt(needs_compressed_size)) + @as(u5, @boolToInt(needs_header_offset))) * 8;
        const needs_zip64 = needs_uncompressed_size or needs_compressed_size or needs_header_offset;

        if (needs_zip64) {
            var read: usize = 0;

            while (read < self.extrafield_len) {
                const field_id = try reader.readIntLittle(u16);
                const field_size = try reader.readIntLittle(u16);
                read += 4;

                if (field_id == 0x0001) {
                    if (field_size < required_zip64_size) return error.MalformedExtraField;
                    if (needs_uncompressed_size) self.uncompressed_size = try reader.readIntLittle(u64);
                    if (needs_compressed_size) self.compressed_size = try reader.readIntLittle(u64);
                    if (needs_header_offset) self.offset = try reader.readIntLittle(u64);

                    read += required_zip64_size;

                    break;
                } else {
                    try Seek.seekBy(seeker, reader.context, field_size);

                    read += field_size;
                }
            }

            const left = self.extrafield_len - read;

            try Seek.seekBy(seeker, reader.context, @intCast(i64, self.file_comment_len + left));
        } else {
            try Seek.seekBy(seeker, reader.context, @intCast(i64, self.extrafield_len + self.file_comment_len));
        }
    }
};

pub const EndCentralDirectory64Record = struct {
    pub const Signature = 0x06064b50;
    pub const size = 52;

    record_size: u64,

    version_made: Version,
    version_needed: Version,

    disk_number: u32,
    disk_start_directory: u32,
    disk_directory_entries: u64,

    directory_entry_count: u64,
    directory_size: u64,
    directory_offset: u64,

    pub fn parse(self: *EndCentralDirectory64Record, reader: anytype) (@TypeOf(reader).Error || error{EndOfStream})!void {
        self.record_size = try reader.readIntLittle(u64);

        try self.version_made.read(reader);
        try self.version_needed.read(reader);

        self.disk_number = try reader.readIntLittle(u32);
        self.disk_start_directory = try reader.readIntLittle(u32);
        self.disk_directory_entries = try reader.readIntLittle(u64);

        self.directory_entry_count = try reader.readIntLittle(u64);
        self.directory_size = try reader.readIntLittle(u64);
        self.directory_offset = try reader.readIntLittle(u64);
    }
};

pub const EndCentralDirectory64Locator = struct {
    pub const Signature = 0x07064b50;
    pub const size = 16;

    directory_disk_number: u32,
    directory_offset: u64,
    number_of_disks: u32,

    pub fn parse(self: *EndCentralDirectory64Locator, reader: anytype) (@TypeOf(reader).Error || error{EndOfStream})!void {
        self.directory_disk_number = try reader.readIntLittle(u32);
        self.directory_offset = try reader.readIntLittle(u64);
        self.number_of_disks = try reader.readIntLittle(u32);
    }
};

pub const EndCentralDirectoryRecord = struct {
    pub const Signature = 0x06054b50;
    pub const size = 18;

    disk_number: u16,
    disk_start_directory: u16,
    disk_directory_entries: u16,

    directory_entry_count: u16,
    directory_size: u32,
    directory_offset: u32,

    comment_length: u16,

    pub fn parse(self: *EndCentralDirectoryRecord, reader: anytype) (@TypeOf(reader).Error || error{EndOfStream})!void {
        self.disk_number = try reader.readIntLittle(u16);
        self.disk_start_directory = try reader.readIntLittle(u16);
        self.disk_directory_entries = try reader.readIntLittle(u16);

        self.directory_entry_count = try reader.readIntLittle(u16);
        self.directory_size = try reader.readIntLittle(u32);
        self.directory_offset = try reader.readIntLittle(u32);

        self.comment_length = try reader.readIntLittle(u16);
    }
};

/// Finds and read's the ZIP central directory and local headers.
pub fn LoadError(comptime Reader: type) type {
    return ReadInfoError(Reader) || ReadDirectoryError(Reader);
}
pub fn load(allocator: std.mem.Allocator, reader: anytype) LoadError(@TypeOf(reader))!Directory {
    const info = try readInfo(reader);
    return try readDirectory(allocator, reader, info);
}

pub const Info = struct {
    is_zip64: bool,
    ecd: EndCentralDirectoryRecord,
    ecd64: EndCentralDirectory64Record,
    start_offset: u64,
    directory_offset: u64,
    num_entries: u32,
};
pub fn ReadInfoError(comptime Reader: type) type {
    return Reader.Error || Seeker(Reader).Context.SeekError || error{ EndOfStream, FileTooSmall, InvalidZip, InvalidZip64Locator, MultidiskUnsupported, TooManyFiles };
}

        // TODO: remove the extra indentation (left like this for better diff)
        pub fn readInfo(reader: anytype) ReadInfoError(@TypeOf(reader))!Info {
            const file_length = try reader.context.getEndPos();
            const minimum_ecdr_offset: u64 = EndCentralDirectoryRecord.size + 4;
            const maximum_ecdr_offset: u64 = EndCentralDirectoryRecord.size + 4 + 0xffff;

            if (file_length < minimum_ecdr_offset) return error.FileTooSmall;

            // Find the ECDR signature with a broad pass.
            var pos = file_length - minimum_ecdr_offset;
            var last_pos = if (maximum_ecdr_offset > file_length) file_length else file_length - maximum_ecdr_offset;
            var buffer: [4096]u8 = undefined;

            find: while (pos > 0) {
                try reader.context.seekTo(pos);

                const read = try reader.readAll(&buffer);
                if (read == 0) return error.InvalidZip;

                var i: usize = 0;
                while (i < read - 4) : (i += 1) {
                    if (std.mem.readIntLittle(u32, buffer[i..][0..4]) == EndCentralDirectoryRecord.Signature) {
                        pos = pos + i;
                        try reader.context.seekTo(pos + 4);

                        break :find;
                    }
                }

                if (pos < 4096 or pos < last_pos) return error.InvalidZip;
                pos -= 4096;
            }

            var self: Info = undefined;
            try self.ecd.parse(reader);

            if (pos > EndCentralDirectory64Locator.size + EndCentralDirectory64Record.size + 8) {
                const locator_pos = pos - EndCentralDirectory64Locator.size - 4;
                try reader.context.seekTo(locator_pos);

                var locator: EndCentralDirectory64Locator = undefined;

                const locator_sig = try reader.readIntLittle(u32);
                if (locator_sig == EndCentralDirectory64Locator.Signature) {
                    try locator.parse(reader);

                    if (locator.directory_offset > file_length - EndCentralDirectory64Record.size - 4) return error.InvalidZip64Locator;

                    try reader.context.seekTo(locator.directory_offset);

                    const ecd64_sig = try reader.readIntLittle(u32);
                    if (ecd64_sig == EndCentralDirectory64Record.Signature) {
                        try self.ecd64.parse(reader);

                        self.is_zip64 = true;
                    }
                }
            }

            self.num_entries = self.ecd.directory_entry_count;
            self.directory_offset = self.ecd.directory_offset;
            var directory_size: u64 = self.ecd.directory_size;

            if (self.ecd.disk_number != self.ecd.disk_start_directory) return error.MultidiskUnsupported;
            if (self.ecd.disk_directory_entries != self.ecd.directory_entry_count) return error.MultidiskUnsupported;

            // Sanity checks
            if (self.is_zip64) {
                if (self.ecd64.disk_number != self.ecd64.disk_start_directory) return error.MultidiskUnsupported;
                if (self.ecd64.disk_directory_entries != self.ecd64.directory_entry_count) return error.MultidiskUnsupported;

                if (self.ecd64.directory_entry_count > std.math.maxInt(u32)) return error.TooManyFiles;
                self.num_entries = @truncate(u32, self.ecd64.directory_entry_count);

                self.directory_offset = self.ecd64.directory_offset;
                directory_size = self.ecd64.directory_size;
            }

            // Gets the start of the actual ZIP.
            // This is required because ZIPs can have preambles for self-execution, for example
            // so they could actually start anywhere in the file.
            self.start_offset = pos - self.ecd.directory_size - self.directory_offset;
            return self;
        }

        // TODO: remove the extra indentation (left like this for better diff)
        fn centralHeaderLessThan(_: void, lhs: CentralDirectoryHeader, rhs: CentralDirectoryHeader) bool {
            return lhs.offset < rhs.offset;
        }

        // TODO: remove the extra indentation (left like this for better diff)
        pub fn ReadDirectoryError(comptime Reader: type) type {
            return std.mem.Allocator.Error || Reader.Error || Seeker(Reader).Context.SeekError || CentralDirectoryHeader.ReadSecondaryError || error{ EndOfStream, MalformedCentralDirectoryHeader, MultidiskUnsupported, MalformedLocalFileHeader };
        }
        pub fn readDirectory(allocator: std.mem.Allocator, reader: anytype, info: Info) ReadDirectoryError(@TypeOf(reader))!Directory {
            const Seek = Seeker(@TypeOf(reader));

            var headers = try std.ArrayListUnmanaged(CentralDirectoryHeader).initCapacity(allocator, info.num_entries);
            errdefer headers.deinit(allocator);

            var index: u32 = 0;
            try reader.context.seekTo(info.start_offset + info.directory_offset);

            var buffered = Seek.BufferedReader{ .unbuffered_reader = reader };
            const buffered_reader = buffered.reader();

            var filename_len_total: usize = 0;
            while (index < info.num_entries) : (index += 1) {
                const sig = try buffered_reader.readIntLittle(u32);
                if (sig != CentralDirectoryHeader.Signature) return error.MalformedCentralDirectoryHeader;

                var hdr = headers.addOneAssumeCapacity();
                try hdr.readInitial(buffered_reader);
                if (hdr.disk_start != info.ecd.disk_number) return error.MultidiskUnsupported;
                try Seek.seekBy(reader, buffered_reader.context, @intCast(i64, hdr.filename_len + hdr.extrafield_len + hdr.file_comment_len));

                filename_len_total += hdr.filename_len;
            }

            var filename_buffer = try std.ArrayListUnmanaged(u8).initCapacity(allocator, filename_len_total);
            errdefer filename_buffer.deinit(allocator);

            try Seek.seekTo(reader, buffered_reader.context, info.start_offset + info.directory_offset);

            for (headers.items) |*hdr| {
                try Seek.seekBy(reader, buffered_reader.context, 46);
                hdr.filename = try readFilename(&filename_buffer, buffered_reader, hdr.filename_len);
                try hdr.readSecondary(reader, buffered_reader);
            }

            std.sort.sort(CentralDirectoryHeader, headers.items, {}, centralHeaderLessThan);

            for (headers.items) |*hdr| {
                try Seek.seekTo(reader, buffered_reader.context, info.start_offset + hdr.offset);
                const signature = try buffered_reader.readIntLittle(u32);
                if (signature != LocalFileHeader.Signature) return error.MalformedLocalFileHeader;
                try hdr.local_header.read(hdr, reader, buffered_reader);
            }

            return Directory {
                .start_offset = info.start_offset,
                .headers = headers.toOwnedSlice(allocator),
                .filename_buffer = filename_buffer.toOwnedSlice(allocator),
            };
        }

pub const Directory = struct {
    start_offset: u64,
    headers: []CentralDirectoryHeader,
    filename_buffer: []u8,

    pub fn deinit(self: Directory, allocator: std.mem.Allocator) void {
        allocator.free(self.headers);
        allocator.free(self.filename_buffer);
    }

        // TODO: remove the extra indentation (left like this for better diff)
        pub fn getFileIndex(self: Directory, filename: []const u8) !usize {
            for (self.directory.items) |*hdr, i| {
                if (std.mem.eql(u8, hdr.filename, filename)) {
                    return i;
                }
            }

            return error.FileNotFound;
        }

        pub fn readFileAlloc(self: Directory, reader: anytype, allocator: std.mem.Allocator, index: usize) ![]const u8 {
            const Seek = Seeker(@TypeOf(reader));
            const header = self.headers.items[index];

            reader.context.seekTo(self.start_offset + header.local_header.offset);

            var buffer = try allocator.alloc(u8, header.uncompressed_size);
            errdefer allocator.free(buffer);

            var read_buffered = Seek.BufferedReader{ .unbuffered_reader = reader };
            var limited = utils.LimitedReader(Seek.BufferedReader.Reader).init(read_buffered.reader(), header.compressed_size);
            const limited_reader = limited.reader();

            var write_stream = std.io.fixedBufferStream(buffer);
            const writer = write_stream.writer();

            var fifo = std.fifo.LinearFifo(u8, .{ .Static = 8192 }).init();

            switch (header.compression) {
                .none => {
                    try fifo.pump(limited_reader, writer);
                },
                .deflated => {
                    var window: [0x8000]u8 = undefined;
                    var stream = std.compress.deflate.inflateStream(limited_reader, &window);

                    try fifo.pump(stream.reader(), writer);
                },
                else => return error.CompressionUnsupported,
            }

            return buffer;
        }

        pub const ExtractOptions = struct {
            skip_components: u16 = 0,
        };

        pub fn extract(self: Directory, reader: anytype, dir: std.fs.Dir, options: ExtractOptions) !usize {
            const Seek = Seeker(@TypeOf(reader));

            var buffered = Seek.BufferedReader{ .unbuffered_reader = reader };
            const file_reader = buffered.reader();

            var written: usize = 0;

            extract: for (self.headers) |hdr| {
                const new_filename = blk: {
                    var component: usize = 0;
                    var last_pos: usize = 0;
                    while (component < options.skip_components) : (component += 1) {
                        last_pos = std.mem.indexOfPos(u8, hdr.filename, last_pos, "/") orelse continue :extract;
                    }

                    if (last_pos + 1 == hdr.filename_len) continue :extract;

                    break :blk if (hdr.filename[last_pos] == '/') hdr.filename[last_pos + 1 ..] else hdr.filename[last_pos..];
                };

                if (std.fs.path.dirnamePosix(new_filename)) |dirname| {
                    try dir.makePath(dirname);
                }

                if (new_filename[new_filename.len - 1] == '/') continue;

                const fd = try dir.createFile(new_filename, .{});
                defer fd.close();

                try Seek.seekTo(reader, file_reader.context, self.start_offset + hdr.local_header.offset);

                var limited = utils.LimitedReader(Seek.BufferedReader.Reader).init(file_reader, hdr.compressed_size);
                const limited_reader = limited.reader();

                var fifo = std.fifo.LinearFifo(u8, .{ .Static = 8192 }).init();

                written += hdr.uncompressed_size;

                switch (hdr.compression) {
                    .none => {
                        try fifo.pump(limited_reader, fd.writer());
                    },
                    .deflated => {
                        var window: [0x8000]u8 = undefined;
                        var stream = std.compress.deflate.inflateStream(limited_reader, &window);

                        try fifo.pump(stream.reader(), fd.writer());
                    },
                    else => return error.CompressionUnsupported,
                }
            }

            return written;
        }

        /// Returns a file tree of this ZIP archive.
        /// Useful for plucking specific files out of a ZIP or listing it's contents.
        pub fn getFileTree(self: Directory, allocator: std.mem.Allocator) !FileTree {
            var tree = FileTree{};
            try tree.entries.ensureTotalCapacity(allocator, @intCast(u32, self.headers.len));
            errdefer tree.entries.deinit(allocator);

            for (self.headers) |*hdr| {
                try tree.appendFile(allocator, hdr);
            }

            return tree;
        }
};

        // TODO: remove the extra indentation (left like this for better diff)
        fn readFilename(filename_buffer: *std.ArrayListUnmanaged(u8), reader: anytype, len: usize) ![]const u8 {
            const prev_len = filename_buffer.items.len;
            filename_buffer.items.len += len;

            var buf = filename_buffer.items[prev_len..][0..len];
            const read = try reader.readAll(buf);
            if (read != len) return error.EndOfStream;

            return buf;
        }

fn Seeker(comptime Reader: type) type {
    return struct {
        pub const Context = std.meta.fieldInfo(Reader, .context).field_type;
        comptime {
            const is_seekable = @hasDecl(Context, "seekBy") and @hasDecl(Context, "seekTo") and @hasDecl(Context, "getEndPos");
            if (!is_seekable) @compileError("Reader must wrap a seekable context");
        }
        pub const BufferedReader = std.io.BufferedReader(8192, Reader);

        pub fn seekBy(reader: Reader, buffered: *BufferedReader, offset: i64) !void {
            if (offset == 0) return;

            if (offset > 0) {
                const u_offset = @intCast(u64, offset);

                if (u_offset <= buffered.fifo.count) {
                    buffered.fifo.discard(u_offset);
                } else if (u_offset <= buffered.fifo.count + buffered.fifo.buf.len) {
                    const left = u_offset - buffered.fifo.count;

                    buffered.fifo.discard(buffered.fifo.count);
                    try buffered.reader().skipBytes(left, .{ .buf_size = 8192 });
                } else {
                    const left = u_offset - buffered.fifo.count;

                    buffered.fifo.discard(buffered.fifo.count);
                    try reader.context.seekBy(@intCast(i64, left));
                }
            } else {
                const left = offset - @intCast(i64, buffered.fifo.count);

                buffered.fifo.discard(buffered.fifo.count);
                try reader.context.seekBy(left);
            }
        }

        pub fn getPos(reader: Reader, buffered: *BufferedReader) !u64 {
            const pos = try reader.context.getPos();

            return pos - buffered.fifo.count;
        }

        pub fn seekTo(reader: Reader, buffered: *BufferedReader, pos: u64) !void {
            const offset = @intCast(i64, pos) - @intCast(i64, try getPos(reader, buffered));

            try seekBy(reader, buffered, offset);
        }
    };
}

// High-level constructs

pub const FileTree = struct {
    entries: std.StringHashMapUnmanaged(*const CentralDirectoryHeader) = .{},
    structure: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(*const CentralDirectoryHeader)) = .{},

    pub fn appendFile(self: *FileTree, allocator: std.mem.Allocator, hdr: *const CentralDirectoryHeader) !void {
        // Determines the end of filename. If the filename is a directory, skip the last character as it is an extraenous `/`, else do nothing.
        var filename_end_index = hdr.filename.len - if (hdr.filename[hdr.filename.len - 1] == '/') @as(usize, 1) else @as(usize, 0);
        var start = if (std.mem.lastIndexOf(u8, hdr.filename[0..filename_end_index], "/")) |ind|
            hdr.filename[0..ind]
        else
            "/";

        var gpr = try self.structure.getOrPut(allocator, start);
        if (!gpr.found_existing)
            gpr.value_ptr.* = std.ArrayListUnmanaged(*const CentralDirectoryHeader){};
        try gpr.value_ptr.append(allocator, hdr);

        try self.entries.put(allocator, hdr.filename, hdr);
    }

    pub fn deinit(self: *FileTree, allocator: std.mem.Allocator) void {
        self.entries.deinit(allocator);

        var it = self.structure.valueIterator();
        while (it.next()) |entry| {
            entry.deinit(allocator);
        }

        self.structure.deinit(allocator);
    }

    pub fn readDir(self: FileTree, path: []const u8) ?*std.ArrayListUnmanaged(*const CentralDirectoryHeader) {
        return if (self.structure.getEntry(path)) |ent| ent.value_ptr else null;
    }

    pub fn getEntry(self: FileTree, path: []const u8) ?*const CentralDirectoryHeader {
        return self.entries.get(path);
    }
};

comptime {
    std.testing.refAllDecls(@This());
}
