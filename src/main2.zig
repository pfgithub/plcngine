const world_import = @import("world.zig");
const render_import = @import("render.zig");
const World = world_import.World;
const Render = render_import.Render;
const math = @import("math.zig");

const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vi2f = math.vi2f;
const vf2i = math.vf2i;

const std = @import("std");
const mach = @import("mach");
const Core = mach.Core;
const gpu = mach.gpu;
const zm = @import("zmath");
const zigimg = @import("zigimg");
const assets = struct {
    const gotta_go_fast_image = @embedFile("gotta-go-fast.png");
};

pub const Vertex = extern struct {
    pos: @Vector(4, f32),
    uv: @Vector(2, f32),
};

pub const App = @This();

pub const UniformBufferObject = extern struct {
    screen_size: @Vector(2, f32),
    colors: [4]@Vector(4, f32),
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
texture: ?*gpu.Texture,
texture_view: ?*gpu.TextureView,

world: *World,
render: *Render,
ih: InputHelper,
controller: Controller,

/// we want SSAA not MSAA. MSAA only runs the fragment shader once per pixel using the
/// center of the pixel. We want to supersample the fragment shader (2-4 samples per pixel)
/// to get smooth pixel art when at edges.
///
/// https://godotshaders.com/shader/smooth-3d-pixel-filtering/
const sample_count = 4;

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

    const shader_module = app.core.device().createShaderModuleWGSL("shader.wgsl", @embedFile("shaders/indexed_image.wgsl"));
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
        .multisample = .{
            .count = sample_count,
        },
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
    app.ih = .{};
    app.controller = .{};
    app.texture = null;
    app.texture_view = null;

    app.core.device().tick();
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer app.core.deinit();

    if(app.depth_texture) |dt| dt.release();
    if(app.depth_texture_view) |dtv| dtv.release();
    if(app.texture) |dt| dt.release();
    if(app.texture_view) |dtv| dtv.release();
    app.render.destroy();
    app.world.destroy();
}

