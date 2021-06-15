const std = @import("std");
const compression = @import("compression.zig");

pub const DataDescriptor = packed struct {
    const Self = @This();

    uncompressed_checksum: u32,
    compressed_size: u32,
    uncompressed_size: u32,

    pub fn parse(reader: anytype) !Self {
        return try reader.readStruct(Self);
    }
};

pub const LocalFileHeader = packed struct {
    const Self = @This();

    /// Minimum version of the zip spec required.
    min_version: u16,
    /// General purpose bit flag.
    bit_flag: u16,
    /// The method used to compress this file.
    compression_method: compression.CompressionMethod,

    last_modified_time: u16,
    last_modified_date: u16,

    /// CRC-32 of uncompressed data.
    uncompressed_checksum: u32,
    /// Compressed size (or 0xffffffff for ZIP64)
    compressed_size: u32,

    /// Uncompressed size (or 0xffffffff for ZIP64)
    uncompressed_size: u32,
    filename_length: u16,
    extra_field_length: u16,

    pub fn parse(reader: anytype) !Self {
        return try reader.readStruct(Self);
    }

    pub fn readFilenameArrayList(self: Self, reader: anytype, array_list: *std.ArrayList(u8)) ![]u8 {
        try array_list.ensureTotalCapacity(self.filename_length);
        array_list.expandToCapacity();

        var read = try reader.readAll(array_list.items[0..self.filename_length]);
        return array_list.items[0..read];
    }

    pub fn readExtraFieldArrayList(self: Self, reader: anytype, array_list: *std.ArrayList(u8)) ![]u8 {
        try array_list.ensureTotalCapacity(self.extra_field_length);
        array_list.expandToCapacity();

        var read = try reader.readAll(array_list.items[0..self.extra_field_length]);
        return array_list.items[0..read];
    }

    pub fn decompressArrayList(self: Self, reader: anytype, array_list: *std.ArrayList(u8)) ![]u8 {
        try array_list.ensureTotalCapacity(self.uncompressed_size);
        array_list.expandToCapacity();

        switch (self.compression_method) {
            .none => {
                var read = try reader.readAll(array_list.items[0..self.uncompressed_size]);
                return array_list.items[0..read];
            },
            .deflated => {
                var window: [0x8000]u8 = undefined;
                var stream = std.compress.deflate.inflateStream(reader, &window);
                var read = try stream.reader().readAll(array_list.items[0..self.uncompressed_size]);
                return array_list.items[0..read];
            },
            else => {
                std.log.crit("bidoof this method isn't implemented! {s}", .{self.compression_method});
                return error.MethodNotImplemented;
            },
        }
    }

    pub fn needsDataDescriptor(self: Self) bool {
        return self.bit_flag & 0x08 == 0x08;
    }

    pub fn parseDataDescriptor(self: Self, reader: anytype) !DataDescriptor {
        while (true) {
            var first = try reader.readByte();
            if (first != 'P') continue;
            var second = try reader.readByte();
            if (second != 'K') continue;

            var buf: [2]u8 = undefined;
            var rest = try reader.readAll(&buf);

            if ((buf[0] == 0x03 and buf[1] == 0x04) or (buf[0] == 0x01 and buf[1] == 0x02)) {
                try reader.context.seekBy(-16);
                return DataDescriptor.parse(reader);
            }
        }

        return error.DataDescriptorNotFound;
    }
};

pub const CentralDirectoryHeader = packed struct {
    const Self = @This();

    made_by_version: u16,
    min_version: u16,

    bit_flag: u16,
    compression_method: compression.CompressionMethod,

    last_modified_time: u16,
    last_modified_date: u16,

    /// CRC-32 of uncompressed data.
    uncompressed_checksum: u32,
    /// Compressed size (or 0xffffffff for ZIP64)
    compressed_size: u32,

    /// Uncompressed size (or 0xffffffff for ZIP64)
    uncompressed_size: u32,
    filename_length: u16,
    extra_field_length: u16,
    file_comment_length: u16,
    disk_number_start: u16,

    internal_file_attributes: u16,
    external_file_attributes: u32,

    relative_offset: u32,

    pub fn parse(reader: anytype) !Self {
        return try reader.readStruct(Self);
    }

    pub fn readFilenameArrayList(self: Self, reader: anytype, array_list: *std.ArrayList(u8)) ![]u8 {
        try array_list.ensureTotalCapacity(self.filename_length);
        array_list.expandToCapacity();

        var read = try reader.readAll(array_list.items[0..self.filename_length]);
        return array_list.items[0..read];
    }

    pub fn readExtraFieldArrayList(self: Self, reader: anytype, array_list: *std.ArrayList(u8)) ![]u8 {
        try array_list.ensureTotalCapacity(self.extra_field_length);
        array_list.expandToCapacity();

        var read = try reader.readAll(array_list.items[0..self.extra_field_length]);
        return array_list.items[0..read];
    }

    pub fn readFileCommentArrayList(self: Self, reader: anytype, array_list: *std.ArrayList(u8)) ![]u8 {
        try array_list.ensureTotalCapacity(self.file_comment_length);
        array_list.expandToCapacity();

        var read = try reader.readAll(array_list.items[0..self.file_comment_length]);
        return array_list.items[0..read];
    }
};

