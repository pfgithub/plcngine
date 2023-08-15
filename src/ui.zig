const std = @import("std");
const math = @import("math.zig");
const world_import = @import("world.zig");
const World = world_import.World;
const Chunk = world_import.Chunk;
const CHUNK_SIZE = world_import.CHUNK_SIZE;
const App = @import("main2.zig");
const core = @import("core");
const render = @import("render.zig");

const x = math.x;
const y = math.y;
const z = math.z;
const w = math.w;

const mach = @import("mach");
const gpu = mach.gpu;

const Vec2i = math.Vec2i;
const Vec2f32 = math.Vec2f32;
const vi2f = math.vi2f;
const vf2i = math.vf2i;

const Color = union(enum) {
    pub const transparent = Color{.indexed = 0};
    pub const white = Color{.indexed = 1};
    pub const light = Color{.indexed = 2};
    pub const dark = Color{.indexed = 3};
    pub const black = Color{.indexed = 4};

    indexed: u2,
    rgba: u32,
};

pub const UI = struct {
    vertex_buffer: ?*gpu.Buffer = null,
    bind_group: ?*gpu.BindGroup = null,
    atlas: mach.Atlas,
    texture: ?*gpu.Texture = null,

    pub fn init(ui: *UI) !void {
        ui.* = .{
            .atlas = try mach.Atlas.init(core.allocator, 2048, .rgba), // rgba? should it be grayscale?
        };
    }

    pub fn deinit(ui: *UI) void {
        if(ui.vertex_buffer) |b| b.release();
        if(ui.bind_group) |b| b.release();
        if(ui.texture) |b| b.release();
        ui.atlas.deinit(core.allocator);
    }

    pub fn prepare(ui: *UI,
        encoder: *gpu.CommandEncoder,
        uniform_buffer: *gpu.Buffer,
    ) !void {
        var first_init = false;
        const img_size = gpu.Extent3D{
            .width = ui.atlas.size,
            .height = ui.atlas.size,
        };
        if(ui.texture == null) {
            ui.texture = core.device.createTexture(&.{
                .size = img_size,
                .format = switch(ui.atlas.format) {
                    .rgba => gpu.Texture.Format.rgba8_unorm,
                    else => @panic("TODO"),
                },
                .usage = .{
                    .texture_binding = true,
                    .copy_dst = true,
                    .render_attachment = true,
                },
            });
            first_init = true;
        }
        if(ui.atlas.modified or first_init) {
            ui.atlas.modified = false;
            const data_layout = gpu.Texture.DataLayout{
                .bytes_per_row = ui.atlas.size * ui.atlas.format.depth(),
                .rows_per_image = ui.atlas.size, // height
            };
            App.instance.queue.writeTexture(&.{ .texture = ui.texture.? }, &data_layout, &img_size, ui.atlas.data);
        }

        var vertices = std.ArrayList(App.Vertex).init(core.allocator);
        defer vertices.deinit();

        try sample(&vertices);

        if(ui.vertex_buffer) |b| b.release();
        ui.vertex_buffer = core.device.createBuffer(&.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = @sizeOf(App.Vertex) * vertices.items.len,
            .mapped_at_creation = .false,
        });
        encoder.writeBuffer(ui.vertex_buffer.?, 0, vertices.items);

        const sampler = core.device.createSampler(&.{
            .mag_filter = .nearest,
            .min_filter = .nearest,
        });
        defer sampler.release();

        const texture_view = ui.texture.?.createView(&gpu.TextureView.Descriptor{});
        defer texture_view.release();

        if(ui.bind_group) |prev_bg| prev_bg.release();
        ui.bind_group = core.device.createBindGroup(
            &gpu.BindGroup.Descriptor.init(.{
                .layout = App.instance.pipeline.getBindGroupLayout(0),
                .entries = &.{
                    gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(App.UniformBufferObject)),
                    gpu.BindGroup.Entry.sampler(1, sampler),
                    gpu.BindGroup.Entry.textureView(2, texture_view),
                },
            }),
        );
    }

    pub fn render(ui: *UI,
        pass: *gpu.RenderPassEncoder,
    ) !void {
        const vb_size = ui.vertex_buffer.?.getSize();
        pass.setVertexBuffer(0, ui.vertex_buffer.?, 0, vb_size);
        pass.setBindGroup(0, ui.bind_group.?, &.{});
        pass.draw(@intCast(vb_size / @sizeOf(App.Vertex)), 1, 0, 0);
    }
};

pub fn sample(vertices: *std.ArrayList(App.Vertex)) !void {
    const final_size = Vec2i{80, 80};

    try vertices.appendSlice(&render.vertexRect(.{
        .ul = .{10, 10},
        .br = .{10 + @as(f32, @floatFromInt(final_size[0])), 10 + @as(f32, @floatFromInt(final_size[1]))},
        .draw_colors = 0o33332,
        .border_radius = 10.0,
        .border = 2.0,
    }));
}