fn EnumBitSet(comptime Enum: type) type {
    return struct {
        const Self = @This();
        const Backing = std.StaticBitSet(std.meta.fields(Enum).len);
        backing: Backing,
        pub fn initEmpty() Self {
            return .{
                .backing = Backing.initEmpty(),
            };
        }
        pub fn get(self: *const Self, v: Enum) bool {
            return self.backing.isSet(@intFromEnum(v));
        }
        pub fn set(self: *Self, v: Enum, val: bool) void {
            return self.backing.setValue(@intFromEnum(v), val);
        }
    };
}
const InputHelper = struct {
    keys_held: EnumBitSet(Core.Key) = EnumBitSet(Core.Key).initEmpty(),
    mouse_held: EnumBitSet(Core.MouseButton) = EnumBitSet(Core.MouseButton).initEmpty(),
    mouse_pos: ?Vec2f32 = null,

    frame: struct {
        key_press: EnumBitSet(Core.Key) = EnumBitSet(Core.Key).initEmpty(),
        key_repeat: EnumBitSet(Core.Key) = EnumBitSet(Core.Key).initEmpty(),
        key_release: EnumBitSet(Core.Key) = EnumBitSet(Core.Key).initEmpty(),

        mouse_press: EnumBitSet(Core.MouseButton) = EnumBitSet(Core.MouseButton).initEmpty(),
        mouse_release: EnumBitSet(Core.MouseButton) = EnumBitSet(Core.MouseButton).initEmpty(),
        mouse_scroll: Vec2f32 = .{0, 0},
        mouse_delta: Vec2f32 = .{0, 0},
    } = .{},

    const ModKeysInit = packed struct {
        ctrl: bool = false,
        alt: bool = false,
        shift: bool = false,
        super: bool = false,
        _rem: u4 = 0,
    };
    const ModKeys = enum(u8) {
        _,
        fn from(keys: ModKeysInit) ModKeys {
            return @enumFromInt(@as(u8, @bitCast(keys)));
        }
        fn to(keys: ModKeys) ModKeysInit {
            return @bitCast(keys);
        }
        fn eql(self: ModKeys, keys: ModKeysInit) bool {
            return self == ModKeys.from(keys);
        }
    };

    fn modifiers(ih: *const InputHelper) ModKeys {
        return ModKeys.from(.{
            .ctrl = ih.keys_held.get(.left_control) or ih.keys_held.get(.right_control),
            .alt = ih.keys_held.get(.left_alt) or ih.keys_held.get(.right_alt),
            .shift = ih.keys_held.get(.left_shift) or ih.keys_held.get(.right_shift),
            .super = ih.keys_held.get(.left_super) or ih.keys_held.get(.right_super),
        });
    }
    fn modsEql(ih: *const InputHelper, keys: ModKeysInit) bool {
        return ih.modifiers().eql(keys);
    }
    fn startFrame(ih: *InputHelper) void {
        ih.frame = .{};
    }
    fn update(ih: *InputHelper, event: Core.Event) !void {
        switch(event) {
            .key_press => |ev| {
                ih.keys_held.set(ev.key, true);
                ih.frame.key_press.set(ev.key, true);
            },
            .key_repeat => |ev| {
                ih.frame.key_repeat.set(ev.key, true);
            },
            .key_release => |ev| {
                ih.keys_held.set(ev.key, false);
                ih.frame.key_release.set(ev.key, true);
            },
            .mouse_press => |ev| {
                ih.mouse_held.set(ev.button, true);
                ih.frame.mouse_press.set(ev.button, true);

                const new_pos = Vec2f32{@floatCast(ev.pos.x), @floatCast(ev.pos.y)};
                if(ih.mouse_pos) |prev_pos| ih.frame.mouse_delta += new_pos - prev_pos;
                ih.mouse_pos = new_pos;
            },
            .mouse_release => |ev| {
                ih.mouse_held.set(ev.button, false);
                ih.frame.mouse_release.set(ev.button, true);

                const new_pos = Vec2f32{@floatCast(ev.pos.x), @floatCast(ev.pos.y)};
                if(ih.mouse_pos) |prev_pos| ih.frame.mouse_delta += new_pos - prev_pos;
                ih.mouse_pos = new_pos;
            },
            .mouse_motion => |ev| {
                const new_pos = Vec2f32{@floatCast(ev.pos.x), @floatCast(ev.pos.y)};
                if(ih.mouse_pos) |prev_pos| ih.frame.mouse_delta += new_pos - prev_pos;
                ih.mouse_pos = new_pos;
            },
            .mouse_scroll => |ev| {
                ih.frame.mouse_scroll = Vec2f32{ev.xoffset, ev.yoffset};
            },
            else => {},
        }
    }

    fn isCursorHidden(_: *const InputHelper) bool {
        return false;
    }
};
const Controller = struct {
    prev_world_pos: ?Vec2i = null,
    fn update(controller: *Controller, app: *App) !void {
        const render = app.render;
        const world = app.world;
        const ih = &app.ih;

        const mp = app.ih.mouse_pos orelse Vec2f32{-1, -1};

        const mwheel_mul: Vec2f32 = .{20.0, 20.0};
        const mwheel_ray = ih.frame.mouse_scroll * mwheel_mul;
        if(ih.modsEql(.{.ctrl = true}) or ih.modsEql(.{.alt = true})) {
            const mpos_before = render.screenToWorldPos(mp);

            const wheel: f32 = (mwheel_ray[0] + mwheel_ray[1]) / 120.0;
            const zoom: f32 = std.math.pow(f32, 1 + @fabs(wheel) / 2, @as(f32, if(wheel > 0) 1 else -1));
            render.center_scale *= zoom;
            if(render.center_scale < 1.0) render.center_scale = 1.0;
            if(render.center_scale > 2048.0) render.center_scale = 2048.0;

            const mpos_after = render.screenToWorldPos(mp);
            render.center_offset -= mpos_after - mpos_before;
            if(render.center_scale == 1.0) render.center_offset = @round(render.center_offset);
        }else if(ih.keys_held.get(.left_shift) or ih.keys_held.get(.right_shift)) {
            render.center_offset -= Vec2f32{mwheel_ray[0] + mwheel_ray[1], 0} / @splat(2, render.center_scale);
        }else{
            render.center_offset -= mwheel_ray / @splat(2, render.center_scale);
        }
        if(ih.isCursorHidden()) {
            const mmove_vec = ih.frame.mouse_delta;

            render.center_offset += mmove_vec / @splat(2, render.center_scale);
        }
        if(ih.mouse_held.get(.middle) or (ih.mouse_held.get(.left) and ih.modsEql(.{.alt = true}))) {
            render.center_offset -= ih.frame.mouse_delta / @splat(2, render.center_scale);
        }


        const world_pos = vf2i(render.screenToWorldPos(mp));
        if(ih.mouse_held.get(.left) and ih.modsEql(.{})) {
            if(controller.prev_world_pos == null) controller.prev_world_pos = world_pos;
            var lp = math.LinePlotter.init(controller.prev_world_pos.?, world_pos);
            while(lp.next()) |pos| {
                try world.setPixel(pos, 4);
            }
            controller.prev_world_pos = world_pos;
        }else{
            controller.prev_world_pos = null;
        }
    }
};

