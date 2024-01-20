const std = @import("std");

const test_names = .{ "zip", "tar" };

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.step("test", "Run library tests");
    run_tests.dependOn(&tests.step);

    inline for (test_names) |name| {
        const exe = b.addExecutable(.{
            .name = b.fmt("zarc-{s}", .{name}),
            .root_source_file = .{ .path = b.fmt("tests/{s}.zig", .{name}) },
            .target = target,
            .optimize = optimize,
        });

        exe.addAnonymousModule("zarc", .{
            .source_file = .{ .path = "src/main.zig" },
        });
        const install_exe_step = b.addInstallArtifact(exe);
        b.getInstallStep().dependOn(&install_exe_step.step);

        const run_exe = b.addRunArtifact(exe);
        run_exe.step.dependOn(&install_exe_step.step);
        if (b.args) |args| {
            run_exe.addArgs(args);
        }

        const run_step = b.step(b.fmt("run-{s}", .{name}), b.fmt("Run the {s} format tests", .{name}));
        run_step.dependOn(&run_exe.step);
    }
}
