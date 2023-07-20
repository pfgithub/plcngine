const td = @import("tool.zig");

const State = struct {
    prev_pos: ?Vec2i = null,
    // TODO: store the full line & then put it all in one transaction
};
const Config = struct {
    width: i32 = 1,
};

const Tool = struct {
    config: Config = .{},
    state: State = .{},

    pub fn init() Tool {
        return .{};
    }
    pub fn deinit(_: *Tool) void {}

    pub fn input(tool: *Tool, ev) {
        const state = &tool.state;

        const world = ev.world;
        const world_pos = ev.mouse_pos;
        // updates the image
        switch(ev.current) {
            .mouse_down, .mouse_move, .mouse_up => {
                if(state.prev_world_pos == null) state.prev_world_pos = world_pos;
                var lp = math.LinePlotter.init(state.prev_world_pos.?, world_pos);
                while(lp.next()) |pos| {
                    try world.setPixel(pos, 255);
                }

                if(ev.current == .mouse_up) {
                    state.prev_world_pos = null;
                }
            },
        }
    }
    pub fn renderPreview(_: *Tool) {
        // renders the preview
    }

    pub fn descriptor(tool: *Tool) td.ToolDescriptor {
        return .{
            .content = @ptrCast(tool),
            .renderPreview = fn{
                fn aa(tool: *opaque{}) {
                    return renderPreview(@ptrCast(tool));
                }
            }.a,
            .input = fn{
                fn aa(tool: *opaque{}) {
                    return input(@ptrCast(tool));
                }
            }.aa,
        };
    },
};

// export common interface
