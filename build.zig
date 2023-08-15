const std = @import("std");
const mach = @import("mach");

const build_runner = @import("root");
const deps = build_runner.dependencies;

const msdfgen_root = deps.build_root.msdfgen;

// TODO: move libs from submodules to package manager; search in zig-cache
// for dependencies.zig, use deps.something to find the prefix folder

fn linkMsdfGen(b: *std.Build, app: *std.build.Step.Compile) !void {
    _ = b;
    app.linkSystemLibrary("c++");
    app.addIncludePath(.{.path = msdfgen_root ++ "/"});
    for(&[_][]const u8{
        msdfgen_root ++ "/core/contour-combiners.cpp",
        msdfgen_root ++ "/core/Contour.cpp",
        msdfgen_root ++ "/core/edge-coloring.cpp",
        msdfgen_root ++ "/core/edge-segments.cpp",
        msdfgen_root ++ "/core/edge-selectors.cpp",
        msdfgen_root ++ "/core/EdgeHolder.cpp",
        msdfgen_root ++ "/core/equation-solver.cpp",
        msdfgen_root ++ "/core/msdf-error-correction.cpp",
        msdfgen_root ++ "/core/MSDFErrorCorrection.cpp",
        msdfgen_root ++ "/core/msdfgen.cpp",
        msdfgen_root ++ "/core/Projection.cpp",
        msdfgen_root ++ "/core/rasterization.cpp",
        msdfgen_root ++ "/core/render-sdf.cpp",
        msdfgen_root ++ "/core/save-bmp.cpp",
        msdfgen_root ++ "/core/save-tiff.cpp",
        msdfgen_root ++ "/core/Scanline.cpp",
        msdfgen_root ++ "/core/sdf-error-estimation.cpp",
        msdfgen_root ++ "/core/shape-description.cpp",
        msdfgen_root ++ "/core/Shape.cpp",
        msdfgen_root ++ "/core/SignedDistance.cpp",
        msdfgen_root ++ "/core/Vector2.cpp",

        msdfgen_root ++ "/ext/import-font.cpp",
        // msdfgen_root ++ "/ext/resolve-shape-geometry.cpp",

        "src/msdfgen_glue.cpp",
    }) |cpp_file| {
        app.addCSourceFile(.{.file = .{.path = cpp_file}, .flags = &.{}});
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const codegen_step = std.build.Step.Run.create(b, "codegen zix");
    codegen_step.addArgs(&.{
        "bun", "src/zix_compiler.ts", "src",
    });

    mach.mach_glfw_import_path = "mach.mach_core.mach_glfw";
    const app = try mach.App.init(b, .{
        .name = "plcngine",
        .src = "src/main2.zig",
        .target = target,
        .deps = &[_]std.build.ModuleDependency{},
        .optimize = optimize,
    });
    app.compile.linkLibrary(b.dependency("mach_freetype.freetype", .{
        .target = target,
        .optimize = optimize,
    }).artifact("freetype"));
    try linkMsdfGen(b, app.compile);
    try app.link();
    app.compile.step.dependOn(&codegen_step.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);
}
