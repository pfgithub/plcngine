const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});
const math = @import("math.zig");

const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vi2f = math.vi2f;
const vf2i = math.vf2i;

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
