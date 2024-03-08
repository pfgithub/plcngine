const std = @import("std");
const math = @import("math.zig");
const world_import = @import("world.zig");
const World = world_import.World;
const Chunk = world_import.Chunk;
const CHUNK_SIZE = world_import.CHUNK_SIZE;
const App = @import("main2.zig");
const render = @import("render.zig");

const msdf = @import("msdf").msdf;

const x = math.x;
const y = math.y;
const z = math.z;
const w = math.w;

const core = @import("mach").core;
const gpu = core.gpu;
const Atlas = @import("vendor/mach_gfx_atlas.zig");

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
    atlas: Atlas,
    texture: ?*gpu.Texture = null,
    text_render: TextRender,

    pub fn init(ui: *UI) !void {
        var atlas = try Atlas.init(core.allocator, 2048, .rgba);
        errdefer atlas.deinit(core.allocator);

        var text_render = try TextRender.init(core.allocator);
        errdefer text_render.deinit();

        ui.* = .{
            .atlas = atlas,
            .text_render = text_render,
        };
    }

    pub fn deinit(ui: *UI) void {
        if(ui.vertex_buffer) |b| b.release();
        if(ui.bind_group) |b| b.release();
        if(ui.texture) |b| b.release();
        ui.text_render.deinit();
        ui.atlas.deinit(core.allocator);
    }

    pub fn prepare(ui: *UI,
        encoder: *gpu.CommandEncoder,
        uniform_buffer: *gpu.Buffer,
    ) !void {
        // 1. render the interface
        var vertices = std.ArrayList(App.Vertex).init(core.allocator);
        defer vertices.deinit();

        try sample(ui, &vertices);

        // 2. update the buffers & images
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

pub fn sample(ui: *UI, vertices: *std.ArrayList(App.Vertex)) !void {
    const final_size = Vec2i{80, 80};

    try vertices.appendSlice(&render.vertexRect(.{
        .ul = .{10, 10},
        .br = .{10 + @as(f32, @floatFromInt(final_size[0])), 10 + @as(f32, @floatFromInt(final_size[1]))},
        .draw_colors = 0o22223,
        .border_radius = 10.0,
        .border = 2.0,
    }));

    try textSample(&ui.text_render);
}

fn once(comptime _: std.builtin.SourceLocation) bool {
    const data = struct {
        var activated: bool = false;
    };
    if(data.activated) return false;
    data.activated = true;
    return true;
}

const TextGlyph = struct {
    bitmap: *msdf.cz_Bitmap3f,
    fn init(text_render: *TextRender, glyph: u32) !TextGlyph {
        const shape: *msdf.cz_Shape = msdf.cz_createShape() orelse return error.LoadShape;
        defer msdf.cz_destroyShape(shape);

        var advance: f64 = undefined;
        if(!msdf.cz_loadGlyph(shape, text_render.font, glyph, &advance)) return error.LoadGlyph;

        msdf.cz_shapeNormalize(shape);

        const bitmap: *msdf.cz_Bitmap3f = msdf.cz_createBitmap3f(16, 16) orelse return error.CreateBitmap;
        errdefer msdf.cz_destroyBitmap3f(bitmap);

        msdf.cz_generateMSDF(bitmap, shape, 1.0, 1.0, 4.0, 4.0, 4.0); // scale.x, scale.y, translation.x, translation.y, range

        return .{
            .bitmap = bitmap,
        };
    }
    fn deinit(glyph: *TextGlyph) void {
        msdf.cz_destroyBitmap3f(glyph.bitmap);
    }
};
const TextRender = struct {
    ft: *msdf.FreetypeHandle,
    font: *msdf.FontHandle,
    glyphs: std.AutoHashMap(u32, TextGlyph), // {font, size, glyph_u32} => Glyph

    pub fn init(alloc: std.mem.Allocator) !TextRender {
        const font_data = @embedFile("data/NotoSans-Regular.ttf");

        const ft: *msdf.FreetypeHandle = msdf.cz_initializeFreetype() orelse return error.InitializeFreetype;
        errdefer msdf.cz_deinitializeFreetype(ft);

        const font: *msdf.FontHandle = msdf.cz_loadFontData(ft, @ptrCast(font_data.ptr), @intCast(font_data.len)) orelse return error.LoadFont;
        errdefer msdf.cz_destroyFont(font);

        var glyphs = std.AutoHashMap(u32, TextGlyph).init(alloc);
        errdefer glyphs.deinit();

        return .{
            .ft = ft,
            .font = font,
            .glyphs = glyphs,
        };
    }

    pub fn deinit(text_render: *TextRender) void {
        var glyphs_iter = text_render.glyphs.iterator();
        while(glyphs_iter.next()) |item| {
            item.value_ptr.deinit();
        }
        text_render.glyphs.deinit();
        msdf.cz_destroyFont(text_render.font);
        msdf.cz_deinitializeFreetype(text_render.ft);
    }

    pub fn getOrRenderGlyph(text_render: *TextRender, glyph: u32) !TextGlyph {
        const result = try text_render.glyphs.getOrPut(glyph);
        if(!result.found_existing) {
            errdefer if(!text_render.glyphs.remove(glyph)) unreachable;
            result.value_ptr.* = try TextGlyph.init(text_render, glyph);
        }
        return result.value_ptr.*;
    }
};

pub fn textSample(text_render: *TextRender) !void {
    const glyph = try text_render.getOrRenderGlyph('B');

    if(once(@src())) {
        std.log.info("msdfgen success! {d} {d}", .{
            msdf.cz_bitmap3fWidth(glyph.bitmap),
            msdf.cz_bitmap3fHeight(glyph.bitmap),
            // msdf.cz_bitmap3fData(bitmap),
        });
    }


    // TODO: add to texture atlas & render

    // Shape shape;
    // if (loadGlyph(shape, font, 'A')) {
    //     shape.normalize();
    //     //                      max. angle
    //     edgeColoringSimple(shape, 3.0);
    //     //           image width, height
    //     Bitmap<float, 3> msdf(32, 32);
    //     //                     range, scale, translation
    //     generateMSDF(msdf, shape, 4.0, 1.0, Vector2(4.0, 4.0));
    //     savePng(msdf, "output.png");
    // }
}

// rendering:
// opaque:
// - any order, write to depth buffer
// transparent:
// - back to front, switch shader programs in the middle if needed.

// text shadows & outlines:
// - if we add a regular sdf to the alpha channel, we could use that for shadows and outlines
// - use generateMTSDF for this

// if msdf isn't good for small text / thin fonts / cjk / too much texture memory:
// - freetype provides glyph rasterization, and mach has bindings for it
// - we will need harfbuzz for layout eventually. mach also provides harfbuzz
// - consider using msdf when larger than a given size

// if msdf is too slow:
// - https://github.com/nyyManni/msdfgl