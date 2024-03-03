const std = @import("std");

pub const simd = @import("utils/simd.zig");

pub fn readStruct(comptime T: type, instance: *T, reader: anytype, comptime expected_size: usize) !void {
    const fields = std.meta.fields(T);

    var buf: [expected_size]u8 = undefined;
    const read = try reader.readAll(&buf);
    if (read != expected_size) return error.EndOfStream;

    comptime var index = 0;
    inline for (fields) |field| {
        const child = field.type;

        switch (@typeInfo(child)) {
            .Struct => |data| {
                if (data.layout == .Packed) {
                    const Int = std.meta.Int(.unsigned, @sizeOf(child) * 8);

                    @field(instance, field.name) = @bitCast(std.mem.readIntLittle(Int, buf[index..][0..@sizeOf(Int)]));
                    index += @sizeOf(Int);
                } else {
                    const Int = @typeInfo(@TypeOf(child.read)).Fn.args[0].arg_type.?;

                    @field(instance, field.name) = child.read(std.mem.readIntLittle(Int, buf[index..][0..@sizeOf(Int)]));
                    index += @sizeOf(Int);
                }
            },
            .Enum => |data| {
                @field(instance, field.name) = @enumFromInt(std.mem.readIntLittle(data.tag_type, buf[index..][0..@sizeOf(data.tag_type)]));
                index += @sizeOf(data.tag_type);
            },
            .Int => {
                @field(instance, field.name) = std.mem.readIntLittle(child, buf[index..][0..@sizeOf(child)]);
                index += @sizeOf(child);
            },
            .Array => |data| {
                if (data.child == u8) {
                    @field(instance, field.name) = buf[index..][0 .. @sizeOf(data.child) * data.len].*;
                    index += @sizeOf(data.child) * data.len;
                } else unreachable;
            },
            else => unreachable,
        }
    }

    if (index != expected_size) @compileError("invalid size");
}

pub fn LimitedReader(comptime ReaderType: type) type {
    return struct {
        unlimited_reader: ReaderType,
        limit: usize,
        pos: usize = 0,

        pub const Error = ReaderType.Error;
        pub const Reader = std.io.Reader(*Self, Error, read);

        const Self = @This();

        pub fn init(unlimited_reader: ReaderType, limit: usize) Self {
            return .{
                .unlimited_reader = unlimited_reader,
                .limit = limit,
            };
        }

        fn read(self: *Self, dest: []u8) Error!usize {
            if (self.pos >= self.limit) return 0;

            const left = @min(self.limit - self.pos, dest.len);
            const num_read = try self.unlimited_reader.read(dest[0..left]);

            self.pos += num_read;

            return num_read;
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }
    };
}
