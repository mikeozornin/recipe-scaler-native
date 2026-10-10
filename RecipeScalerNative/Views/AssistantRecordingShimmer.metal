//
//  AssistantRecordingShimmer.metal
//  RecipeScalerNative
//
//  Colour effect for `AssistantRecordingShimmer` (AssistantComposer.swift): four colour
//  points drift through a noise-warped field and blend like a mesh gradient. `level`
//  (smoothed voice, 0…1) deepens the warp and lifts light from the toolbar; film grain
//  keeps the soft gradient from banding.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace {

float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), u.x),
               mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}

float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * valueNoise(p);
        p = p * 2.03 + 17.1;
        a *= 0.5;
    }
    return v;
}

/// Integer hash for per-pixel grain: `sin`-based hashing loses precision at pixel-sized
/// inputs on the GPU and shows up as a diagonal pattern.
float grainHash(float2 p) {
    uint2 q = uint2(int2(p)) * uint2(1597334673u, 3812015801u);
    uint n = (q.x ^ q.y) * 1597334673u;
    return float(n) * (1.0 / 4294967295.0);
}

float inverseDistanceWeight(float2 q, float2 point) {
    float2 d = q - point;
    return 1.0 / (dot(d, d) + 0.02);
}

} // namespace

[[ stitchable ]] half4 assistantRecordingMesh(
    float2 position,
    half4 color,
    float2 size,
    float phase,
    float level,
    float isDark,
    float grainSeed,
    float displayScale,
    half4 c0,
    half4 c1,
    half4 c2,
    half4 c3
) {
    float2 uv = position / size;
    float ph = phase;
    float2 aspect = float2(size.x / size.y * 0.55, 1.0);

    float2 warp = float2(fbm(uv * 2.2 + float2(ph * 0.25, 0.0)),
                         fbm(uv * 2.2 + float2(5.2, -ph * 0.22))) - 0.5;
    float2 q = (uv + warp * (0.18 + 0.22 * level)) * aspect;

    float2 p0 = float2(0.15 + 0.12 * sin(ph * 0.61), 0.25 + 0.35 * sin(ph * 0.83 + 1.0)) * aspect;
    float2 p1 = float2(0.45 + 0.18 * sin(ph * 0.47 + 2.0), 0.80 + 0.25 * cos(ph * 0.71)) * aspect;
    float2 p2 = float2(0.72 + 0.15 * cos(ph * 0.53 + 1.0), 0.20 + 0.30 * sin(ph * 0.67 + 3.0)) * aspect;
    float2 p3 = float2(0.92 + 0.08 * sin(ph * 0.39), 0.70 + 0.30 * cos(ph * 0.58 + 2.0)) * aspect;

    float w0 = inverseDistanceWeight(q, p0);
    float w1 = inverseDistanceWeight(q, p1);
    float w2 = inverseDistanceWeight(q, p2);
    float w3 = inverseDistanceWeight(q, p3);
    float3 col = (float3(c0.rgb) * w0 + float3(c1.rgb) * w1 + float3(c2.rgb) * w2 + float3(c3.rgb) * w3)
        / (w0 + w1 + w2 + w3);

    // Voice: a soft glow rising from the toolbar edge.
    float2 liftUV = (uv - float2(0.5, 1.05)) * float2(1.6, 2.2);
    float lift = exp(-dot(liftUV, liftUV)) * level;
    col = mix(col, float3(c3.rgb) * 1.08 + 0.06, lift * 0.55);

    col = isDark > 0.5
        ? col * (0.58 + 0.22 * level)
        : mix(col, float3(1.0), 0.30 - 0.14 * level);

    float2 pixel = floor(position * displayScale) + floor(grainSeed * 997.0) * float2(13.0, 7.0);
    col += (grainHash(pixel) - 0.5) * 0.06;

    float alpha = float(color.a);
    return half4(half3(clamp(col, 0.0, 1.0) * alpha), half(alpha));
}
