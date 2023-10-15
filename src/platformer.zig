const std = @import("std");
const math = @import("math.zig");

const Sound = enum{
    hit_ground,
    falling_wind,
};
fn playSound(sound: Sound, volume: f32) void {
    _ = volume;
    _ = sound;
}
const PixelColor = enum{black, dark, light, white};
fn getWorldPixel(pos: Vec2i) PixelColor {
    _ = pos;
    return .black;
}

const x = 0;
const y = 1;

const Vec2f32 = math.Vec2f32;
const Vec2f = Vec2f32;
const Vec2i = math.Vec2i;

const Player = struct {
    pos: Vec2f = Vec2f{100, -100},
    // safe as long as positions remain -16,777,217...16,777,217
    // given that our world is 1,600x1,600 that seems okay.
    vel_gravity: Vec2f = Vec2f{0, 0},
    vel_instant: Vec2f = Vec2f{0, 0},
    vel_dash: Vec2f = Vec2f{0, 0},
    size: Vec2i = Vec2i{4, 4},
    on_ground: u8 = 0,
    dash_used: bool = false,
    jump_used: bool = false,
    disallow_noise: u8 = 0,

    vel_instant_prev: Vec2f = Vec2f{0, 0},

    pub fn posInt(player: Player) Vec2i {
        return Vec2i{
            @intFromFloat(player.pos[x]),
            @intFromFloat(-player.pos[y]),
        };
    }

    pub fn update(player: *Player) void {
        player.vel_gravity = @min(Vec2f{100, 100}, player.vel_gravity);
        player.vel_gravity = @max(Vec2f{-100, -100}, player.vel_gravity);

        if(player.vel_instant[x] == 0) {
            player.vel_instant[x] = player.vel_instant_prev[x];
        }

        const vec_instant = player.vel_gravity + player.vel_instant + player.vel_dash;

        const prev_on_ground = player.on_ground;
        const prev_y_vel = vec_instant[y];

        const step_x_count = @ceil(std.math.fabs(vec_instant[x])) * 2;
        const step_x = if(step_x_count == 0) @as(f32, 0) else vec_instant[x] / step_x_count;
        for(0..@intFromFloat(@ceil(step_x_count))) |_| {
            player.pos[x] += step_x;
            if(player.colliding()) {
                for([_]f32{-1, 1}) |v| {
                    player.pos[y] += v;
                    if(!player.colliding()) break; // note: we should also decrease the velocity
                    player.pos[y] -= v;
                }else{
                    player.pos[x] -= step_x;
                    break;
                }
            }
        }
        const step_y_count = @ceil(std.math.fabs(vec_instant[y])) * 2;
        const step_y = if(step_y_count == 0) @as(f32, 0) else vec_instant[y] / step_y_count;
        for(0..@intFromFloat(step_y_count)) |_| {
            player.pos[y] += step_y;
            if(player.colliding()) {
                for([_]f32{-1, 1}) |v| {
                    player.pos[x] += v;
                    if(!player.colliding()) break; // note: we should also decrease the velocity
                    player.pos[x] -= v;
                }else{
                    player.pos[y] -= step_y;
                    player.vel_gravity[y] = 0;
                    if(step_y < 0) {
                        player.on_ground = 0;
                    }
                    break;
                }
            }else{
                player.on_ground +|= 1;
            }
        }
        if(step_y == 0) {
            player.pos[y] -= 1;
            if(!player.colliding()) {
                player.on_ground +|= 1;
            }
            player.pos[y] += 1;
        }
        // player.vel_instant_prev = player.vel_instant;
        player.vel_instant = Vec2f{0, 0};
        if(player.on_ground == 0) {
            player.dash_used = false;
            player.vel_instant_prev[x] *= 0.6;
            if(prev_on_ground != 0 and player.disallow_noise == 0) {
                const volume_float = @min(@max(-prev_y_vel / 10.0 * 100.0, 0), 100);
                if(volume_float > 5) {
                    playSound(.falling_wind, volume_float);
                }
            }
        }else{
            player.vel_instant_prev[x] *= 0.8;
            if(-player.vel_gravity[y] > 5 and player.disallow_noise == 0) {
                const volume = @max(@min((-player.vel_gravity[y] - 5) / 15, 1.0), 0.0) * 100;
                playSound(.hit_ground, volume);
            }
        }
        player.vel_dash *= @splat(@as(f32, 0.9));
        if(math.magnitude(player.vel_dash) < 0.3) player.vel_gravity[y] -= 0.20;
    }
    pub fn colliding(player: *Player) bool {
        const pos = player.posInt();
        for(0..@intCast(player.size[x])) |x_offset| {
            const value = getWorldPixel(pos + Vec2i{
                @intCast(x_offset),
                0,
            });
            if(value == .black) return true;
        }
        for(0..(@intCast(player.size[x]))) |x_offset| {
            const value = getWorldPixel(pos + Vec2i{
                @intCast(x_offset),
                player.size[y] - 1,
            });
            if(value == .black) return true;
        }
        for(0..(@intCast(player.size[y] - 2))) |y_offset| {
            const value = getWorldPixel(pos + Vec2i{
                0,
                @intCast(y_offset + 1),
            });
            if(value == .black) return true;
        }
        for(0..(@intCast(player.size[y] - 2))) |y_offset| {
            const value = getWorldPixel(pos + Vec2i{
                player.size[x] - 1,
                @intCast(y_offset + 1),
            });
            if(value == .black) return true;
        }
        return false;
    }
};
