//
//  ShineShader.metal
//  ShineCard
//
//  1:1 复刻 react-native-shine 的 WGSL shader
//

#include <metal_stdlib>
using namespace metal;

// MARK: - 顶点结构
struct Vertex {
    float4 position [[position]];
    float2 uv;
};

// MARK: - Uniforms (对应 WebGPU bind groups)
struct Uniforms {
    float2 resolution;           // 屏幕分辨率
    float2 rotation;             // 旋转/倾斜参数 (rot.xy)
    float time;                  // 时间
    
    // Holo options
    float holoDirectionDegree;   // 全息方向角度
    float holoShift;             // 偏移
    float holoRotationShiftPower;// 旋转偏移强度
    float holoSize;              // 全息条纹大小
    float holoMultiplier;        // 条纹密度乘数
    float holoEaseSize;          // 边缘过渡大小
    float holoVisibility;        // 全息可见度
    float holoSaturation;        // 饱和度
    
    // Glare options
    float glareIntensity;        // 光泽强度
    float glowPower;             // 光晕曲线
    float lightIntensity;        // 光源强度
    float hueBlendPower;         // 色相混合强度
    float hueShiftAngleMin;      // 色相偏移最小角度
    float hueShiftAngleMax;      // 色相偏移最大角度
    float4 glareColor;           // 光泽颜色 RGBA
    
    // 效果开关
    float enableHolo;            // 1.0 = 开启全息
    float enableGlare;           // 1.0 = 开启光泽
    float enableDoubleHolo;      // 1.0 = 双层全息
};

// MARK: - 顶点着色器 (1:1 复刻 mainVertex)
vertex Vertex vertexShader(uint vertexID [[vertex_id]]) {
    const float2 positions[] = {
        float2(-1.0, -1.0), // bottom left
        float2(1.0, 1.0),   // top right
        float2(1.0, -1.0),  // bottom right
        float2(-1.0, -1.0), // bottom left
        float2(-1.0, 1.0),  // top left
        float2(1.0, 1.0),   // top right
    };
    
    const float2 uvs[] = {
        float2(0.0, 0.0),
        float2(1.0, 1.0),
        float2(1.0, 0.0),
        float2(0.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0),
    };
    
    Vertex out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

// MARK: - 工具函数

// 角度转弧度 (WGSL radians() 的 Metal 实现)
float radians(float degrees) {
    return degrees * (M_PI_F / 180.0);
}

// 随机数生成 (1:1 复刻 random)
float random(float2 st) {
    return fract(sin(dot(st, float2(12.9898, 78.233))) * 437358.845701);
}

// RGB 转 HSV (1:1 复刻 rgbToHSV)
float3 rgbToHSV(float3 rgb) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(
        float4(rgb.z, rgb.y, K.w, K.z),
        float4(rgb.y, rgb.z, K.x, K.y),
        step(rgb.z, rgb.y)
    );
    float4 q = mix(
        float4(p.x, p.y, p.w, rgb.x),
        float4(rgb.x, p.y, p.z, p.x),
        step(p.x, rgb.x)
    );
    
    float v = max(q.x, q.y);
    float d_val = v - min(q.y, q.w);
    float epsilon = 1.0e-10;
    
    float h_temp = q.z + (q.w - q.y) / (6.0 * d_val + epsilon);
    float h = fract(h_temp);
    float s = d_val / (v + epsilon);
    
    return float3(h, s, v);
}

// HSV 转 RGB (1:1 复刻 hsvToRGB)
float3 hsvToRGB(float3 hsv) {
    float h = hsv.x;
    float s = hsv.y;
    float v = hsv.z;
    
    float h2 = h * 6.0;
    float i = floor(h2);
    float f = h2 - i;
    
    float p = v * (1.0 - s);
    float q = v * (1.0 - s * f);
    float t = v * (1.0 - s * (1.0 - f));
    
    float i0 = step(0.0, i) - step(1.0, i);
    float i1 = step(1.0, i) - step(2.0, i);
    float i2 = step(2.0, i) - step(3.0, i);
    float i3 = step(3.0, i) - step(4.0, i);
    float i4 = step(4.0, i) - step(5.0, i);
    float i5 = step(5.0, i) - step(6.0, i);
    
    float r = i0 * v + i1 * q + i2 * p + i3 * p + i4 * t + i5 * v;
    float g = i0 * t + i1 * v + i2 * v + i3 * q + i4 * p + i5 * p;
    float b = i0 * p + i1 * p + i2 * t + i3 * v + i4 * v + i5 * q;
    
    return float3(r, g, b);
}