pub const EndCentralDirectoryRecord = packed struct {
    const Self = @This();

    disk_number: u16,
    central_directory_start_disk: u16,
    disk_central_directory_count: u16,
    total_central_directory_count: u16,

    central_directory_size: u32,
    central_directory_offset: u32,
    comment_length: u16,

    pub fn parse(reader: anytype) !Self {
        return try reader.readStruct(Self);
    }

    pub fn readFileCommentArrayList(self: Self, reader: anytype, array_list: *std.ArrayList(u8)) ![]u8 {
        try array_list.ensureTotalCapacity(self.file_comment_length);
        array_list.expandToCapacity();

        var read = try reader.readAll(array_list.items[0..self.file_comment_length]);
        return array_list.items[0..read];
    }
};

pub const Section = union(enum) {
    const Self = @This();

    /// 0x04034b50 (PK\x03\x04).
    local_file_header: LocalFileHeader,
    /// 0x02014b50 (PK\x01\x02).
    central_directory_header: CentralDirectoryHeader,
    /// 0x06054b50 (PK\x05\x06).
    end_central_directory_record: EndCentralDirectoryRecord,

    pub fn parse(reader: anytype) !Self {
        while (true) {
            var first = try reader.readByte();
            if (first != 'P') continue;
            var second = try reader.readByte();
            if (second != 'K') continue;

            var buf: [2]u8 = undefined;
            var rest = try reader.readAll(&buf);

            if (buf[0] == 0x03 and buf[1] == 0x04) {
                return Self{ .local_file_header = try LocalFileHeader.parse(reader) };
            } else if (buf[0] == 0x01 and buf[1] == 0x02) {
                return Self{ .central_directory_header = try CentralDirectoryHeader.parse(reader) };
            } else if (buf[0] == 0x05 and buf[1] == 0x06) {
                return Self{ .end_central_directory_record = try EndCentralDirectoryRecord.parse(reader) };
            }
        }
    }
};

// High-level constructs

pub const ZipFile = struct {
    name: []const u8,
    offset: u64,
};

pub const ZipDirectoryChild = union(enum) {
    directory: *ZipDirectory,
    file: *ZipFile,
};

pub const ZipDirectory = struct {
    name: []const u8,
    children: std.StringHashMap(ZipDirectoryChild),

    pub fn iterate(self: ZipDirectory) std.StringHashMap(ZipDirectoryChild).ValueIterator {
        return self.children.valueIterator();
    }

    pub fn getDir(self: *ZipDirectory, path: []const u8) !*ZipDirectory {
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

    allocator: *std.mem.Allocator,
    root_dir: ZipDirectory,

    pub fn init(allocator: *std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .root_dir = .{
                .name = "/",
                .children = std.StringHashMap(ZipDirectoryChild).init(allocator),
            },
        };
    }

    pub fn appendFile(self: *Self, file: ZipFile) !void {
        var parts = std.mem.split(file.name, "/");
        var dir = &self.root_dir;

        while (parts.next()) |part| {
            if (parts.index == null) {
                var f = try self.allocator.create(ZipFile);
                f.* = file;
                try dir.children.put(part, .{ .file = f });
            } else {
                var gpr = try dir.children.getOrPut(part);
                if (gpr.found_existing) {
                    dir = gpr.value_ptr.*.directory;
                } else {
                    var d = try self.allocator.create(ZipDirectory);
                    d.* = .{
                        .name = part,
                        .children = std.StringHashMap(ZipDirectoryChild).init(self.allocator),
                    };
                    gpr.value_ptr.* = .{ .directory = d };
                    dir = d;
                }
            }
        }
    }
};

pub fn Zip(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: *std.mem.Allocator,
        reader: T,
        file_tree: FileTree,

        pub fn init(allocator: *std.mem.Allocator, reader: T) !Self {
            var start: usize = 0;
            var end = try reader.context.getEndPos();

            while (true) {
                var first = try reader.readByte();
                if (first != 'P') continue;
                var second = try reader.readByte();
                if (second != 'K') continue;

                break;
            }

            start = (try reader.context.getPos()) + 2;

            var offset: usize = 22;
            while ((try reader.readIntLittle(u32)) != 0x06054b50) : (offset += 1)
                try reader.context.seekTo(end - offset);

            var eocd = try EndCentralDirectoryRecord.parse(reader);

            try reader.context.seekTo(eocd.central_directory_offset + start);

            var file_tree = FileTree.init(allocator);

            var index: usize = 0;
            while (index < eocd.total_central_directory_count) : (index += 1) {
                var cdh = try CentralDirectoryHeader.parse(reader);

                var name = try allocator.alloc(u8, cdh.filename_length);
                _ = try reader.readAll(name);

                try file_tree.appendFile(.{
                    .name = name,
                    .offset = try reader.context.getPos(),
                });

                try reader.context.seekBy(cdh.extra_field_length + cdh.file_comment_length + 4); // 4 is for the signature of the next directory btw
            }

            return Self{
                .allocator = allocator,
                .reader = reader,
                .file_tree = file_tree,
            };
        }

        pub fn openDir(self: *Self) ZipDirectory {}
    };
}
