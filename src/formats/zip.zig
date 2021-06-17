const std = @import("std");
const mem = std.mem;

pub const CompressionMethod = enum(u16) {
    none = 0,
    shrunk = 1,
    rwcf1 = 2,
    rwcf2 = 3,
    rwcf3 = 4,
    rwcf4 = 5,
    imploded = 6,
    deflated = 8,
    enhanced_deflated = 9,
    pkware_dcl_imploded = 10,
    bzip2 = 12,
    lzma = 14,
    ibm_terse = 18,
    ibm_lz77_z = 19,
    ppmd_version_i_rev_1 = 98,
};

pub const LocalFileHeader = struct {
    pub const Signature = 0x04034b50;

    parser: *Parser,
    location: usize,

    version_needed: u16,
    bit_flag: u16,
    compression_method: CompressionMethod,

    last_mod_time: u16,
    last_mod_date: u16,

    checksum: u32,
    compressed_size: u32,
    uncompressed_size: u32,

    filename_len: u16,
    extrafield_len: u16,

    pub fn parse(self: *LocalFileHeader, parser: *Parser) !void {
        self.parser = parser;
        self.location = try parser.file.getPos() - 4;

        var buf: [26]u8 = undefined;
        _ = try parser.reader.readAll(&buf);

        self.version_needed = mem.readIntLittle(u16, buf[0..2]);
        self.bit_flag = mem.readIntLittle(u16, buf[2..4]);
        self.compression_method = @intToEnum(CompressionMethod, mem.readIntLittle(u16, buf[4..6]));

        self.last_mod_time = mem.readIntLittle(u16, buf[6..8]);
        self.last_mod_date = mem.readIntLittle(u16, buf[8..10]);

        self.checksum = mem.readIntLittle(u32, buf[10..14]);
        self.compressed_size = mem.readIntLittle(u32, buf[14..18]);
        self.uncompressed_size = mem.readIntLittle(u32, buf[18..22]);

        self.filename_len = mem.readIntLittle(u16, buf[22..24]);
        self.extrafield_len = mem.readIntLittle(u16, buf[24..26]);

        try parser.file.seekBy(self.filename_len + self.extrafield_len);
    }
};

pub const DataDescriptor = struct {
    pub const Signature = 0x04034b50;

    parser: *Parser,
    location: usize,

    checksum: u32,
    compressed_size: u32,
    uncompressed_size: u32,

    pub fn parse(self: *DataDescriptor, parser: *Parser) !void {
        self.parser = parser;
        self.location = try reader.context.getPos() - 4;

        var buf: [12]u8 = undefined;
        _ = try parser.reader.readAll(&buf);

        self.checksum = mem.readIntLittle(u32, buf[0..4]);
        self.compressed_size = mem.readIntLittle(u32, buf[4..8]);
        self.uncompressed_size = mem.readIntLittle(u32, buf[8..12]);
    }
};

pub const CentralDirectoryHeader = struct {
    pub const Signature = 0x02014b50;

    parser: *Parser,
    location: usize,

    version_made: u16,
    version_needed: u16,
    bit_flag: u16,
    compression_method: u16,

    last_mod_time: u16,
    last_mod_date: u16,

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

    filename: []const u8,
    extrafield: []const u8,
    file_comment: []const u8,

    pub fn parse(self: *CentralDirectoryHeader, parser: *Parser, reader: anytype, position: usize) !usize {
        self.parser = parser;
        self.location = position - 4;

        var buf: [42]u8 = undefined;
        _ = try reader.readAll(&buf);

        self.version_made = mem.readIntLittle(u16, buf[0..2]);
        self.version_needed = mem.readIntLittle(u16, buf[2..4]);
        self.bit_flag = mem.readIntLittle(u16, buf[4..6]);
        self.compression_method = mem.readIntLittle(u16, buf[6..8]);

        self.last_mod_time = mem.readIntLittle(u16, buf[8..10]);
        self.last_mod_date = mem.readIntLittle(u16, buf[10..12]);

        self.checksum = mem.readIntLittle(u32, buf[12..16]);
        self.compressed_size = mem.readIntLittle(u32, buf[16..20]);
        self.uncompressed_size = mem.readIntLittle(u32, buf[20..24]);

        self.filename_len = mem.readIntLittle(u16, buf[24..26]);
        self.extrafield_len = mem.readIntLittle(u16, buf[26..28]);
        self.file_comment_len = mem.readIntLittle(u16, buf[28..30]);

        self.disk_start = mem.readIntLittle(u16, buf[30..32]);
        self.internal_attributes = mem.readIntLittle(u16, buf[32..34]);
        self.external_attributes = mem.readIntLittle(u32, buf[34..38]);

        self.data_offset = mem.readIntLittle(u32, buf[38..42]);

        self.filename = try parser.readString(reader, self.filename_len);
        self.extrafield = try parser.readString(reader, self.extrafield_len);
        self.file_comment = try parser.readString(reader, self.file_comment_len);

        return 42 + self.filename_len + self.extrafield_len + self.file_comment_len;
    }
};

