const std = @import("std");
const mach = @import("libs/mach/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
        },
        .optimize = optimize,
    });
    try app.link(.{});

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);
}
