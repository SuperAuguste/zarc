const std = @import("std");
const zip = @import("formats/zip.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();
    const allocator = &gpa.allocator;

    var zip_file = try std.fs.cwd().openFile("java.base.jmod", .{});

    var start = std.time.milliTimestamp();

    var zip_parser = zip.Parser.init(allocator, zip_file);
    try zip_parser.load();
    defer zip_parser.deinit();

    var file = try zip_parser.file_tree.root_dir.getFile("legal/asm.md");
    var local_header = try file.readLocalFileHeader();

    var data = try allocator.alloc(u8, local_header.uncompressed_size);
    defer allocator.free(data);
    _ = try local_header.decompress(data);

    std.log.info("Decompressed data: {s}", .{data});

    std.debug.print("Total runtime in ms: {d}", .{std.time.milliTimestamp() - start});
}
