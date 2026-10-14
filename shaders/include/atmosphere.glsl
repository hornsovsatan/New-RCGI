#ifndef INCLUDE_ATMOSPHERE
#define INCLUDE_ATMOSPHERE

/*
    Atmosfer RCGI v2
    Struktur LUT ala Hillaire, spektral 4 panjang gelombang (630 560 490 430 nm) dari fgarlin.
    Konstanta dari Blender intern/sky/source/sky_multiple_scattering.cpp (MIT, Fernando Garcia Linan).
    Limb darkening: Hestroffer and Magnan 1998. Satuan jarak: kilometer.
*/

const float EARTH_RADIUS    = 6371.0;
const float ATMOS_THICKNESS = 100.0;
const float ATMOS_RADIUS    = 6471.0;

const float SKY_UNIT_SCALE = 0.05;

const vec4 SUN_SPECTRAL_IRRADIANCE   = vec4(1.679, 1.828, 1.986, 1.307);
const vec4 MOLECULAR_SCATTERING_BASE = vec4(6.605e-3, 1.067e-2, 1.842e-2, 3.156e-2);
const vec4 OZONE_ABSORPTION_BASE     = vec4(0.0439639, 0.0495606, 0.0170816, 0.00139666);
const vec4 AEROSOL_SCATTERING_BASE   = vec4(0.0217637, 0.0242304, 0.0286507, 0.0328795);
const vec4 AEROSOL_ABSORPTION_BASE   = vec4(3.92946e-4, 6.31624e-4, 1.09046e-3, 1.85761e-3);
const float AEROSOL_HEIGHT_SCALE     = 0.73;
const float AEROSOL_BACKGROUND       = 1.4619e-14;
const float AEROSOL_G                = 0.8;

const vec4 SUN_LIMB_ALPHA = vec4(0.4405, 0.4984, 0.5729, 0.6561);
const vec3 MOON_TINT      = vec3(0.80, 0.90, 1.12);

const vec2 TLUT_SIZE    = vec2(256.0, 64.0);
const vec2 SKYVIEW_SIZE = vec2(256.0, 128.0);

/* ===== arah dan ketinggian ===== */

vec3 getSunDir ()   { return normalize(mat3(gbufferModelViewInverse) * sunPosition); }
vec3 getMoonDir ()  { return normalize(mat3(gbufferModelViewInverse) * moonPosition); }
vec3 getLightDir () { return normalize(mat3(gbufferModelViewInverse) * shadowLightPosition); }

float cameraAltitudeKm () {
    return clamp(ATMOS_BASE_ALTITUDE + max(cameraPosition.y - 63.0, 0.0) * ATMOS_HEIGHT_SCALE * 0.001, 0.001, ATMOS_THICKNESS - 1.0);
}

/* ===== spektral ke RGB ===== */

vec3 spectralToRGB (vec4 L) {
    const vec3 c0 = vec3(53.3869177, 22.9813375, 0.0);
    const vec3 c1 = vec3(43.9048445, 71.3477957, 0.1025069);
    const vec3 c2 = vec3(1.6137278, 18.4229606, 31.7429212);
    const vec3 c3 = vec3(20.7626687, 2.3614214, 110.4800964);
    vec3 xyz = c0 * L.x + c1 * L.y + c2 * L.z + c3 * L.w;

    const mat3 XYZ_TO_SRGB = mat3(
         3.2404542, -0.9692660,  0.0556434,
        -1.5371385,  1.8760108, -0.2040259,
        -0.4985314,  0.0415560,  1.0572252
    );
    return max(XYZ_TO_SRGB * xyz, vec3(0.0)) * (SKY_UNIT_SCALE * 0.3);
}

/* ===== geometri ===== */

vec2 raySphere (vec3 ro, vec3 rd, float r) {
    float b = dot(ro, rd);
    float c = dot(ro, ro) - r * r;
    float d = b * b - c;
    if (d < 0.0) return vec2(-1.0);
    d = sqrt(d);
    return vec2(-b - d, -b + d);
}

/* ===== koefisien medium per km ===== */

void atmosCoefficients (float h, out vec4 scatMol, out vec4 scatAer, out vec4 ext) {
    h = max(h, 0.0);
    scatMol = MOLECULAR_SCATTERING_BASE * exp(-0.07771971 * pow(max(h, 1e-6), 1.16364243)) * AIR_DENSITY;

    float logH = log(max(h, 1e-4));
    vec4 absOzone = OZONE_ABSORPTION_BASE * exp(-sqr(logH - 3.22261) * 5.55555555 - logH) * OZONE_DENSITY;

    float aer = (exp(-h / AEROSOL_HEIGHT_SCALE) + AEROSOL_BACKGROUND) * AEROSOL_DENSITY;
    scatAer = AEROSOL_SCATTERING_BASE * aer;

    ext = scatMol + absOzone + scatAer + AEROSOL_ABSORPTION_BASE * aer;
}