// 色相偏移 (1:1 复刻 hueShift)
float3 hueShift(float3 rgb, float angle) {
    float3 hsv = rgbToHSV(rgb);
    float shiftedH = fract(hsv.x + angle / 360.0);
    return hsvToRGB(float3(shiftedH, hsv.y, hsv.z));
}

// 光泽颜色增强 (1:1 复刻 glareColorShift)
float3 glareColorShift(float3 color, float power) {
    float maxValue = max(max(color.x, color.y), color.z);
    float scale = mix(1.0, 1.0 / max(maxValue, 0.001), power);
    float3 boosted = color * scale;
    return mix(color, boosted, power);
}

// 单个通道 overlay (1:1 复刻 overlayChannel)
float overlayChannel(float base, float blend) {
    float mult = 2.0 * base * blend;
    float screen = 1.0 - 2.0 * (1.0 - base) * (1.0 - blend);
    return base < 0.5 ? mult : screen;
}

// 三通道 overlay (1:1 复刻 overlayChannels)
float3 overlayChannels(float3 base, float3 blend) {
    return float3(
        overlayChannel(base.x, blend.x),
        overlayChannel(base.y, blend.y),
        overlayChannel(base.z, blend.z)
    );
}

// MARK: - Holo 效果 (1:1 复刻 holoFragment.ts)

float4 holo(
    float2 uv,
    constant Uniforms &uniforms,
    float directionDegreeModifier,
    float shiftModifier,
    float rotationShiftPowerModifier
) {
    float2 rot = uniforms.rotation;
    
    float directionDegree = uniforms.holoDirectionDegree + directionDegreeModifier;
    float shift = uniforms.holoShift + shiftModifier;
    float rotationShiftPower = uniforms.holoRotationShiftPower * rotationShiftPowerModifier;
    float holoSize = uniforms.holoSize;
    float holoMultiplier = uniforms.holoMultiplier;
    float holoEaseSize = uniforms.holoEaseSize;
    float holoVisibility = uniforms.holoVisibility;
    float holoSaturation = uniforms.holoSaturation;
    
    float angleRadians = radians(directionDegree);
    
    float yMultiplier = abs(cos(angleRadians));
    float xMultiplier = abs(sin(angleRadians));
    float range = xMultiplier + yMultiplier;
    
    float intervalSize = range / holoMultiplier;
    float x = (uv.x * xMultiplier + uv.y * yMultiplier) + shift + 1.0;
    
    float rotationShift = rot.x * xMultiplier + rot.y * yMultiplier;
    float shiftMultiplied = rotationShift * rotationShiftPower;
    float offset = shiftMultiplied + shift;
    
    float xOffseted = fmod(x + offset, intervalSize);
    float diffractionSizeCalculated = holoSize * intervalSize;
    float diffractionNoiseSizeCalculated = diffractionSizeCalculated * holoEaseSize;
    float diffractionStart = diffractionNoiseSizeCalculated;
    float diffractionEnd = diffractionSizeCalculated + diffractionStart;
    
    float t = (xOffseted - diffractionStart) / (diffractionEnd - diffractionStart);
    float holoRotated = directionDegree > 179.0 ? M_PI_F : 0.0;
    float ft = (1.0 - cos(M_PI_F * t - holoRotated)) / 2.0;
    float hue = -0.06 + ft * 0.85;
    float hueWithNoise = hue + (random(uv) - 0.5) / 180.0 * 40.0;
    float missingRedHue = hueWithNoise + 1.0;
    float rainbowAccurateHue = hueWithNoise > 0.0 ? hueWithNoise : missingRedHue;
    
    bool boundaryCheck = xOffseted < diffractionStart || xOffseted > diffractionEnd;
    float xBoundary = xOffseted > diffractionStart ? xOffseted - diffractionEnd : diffractionStart - xOffseted;
    float xBoundaryScaled = xBoundary / diffractionNoiseSizeCalculated;
    float boundaryVisibilityScaled = pow(xBoundaryScaled, 2.0);
    float calculatedVisibility = clamp(mix(holoVisibility, 1.0, boundaryVisibilityScaled * float(boundaryCheck)), 0.0, 1.0);
    
    float3 shiftedRGB = hsvToRGB(float3(rainbowAccurateHue, holoSaturation, 1.0));
    float visibilityAdjusted = calculatedVisibility; // 原代码用 texture alpha，这里简化
    
    return float4(shiftedRGB, visibilityAdjusted);
}

