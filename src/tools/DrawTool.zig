const DrawTool = @This();
const App = @import("../main2.zig");
const math = @import("../math.zig");
const world_mod = @import("../world.zig");
const std = @import("std");
const core = @import("mach-core");

const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vf2i = math.vf2i;

pen_primary_color: u8 = 1,
pen_secondary_color: u8 = 0,
current_line: ?CurrentLine = null,

const SetPixel = struct {};
const CurrentLine = struct {
    prev_world_pos: Vec2i,
    set_pixels: std.ArrayList(SetPixel),
};

// tool: click & drag : draws to the overlay & presence
// on release, commit the action to the world

pub fn deinit(tool: *DrawTool) void {
    if(tool.current_line) |*current_line| {
        current_line.set_pixels.deinit();
    }
}

pub fn update(tool: *DrawTool, app: *App) !void {
    const render = app.render;
    const world = app.world;
    const ih = &app.ih;

    const mp = app.ih.mouse_pos orelse Vec2f32{-1, -1};

    const world_pos = vf2i(render.screenToWorldPos(mp));
    // if(controls.pen_held_primary or controls.pen_held_secondary)
    if((ih.mouse_held.get(.left) or ih.mouse_held.get(.right)) and ih.modsEql(.{})) {
        const target_color = if(ih.mouse_held.get(.left)) tool.pen_primary_color else tool.pen_secondary_color;
        if(tool.current_line == null) {
            tool.current_line = .{
                .prev_world_pos = world_pos,
                .set_pixels = std.ArrayList(SetPixel).init(core.allocator),
            };
        }
        var lp = math.LinePlotter.init(tool.current_line.?.prev_world_pos, world_pos);
        while(lp.next()) |pos| {
            try world.setPixel(pos, target_color);
        }
        tool.current_line.?.prev_world_pos = world_pos;
    }else{
        if(tool.current_line) |*current_line| {
            // commit
            current_line.set_pixels.deinit(); // TODO: toOwnedSlice and put in operation
            tool.current_line = null;
        }
    }

    {
        const target_color_opt: ?*u8 = if(ih.modsEql(.{})) (
            &tool.pen_primary_color
        ) else if(ih.modsEql(.{.shift = true})) (
            &tool.pen_secondary_color
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