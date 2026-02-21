//
//  ShineShader.metal
//  ShineCard
//
//  高级光泽效果 - 全息卡牌风格
//

#include <metal_stdlib>
using namespace metal;

// 顶点结构
struct Vertex {
    float4 position [[position]];
    float2 texCoord;
};

// 顶点着色器
vertex Vertex vertexShader(uint vertexID [[vertex_id]]) {
    const Vertex vertices[] = {
        {{-1.0, -1.0, 0.0, 1.0}, {0.0, 1.0}},
        {{ 1.0, -1.0, 0.0, 1.0}, {1.0, 1.0}},
        {{-1.0,  1.0, 0.0, 1.0}, {0.0, 0.0}},
        {{ 1.0,  1.0, 0.0, 1.0}, {1.0, 0.0}},
    };
    return vertices[vertexID];
}

// Uniforms
struct Uniforms {
    float2 touchPosition;
    float isTouching;
    float time;
    float2 resolution;
};

// 噪声函数 - 用于添加纹理感
float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash22(i).x;
    float b = hash22(i + float2(1.0, 0.0)).x;
    float c = hash22(i + float2(0.0, 1.0)).x;
    float d = hash22(i + float2(1.0, 1.0)).x;
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 菲涅尔效应 - 边缘发光
float fresnel(float cosTheta, float power) {
    return pow(1.0 - abs(cosTheta), power);
}

// HSL 转 RGB
float3 hsl2rgb(float3 c) {
    float3 rgb = clamp(abs(fmod(c.x * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return c.z + c.y * (rgb - 0.5) * (1.0 - abs(2.0 * c.z - 1.0));
}

// 片段着色器 - 高级全息光泽效果
fragment float4 fragmentShader(
    Vertex in [[stage_in]],
    constant Uniforms &uniforms [[buffer(0)]],
    texture2d<float> cardTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    float2 uv = in.texCoord;
    float2 touchPos = uniforms.touchPosition;
    float time = uniforms.time;
    
    // 采样基础纹理
    float4 baseColor = cardTexture.sample(textureSampler, uv);
    
    // 计算与触摸点的方向向量
    float2 toTouch = touchPos - uv;
    float dist = length(toTouch);
    float2 dir = normalize(toTouch + 0.0001); // 避免除零
    
    // === 1. 动态光泽光源 ===
    // 模拟手指移动时的光源位置（从触摸点斜上方照射）
    float2 lightPos = touchPos + float2(0.1 * sin(time), 0.15);
    float lightDist = length(uv - lightPos);
    
    // 主光泽 - 高斯分布
    float shineRadius = 0.25;
    float primaryShine = exp(-(lightDist * lightDist) / (2.0 * shineRadius * shineRadius));
    
    // === 2. 菲涅尔边缘光 ===
    // 基于 UV 边缘的距离计算菲涅尔效应
    float2 fromCenter = uv - 0.5;
    float edgeDist = length(fromCenter);
    float edgeFresnel = fresnel(edgeDist * 2.0, 2.5);
    
    // === 3. 全息干涉图案 ===
    // 模拟全息卡片的彩虹衍射效果
    float angle = atan2(dir.y, dir.x);
    float interference = sin(dist * 30.0 - time * 3.0) * 0.5 + 0.5;
    float interference2 = sin(angle * 8.0 + dist * 20.0 + time * 2.0) * 0.5 + 0.5;
    
    // 组合干涉图案
    float holoPattern = interference * interference2 * (1.0 - dist * 0.8);
    
    // === 4. 彩虹色散 ===
    // 基于距离和角度的动态色相
    float hue = fract((dist * 2.0 - angle / 6.28318) + time * 0.3);
    float3 rainbow = hsl2rgb(float3(hue, 0.8, 0.6));
    
    // === 5. 噪点纹理 ===
    // 添加细微的噪点增加真实感
    float noiseVal = noise(uv * 200.0 + time * 0.1);
    float grain = mix(0.95, 1.05, noiseVal);
    
    // === 6. 组合效果 ===
    float3 finalColor = baseColor.rgb;
    
    // 基础光泽（白色高光）
    float3 specular = float3(1.0, 0.98, 0.95) * primaryShine * 0.6;
    
    // 全息彩虹（仅在触摸时出现）
    float3 holographic = rainbow * holoPattern * 0.4 * uniforms.isTouching;
    
    // 边缘菲涅尔光（始终存在，但触摸时增强）
    float edgeIntensity = 0.15 + uniforms.isTouching * 0.25;
    float3 edgeGlow = rainbow * edgeFresnel * edgeIntensity;
    
    // 混合所有层
    finalColor = finalColor * grain;
    finalColor += specular * uniforms.isTouching;
    finalColor += holographic;
    finalColor += edgeGlow;
    
    // === 7. 微光闪烁 ===
    float sparkle = pow(noise(uv * 100.0 + time * 5.0), 8.0) * 0.3 * uniforms.isTouching;
    finalColor += sparkle;
    
    // 最终颜色调整 - 保持对比度
    finalColor = pow(finalColor, 0.9); // 轻微提亮
    
    return float4(finalColor, baseColor.a);
}
