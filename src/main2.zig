const world_import = @import("world.zig");
const render_import = @import("render.zig");
const World = world_import.World;
const Render = render_import.Render;
const math = @import("math.zig");
const FramerateCounter = @import("util/framerate_counter.zig");
const sysaudio = @import("mach-sysaudio");
const Tool = @import("tools/Tool.zig");
const DrawTool = @import("tools/DrawTool.zig");
const FillTool = @import("tools/FillTool.zig");
const platformer = @import("platformer.zig");

const Player = platformer.Player;
const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vi2f = math.vi2f;
const vf2i = math.vf2i;

const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const zm = @import("zmath");
const zigimg = @import("zigimg");
const assets = struct {
    const gotta_go_fast_image = @embedFile("gotta-go-fast.png");
};

pub const Vertex = extern struct {
    pos: @Vector(4, f32),
    uv: @Vector(2, f32),
    draw_colors: u32,
    rect_uv: @Vector(2, f32),

    corner_1: @Vector(2, f32),
    corner_2: @Vector(2, f32),
    corner_3: @Vector(2, f32),
    corner_4: @Vector(2, f32),

    border_t: f32,
    border_r: f32,
    border_b: f32,
    border_l: f32,
};

pub const App = @This();

pub const UniformBufferObject = extern struct {
    screen_size: @Vector(2, f32),
    colors: [4]@Vector(4, f32),
};

// timer: mach.Timer,
// fps_timer: mach.Timer,
// window_title_timer: mach.Timer,
pipeline: *gpu.RenderPipeline,
queue: *gpu.Queue,
texture: ?*gpu.Texture,
texture_view: ?*gpu.TextureView,
audio_ctx: sysaudio.Context,
player: sysaudio.Player,
title_buf: [32:0]u8,

world: *World,
render: *Render,
ih: InputHelper,
controller: *Controller,
frc: FramerateCounter,

/// we want SSAA not MSAA. MSAA only runs the fragment shader once per pixel using the
/// center of the pixel. We want to supersample the fragment shader (2-4 samples per pixel)
/// to get smooth pixel art when at edges.
///
/// https://godotshaders.com/shader/smooth-3d-pixel-filtering/
const sample_count = 4;

pub var instance: *App = undefined;
pub fn init(app: *App) !void {
    try core.init(.{});
    instance = app;

    // fn (ctx: @TypeOf(context), typ: ErrorType, message: [*:0]const u8) callconv(.Inline) void
    core.device.setUncapturedErrorCallback(app, struct{fn a(ctx: *App, typ: gpu.ErrorType, message: [*:0]const u8) callconv(.Inline) void {
        _ = ctx;
        std.log.scoped(.wgpu).err("{s} / {s}", .{@tagName(typ), message});
        std.process.exit(1);
    }}.a);

    app.title_buf = std.mem.zeroes([32:0]u8);

    app.world = try World.create(core.allocator);
    errdefer app.world.destroy();
    app.render = try Render.create(core.allocator, app.world, app);
    errdefer app.render.destroy();

    app.audio_ctx = try sysaudio.Context.init(null, core.allocator, .{});
    errdefer app.audio_ctx.deinit();
    try app.audio_ctx.refresh();

    const device = app.audio_ctx.defaultDevice(.playback) orelse return error.NoDeviceFound;
    app.player = try app.audio_ctx.createPlayer(device, writeFn, .{ .user_data = app });
    errdefer app.player.deinit();
    try app.player.start();

    const shader_module = core.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shaders/indexed_image.wgsl"));
    defer shader_module.release();

    const vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x4, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 1 },
        .{ .format = .uint32, .offset = @offsetOf(Vertex, "draw_colors"), .shader_location = 2 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "rect_uv"), .shader_location = 3 },

        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "corner_1"), .shader_location = 4 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "corner_2"), .shader_location = 5 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "corner_3"), .shader_location = 6 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "corner_4"), .shader_location = 7 },

        .{ .format = .float32, .offset = @offsetOf(Vertex, "border_t"), .shader_location = 8 },
        .{ .format = .float32, .offset = @offsetOf(Vertex, "border_r"), .shader_location = 9 },
        .{ .format = .float32, .offset = @offsetOf(Vertex, "border_b"), .shader_location = 10 },
        .{ .format = .float32, .offset = @offsetOf(Vertex, "border_l"), .shader_location = 11 },
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
        .format = core.descriptor.format,
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
    const pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

    const queue = core.device.getQueue();

    app.controller = try Controller.create(core.allocator);
    errdefer app.controller.destroy();

    // app.timer = try mach.Timer.start();
    // app.fps_timer = try mach.Timer.start();
    // app.window_title_timer = try mach.Timer.start();
    app.pipeline = pipeline;
    app.queue = queue;
    app.ih = .{};
    app.texture = null;
    app.texture_view = null;
    app.frc = FramerateCounter.init();

    core.device.tick();
}

