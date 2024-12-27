#include <metal_stdlib>
using namespace metal;

vertex float4 vertexShader(uint vertexID [[vertex_id]]) {
    const float2 vertices[] = {
        float2(0.0, 0.5),    // top
        float2(-0.5, -0.5),  // bottom left
        float2(0.5, -0.5)    // bottom right
    };

    return float4(vertices[vertexID], 0.0, 1.0);
}

fragment float4 fragmentShader() {
    return float4(1.0, 0.0, 0.0, 1.0); // Red color
}
