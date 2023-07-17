const td = @import("tool.zig");

const State = struct {
    prev_pos: ?Vec2i,
};
const Config = struct {
    width: i32,
};

const Tool = struct {
    config: Config,
    state: State,

    pub fn input(ev) {
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
    pub fn renderPreview() {
        // renders the preview
    }

    pub fn descriptor(tool: *Tool) td.ToolDescriptor {
        return .{
            .renderPreview = renderPreview,
            .input = input,
        };
    },
};

// export common interface
