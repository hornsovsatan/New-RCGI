#version 430 compatibility

#include "/include/uniforms.glsl"
#include "/include/config.glsl"
#include "/include/constants.glsl"
#include "/include/common.glsl"
#include "/include/pbr.glsl"
#include "/include/main.glsl"

/* Auto exposure, diadaptasi dari convolveExposure.glsl Zephyr Starlight (Kirilpro6284) */

layout (local_size_x = 256) in;
const ivec3 workGroups = ivec3(1, 1, 1);

shared float lumBuf[512];

void main () {
    uint id = gl_LocalInvocationID.x;

    for (uint i = 0u; i < 2u; i++) {
        uint idx = id * 2u + i;
        vec2 uv = R2(512u * uint(frameCounter & 7) + idx);
        float l = luminance(texelFetch(colortex7, ivec2(screenSize * uv), 0).rgb) * EXPOSURE_CALIBRATION;
        if (isnan(l) || isinf(l)) l = 0.003;
        lumBuf[idx] = clamp(l, 0.0015, 0.05);
    }
    barrier();

    for (uint s = 256u; s > 0u; s >>= 1u) {
        if (id < s) lumBuf[id] += lumBuf[id + s];
        barrier();
    }

    if (id == 0u) {
        float prev = renderState.globalLuminance;
        if (!(prev >= 0.0015 && prev <= 0.05)) prev = 0.003;
        renderState.globalLuminance = mix(prev, lumBuf[0] / 512.0, ADAPTATION_SPEED);
    }
}
