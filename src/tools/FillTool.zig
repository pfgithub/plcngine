const FillTool = @This();
const std = @import("std");
const App = @import("../main2.zig");
const math = @import("../math.zig");
const core = @import("mach-core");
const world_mod = @import("../world.zig");

const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vf2i = math.vf2i;

fill_primary_color: u8 = 1,
fill_secondary_color: u8 = 0,

pub fn deinit(_: *FillTool) void {}

pub fn update(tool: *FillTool, app: *App) !void {
    const render = app.render;
    const world = app.world;
    const ih = &app.ih;

    const mp = app.ih.mouse_pos orelse Vec2f32{-1, -1};

    const world_pos = vf2i(render.screenToWorldPos(mp));
    const target_chunk, const start_pos = try world.getChunkAtPixel(world_pos);
    // if(controls.pen_held_primary or controls.pen_held_secondary)
    if((ih.frame.mouse_press.get(.left) or ih.frame.mouse_press.get(.right)) and ih.modsEql(.{})) {
        const target_color = if(ih.frame.mouse_press.get(.left)) tool.fill_primary_color else tool.fill_secondary_color;
        const current_color = target_chunk.getPixel(start_pos);
        try floodFill(target_chunk, start_pos, current_color, target_color);
    }

    {
        const target_color_opt: ?*u8 = if(ih.modsEql(.{})) (
            &tool.fill_primary_color
        ) else if(ih.modsEql(.{.shift = true})) (
            &tool.fill_secondary_color
        ) else null;
        if(target_color_opt) |target_color| {
            if(ih.frame.key_press.get(.zero)) target_color.* = 0;
            if(ih.frame.key_press.get(.one)) target_color.* = 1;
            if(ih.frame.key_press.get(.two)) target_color.* = 2;
            if(ih.frame.key_press.get(.three)) target_color.* = 3;
            if(ih.frame.key_press.get(.four)) target_color.* = 4;
        }
    }
}

// in the future, this can return an Operation
// either set_pixels or set_area, whichever is smaller
pub fn floodFill(chunk: *world_mod.Chunk, start_pos: Vec2i, replace_color: u8, with_color: u8) !void {
    if(replace_color == with_color) return;

    // fill will be implemented by:
    // - make a new chunk-sized region filled with 255
    // - set pixels in it
    // - run-length encode
    // - emit output operation

    // also we can do a faster fill if we're smarter about the setpixel list
    // ie:
    // - from each point go max left and max right
    // - only add a pixel to the setpixel list if it's above or below and there was
    // - a blocker between the last pixel in the list

    var setpixel_list = std.ArrayList(Vec2i).init(core.allocator);
    try setpixel_list.append(start_pos);

    var iter_count: usize = 0;
    while(setpixel_list.popOrNull()) |target| : (iter_count += 1) {
        if(iter_count > world_mod.CHUNK_SIZE * world_mod.CHUNK_SIZE * 2) {
            @panic("infinite loop");
        }
        chunk.setPixel(target, with_color);

        for(&[_]Vec2i{.{-1, 0}, .{1, 0}, .{0, -1}, .{0, 1}}) |offset| {
            const new_target = target + offset;
            if(!world_mod.Chunk.hasPixel(new_target)) continue;
            const value = chunk.getPixel(new_target);

            if(value == replace_color) {
                try setpixel_list.append(new_target);
            }
        }
    }
}