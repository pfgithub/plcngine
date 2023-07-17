const std = @import("std");
const Instant = std.time.Instant;
const FramerateCounter = @This();

const SMOOTH_LEN = 5;
const instant_zero = std.mem.zeroes(Instant);

frame_times: [SMOOTH_LEN]u64 = [1]u64{0} ** SMOOTH_LEN,
last_frame_time: Instant,

pub fn init() FramerateCounter {
    return .{
        .last_frame_time = Instant.now() catch instant_zero,
    };
}

pub fn onFrame(frc: *FramerateCounter) void {
    const current_frame_time: Instant = Instant.now() catch instant_zero;
    const frame_time = current_frame_time.since(frc.last_frame_time);
    frc.last_frame_time = current_frame_time;

    for(0..SMOOTH_LEN - 1) |i| {
        frc.frame_times[i] = frc.frame_times[i + 1];
    }
    frc.frame_times[SMOOTH_LEN - 1] = frame_time;
}

pub fn getFramerate(frc: *FramerateCounter) f64 {
    var sum: f64 = 0;
    for(frc.frame_times) |ft| {
        sum += @floatFromInt(ft);
    }
    const average: f64 = sum / SMOOTH_LEN; // nanoseconds
    return 1000000000.0 / average;
}

// /*
//
// class FramerateCounter {
//     private frame_times: number[];
//     private last_frame_time: number;
//
//     constructor() {
//         this.frame_times = [];
//     }
//
//     onFrame() {
//         const currentFrameTime = performance.now();
//         const frameTime = currentFrameTime - this.last_frame_time;
//         this.last_frame_time = currentFrameTime;
//
//         if (this.frame_times.length > 5) {
//             this.frame_times.shift();
//         }
//         this.frame_times.push(frameTime);
//     }
//
//     getFramerate() {
//         const averageFrameTime = this.frame_times.reduce((a, b) => a + b, 0) / this.frame_times.length;
//         return 1000 / averageFrameTime;
//     }
// }
// */
