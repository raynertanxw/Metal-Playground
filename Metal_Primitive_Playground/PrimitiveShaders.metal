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
};

struct PrimitiveUniforms {
    float4x4 projectionMatrix;
};

struct PrimitiveInstanceData {
    float4x4 transform;
    float4 color;
    uint shapeType;
    float4 sdfParams;
};

struct PrimitiveVOut {
    float4 position [[position]];
    float2 localPos;
    float4 color;
    uint shapeType;
    float4 sdfParams;
};

vertex PrimitiveVOut vertex_primitive(uint vertexId [[vertex_id]],
                                      uint instanceId [[instance_id]],
                                      const constant PrimitiveVertex* vertices [[buffer(0)]],
                                      const constant PrimitiveInstanceData *instances [[buffer(1)]],
                                      const constant PrimitiveUniforms& uniforms [[buffer(2)]])
{
    const PrimitiveVertex v = vertices[vertexId];
    const PrimitiveInstanceData inst = instances[instanceId];
    
    PrimitiveVOut out;
    out.localPos = v.position; // Keep for SDF evaluation
    
    float4 worldPos = inst.transform * float4(v.position, 0.0, 1.0);
    out.position = uniforms.projectionMatrix * worldPos;
    
    out.color = inst.color;
    out.shapeType = inst.shapeType;
    out.sdfParams = inst.sdfParams;
    
    return out;
}

fragment float4 fragment_primitive(PrimitiveVOut in [[stage_in]]) {
    float2 uv = in.localPos;

    float alpha = 0.0;

    if (in.shapeType == 0) {
        // Rect
        float2 d = abs(uv) - 1.0;
        float dist = max(d.x, d.y);
        alpha = smoothstep(0.01, -0.01, dist);
    } else if (in.shapeType == 1) {
        // TODO: UNTESTED
        // Rounded Rect
        float radius = in.sdfParams.x;
        float2 size = float2(1.0 - radius, 1.0 - radius);
        float2 d = abs(uv) - size;
        float dist = length(max(d, 0.0)) - radius;
        alpha = smoothstep(0.01, -0.01, dist);
    } else if (in.shapeType == 2) {
        // Circle (fully rounded rect)
        float radius = 0.5;
        float edge = 0.001;
        float dist = length(uv);
        alpha = smoothstep(radius, radius - edge, dist);
    }

    return float4(in.color.rgb, in.color.a * alpha);
}


