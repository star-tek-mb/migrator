const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite3_dep = b.dependency("sqlite3", .{ .target = target, .optimize = optimize });
    const pgz_dep = b.dependency("pgz", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "migrator",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkLibrary(sqlite3_dep.artifact("sqlite3"));
    exe.addModule("pgz", pgz_dep.module("pgz"));
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
