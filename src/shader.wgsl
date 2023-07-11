struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) fragUV : vec2<f32>,
};

@vertex
fn vertex_main(
    @location(0) position : vec4<f32>,
    @location(1) uv : vec2<f32>,
) -> VertexOutput {
    var output : VertexOutput;
    output.Position = position;
    output.fragUV = uv;
    return output;
}

struct Uniforms {
    color: u32,
};

@group(0) @binding(0) var<uniform> uniforms : Uniforms;
@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var myTexture: texture_2d<f32>;

@fragment
fn frag_main(
    @location(0) fragUV: vec2<f32>,
) -> @location(0) vec4<f32> {
    var sample = textureSample(myTexture, mySampler, fragUV);
    return vec4f(sample.r, f32(uniforms.color) * 0.0 + sample.g, sample.b, sample.a);
}
