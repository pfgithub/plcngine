// A simple tone engine.
//
// It renders 512 tones simultaneously, each with their own frequency and duration.
//
// `keyToFrequency` can be used to convert a keyboard key to a frequency, so that the
// keys asdfghj on your QWERTY keyboard will map to the notes C/D/E/F/G/A/B[4], the
// keys above qwertyu will map to C5 and the keys below zxcvbnm will map to C3.
//
// The duration is hard-coded to 1.5s. To prevent clicking, tones are faded in linearly over
// the first 1/64th duration of the tone. To provide a cool sustained effect, tones are faded
// out using 1-log10(x*10) (google it to see how it looks, it's strong for most of the duration of
// the note then fades out slowly.)
const std = @import("std");
const mach = @import("mach");
const builtin = @import("builtin");
const sysaudio = mach.sysaudio;

pub const App = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const MAX_TONES = 16;

audio_ctx: sysaudio.Context,
player: sysaudio.Player,
playing: [MAX_TONES]Tone,
sample_counter: u32,

const Tone = struct {
    frequency: f32,
    start_time: u32,
    end_time: u32,
    wave: Wave,
};

const Wave = enum{
    triangle,
    sin,
    square,
    sawtooth,

    fn exec(wave: Wave, f: f32) f32 {
        const fv: f32 = f * 2.0;
        return switch(wave) {
            .triangle => @fabs(@mod(fv, 2) - 1),
            .sin => std.math.sin(fv * std.math.pi),
            .square => if(@mod(fv, 2) > 1.0) 0.2 else -0.2,
            .sawtooth => (@mod(fv, 2) - 1) * 0.4,
        };
    }
};

var DEFAULT_WAVE: Wave = .square;

pub fn init(app: *App) !void {
    try mach.core.init(.{});

    app.sample_counter = 0;
    app.playing = [_]Tone{.{.frequency = 0, .start_time = 0, .end_time = 0, .wave = DEFAULT_WAVE}} ** MAX_TONES;

    app.audio_ctx = try sysaudio.Context.init(null, gpa.allocator(), .{});
    errdefer app.audio_ctx.deinit();
    try app.audio_ctx.refresh();

    const device = app.audio_ctx.defaultDevice(.playback) orelse return error.NoDeviceFound;
    app.player = try app.audio_ctx.createPlayer(device, writeFn, .{ .user_data = app });
    try app.player.start();
}

pub fn deinit(app: *App) void {
    defer _ = gpa.deinit();
    defer mach.core.deinit();

    app.player.deinit();
    app.audio_ctx.deinit();
}

pub fn update(app: *App) !bool {
    var iter = mach.core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                const vol = try app.player.volume();
                switch (ev.key) {
                    .down => try app.player.setVolume(@max(0.0, vol - 0.1)),
                    .up => try app.player.setVolume(@min(1.0, vol + 0.1)),
                    .one => DEFAULT_WAVE = .sin,
                    .two => DEFAULT_WAVE = .triangle,
                    .three => DEFAULT_WAVE = .square,
                    .four => DEFAULT_WAVE = .sawtooth,
                    else => {},
                }

                app.fillTone(keyToFrequency(ev.key));
            },
            .key_release => |ev| {
                app.delTone(keyToFrequency(ev.key));
            },
            .close => return true,
            else => {},
        }
    }

    if (builtin.cpu.arch != .wasm32) {
        const back_buffer_view = mach.core.swap_chain.getCurrentTextureView().?;

        mach.core.swap_chain.present();
        back_buffer_view.release();
    }

    return false;
}

