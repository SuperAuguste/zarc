const std = @import("std");
const zzip = @import("zzip.zig");

pub fn main() anyerror!void {
    const allocator = std.heap.page_allocator;

    var f = try std.fs.cwd().openFile("C:/Program Files/Java/jdk-16.0.1/jmods/java.base.jmod", .{});
    var reader = f.reader();

    const Zip = zzip.Zip(std.fs.File.Reader);
    var zip = try Zip.init(allocator, reader);

    var root = zip.file_tree.root_dir;
    std.log.info("{s}", .{(try zip.file_tree.root_dir.getFile("classes/java/lang/Integer.class")).name});
    // var itt = root.iterate();

    // while (itt.next()) |next| {
    //     switch (next.*) {
    //         .directory => |dir| {
    //             std.log.info("Dir: {s}", .{dir.name});
    //         },
    //         .file => |file| {
    //             std.log.info("File: {s}", .{file.name});
    //         },
    //     }
    // }

    // while (try zip.next()) {
    //     switch (section) {
    //         .local_file_header => |*file| {
    //             std.log.info("Reading {s}", .{file.readFilenameArrayList(reader, &buf)});
    //             _ = try file.readExtraFieldArrayList(reader, &buf);

    //             if (file.needsDataDescriptor()) {
    //                 var start_of_data = try reader.context.getPos();
    //                 var desc = try file.parseDataDescriptor(reader);

    //                 file.uncompressed_checksum = desc.uncompressed_checksum;
    //                 file.compressed_size = desc.compressed_size;
    //                 file.uncompressed_size = desc.uncompressed_size;

    //                 try reader.context.seekTo(start_of_data);

    //                 var d = try file.decompressArrayList(reader, &buf);
    //                 var h = std.hash.Crc32.hash(d);

    //                 if (h != file.uncompressed_checksum) @panic("Oh no the impostor vented!!");
    //             } else {
    //                 var d = try file.decompressArrayList(reader, &buf);
    //                 var h = std.hash.Crc32.hash(d);

    //                 if (h != file.uncompressed_checksum) @panic("Oh no the impostor vented!!");
    //             }
    //         },
    //         .central_directory_header => |cdh| {
    //             std.log.info("{s}", .{cdh.readFilenameArrayList(reader, &buf)});
    //             std.log.info("{s}", .{cdh.readExtraFieldArrayList(reader, &buf)});
    //             std.log.info("{s}", .{cdh.readFileCommentArrayList(reader, &buf)});
    //         },
    //         .end_central_directory_record => |cdh| {
    //             std.log.info("Sussy wussy amongus!! {s}", .{cdh});
    //             break;
    //         },
    //     }
    // }
}
