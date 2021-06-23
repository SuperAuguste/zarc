const std = @import("std");

const test_names = .{ "zip", "tar" };

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const tests = b.addTest("src/main.zig");

    tests.setTarget(target);
    tests.setBuildMode(mode);

    const run_tests = b.step("test", "Run library tests");
    run_tests.dependOn(&tests.step);

    inline for (test_names) |name| {
        const exe = b.addExecutable(b.fmt("zarc-{s}", .{name}), b.fmt("tests/{s}.zig", .{name}));

        exe.setTarget(target);
        exe.setBuildMode(mode);

        exe.addPackagePath("zarc", "src/main.zig");
        exe.install();

        const run_exe = exe.run();
        run_exe.step.dependOn(&exe.install_step.?.step);
        if (b.args) |args| {
            run_exe.addArgs(args);
        }

        const run_step = b.step(b.fmt("run-{s}", .{name}), b.fmt("Run the {s} format tests", .{name}));
        run_step.dependOn(&run_exe.step);
    }
}