/* ===== transmittance LUT ===== */

vec4 computeTransmittance (float cosTheta, float hNorm) {
    vec3 ro = vec3(0.0, mix(EARTH_RADIUS, ATMOS_RADIUS, hNorm), 0.0);
    vec3 rd = vec3(sqrt(max(1.0 - cosTheta * cosTheta, 0.0)), cosTheta, 0.0);
    float td = max(raySphere(ro, rd, ATMOS_RADIUS).y, 0.0);
    float dt = td / 64.0;
    vec4 od = vec4(0.0);
    for (int i = 0; i < 64; i++) {
        vec3 p = ro + rd * ((float(i) + 0.5) * dt);
        vec4 a, b, e;
        atmosCoefficients(length(p) - EARTH_RADIUS, a, b, e);
        od += e;
    }
    return exp(-od * dt);
}

vec4 lookupTransmittance (float cosTheta, float hNorm) {
    vec2 uv = saturate(vec2(cosTheta * 0.5 + 0.5, hNorm));
    uv = (uv * (TLUT_SIZE - 1.0) + 0.5) / TLUT_SIZE;
    return texture(transmittanceSampler, uv);
}

/* ===== multiple scattering (fit fgarlin) ===== */

vec4 multiScatter (float cosTheta, float hNorm, float d) {
    float omega = TWO_PI * (1.0 - sqrt(max(1.0 - sqr(EARTH_RADIUS / d), 0.0)));
    vec4 tGround = lookupTransmittance(cosTheta, 0.0);
    vec4 tGroundToSample = lookupTransmittance(1.0, 0.0) / max(lookupTransmittance(1.0, hNorm), vec4(1e-6));
    vec4 lGround = (1.0 / (4.0 * PI)) * omega * (ATMOS_GROUND_ALBEDO / PI) * tGround * tGroundToSample * max(cosTheta, 0.0);
    vec4 lMs = 0.02 * vec4(0.217, 0.347, 0.594, 1.0) / (1.0 + 5.0 * exp(-17.92 * cosTheta));
    return lMs + lGround;
}

/* ===== in-scattering ===== */

vec4 inscatter (vec3 ro, vec3 rd, vec3 L, float td, inout vec4 T) {
    float mu = dot(rd, L);
    float pR = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
    float g2 = AEROSOL_G * AEROSOL_G;
    float pA = (1.0 - g2) / (4.0 * PI * pow(max(1.0 + g2 - 2.0 * AEROSOL_G * mu, 1e-4), 1.5));

    float dt = td / float(SKY_STEPS);
    vec4 sum = vec4(0.0);
    for (int i = 0; i < SKY_STEPS; i++) {
        vec3 p = ro + rd * ((float(i) + 0.5) * dt);
        float d = length(p);
        float h = max(d - EARTH_RADIUS, 0.0);
        float hn = h / ATMOS_THICKNESS;
        float c = dot(p / d, L);

        vec4 sM, sA, ext;
        atmosCoefficients(h, sM, sA, ext);
        vec4 tSun = lookupTransmittance(c, hn);
        vec4 ms = multiScatter(c, hn, d);

        vec4 S = SUN_SPECTRAL_IRRADIANCE * (sM * (pR * tSun + ms) + sA * (pA * tSun + ms));
        vec4 st = exp(-dt * ext);
        sum += T * (S - S * st) / max(ext, vec4(1e-7));
        T *= st;
    }
    return sum;
}

/* ===== sky-view LUT ===== */

vec2 skyViewEncode (vec3 dir) {
    float u = atan(dir.z, dir.x) / TWO_PI + 0.5;
    float e = asin(clamp(dir.y, -1.0, 1.0));
    float v = 0.5 + 0.5 * sign(e) * sqrt(abs(e) / HALF_PI);
    return vec2(u, v);
}

vec3 skyViewDecode (vec2 uv) {
    float az = (uv.x - 0.5) * TWO_PI;
    float l = uv.y * 2.0 - 1.0;
    float e = sign(l) * l * l * HALF_PI;
    return vec3(cos(e) * cos(az), sin(e), cos(e) * sin(az));
}

