
struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) ul_screenspace : vec2<f32>,
    @location(1) br_screenspace : vec2<f32>,
    @location(2) rect_uv : vec2<f32>,
};

@vertex
fn vertex_main(
    // position of the current vertex
    @location(0) position : vec4<f32>,

    // screenspace position of the top left corner of all four vertices
    @location(1) ul_screenspace : vec2<f32>,
    // screenspace position of the bottom right corner of all four vertices
    @location(2) br_screenspace : vec2<f32>,
    // top left corner = [0, 0], bottom right corner = [1, 1]
    @location(3) rect_uv : vec2<f32>,
) -> VertexOutput {
    var output: VertexOutput;

    var xy: vec2<f32> = position.xy / uniforms.screen_size * 2.0 - 1.0;
    output.Position = vec4(xy.x, 0.0 - xy.y, position.zw);

    output.ul_screenspace = ul_screenspace;
    output.br_screenspace = br_screenspace;
    output.rect_uv = rect_uv;

    return output;
}

struct Uniforms { // %[Uniforms]
    screen_size: vec2<f32>,
    colors: array<vec4<f32>, 4>,
};