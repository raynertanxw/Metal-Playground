//
//  TextShaders.metal
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 2/8/25.
//

#include <metal_stdlib>
using namespace metal;

// Data sent from the CPU to the vertex shader for each vertex.
struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

// Data passed from the vertex shader to the fragment shader.
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Vertex Shader

vertex VertexOut text_vertex_shader(const VertexIn vertex_in [[stage_in]],
                                    constant float4x4 &projection_matrix [[buffer(1)]])
{
    VertexOut out;
    // Simply transform the 2D position by the projection matrix and pass tex coords.
    out.position = projection_matrix * float4(vertex_in.position, 0.0, 1.0);
    out.texCoord = vertex_in.texCoord;
    return out;
}

// MARK: - Fragment Shader

// Helper function to find the median of three values.
// This is key to reconstructing the distance from the MSDF.
float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

fragment float4 text_fragment_shader(VertexOut in [[stage_in]],
                                     texture2d<float> sdfTexture [[texture(0)]],
                                     constant float4 &textColor [[buffer(0)]],
                                     constant float &distanceRange [[buffer(1)]])
{
    constexpr sampler texSampler(min_filter::linear, mag_filter::linear);

    float3 msdf = sdfTexture.sample(texSampler, in.texCoord).rgb;
    float sd = median(msdf.r, msdf.g, msdf.b);

    float screenPxRange = max(fwidth(sd), 1e-4); // Prevent divide-by-zero or zero smoothing
    float edgeOffset = screenPxRange / distanceRange;
    float bias = -0.00;
    
    float alpha = smoothstep(0.5 + bias - edgeOffset, 0.5 + bias + edgeOffset, sd);
    return float4(textColor.rgb * alpha, textColor.a * alpha);
    
    
    // TODO: Possible future features such as outline and drop shadow.
}


