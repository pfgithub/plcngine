const std = @import("std");
const App = @import("main2.zig");
const render = @import("render.zig");
const math = @import("math.zig");
const Vec2i = math.Vec2i;

const Color = union(enum) {
    pub const transparent = Color{.indexed = 0};
    pub const white = Color{.indexed = 1};
    pub const light = Color{.indexed = 2};
    pub const dark = Color{.indexed = 3};
    pub const black = Color{.indexed = 4};

    indexed: u2,
    rgba: u32,
};

const ui = struct {
    const Globals = struct {
        arena: ?std.heap.ArenaAllocator,
    };
    var globals: Globals = .{
        .arena = undefined,
    };
    fn alloc() std.mem.Allocator {
        return ui.globals.arena.?.allocator();
    }
};

pub fn startVList() void {

}
pub fn endVList() void {

}

const Constraints = struct {x: ?i32, y: ?i32};
const ContainerHandler = struct {
    data: usize,
    get_constraints: *const fn(val: usize) UIError!Constraints,
    post_child: *const fn(val: usize, size: Vec2i) UIError!void,
};
pub fn startContainer(handler: *const ContainerHandler) void {
    _ = handler;
}
pub fn endContainer() void {

}

const UIError = error{UI_TemporaryError, UI_PermanentError, OutOfMemory};

pub fn sample(vertices: *std.ArrayList(App.Vertex)) UIError!void {
    if(ui.globals.arena == null) {
        ui.globals.arena = std.heap.ArenaAllocator.init(vertices.allocator);
    }else{
        _ = ui.globals.arena.?.reset(.retain_capacity);
    }

    const result_size: ?*Vec2i = null;

    startContainer(&.{
        .data = 0,
        .get_constraints = &struct {fn f(data: usize) UIError!Constraints {
            _ = data;
            return .{.x = null, .y = null};
        }}.f,
        .post_child = &struct {fn f(data: usize, size: Vec2i) UIError!void {
            const data_ptr: ?*Vec2i = @ptrFromInt(data);
            if(data_ptr != null) return error.UI_PermanentError;
            data_ptr.?.* = size;
        }}.f,
    });
    //startVList();
    //useSize(.{16, 16});
    //useSize(.{16, 16});
    //endVList();
    endContainer();

    const final_size = result_size orelse Vec2i{80, 80};

    try vertices.appendSlice(&render.vertexRect(.{
        .ul = .{10, 10},
        .br = .{10 + @as(f32, @floatFromInt(final_size[0])), 10 + @as(f32, @floatFromInt(final_size[1]))},
        .draw_colors = 0o33332,
        .border_radius = 10.0,
        .border = 2.0,
    }));
}
