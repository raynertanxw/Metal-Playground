//
//  Shaders.metal
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 25/7/25.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct AtlasVertex {
    float2 position [[attribute(AtlasVertAttrPosition)]];
    float2 uv [[attribute(AtlasVertAttrUV)]];
};

struct AtlasInstanceData {
    float4x4 transform;
    float4 color;
    float2 atlasUVMin;
    float2 atlasUVMax;
    uint32_t __padding[8];
};

struct AtlasVOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex AtlasVOut vertex_atlas(AtlasVertex in [[stage_in]],
                         uint instanceId [[instance_id]],
                         const constant AtlasInstanceData* instances [[buffer(BufferIndexInstances)]])
{
    const AtlasInstanceData inst = instances[instanceId];
    
    AtlasVOut out;
    float4 pos = float4(in.position, 0.0, 1.0);
    out.position = instances[instanceId].transform * pos;
    out.uv = mix(inst.atlasUVMin, inst.atlasUVMax, in.uv); // mix is lerp
    out.color = instances[instanceId].color;
    
    return out;
}

fragment float4 fragment_atlas(AtlasVOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              sampler samp [[sampler(0)]]) {
    float4 texColor = tex.sample(samp, in.uv);
    return texColor * in.color;
}

