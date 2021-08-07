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
    ppmd_1_1 = 98,
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

    pub fn cast(n: u16) Version {
        return .{
            .vendor = @intToEnum(Vendor, @truncate(u8, n >> 8)),
            .major = @truncate(u8, n) / 10,
            .minor = @truncate(u8, n) % 10,
        };
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
};

pub const InternalAttributes = packed struct {
    apparent_text: bool,
    __1_reserved: u1,
    control_before_logical: bool,
    __3_7_reserved: u5,
    __8_15_reserved: u8,
};

pub const ModificationTime = struct {
    second: u8,
    minute: u8,
    hour: u8,

    pub fn cast(n: u16) ModificationTime {
        return .{
            .second = @as(u8, @truncate(u5, n)) * 2,
            .minute = @truncate(u6, n >> 5),
            .hour = @truncate(u5, n >> 11),
        };
    }
};

pub const ModificationDate = struct {
    day: u8,
    month: u8,
    year: u16,

    pub fn cast(n: u16) ModificationDate {
        return .{
            .day = @truncate(u5, n),
            .month = @truncate(u4, n >> 5),
            .year = @as(u16, @truncate(u7, n >> 9)) + 1980,
        };
    }
};

pub const LocalFileHeader = struct {
    pub const Signature = 0x04034b50;
    pub const Data = struct {
        pub const size = 26;

        version_needed: Version,
        bit_flag: GeneralPurposeBitFlag,
        compression_method: CompressionMethod,

        last_mod_time: ModificationTime,
        last_mod_date: ModificationDate,

        checksum: u32,
        compressed_size: u32,
        uncompressed_size: u32,

        filename_len: u16,
        extrafield_len: u16,
    };

    data: Data,

    central_header: *const CentralDirectoryHeader,

    pub fn parse(self: *LocalFileHeader, central_header: *const CentralDirectoryHeader, parser: *Parser, reader: anytype) !void {
        self.central_header = central_header;

        const read = try utils.readStruct(Data, &self.data, reader, Data.size);
        const seek = self.data.filename_len + self.data.extrafield_len;

        try parser.file.seekBy(seek);

        return read + seek;
    }
};

pub const DataDescriptor = struct {
    pub const Signature = 0x04034b50;
    pub const Data = struct {
        pub const size = 12;

        checksum: u32,
        compressed_size: u32,
        uncompressed_size: u32,
    };

    data: Data,

    pub fn parse(self: *DataDescriptor, parser: *Parser, reader: anytype) !usize {
        _ = parser;
        return utils.readStruct(Data, &self.data, reader, Data.size);
    }
};

pub const CentralDirectoryHeader = struct {
    pub const Signature = 0x02014b50;
    pub const Data = struct {
        pub const size = 42;

        version_made: Version,
        version_needed: Version,
        bit_flag: GeneralPurposeBitFlag,
        compression_method: CompressionMethod,

        last_mod_time: ModificationTime,
        last_mod_date: ModificationDate,

        checksum: u32,
        compressed_size: u32,
        uncompressed_size: u32,

        filename_len: u16,
        extrafield_len: u16,
        file_comment_len: u16,

        disk_start: u16,
        internal_attributes: u16,
        external_attributes: u32,

        data_offset: u32,
    };

    data: Data,

    compressed: u64 = 0,
    uncompressed: u64 = 0,
    offset: u64 = 0,

    filename: []const u8,
    extrafield: []const u8,
    file_comment: []const u8,

    local_header: ?LocalFileHeader,

    pub fn parse(self: *CentralDirectoryHeader, parser: *Parser, reader: anytype) !usize {
        const read = try utils.readStruct(Data, &self.data, reader, Data.size);
        const seek = self.data.filename_len + self.data.extrafield_len + self.data.file_comment_len;

        self.filename = try parser.readString(reader, self.data.filename_len);

        if (self.data.disk_start != 0 and self.data.disk_start != 1) return error.MultidiskUnsupported;

        self.compressed = self.data.compressed_size;
        self.uncompressed = self.data.uncompressed_size;
        self.offset = self.data.data_offset;

        var pos: usize = 0;
        while (pos < self.data.extrafield_len) {
            const tag = try reader.readIntLittle(u16);
            const size = try reader.readIntLittle(u16);

            if (tag == 0x0001) {
                if (size > 28) return error.InvalidZip;
                var field_read: u16 = 0;

                if (self.uncompressed == 0xFFFFFFFF) {
                    if (field_read + 8 > size) return error.InvalidZip;

                    self.uncompressed = try reader.readIntLittle(u64);
                    field_read += 8;
                }

                if (self.compressed == 0xFFFFFFFF) {
                    if (field_read + 8 > size) return error.InvalidZip;

                    self.compressed = try reader.readIntLittle(u64);
                    field_read += 8;
                }

                if (self.offset == 0xFFFFFFFF) {
                    if (field_read + 8 > size) return error.InvalidZip;

                    self.offset = try reader.readIntLittle(u64);
                    field_read += 8;
                }

                if (size - field_read > 0) {
                    try reader.skipBytes(size - field_read, .{});
                }
            } else {
                try reader.skipBytes(size, .{});
            }

            pos += 4 + size;
        }

        // self.extrafield = try parser.readString(reader, self.data.extrafield_len);
        self.file_comment = try parser.readString(reader, self.data.file_comment_len);

        return read + seek;
    }

    pub fn readLocalFileHeader(self: *const CentralDirectoryHeader) !*const LocalFileHeader {
        if (self.local_header) return &self.local_header;

        try self.parser.file.seekTo(self.parser.start_offset + self.data_offset + 4);

        self.local_header = undefined;
        self.local_header.?.parse(self, self.parser, self.reader);

        return &self.local_header;
    }
};

