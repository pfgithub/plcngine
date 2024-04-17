const std = @import("std");
const mach = @import("mach");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
        .core = true,
    });
    // const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize });
    const app = try mach.CoreApp.init(b, mach_dep.builder, .{
        .name = "plcngine",
        .src = "src/main2.zig",
        .target = target,
        .deps = &[_]std.Build.Module.Import{
            // std.Build.Module.Import{
            //     .name = "xev",
            //     .module = xev.module("xev"),
            // },
        },
        .optimize = optimize,
    });

    if (b.args) |args| app.run.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);

    // const exe = b.addExecutable(.{
    //     .name = "network",
    //     .root_source_file = .{.path = "src/testing/xevtest.zig"},
    //     .target = target,
    //     .optimize = optimize,
    //     .deps = &.{
    //         .{.name = "xev", .module = xev.module("xev")},
    //     },
    // });
    // b.installArtifact(exe);
}