pub const EndCentralDirectory64Record = struct {
    pub const Signature = 0x06064b50;

    parser: *Parser,
    location: usize,

    size: u64,

    version_made: u16,
    version_needed: u16,

    disk_number: u32,
    disk_start_central_directory: u32,
    disk_count_directory_entries: u64,

    central_directory_entry_count: u64,
    central_directory_size: u64,
    central_directory_offset: u64,

    pub fn parse(self: *EndCentralDirectory64Record, parser: *Parser) !usize {
        self.parser = parser;
        self.location = (try parser.file.getPos()) - 4;

        var buf: [52]u8 = undefined;
        _ = try parser.reader.readAll(&buf);

        self.size = mem.readIntLittle(u64, buf[0..8]);

        self.version_made = mem.readIntLittle(u16, buf[8..10]);
        self.disk_count_directory_entries = mem.readIntLittle(u16, buf[10..12]);

        self.disk_number = mem.readIntLittle(u32, buf[12..16]);
        self.disk_start_central_directory = mem.readIntLittle(u32, buf[16..20]);
        self.disk_count_directory_entries = mem.readIntLittle(u64, buf[20..28]);

        self.central_directory_entry_count = mem.readIntLittle(u64, buf[28..36]);
        self.central_directory_size = mem.readIntLittle(u64, buf[36..44]);
        self.central_directory_offset = mem.readIntLittle(u64, buf[44..52]);

        try parser.file.seekBy(self.size - 44);

        return 12 + self.size;
    }
};

pub const EndCentralDirectory64Locator = struct {
    pub const Signature = 0x07064b50;

    parser: *Parser,
    location: usize,

    disk_number: u32,
    ecd64_offset: u64,
    number_of_disks: u32,

    pub fn parse(self: *EndCentralDirectory64Locator, parser: *Parser) !usize {
        self.parser = parser;
        self.location = (try parser.file.getPos()) - 4;

        var buf: [16]u8 = undefined;
        _ = try parser.reader.readAll(&buf);

        self.disk_number = mem.readIntLittle(u32, buf[0..4]);
        self.ecd64_offset = mem.readIntLittle(u64, buf[4..12]);
        self.number_of_disks = mem.readIntLittle(u32, buf[12..16]);

        return 16;
    }
};

pub const EndCentralDirectoryRecord = struct {
    pub const Signature = 0x06054b50;

    parser: *Parser,
    location: usize,

    disk_number: u16,
    disk_start_central_directory: u16,
    disk_count_directory_entries: u16,

    central_directory_entry_count: u16,
    central_directory_size: u32,
    central_directory_offset: u32,

    comment_length: u16,

    pub fn parse(self: *EndCentralDirectoryRecord, parser: *Parser) !usize {
        self.parser = parser;
        self.location = (try parser.file.getPos()) - 4;

        var buf: [18]u8 = undefined;
        _ = try parser.reader.readAll(&buf);

        self.disk_number = mem.readIntLittle(u16, buf[0..2]);
        self.disk_start_central_directory = mem.readIntLittle(u16, buf[2..4]);
        self.disk_count_directory_entries = mem.readIntLittle(u16, buf[4..6]);

        self.central_directory_entry_count = mem.readIntLittle(u16, buf[6..8]);
        self.central_directory_size = mem.readIntLittle(u32, buf[8..12]);
        self.central_directory_offset = mem.readIntLittle(u32, buf[12..16]);

        self.comment_length = mem.readIntLittle(u16, buf[16..18]);

        try parser.file.seekBy(self.comment_length);

        return 18 + self.comment_length;
    }
};