/* mahal: hanya dipanggil di begin_f.csh */
vec3 skyRadianceRaw (vec3 dir) {
    vec3 ro = vec3(0.0, EARTH_RADIUS + cameraAltitudeKm(), 0.0);
    vec2 tA = raySphere(ro, dir, ATMOS_RADIUS);
    vec2 tG = raySphere(ro, dir, EARTH_RADIUS);
    bool ground = tG.x > 0.0;
    float td = ground ? tG.x : tA.y;

    vec3 result = vec3(0.0);
    for (int k = 0; k < 2; k++) {
        vec3 L = (k == 0) ? getSunDir() : getMoonDir();
        if (L.y < -0.35) continue;

        vec4 T = vec4(1.0);
        vec4 Ls = inscatter(ro, dir, L, td, T);

        if (ground) {
            vec3 up = normalize(ro + dir * td);
            float c = dot(up, L);
            Ls += T * SUN_SPECTRAL_IRRADIANCE * lookupTransmittance(c, 0.0) * (ATMOS_GROUND_ALBEDO / PI) * max(c, 0.0);
        }

        vec3 rgb = spectralToRGB(Ls);
        result += (k == 0) ? rgb * SUN_INTENSITY : rgb * MOON_INTENSITY * MOON_TINT;
    }
    return result;
}

/* murah: dipakai di mana saja */
vec3 skyRadiance (vec3 dir) {
    return texture(skyViewSampler, skyViewEncode(dir)).rgb;
}

vec3 nightAirglow (vec3 dir) {
    return vec3(1.0, 1.4, 2.2) * 1e-4 * NIGHT_SKY_BRIGHTNESS * (0.5 + 0.5 * saturate(1.0 - dir.y));
}

/* ===== cahaya matahari dan bulan untuk lighting ===== */

vec3 getLightColor () {
    vec3 L = getLightDir();
    float hn = cameraAltitudeKm() / ATMOS_THICKNESS;
    vec3 rgb = spectralToRGB(SUN_SPECTRAL_IRRADIANCE * lookupTransmittance(L.y, hn)) * smoothstep(-0.01, 0.02, L.y);
    bool isSun = dot(L, getSunDir()) > 0.5;
    return isSun ? rgb * SUN_INTENSITY : rgb * MOON_INTENSITY * MOON_TINT;
}

/* ===== piringan matahari dan bulan ===== */

vec3 celestialDisks (vec3 dir) {
    vec3 result = vec3(0.0);
    float h = cameraAltitudeKm();
    float hn = h / ATMOS_THICKNESS;
    float horizonCos = -sqrt(max(1.0 - sqr(EARTH_RADIUS / (EARTH_RADIUS + h)), 0.0));
    float groundMask = smoothstep(horizonCos - 0.002, horizonCos + 0.002, dir.y);
    vec4 T = lookupTransmittance(dir.y, hn);

    float aS = acos(clamp(dot(dir, getSunDir()), -1.0, 1.0)) / SUN_ANGULAR_RADIUS;
    if (aS < 1.05) {
        float mu = sqrt(max(1.0 - sqr(min(aS, 1.0)), 1e-4));
        vec4 limb = pow(vec4(mu), SUN_LIMB_ALPHA) * (SUN_LIMB_ALPHA + 2.0) * 0.5;
        float omega = PI * SUN_ANGULAR_RADIUS * SUN_ANGULAR_RADIUS;
        float edge = 1.0 - smoothstep(0.97, 1.03, aS);
        result += spectralToRGB(SUN_SPECTRAL_IRRADIANCE * T * limb / omega) * SUN_INTENSITY * edge * groundMask;
    }

    float aM = acos(clamp(dot(dir, getMoonDir()), -1.0, 1.0)) / MOON_ANGULAR_RADIUS;
    if (aM < 1.05) {
        float shade = 0.8 + 0.2 * sqrt(max(1.0 - sqr(min(aM, 1.0)), 0.0));
        float omega = PI * MOON_ANGULAR_RADIUS * MOON_ANGULAR_RADIUS;
        float edge = 1.0 - smoothstep(0.97, 1.03, aM);
        result += spectralToRGB(SUN_SPECTRAL_IRRADIANCE * T / omega) * MOON_INTENSITY * MOON_TINT * shade * edge * groundMask;
    }
    return result;
}

/* ===== aerial perspective (kabut atmosfer) ===== */

vec3 applyAerialPerspective (vec3 color, vec3 playerPos, vec3 viewDir) {
    float skyVis = saturate(float(eyeBrightnessSmooth.y) / 240.0);
    float distKm = length(playerPos) * 0.001 * AERIAL_PERSPECTIVE * skyVis;

    vec4 sM, sA, ext;
    atmosCoefficients(cameraAltitudeKm(), sM, sA, ext);
    vec3 extRGB = vec3(ext.x, ext.y, 0.5 * (ext.z + ext.w));
    vec3 T = exp(-extRGB * distKm);

    vec3 hazeDir = normalize(vec3(viewDir.x, max(viewDir.y, 0.03), viewDir.z));
    return color * T + skyRadiance(hazeDir) * (1.0 - T);
}

#endif
