const std = @import("std");

pub const simd = @import("utils/simd.zig");

pub fn readStruct(comptime T: type, instance: *T, reader: anytype, comptime expected_size: usize) !usize {
    const fields = std.meta.fields(T);

    var buf: [expected_size]u8 = undefined;
    _ = try reader.readAll(&buf);

    comptime var index = 0;
    inline for (fields) |field| {
        const child = field.field_type;

        switch (@typeInfo(child)) {
            .Struct => |data| {
                if (data.layout == .Packed) {
                    const Int = std.meta.Int(.unsigned, @sizeOf(child) * 8);

                    @field(instance, field.name) = @bitCast(field.field_type, std.mem.readIntLittle(Int, buf[index..][0..@sizeOf(Int)]));
                    index += @sizeOf(Int);
                } else {
                    const Int = @typeInfo(@TypeOf(child.cast)).Fn.args[0].arg_type.?;

                    @field(instance, field.name) = child.cast(std.mem.readIntLittle(Int, buf[index..][0..@sizeOf(Int)]));
                    index += @sizeOf(Int);
                }
            },
            .Enum => |data| {
                @field(instance, field.name) = @intToEnum(child, std.mem.readIntLittle(data.tag_type, buf[index..][0..@sizeOf(data.tag_type)]));
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

    return expected_size;
}
