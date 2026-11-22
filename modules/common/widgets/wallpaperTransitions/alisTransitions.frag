#version 440

// Alis built-in GPU wallpaper transitions replacing external awww daemon.
// Modes:
//   0 = grow   (circular expand from origin)
//   1 = outer  (circular shrink from edges to origin)
//   2 = center (circular expand from screen center)
//   3 = any    (circular expand from randomized origin)
//   4 = wave   (directional sinusoidal wave sweep)
//   5 = wipe   (directional linear feathered wipe)
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float time;
    vec2 aspectRatio;
    vec2 origin;
    float transitionMode;
    float transitionAngle;
} ubuf;

layout(binding = 1) uniform sampler2D source1;
layout(binding = 2) uniform sampler2D source2;

void main() {
    vec2 uv = qt_TexCoord0;
    float p = clamp(ubuf.progress, 0.0, 1.0);

    if (p <= 0.0001) {
        fragColor = texture(source1, uv) * ubuf.qt_Opacity;
        return;
    }
    if (p >= 0.9999) {
        fragColor = texture(source2, uv) * ubuf.qt_Opacity;
        return;
    }

    vec4 outgoing = texture(source1, uv);
    vec4 incoming = texture(source2, uv);

    int mode = int(ubuf.transitionMode + 0.5);
    float aspect = max(0.1, ubuf.aspectRatio.x / max(0.0001, ubuf.aspectRatio.y));
    vec2 scale = vec2(aspect, 1.0);
    float reveal = p;

    if (mode == 0 || mode == 2 || mode == 3) {
        // Circular grow from origin (or center for mode 2)
        vec2 center = (mode == 2) ? vec2(0.5, 0.5) : clamp(ubuf.origin, vec2(0.0), vec2(1.0));
        vec2 d00 = (vec2(0.0, 0.0) - center) * scale;
        vec2 d10 = (vec2(1.0, 0.0) - center) * scale;
        vec2 d01 = (vec2(0.0, 1.0) - center) * scale;
        vec2 d11 = (vec2(1.0, 1.0) - center) * scale;
        float maxR = max(max(length(d00), length(d10)), max(length(d01), length(d11)));
        float dist = length((uv - center) * scale);
        float feather = max(0.015, fwidth(dist) * 1.5);
        float radius = mix(-feather, maxR + feather, p);
        reveal = 1.0 - smoothstep(radius - feather, radius + feather, dist);
    } else if (mode == 1) {
        // Outer: circular reveal moving inward from outer corners toward center
        vec2 center = vec2(0.5, 0.5);
        float maxR = length(vec2(0.5, 0.5) * scale);
        float dist = length((uv - center) * scale);
        float feather = max(0.015, fwidth(dist) * 1.5);
        float radius = mix(maxR + feather, -feather, p);
        reveal = smoothstep(radius - feather, radius + feather, dist);
    } else if (mode == 4) {
        // Wave: directional sinusoidal front
        vec2 dir = vec2(cos(ubuf.transitionAngle), -sin(ubuf.transitionAngle));
        vec2 perp = vec2(-dir.y, dir.x);
        vec2 centered = uv - vec2(0.5, 0.5);
        float extent = 0.5 * (abs(dir.x) + abs(dir.y));
        float proj = dot(centered, dir) + extent;
        float span = 2.0 * extent;
        float waveOffset = sin(dot(centered * scale, perp) * 18.0 + ubuf.time * 4.0) * 0.045;
        float front = mix(-0.08, span + 0.08, p) + waveOffset;
        float feather = max(0.025, fwidth(proj) * 1.5);
        reveal = 1.0 - smoothstep(front - feather, front + feather, proj);
    } else {
        // Wipe (mode 5): crisp directional linear sweep with soft feather
        vec2 dir = vec2(cos(ubuf.transitionAngle), -sin(ubuf.transitionAngle));
        vec2 centered = uv - vec2(0.5, 0.5);
        float extent = 0.5 * (abs(dir.x) + abs(dir.y));
        float proj = dot(centered, dir) + extent;
        float span = 2.0 * extent;
        float feather = max(0.03, fwidth(proj) * 1.5);
        float front = mix(-feather, span + feather, p);
        reveal = 1.0 - smoothstep(front - feather, front + feather, proj);
    }

    vec4 blended = mix(outgoing, incoming, clamp(reveal, 0.0, 1.0));
    fragColor = blended * ubuf.qt_Opacity;
}
