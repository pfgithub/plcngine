const std = @import("std");
const mach_core = @import("mach_core");

const build_runner = @import("root");
const deps = build_runner.dependencies;

const msdfgen_root = blk: {
    const target_str: []const u8 = for (deps.root_deps) |root_dep| {
        if (std.mem.eql(u8, root_dep[0], "msdfgen")) {
            break root_dep[1];
        }
    } else @compileError("missing root dep 'msdfgen'");
    const pkgval = @field(deps.packages, target_str);
    break :blk pkgval.build_root;
};

// TODO: move libs from submodules to package manager; search in zig-cache
// for dependencies.zig, use deps.something to find the prefix folder

fn linkMsdfGen(b: *std.Build, app: *std.build.Step.Compile) !void {
    _ = b;
    app.linkSystemLibrary("c++");
    app.addIncludePath(.{.path = msdfgen_root ++ "/"});
    app.addIncludePath(.{.path = "src/"});
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

    const mach_core_dep = b.dependency("mach_core", .{
        .target = target,
        .optimize = optimize,
    });
    const mach_freetype_dep = b.dependency("mach_freetype", .{
        .target = target,
        .optimize = optimize,
    });
    const mach_sysaudio_dep = b.dependency("mach_sysaudio", .{
        .target = target,
        .optimize = optimize,
    });
    const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize });
    const app = try mach_core.App.init(b, mach_core_dep.builder, .{
        .name = "plcngine",
        .src = "src/main2.zig",
        .target = target,
        .deps = &[_]std.build.ModuleDependency{
            std.Build.ModuleDependency{
                .name = "mach-freetype",
                .module = mach_freetype_dep.module("mach-freetype"),
            },
            std.Build.ModuleDependency{
                .name = "mach-sysaudio",
                .module = mach_sysaudio_dep.module("mach-sysaudio"),
            },
            std.Build.ModuleDependency{
                .name = "xev",
                .module = xev.module("xev"),
            },
        },
        .optimize = optimize,
    });
    @import("mach_freetype").linkFreetype(mach_freetype_dep.builder, app.compile);
    @import("mach_sysaudio").link(mach_sysaudio_dep.builder, app.compile);
    try linkMsdfGen(b, app.compile);

    if (b.args) |args| app.run.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);

    const exe = b.addExecutable(.{
        .name = "network",
        .root_source_file = .{.path = "src/testing/xevtest.zig"},
    });
    exe.addModule("xev", xev.module("xev"));
    b.installArtifact(exe);
}
