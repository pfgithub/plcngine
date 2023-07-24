const std = @import("std");
const math = @import("math.zig");
const world_import = @import("world.zig");
const World = world_import.World;
const Chunk = world_import.Chunk;
const CHUNK_SIZE = world_import.CHUNK_SIZE;
const App = @import("main2.zig");

const x = math.x;
const y = math.y;
const z = math.z;
const w = math.w;

const mach = @import("mach");
const gpu = mach.gpu;

const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vi2f = math.vi2f;
const vf2i = math.vf2i;

pub const RectOpts = struct {
    ul: Vec2f32,
    ur: ?Vec2f32 = null,
    bl: ?Vec2f32 = null,
    br: Vec2f32,
    draw_colors: u32, // octal literal
    border_radius: f32 = 0.0,
    border_radius_ul: ?f32 = null,
    border_radius_ur: ?f32 = null,
    border_radius_bl: ?f32 = null,
    border_radius_br: ?f32 = null,
};
pub fn vertexRect(
    opts: RectOpts,
) [6]App.Vertex {
    const ul = opts.ul;
    const ur = opts.ur orelse Vec2f32{opts.br[x], opts.ul[y]};
    const bl = opts.bl orelse Vec2f32{opts.ul[x], opts.br[y]};
    const br = opts.br;
    const draw_colors = opts.draw_colors;

    const border_radius_ul = opts.border_radius_ul orelse opts.border_radius;
    const border_radius_ur = opts.border_radius_ur orelse opts.border_radius;
    const border_radius_bl = opts.border_radius_bl orelse opts.border_radius;
    const border_radius_br = opts.border_radius_br orelse opts.border_radius;

    const hy = br[y] - ul[y];
    const hx = br[x] - ul[x];
    const corner_1 = Vec2f32{border_radius_ul / hx, border_radius_ul / hy};
    const corner_2 = Vec2f32{border_radius_ur / hx, border_radius_ur / hy};
    const corner_3 = Vec2f32{border_radius_bl / hx, border_radius_bl / hy};
    const corner_4 = Vec2f32{border_radius_br / hx, border_radius_br / hy};

    return [6]App.Vertex{
        .{ .pos = .{ ul[x], ul[y], 0, 1 }, .uv = .{ 0, 0 }, .rect_uv = .{ 0, 0 }, .draw_colors = draw_colors, .corner_1 = corner_1, .corner_2 = corner_2, .corner_3 = corner_3, .corner_4 = corner_4 },
        .{ .pos = .{ bl[x], br[y], 0, 1 }, .uv = .{ 0, 1 }, .rect_uv = .{ 0, 1 }, .draw_colors = draw_colors, .corner_1 = corner_1, .corner_2 = corner_2, .corner_3 = corner_3, .corner_4 = corner_4 },
        .{ .pos = .{ ur[x], ur[y], 0, 1 }, .uv = .{ 1, 0 }, .rect_uv = .{ 1, 0 }, .draw_colors = draw_colors, .corner_1 = corner_1, .corner_2 = corner_2, .corner_3 = corner_3, .corner_4 = corner_4 },

        .{ .pos = .{ bl[x], bl[y], 0, 1 }, .uv = .{ 0, 1 }, .rect_uv = .{ 0, 1 }, .draw_colors = draw_colors, .corner_1 = corner_1, .corner_2 = corner_2, .corner_3 = corner_3, .corner_4 = corner_4 },
        .{ .pos = .{ br[x], br[y], 0, 1 }, .uv = .{ 1, 1 }, .rect_uv = .{ 1, 1 }, .draw_colors = draw_colors, .corner_1 = corner_1, .corner_2 = corner_2, .corner_3 = corner_3, .corner_4 = corner_4 },
        .{ .pos = .{ ur[x], ur[y], 0, 1 }, .uv = .{ 1, 0 }, .rect_uv = .{ 1, 0 }, .draw_colors = draw_colors, .corner_1 = corner_1, .corner_2 = corner_2, .corner_3 = corner_3, .corner_4 = corner_4 },
    };
}

