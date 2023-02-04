//! SIMD optimizated utility functions

const std = @import("std");

/// NOTE: This function is probably missing some optimizations of some kind.
/// Feel free to tinker! Also this could easily be genericized by adding a base
/// param, but we only need this for octal, so that isn't necessary yet.
/// Benchmarks on my machine indicate this is twice as fast as std.fmt.parseInt.
pub fn parseOctal(comptime T: type, comptime size: usize, buf: [size]u8) T {
    std.debug.assert(buf.len == size);

    const VectorT = std.meta.Vector(size, T);

    // The size of our Vector is required to be known at compile time,
    // so let's compute our "multiplication mask" at compile time too!
    comptime var multi_mask: VectorT = undefined;
    // This "subtraction mask" Turns ASCII numbers into actual numbers
    // by subtracting 48, the ASCII value of '0'
    const sub_mask: @Vector(size, T) = @splat(@as(T, 48));

    // Our accumulator for our "multiplication mask" (1, 8, 64, etc.)
    comptime var acc: T = 1;
    comptime var acci: usize = 0;

    // Preload the vector with our powers of 8
    comptime while (acci < size) : ({
        acc *= 8;
        acci += 1;
    }) {
        multi_mask[size - acci - 1] = acc;
    };

    // Let's actually do the math now!
    var vec: VectorT = undefined;
    for (buf, 0..) |b, i| vec[i] = b;
    // Applies our "subtraction mask"
    vec -= sub_mask;
    // Applies our "multiplication mask"
    vec *= multi_mask;

    // Finally sum things up
    return @reduce(.Add, vec);
}

test "SIMD Octal Parsing" {
    try std.testing.expectEqual(parseOctal(u64, 11, "77777777777"), 8589934591);
    try std.testing.expectEqual(parseOctal(u64, 11, "74717577077"), 8174632511);
}

fn fillMultiMask(comptime T: type, comptime vector_size: u32, comptime multi_mask: *std.meta.Vector(vector_size, T), comptime offset: usize, comptime size: usize) void {
    // Our accumulator for our "multiplication mask" (1, 8, 64, etc.)
    comptime var acc: T = 1;
    comptime var acci: usize = 0;

    // Preload the vector with our powers of 8
    comptime while (acci < size) : ({
        acc *= 8;
        acci += 1;
    }) {
        multi_mask.*[offset + (size - acci - 1)] = acc;
    };
}

/// Parses a set of octal fields all at once.
pub fn OctalGroupParser(comptime T: type, comptime Z: type) type {
    const z_fields = std.meta.fields(Z);

    const OutT = @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = &comptime fields: {
            var fields: [z_fields.len]std.builtin.TypeInfo.StructField = undefined;

            inline for (z_fields, 0..) |field, i| {
                fields[i] = .{
                    .name = field.name,
                    .type = T,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = 0,
                };
            }

            break :fields fields;
        },
        .decls = &[0]std.builtin.TypeInfo.Declaration{},
        .is_tuple = false,
    } });

    return struct {
        pub fn process(input: Z) OutT {
            var o: OutT = undefined;

            comptime var vector_size: u32 = 0;
            comptime var multi_offset: usize = 0;

            inline for (z_fields) |field| {
                std.debug.assert(@field(input, field.name).len == @sizeOf(field.type)); // Length mismatch
                vector_size += @sizeOf(field.type);
            }

            const VectorT = std.meta.Vector(vector_size, T);
            comptime var multi_mask: VectorT = undefined;
            const sub_mask: @Vector(vector_size, T) = @splat(@as(T, 48));

            comptime for (z_fields) |field| {
                fillMultiMask(T, vector_size, &multi_mask, multi_offset, @sizeOf(field.type));
                multi_offset += @sizeOf(field.type);
            };

            var big_boy_buf: [vector_size]T = undefined;
            var bc: [vector_size]u8 = @bitCast(input);
            for (bc, 0..) |b, i| big_boy_buf[i] = b;

            // Let's actually do the math now!
            var vec: VectorT = big_boy_buf;
            // Applies our "subtraction mask"
            vec -= sub_mask;
            // Applies our "multiplication mask"
            vec *= multi_mask;

            comptime var sb_off: usize = 0;
            var small_boy_buf: [vector_size]T = vec;

            inline for (z_fields) |field| {
                var imp: std.meta.Vector(@sizeOf(field.type), T) = small_boy_buf[sb_off .. sb_off + @sizeOf(field.type)].*;
                @field(o, field.name) = @reduce(.Add, imp);
                sb_off += @sizeOf(field.type);
            }

            return o;
        }
    };
}
