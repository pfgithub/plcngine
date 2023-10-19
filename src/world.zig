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
pub const CHUNK_VERSION = 0;
pub const Chunk = struct {
    chunk_pos: Vec2i,
    texture: [CHUNK_SIZE * CHUNK_SIZE]u8 = [_]u8{0} ** (CHUNK_SIZE * CHUNK_SIZE), // 8bpp image data, shader to remap colors based on entity
    //entities: [1024]EntityID = [_]EntityID{.none} ** 1024,
    chunk_render_info: render.ChunkRenderInfo = .{},
    last_updated: u64 = 1,
    last_used: u64 = 0,
    last_saved: u64 = 1, // don't save blank chunks

    pub fn deinit(chunk: *Chunk) void {
        chunk.chunk_render_info.deinit();
    }
    fn itmIndex(offset: Vec2i) ?usize {
        if(!hasPixel(offset)) return null;
        return @intCast(offset[1] * CHUNK_SIZE + offset[0]);
    }
    pub fn hasPixel(offset: Vec2i) bool {
        if(@reduce(.Or, offset < Vec2i{0, 0}) or @reduce(.Or, offset >= Vec2i{CHUNK_SIZE, CHUNK_SIZE})) {
            return false;
        }
        return true;
    }
    pub fn getPixel(chunk: *const Chunk, offset: Vec2i) u8 {
        const index = itmIndex(offset) orelse unreachable;
        return chunk.texture[index];
    }
    pub fn setPixel(chunk: *Chunk, offset: Vec2i, value: u8) void {
        const index = itmIndex(offset) orelse unreachable;
        chunk.texture[index] = value;
        chunk.last_updated += 1;
    }

    const FILE_HEADER = std.fmt.comptimePrint("plc_chunk_v{d}_s{d}:", .{CHUNK_VERSION, CHUNK_SIZE});
    pub fn serialize(chunk: Chunk, writer: anytype) !void {
        try writer.writeAll(FILE_HEADER);
        try writer.writeAll(&chunk.texture);
    }
    pub fn deserialize(out: *Chunk, reader: anytype) !void {
        var header: [FILE_HEADER.len]u8 = undefined;
        if(try reader.readAtLeast(&header, header.len) != header.len) return error.BadFile;
        if(!std.mem.eql(u8, &header, FILE_HEADER)) {
            return error.BadFile;
        }

        if(try reader.readAtLeast(&out.texture, out.texture.len) != out.texture.len) return error.BadFile;

        if(reader.readByte() != error.EndOfStream) return error.BadFile;

        out.last_saved = out.last_updated;
    }
};

pub const Entity = struct {};

