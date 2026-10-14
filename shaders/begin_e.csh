#version 430 compatibility

#include "/include/uniforms.glsl"
#include "/include/config.glsl"
#include "/include/constants.glsl"
#include "/include/common.glsl"
#include "/include/atmosphere.glsl"

layout (local_size_x = 8, local_size_y = 8) in;
const ivec3 workGroups = ivec3(32, 8, 1); // 256 x 64

layout (rgba32f) uniform image2D transmittanceImg;

void main () {
    ivec2 p = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = vec2(p) / (TLUT_SIZE - 1.0);
    imageStore(transmittanceImg, p, computeTransmittance(uv.x * 2.0 - 1.0, uv.y));
}
