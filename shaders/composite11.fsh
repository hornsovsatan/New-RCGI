#version 430 compatibility

#include "/include/uniforms.glsl"
#include "/include/config.glsl"
#include "/include/constants.glsl"
#include "/include/common.glsl"

const bool colortex7MipmapEnabled = true;

/* RENDERTARGETS: 14 */
layout (location = 0) out vec4 color;

void main () {
    int tileIndex = int(floatBitsToUint(gl_FragCoord.x / viewWidth) >> 23) - 127;
    int lod = clamp(-tileIndex, 0, 10);
    vec3 c = texelFetch(colortex7, ivec2(gl_FragCoord.xy - exp2(float(tileIndex)) * screenSize), lod).rgb;
    if (any(isnan(c)) || any(isinf(c))) c = vec3(0.0);
    color = vec4(c, 1.0);
}