pub const ChunkRenderInfo = struct {
    // it might be possible to keep one big gpu texture and update subtextures of it:
    // UpdateTextureRec(Texture2D texture, Rectangle rec, const void *pixels)
    // say like 8192x8192
    // and then all the chunks can be drawn in one draw call
    // is that good? idk

    gpu_texture: *gpu.Texture = undefined, // last_updated 0 indicates that this is undefined and should not be used
    last_updated: u64 = 0,
    vertex_buffer: ?*gpu.Buffer = null,
    bind_group: ?*gpu.BindGroup = null,

    pub fn deinit(cri: ChunkRenderInfo) void {
        if(cri.vertex_buffer) |vb| {
            vb.release();
        }
        if(cri.bind_group) |bg| {
            bg.release();
        }
        if(cri.last_updated != 0) {
            cri.gpu_texture.release();
        }
    }
};

pub const Render = struct {
    // renderChunk, renderEntity, renderWorld
    // for all entities of visible chunks : render entities

    //camera_center: Vec2f,
    alloc: std.mem.Allocator,
    center_offset: Vec2f32 = .{0, 0},
    center_scale: f32 = 1.0,
    window_size: Vec2f32 = .{0, 0},

    uniform_buffer: ?*gpu.Buffer = null,
    ui_vertex_buffer: ?*gpu.Buffer = null,
    ui_bind_group: ?*gpu.BindGroup = null,
    ui_texture: ?*gpu.Texture = null,

    world: *World,
    app: *App,

    pub fn create(alloc: std.mem.Allocator, world: *World, app: *App) !*Render {
        const render = try alloc.create(Render);
        render.* = .{
            .alloc = alloc,
            .world = world,
            .app = app,
        };
        return render;
    }
    pub fn destroy(render: *Render) void {
        if(render.uniform_buffer) |b| b.release();
        if(render.ui_vertex_buffer) |b| b.release();
        if(render.ui_bind_group) |b| b.release();
        if(render.ui_texture) |b| b.release();
        render.alloc.destroy(render);
    }

    pub fn screenToWorldPos(render: *Render, screen_pos: Vec2f32) Vec2f32 {
        const wso2 = render.halfScreen();
        const scale = @splat(2, render.center_scale);
        return (screen_pos - wso2) / scale + render.center_offset;
    }
    pub fn worldPosToScreenPos(render: *Render, world_pos: Vec2i) Vec2f32 {
        const wso2 = render.halfScreen();
        const scale = @splat(2, render.center_scale);
        return (vi2f(world_pos) - render.center_offset) * scale + wso2;
    }
    pub fn halfScreen(render: *Render) Vec2f32 {
        return render.window_size / @splat(2, @as(f32, 2.0));
    }

    fn screenChunkBounds(render: *Render) [2]Vec2i {
        const screen_size = render.window_size;
        const ul = vf2i(render.screenToWorldPos(.{0, 0}));
        const ur = vf2i(render.screenToWorldPos(.{screen_size[0], 0}));
        const bl = vf2i(render.screenToWorldPos(.{0, screen_size[1]}));
        const br = vf2i(render.screenToWorldPos(.{screen_size[0], screen_size[1]}));
        const xy_min = @min(ul, ur, bl, br);
        const xy_max = @max(ul, ur, bl, br);
        const chunk_min = World.worldPosToChunkPos(xy_min);
        const chunk_max = World.worldPosToChunkPos(xy_max);
        return .{chunk_min, chunk_max};
    }

    fn color(col: u32) @Vector(4, f32) {
        return @Vector(4, f32){
            @floatFromInt( (col & 0xFF000000) >> 24 ),
            @floatFromInt( (col & 0x00FF0000) >> 16 ),
            @floatFromInt( (col & 0x0000FF00) >> 8 ),
            @floatFromInt( (col & 0x000000FF) >> 0 ),
        } / @splat(4, @as(f32, 255.0));
    }

    pub fn prepareApp(render: *Render,
        encoder: *gpu.CommandEncoder,
    ) !void {
        if(render.uniform_buffer == null) {
            render.uniform_buffer = render.app.core.device().createBuffer(&.{
                .usage = .{ .copy_dst = true, .uniform = true },
                .size = @sizeOf(App.UniformBufferObject),
                .mapped_at_creation = false,
            });
        }
        encoder.writeBuffer(render.uniform_buffer.?, 0, &[_]App.UniformBufferObject{.{
            .screen_size = render.window_size,
            .colors = .{
                color(0xCCFFE5_FF),
                color(0x48FFA7_FF),
                color(0x00821F_FF),
                color(0x002C0A_FF),
            },
        }});

        try render.prepareWorld(encoder);
        try render.prepareUI(encoder);
    }

    pub fn prepareUI(render: *Render,
        encoder: *gpu.CommandEncoder,
    ) !void {
        var vertices = std.ArrayList(App.Vertex).init(render.alloc);
        defer vertices.deinit();

        try vertices.appendSlice(&vertexRect(.{
            .ul = .{10, 10},
            .br = .{90, 190},
            .draw_colors = 0x3,
            .border_radius = 7.0,
        }));
        try vertices.appendSlice(&vertexRect(.{
            .ul = .{10 + 2, 10 + 2},
            .br = .{90 - 2, 190 - 2},
            .draw_colors = 0x2,
            .border_radius = 5.0,
        }));

        if(render.ui_texture == null) {
            const UI_TEX_IMAGE_WIDTH = 1;
            const UI_TEX_IMAGE_HEIGHT = 1;
            const img_size = gpu.Extent3D{
                .width = UI_TEX_IMAGE_WIDTH,
                .height = UI_TEX_IMAGE_HEIGHT,
            };
            render.ui_texture = render.app.core.device().createTexture(&.{
                .size = img_size,
                .format = .rgba8_unorm,
                .usage = .{
                    .texture_binding = true,
                    .copy_dst = true,
                    .render_attachment = true,
                },
            });

            const data_layout = gpu.Texture.DataLayout{
                .bytes_per_row = UI_TEX_IMAGE_WIDTH * 4, // width * channels
                .rows_per_image = UI_TEX_IMAGE_HEIGHT, // height
            };
            render.app.queue.writeTexture(&.{ .texture = render.ui_texture.? }, &data_layout, &img_size, &[UI_TEX_IMAGE_WIDTH * UI_TEX_IMAGE_HEIGHT * 4]u8{
                0, 0, 0, 0,
            });
        }

        if(render.ui_vertex_buffer) |b| b.release();
        render.ui_vertex_buffer = render.app.core.device().createBuffer(&.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = @sizeOf(App.Vertex) * vertices.items.len,
            .mapped_at_creation = false,
        });
        encoder.writeBuffer(render.ui_vertex_buffer.?, 0, vertices.items);

        const sampler = render.app.core.device().createSampler(&.{
            .mag_filter = .nearest,
            .min_filter = .nearest,
        });
        defer sampler.release();

        const texture_view = render.ui_texture.?.createView(&gpu.TextureView.Descriptor{});
        defer texture_view.release();

        if(render.ui_bind_group) |prev_bg| prev_bg.release();
        render.ui_bind_group = render.app.core.device().createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = render.app.pipeline.getBindGroupLayout(0),
                .entries = &.{
                    gpu.BindGroup.Entry.buffer(0, render.uniform_buffer.?, 0, @sizeOf(App.UniformBufferObject)),
                    gpu.BindGroup.Entry.sampler(1, sampler),
                    gpu.BindGroup.Entry.textureView(2, texture_view),
                },
            }),
        );
    }

    pub fn prepareWorld(render: *Render,
        encoder: *gpu.CommandEncoder,
    ) !void {
        const world = render.world;

        const chunk_b = render.screenChunkBounds();
        const chunk_min = chunk_b[0];
        const chunk_max = chunk_b[1];

        {var chunk_y = chunk_min[1]; while(chunk_y <= chunk_max[1]) : (chunk_y += 1) {
            {var chunk_x = chunk_min[0]; while(chunk_x <= chunk_max[0]) : (chunk_x += 1) {
                const chunk_pos = Vec2i{chunk_x, chunk_y};
                const target_chunk = try world.getOrLoadChunk(chunk_pos);
                render.prepareChunk(
                    target_chunk,
                    encoder,
                );
            }}
        }}
    }

    const VERTICES_LEN = 6;
    pub fn prepareChunk(
        render: *Render,
        chunk: *Chunk,
        encoder: *gpu.CommandEncoder,
    ) void {
        const app = render.app;
        const cri = &chunk.chunk_render_info;
        const img_size = gpu.Extent3D{ .width = CHUNK_SIZE, .height = CHUNK_SIZE };
        if(cri.last_updated == 0) {
            cri.gpu_texture = render.app.core.device().createTexture(&.{
                .size = img_size,
                .format = .r8_unorm, // alternatively: r8_uint
                .usage = .{
                    .texture_binding = true,
                    .copy_dst = true,
                    .render_attachment = true,
                },
            });
        }
        if(cri.last_updated != chunk.last_updated) {
            cri.last_updated = chunk.last_updated;
            const data_layout = gpu.Texture.DataLayout{
                .bytes_per_row = CHUNK_SIZE * 1, // width * channels
                .rows_per_image = CHUNK_SIZE, // height
            };
            render.app.queue.writeTexture(&.{ .texture = cri.gpu_texture }, &data_layout, &img_size, &chunk.texture);
        }


        const chunk_world_ul = chunk.chunk_pos * Vec2i{CHUNK_SIZE, CHUNK_SIZE};
        const vertices = &vertexRect(.{
            .ul = render.worldPosToScreenPos( chunk_world_ul ),
            .ur = render.worldPosToScreenPos( chunk_world_ul + Vec2i{CHUNK_SIZE, 0} ),
            .bl = render.worldPosToScreenPos( chunk_world_ul + Vec2i{0, CHUNK_SIZE} ),
            .br = render.worldPosToScreenPos( chunk_world_ul + Vec2i{CHUNK_SIZE, CHUNK_SIZE} ),
            .draw_colors = 0o07743210,
        });

        if(cri.vertex_buffer == null) cri.vertex_buffer = render.app.core.device().createBuffer(&.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = @sizeOf(App.Vertex) * vertices.len,
            .mapped_at_creation = false,
        });
        encoder.writeBuffer(cri.vertex_buffer.?, 0, vertices);


        const sampler = app.core.device().createSampler(&.{
            .mag_filter = .nearest,
            .min_filter = .nearest,
        });
        defer sampler.release();


        const texture_view = cri.gpu_texture.createView(&gpu.TextureView.Descriptor{});
        defer texture_view.release();


        if(cri.bind_group) |prev_bg| prev_bg.release();
        cri.bind_group = app.core.device().createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = app.pipeline.getBindGroupLayout(0),
                .entries = &.{
                    gpu.BindGroup.Entry.buffer(0, render.uniform_buffer.?, 0, @sizeOf(App.UniformBufferObject)),
                    gpu.BindGroup.Entry.sampler(1, sampler),
                    gpu.BindGroup.Entry.textureView(2, texture_view),
                },
            }),
        );
    }

    pub fn renderApp(render: *Render,
        pass: *gpu.RenderPassEncoder,
    ) !void {
        try render.renderWorld(pass);
        try render.renderUI(pass);
    }

    pub fn renderWorld(render: *Render,
        pass: *gpu.RenderPassEncoder,
    ) !void {
        const world = render.world;

        const chunk_b = render.screenChunkBounds();
        const chunk_min = chunk_b[0];
        const chunk_max = chunk_b[1];

        {var chunk_y = chunk_min[1]; while(chunk_y <= chunk_max[1]) : (chunk_y += 1) {
            {var chunk_x = chunk_min[0]; while(chunk_x <= chunk_max[0]) : (chunk_x += 1) {
                const chunk_pos = Vec2i{chunk_x, chunk_y};
                const target_chunk = try world.getOrLoadChunk(chunk_pos);
                render.renderChunk(
                    target_chunk,
                    pass,
                );
            }}
        }}
    }

    pub fn renderChunk(
        render: *Render,
        chunk: *Chunk,
        pass: *gpu.RenderPassEncoder,
    ) void {
        _ = render;
        const cri = &chunk.chunk_render_info;

        pass.setVertexBuffer(0, cri.vertex_buffer.?, 0, @sizeOf(App.Vertex) * VERTICES_LEN);
        pass.setBindGroup(0, cri.bind_group.?, &.{});
        pass.draw(VERTICES_LEN, 1, 0, 0);
    }

    pub fn renderUI(render: *Render,
        pass: *gpu.RenderPassEncoder,
    ) !void {
        const vb_size = render.ui_vertex_buffer.?.getSize();
        pass.setVertexBuffer(0, render.ui_vertex_buffer.?, 0, vb_size);
        pass.setBindGroup(0, render.ui_bind_group.?, &.{});
        pass.draw(@intCast(vb_size / @sizeOf(App.Vertex)), 1, 0, 0);
    }
};
