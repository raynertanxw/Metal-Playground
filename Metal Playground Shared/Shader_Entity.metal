//
//  EntityShaders.metal
//
//  Created by Rayner Tan on 12/10/26.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct EntityVertex {
    float2 position;
};

struct EntityUniforms {
    float4x4 projectionMatrix;
};

struct EntityInstanceData {
    float4x4 transform;
    float4 color;
    float4 atlasUVs;
    float4 sdfParams;
    uint32_t shapeType;
    uint32_t __padding[3];
};

struct EntityVOut {
    float4 position [[position]];
    float2 localPos;
    float2 atlasUV;
    float4 color;
    uint32_t shapeType;
    float4 sdfParams;
};

vertex EntityVOut vertex_entity(uint vertexId [[vertex_id]],
                                      uint instanceId [[instance_id]],
                                      const constant EntityVertex *vertices [[buffer(BufferIndexVertices)]],
                                      const constant EntityInstanceData *instances [[buffer(BufferIndexInstances)]],
                                      const constant EntityUniforms& uniforms [[buffer(BufferIndexUniforms)]])
{
    const EntityVertex v = vertices[vertexId];
    const EntityInstanceData inst = instances[instanceId];
    
    EntityVOut out;
    out.localPos = v.position; // Keep for SDF evaluation
    
    // Mathematically derive 0-to-1 base UV from the [-0.5, 0.5] quad
    float2 baseUV = float2(v.position.x + 0.5, 0.5 - v.position.y);
    
    // Mix (lerp) base UV into the bounds specified by the instance atlasUVs
    // xy = min UV, zw = max UV
    out.atlasUV = mix(inst.atlasUVs.xy, inst.atlasUVs.zw, baseUV);
    
    float4 worldPos = inst.transform * float4(v.position, 0.0, 1.0);
    out.position = uniforms.projectionMatrix * worldPos;
    
    out.color = inst.color;
    out.shapeType = inst.shapeType;
    out.sdfParams = inst.sdfParams;
    
    return out;
}

fragment float4 fragment_entity(EntityVOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                sampler samp [[sampler(0)]]) {
    
    // 1. Process Atlas Texture Draw First
    if (in.shapeType == ShapeTypeAtlas) {
        float4 texColor = tex.sample(samp, in.atlasUV);
        return texColor * in.color;
    }
    
    // 2. Otherwise, evaluate SDF primitives
    float2 uv = in.localPos;
    float alpha = 0.0;

    // SDF is super useful here: https://iquilezles.org/articles/distfunctions2d/
    if (in.shapeType == ShapeTypeNone) {
        alpha = 1.0;
        in.color.r = 1.0;
        in.color.g = 0.0;
        in.color.b = 1.0;
        in.color.a = 1.0;
        /// Magenta full alpha to show unset shape type.
    }
    else if (in.shapeType == ShapeTypeRect) {
        alpha = 1.0;
        /// Nothing special needed here. If you want blurring / smoothing then add smoothstep on rect SDF
    } else if (in.shapeType == ShapeTypeRoundedRect) {
        float2 halfSize = float2(in.sdfParams.x, in.sdfParams.y);
        float radius = min(in.sdfParams.z, min(halfSize.x, halfSize.y)); // Nice capsule if cornerRadius > width/height
        
        float2 pixelPos = uv * halfSize * 2.0; // uv is [-0.5, 0.5] quad space -> rescale to pixel space
        float2 size = halfSize - float2(radius);
        float2 d = abs(pixelPos) - size; // if d is -ve, means pixel is inside full rect area, no chance of corner radius.
        float dist = length(max(d, 0.0)) - radius;
        alpha = smoothstep(0.5, -0.5, dist);
    } else if (in.shapeType == ShapeTypeRectLines) {
        float2 halfSize = float2(in.sdfParams.x, in.sdfParams.y);
        float thickness = max(in.sdfParams.z, 1.0); // min thickness is 1
        
        float2 pixelPos = uv * halfSize * 2.0; // uv is [-0.5, 0.5] quad space -> rescale to pixel space
        float2 d = abs(pixelPos) - halfSize + float2(thickness);
        float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
        alpha = smoothstep(-0.5, 0.5, dist);
    } else if (in.shapeType == ShapeTypeCircle) {
        float radius = in.sdfParams.x;
        float edge = max(in.sdfParams.y, 0.5);
        
        float2 pixelPos = uv * radius * 2.0; // uv is [-0.5, 0.5] quad space -> rescale to [-radius, radius]
        float dist = length(pixelPos) - radius;
        alpha = smoothstep(edge, -edge, dist);
        /// If want smoothing quite a bit of blur kind of smoothing, consider doing
        /// smoothstep(radius, radius - edge, dist); you won't blur beyond the rect
        /// BUT you will loose some accuracy towards the edge (circle will look smaller than radius)
    } else if (in.shapeType == ShapeTypeCircleLines) {
        float radius = in.sdfParams.x;
        float edge = max(in.sdfParams.y, 0.5);
        float halfThickness = max(in.sdfParams.z, 1.0); // Half thickness to keep it inside stroke style.
        
        float2 pixelPos = uv * radius * 2.0; // uv is [-0.5, 0.5] quad space -> rescale to [-radius, radius]
        // range from dist + thickness to dist
        float dist = length(pixelPos) - radius;
        alpha = smoothstep(edge, -edge, abs(dist + halfThickness) - halfThickness);
        /// If want smoothing quite a bit of blur kind of smoothing, consider doing
        /// smoothstep(radius, radius - edge, dist); you won't blur beyond the rect
        /// BUT you will loose some accuracy towards the edge (circle will look smaller than radius)
    }


    return float4(in.color.rgb, in.color.a * alpha);
}


