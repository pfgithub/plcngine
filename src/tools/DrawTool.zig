const DrawTool = @This();
const App = @import("../main2.zig");
const math = @import("../math.zig");

const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vf2i = math.vf2i;

pen_primary_color: u8 = 1,
pen_secondary_color: u8 = 0,
prev_world_pos: ?Vec2i = null,

// tool: click & drag : draws to the overlay & presence
// on release, commit the action to the world

pub fn update(tool: *DrawTool, app: *App) !void {
    const render = app.render;
    const world = app.world;
    const ih = &app.ih;

    const mp = app.ih.mouse_pos orelse Vec2f32{-1, -1};

    const world_pos = vf2i(render.screenToWorldPos(mp));
    // if(controls.pen_held_primary or controls.pen_held_secondary)
    if((ih.mouse_held.get(.left) or ih.mouse_held.get(.right)) and ih.modsEql(.{})) {
        const target_color = if(ih.mouse_held.get(.left)) tool.pen_primary_color else tool.pen_secondary_color;
        if(tool.prev_world_pos == null) tool.prev_world_pos = world_pos;
        var lp = math.LinePlotter.init(tool.prev_world_pos.?, world_pos);
        while(lp.next()) |pos| {
            try world.setPixel(pos, target_color);
        }
        tool.prev_world_pos = world_pos;
    }else{
        tool.prev_world_pos = null;
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