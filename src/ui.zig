const std = @import("std");
const App = @import("main2.zig");
const render = @import("render.zig");

const Color = union(enum) {
    pub const transparent = Color{.indexed = 0};
    pub const white = Color{.indexed = 1};
    pub const light = Color{.indexed = 2};
    pub const dark = Color{.indexed = 3};
    pub const black = Color{.indexed = 4};

    indexed: u2,
    rgba: u32,
};

pub fn sample(vertices: *std.ArrayList(App.Vertex)) !void {
    try vertices.appendSlice(&render.vertexRect(.{
        .ul = .{10, 10},
        .br = .{90, 190},
        .draw_colors = 0o33332,
        .border_radius = 10.0,
        .border = 2.0,
    }));
}
