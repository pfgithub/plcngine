#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec3 vertexNormal;
in vec4 vertexColor;

uniform mat4 mvp;

out vec2 frag_tex_coord;

void main() {
    frag_tex_coord = vertexTexCoord;

    gl_Position = mvp * vec4(vertexPosition, 1.0);
}