const math = @import("math.zig");

const Controls = struct {
    ui: UIControls,
    game: GameControls,
};
const UIControls = struct {
    tool_color_main_0: bool = false,
    tool_color_main_1: bool = false,
    tool_color_main_2: bool = false,
    tool_color_main_3: bool = false,
    tool_color_main_4: bool = false,

    tool_color_alt_0: bool = false,
    tool_color_alt_1: bool = false,
    tool_color_alt_2: bool = false,
    tool_color_alt_3: bool = false,
    tool_color_alt_4: bool = false,
};
const GameControls = struct {
    up_held: bool = false,
    left_held: bool = false,
    down_held: bool = false,
    right_held: bool = false,

    jump_held: bool = false,
    dash_held: bool = false,
};