const FillTool = @This();
const std = @import("std");
const App = @import("../main2.zig");
const math = @import("../math.zig");
const core = @import("mach").core;
const world_mod = @import("../world.zig");
const run_length_encode = @import("../util/run_length_encode.zig");

const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vf2i = math.vf2i;

pub fn deinit(_: *FillTool) void {}

pub fn update(_: *FillTool, app: *App) !void {
    const render = app.render;
    const world = app.world;
    const ih = &app.ih;
    const controller = app.controller;

    const mp = app.ih.mouse_pos orelse Vec2f32{-1, -1};

    const world_pos = vf2i(render.screenToWorldPos(mp));
    const target_chunk, const start_pos = try world.getChunkAtPixel(world_pos);
    // if(controls.pen_held_primary or controls.pen_held_secondary)
    if((ih.frame.mouse_press.get(.left) or ih.frame.mouse_press.get(.right)) and ih.modsEql(.{})) {
        const target_color = if(ih.frame.mouse_press.get(.left)) controller.data.primary_color else controller.data.secondary_color;
        const current_color = target_chunk.getPixel(start_pos);

        const operation = try floodFill(target_chunk, start_pos, current_color, target_color);
        if(operation) |*op| try world.history.applyOperation(op.*);
    }
}

// in the future, this can return an Operation
// either set_pixels or set_area, whichever is smaller
pub fn floodFill(chunk: *world_mod.Chunk, start_pos: Vec2i, replace_color: u8, with_color: u8) !?world_mod.Operation {
    if(replace_color == with_color) return null;

    // fill will be implemented by:
    // - make a new chunk-sized region filled with 255
    // - set pixels in it
    // - run-length encode
    // - emit output operation

    if(replace_color == 255 or with_color == 255) std.debug.panic("255 not allowed", .{});

    var temp_area = world_mod.Texture{};
    for(&temp_area.texture) |*val| val.* = 255;

    // also we can do a faster fill if we're smarter about the setpixel list
    // ie:
    // - from each point go max left and max right
    // - only add a pixel to the setpixel list if it's above or below and there was
    // - a blocker between the last pixel in the list

    var setpixel_list = std.ArrayList(Vec2i).init(core.allocator);
    defer setpixel_list.deinit();
    try setpixel_list.append(start_pos);

    var iter_count: usize = 0;
    while(setpixel_list.popOrNull()) |target| : (iter_count += 1) {
        if(iter_count > world_mod.CHUNK_SIZE * world_mod.CHUNK_SIZE * 2) {
            @panic("infinite loop");
        }
        temp_area.setPixel(target, with_color);

        for(&[_]Vec2i{.{-1, 0}, .{1, 0}, .{0, -1}, .{0, 1}}) |offset| {
            const new_target = target + offset;
            if(!world_mod.Texture.hasPixel(new_target)) continue;
            const world_value = chunk.getPixel(new_target);
            const newregion_value = temp_area.getPixel(new_target);

            if(world_value == replace_color and newregion_value != with_color) {
                try setpixel_list.append(new_target);
            }
        }
    }

    var res_al = std.ArrayList(u8).init(core.allocator);
    defer res_al.deinit();

    try run_length_encode.encode(&temp_area, &res_al);

    std.log.info("fill operation len {d}", .{res_al.items.len});

    var items = try std.ArrayList(world_mod.OperationUnion).initCapacity(core.allocator, 1);
    defer items.deinit();

    try items.append(.{
        .write_in_chunk = .{
            .new_region = try res_al.toOwnedSlice(),
            .old_region = null,
            .chunk = .{
                .position = chunk.chunk_pos,
                .surface = 0,
            },
        },
    });

    return .{
        .alloc = core.allocator,
        .items = try items.toOwnedSlice(),
    };
}