pub const World = struct {
    alloc: std.mem.Allocator,
    loaded_chunks: std.ArrayList(*Chunk), // we can also do [512]?*Chunk or something
    entities: std.ArrayList(*Entity),
    frame_index: u64 = 0,

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
            chunk.deinit();
            world.alloc.destroy(chunk);
        }
        world.loaded_chunks.deinit();
        world.entities.deinit();
        world.alloc.destroy(world);
    }

    pub fn chunkFilename(buf: *[128]u8, pos: Vec2i) []const u8 {
        return std.fmt.bufPrint(
            buf,
            "C_{x}_{x}.plc_chunk",
            .{pos[0], pos[1]},
        ) catch unreachable;
    }
    pub fn saveChunk(chunk: *Chunk) !void {
        if(chunk.last_saved == chunk.last_updated) return; // no changes to save

        var out_name_buffer: [128]u8 = undefined;
        const out_name_str = chunkFilename(&out_name_buffer, chunk.chunk_pos);

        var out_file = try std.fs.cwd().atomicFile(out_name_str, .{});
        defer out_file.deinit();

        const of_writer = out_file.file.writer(); // todo std.io.BufferedWriter

        try chunk.serialize(of_writer);

        try out_file.finish();

        std.log.info("saved to {s}", .{out_name_str});
    }

    pub fn clearUnusedChunks(world: *World) !void {
        // array size decreases while going through this loop; keep the original size outside
        const loaded_chunks_len = world.loaded_chunks.items.len;
        for(0..loaded_chunks_len) |chunk_index_inv| { // 0 1 2 3 => 3 2 1 0
            const chunk_index = loaded_chunks_len - 1 - chunk_index_inv;
            const chunk = world.loaded_chunks.items[chunk_index];
            if(world.frame_index != chunk.last_used) {
                std.log.info("UNLOAD: {d}", .{chunk.chunk_pos});

                try saveChunk(chunk);

                chunk.deinit();
                world.alloc.destroy(chunk);

                // fills from the end of the list so it's okay as long as we loop backwards
                _ = world.loaded_chunks.swapRemove(chunk_index);
            }
        }
    }
    pub fn saveAll(world: *World) !void {
        for(world.loaded_chunks.items) |chunk| {
            try saveChunk(chunk);
        }
    }
    pub fn getOrLoadChunk(world: *World, chunk_pos: Vec2i) !*Chunk {
        for(world.loaded_chunks.items) |chunk| {
            if(@reduce(.And, chunk.chunk_pos == chunk_pos)) {
                chunk.last_used = world.frame_index;
                return chunk;
            }
        }
        // chunk is not loaded ; load
        var chunk = try world.alloc.create(Chunk);
        chunk.* = .{
            .chunk_pos = chunk_pos,
            .last_used = world.frame_index,
        };

        var chunk_name_buffer: [128]u8 = undefined;
        const chunk_name_str = chunkFilename(&chunk_name_buffer, chunk.chunk_pos);

        file_not_found: {
            const file = std.fs.cwd().openFile(chunk_name_str, .{.mode = .read_only}) catch |err| {
                switch(err) {
                error.FileNotFound => break :file_not_found,
                else => return err,
            }
            };
            defer file.close();

            const reader = file.reader(); // TODO BufferedReader
            try chunk.deserialize(reader);
            try world.loaded_chunks.append(chunk);
            return chunk;
        }

        // chunk file does not exist ; create
        std.log.info("create chunk: {any}", .{chunk_pos});
        try world.loaded_chunks.append(chunk);
        return chunk;
    }

    pub fn getChunkAtPixel(world: *World, pos: Vec2i) !struct{*Chunk, Vec2i} {
        const target_chunk = worldPosToChunkPos(pos);
        const target_chunk_offset = target_chunk * Vec2i{CHUNK_SIZE, CHUNK_SIZE};
        const pos_offset = pos - target_chunk_offset;
        const chunk_value = try getOrLoadChunk(world, target_chunk);

        return .{chunk_value, pos_offset};
    }
    pub fn getPixel(world: *World, pos: Vec2i) !u8 {
        const chunk, const offset = try world.getChunkAtPixel(pos);
        return chunk.getPixel(offset);
    }
    pub fn setPixel(world: *World, pos: Vec2i, value: u8) !void {
        const chunk, const offset = try world.getChunkAtPixel(pos);
        return chunk.setPixel(offset, value);
    }

    pub fn worldPosToChunkPos(world_pos: Vec2i) Vec2i {
        return @divFloor(world_pos, Vec2i{CHUNK_SIZE, CHUNK_SIZE});
    }
};

const History = struct {
    synchronized: std.mem.ArrayList(Operation),
    local: std.mem.ArrayList(Operation),
    undo_operations: std.mem.ArrayList(OperationID),
    redo_operations: std.mem.ArrayList(OperationID),
};

// operation id:
// - server: 0 1 2 3 ...
// - clients: 2.[client_id.0], 2.[client_id.1], ...
// undo:
// - reset any pixels to their previous values excluding any that have since been modified
pub const Operation = struct {
    parent: OperationID,
    value: OperationUnion,
};
const OperationID = union(enum) {
    synchronized: usize,
    local: usize,
};
const OperationUnion = union(enum) {
    set_pixels: SetPixels,
    set_area: SetArea,

    pub const SetArea = struct {
        old_region: []const u8,
        new_region: []const u8, // run-length encode? & transparency ignored
        size: Vec2i,
    };
    pub const SetPixels = struct {
        pixel: []const SetPixel,
    };
    pub const SetPixel = struct {
        pos: Vec2i,
        old_value: u8,
        new_value: u8,
    };
};