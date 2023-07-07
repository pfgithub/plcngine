#version 330

in vec2 frag_tex_coord;

uniform sampler2D texture0;
uniform vec4[255] color_map;

out vec4 final_color;

void main() {
    vec4 texel_color = texture(texture0, frag_tex_coord);
    int red = int(texel_color.r * 255.0);
    final_color = color_map[red];
}
