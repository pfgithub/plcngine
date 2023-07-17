struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) fragUV : vec2<f32>,
};

@vertex
fn vertex_main(
    @location(0) position : vec4<f32>,
    @location(1) uv : vec2<f32>,
) -> VertexOutput {
    var output: VertexOutput;
    // (0, 0) => (-1, 1)
    // (100, 100) => (1.0, -1.0)
    var xy: vec2<f32> = position.xy / uniforms.screen_size * 2.0 - 1.0;
    output.Position = vec4(xy.x, 0.0 - xy.y, position.zw);
    output.fragUV = uv;
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
) -> @location(0) vec4<f32> {
    // return textureSample(myTexture, mySampler, fragUV);

    var sample = textureSample(myTexture, mySampler, fragUV);
    var index = i32(sample.r * 255.0);
    if(index == 0) {discard;}
    if(index > 4) {discard;}
    return uniforms.colors[index - 1];
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
