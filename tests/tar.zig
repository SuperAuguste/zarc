const std = @import("std");
const zarc = @import("zarc");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var tests_dir = try std.fs.cwd().openDir("tests/tar", .{ .iterate = true });
    defer tests_dir.close();

    var report = try std.fs.cwd().createFile("tests/tar.report.txt", .{});
    defer report.close();

    const writer = report.writer();

    var it = tests_dir.iterate();
    while (try it.next()) |entry| {
        var archive_file = try tests_dir.openFile(entry.name, .{});
        defer archive_file.close();

        const size = try archive_file.getEndPos();

        var timer = try std.time.Timer.start();
        var archive = zarc.tar.Parser.init(allocator, archive_file);
        defer archive.deinit();

        try archive.load();
        const time = timer.read();

        try writer.print("File: {s}\n", .{entry.name});
        try writer.print("Runtime: {d:.3}ms\n", .{@intToFloat(f64, time) / 1e6});

        try writer.writeAll("\n-----\n\n");

        _ = size;

        // while (true) {}
    }
}
