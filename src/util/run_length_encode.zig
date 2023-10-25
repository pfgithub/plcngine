const world_mod = @import("../world.zig");
const core = @import("mach-core");
const std = @import("std");

// we can consider using QOI if we switch to rgba images
// also if we sacrifice one bit of alpha we can do fancy stuff

const EncodeStatus = struct {
    output_al: *std.ArrayList(u8),
    current_byte: u8,
    current_len: u32,

    fn addByte(status: *EncodeStatus, byte: u8) !void {
        if(status.current_byte != byte or status.current_len == std.math.maxInt(u32)) {
            try status.commit();
        }
        status.current_byte = byte;
        status.current_len += 1;
    }
    fn commit(status: *EncodeStatus) !void {
        if(status.current_len == 0) {
            // nothing to do
        }else if(status.current_len == 1 and status.current_byte <= std.math.maxInt(u7)) {
            try status.output_al.append(status.current_byte);
        }else if(status.current_len < std.math.maxInt(u7)) {
            try status.output_al.append(0b1_0000000 | @as(u8, @intCast(status.current_len)));
            try status.output_al.append(status.current_byte);
        }else{
            try status.output_al.append(0b1_0000000);
            try status.output_al.writer().writeIntLittle(u32, status.current_len);
            try status.output_al.append(status.current_byte);
        }
        status.current_len = 0;
    }
};

// can we guarantee that the encoded size is always <= chunk_size * chunk_size?
// i think the answer is no. but we can guarantee that the encoded size is always <= that + 1
// we use a uuid 16 bit header and if the file already has that header, add an indicator to say it does
// if in decoding the header is missing, don't decompress just copy.
pub fn encode(region: *const [world_mod.CHUNK_SIZE * world_mod.CHUNK_SIZE]u8, output_al: *std.ArrayList(u8)) !void {
    var status = EncodeStatus{
        .output_al = output_al,
        .current_byte = 0,
        .current_len = 0,
    };
    const start_pos = status.output_al.items.len;

    for(region) |byte| {
        try status.addByte(byte);
    }
    try status.commit();

    const end_pos = status.output_al.items.len;
    if(end_pos - start_pos > region.len) {
        std.log.warn("compressed size greater than uncompressed size: {d}, {d}", .{end_pos - start_pos, region.len});
    }

    if(@import("builtin").mode != .ReleaseFast and @import("builtin").mode != .ReleaseSmall) {
        const output_size = world_mod.CHUNK_SIZE * world_mod.CHUNK_SIZE;
        var validate_res: [output_size]u8 = [_]u8{255} ** output_size;
        decode(status.output_al.items[start_pos..], &validate_res) catch |e| {
            std.debug.panic("new region validate failed; decode error: {}", .{e});
        };
        if(!std.mem.eql(u8, region, &validate_res)) {
            std.debug.panic("new region validation failed", .{});
        }
    }
}
const ChunkWriter = struct {
    output: []u8,
    pos: usize = 0,
    fn writeByte(cw: *ChunkWriter, byte: u8) !void {
        if(cw.pos >= cw.output.len) return error.EndOfFile;
        if(byte != 255) cw.output[cw.pos] = byte;
        cw.pos += 1;
    }
};
/// WARNING: does not clear output ; byte 255 in input source will leave the existing value unmodified
pub fn decode(region: []const u8, output: *[world_mod.CHUNK_SIZE * world_mod.CHUNK_SIZE]u8) !void {
    // TODO: allow custom output fn rather than passing in the chunk data

    var in_fbs = std.io.fixedBufferStream(region);
    const reader = in_fbs.reader();

    var cw = ChunkWriter{
        .output = output,
    };

    while(reader.readByte()) |byte| {
        if(byte == 0b1_0000000) {
            const len = try reader.readIntLittle(u32);
            const write_byte = try reader.readByte();
            for(0..len) |_| try cw.writeByte(write_byte);
        }else if(byte & 0b1_0000000 != 0) {
            const len = byte & 0b0_1111111;
            const write_byte = try reader.readByte();
            for(0..len) |_| try cw.writeByte(write_byte);
        }else{
            try cw.writeByte(byte);
        }
    } else |err| switch(err) {
        error.EndOfStream => {},
        else => return err,
    }

    if(cw.pos != output.len) {
        std.log.err("chunk decode expected len {d}, got len {d}", .{output.len, cw.pos});
        return error.DecodeFailed;
    }
}