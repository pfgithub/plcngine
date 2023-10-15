const std = @import("std");
const math = @import("math.zig");
const controls_mod = @import("controls.zig");
const GameControls = controls_mod.GameControls;
const world_mod = @import("world.zig");
const World = world_mod.World;

const Sound = enum{
    hit_ground,
    falling_wind,
    dash,
};
fn playSound(sound: Sound, volume: f32) void {
    _ = volume;
    _ = sound;
}
fn getCollisionPixel(world: *World, pos: Vec2i) !bool {
    const result = try world.getPixel(pos);
    return switch(result) {
        1 => true,
        else => false,
    };
}

const x = 0;
const y = 1;

const Vec2f32 = math.Vec2f32;
const Vec2f = Vec2f32;
const Vec2i = math.Vec2i;

pub const Player = struct {
    // safe as long as positions remain -16,777,217...16,777,217
    // maybe this should be a f64
    pos: Vec2f = Vec2f{100, -100},
    vel_gravity: Vec2f = Vec2f{0, 0},
    vel_instant: Vec2f = Vec2f{0, 0},
    vel_dash: Vec2f = Vec2f{0, 0},
    size: Vec2i = Vec2i{8, 8},
    on_ground: u8 = 0,
    dash_used: bool = false,
    disallow_noise: u8 = 0,
    vel_instant_prev: Vec2f = Vec2f{0, 0},

    jump_button_pressed: bool = false,
    dash_key_used: bool = false,

    abilities: struct {
        dash_unlocked: bool = false,
    } = .{},

    pub fn posInt(player: Player) Vec2i {
        return Vec2i{
            @intFromFloat(@floor(player.pos[x])),
            @intFromFloat(@floor(player.pos[y])),
        };
    }

    pub fn update(player: *Player, world: *World, controls: *const GameControls) !void {
        var flying = false;

        if(!controls.dash_held) {
            player.dash_key_used = false;
        }
        if(controls.dash_held and player.abilities.dash_unlocked and !player.dash_used and !player.dash_key_used) {
            var dir = Vec2f{0, 0};
            if(controls.left_held) {
                dir[x] -= 1;
            }
            if(controls.right_held) {
                dir[x] += 1;
            }
            if(controls.up_held) {
                dir[y] -= 1;
            }
            if(controls.down_held) {
                dir[y] += 1;
            }
            if(dir[x] != 0 or dir[y] != 0) {
                player.dash_key_used = true;
                dir = math.normalize(dir);
                player.dash_used = true;
                player.vel_dash = dir * @as(Vec2f, @splat(2.2));
                player.vel_gravity = Vec2f{0, 0};
                if(player.disallow_noise == 0) {
                    playSound(.dash, 41);
                    player.disallow_noise = 10;
                }
            }
        }
        if(controls.left_held) {
            player.vel_instant += Vec2f{-1, 0};
        }
        if(controls.right_held) {
            player.vel_instant += Vec2f{1, 0};
        }
        if(!player.jump_button_pressed and controls.jump_held and player.on_ground <= 6 and math.magnitude(player.vel_dash) < 0.3) {
            player.vel_gravity[y] = -2.2;
            player.on_ground = std.math.maxInt(u8);
            player.jump_button_pressed = true;
        }
        if(!controls.jump_held) player.jump_button_pressed = false;

        player.disallow_noise -|= 1;

        if(!flying) try player.updateNext(world);
    }
    fn updateNext(player: *Player, world: *World) !void {
        player.vel_gravity = @min(Vec2f{100, 100}, player.vel_gravity);
        player.vel_gravity = @max(Vec2f{-100, -100}, player.vel_gravity);

        if(player.vel_instant[x] == 0) {
            player.vel_instant[x] = player.vel_instant_prev[x];
        }

        const vec_instant = player.vel_gravity + player.vel_instant + player.vel_dash;

        const prev_on_ground = player.on_ground;
        const prev_y_vel = vec_instant[y];

        const step_x_count = @ceil(@abs(vec_instant[x])) * 2;
        const step_x = if(step_x_count == 0) @as(f32, 0) else vec_instant[x] / step_x_count;
        for(0..@intFromFloat(@ceil(step_x_count))) |_| {
            player.pos[x] += step_x;
            if(try player.colliding(world)) {
                for([_]f32{-1, 1}) |v| {
                    player.pos[y] += v;
                    if(!(try player.colliding(world))) break; // note: we should also decrease the velocity
                    player.pos[y] -= v;
                }else{
                    player.pos[x] -= step_x;
                    break;
                }
            }
        }
        const step_y_count = @ceil(@abs(vec_instant[y])) * 2;
        const step_y = if(step_y_count == 0) @as(f32, 0) else vec_instant[y] / step_y_count;
        for(0..@intFromFloat(step_y_count)) |_| {
            player.pos[y] += step_y;
            if(try player.colliding(world)) {
                for([_]f32{-1, 1}) |v| {
                    player.pos[x] += v;
                    if(!(try player.colliding(world))) break; // note: we should also decrease the velocity
                    player.pos[x] -= v;
                }else{
                    player.pos[y] -= step_y;
                    player.vel_gravity[y] = 0;
                    if(step_y > 0) {
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
            if(!(try player.colliding(world))) {
                player.on_ground +|= 1;
            }
            player.pos[y] += 1;
        }
        player.vel_instant = Vec2f{0, 0};
        if(player.on_ground == 0) {
            player.dash_used = false;
            player.vel_instant_prev[x] *= 0.6;
            if(prev_on_ground != 0 and player.disallow_noise == 0) {
                const volume_float = @min(@max(prev_y_vel / 10.0 * 100.0, 0), 100);
                if(volume_float > 5) {
                    playSound(.falling_wind, volume_float);
                }
            }
        }else{
            player.vel_instant_prev[x] *= 0.8;
            if(player.vel_gravity[y] > 5 and player.disallow_noise == 0) {
                const volume = @max(@min((player.vel_gravity[y] - 5) / 15, 1.0), 0.0) * 100;
                playSound(.hit_ground, volume);
            }
        }
        player.vel_dash *= @splat(@as(f32, 0.9));
        if(math.magnitude(player.vel_dash) < 0.3) player.vel_gravity[y] += 0.20;
    }
    pub fn colliding(player: *Player, world: *World) !bool {
        const pos = player.posInt();
        for(0..@intCast(player.size[x])) |x_offset| {
            const collision = try getCollisionPixel(world, pos + Vec2i{
                @intCast(x_offset),
                0,
            });
            if(collision) return true;
        }
        for(0..(@intCast(player.size[x]))) |x_offset| {
            const collision = try getCollisionPixel(world, pos + Vec2i{
                @intCast(x_offset),
                player.size[y] - 1,
            });
            if(collision) return true;
        }
        for(0..(@intCast(player.size[y] - 2))) |y_offset| {
            const collision = try getCollisionPixel(world, pos + Vec2i{
                0,
                @intCast(y_offset + 1),
            });
            if(collision) return true;
        }
        for(0..(@intCast(player.size[y] - 2))) |y_offset| {
            const collision = try getCollisionPixel(world, pos + Vec2i{
                player.size[x] - 1,
                @intCast(y_offset + 1),
            });
            if(collision) return true;
        }
        return false;
    }
};
