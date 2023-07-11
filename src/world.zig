const std = @import("std");
const math = @import("math.zig");
// const world = @This();
const render = @import("render.zig");

const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vi2f = math.vi2f;
const vf2i = math.vf2i;

pub const EntityID = enum(u32) {none, _};

pub const CHUNK_SIZE = 2048; // 2048
pub const Chunk = struct {
    chunk_pos: Vec2i,
    texture: [CHUNK_SIZE * CHUNK_SIZE]u8 = [_]u8{0} ** (CHUNK_SIZE * CHUNK_SIZE), // 8bpp image data, shader to remap colors based on entity
    entities: [1024]EntityID = [_]EntityID{.none} ** 1024,
    chunk_render_info: render.ChunkRenderInfo = .{},
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

pub const Entity = struct {};

pub const World = struct {
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
