const std = @import("std");
const zip = @import("formats/zip.zig");

pub fn main() anyerror!void {
    const allocator = std.heap.page_allocator;

    var zip_file = try std.fs.cwd().openFile("java.base.jmod", .{});

    var start = std.time.milliTimestamp();

    var zip_parser = zip.Parser.init(allocator, zip_file);
    try zip_parser.load();

    std.debug.print("Total runtime in ms: {d}", .{std.time.milliTimestamp() - start});
}