fn writeFn(app_op: ?*anyopaque, frames: usize) void {
    const app: *App = @ptrCast(@alignCast(app_op));


    //const a_sample_counter: f32 = @floatFromInt(app.sample_counter);
    const sample_rate: f32 = @floatFromInt(app.player.sampleRate());

    for (0..frames) |frame| {
        var sample: f32 = 0;
        //const sample_counter: f32 = @floatFromInt(frame);

        app.sample_counter +%= 1;
        const sample_counter: f32 = @floatFromInt(app.sample_counter);

        for (&app.playing) |*tone| {
            if (tone.frequency == 0) continue;
            if (tone.end_time < app.sample_counter) continue;

            const tone_sample_counter: f32 = @floatFromInt(app.sample_counter -% tone.start_time);
            const tone_end_counter: f32 = @floatFromInt(tone.end_time -% app.sample_counter);
            const duration: f32 = TONE_START_SEC * sample_rate;
            const end_duration: f32 = TONE_END_SEC * sample_rate;

            // The sine wave that plays the frequency.
            const gain = 0.1;
            const sine_wave = DEFAULT_WAVE.exec(tone.frequency * sample_counter / sample_rate) * gain;

            const fade_in = @max(@min(tone_sample_counter / duration, 1.0), 0.0);

            // A number ranging from 1.0 to 0.0 over half the duration of the tone.
            var fade_out = @max(@min(tone_end_counter / end_duration, 1.0), 0.0);
            if(tone.end_time == std.math.maxInt(u32)) fade_out = 1.0;

            // Mix this tone into the sample we'll actually play on e.g. the speakers, reducing
            // sine wave intensity if we're fading in or out over the entire duration of the
            // tone.
            sample += sine_wave * fade_in * fade_out;
        }

        // Emit the sample on all channels.
        app.player.writeAll(frame, sample);
    }
}

const TONE_START_SEC: f32 = 0.01;
const TONE_END_SEC: f32 = 0.01;

pub fn fillTone(app: *App, frequency: f32) void {
    for (&app.playing) |*tone| {
        if (tone.frequency == 0 or tone.end_time < app.sample_counter) { // will break on wrap
            tone.* = Tone{
                .frequency = frequency,
                .start_time = app.sample_counter,
                .end_time = std.math.maxInt(u32),
                .wave = DEFAULT_WAVE,
            };
            return;
        }
    }
}

pub fn delTone(app: *App, frequency: f32) void {
    const sample_rate: f32 = @floatFromInt(app.player.sampleRate());
    for (&app.playing) |*tone| {
        if (tone.frequency == frequency and tone.end_time == std.math.maxInt(u32)) {
            tone.end_time = app.sample_counter +% @as(u32, @intFromFloat(TONE_END_SEC * sample_rate));
        }
    }
}

pub fn keyToFrequency(key: mach.core.Key) f32 {
    // The frequencies here just come from a piano frequencies chart. You can google for them.
    return switch (key) {
        // First row of piano keys, the highest.
        .q => 523.25, // C5
        .w => 587.33, // D5
        .e => 659.26, // E5
        .r => 698.46, // F5
        .t => 783.99, // G5
        .y => 880.0, // A5
        .u => 987.77, // B5
        .i => 1046.5, // C6
        .o => 1174.7, // D6
        .p => 1318.5, // E6
        .left_bracket => 1396.9, // F6
        .right_bracket => 1568.0, // G6

        // Second row of piano keys, the middle.
        .a => 261.63, // C4
        .s => 293.67, // D4
        .d => 329.63, // E4
        .f => 349.23, // F4
        .g => 392.0, // G4
        .h => 440.0, // A4
        .j => 493.88, // B4
        .k => 523.25, // C5
        .l => 587.33, // D5
        .semicolon => 659.26, // E5
        .apostrophe => 698.46, // F5

        // Third row of piano keys, the lowest.
        .z => 130.81, // C3
        .x => 146.83, // D3
        .c => 164.81, // E3
        .v => 174.61, // F3
        .b => 196.00, // G3
        .n => 220.0, // A3
        .m => 246.94, // B3
        .comma => 261.63, // C4
        .period => 293.67, // D4
        .slash => 329.63, // E5
        else => 0.0,
    };
}
