const std = @import("std");
pub const x = 0;
pub const y = 1;
pub const z = 2;
pub const w = 3;

pub const Vec2i = @Vector(2, i32);
pub const Vec2f32 = @Vector(2, f32);
pub fn vi2f(vi: Vec2i) Vec2f32 {
    return .{@floatFromInt(vi[0]), @floatFromInt(vi[1])};
}
pub fn vf2i(vfv: Vec2f32) Vec2i {
    const vf = @floor(vfv);
    return .{@intFromFloat(vf[0]), @intFromFloat(vf[1])};
}

pub const LinePlotter = struct {
    x0: i32,
    x1: i32,
    y0: i32,
    y1: i32,

    dx: i32,
    dy: i32,
    sx: i32,
    sy: i32,
    err: i32,
    done: bool = false,

    pub fn init(start: Vec2i, end: Vec2i) LinePlotter {
        const x0: i32 = start[0];
        const x1: i32 = end[0];
        const y0: i32 = start[1];
        const y1: i32 = end[1];

        const dx: i32 = (std.math.absInt(x1 - x0) catch unreachable);
        const dy: i32 = -(std.math.absInt(y1 - y0) catch unreachable);
        const sx: i32 = if(x0 < x1) 1 else -1;
        const sy: i32 = if(y0 < y1) 1 else -1;
        const err = dx + dy;

        return .{
            .x0 = x0, .x1 = x1, .y0 = y0, .y1 = y1,
            .dx = dx, .dy = dy, .sx = sx, .sy = sy,
            .err = err,
        };
    }
    pub fn next(lp: *LinePlotter) ?Vec2i {
        if(lp.done) return null;
        const res = Vec2i{lp.x0, lp.y0};
        if(lp.x0 == lp.x1 and lp.y0 == lp.y1) {
            lp.done = true;
            return res;
        }
        const e2: i32 = 2 * lp.err;
        if(e2 >= lp.dy) {
            lp.err += lp.dy;
            lp.x0 += lp.sx;
        }
        if(e2 <= lp.dx) {
            lp.err += lp.dx;
            lp.y0 += lp.sy;
        }
        return res;
    }
};
