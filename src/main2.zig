const world_import = @import("world.zig");
const render_import = @import("render.zig");
const World = world_import.World;
const Render = render_import.Render;

const std = @import("std");
const mach = @import("mach");
const gpu = mach.gpu;
const zm = @import("zmath");
const zigimg = @import("zigimg");
const assets = struct {
    const gotta_go_fast_image = @embedFile("gotta-go-fast.png");
};

const Vertex = extern struct {
    pos: @Vector(4, f32),
    uv: @Vector(2, f32),
};

const vertices = [_]Vertex{
    .{ .pos = .{ -0.5, -0.5, 0, 1 }, .uv = .{ 0, 1 } },
    .{ .pos = .{ 0.5, -0.5, 0, 1 }, .uv = .{ 1, 1 } },
    .{ .pos = .{ -0.5, 0.5, 0, 1 }, .uv = .{ 0, 0 } },

    .{ .pos = .{ -0.5, 0.5, 0, 1 }, .uv = .{ 0, 0 } },
    .{ .pos = .{ 0.5, -0.5, 0, 1 }, .uv = .{ 1, 1 } },
    .{ .pos = .{ 0.5, 0.5, 0, 1 }, .uv = .{ 1, 0 } },
};

pub const App = @This();

const UniformBufferObject = struct {
    color: u32,
};
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

core: mach.Core,
timer: mach.Timer,
fps_timer: mach.Timer,
window_title_timer: mach.Timer,
pipeline: *gpu.RenderPipeline,
queue: *gpu.Queue,
depth_texture: ?*gpu.Texture,
depth_texture_view: ?*gpu.TextureView,
cube_texture_view: *gpu.TextureView,

world: *World,
render: *Render,

pub fn init(app: *App) !void {
    const allocator = gpa.allocator();
    try app.core.init(allocator, .{});

    // fn (ctx: @TypeOf(context), typ: ErrorType, message: [*:0]const u8) callconv(.Inline) void
    app.core.device().setUncapturedErrorCallback(app, struct{fn a(ctx: *App, typ: gpu.ErrorType, message: [*:0]const u8) callconv(.Inline) void {
        _ = ctx;
        std.log.scoped(.wgpu).err("{s} / {s}", .{@tagName(typ), message});
        std.process.exit(1);
    }}.a);

    app.world = try World.create(allocator);
    errdefer app.world.destroy();
    app.render = try Render.create(allocator, app.world, app);
    errdefer app.render.destroy();

    const shader_module = app.core.device().createShaderModuleWGSL("shader.wgsl", @embedFile("shader.wgsl"));
    defer shader_module.release();

    const vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x4, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 1 },
    };
    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Vertex),
        .step_mode = .vertex,
        .attributes = &vertex_attributes,
    });

    const blend = gpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .zero,
        },
    };
    const color_target = gpu.ColorTargetState{
        .format = app.core.descriptor().format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        // Enable depth testing so that the fragment closest to the camera
        // is rendered in front.
        .depth_stencil = &.{
            .format = .depth24_plus,
            .depth_write_enabled = true,
            .depth_compare = .less,
        },
        .vertex = gpu.VertexState.init(.{
            .module = shader_module,
            .entry_point = "vertex_main",
            .buffers = &.{vertex_buffer_layout},
        }),
        .primitive = .{
            // Backface culling since the cube is solid piece of geometry.
            // Faces pointing away from the camera will be occluded by faces
            // pointing toward the camera.
            .cull_mode = .back,
        },
        // .multisample = .{
        //     .count = 4,
        // },
    };
    const pipeline = app.core.device().createRenderPipeline(&pipeline_descriptor);

    const queue = app.core.device().getQueue();
    var img = try zigimg.Image.fromMemory(allocator, assets.gotta_go_fast_image);
    defer img.deinit();
    const img_size = gpu.Extent3D{ .width = @as(u32, @intCast(img.width)), .height = @as(u32, @intCast(img.height)) };
    const cube_texture = app.core.device().createTexture(&.{
        .size = img_size,
        .format = .rgba8_unorm,
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
            .render_attachment = true,
        },
    });
    const data_layout = gpu.Texture.DataLayout{
        .bytes_per_row = @as(u32, @intCast(img.width * 4)),
        .rows_per_image = @as(u32, @intCast(img.height)),
    };
    switch (img.pixels) {
        .rgba32 => |pixels| queue.writeTexture(&.{ .texture = cube_texture }, &data_layout, &img_size, pixels),
        .rgb24 => |pixels| {
            const data = try rgb24ToRgba32(allocator, pixels);
            defer data.deinit(allocator);
            queue.writeTexture(&.{ .texture = cube_texture }, &data_layout, &img_size, data.rgba32);
        },
        else => @panic("unsupported image color format"),
    }
    app.cube_texture_view = cube_texture.createView(&gpu.TextureView.Descriptor{});

    app.timer = try mach.Timer.start();
    app.fps_timer = try mach.Timer.start();
    app.window_title_timer = try mach.Timer.start();
    app.pipeline = pipeline;
    app.queue = queue;
    app.depth_texture = null;
    app.depth_texture_view = null;

    app.core.device().tick();
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();

    if(app.depth_texture) |dt| dt.release();
    if(app.depth_texture_view) |dtv| dtv.release();
    app.render.destroy();
    app.world.destroy();
}

