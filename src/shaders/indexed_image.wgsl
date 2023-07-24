struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) fragUV : vec2<f32>,
    @location(1) @interpolate(flat) draw_colors: u32,
    @location(2) rectUV : vec2<f32>,
};

@vertex
fn vertex_main(
    @location(0) position : vec4<f32>,
    @location(1) uv : vec2<f32>,
    @location(2) draw_colors: u32,
    @location(3) rect_uv : vec2<f32>,
) -> VertexOutput {
    var output: VertexOutput;
    // (0, 0) => (-1, 1)
    // (100, 100) => (1.0, -1.0)
    var xy: vec2<f32> = position.xy / uniforms.screen_size * 2.0 - 1.0;
    output.Position = vec4(xy.x, 0.0 - xy.y, position.zw);
    output.fragUV = uv;
    output.draw_colors = draw_colors;
    output.rectUV = rect_uv;
    return output;
}

struct Uniforms { // %[Uniforms]
    screen_size: vec2<f32>,
    colors: array<vec4<f32>, 4>,
};

@group(0) @binding(0) var<uniform> uniforms : Uniforms;
@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var myTexture: texture_2d<f32>;

fn dist(a: vec2<f32>, b: vec2<f32>) -> f32 {
    var c = a - b;
    return sqrt(c.x * c.x + c.y * c.y);
}
fn min4(a: f32, b: f32, c: f32, d: f32) -> f32 {
    return min(min(a, b), min(c, d));
}

@fragment
fn frag_main(
    @location(0) fragUV: vec2<f32>,
    @location(1) @interpolate(flat) draw_colors: u32,
    @location(2) rectUV : vec2<f32>,
) -> @location(0) vec4<f32> {
    var sample = textureSample(myTexture, mySampler, fragUV);

    // there's a rounded rectangle sdf but I don't know it
    var radius = f32(0.1);
    var rinv = 1.0 - radius;
    var is_corner_1 = rectUV.x < radius && rectUV.y < radius;
    var is_corner_2 = rectUV.x > rinv && rectUV.y < radius;
    var is_corner_3 = rectUV.x < radius && rectUV.y > rinv;
    var is_corner_4 = rectUV.x > rinv && rectUV.y > rinv;
    var is_corner = is_corner_1 || is_corner_2 || is_corner_3 || is_corner_4;
    // oh we need to measure dist horizontal and vertical seperately
    var corner_dist = min4(
        dist(vec2<f32>(radius, radius), rectUV),
        dist(vec2<f32>(rinv, radius), rectUV),
        dist(vec2<f32>(radius, rinv), rectUV),
        dist(vec2<f32>(rinv, rinv), rectUV),
    );
    if(is_corner && corner_dist > radius) {
        discard;
    }

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
