const std = @import("std");

const test_names = .{"zip"};

pub fn build(b: *std.build.Builder) void {
    const tests = b.addTest("src/main.zig");

    const run_tests = b.step("test", "Run library tests");
    run_tests.dependOn(&tests.step);

    inline for (test_names) |name| {
        const exe = b.addExecutable(b.fmt("zarc-{s}", .{name}), b.fmt("tests/{s}.zig", .{name}));
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
