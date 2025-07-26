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
    float3 color;
};

struct PrimitiveFragmentInput {
    float4 position [[position]];
    float4 color;
};

vertex PrimitiveFragmentInput vertex_primitive(constant PrimitiveVertex* vertices,
                          uint index [[vertex_id]]) {
    return {
        .position { float4(vertices[index].position, 1.0, 1.0) },
        .color { float4(vertices[index].color, 1.0) }
    };
}

fragment float4 fragment_primitive(PrimitiveFragmentInput input [[stage_in]]) {
    return input.color;
}

