const std = @import("std");
const Tool = @This();
const App = @import("../main2.zig");

// vtable, data
const Vtable = struct {
    deinit: *const fn(tool: *Data) void,
    update: *const fn(tool: *Data, app: *App) anyerror!void,
    renderUI: *const fn(tool: *Data, app: *App) anyerror!void,
};
const Data = opaque {};

vtable: *const Vtable,
data: *Data,

/// wrap(T: type, tool: *T)
pub fn wrap(comptime ToolType: type, tool_data: *ToolType) Tool {
    const VtableValues = struct {
        fn vtable_deinit(tool: *Data) void {
            return ToolType.deinit(@ptrCast(@alignCast(tool)));
        }
        fn vtable_update(tool: *Data, app: *App) anyerror!void {
            if(!@hasDecl(ToolType, "update")) return;
            return ToolType.update(@ptrCast(@alignCast(tool)), app);
        }
        fn vtable_renderUI(tool: *Data, app: *App) anyerror!void {
            if(!@hasDecl(ToolType, "renderUI")) return;
            return ToolType.renderUI(@ptrCast(@alignCast(tool)), app);
        }

        const vtable = Vtable {
            .deinit = &vtable_deinit,
            .update = &vtable_update,
            .renderUI = &vtable_renderUI,
        };
    };
    return .{
        .vtable = &VtableValues.vtable,
        .data = @alignCast(@ptrCast(tool_data)),
    };
}

pub fn deinit(tool: *Tool) !void {
    return tool.vtable.deinit(tool.data);
}
pub fn update(tool: *Tool, app: *App) !void {
    return tool.vtable.update(tool.data, app);
}
pub fn renderUI(tool: *Tool, app: *App) !void {
    return tool.vtable.renderUI(tool.data, app);
}