pub const EndCentralDirectory64Record = struct {
    pub const Signature = 0x06064b50;
    pub const Data = struct {
        pub const size = 52;

        size: u64,

        version_made: u16,
        version_needed: u16,

        disk_number: u32,
        disk_start_central_directory: u32,
        disk_count_directory_entries: u64,

        central_directory_entry_count: u64,
        central_directory_size: u64,
        central_directory_offset: u64,
    };

    data: Data,

    extensible_data_sector: []const u8,

    pub fn parse(self: *EndCentralDirectory64Record, parser: *Parser, reader: anytype) !usize {
        const read = try utils.readStruct(Data, &self.data, reader, Data.size);
        const seek = self.data.size - 44;

        self.extensible_data_sector = try parser.readString(reader, seek);

        return read + seek;
    }
};

pub const EndCentralDirectory64Locator = struct {
    pub const Signature = 0x07064b50;
    pub const Data = struct {
        pub const size = 16;

        disk_number: u32,
        ecd64_offset: u64,
        number_of_disks: u32,
    };

    data: Data,

    pub fn parse(self: *EndCentralDirectory64Locator, parser: *Parser, reader: anytype) !usize {
        _ = parser;
        return try utils.readStruct(Data, &self.data, reader, Data.size);
    }
};

pub const EndCentralDirectoryRecord = struct {
    pub const Signature = 0x06054b50;
    pub const Data = struct {
        pub const size = 18;

        disk_number: u16,
        disk_start_central_directory: u16,
        disk_count_directory_entries: u16,

        central_directory_entry_count: u16,
        central_directory_size: u32,
        central_directory_offset: u32,

        comment_length: u16,
    };

    parser: *Parser,
    location: usize,

    data: Data,

    comment: []const u8,

    pub fn parse(self: *EndCentralDirectoryRecord, parser: *Parser, reader: anytype) !usize {
        const read = try utils.readStruct(Data, &self.data, reader, Data.size);
        const seek = self.data.comment_length;

        self.comment = try parser.readString(reader, self.data.comment_length);

        return read + seek;
    }
};

