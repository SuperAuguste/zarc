const std = @import("std");
// const zarc = @import("zarc.zig");
const zip = @import("formats/zip.zig");
const tar = @import("formats/tar.zig");

fn printDir(file_tree: zip.FileTree, name: []const u8, depth: usize) anyerror!void {
    var w = std.io.getStdErr().writer();
    if (file_tree.readDir(name)) |d|
        for (d.items) |entry| {
            try w.writeByteNTimes(' ', depth);
            try w.writeAll(entry.filename[if (std.mem.eql(u8, name, "/")) 0 else name.len + 1..]);
            try w.writeByte('\n');
            if (entry.filename[entry.filename.len - 1] == '/') try printDir(file_tree, entry.filename[0 .. entry.filename.len - 1], depth + 1);
        };
}

fn printFileTree(file_tree: zip.FileTree) !void {
    try printDir(file_tree, "/", 0);
}

pub fn main() anyerror!void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.detectLeaks();
    // const allocator = &gpa.allocator;
    const allocator = std.heap.page_allocator;

    var archive_file = try std.fs.cwd().openFile("zig-windows.zip", .{});

    var start = std.time.milliTimestamp();

    // TODO: Actually get this working.
    // var archive = try zarc.parse(allocator, archive_file, .zip);
    // defer archive.deinit();

    // var root = archive.file_tree.root_dir;
    // var file = root.getEntry("legal/asm.md").file;

    // var data = try file.decompress();
    // defer allocator.free(data);

    // std.log.info("{s}", .{data});

    // var archive = tar.Parser.init(allocator, archive_file);
    // try archive.load();

    var archive = zip.Parser.init(allocator, archive_file);
    try archive.load();

    std.debug.print("Total runtime in ms: {d}\n", .{std.time.milliTimestamp() - start});

    try printFileTree(archive.file_tree);
}
