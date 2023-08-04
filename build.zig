const std = @import("std");
const mach = @import("libs/mach/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const codegen_step = std.build.Step.Run.create(b, "codegen zix");
    codegen_step.addArgs(&.{
        "bun", "src/zix_compiler.ts", "src",
    });

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
    app.compile.step.dependOn(&codegen_step.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);
}
