pub const ToolDescriptor = struct {
    content: *opaque{},
    renderPreview = ?*fn() void,
    input = ?*fn() void,
};