pub fn update(app: *App) !bool {
    var iter = app.core.pollEvents();
    while (iter.next()) |event| {
        app.ih.startFrame();
        try app.ih.update(event);

        app.render.window_size = .{
            @floatFromInt(app.core.descriptor().width),
            @floatFromInt(app.core.descriptor().height),
        };
        try app.controller.update(app);

        switch (event) {
            .framebuffer_resize => {
                // If window is resized, recreate depth buffer otherwise we cannot use it.
                if(app.depth_texture) |dt| dt.release();
                app.depth_texture = null;

                if(app.depth_texture_view) |dtv| dtv.release();
                app.depth_texture_view = null;

                if(app.texture) |dt| dt.release();
                app.texture = null;

                if(app.texture_view) |dtv| dtv.release();
                app.texture_view = null;
            },
            .close => return true,
            else => {},
        }
    }

    if(app.depth_texture == null) {
        if(app.depth_texture_view != null) unreachable;
        if(app.texture != null) unreachable;
        if(app.texture_view != null) unreachable;

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
            .sample_count = sample_count,
        });
        app.depth_texture_view = app.depth_texture.?.createView(&gpu.TextureView.Descriptor{
            .format = .depth24_plus,
            .dimension = .dimension_2d,
            .array_layer_count = 1,
            .mip_level_count = 1,
        });

        app.texture = app.core.device().createTexture(&gpu.Texture.Descriptor{
            .size = gpu.Extent3D{
                .width = app.core.descriptor().width,
                .height = app.core.descriptor().height,
            },
            .format = app.core.descriptor().format,
            .usage = .{ .render_attachment = true },
            .sample_count = sample_count,
        });
        app.texture_view = app.texture.?.createView(null);
    }

    const back_buffer_view = app.core.swapChain().getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = if(sample_count == 1) back_buffer_view else app.texture_view.?,
        .resolve_target = if(sample_count == 1) null else back_buffer_view,
        .clear_value = .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 0.0 },
        .load_op = .clear,
        .store_op = if(sample_count == 1) .store else .discard,
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

    // switch (ev.key) {
    //     .space => return true,
    //     .one => app.core.setVSync(.none),
    //     .two => app.core.setVSync(.double),
    //     .three => app.core.setVSync(.triple),
    //     else => {},
    // }

    try app.render.prepareWorld(encoder);

    const pass: *gpu.RenderPassEncoder = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    try app.render.renderWorld(pass);
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
