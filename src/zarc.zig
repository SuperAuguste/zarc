const std = @import("std");

pub const ArchiveKind = enum {
    zip,
    /// TODO: How do we handle this? Tars are so complicated because they're never compressed on their own (.tar.gz, .tar.xz, etc.)
    tar,
};

pub const Archive = struct {};

pub fn parse(allocator: *std.mem.Allocator, file: std.fs.File, archive_kind: ArchiveKind) Archive {}
