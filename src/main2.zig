const world_import = @import("world.zig");
const render_import = @import("render.zig");
const World = world_import.World;
const Render = render_import.Render;
const math = @import("math.zig");
const FramerateCounter = @import("util/framerate_counter.zig");
const Tool = @import("tools/Tool.zig");
const DrawTool = @import("tools/DrawTool.zig");
const FillTool = @import("tools/FillTool.zig");
const platformer = @import("platformer.zig");

const imgui = @import("zig-imgui");
const imgui_mach = imgui.backends.mach;

const Player = platformer.Player;
const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vi2f = math.vi2f;
const vf2i = math.vf2i;

const std = @import("std");
const core = @import("mach").core;
const gpu = core.gpu;
const zm = @import("zmath");
const zigimg = @import("zigimg");
const assets = struct {
    const gotta_go_fast_image = @embedFile("gotta-go-fast.png");
};

// this does not have to be extern as @offsetOf is used
pub const Vertex = struct {
    position: @Vector(2, f32),
    uv: @Vector(2, f32),
    draw_colors: u32,
};

pub const App = @This();

// this has to be extern, offsets are never used?
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
// audio_ctx: sysaudio.Context,
// player: sysaudio.Player,
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
// const sample_count = 4;
const sample_count = 1;

pub var instance: *App = undefined;
pub fn init(app: *App) !void {
    try core.init(.{});
    instance = app;

    core.setFrameRateLimit(60);

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

    // app.audio_ctx = try sysaudio.Context.init(null, core.allocator, .{});
    // errdefer app.audio_ctx.deinit();
    // try app.audio_ctx.refresh();

    // const device = app.audio_ctx.defaultDevice(.playback) orelse return error.NoDeviceFound;
    // app.player = try app.audio_ctx.createPlayer(device, writeFn, .{ .user_data = app });
    // errdefer app.player.deinit();
    // try app.player.start();

    const shader_module = core.device.createShaderModuleWGSL("shaders/ui.wgsl", @embedFile("shaders/ui.wgsl"));
    defer shader_module.release();

    const vertex_attributes = [_]gpu.VertexAttribute{
        .{.format = .float32x2, .offset = @offsetOf(Vertex, "position"), .shader_location = 0},
        .{.format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 1},
        .{.format = .uint32, .offset = @offsetOf(Vertex, "draw_colors"), .shader_location = 2},
        // .{ .format = .float32x4, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
        // .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 1 },
        // .{ .format = .uint32, .offset = @offsetOf(Vertex, "draw_colors"), .shader_location = 2 },
        // .{ .format = .float32x2, .offset = @offsetOf(Vertex, "rect_uv"), .shader_location = 3 },

        // .{ .format = .float32x2, .offset = @offsetOf(Vertex, "corner_1"), .shader_location = 4 },
        // .{ .format = .float32x2, .offset = @offsetOf(Vertex, "corner_2"), .shader_location = 5 },
        // .{ .format = .float32x2, .offset = @offsetOf(Vertex, "corner_3"), .shader_location = 6 },
        // .{ .format = .float32x2, .offset = @offsetOf(Vertex, "corner_4"), .shader_location = 7 },

        // .{ .format = .float32, .offset = @offsetOf(Vertex, "border_t"), .shader_location = 8 },
        // .{ .format = .float32, .offset = @offsetOf(Vertex, "border_r"), .shader_location = 9 },
        // .{ .format = .float32, .offset = @offsetOf(Vertex, "border_b"), .shader_location = 10 },
        // .{ .format = .float32, .offset = @offsetOf(Vertex, "border_l"), .shader_location = 11 },
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

    {
        // imgui.setZigAllocator(&core.allocator);
        _ = imgui.createContext(null);
        try imgui_mach.init(core.allocator, core.device, .{});

        var io = imgui.getIO();
        io.config_windows_move_from_title_bar_only = true;
        io.config_flags |= imgui.ConfigFlags_NavEnableKeyboard | imgui.ConfigFlags_DockingEnable;
    }

    core.device.tick();
}

pub fn deinit(app: *App) void {
    defer core.deinit();

    // app.player.deinit();
    // app.audio_ctx.deinit();
    if(app.texture) |dt| dt.release();
    if(app.texture_view) |dtv| dtv.release();
    app.render.destroy();
    app.controller.destroy();
    app.world.destroy();

    imgui_mach.shutdown();
    imgui.destroyContext(null);
}

fn writeFn(app_op: ?*anyopaque, frames: usize) void {
    const app: *App = @as(*App, @ptrCast(@alignCast(app_op)));

    for (0..frames) |frame| {
        const sample: f32 = 0;
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
        _ = imgui_mach.processEvent(event);
        const io = imgui.getIO();
        switch(event) {
            .key_press => |ev| {
                if(!io.want_capture_keyboard) {
                    ih.keys_held.set(ev.key, true);
                    ih.frame.key_press.set(ev.key, true);
                }
            },
            .key_repeat => |ev| {
                if(!io.want_capture_keyboard) {
                    ih.frame.key_repeat.set(ev.key, true);
                }
            },
            .key_release => |ev| {
                ih.keys_held.set(ev.key, false);
                if(!io.want_capture_keyboard) {
                    ih.frame.key_release.set(ev.key, true);
                }
            },
            .mouse_press => |ev| {
                if(!io.want_capture_mouse) {
                    ih.mouse_held.set(ev.button, true);
                    ih.frame.mouse_press.set(ev.button, true);
                }
                const new_pos = Vec2f32{@floatCast(ev.pos.x), @floatCast(ev.pos.y)};
                if(ih.mouse_pos) |prev_pos| ih.frame.mouse_delta += new_pos - prev_pos;
                ih.mouse_pos = new_pos;
            },
            .mouse_release => |ev| {
                ih.mouse_held.set(ev.button, false);
                if(!io.want_capture_mouse) {
                    ih.frame.mouse_release.set(ev.button, true);
                }

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
                if(!io.want_capture_mouse) {
                    ih.frame.mouse_scroll += Vec2f32{ev.xoffset, ev.yoffset};
                }
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

    data: struct {
        primary_color: u8 = 1,
        secondary_color: u8 = 0,
    } = .{},

    play_mode: bool = false,
    player: Player = .{},
    player_cam_v: Vec2f32 = .{0, 0},

    timer: ?std.time.Timer = null,
    ns: u64 = 0,

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
        controller.draw_tool_data.deinit();
        controller.fill_tool_data.deinit();

        const alloc = controller.alloc;
        alloc.destroy(controller);
    }

    fn update(controller: *Controller, app: *App) !void {
        const ih = &app.ih;

        if(ih.frame.key_press.get(.tab) and ih.modsEql(.{})) {
            controller.play_mode = !controller.play_mode;
            if(controller.play_mode) {
                controller.player_cam_v = app.render.center_offset + (controller.player.pos - app.render.center_offset) * Vec2f32{2, 2};
            }
        }

        if(!controller.play_mode) {
            try controller.updateEditMode(app);
        }
    }
    fn tick(controller: *Controller, app: *App) !void {
        if(controller.timer == null) {
            controller.timer = try std.time.Timer.start();
        }
        const delta_time = controller.timer.?.lap();
        controller.ns += delta_time;
        const ns_per_frame = 16666666;
        for(0..4) |_| {
            if(controller.ns > ns_per_frame) {
                controller.ns -= ns_per_frame;
                try controller.tickNow(app);
            }else break;
        } else {
            controller.ns = 0;
        }
        try controller.updateView(delta_time, app);
    }
    fn tickNow(controller: *Controller, app: *App) !void {
        if(controller.play_mode) {
            try controller.tickPlayMode(app);
        }
    }
    fn updateView(controller: *Controller, delta_time_ns: u64, app: *App) !void {
        const render = app.render;

        if(controller.play_mode) {
            const target_offset = controller.player.pos - (vi2f(controller.player.size) / Vec2f32{2, 2});
            const target_zoom = 4.0;

            const offset_dist = controller.player_cam_v - target_offset;
            const zoom_dist = render.center_scale - target_zoom;

            const delta_time_sec: f32 = @floatCast(@as(f64, @floatFromInt(delta_time_ns)) / 1e+9);

            const delta_zoom = std.math.pow(f32, 0.01, delta_time_sec);
            const delta_pan = std.math.pow(f32, 0.001, delta_time_sec);

            // [camera] [player] [target_camera_pos]
            controller.player_cam_v = offset_dist * Vec2f32{delta_pan, delta_pan} + target_offset;
            render.center_offset = controller.player_cam_v + (controller.player.pos - controller.player_cam_v) * Vec2f32{2, 2};
            // TODO:    ensure player is always within central camera square
            render.center_scale = zoom_dist * delta_zoom + target_zoom;
        }
    }
    fn tickPlayMode(controller: *Controller, app: *App) !void {
        const ih = &app.ih;

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
        if(ih.frame.key_press.get(.w) and ih.modsEql(.{})) {
            std.log.info("{d}", .{render.screenToWorldPos(mp)});
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
    var events_count: usize = 0;
    while (iter.next()) |event| : (events_count += 1) {
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
    if(events_count == 0) {
        app.ih.startFrame();
        app.render.window_size = .{
            @floatFromInt(core.descriptor.width),
            @floatFromInt(core.descriptor.height),
        };
        try app.controller.update(app);
    }
    try app.controller.tick(app);
    try app.appTick();

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

    imblk: {
        imgui_mach.newFrame() catch break :imblk;
        imgui.newFrame();

        _ = imgui.dockSpaceOverViewportEx(null, imgui.DockNodeFlags_PassthruCentralNode, null);

        imgui.showDemoWindow(null);

        if(imgui.begin("Demo", null, 0)) {
            if(imgui.button("Save")) {
                try app.world.saveAll();
            }
            if(imgui.button("Line Tool")) {
                app.controller.current_tool = Tool.wrap(DrawTool, &app.controller.draw_tool_data);
            }
            if(imgui.button("Fill Tool")) {
                app.controller.current_tool = Tool.wrap(FillTool, &app.controller.fill_tool_data);
            }

            imgui.text("Colors:");
            for(&app.render.colors, [_][:0]const u8{"1", "2", "3", "4"}) |*color, label| {
                var imcolor: [3]f32 = .{color.*[0], color.*[1], color.*[2]};
                imgui.sameLine();
                _ = imgui.colorEdit3(label, &imcolor, imgui.ColorEditFlags_NoInputs | imgui.ColorEditFlags_NoLabel | imgui.ColorEditFlags_PickerHueWheel);
                color.* = .{imcolor[0], imcolor[1], imcolor[2], color.*[3]};
            }

            {
                const ih = &app.ih;
                const target_color_opt: ?*u8 = if(ih.modsEql(.{})) (
                    &app.controller.data.primary_color
                ) else if(ih.modsEql(.{.shift = true})) (
                    &app.controller.data.secondary_color
                ) else null;
                if(target_color_opt) |target_color| {
                    if(ih.frame.key_press.get(.zero)) target_color.* = 0;
                    if(ih.frame.key_press.get(.one)) target_color.* = 1;
                    if(ih.frame.key_press.get(.two)) target_color.* = 2;
                    if(ih.frame.key_press.get(.three)) target_color.* = 3;
                    if(ih.frame.key_press.get(.four)) target_color.* = 4;
                }
            }

            imgui.text("Primary:");
            if(imgui.colorButton("primary-0", .{.x = 0, .y = 0, .z = 0, .w = 0}, 0)) app.controller.data.primary_color = 0;
            imgui.sameLine();
            if(imgui.colorButton("primary-1", .{.x = app.render.colors[0][0], .y = app.render.colors[0][1], .z = app.render.colors[0][2], .w = 1.0}, 0)) app.controller.data.primary_color = 1;
            imgui.sameLine();
            if(imgui.colorButton("primary-2", .{.x = app.render.colors[1][0], .y = app.render.colors[1][1], .z = app.render.colors[1][2], .w = 1.0}, 0)) app.controller.data.primary_color = 2;
            imgui.sameLine();
            if(imgui.colorButton("primary-3", .{.x = app.render.colors[2][0], .y = app.render.colors[2][1], .z = app.render.colors[2][2], .w = 1.0}, 0)) app.controller.data.primary_color = 3;
            imgui.sameLine();
            if(imgui.colorButton("primary-4", .{.x = app.render.colors[3][0], .y = app.render.colors[3][1], .z = app.render.colors[3][2], .w = 1.0}, 0)) app.controller.data.primary_color = 4;
            imgui.text("Secondary:");
            if(imgui.colorButton("secondary-0", .{.x = 0, .y = 0, .z = 0, .w = 0}, 0)) app.controller.data.secondary_color = 0;
            imgui.sameLine();
            if(imgui.colorButton("secondary-1", .{.x = app.render.colors[0][0], .y = app.render.colors[0][1], .z = app.render.colors[0][2], .w = 1.0}, 0)) app.controller.data.secondary_color = 1;
            imgui.sameLine();
            if(imgui.colorButton("secondary-2", .{.x = app.render.colors[1][0], .y = app.render.colors[1][1], .z = app.render.colors[1][2], .w = 1.0}, 0)) app.controller.data.secondary_color = 2;
            imgui.sameLine();
            if(imgui.colorButton("secondary-3", .{.x = app.render.colors[2][0], .y = app.render.colors[2][1], .z = app.render.colors[2][2], .w = 1.0}, 0)) app.controller.data.secondary_color = 3;
            imgui.sameLine();
            if(imgui.colorButton("secondary-4", .{.x = app.render.colors[3][0], .y = app.render.colors[3][1], .z = app.render.colors[3][2], .w = 1.0}, 0)) app.controller.data.secondary_color = 4;

            try app.controller.current_tool.renderUI(app);
        }
        imgui.end();

        imgui.render();
    }

    const encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });

    try app.render.prepareApp(encoder);

    const pass: *gpu.RenderPassEncoder = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    try app.render.renderApp(pass);
    imgui_mach.renderDrawData(imgui.getDrawData().?, pass) catch {};
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
