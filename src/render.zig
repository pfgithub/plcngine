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

const core = @import("mach").core;
const gpu = core.gpu;

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

    uv_ul: ?Vec2f32 = null,
    uv_br: ?Vec2f32 = null,
};
pub fn vertexRect(
    opts: RectOpts,
) [6]App.Vertex {
    const ul = opts.ul;
    const br = opts.br;
    const ur = opts.ur orelse Vec2f32{br[x], ul[y]};
    const bl = opts.bl orelse Vec2f32{ul[x], br[y]};
    const draw_colors = opts.draw_colors;

    const uv_ul: Vec2f32 = opts.uv_ul orelse Vec2f32{0, 0};
    const uv_br: Vec2f32 = opts.uv_br orelse Vec2f32{1, 1};
    const uv_ur: Vec2f32 = Vec2f32{uv_br[x], uv_ul[y]};
    const uv_bl: Vec2f32 = Vec2f32{uv_ul[x], uv_br[y]};

    return [6]App.Vertex{
        .{
            .position = .{ ul[x], ul[y] },
            .uv = uv_ul,
            .draw_colors = draw_colors,
        },
        .{
            .position = .{ bl[x], bl[y] },
            .uv = uv_bl,
            .draw_colors = draw_colors,
        },
        .{
            .position = .{ ur[x], ur[y] },
            .uv = uv_ur,
            .draw_colors = draw_colors,
        },

        .{
            .position = .{ bl[x], bl[y] },
            .uv = uv_bl,
            .draw_colors = draw_colors,
        },
        .{
            .position = .{ br[x], br[y] },
            .uv = uv_br,
            .draw_colors = draw_colors,
        },
        .{
            .position = .{ ur[x], ur[y] },
            .uv = uv_ur,
            .draw_colors = draw_colors,
        },
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

pub fn color(col: u32) @Vector(4, f32) {
    return @Vector(4, f32){
        @floatFromInt( (col & 0xFF000000) >> 24 ),
        @floatFromInt( (col & 0x00FF0000) >> 16 ),
        @floatFromInt( (col & 0x0000FF00) >> 8 ),
        @floatFromInt( (col & 0x000000FF) >> 0 ),
    } / @as(@Vector(4, f32), @splat(255.0));
}

pub const Render = struct {
    // renderChunk, renderEntity, renderWorld
    // for all entities of visible chunks : render entities

    //camera_center: Vec2f,
    alloc: std.mem.Allocator,
    center_offset: Vec2f32 = .{0, 0},
    center_scale: f32 = 1.0,
    window_size: Vec2f32 = .{0, 0},

    colors: [4]@Vector(4, f32) = [4]@Vector(4, f32){
        color(0x002C0A_FF),
        color(0x00821F_FF),
        color(0x48FFA7_FF),
        color(0xCCFFE5_FF),
    },

    uniform_buffer: ?*gpu.Buffer = null,
    world: *World,
    app: *App,
    overlay: RenderOverlay = .{},

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
        render.alloc.destroy(render);
    }

    pub fn screenToWorldPos(render: *Render, screen_pos: Vec2f32) Vec2f32 {
        const wso2 = render.halfScreen();
        const scale: Vec2f32 = @splat(render.center_scale);
        return (screen_pos - wso2) / scale + render.center_offset;
    }
    pub fn worldPosIntToScreenPos(render: *Render, world_pos: Vec2i) Vec2f32 {
        return worldPosToScreenPos(render, vi2f(world_pos));
    }
    pub fn worldPosToScreenPos(render: *Render, world_pos: Vec2f32) Vec2f32 {
        const wso2 = render.halfScreen();
        const scale: Vec2f32 = @splat(render.center_scale);
        return (world_pos - render.center_offset) * scale + wso2;
    }
    pub fn halfScreen(render: *Render) Vec2f32 {
        return render.window_size / @as(Vec2f32, @splat(2.0));
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

    pub fn prepareApp(render: *Render,
        encoder: *gpu.CommandEncoder,
    ) !void {
        if(render.uniform_buffer == null) {
            render.uniform_buffer = core.device.createBuffer(&.{
                .usage = .{ .copy_dst = true, .uniform = true },
                .size = @sizeOf(App.UniformBufferObject),
                .mapped_at_creation = .false,
            });
        }
        encoder.writeBuffer(render.uniform_buffer.?, 0, &[_]App.UniformBufferObject{.{
            .screen_size = render.window_size,
            .colors = render.colors
        }});

        try render.prepareWorld(encoder);
        try render.overlay.prepareOverlay(encoder, render);
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
            cri.gpu_texture = core.device.createTexture(&.{
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
            render.app.queue.writeTexture(&.{ .texture = cri.gpu_texture }, &data_layout, &img_size, &chunk.texture.texture);
        }


        const chunk_world_ul = chunk.chunk_pos * Vec2i{CHUNK_SIZE, CHUNK_SIZE};
        const vertices = &vertexRect(.{
            .ul = render.worldPosIntToScreenPos( chunk_world_ul ),
            .ur = render.worldPosIntToScreenPos( chunk_world_ul + Vec2i{CHUNK_SIZE, 0} ),
            .bl = render.worldPosIntToScreenPos( chunk_world_ul + Vec2i{0, CHUNK_SIZE} ),
            .br = render.worldPosIntToScreenPos( chunk_world_ul + Vec2i{CHUNK_SIZE, CHUNK_SIZE} ),
            .draw_colors = 0o07743210,
        });

        if(cri.vertex_buffer == null) cri.vertex_buffer = core.device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = @sizeOf(App.Vertex) * vertices.len,
            .mapped_at_creation = .false,
        });
        encoder.writeBuffer(cri.vertex_buffer.?, 0, vertices);


        const sampler = core.device.createSampler(&.{
            .mag_filter = .nearest,
            .min_filter = .nearest,
        });
        defer sampler.release();


        const texture_view = cri.gpu_texture.createView(&gpu.TextureView.Descriptor{});
        defer texture_view.release();


        if(cri.bind_group) |prev_bg| prev_bg.release();
        cri.bind_group = core.device.createBindGroup(
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
        try render.overlay.renderOverlay(pass);
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
};

const RenderOverlay = struct {
    uniform_buffer: ?*gpu.Buffer = null,
    gpu_texture: ?*gpu.Texture = null,
    vertex_buffer: ?*gpu.Buffer = null,
    bind_group: ?*gpu.BindGroup = null,
    update_texture: bool = true,

    const VERTICES_LEN = 6;

    pub fn prepareOverlay(
        render: *RenderOverlay,
        encoder: *gpu.CommandEncoder,
        parent_render: *Render,
    ) !void {
        if(render.uniform_buffer == null) {
            render.uniform_buffer = core.device.createBuffer(&.{
                .usage = .{ .copy_dst = true, .uniform = true },
                .size = @sizeOf(App.UniformBufferObject),
                .mapped_at_creation = .false,
            });
        }
        encoder.writeBuffer(render.uniform_buffer.?, 0, &[_]App.UniformBufferObject{.{
            .screen_size = parent_render.window_size,
            .colors = .{
                color(0x000000_FF),
                color(0x444444_FF),
                color(0xAAAAAA_FF),
                color(0xFFFFFF_FF),
            },
        }});

        const app = parent_render.app;
        const img_size = gpu.Extent3D{ .width = 1, .height = 1 };
        if(render.gpu_texture == null) {
            render.gpu_texture = core.device.createTexture(&.{
                .size = img_size,
                .format = .r8_unorm, // alternatively: r8_uint
                .usage = .{
                    .texture_binding = true,
                    .copy_dst = true,
                    .render_attachment = true,
                },
            });
        }
        if(render.update_texture) {
            const OVERLAY_TEXTURE_SIZE = 4;
            render.update_texture = false;
            const data_layout = gpu.Texture.DataLayout{
                .bytes_per_row = OVERLAY_TEXTURE_SIZE * 1, // width * channels
                .rows_per_image = OVERLAY_TEXTURE_SIZE, // height
            };
            const texture: [OVERLAY_TEXTURE_SIZE * OVERLAY_TEXTURE_SIZE]u8 = [_]u8{
                1, 1, 1, 1,
                1, 1, 1, 1,
                1, 1, 1, 1,
                1, 1, 1, 1,
            };
            app.queue.writeTexture(&.{ .texture = render.gpu_texture.? }, &data_layout, &img_size, &texture);
        }

        const player = &app.controller.player;
        const player_size = vi2f(player.size);
        const vertices: *const [VERTICES_LEN]App.Vertex = &vertexRect(.{
            .ul = parent_render.worldPosToScreenPos( player.pos ),
            .ur = parent_render.worldPosToScreenPos( player.pos + Vec2f32{player_size[x] - 1, 0} ),
            .bl = parent_render.worldPosToScreenPos( player.pos + Vec2f32{0, player_size[y] - 1} ),
            .br = parent_render.worldPosToScreenPos( player.pos + Vec2f32{player_size[x] - 1, player_size[y] - 1} ),
            .draw_colors = 0o07743210,
        });

        if(render.vertex_buffer == null) render.vertex_buffer = core.device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = @sizeOf(App.Vertex) * vertices.len,
            .mapped_at_creation = .false,
        });
        encoder.writeBuffer(render.vertex_buffer.?, 0, vertices);

        const sampler = core.device.createSampler(&.{
            .mag_filter = .nearest,
            .min_filter = .nearest,
        });
        defer sampler.release();

        const texture_view = render.gpu_texture.?.createView(&gpu.TextureView.Descriptor{});
        defer texture_view.release();

        if(render.bind_group) |prev_bg| prev_bg.release();
        render.bind_group = core.device.createBindGroup(
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

    pub fn renderOverlay(render: *RenderOverlay,
        pass: *gpu.RenderPassEncoder,
    ) !void {
        pass.setVertexBuffer(0, render.vertex_buffer.?, 0, @sizeOf(App.Vertex) * VERTICES_LEN);
        pass.setBindGroup(0, render.bind_group.?, &.{});
        pass.draw(VERTICES_LEN, 1, 0, 0);
    }
};