pub const Parser = struct {
    allocator: *std.mem.Allocator,

    file: std.fs.File,
    reader: std.fs.File.Reader,

    start_offset: usize = 0,

    is_zip64: bool = false,
    zip_ecdr: EndCentralDirectoryRecord = undefined,
    zip64_ecdl: EndCentralDirectory64Locator = undefined,
    zip64_ecdr: EndCentralDirectory64Record = undefined,

    central_directory: std.ArrayListUnmanaged(CentralDirectoryHeader) = .{},
    file_headers: std.ArrayListUnmanaged(LocalFileHeader) = .{},
    string_buffer: std.ArrayListUnmanaged(u8) = .{},

    file_tree: FileTree = FileTree{},

    num_entries: u32 = 0,
    dir_size: u64 = 0,
    dir_offset: u64 = 0,

    pub fn init(allocator: *std.mem.Allocator, file: std.fs.File) Parser {
        return .{
            .allocator = allocator,

            .file = file,
            .reader = file.reader(),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.central_directory.deinit(self.allocator);
        self.file_headers.deinit(self.allocator);
        self.string_buffer.deinit(self.allocator);

        self.file_tree.deinit(self.allocator);
    }

    pub fn load(self: *Parser) !void {
        const end = try self.file.getEndPos();
        const start_offset: u64 = EndCentralDirectoryRecord.Data.size + 4;
        var offset = start_offset;

        while (offset < end and offset < 0xffff + start_offset) : (offset += 1) {
            try self.file.seekTo(end - offset);

            if ((try self.reader.readIntLittle(u32)) == EndCentralDirectoryRecord.Signature) break;
        }

        _ = try self.zip_ecdr.parse(self, self.reader);

        const pos = end - offset;

        if (pos > EndCentralDirectory64Locator.Data.size + EndCentralDirectory64Record.Data.size + 8) {
            const locator = pos - EndCentralDirectory64Locator.Data.size - 4;
            try self.file.seekTo(locator);

            const zip64_ecdl_sig = try self.reader.readIntLittle(u32);
            if (zip64_ecdl_sig == EndCentralDirectory64Locator.Signature) {
                _ = try self.zip64_ecdl.parse(self, self.reader);

                if (self.zip64_ecdl.data.ecd64_offset > end - EndCentralDirectory64Record.Data.size - 4) return error.InvalidZip;

                try self.file.seekTo(self.zip64_ecdl.data.ecd64_offset);

                const zip64_ecdr_sig = try self.reader.readIntLittle(u32);
                if (zip64_ecdr_sig == EndCentralDirectory64Record.Signature) {
                    _ = try self.zip64_ecdr.parse(self, self.reader);

                    self.is_zip64 = true;
                }
            }
        }

        self.num_entries = self.zip_ecdr.data.central_directory_entry_count;
        self.dir_size = self.zip_ecdr.data.central_directory_size;
        self.dir_offset = self.zip_ecdr.data.central_directory_offset;

        // Sanity checks
        if (self.is_zip64) {
            if (self.zip64_ecdr.data.disk_number != 0 and self.zip64_ecdr.data.disk_number != 1) return error.MultidiskUnsupported;
            if (self.zip64_ecdr.data.disk_start_central_directory != 0 and self.zip64_ecdr.data.disk_start_central_directory != 1) return error.MultidiskUnsupported;
            if (self.zip64_ecdr.data.disk_count_directory_entries != self.zip_ecdr.data.central_directory_entry_count) return error.MultidiskUnsupported;

            if (self.zip64_ecdr.data.central_directory_entry_count > std.math.maxInt(u32)) return error.TooManyFiles;
            self.num_entries = @truncate(u32, self.zip64_ecdr.data.central_directory_entry_count);

            self.dir_size = self.zip64_ecdr.data.central_directory_size;
            self.dir_offset = self.zip64_ecdr.data.central_directory_offset;
        } else {
            if (self.zip_ecdr.data.disk_number != 0 and self.zip_ecdr.data.disk_number != 1) return error.MultidiskUnsupported;
            if (self.zip_ecdr.data.disk_start_central_directory != 0 and self.zip_ecdr.data.disk_start_central_directory != 1) return error.MultidiskUnsupported;
            if (self.zip_ecdr.data.disk_count_directory_entries != self.zip_ecdr.data.central_directory_entry_count) return error.MultidiskUnsupported;
        }

        // Gets the start of the actual ZIP.
        // This is required because ZIPs can have preambles for self-execution, for example
        // so they could actually start anywhere in the file.
        self.start_offset = pos - self.zip_ecdr.data.central_directory_size - self.zip_ecdr.data.central_directory_offset;

        const string_space = self.dir_size - ((CentralDirectoryHeader.Data.size + 4) * self.num_entries);
        try self.string_buffer.ensureUnusedCapacity(self.allocator, string_space);

        try self.readCentralDirectory();
    }

    fn readString(self: *Parser, reader: anytype, len: usize) ![]const u8 {
        if (len == 0) return "";

        try self.string_buffer.ensureUnusedCapacity(self.allocator, len);
        const prev_len = self.string_buffer.items.len;
        self.string_buffer.items.len += len;

        var buf = self.string_buffer.items[prev_len..][0..len];
        _ = try reader.readAll(buf);

        return buf;
    }

    fn centralHeaderLessThan(_: void, lhs: CentralDirectoryHeader, rhs: CentralDirectoryHeader) bool {
        return lhs.data.data_offset < rhs.data.data_offset;
    }

    fn readCentralDirectory(self: *Parser) !void {
        try self.central_directory.ensureTotalCapacity(self.allocator, self.num_entries);

        var index: u32 = 0;
        var pos: usize = self.start_offset + self.dir_offset;
        try self.file.seekTo(pos);

        var buffered = std.io.BufferedReader(8192, std.fs.File.Reader){ .unbuffered_reader = self.reader };
        const reader = buffered.reader();

        try self.file_tree.entries.ensureCapacity(self.allocator, self.num_entries);

        while (index < self.num_entries) : (index += 1) {
            const sig = try reader.readIntLittle(u32);
            if (sig != CentralDirectoryHeader.Signature) return error.InvalidZip;
            pos += 4;

            var hdr = self.central_directory.addOneAssumeCapacity();
            pos += try hdr.parse(self, reader);
        }

        std.sort.sort(CentralDirectoryHeader, self.central_directory.items, {}, centralHeaderLessThan);

        for (self.central_directory.items) |*hdr| {
            try self.file_tree.appendFile(self.allocator, hdr);
        }
    }
};

// High-level constructs

pub const FileTree = struct {
    entries: std.StringHashMapUnmanaged(*const CentralDirectoryHeader) = .{},
    structure: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(*const CentralDirectoryHeader)) = .{},

    pub fn appendFile(self: *FileTree, allocator: *std.mem.Allocator, hdr: *const CentralDirectoryHeader) !void {
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

    pub fn deinit(self: *FileTree, allocator: *std.mem.Allocator) void {
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
