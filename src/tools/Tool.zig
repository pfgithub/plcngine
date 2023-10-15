const std = @import("std");
const Tool = @This();
const App = @import("../main2.zig");

// vtable, data
const Vtable = struct {
    update: *const fn(tool: *Data, app: *App) anyerror!void,
};
const Data = opaque {};

vtable: *const Vtable,
data: *Data,

/// wrap(T: type, tool: *T)
pub fn wrap(comptime ToolType: type, tool_data: *ToolType) Tool {
    const VtableValues = struct {
        fn vtable_update(tool: *Data, app: *App) anyerror!void {
            return ToolType.update(@ptrCast(@alignCast(tool)), app);
        }

        const vtable = Vtable {
            .update = &vtable_update,
        };
    };
    return .{
        .vtable = &VtableValues.vtable,
        .data = @alignCast(@ptrCast(tool_data)),
    };
}

pub fn update(tool: *Tool, app: *App) !void {
    return tool.vtable.update(tool.data, app);
}