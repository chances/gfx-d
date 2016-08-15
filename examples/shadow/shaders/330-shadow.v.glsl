#version 330

in vec3 a_Pos;

uniform Locals {
    mat4 u_Transform;
};

void main() {
    gl_Position = u_Transform * vec4(a_Pos, 1.0);
}
