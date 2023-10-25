const world_mod = @import("../world.zig");
const core = @import("mach-core");
const std = @import("std");

const EncodeStatus = struct {
    output_al: *std.ArrayList(u8),
    current_byte: u8,
    current_len: u7,

    fn addByte(status: *EncodeStatus, byte: u8) !void {
        if(status.current_byte != byte or status.current_len == std.math.maxInt(u7)) {
            try status.commit();
        }
        status.current_byte = byte;
    }
    fn commit(status: *EncodeStatus) !void {
        if(status.current_len == 0) {
            // nothing to do
        }else if(status.current_len == 1 and status.current_byte < std.math.maxInt(u7)) {
            try status.output_al.append(status.current_byte);
        }else{
            try status.output_al.append(0b1_0000000 | status.current_len);
            try status.output_al.append(status.current_byte);
        }
        status.current_len = 0;
    }
};

fn encode(region: *const [world_mod.CHUNK_SIZE * world_mod.CHUNK_SIZE]u8) []u8 {
    var output_al = std.ArrayList.init(u8).init(core.allocator);
    var status = EncodeStatus{
        .output_al = &output_al,
        .current_byte = 0,
        .current_len = 0,
    };
    for(region) |byte| {
        try status.addByte(byte);
    }
    try status.commit();
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
fn decode(region: []const u8, output: *[world_mod.CHUNK_SIZE * world_mod.CHUNK_SIZE]u8) !void {

    var in_fbs = std.io.fixedBufferStream(region);
    const reader = in_fbs.reader();

    var cw = ChunkWriter{
        .output = output,
    };

    while(reader.readByte()) |byte| {
        if(byte & 0b1_0000000 != 0) {
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
}