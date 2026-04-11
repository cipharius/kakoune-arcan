const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const arcan = b.dependency("arcan", .{
        .target = target,
        .optimize = optimize,

        .static = true,

        .build_shmif = true,
        .build_tui = true,
        .build_a12 = false,
    });

    const aka = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    aka.addImport("arcan", arcan.module("arcan"));

    const exe = b.addExecutable(.{
        .name = "aka",
        .root_module = aka,
    });
    exe.linkLibrary(arcan.artifact("arcan_shmif"));
    exe.linkLibrary(arcan.artifact("arcan_tui"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .name = "aka-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
