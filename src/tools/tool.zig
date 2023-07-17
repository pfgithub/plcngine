pub const ToolDescriptor = struct {

    renderPreview = ?*fn() void,
    input = ?*fn() void,
};