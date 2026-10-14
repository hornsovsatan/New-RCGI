#version 430 compatibility

#include "/include/uniforms.glsl"
#include "/include/config.glsl"
#include "/include/constants.glsl"
#include "/include/common.glsl"

/* RENDERTARGETS: 7 */
layout (location = 0) out vec4 color;

vec4 cubic (float v) {
    vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
    vec4 s = n * n * n;
    float x = s.x;
    float y = s.y - 4.0 * s.x;
    float z = s.z - 4.0 * s.y + 6.0 * s.x;
    float w = 6.0 - x - y - z;
    return vec4(x, y, z, w) / 6.0;
}

vec4 texBicubic (sampler2D tex, vec2 uv, vec2 texSize) {
    vec2 inv = 1.0 / texSize;
    uv = uv * texSize - 0.5;
    vec2 f = fract(uv);
    uv -= f;
    vec4 xc = cubic(f.x);
    vec4 yc = cubic(f.y);
    vec4 c = uv.xxyy + vec2(-0.5, 1.5).xyxy;
    vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
    vec4 o = (c + vec4(xc.yw, yc.yw) / s) * inv.xxyy;
    vec4 s0 = texture(tex, o.xz);
    vec4 s1 = texture(tex, o.yz);
    vec4 s2 = texture(tex, o.xw);
    vec4 s3 = texture(tex, o.yw);
    float sx = s.x / (s.x + s.y);
    float sy = s.z / (s.z + s.w);
    return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

void main() {
    vec2 uv = gl_FragCoord.xy / screenSize;
    vec3 bloom = vec3(0.0);
    for (int i = 0; i < BLOOM_TILES; i++) {
        vec3 s = texBicubic(colortex14, exp2(-float(i + 1)) * (uv + 1.0), screenSize).rgb;
        if (!any(isnan(s))) bloom += s;
    }
    color = vec4(texelFetch(colortex7, ivec2(gl_FragCoord.xy), 0).rgb + bloom * BLOOM_STRENGTH, 1.0);
}
