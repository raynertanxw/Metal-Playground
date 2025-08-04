//
//  TextShaders.metal
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 2/8/25.
//

#include <metal_stdlib>
using namespace metal;
#include "ShaderTypes.h"

struct TextFragmentUniforms {
    float4 textColor;
    float distanceRange;
};

struct VertexIn {
    float2 position [[attribute(TextVertAttrPosition)]];
    float2 uv [[attribute(TextVertAttrUV)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// MARK: - Vertex Shader
vertex VertexOut text_vertex_shader(const VertexIn vertex_in [[stage_in]],
                                    constant float4x4 &projection_matrix [[buffer(TextBufferIndexProjectionMatrix)]])
{
    VertexOut out;
    out.position = projection_matrix * float4(vertex_in.position, 0.0, 1.0);
    out.uv = vertex_in.uv;
    return out;
}

// MARK: - Fragment Shader
fragment float4 text_fragment_shader(VertexOut in [[stage_in]],
                                     texture2d<float> sdfTexture [[texture(0)]],
                                     constant TextFragmentUniforms &uniforms [[buffer(0)]],
                                     const sampler samp [[sampler(0)]])
{
    float3 msdf = sdfTexture.sample(samp, in.uv).rgb;
    float sd = median3(msdf.r, msdf.g, msdf.b);;

    float screenPxRange = max(fwidth(sd), 1e-4); // Prevent divide-by-zero or zero smoothing
    float edgeOffset = screenPxRange / uniforms.distanceRange;
    float bias = -0.00;
    
    float alpha = smoothstep(0.5 + bias - edgeOffset, 0.5 + bias + edgeOffset, sd);
    return float4(uniforms.textColor.rgb, uniforms.textColor.a * alpha);
    
    
    // TODO: Possible future features such as outline and drop shadow.
}
