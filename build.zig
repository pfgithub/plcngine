const std = @import("std");
const mach = @import("mach");

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

fn linkMsdfGen(b: *std.Build, app: *std.Build.Module) !void {
    _ = b;
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

    const msdf_module = b.addModule("msdf", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = .{.path = "src/msdf.zig"},
        .link_libcpp = true,
    });
    const use_system_zlib = b.option(bool, "use_system_zlib", "Use system zlib") orelse false;
    const enable_brotli = b.option(bool, "enable_brotli", "Build brotli") orelse true;
    const freetype_dep = b.dependency("freetype", .{
        .target = target,
        .optimize = optimize,
        .use_system_zlib = use_system_zlib,
        .enable_brotli = enable_brotli,
    });
    msdf_module.linkLibrary(freetype_dep.artifact("freetype")); // this lib has installHeader, how can we use it instead of vvv?
    msdf_module.addIncludePath(freetype_dep.path("include"));
    try linkMsdfGen(b, msdf_module);

    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
    });
    const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize });
    const app = try mach.CoreApp.init(b, mach_dep.builder, .{
        .name = "plcngine",
        .src = "src/main2.zig",
        .target = target,
        .deps = &.{
            .{
                .name = "xev",
                .module = xev.module("xev"),
            },
            .{.name = "msdf", .module = msdf_module},
        },
        .optimize = optimize,
    });
    app.compile.addIncludePath(.{.path = "src/"});
    // const mach_freetype_dep = b.dependency("mach_freetype", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    // app.compile.root_module.addImport("mach-freetype", mach_freetype_dep.module("mach-freetype"));

    if (b.args) |args| app.run.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);

    const exe = b.addExecutable(.{
        .name = "network",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{.path = "src/testing/xevtest.zig"},
    });
    exe.root_module.addImport("xev", xev.module("xev"));
    b.installArtifact(exe);
}
