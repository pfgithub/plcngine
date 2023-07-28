struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) fragUV : vec2<f32>,
    @location(1) @interpolate(flat) draw_colors: u32,
    @location(2) rectUV : vec2<f32>,

    @location(3) corner_1 : vec2<f32>,
    @location(4) corner_2 : vec2<f32>,
    @location(5) corner_3 : vec2<f32>,
    @location(6) corner_4 : vec2<f32>,

    @location(7) border_t: f32,
    @location(8) border_r: f32,
    @location(9) border_b: f32,
    @location(10) border_l: f32,
};

@vertex
fn vertex_main(
    @location(0) position : vec4<f32>,
    @location(1) uv : vec2<f32>,
    @location(2) draw_colors: u32,
    @location(3) rect_uv : vec2<f32>,

    @location(4) corner_1: vec2<f32>,
    @location(5) corner_2: vec2<f32>,
    @location(6) corner_3: vec2<f32>,
    @location(7) corner_4: vec2<f32>,

    @location(8) border_t: f32,
    @location(9) border_r: f32,
    @location(10) border_b: f32,
    @location(11) border_l: f32,
) -> VertexOutput {
    var output: VertexOutput;
    // (0, 0) => (-1, 1)
    // (100, 100) => (1.0, -1.0)
    var xy: vec2<f32> = position.xy / uniforms.screen_size * 2.0 - 1.0;
    output.Position = vec4(xy.x, 0.0 - xy.y, position.zw);
    output.fragUV = uv;
    output.draw_colors = draw_colors;
    output.rectUV = rect_uv;

    output.corner_1 = corner_1;
    output.corner_2 = corner_2;
    output.corner_3 = corner_3;
    output.corner_4 = corner_4;

    output.border_t = border_t;
    output.border_r = border_r;
    output.border_b = border_b;
    output.border_l = border_l;

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
fn dist2(a: f32, b: f32) -> f32 {
    return sqrt(a * a + b * b);
}
fn min4(a: f32, b: f32, c: f32, d: f32) -> f32 {
    return min(min(a, b), min(c, d));
}

@fragment
fn frag_main(
    @location(0) frag_uv: vec2<f32>,
    @location(1) @interpolate(flat) draw_colors: u32,
    @location(2) rect_uv : vec2<f32>,

    @location(3) corner_1 : vec2<f32>,
    @location(4) corner_2 : vec2<f32>,
    @location(5) corner_3 : vec2<f32>,
    @location(6) corner_4 : vec2<f32>,

    @location(7) border_t: f32,
    @location(8) border_r: f32,
    @location(9) border_b: f32,
    @location(10) border_l: f32,
) -> @location(0) vec4<f32> {
    var sample = textureSample(myTexture, mySampler, frag_uv);

    // there's a rounded rectangle sdf but I don't know it

    var radius = f32(0.1);
    var rinv = 1.0 - radius;
    var is_corner_1 = rect_uv.x < corner_1.x && rect_uv.y < corner_1.y;
    var is_corner_2 = rect_uv.x > (1.0 - corner_2.x) && rect_uv.y < corner_2.y;
    var is_corner_3 = rect_uv.x < corner_3.x && rect_uv.y > (1.0 - corner_3.y);
    var is_corner_4 = rect_uv.x > (1.0 - corner_4.x) && rect_uv.y > (1.0 - corner_4.y);
    var is_corner = is_corner_1 || is_corner_2 || is_corner_3 || is_corner_4;
    var corner_1_dist = dist2(
        (rect_uv.x - corner_1.x) * (1.0 / corner_1.x), // x dist
        (rect_uv.y - corner_1.y) * (1.0 / corner_1.y), // y dist
    );
    var corner_2_dist = dist2(
        (rect_uv.x - (1.0 - corner_2.x)) * (1.0 / corner_2.x), // x dist
        (rect_uv.y - corner_2.y) * (1.0 / corner_2.y), // y dist
    );
    var corner_3_dist = dist2(
        (rect_uv.x - corner_3.x) * (1.0 / corner_3.x), // x dist
        (rect_uv.y - (1.0 - corner_3.y)) * (1.0 / corner_3.y), // y dist
    );
    var corner_4_dist = dist2(
        (rect_uv.x - (1.0 - corner_4.x)) * (1.0 / corner_4.x), // x dist
        (rect_uv.y - (1.0 - corner_4.y)) * (1.0 / corner_4.y), // y dist
    );
    var corner_dist = min4(
        corner_1_dist,
        corner_2_dist,
        corner_3_dist,
        corner_4_dist,
    );
    if(is_corner && corner_dist > 1.0) {
        discard;
    }

    var border_t_dist = rect_uv.y - border_t;
    var border_r_dist = (1.0 - rect_uv.x) - border_r;
    var border_b_dist = (1.0 - rect_uv.y) - border_b;
    var border_l_dist = rect_uv.x - border_l;
    if(border_t_dist < 0 && border_t > 0) {
        sample = vec4(1.1 / 255.0, 0.0, 0.0, 1.0);
    }
    if(border_r_dist < 0 && border_r > 0) {
        sample = vec4(2.1 / 255.0, 0.0, 0.0, 1.0);
    }
    if(border_b_dist < 0 && border_b > 0) {
        sample = vec4(3.1 / 255.0, 0.0, 0.0, 1.0);
    }
    if(border_l_dist < 0 && border_l > 0) {
        sample = vec4(4.1 / 255.0, 0.0, 0.0, 1.0);
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
