// vtable, data
const Vtable = struct {
    update(tool: *DrawTool, app: *App)
};
const Data = opaque {};

vtable: *const Vtable,
data: *Data,