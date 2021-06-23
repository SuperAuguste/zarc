const std = @import("std");

pub const zip = @import("formats/zip.zig");
pub const tar = @import("formats/tar.zig");

pub const ArchiveKind = enum {
    zip,
    /// tars are first decompressed, then handled here
    tar,
};

pub const Archive = struct {};

// pub fn parse(allocator: *std.mem.Allocator, file: std.fs.File, archive_kind: ArchiveKind) Archive {}

test {
    std.testing.refAllDecls(@This());
}
