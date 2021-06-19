const std = @import("std");
const zarc = @import("zarc");

fn printDir(writer: anytype, file_tree: zarc.zip.FileTree, name: []const u8, depth: usize) anyerror!void {
    if (file_tree.readDir(name)) |d| {
        for (d.items) |entry| {
            try writer.writeByteNTimes('\t', depth);
            try writer.writeAll(entry.filename[if (std.mem.eql(u8, name, "/")) 0 else name.len + 1..]);
            try writer.writeByte('\n');

            if (entry.filename[entry.filename.len - 1] == '/') {
                try printDir(writer, file_tree, entry.filename[0 .. entry.filename.len - 1], depth + 1);
            }
        }
    }
}

fn printFileTree(writer: anytype, file_tree: zarc.zip.FileTree) !void {
    try printDir(writer, file_tree, "/", 0);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var tests_dir = try std.fs.cwd().openDir("tests/zip", .{ .iterate = true });
    defer tests_dir.close();

    var report = try std.fs.cwd().createFile("tests/zip.report.txt", .{});
    defer report.close();

    const writer = report.writer();

    var it = tests_dir.iterate();
    while (try it.next()) |entry| {
        var archive_file = try tests_dir.openFile(entry.name, .{});
        defer archive_file.close();

        const size = try archive_file.getEndPos();

        var timer = try std.time.Timer.start();
        var archive = zarc.zip.Parser.init(allocator, archive_file);
        defer archive.deinit();

        try archive.load();
        const time = timer.read();

        try writer.print("File: {s}\n", .{entry.name});
        try writer.print("Runtime: {d:.3}ms\n\n", .{@intToFloat(f64, time) / 1e6});
        try writer.print("Total Size: {d}\n", .{size});
        try writer.print("Offset: {d}\n", .{archive.start_offset});
        try writer.print("Archive Size: {d}\n", .{size - archive.start_offset});
        try writer.print("ZIP64: {}\n", .{archive.is_zip64});
        try writer.print("Entries: {d}\n", .{archive.num_entries});
        try writer.print("Directory Size: {d}\n", .{archive.dir_size});
        try writer.print("Directory Offset: {d}\n\n", .{archive.dir_offset});

        try printFileTree(writer, archive.file_tree);

        try writer.writeAll("\n-----\n\n");
    }
}
