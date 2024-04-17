const DrawTool = @This();
const App = @import("../main2.zig");
const math = @import("../math.zig");
const world_mod = @import("../world.zig");
const std = @import("std");
const core = @import("mach").core;

const imgui = @import("zig-imgui");

const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vf2i = math.vf2i;

current_line: ?CurrentLine = null,

const SetPixel = struct {
    pos: Vec2i,
    value: u8,
};
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
    const controller = app.controller;

    const mp = app.ih.mouse_pos orelse Vec2f32{-1, -1};

    const world_pos = vf2i(render.screenToWorldPos(mp));
    // if(controls.pen_held_primary or controls.pen_held_secondary)
    if((ih.mouse_held.get(.left) or ih.mouse_held.get(.right)) and ih.modsEql(.{})) {
        const target_color = if(ih.mouse_held.get(.left)) controller.data.primary_color else controller.data.secondary_color;
        if(tool.current_line == null) {
            tool.current_line = .{
                .prev_world_pos = world_pos,
                .set_pixels = std.ArrayList(SetPixel).init(core.allocator),
            };
        }
        var lp = math.LinePlotter.init(tool.current_line.?.prev_world_pos, world_pos);
        while(lp.next()) |pos| {
            if(tool.current_line.?.set_pixels.items.len == 0 or @reduce(.Or, tool.current_line.?.prev_world_pos != pos)) {
                try tool.current_line.?.set_pixels.append(.{.pos = pos, .value = target_color});
            }
        }
        tool.current_line.?.prev_world_pos = world_pos;
    }else{
        if(tool.current_line) |*current_line| {
            // commit
            std.log.info("line len: {d}", .{current_line.set_pixels.items.len});
            for(current_line.set_pixels.items) |item| {
                try world.setPixel(item.pos, item.value);
            }


            current_line.set_pixels.deinit(); // TODO: toOwnedSlice and put in operation
            tool.current_line = null;
        }
    }
}
