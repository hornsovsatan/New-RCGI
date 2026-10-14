#version 430 compatibility

#include "/include/uniforms.glsl"
#include "/include/config.glsl"
#include "/include/constants.glsl"
#include "/include/common.glsl"
#include "/include/pbr.glsl"
#include "/include/main.glsl"
#include "/include/raytracing.glsl"
#include "/include/text.glsl"

in vec2 texcoord;
layout(location = 0) out vec4 color;

vec3 tonemap (vec3 c, float exposure) {
    return pow(1.0 - exp(-exposure * c), vec3(1.0 / 2.2));
}

float hash12 (vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    color = texelFetch(colortex7, ivec2(gl_FragCoord.xy), 0);
    color.rgb = max(color.rgb, vec3(0.0)) * EXPOSURE_CALIBRATION;

    #ifdef DYNAMIC_EXPOSURE
        float lum = renderState.globalLuminance;
        if (!(lum >= 0.0015)) lum = 0.003;
        float exposure = BRIGHTNESS * 8.0 * exp(0.005 / min(lum, 0.05));
    #else
        float exposure = BRIGHTNESS * MANUAL_EXPOSURE;
    #endif

    color.rgb = tonemap(color.rgb, exposure) + (hash12(gl_FragCoord.xy + float(frameCounter % 64)) - 0.5) / 255.0;
    color.a = 1.0;

    #ifdef DEBUG_VIEW
        #define FONT_SIZE 1 // [1 2 3 4 5 6 7 8]
        beginText(ivec2(gl_FragCoord.xy / FONT_SIZE), ivec2(20, viewHeight / FONT_SIZE - 20));
        text.fgCol = vec4(vec3(1.0), 1.0);
        text.bgCol = vec4(vec3(0.0), 0.0);
        if (!hideGUI) {
            for (int i = 0; i < 8; i++) {
                printChar(_c);
                printInt(i);
                printString((_space, _p, _r, _o, _b, _e, _space, _c, _o, _u, _n, _t, _colon, _space));
                printUnsignedInt(renderState.probeCount[i]);
                printLine();
            }
        }
        endText(color.rgb);
    #endif
}
