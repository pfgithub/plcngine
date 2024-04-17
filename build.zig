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

    const zig_imgui_dep = b.dependency("zig_imgui", .{ .target = target, .optimize = optimize });
    const imgui_module = b.addModule("zig-imgui", .{
        .root_source_file = zig_imgui_dep.path("src/imgui.zig"),
        .imports = &.{
            .{ .name = "mach", .module = mach_dep.module("mach") },
        },
    });
    const imgui_lib = b.addStaticLibrary(.{
        .name = "imgui",
        .target = target,
        .optimize = optimize,
    });
    imgui_lib.linkLibC();

    // const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize });
    const app = try mach.CoreApp.init(b, mach_dep.builder, .{
        .name = "plcngine",
        .src = "src/main2.zig",
        .target = target,
        .mach_mod = mach_dep.module("mach"),
        .deps = &[_]std.Build.Module.Import{
            .{ .name = "zig-imgui", .module = imgui_module },
            // std.Build.Module.Import{
            //     .name = "xev",
            //     .module = xev.module("xev"),
            // },
        },
        .optimize = optimize,
    });

    app.compile.linkLibrary(zig_imgui_dep.artifact("imgui"));
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
