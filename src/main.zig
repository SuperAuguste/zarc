const std = @import("std");
const zzip = @import("zzip.zig");

pub fn main() anyerror!void {
    const allocator = std.heap.page_allocator;

    var zip_file = try std.fs.cwd().openFile("zig-windows.zip", .{});

    var timer = try std.time.Timer.start();
    var zip = zzip.Parser.init(allocator, zip_file);
    try zip.load();
    const stop = timer.read();

    std.debug.print("{}\n", .{stop});

    // for (zip.central_directory.items) |f| {
    //     std.debug.print("{s}\n", .{f.filename});
    // }
}
