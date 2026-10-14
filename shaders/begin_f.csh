#version 430 compatibility

#include "/include/uniforms.glsl"
#include "/include/config.glsl"
#include "/include/constants.glsl"
#include "/include/common.glsl"
#include "/include/atmosphere.glsl"

layout (local_size_x = 8, local_size_y = 8) in;
const ivec3 workGroups = ivec3(32, 16, 1); // 256 x 128

layout (rgba16f) uniform image2D skyViewImg;

void main () {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = (vec2(p) + 0.5) / SKYVIEW_SIZE;
    imageStore(skyViewImg, p, vec4(skyRadianceRaw(skyViewDecode(uv)), 1.0));
}
