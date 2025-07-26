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
    float2 uv;
};

struct InstanceData {
    float4x4 transform;
    float4 color;
    float2 atlasUVMin;
    float2 atlasUVMax;
};

struct VOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex VOut vertex_main(uint vertexId [[vertex_id]],
                         uint instanceId [[instance_id]],
                         const device Vertex* vertices [[buffer(0)]],
                         const device InstanceData* instances [[buffer(1)]])
{
    const Vertex v = vertices[vertexId];
    const InstanceData inst = instances[instanceId];
    
    VOut out;
    float4 pos = float4(v.position, 0.0, 1.0);
    out.position = instances[instanceId].transform * pos;
    out.uv = mix(inst.atlasUVMin, inst.atlasUVMax, v.uv); // mix is lerp
    out.color = instances[instanceId].color;
    
    return out;
}

fragment float4 fragment_main(VOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              sampler samp [[sampler(0)]]) {
    float4 texColor = tex.sample(samp, in.uv);
    return texColor * in.color;
}

