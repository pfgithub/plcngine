struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) uv : vec2<f32>,
    @location(1) @interpolate(flat) draw_colors: u32,
}

struct Uniforms {
    screen_size: vec2<f32>,
    colors: array<vec4<f32>, 4>,
};
@group(0) @binding(0) var<uniform> uniforms : Uniforms;
@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var myTexture: texture_2d<f32>;

@vertex
fn vertex_main(
    @location(0) position : vec2<f32>,
    @location(1) uv : vec2<f32>,
    @location(2) draw_colors : u32,
) -> VertexOutput {
    var output: VertexOutput;
    // (0, 0) => (-1, 1)
    // (100, 100) => (1.0, -1.0)
    var xy: vec2<f32> = position / uniforms.screen_size * 2.0 - 1.0;

    output.Position = vec4(xy.x, 0.0 - xy.y, 0.0, 1.0);
    output.uv = uv;
    output.draw_colors = draw_colors;

    return output;
}

@fragment
fn frag_main(
    // why do we have to copy all of this when it's in vertexoutput already?
    // can we just `in: VertexOutput`?
    @location(0) uv: vec2<f32>,
    @location(1) @interpolate(flat) draw_colors: u32,
) -> @location(0) vec4<f32> {
    var sample = textureSample(myTexture, mySampler, uv);


    if(draw_colors <= 0x0FFFFFFF) {
        // 0=transparent,1=colors[0],2=colors[1],3=colors[2],4=colors[3],5=reserved,6=reserved,7=reserved
        var index = u32(sample.r * 255.0);
        var shiftres = (draw_colors >> (index * 3)) & 7;
        if(shiftres == 0) {
            // return vec4<f32>(sample.r * 50.0, uv.xy, 1.0);
            discard;
            // we might be skipping discard support
        }
        if(shiftres > 4) {
            return vec4<f32>(1.0, 0.0, 1.0, 1.0); // error color
        }
        return uniforms.colors[shiftres - 1];
    }else if(draw_colors == 0x10000001) {
        return sample;
    // } else if(draw_colors == 0x10000002) {
    // sample msdf
    } else {
    
        return vec4(1.0, 0.0, 1.0, 1.0); // error color
    }
}