pub fn deinit(app: *App) void {
    defer core.deinit();

    app.player.deinit();
    app.audio_ctx.deinit();
    if(app.texture) |dt| dt.release();
    if(app.texture_view) |dtv| dtv.release();
    app.render.destroy();
    app.controller.destroy();
    app.world.destroy();
}

fn writeFn(app_op: ?*anyopaque, frames: usize) void {
    const app: *App = @as(*App, @ptrCast(@alignCast(app_op)));

    for (0..frames) |frame| {
        var sample: f32 = 0;
        // sample rate = app.player.sampleRate()

        // Emit the sample on all channels.
        app.player.writeAll(frame, sample);
    }
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
    keys_held: EnumBitSet(core.Key) = EnumBitSet(core.Key).initEmpty(),
    mouse_held: EnumBitSet(core.MouseButton) = EnumBitSet(core.MouseButton).initEmpty(),
    mouse_pos: ?Vec2f32 = null,

    frame: struct {
        key_press: EnumBitSet(core.Key) = EnumBitSet(core.Key).initEmpty(),
        key_repeat: EnumBitSet(core.Key) = EnumBitSet(core.Key).initEmpty(),
        key_release: EnumBitSet(core.Key) = EnumBitSet(core.Key).initEmpty(),

        mouse_press: EnumBitSet(core.MouseButton) = EnumBitSet(core.MouseButton).initEmpty(),
        mouse_release: EnumBitSet(core.MouseButton) = EnumBitSet(core.MouseButton).initEmpty(),
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
    pub fn modsEql(ih: *const InputHelper, keys: ModKeysInit) bool {
        return ih.modifiers().eql(keys);
    }
    fn startFrame(ih: *InputHelper) void {
        ih.frame = .{};
    }
    fn update(ih: *InputHelper, event: core.Event) !void {
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
fn appTick(app: *App) !void {
    try app.world.clearUnusedChunks();
    app.world.frame_index += 1;
}

const Controller = struct {
    alloc: std.mem.Allocator,
    draw_tool_data: DrawTool = .{},
    fill_tool_data: FillTool = .{},
    current_tool: Tool,

    play_mode: bool = false,
    player: Player = .{},

    pub fn create(alloc: std.mem.Allocator) !*Controller {
        const controller = try alloc.create(Controller);
        errdefer alloc.destroy(controller);
        controller.* = .{
            .alloc = alloc,
            .current_tool = undefined,
        };
        controller.current_tool = Tool.wrap(DrawTool, &controller.draw_tool_data);
        return controller;
    }
    pub fn destroy(controller: *Controller) void {
        const alloc = controller.alloc;
        alloc.destroy(controller);
    }

    fn update(controller: *Controller, app: *App) !void {
        const ih = &app.ih;

        if(ih.frame.key_press.get(.tab) and ih.modsEql(.{})) {
            controller.play_mode = !controller.play_mode;
        }

        if(controller.play_mode) {
            try controller.updatePlayMode(app);
        }else {
            try controller.updateEditMode(app);
        }
    }
    fn updatePlayMode(controller: *Controller, app: *App) !void {
        const render = app.render;
        const ih = &app.ih;

        render.center_offset = controller.player.pos - (vi2f(controller.player.size) / Vec2f32{2, 2});
        render.center_scale = 4.0;

        try controller.player.update(app.world, &.{
            .up_held = ih.keys_held.get(.w),
            .left_held = ih.keys_held.get(.a),
            .down_held = ih.keys_held.get(.s),
            .right_held = ih.keys_held.get(.d),

            .jump_held = ih.keys_held.get(.space),
            .dash_held = ih.mouse_held.get(.left),
        });
    }
    fn updateEditMode(controller: *Controller, app: *App) !void {
        const render = app.render;
        const ih = &app.ih;

        const mp = app.ih.mouse_pos orelse Vec2f32{-1, -1};

        if(ih.frame.key_press.get(.b) and ih.modsEql(.{})) {
            controller.current_tool = Tool.wrap(DrawTool, &controller.draw_tool_data);
        }
        if(ih.frame.key_press.get(.f) and ih.modsEql(.{})) {
            controller.current_tool = Tool.wrap(FillTool, &controller.fill_tool_data);
        }

        if(ih.frame.key_press.get(.q) and ih.modsEql(.{})) {
            controller.player.pos = render.screenToWorldPos(mp);
        }

        const mwheel_mul: Vec2f32 = .{20.0, 20.0};
        const mwheel_ray = ih.frame.mouse_scroll * mwheel_mul;
        if((ih.modsEql(.{.ctrl = true}) or ih.modsEql(.{.super = true})) and ih.frame.key_press.get(.s)) {
            try app.world.saveAll();
        }
        if(ih.modsEql(.{.ctrl = true}) or ih.modsEql(.{.alt = true})) {
            const mpos_before = render.screenToWorldPos(mp);

            const wheel: f32 = (mwheel_ray[0] + mwheel_ray[1]) / 120.0;
            const zoom: f32 = std.math.pow(f32, 1 + @abs(wheel) / 2, @as(f32, if(wheel > 0) 1 else -1));
            render.center_scale *= zoom;
            if(render.center_scale < 0.5) render.center_scale = 0.5;
            if(render.center_scale > 2048.0) render.center_scale = 2048.0;

            const mpos_after = render.screenToWorldPos(mp);
            render.center_offset -= mpos_after - mpos_before;
            if(render.center_scale == 1.0) render.center_offset = @round(render.center_offset);
        }else if(ih.keys_held.get(.left_shift) or ih.keys_held.get(.right_shift)) {
            render.center_offset -= Vec2f32{mwheel_ray[0] + mwheel_ray[1], 0} / @as(Vec2f32, @splat(render.center_scale));
        }else{
            render.center_offset -= mwheel_ray / @as(Vec2f32, @splat(render.center_scale));
        }
        if(ih.modsEql(.{.ctrl = true}) and ih.frame.key_press.get(.one)) {
            render.center_scale = 1.0;
        }
        if(ih.modsEql(.{.ctrl = true}) and ih.frame.key_press.get(.two)) {
            render.center_scale = 2.0;
        }
        if(ih.isCursorHidden()) {
            const mmove_vec = ih.frame.mouse_delta;

            render.center_offset += mmove_vec / @as(Vec2f32, @splat(render.center_scale));
        }
        if(ih.mouse_held.get(.middle) or (ih.mouse_held.get(.left) and ih.modsEql(.{.alt = true}))) {
            render.center_offset -= ih.frame.mouse_delta / @as(Vec2f32, @splat(render.center_scale));
        }

        try controller.current_tool.update(app);
    }
};

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        app.ih.startFrame();
        try app.ih.update(event);

        app.render.window_size = .{
            @floatFromInt(core.descriptor.width),
            @floatFromInt(core.descriptor.height),
        };
        try app.controller.update(app);

        switch (event) {
            .framebuffer_resize => {
                if(app.texture) |dt| dt.release();
                app.texture = null;

                if(app.texture_view) |dtv| dtv.release();
                app.texture_view = null;
            },
            .close => {
                try app.world.saveAll();
                return true;
            },
            else => {},
        }
    }

    if(app.texture == null) {
        if(app.texture != null) unreachable;
        if(app.texture_view != null) unreachable;

        app.texture = core.device.createTexture(&gpu.Texture.Descriptor{
            .size = gpu.Extent3D{
                .width = core.descriptor.width,
                .height = core.descriptor.height,
            },
            .format = core.descriptor.format,
            .usage = .{ .render_attachment = true },
            .sample_count = sample_count,
        });
        app.texture_view = app.texture.?.createView(null);
    }

    // TODO limit to 20tps:
    try app.appTick();

    // switch (ev.key) {
    //     .space => return true,
    //     .one => core.setVSync(.none),
    //     .two => core.setVSync(.double),
    //     .three => core.setVSync(.triple),
    //     else => {},
    // }

    const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = if(sample_count == 1) back_buffer_view else app.texture_view.?,
        .resolve_target = if(sample_count == 1) null else back_buffer_view,
        .clear_value = .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 0.0 },
        .load_op = .clear,
        .store_op = if(sample_count == 1) .store else .discard,
    };

    const encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });

    try app.render.prepareApp(encoder);

    const pass: *gpu.RenderPassEncoder = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    try app.render.renderApp(pass);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    app.queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swap_chain.present();
    back_buffer_view.release();

    // if(true) {
    //     const delta_time = app.fps_timer.read();
    //     app.fps_timer.reset();
    //     const title = try std.fmt.bufPrintZ(&app.title_buf, "Textured Cube [ FPS: {d:.0} ]", .{@floor(1 / delta_time)});
    //     core.setTitle(title);
    // }

    core.device.tick();

    app.frc.onFrame();
    // var buf: [64]u8 = undefined;
    // const title = try std.fmt.bufPrintZ(&buf, "plcngine [ FPS: {d:.2} ]", .{ app.frc.getFramerate() });
    // core.setTitle(title);
    // setTitle memory mut last until the main thread accepts the updated title. so uuh?

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