// Double Holo (1:1 复刻 doubleHoloFragment)
float4 doubleHolo(float2 uv, constant Uniforms &uniforms) {
    float4 firstHolo = holo(uv, uniforms, 0.0, 0.0, 1.0);
    float4 secondHolo = holo(uv, uniforms, 178.0, 0.59, -1.0);
    
    float aa = firstHolo.w + secondHolo.w;
    float vis = 2.0 - aa;
    float test = 1.0 - vis;
    float visibility = clamp(test, 0.9, 1.0);
    
    bool useSingle = secondHolo.w == 1.0;
    float4 singleColor = useSingle ? firstHolo : secondHolo;
    
    float4 addedColor = float4(overlayChannels(firstHolo.xyz, secondHolo.xyz), visibility);
    
    bool useAdded = secondHolo.w != 1.0 && firstHolo.w != 1.0;
    return useAdded ? addedColor : singleColor;
}

// MARK: - Glare 效果 (1:1 复刻 glareFragment.ts)

float4 glare(
    float2 inputUV,
    constant Uniforms &uniforms,
    texture2d<float> cardTexture [[texture(0)]],
    texture2d<float> blurredTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]]
) {
    float2 uv = float2(inputUV.x, 1.0 - inputUV.y);
    float2 centeredCoords = uv * 2.0 - 1.0;
    
    float2 rot = uniforms.rotation;
    float2 center = float2(rot.x, rot.y);
    
    float glareIntensity = uniforms.glareIntensity;
    float glowPower = uniforms.glowPower;
    float lightIntensity = uniforms.lightIntensity / 1.3;
    float hueBlendPower = uniforms.hueBlendPower;
    float hueShiftAngleMin = uniforms.hueShiftAngleMin;
    float hueShiftAngleMax = uniforms.hueShiftAngleMax;
    
    float4 color = cardTexture.sample(textureSampler, uv);
    float4 blurredColor = blurredTexture.sample(textureSampler, uv);
    
    float dist = distance(center, centeredCoords);
    float radial = exp(-dist);
    float radialScaled = radial * (1.0 + max(0.0, glareIntensity));
    float influenceRaw = smoothstep(0.0, 1.0, radialScaled);
    float curveExp = clamp(glowPower, 0.05, 64.0);
    float glowMask = pow(influenceRaw, 1.0 / curveExp);
    
    float maskedGlow = glowMask * blurredColor.w;
    float3 boostedRGB = glareColorShift(blurredColor.xyz, maskedGlow);
    
    float hueT = clamp(maskedGlow, 0.0, 1.0);
    float hueAngle = mix(hueShiftAngleMin, hueShiftAngleMax, hueT);
    float3 hueShifted = hueShift(boostedRGB, hueAngle);
    
    float hueMixWeight = clamp((hueBlendPower / 5.0) * maskedGlow, 0.0, 1.0);
    float3 chromaMixed = mix(color.xyz, hueShifted, hueMixWeight);
    
    float glareStrength = clamp(lightIntensity, 0.0, 100.0);
    float3 glareLayer = float3(maskedGlow) * glareStrength;
    
    float3 overlaidRGB = overlayChannels(chromaMixed, glareLayer);
    float3 finalRGB = mix(chromaMixed, overlaidRGB, float3(maskedGlow));
    
    return float4(clamp(finalRGB, 0.0, 1.0), color.w);
}

// MARK: - 主片段着色器

fragment float4 fragmentShader(
    Vertex in [[stage_in]],
    constant Uniforms &uniforms [[buffer(0)]],
    texture2d<float> cardTexture [[texture(0)]],
    texture2d<float> blurredTexture [[texture(1)]],
    sampler textureSampler [[sampler(0)]]
) {
    float2 uv = in.uv;
    
    // 获取基础颜色
    float4 baseColor = cardTexture.sample(textureSampler, uv);
    
    float4 finalColor = baseColor;
    
    // 应用 Holo 效果
    if (uniforms.enableHolo > 0.5) {
        float4 holoColor;
        if (uniforms.enableDoubleHolo > 0.5) {
            holoColor = doubleHolo(uv, uniforms);
        } else {
            holoColor = holo(uv, uniforms, 0.0, 0.0, 1.0);
        }
        // 混合全息层（使用 alpha 混合）
        finalColor.xyz = overlayChannels(finalColor.xyz, holoColor.xyz * holoColor.w);
    }
    
    // 应用 Glare 效果
    if (uniforms.enableGlare > 0.5) {
        float4 glareColor = glare(uv, uniforms, cardTexture, blurredTexture, textureSampler);
        finalColor = glareColor;
    }
    
    return finalColor;
}
