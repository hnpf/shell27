#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec2 srcSize;
    vec2 srcOffset;
    float mode;
    float intensity;
    float refract;
    float bevel;
    vec4 tint;
    vec2 lightDir;
};

layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D mask;
layout(binding = 3) uniform sampler2D hmap;

float H(vec2 uv) { return texture(hmap, uv).a; }
vec3 bgAt(vec2 p, float lod) { return textureLod(src, clamp(p / srcSize, vec2(0.001), vec2(0.999)), lod).rgb; }

void main()
{
    vec2 uv = qt_TexCoord0;
    float alpha = texture(mask, uv).a;
    if (alpha <= 0.002) { fragColor = vec4(0.0); return; }

    vec2 p = uv * itemSize + srcOffset;
    vec2 d = 2.0 / itemSize;
    vec2 g = vec2(H(uv + vec2(d.x, 0.0)) - H(uv - vec2(d.x, 0.0)),
                  H(uv + vec2(0.0, d.y)) - H(uv - vec2(0.0, d.y))) * 0.5;
    float slope = length(g) * bevel;
    float s = clamp(slope, 0.0, 1.0);
    vec2 n2 = slope > 1e-6 ? -g / length(g) : vec2(0.0);
    float bend = s * s * (3.0 - 2.0 * s);
    vec2 shift = n2 * refract * (0.35 * s + 0.65 * bend);
    float lod = 0.5 + 2.0 * intensity;
    vec3 bg;
    bg.r = bgAt(p - shift * 1.10, lod).r;
    bg.g = bgAt(p - shift, lod).g;
    bg.b = bgAt(p - shift * 0.90, lod).b;
    float luminance = dot(bg, vec3(0.299, 0.587, 0.114));
    bg = mix(vec3(luminance), bg, 1.25);
    vec3 glass = bg * 1.04 + 0.04;
    glass = mix(glass, mix(vec3(1.0), tint.rgb, 0.85), 0.08 + 0.52 * intensity);
    glass = mix(glass, glass * tint.rgb, 0.35 * (1.0 - tint.r * tint.g * tint.b));
    float facing = dot(n2, normalize(lightDir));
    float shade = facing * smoothstep(0.0, 0.55, s);
    glass *= 1.0 + 0.22 * shade;
    glass += 0.10 * max(shade, 0.0) * (1.0 - 0.5 * intensity);
    fragColor = vec4(clamp(glass, 0.0, 1.0) * alpha, alpha) * qt_Opacity;
}