pub const Parser = struct {
    allocator: *std.mem.Allocator,

    file: std.fs.File,
    reader: std.fs.File.Reader,

    is_zip64: bool = false,
    zip_ecdr: EndCentralDirectoryRecord = undefined,
    zip64_ecdl: EndCentralDirectory64Locator = undefined,
    zip64_ecdr: EndCentralDirectory64Record = undefined,

    central_directory: std.ArrayListUnmanaged(CentralDirectoryHeader) = .{},
    file_headers: std.ArrayListUnmanaged(LocalFileHeader) = .{},
    string_buffer: std.ArrayListUnmanaged(u8) = .{},

    file_tree: FileTree = FileTree{},

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
    }

    pub fn load(self: *Parser) !void {
        self.loadZip64() catch |err| {
            if (err == error.InvalidZip64) {
                try self.loadZip();
            } else return err;
        };

        const string_space = if (self.is_zip64)
            self.zip64_ecdr.central_directory_size - (46 * self.zip64_ecdr.central_directory_entry_count)
        else
            self.zip_ecdr.central_directory_size - (46 * @as(u32, self.zip_ecdr.central_directory_entry_count));

        try self.string_buffer.ensureTotalCapacity(self.allocator, string_space);

        try self.readCentralDirectory();
    }

    fn readString(self: *Parser, reader: anytype, len: usize) ![]const u8 {
        std.debug.assert(self.string_buffer.items.len + len <= self.string_buffer.capacity);
        const prev_len = self.string_buffer.items.len;
        self.string_buffer.items.len += len;

        var buf = self.string_buffer.items[prev_len..][0..len];
        _ = try reader.readAll(buf);

        return buf;
    }

    fn findSignature(self: *Parser, sig: u32, start_offset: u64) !u64 {
        const end = try self.file.getEndPos();
        var offset = start_offset;

        if (end < offset) return error.InvalidFormat;

        while (offset < end and offset < 1024) : (offset += 1) {
            if ((try self.reader.readIntLittle(u32)) != sig) {
                try self.file.seekTo(end - offset);
            } else {
                return end - offset;
            }
        }

        return error.InvalidZip;
    }

    fn loadZip(self: *Parser) !void {
        _ = self.findSignature(EndCentralDirectoryRecord.Signature, 22) catch return error.InvalidZip;

        _ = try self.zip_ecdr.parse(self);
    }

    fn loadZip64(self: *Parser) !void {
        _ = self.findSignature(EndCentralDirectory64Locator.Signature, 22) catch return error.InvalidZip64;

        _ = try self.zip64_ecdl.parse(self);

        try self.file.seekTo(self.zip64_ecdl.location - self.zip64_ecdl.ecd64_offset);

        const zip64_ecdr_sig = try self.reader.readIntLittle(u32);
        if (zip64_ecdr_sig != EndCentralDirectory64Record.Signature) return error.InvalidZip64;

        _ = try self.zip64_ecdl.parse(self);

        self.is_zip64 = true;
    }

    fn readCentralDirectory(self: *Parser) !void {
        if (self.is_zip64) {
            std.debug.panic("zip64 unimplemented\n", .{});
        } else {
            const size = self.zip_ecdr.central_directory_entry_count;
            try self.central_directory.ensureTotalCapacity(self.allocator, size);

            var index: u32 = 0;
            var pos: usize = self.zip_ecdr.central_directory_offset;
            try self.file.seekTo(pos);

            var buffered = std.io.BufferedReader(8192, std.fs.File.Reader){ .unbuffered_reader = self.reader };
            const reader = buffered.reader();

            while (index < size) : (index += 1) {
                const sig = try reader.readIntLittle(u32);
                if (sig != CentralDirectoryHeader.Signature) return error.InvalidZip;
                pos += 4;

                var hdr = self.central_directory.addOneAssumeCapacity();
                pos += try hdr.parse(self, reader, pos);

                try self.file_tree.appendFile(self.allocator, hdr);
            }
        }
    }
};

// High-level constructs

pub const ZipFile = struct {
    name: []const u8,
    header: *const CentralDirectoryHeader,
};

pub const ZipDirectoryChild = union(enum) {
    directory: ZipDirectory,
    file: ZipFile,
};

pub const ZipDirectory = struct {
    name: []const u8,
    children: std.StringHashMapUnmanaged(ZipDirectoryChild) = .{},

    pub fn iterate(self: ZipDirectory) std.StringHashMapUnmanaged(ZipDirectoryChild).ValueIterator {
        return self.children.valueIterator();
    }

    pub fn getDir(self: *ZipDirectory, path: []const u8) !*ZipDirectory {
        if (std.mem.eql(u8, path, "/")) return self;

        var dir = self;
        var parts = std.mem.split(path, "/");

        while (parts.next()) |part| {
            if (dir.children.get(part)) |p| {
                dir = p.directory;
            } else return error.NotFound;
        }

        return dir;
    }

    pub fn getFile(self: *ZipDirectory, path: []const u8) !*ZipFile {
        var dir = self;
        var parts = std.mem.split(path, "/");

        while (parts.next()) |part| {
            std.log.info("{s} {s}", .{ part, dir.name });
            if (dir.children.get(part)) |p| {
                if (parts.index == null) return p.file;
                dir = p.directory;
            } else return error.NotFound;
        }

        unreachable;
    }
};

pub const FileTree = struct {
    const Self = @This();

    root_dir: ZipDirectory = .{
        .name = "/",
    },

    pub fn appendFile(self: *Self, allocator: *std.mem.Allocator, header: *CentralDirectoryHeader) !void {
        var parts = std.mem.split(header.filename, "/");
        var dir = &self.root_dir;

        while (parts.next()) |part| {
            if (part.len > 0) {
                if (parts.index == null) {
                    const result = try dir.children.getOrPut(allocator, part);
                    result.value_ptr.* = .{
                        .file = .{
                            .name = part,
                            .header = header,
                        },
                    };
                } else {
                    const result = try dir.children.getOrPut(allocator, part);
                    if (result.found_existing) {
                        dir = &result.value_ptr.directory;
                    } else {
                        result.value_ptr.* = .{
                            .directory = .{
                                .name = part,
                            },
                        };

                        dir = &result.value_ptr.directory;
                    }
                }
            }
        }
    }
};
