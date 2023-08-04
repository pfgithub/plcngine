const std = @import("std");
const mach = @import("libs/mach/build.zig");

fn linkMsdfGen(b: *std.Build, app: *std.build.Step.Compile) !void {
    _ = b;
    app.linkSystemLibrary("c++");
    app.addIncludePath("libs/msdfgen/");
    for(&[_][]const u8{
        "libs/msdfgen/core/contour-combiners.cpp",
        "libs/msdfgen/core/Contour.cpp",
        "libs/msdfgen/core/edge-coloring.cpp",
        "libs/msdfgen/core/edge-segments.cpp",
        "libs/msdfgen/core/edge-selectors.cpp",
        "libs/msdfgen/core/EdgeHolder.cpp",
        "libs/msdfgen/core/equation-solver.cpp",
        "libs/msdfgen/core/msdf-error-correction.cpp",
        "libs/msdfgen/core/MSDFErrorCorrection.cpp",
        "libs/msdfgen/core/msdfgen.cpp",
        "libs/msdfgen/core/Projection.cpp",
        "libs/msdfgen/core/rasterization.cpp",
        "libs/msdfgen/core/render-sdf.cpp",
        "libs/msdfgen/core/save-bmp.cpp",
        "libs/msdfgen/core/save-tiff.cpp",
        "libs/msdfgen/core/Scanline.cpp",
        "libs/msdfgen/core/sdf-error-estimation.cpp",
        "libs/msdfgen/core/shape-description.cpp",
        "libs/msdfgen/core/Shape.cpp",
        "libs/msdfgen/core/SignedDistance.cpp",
        "libs/msdfgen/core/Vector2.cpp",

        // "libs/msdfgen/ext/import-font.cpp",
        // "libs/msdfgen/ext/resolve-shape-geometry.cpp",
    }) |cpp_file| {
        app.addCSourceFile(cpp_file, &.{});
    }
}

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
    try linkMsdfGen(b, app.compile);
    try app.link(.{});
    app.compile.step.dependOn(&codegen_step.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);
}
