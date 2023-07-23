// render quads with info on:
// -
// used for:
// - rounded rectangles + shadows
// - text
// render back to front for transparency support
// borders :
// - render two rectangles
// shadow :
// - render a rectangle with shadow props set

// vertex :
// - pos(vec2) (screenspace, px)
// - rounding(vec4) (screenspace, px, one value per corner)
// - vertex_rounding(f32) (screenspace, px radius)
// - corner(f32) (0..4 index)
// - uv(vec2) (use for color or image fill)
// shadow:
// - blur radius, offset, expand
// vertex shader will:
// - expand position to cover shadow area, if necessary

struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) texUV : vec2<f32>,
    @location(1) rectPos : vec2<f32>, // 0..1 based on the rect position
    // @location(2) rounding : vec2<f32>, // 0..(0.5) radius for rounding on a 1.0 sized rect
};

@vertex
fn vertex_main(
    @location(0) position : vec4<f32>,
    @location(1) uv : vec2<f32>,
    @location(2) rounding: f32,
    @location(3) corner: vec2<f32>,
) -> VertexOutput {
    var output: VertexOutput;
    var xy: vec2<f32> = position.xy / uniforms.screen_size * 2.0 - 1.0;
    output.Position = vec4(xy.x, 0.0 - xy.y, position.zw);
    output.texUV = uv;

    output.rectPos = corner;
    // ignore rounding for now

    return output;
}

// => fragment shader:
// - position vec2(0...1)
// - border_radius vec2(0...1) (border radius, converted to an oval)

// note: disable depth stencil for this render pass