pub fn update(app: *App) !bool {
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                _ = ev;
                std.debug.print("vsync mode changed to {s}\n", .{@tagName(app.core.vsync())});
                // switch (ev.key) {
                //     .space => return true,
                //     .one => app.core.setVSync(.none),
                //     .two => app.core.setVSync(.double),
                //     .three => app.core.setVSync(.triple),
                //     else => {},
                // }
                // std.debug.print("vsync mode changed to {s}\n", .{@tagName(app.core.vsync())});
            },
            .framebuffer_resize => {
                // If window is resized, recreate depth buffer otherwise we cannot use it.
                if(app.depth_texture) |dt| dt.release();
                app.depth_texture = null;

                if(app.depth_texture_view) |dtv| dtv.release();
                app.depth_texture_view = null;
            },
            .close => return true,
            else => {},
        }
    }

    if(app.depth_texture == null and app.depth_texture_view == null) {
        app.depth_texture = app.core.device().createTexture(&gpu.Texture.Descriptor{
            .size = gpu.Extent3D{
                .width = app.core.descriptor().width,
                .height = app.core.descriptor().height,
            },
            .format = .depth24_plus,
            .usage = .{
                .render_attachment = true,
                .texture_binding = true,
            },
        });
        app.depth_texture_view = app.depth_texture.?.createView(&gpu.TextureView.Descriptor{
            .format = .depth24_plus,
            .dimension = .dimension_2d,
            .array_layer_count = 1,
            .mip_level_count = 1,
        });
    }

    const back_buffer_view = app.core.swapChain().getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 0.0 },
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = app.core.device().createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
        .depth_stencil_attachment = &.{
            .view = app.depth_texture_view.?,
            .depth_clear_value = 1.0,
            .depth_load_op = .clear,
            .depth_store_op = .store,
        },
    });

    const vertex_buffer = app.core.device().createBuffer(&.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = @sizeOf(Vertex) * vertices.len,
        .mapped_at_creation = false,
    });
    defer vertex_buffer.release();
    encoder.writeBuffer(vertex_buffer, 0, vertices[0..]);


    const uniform_buffer = app.core.device().createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(UniformBufferObject),
        .mapped_at_creation = false,
    });
    defer uniform_buffer.release();

    // Create a sampler with linear filtering for smooth interpolation.
    const sampler = app.core.device().createSampler(&.{
        .mag_filter = .nearest,
        .min_filter = .nearest,
    });
    defer sampler.release();

    const bind_group = app.core.device().createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .layout = app.pipeline.getBindGroupLayout(0),
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(UniformBufferObject)),
                gpu.BindGroup.Entry.sampler(1, sampler),
                gpu.BindGroup.Entry.textureView(2, app.cube_texture_view),
            },
        }),
    );
    defer bind_group.release();

    const ubo = UniformBufferObject{
        // .mat = zm.transpose(mvp),
        .color = 0xFF0000FF,
    };
    encoder.writeBuffer(uniform_buffer, 0, &[_]UniformBufferObject{ubo});

    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setVertexBuffer(0, vertex_buffer, 0, @sizeOf(Vertex) * vertices.len);
    pass.setBindGroup(0, bind_group, &.{});
    pass.draw(vertices.len, 1, 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    app.core.swapChain().present();
    back_buffer_view.release();

    // const delta_time = app.fps_timer.read();
    // app.fps_timer.reset();
    // var buf: [32]u8 = undefined;
    // const title = try std.fmt.bufPrintZ(&buf, "Textured Cube [ FPS: {d} ]", .{@floor(1 / delta_time)});
    // app.core.setTitle(title);
    // if (app.window_title_timer.read() >= 1.0) {
    //     app.window_title_timer.reset();
    // }

    app.core.device().tick();

    return false;
}

fn rgb24ToRgba32(allocator: std.mem.Allocator, in: []zigimg.color.Rgb24) !zigimg.color.PixelStorage {
    const out = try zigimg.color.PixelStorage.init(allocator, .rgba32, in.len);
    var i: usize = 0;
    while (i < in.len) : (i += 1) {
        out.rgba32[i] = zigimg.color.Rgba32{ .r = in[i].r, .g = in[i].g, .b = in[i].b, .a = 255 };
    }
    return out;
}
