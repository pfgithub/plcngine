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

struct Uniforms {
    screen_size: vec2<f32>,
    color: u32,
};

@group(0) @binding(0) var<uniform> uniforms : Uniforms;
@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var myTexture: texture_2d<f32>;

@fragment
fn frag_main(
    @location(0) fragUV: vec2<f32>,
) -> @location(0) vec4<f32> {
    var sample = texture2DAA(myTexture, mySampler, fragUV);
    return vec4f(sample.r, sample.g, sample.b, sample.a);
}

fn texture2DAA(tex : texture_2d<f32>, s : sampler, uv : vec2<f32>) -> vec4<f32> {
    // https://www.shadertoy.com/view/csX3RH
    // https://jsfiddle.net/cx20/vmkaqw2b/

    let texsize : vec2<f32> = vec2<f32>(textureDimensions(tex, 0i));
    var uv_texspace : vec2<f32> = uv * texsize;
    let seam : vec2<f32> = floor(uv_texspace + vec2<f32>(0.5f, 0.5f));
    
    uv_texspace = ((uv_texspace - seam) / fwidth(uv_texspace)) + seam;
    uv_texspace = clamp(uv_texspace, seam - vec2<f32>(0.5f, 0.5f), seam + vec2<f32>(0.5f, 0.5f));

    return textureSample(tex, s, uv_texspace / texsize);
}