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
                                      texture2d<float> sdf_texture [[texture(0)]],
                                      constant float4 &text_color [[buffer(0)]])
{
    constexpr sampler tex_sampler(min_filter::linear, mag_filter::linear);

    // Sample the MSDF texture.
    float4 sample = sdf_texture.sample(tex_sampler, in.texCoord);

    // Find the median of the R, G, and B channels to get the signed distance.
    float sd = median(sample.r, sample.g, sample.b);
    
    // --- The Core SDF Rendering Logic ---
    // `screen_px_range` defines how "soft" the edge is.
    // `fwidth` calculates the change in distance across a pixel, making the
    // anti-aliasing resolution-independent.
    float screen_px_range = fwidth(sd);
    
    // `smoothstep` creates a smooth transition from 0 to 1.
    // We want the text to be opaque (alpha=1) when the distance `sd` is
    // greater than 0.5, and transparent (alpha=0) otherwise.
    // The transition happens over a range defined by `screen_px_range`.
    float opacity = clamp(smoothstep(0.5 - screen_px_range, 0.5 + screen_px_range, sd), 0.0, 1.0);

    // Final color is the text color multiplied by the calculated opacity.
    // The `premultipliedAlpha` blending on the pipeline will handle the rest.
    return float4(text_color.rgb * opacity, text_color.a * opacity);
    
    /*
    // --- ADVANCED EFFECTS (Examples) ---
    
    // 1. Outline
    float outline_width = 0.1; // 10% of the font size
    float outline_smoothing = screen_px_range * 2.0;
    float4 outline_color = float4(0.0, 0.0, 0.0, 1.0);
    float outline_factor = smoothstep(0.5 - outline_width - outline_smoothing, 0.5 - outline_width, sd);
    
    float4 final_color = mix(outline_color, text_color, opacity);
    return float4(final_color.rgb, (text_color.a * opacity) + (outline_color.a * (outline_factor - opacity)));
    
    // 2. Soft Shadow
    float shadow_offset = 0.05;
    float shadow_softness = 0.1;
    float4 shadow_color = float4(0.0, 0.0, 0.0, 0.5);
    float shadow_sd = median(sdf_texture.sample(tex_sampler, in.texCoord - shadow_offset).rgb);
    float shadow_opacity = smoothstep(0.5 - shadow_softness, 0.5 + shadow_softness, shadow_sd);
    
    float4 final_color = mix(shadow_color, text_color, opacity);
    return float4(final_color.rgb, max(opacity, shadow_opacity * shadow_color.a));
    */
}


