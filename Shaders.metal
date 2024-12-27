#include <simd/simd.h>

struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
    float3 normal [[attribute(2)]];
    float2 texCoord [[attribute(3)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct Uniforms {
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 projectionMatrix;
};

vertex VertexOut vertexShader(VertexIn in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 worldPosition = uniforms.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
    out.color = in.color;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]]) {
    return in.color;
} 