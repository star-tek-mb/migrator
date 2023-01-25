const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const sqlite3_dep = b.dependency("sqlite3", .{});

    const exe = b.addExecutable("migrator", "src/main.zig");
    exe.setTarget(target);
    exe.linkLibC();
    exe.linkLibrary(sqlite3_dep.artifact("sqlite3"));
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
