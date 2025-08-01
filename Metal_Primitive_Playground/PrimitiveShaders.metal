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
        // Rounded Rect
        float2 halfSize = float2(in.sdfParams.x, in.sdfParams.y);
        float radius = min(in.sdfParams.z, min(halfSize.x, halfSize.y)); // Nice capsule if cornerRadius > width/height

        // Map localPos from [-0.5, 0.5] to pixel space
        float2 pixelPos = uv * halfSize * 2.0;
        
        float2 size = halfSize - float2(radius);
        float2 d = abs(pixelPos) - size;
        float dist = length(max(d, 0.0)) - radius;
        
        // Use a smoother edge width (~1.0 pixel range)
        alpha = smoothstep(1.0, -1.0, dist);
    } else if (in.shapeType == 2) { // Circle (fully rounded rect)
        float radius = in.sdfParams.x;
        float2 pixelPos = uv * radius * 2.0; // uv is [-0.5, 0.5] quad space → rescale to [-radius, radius]
        float dist = length(pixelPos); // Distance to center which is (0,0)
        float edge = max(in.sdfParams.y, 0.5);
        alpha = smoothstep(radius + edge, radius - edge, dist);
        /// If want smoothing quite a bit of blur kind of smoothing, consider doing
        /// smoothstep(radius, radius - edge, dist); you won't blur beyond the rect
        /// BUT you will loose some accuracy towards the edge (circle will look smaller than radius)
    }


    return float4(in.color.rgb, in.color.a * alpha);
}


