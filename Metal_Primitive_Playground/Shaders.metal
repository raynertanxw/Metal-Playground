//
//  Shaders.metal
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 25/7/25.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float2 position;
};

struct InstanceData {
    float4x4 transform;
    float4 color;
};

struct VOut {
    float4 position [[position]];
    float4 color;
};

vertex VOut vertex_main(uint vertexId [[vertex_id]],
                         uint instanceId [[instance_id]],
                         const device Vertex* vertices [[buffer(0)]],
                         const device InstanceData* instances [[buffer(1)]])
{
    VOut out;
    float4 pos = float4(vertices[vertexId].position, 0.0, 1.0);
    out.position = instances[instanceId].transform * pos;
    out.color = instances[instanceId].color;
    return out;
}

fragment float4 fragment_main(VOut in [[stage_in]]) {
    return in.color;
}

