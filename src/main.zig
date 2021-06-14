const std = @import("std");
const zzip = @import("zzip.zig");

pub fn main() anyerror!void {
    const allocator = std.heap.page_allocator;

    var f = try std.fs.cwd().openFile("do_not_open.zip", .{});
    var reader = f.reader();
    var buf = std.ArrayList(u8).init(allocator);

    while (true) {
        var section = try zzip.Section.parse(reader);

        switch (section) {
            .local_file_header => |*file| {
                std.log.info("Reading {s}", .{file.readFilenameArrayList(reader, &buf)});
                _ = try file.readExtraFieldArrayList(reader, &buf);

                if (file.needsDataDescriptor()) {
                    var start_of_data = try reader.context.getPos();
                    var desc = try file.parseDataDescriptor(reader);

                    file.uncompressed_checksum = desc.uncompressed_checksum;
                    file.compressed_size = desc.compressed_size;
                    file.uncompressed_size = desc.uncompressed_size;

                    try reader.context.seekTo(start_of_data);

                    var d = try file.decompressArrayList(reader, &buf);
                    var h = std.hash.Crc32.hash(d);

                    if (h != file.uncompressed_checksum) @panic("Oh no the impostor vented!!");
                } else {
                    var d = try file.decompressArrayList(reader, &buf);
                    var h = std.hash.Crc32.hash(d);

                    if (h != file.uncompressed_checksum) @panic("Oh no the impostor vented!!");
                }
            },
            .central_directory_header => |cdh| {
                std.log.info("{s}", .{cdh.readFilenameArrayList(reader, &buf)});
                std.log.info("{s}", .{cdh.readExtraFieldArrayList(reader, &buf)});
                std.log.info("{s}", .{cdh.readFileCommentArrayList(reader, &buf)});
            },
            .end_central_directory_record => |cdh| {
                std.log.info("Sussy wussy amongus!! {s}", .{cdh});
                break;
            },
        }
    }
}
