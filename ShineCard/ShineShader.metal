//
//  ShineShader.metal
//  ShineCard
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
        {{-1.0, -1.0, 0.0, 1.0}, {0.0, 1.0}},  // 左下
        {{ 1.0, -1.0, 0.0, 1.0}, {1.0, 1.0}},  // 右下
        {{-1.0,  1.0, 0.0, 1.0}, {0.0, 0.0}},  // 左上
        {{ 1.0,  1.0, 0.0, 1.0}, {1.0, 0.0}},  // 右上
    };
    return vertices[vertexID];
}

// 片段着色器 uniform
struct Uniforms {
    float2 touchPosition;  // 0-1 范围
    float isTouching;
    float time;
};

// 片段着色器 - 光泽效果
fragment float4 fragmentShader(
    Vertex in [[stage_in]],
    constant Uniforms &uniforms [[buffer(0)]],
    texture2d<ffloat> cardTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    // 采样卡片纹理
    float4 color = cardTexture.sample(textureSampler, in.texCoord);
    
    // 如果没有触摸，直接返回原色
    if (uniforms.isTouching < 0.5) {
        return color;
    }
    
    // 计算与触摸点的距离
    float2 uv = in.texCoord;
    float dist = distance(uv, uniforms.touchPosition);
    
    // 光泽强度 - 距离越近越亮
    float shineRadius = 0.35;
    float shineIntensity = smoothstep(shineRadius, 0.0, dist);
    
    // 光泽颜色（白色带点彩虹）
    float3 shineColor = float3(1.0, 1.0, 1.0);
    
    // 添加彩虹色相偏移
    float hue = (uniforms.time * 0.5 + dist * 2.0) * 6.28318;
    shineColor.r += sin(hue) * 0.1;
    shineColor.g += sin(hue + 2.094) * 0.1;
    shineColor.b += sin(hue + 4.188) * 0.1;
    
    // 混合光泽
    float3 finalColor = mix(color.rgb, shineColor, shineIntensity * 0.4);
    
    // 边缘高光
    float edgeShine = pow(shineIntensity, 3.0) * 0.5;
    finalColor += shineColor * edgeShine;
    
    return float4(finalColor, color.a);
}
