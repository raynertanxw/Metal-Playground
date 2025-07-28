//
//  PrimitiveShaders.metal
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 26/7/25.
//

#include <metal_stdlib>
using namespace metal;

struct PrimitiveVertex {
    float2 position;
    float4 colorRGBA;
};

struct PrimitiveUniforms {
    float4x4 projectionMatrix;
};

struct PrimitiveFragmentInput {
    float4 position [[position]];
    float4 color;
};

vertex PrimitiveFragmentInput vertex_primitive(constant PrimitiveVertex* vertices,
                                               uint index [[vertex_id]],
                                               constant PrimitiveUniforms& uniforms [[buffer(1)]]) {
    return {
        .position { uniforms.projectionMatrix * float4(vertices[index].position, 0, 1) },
        .color { float4(vertices[index].colorRGBA) }
    };
}

fragment float4 fragment_primitive(PrimitiveFragmentInput input [[stage_in]]) {
    return input.color;
}

