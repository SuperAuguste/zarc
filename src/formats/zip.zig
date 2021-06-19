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
        self.location = (try parser.file.getPos()) - 4;

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

        if (self.bit_flag & 0x08 == 0x08) {
            var curr = try self.parser.file.getPos();

            var data_descriptor_sigs = [_]u32{ LocalFileHeader.Signature, CentralDirectoryHeader.Signature, DataDescriptor.Signature };
            var sig_result = try self.parser.matchSignature(&data_descriptor_sigs, curr, .forwards);

            if (sig_result.signature != DataDescriptor.Signature)
                try self.parser.reader.context.seekBy(-16);

            var data_descriptor: DataDescriptor = undefined;
            try DataDescriptor.parse(&data_descriptor, self.parser);

            self.checksum = data_descriptor.checksum;
            self.compressed_size = data_descriptor.compressed_size;
            self.uncompressed_size = data_descriptor.uncompressed_size;

            try parser.file.seekTo(curr);
        }
    }

    pub fn decompress(self: *const LocalFileHeader, buffer: []u8) !usize {
        switch (self.compression_method) {
            .none => {
                return try self.parser.reader.readAll(buffer[0..self.uncompressed_size]);
            },
            .deflated => {
                var window: [0x8000]u8 = undefined;
                var stream = std.compress.deflate.inflateStream(self.parser.reader, &window);
                return try stream.reader().readAll(buffer[0..self.uncompressed_size]);
            },
            else => {
                std.log.crit("bidoof this method isn't implemented! {s}", .{self.compression_method});
                return error.MethodNotImplemented;
            },
        }
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
        self.location = (try parser.reader.context.getPos()) - 4;

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

    pub fn readLocalFileHeader(self: *const CentralDirectoryHeader) !LocalFileHeader {
        try self.parser.file.seekTo(self.parser.start_offset + self.data_offset + 4);

        var lfh: LocalFileHeader = undefined;
        try LocalFileHeader.parse(&lfh, self.parser);

        return lfh;
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

    start_offset: usize = 0,

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
        self.file_tree.root_dir.deinit(self.allocator);
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

    const SignatureDirection = enum { forwards, backwards };
    const SignatureResult = struct { offset: u64, signature: u32 };

    /// NOTE: This is a great utility method, but it's also pretty slow
    /// for signatures > 1 because `for (signatures)` is not inlinable (LLVM crashes if you try to inline it).
    /// Sadly, this is the only way to properly find signatures, so it's *slight* a tradeoff we've gotta absorb. :(
    fn matchSignature(self: *Parser, signatures: []u32, start_offset: u64, direction: SignatureDirection) !SignatureResult {
        const end = if (direction == .backwards) try self.file.getEndPos() else start_offset;
        var offset = if (direction == .backwards) start_offset else 0;

        if (end < offset) return error.InvalidFormat;

        while (((direction == .backwards and offset < end) or (direction == .forwards)) and offset < 1024) : (offset += 1) {
            for (signatures) |sig| {
                if ((try self.reader.readIntLittle(u32)) != sig) {
                    try self.file.seekTo(if (direction == .backwards) end - offset else end + offset);
                } else {
                    return SignatureResult{ .offset = if (direction == .backwards) end - offset else end + offset, .signature = sig };
                }
            }
        }

        return error.InvalidZip;
    }

    fn findSignature(self: *Parser, sig: u32, start_offset: u64, direction: SignatureDirection) !u64 {
        return (try self.matchSignature(&[_]u32{sig}, start_offset, direction)).offset;
    }

    fn loadZip(self: *Parser) !void {
        _ = self.findSignature(EndCentralDirectoryRecord.Signature, 22, .backwards) catch return error.InvalidZip;

        _ = try self.zip_ecdr.parse(self);
    }

    fn loadZip64(self: *Parser) !void {
        _ = self.findSignature(EndCentralDirectory64Locator.Signature, 22, .backwards) catch return error.InvalidZip64;

        _ = try self.zip64_ecdl.parse(self);

        try self.file.seekTo(self.zip64_ecdl.location - self.zip64_ecdl.ecd64_offset);

        const zip64_ecdr_sig = try self.reader.readIntLittle(u32);
        if (zip64_ecdr_sig != EndCentralDirectory64Record.Signature) return error.InvalidZip64;

        _ = try self.zip64_ecdl.parse(self);

        self.is_zip64 = true;
    }

    fn findStart(self: *Parser) !void {
        var original_position = try self.file.getPos();
        try self.file.seekTo(0);

        var start_sigs = [_]u32{ LocalFileHeader.Signature, CentralDirectoryHeader.Signature, EndCentralDirectoryRecord.Signature };
        _ = try self.matchSignature(&start_sigs, 0, .forwards);

        self.start_offset = (try self.file.getPos()) - 4;
        try self.file.seekTo(original_position);
    }

    fn readCentralDirectory(self: *Parser) !void {
        // Gets the start of the actual ZIP.
        // This is required because ZIPs can have preambles for self-execution, for example
        // so they could actually start anywhere in a `.zip` file.
        try self.findStart();

        // Actually begin parsing the central directory
        if (self.is_zip64) {
            std.debug.panic("zip64 unimplemented\n", .{});
        } else {
            const size = self.zip_ecdr.central_directory_entry_count;
            try self.central_directory.ensureTotalCapacity(self.allocator, size);

            var index: u32 = 0;
            var pos: usize = self.start_offset + self.zip_ecdr.central_directory_offset;
            try self.file.seekTo(pos);

            var buffered = std.io.BufferedReader(8192, std.fs.File.Reader){ .unbuffered_reader = self.reader };
            const reader = buffered.reader();

            try self.file_tree.entries.ensureCapacity(self.allocator, size);

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

    pub fn readDir(self: *const FileTree, path: []const u8) ?*std.ArrayListUnmanaged(*const CentralDirectoryHeader) {
        return if (self.structure.getEntry(path)) |ent| ent.value_ptr else null;
    }

    pub fn getEntry(self: *const FileTree, path: []const u8) ?*const CentralDirectoryHeader {
        return self.entries.get(path);
    }
};
