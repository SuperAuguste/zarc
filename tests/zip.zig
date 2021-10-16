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

    var main_extract_dir = try std.fs.cwd().makeOpenPath("tests/extract/zip", .{});
    defer main_extract_dir.close();

    var report = try std.fs.cwd().createFile("tests/zip.report.txt", .{});
    defer report.close();

    const writer = report.writer();

    var it = tests_dir.iterate();
    while (try it.next()) |entry| {
        var archive_file = try tests_dir.openFile(entry.name, .{});
        defer archive_file.close();

        var extract_dir = try main_extract_dir.makeOpenPath(entry.name, .{});
        defer extract_dir.close();

        const size = try archive_file.getEndPos();

        var timer = try std.time.Timer.start();
        const archive = try zarc.zip.readInfo(archive_file.reader());

        try writer.print("File: {s}\n", .{entry.name});

        const archive_dir = try zarc.zip.readDirectory(allocator, archive_file.reader(), archive);
        defer archive_dir.deinit(allocator);

        const time = timer.read();

        const load_time = @intToFloat(f64, time) / 1e9;
        const read_speed = (@intToFloat(f64, archive.ecd.directory_size) * 2 + @intToFloat(f64, archive.directory_offset)) / load_time;

        try writer.print("Runtime: {d:.3}ms\n\n", .{load_time * 1e3});
        try writer.print("Speed: {d:.3} MB/s\n", .{read_speed / 1e6});
        try writer.print("Total Size: {d}\n", .{size});
        try writer.print("Offset: {d}\n", .{archive.start_offset});
        try writer.print("Directory Size: {d}\n", .{archive.ecd.directory_size});
        try writer.print("Directory Offset: {d}\n", .{archive.directory_offset});
        try writer.print("Entries: {d}\n", .{archive.num_entries});
        try writer.print("ZIP64: {}\n", .{archive.is_zip64});

        // var tree = try archive_dir.getFileTree(allocator);
        // defer tree.deinit(allocator);
        // try printFileTree(writer, tree);

        // const start = timer.read();
        // const total_written = try archive_dir.extract(archive_file.reader(), extract_dir, .{ .skip_components = 1 });
        // const stop = timer.read();

        // const extract_time = @intToFloat(f64, stop - start) / 1e9;
        // const extract_speed = @intToFloat(f64, total_written) / extract_time;
        // try writer.print("Extract Size: {d}\n", .{total_written});
        // try writer.print("Extract Speed: {d:.3} MB/s\n", .{extract_speed / 1e6});

        try writer.writeAll("\n-----\n\n");
    }
}
