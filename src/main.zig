const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});
const math = @import("math.zig");

const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vi2f = math.vi2f;
const vf2i = math.vf2i;

const EntityID = enum(u32) {none, _};

const CHUNK_SIZE = 2048; // 2048
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
        std.log.info("create chunk: {any}", .{chunk_pos});
        var chunk = try world.alloc.create(Chunk);
        chunk.* = .{
            .chunk_pos = chunk_pos,
        };
        try world.loaded_chunks.append(chunk);
        return chunk;
    }

    fn getPixel(world: *World, pos: Vec2i) !u8 {
        const target_chunk = worldPosToChunkPos(pos);
        const target_chunk_offset = target_chunk * Vec2i{CHUNK_SIZE, CHUNK_SIZE};
        const pos_offset = pos - target_chunk_offset;
        const chunk_value = try getOrLoadChunk(world, target_chunk);

        return chunk_value.getPixel(pos_offset);
    }
    fn setPixel(world: *World, pos: Vec2i, value: u8) !void {
        const target_chunk = worldPosToChunkPos(pos);
        const target_chunk_offset = target_chunk * Vec2i{CHUNK_SIZE, CHUNK_SIZE};
        const pos_offset = pos - target_chunk_offset;
        const chunk_value = try getOrLoadChunk(world, target_chunk);

        return chunk_value.setPixel(pos_offset, value);
    }

    fn worldPosToChunkPos(world_pos: Vec2i) Vec2i {
        return @divFloor(world_pos, Vec2i{CHUNK_SIZE, CHUNK_SIZE});
    }
};

const Render = struct {
    // renderChunk, renderEntity, renderWorld
    // for all entities of visible chunks : render entities

    //camera_center: Vec2f,
    alloc: std.mem.Allocator,
    remap_colors_shader: ray.Shader,
    center_offset: Vec2f32 = .{0, 0},
    center_scale: f32 = 1.0,
    window_size: Vec2f32 = .{0, 0},

    world: *World,

    fn create(alloc: std.mem.Allocator, world: *World) !*Render {
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
            .world = world,
        };
        return render;
    }
    fn destroy(render: *Render) void {
        ray.UnloadShader(render.remap_colors_shader);
        render.alloc.destroy(render);
    }

    fn screenToWorldPos(render: *Render, screen_pos: Vec2f32) Vec2f32 {
        const wso2 = render.halfScreen();
        const scale = @splat(2, render.center_scale);
        return (screen_pos - wso2) / scale + render.center_offset;
    }
    fn worldPosToScreenPos(render: *Render, world_pos: Vec2i) Vec2f32 {
        const wso2 = render.halfScreen();
        const scale = @splat(2, render.center_scale);
        return (vi2f(world_pos) - render.center_offset) * scale + wso2;
    }
    fn halfScreen(render: *Render) Vec2f32 {
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

    fn renderChunk(render: *Render, chunk: *Chunk, scale: f32, offset: Vec2f32) void {
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

        // if we draw triangles, we can convert the four corners to positions and draw those triangles
        ray.DrawTextureEx(
            cri.gpu_texture,
            .{.x = offset[0], .y = offset[1]}, // position, for now
            0,
            scale, // scale, for now
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

    var render = try Render.create(alloc, world);
    defer render.destroy();

    var prev_world_pos: ?Vec2i = null;

    const mwheel_mul: Vec2f32 = .{20.0, 20.0};

    //ray.DisableCursor();

    while(!ray.WindowShouldClose()) {
        render.window_size = vi2f(.{ray.GetScreenWidth(), ray.GetScreenHeight()});
        // std.log.info("{d}, {d}", .{render.center_offset, render.center_scale});

        const mp = if(ray.IsCursorHidden()) render.halfScreen() else vi2f(.{ray.GetMouseX(), ray.GetMouseY()});
        if(!ray.IsCursorHidden()) {
            if(ray.IsKeyPressed(ray.KEY_A)) {
                ray.DisableCursor();
            }
        }else{
            if(ray.IsKeyPressed(ray.KEY_ESCAPE)) {
                ray.EnableCursor();
            }
        }

        const mwheel_rayvec = ray.GetMouseWheelMoveV();
        const mwheel_ray = Vec2f32{mwheel_rayvec.x, mwheel_rayvec.y} * mwheel_mul;
        if(ray.IsKeyDown(ray.KEY_LEFT_CONTROL) or ray.IsKeyDown(ray.KEY_RIGHT_CONTROL) or ray.IsKeyDown(ray.KEY_LEFT_ALT) or ray.IsKeyDown(ray.KEY_RIGHT_ALT)) {
            const mpos_before = render.screenToWorldPos(mp);

            const wheel: f32 = (mwheel_ray[0] + mwheel_ray[1]) / 120.0;
            const zoom: f32 = std.math.pow(f32, 1 + @fabs(wheel) / 2, @as(f32, if(wheel > 0) -1 else 1));
            render.center_scale *= zoom;
            if(render.center_scale < 1.0) render.center_scale = 1.0;
            if(render.center_scale > 2048.0) render.center_scale = 2048.0;

            const mpos_after = render.screenToWorldPos(mp);
            render.center_offset -= mpos_after - mpos_before;
        }else if(ray.IsKeyDown(ray.KEY_LEFT_SHIFT) or ray.IsKeyDown(ray.KEY_RIGHT_SHIFT)) {
            render.center_offset -= Vec2f32{mwheel_ray[0] + mwheel_ray[1], 0} / @splat(2, render.center_scale);
        }else{
            render.center_offset -= mwheel_ray / @splat(2, render.center_scale);
        }
        if(ray.IsCursorHidden()) {
            const md = ray.GetMouseDelta();
            const mmove_vec = Vec2f32{md.x, md.y};

            render.center_offset += mmove_vec / @splat(2, render.center_scale);
        }

        {
            const world_pos = vf2i(render.screenToWorldPos(mp));
            if(ray.IsMouseButtonDown(ray.MOUSE_BUTTON_LEFT)) {
                if(prev_world_pos == null) prev_world_pos = world_pos;
                var lp = math.LinePlotter.init(prev_world_pos.?, world_pos);
                while(lp.next()) |pos| {
                    try world.setPixel(pos, 255);
                }
                prev_world_pos = world_pos;
            }else{
                prev_world_pos = null;
            }
        }

        ray.BeginDrawing();
        try render.renderWorld();
        ray.DrawFPS(10, 10);

        if(!ray.IsWindowFocused()) {
            ray.DrawText("Click to focus", 20, 20, 10, .{.r = 255, .g = 0, .b = 0, .a = 255});
        }

        ray.EndDrawing();
    }
}
