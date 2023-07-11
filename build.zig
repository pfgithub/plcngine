const std = @import("std");
const mach = @import("libs/mach/build.zig");
const zmath = @import("libs/zmath/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = mach.Options{ .core = .{
        .gpu_dawn_options = .{
            .from_source = b.option(bool, "dawn-from-source", "Build Dawn from source") orelse false,
            .debug = b.option(bool, "dawn-debug", "Use a debug build of Dawn") orelse false,
        },
    } };

    //const exe = b.addExecutable(.{
    //    .name = "plcngine",
    //    .root_source_file = .{ .path = "src/main.zig" },
    //    .target = target,
    //    .optimize = optimize,
    //});
    //exe.linkLibC();
    //exe.linkSystemLibrary("raylib");
    //b.installArtifact(exe);

    const app = try mach.App.init(b, .{
        .name = "plcngine",
        .src = "src/main2.zig",
        .target = target,
        .deps = &[_]std.build.ModuleDependency{
            .{
                .name = "zigimg",
                .module = b.createModule(.{.source_file = .{.path = "libs/zigimg/zigimg.zig"}}),
            },
            .{
                .name = "zmath",
                .module = zmath.package(b, target, optimize, .{
                    .options = .{ .enable_cross_platform_determinism = true },
                }).zmath,
            },
        },
        .optimize = optimize,
    });
    try app.link(options);
    app.install();

    const run_cmd = app.addRunArtifact();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
