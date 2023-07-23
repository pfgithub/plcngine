struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) fragUV : vec2<f32>,
    @location(1) @interpolate(flat) draw_colors: u32,
};

@vertex
fn vertex_main(
    @location(0) position : vec4<f32>,
    @location(1) uv : vec2<f32>,
    @location(2) draw_colors: u32,
) -> VertexOutput {
    var output: VertexOutput;
    // (0, 0) => (-1, 1)
    // (100, 100) => (1.0, -1.0)
    var xy: vec2<f32> = position.xy / uniforms.screen_size * 2.0 - 1.0;
    output.Position = vec4(xy.x, 0.0 - xy.y, position.zw);
    output.fragUV = uv;
    output.draw_colors = draw_colors;
    return output;
}

struct Uniforms { // %[Uniforms]
    screen_size: vec2<f32>,
    colors: array<vec4<f32>, 4>,
};

@group(0) @binding(0) var<uniform> uniforms : Uniforms;
@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var myTexture: texture_2d<f32>;

@fragment
fn frag_main(
    @location(0) fragUV: vec2<f32>,
    @location(1) @interpolate(flat) draw_colors: u32,
) -> @location(0) vec4<f32> {
    // return textureSample(myTexture, mySampler, fragUV);

    var sample = textureSample(myTexture, mySampler, fragUV);

    if(draw_colors <= 0x0FFFFFFF) {
        // 0=transparent,1=colors[0],2=colors[1],3=colors[2],4=colors[3],5=reserved,6=reserved,7=reserved
        var index = u32(sample.r * 255.0);
        var shiftres = (draw_colors >> (index * 3)) & 7;
        if(shiftres == 0) {discard;}
        if(shiftres > 4) {
            return vec4<f32>(1.0, 0.0, 1.0, 1.0); // error color
        }
        return uniforms.colors[shiftres - 1];
    }else{
        return sample;
    }
}

// v can't use this, we need supersampling
// fn texture2DAA(tex : texture_2d<f32>, s : sampler, uv : vec2<f32>) -> vec4<f32> {
//     // https://www.shadertoy.com/view/csX3RH
//     // https://jsfiddle.net/cx20/vmkaqw2b/
//
//     let texsize : vec2<f32> = vec2<f32>(textureDimensions(tex, 0i));
//     var uv_texspace : vec2<f32> = uv * texsize;
//     let seam : vec2<f32> = floor(uv_texspace + vec2<f32>(0.5f, 0.5f));
//
//     uv_texspace = ((uv_texspace - seam) / fwidth(uv_texspace)) + seam;
//     uv_texspace = clamp(uv_texspace, seam - vec2<f32>(0.5f, 0.5f), seam + vec2<f32>(0.5f, 0.5f));
//
//     return textureSample(tex, s, uv_texspace / texsize);
// }
