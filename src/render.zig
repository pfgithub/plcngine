const std = @import("std");
const math = @import("math.zig");
const world_import = @import("world.zig");
const World = world_import.World;
const Chunk = world_import.Chunk;
const CHUNK_SIZE = world_import.CHUNK_SIZE;
const App = @import("main2.zig");

const mach = @import("mach");
const gpu = mach.gpu;

const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vi2f = math.vi2f;
const vf2i = math.vf2i;

pub const ChunkRenderInfo = struct {
    // it might be possible to keep one big gpu texture and update subtextures of it:
    // UpdateTextureRec(Texture2D texture, Rectangle rec, const void *pixels)
    // say like 8192x8192
    // and then all the chunks can be drawn in one draw call
    // is that good? idk

    gpu_texture: *gpu.Texture = undefined, // last_updated 0 indicates that this is undefined and should not be used
    last_updated: usize = 0,

    pub fn deinit(cri: ChunkRenderInfo) void {
        if(cri.last_updated != 0) {
            cri.gpu_texture.destroy();
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

    pub fn renderWorld(render: *Render) !void {
        const world = render.world;

        const screen_size = render.window_size;
        const ul = vf2i(render.screenToWorldPos(.{0, 0}));
        const ur = vf2i(render.screenToWorldPos(.{screen_size[0], 0}));
        const bl = vf2i(render.screenToWorldPos(.{0, screen_size[1]}));
        const br = vf2i(render.screenToWorldPos(.{screen_size[0], screen_size[1]}));
        const xy_min = @min(ul, ur, bl, br);
        const xy_max = @max(ul, ur, bl, br);
        const chunk_min = World.worldPosToChunkPos(xy_min);
        const chunk_max = World.worldPosToChunkPos(xy_max);

        {var chunk_y = chunk_min[1]; while(chunk_y <= chunk_max[1]) : (chunk_y += 1) {
            {var chunk_x = chunk_min[0]; while(chunk_x <= chunk_max[0]) : (chunk_x += 1) {
                const chunk_pos = Vec2i{chunk_x, chunk_y};
                const target_chunk = try world.getOrLoadChunk(chunk_pos);
                render.renderChunk(
                    target_chunk,
                    render.center_scale,
                    render.worldPosToScreenPos( chunk_pos * Vec2i{CHUNK_SIZE, CHUNK_SIZE} ),
                );
            }}
        }}
    }

    pub fn renderChunk(render: *Render, chunk: *Chunk, scale: f32, offset: Vec2f32) void {
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

        // draw two triangles with uv coords of target texture
        // int texture_loc = ray.GetShaderLocation(render.remap_colors_shader, "texture0");
        // int swirl_center_loc = ray.GetShaderLocation(render.remap_colors_shader, "color_map");
        //ray.SetShaderValueTexture(render.remap_colors_shader, cri.gpu_texture);
        //ray.BeginShaderMode(render.remap_colors_shader, texture_loc, cri.gpu_texture);

        // if we draw triangles, we can convert the four corners to positions and draw those triangles

        // update vertex buffer if needed

        // ray.DrawTextureEx(
        //     cri.gpu_texture,
        //     .{.x = offset[0], .y = offset[1]}, // position, for now
        //     0,
        //     scale, // scale, for now
        //     .{.r = 255, .g = 255, .b = 255, .a = 255},
        // );
        _ = scale;
        _ = offset;

        //ray.EndShaderMode();
    }
};
