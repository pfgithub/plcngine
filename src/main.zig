const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});

const Vec2i = @Vector(2, i32);

const EntityID = enum(u32) {none, _};

const CHUNK_SIZE = 256; // 2048
const Chunk = struct {
    chunk_pos: Vec2i,
    texture: [CHUNK_SIZE * CHUNK_SIZE]u8 = [_]u8{0} ** (CHUNK_SIZE * CHUNK_SIZE), // 8bpp image data, shader to remap colors based on entity
    entities: [1024]EntityID = [_]EntityID{.none} ** 1024,
    chunk_render_info: ChunkRenderInfo = .{},
    last_updated: usize = 1,

    fn itmIndex(offset: Vec2i) ?usize {
        if(@reduce(.Or, offset < Vec2i{0, 0}) or @reduce(.Or, offset >= Vec2i{CHUNK_SIZE, CHUNK_SIZE})) {
            return null;
        }
        return @intCast(offset[1] * CHUNK_SIZE + offset[0]);
    }
    fn getPixel(chunk: *const Chunk, offset: Vec2i) u8 {
        const index = itmIndex(offset) orelse unreachable;
        return chunk.texture[index];
    }
    fn setPixel(chunk: *Chunk, offset: Vec2i, value: u8) void {
        const index = itmIndex(offset) orelse unreachable;
        chunk.texture[index] = value;
        chunk.last_updated += 1;
    }
};

const ChunkRenderInfo = struct {
    // it might be possible to keep one big gpu texture and update subtextures of it:
    // UpdateTextureRec(Texture2D texture, Rectangle rec, const void *pixels)
    // say like 8192x8192
    // and then all the chunks can be drawn in one draw call
    // is that good? idk

    gpu_texture: ray.Texture2D = undefined, // last_updated 0 indicates that this is undefined and should not be used
    last_updated: usize = 0,

    fn deinit(cri: ChunkRenderInfo) void {
        if(cri.last_updated != 0) {
            ray.UnloadTexture(cri.gpu_texture);
        }
    }
};

const Entity = struct {};

const World = struct {
    alloc: std.mem.Allocator,
    loaded_chunks: std.ArrayList(*Chunk), // we can also do [512]?*Chunk or something
    entities: std.ArrayList(*Entity),

    pub fn create(alloc: std.mem.Allocator) !*World {
        const world = try alloc.create(World);
        world.* = .{
            .alloc = alloc,
            .loaded_chunks = std.ArrayList(*Chunk).init(alloc),
            .entities = std.ArrayList(*Entity).init(alloc),
        };
        return world;
    }
    pub fn destroy(world: *World) void {
        for(world.loaded_chunks.items) |chunk| {
            chunk.chunk_render_info.deinit();
            world.alloc.destroy(chunk);
        }
        world.loaded_chunks.deinit();
        world.entities.deinit();
        world.alloc.destroy(world);
    }

    pub fn getOrLoadChunk(world: *World, chunk_pos: Vec2i) !*Chunk {
        for(world.loaded_chunks.items) |chunk| {
            if(@reduce(.And, chunk.chunk_pos == chunk_pos)) {
                return chunk;
            }
        }
        // chunk is not loaded ; load
        // chunk file does not exist ; create
        var chunk = try world.alloc.create(Chunk);
        chunk.* = .{
            .chunk_pos = chunk_pos,
        };
        try world.loaded_chunks.append(chunk);
        return chunk;
    }
};

const Render = struct {
    // renderChunk, renderEntity, renderWorld
    // for all entities of visible chunks : render entities

    //camera_center: Vec2f,
    alloc: std.mem.Allocator,
    remap_colors_shader: ray.Shader,

    fn create(alloc: std.mem.Allocator) !*Render {
        const render = try alloc.create(Render);
        const remap_colors_shader = ray.LoadShaderFromMemory(
            @embedFile("colors.vs"),
            @embedFile("colors.fs"),
        );
        if(!ray.IsShaderReady(remap_colors_shader)) {
            return error.ShaderNotReady;
        }
        render.* = .{
            .alloc = alloc,
            .remap_colors_shader = remap_colors_shader,
        };
        return render;
    }
    fn destroy(render: *Render) void {
        ray.UnloadShader(render.remap_colors_shader);
        render.alloc.destroy(render);
    }

    pub fn renderWorld(render: *Render, world: *World) !void {
        const target_chunk = try world.getOrLoadChunk(.{0, 0});
        render.renderChunk(target_chunk);
    }

    fn renderChunk(render: *Render, chunk: *Chunk) void {
        const cri = &chunk.chunk_render_info;
        if(cri.last_updated == 0) {
            cri.gpu_texture = ray.LoadTextureFromImage(.{
                .data = &chunk.texture,
                .width = CHUNK_SIZE,
                .height = CHUNK_SIZE,
                .mipmaps = 1,
                .format = ray.PIXELFORMAT_UNCOMPRESSED_GRAYSCALE,
            });
            cri.last_updated = chunk.last_updated;
        }else if(cri.last_updated != chunk.last_updated) {
            cri.last_updated = chunk.last_updated;
            ray.UpdateTexture(cri.gpu_texture, &chunk.texture);
        }

        _ = render;
        // draw two triangles with uv coords of target texture
        // int texture_loc = ray.GetShaderLocation(render.remap_colors_shader, "texture0");
        // int swirl_center_loc = ray.GetShaderLocation(render.remap_colors_shader, "color_map");
        //ray.SetShaderValueTexture(render.remap_colors_shader, cri.gpu_texture);
        //ray.BeginShaderMode(render.remap_colors_shader, texture_loc, cri.gpu_texture);
        ray.DrawTextureEx(
            cri.gpu_texture,
            .{.x = 0, .y = 0}, // position, for now
            0,
            1.0, // scale, for now
            .{.r = 255, .g = 255, .b = 255, .a = 255},
        );
        //ray.EndShaderMode();
    }
};

pub fn main() !void {
    ray.SetConfigFlags(ray.FLAG_WINDOW_RESIZABLE);
    ray.InitWindow(160 * 3 + 10 * 2, 160 * 3 + 10 * 2, "plcngine");
    defer ray.CloseWindow();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if(gpa.deinit() == .leak) @panic("memory leak");
    const alloc = gpa.allocator();

    ray.SetTargetFPS(60);
    ray.SetExitKey(0);

    var world = try World.create(alloc);
    defer world.destroy();

    var render = try Render.create(alloc);
    defer render.destroy();

    while(!ray.WindowShouldClose()) {
        const mp = Vec2i{ray.GetMouseX(), ray.GetMouseY()};
        const target_chunk = try world.getOrLoadChunk(.{0, 0});
        if(Chunk.itmIndex(mp) != null) {
            target_chunk.setPixel(mp, 255);
        }

        ray.BeginDrawing();
        try render.renderWorld(world);
        ray.EndDrawing();
    }
}
