//
//  Renderer.hpp
//  Metal Playground macOS CPP
//
//  Created by Rayner Tan on 21/8/25.
//

#ifndef Renderer_hpp
#define Renderer_hpp

#include <Metal/Metal.hpp>
#include <MetalKit/MetalKit.hpp>
#include <simd/simd.h>
#include <functional>
#include <map>
#include <string>
#include <vector>
#include <optional>

struct AtlasVertex {
    simd_float2 position;
    simd_float2 uv;
};

struct AtlasInstanceData {
    simd_float4x4 transform;
    simd_float4 color;
    simd_float2 uvMin;
    simd_float2 uvMax;
    uint32_t __padding[8];
};

struct AtlasUVRect {
    simd_float2 minUV; // bottom-left
    simd_float2 maxUV; // top-right
};

struct PrimitiveVertex {
    simd_float2 position;
};

struct PrimitiveUniforms {
    simd_float4x4 projectionMatrix;
};

struct PrimitiveInstanceData {
    simd_float4x4 transform;
    simd_float4 color;
    int32_t shapeType;
    simd_float4 sdfParams;
    uint32_t __padding[4];
};

struct TextVertex {
    simd_float2 position;
    simd_float2 uv;
    simd_float4 textColor;
};

struct TextFragmentUniforms {
    float distanceRange;
};

// MARK: - Font Atlas Structs
// TODO: Check, need to load this as a codable from the JSON...
// TODO: Consider changing all doubles to floats
struct AtlasMetrics {
    std::string type;
    double distanceRange;
    double size;
    int width;
    int height;
    std::string yOrigin;
};

struct FontMetrics {
    double emSize;
    double lineHeight;
    double ascender;
    double descender;
    double underlineY;
    double underlineThickness;
};

struct Bounds {
    double left;
    double bottom;
    double right;
    double top;
};

struct Glyph {
    int unicode;
    double advance;
    std::optional<Bounds> planeBounds;
    std::optional<Bounds> atlasBounds;
};

struct Kerning {
    int unicode1;
    int unicode2;
    double advance;
};

struct FontAtlas {
    AtlasMetrics atlas;
    FontMetrics metrics;
    std::vector<Glyph> glyphs;
    std::vector<Kerning> kerning;
};

class Renderer
{
public:
    Renderer( MTL::Device* pDevice, MTK::View* pView );
    ~Renderer();
    void draw( MTK::View* pView );
    void drawableSizeWillChange( MTK::View* pView, CGSize size );

    
    // MARK: - For debugging
    CFTimeInterval lastRenderTimestamp = 0;
    int renderFrameCount = 0;
    double reportedFPS = 0;
    std::function<void(double)> onFramePresented = nullptr;

private:
    simd_float4x4 projectionMatrix = matrix_identity_float4x4;
    CGSize screenSize = {0.0f, 0.0f};
    
    MTL::Device* device;
    MTL::CommandQueue* commandQueue;
    
    static const int maxBuffersInFlight = 3;
    dispatch_semaphore_t inFlightSemaphore;
    int triBufferIndex = 0;
    
    
    // MARK: - ATLAS PIPELINE VARS
    MTL::RenderPipelineState* atlasPipelineState = nullptr;
    MTL::Buffer* atlasVertexBuffer = nullptr;
    MTL::Buffer* atlasTriInstanceBuffer = nullptr;
    int atlasTriInstanceBufferOffset = 0;
    AtlasInstanceData* atlasInstancesPtr = nullptr;
    const int atlasMaxInstanceCount = 150000;
    int atlasInstanceCount = 0;
    
    const AtlasVertex atlasSquareVertices[4] = {
        AtlasVertex{ .position={ -0.5f, -0.5f }, .uv={ 0.0f, 1.0f } },
        AtlasVertex{ .position={  0.5f, -0.5f }, .uv={ 1.0f, 1.0f } },
        AtlasVertex{ .position={ -0.5f,  0.5f }, .uv={ 0.0f, 0.0f } },
        AtlasVertex{ .position={  0.5f,  0.5f }, .uv={ 1.0f, 0.0f } }
    };
    // TODO: Use Arguement buffers to pass multiple texture atlasses?
    MTL::Texture* mainAtlasTexture = nullptr;
    std::map<std::string, AtlasUVRect> mainAtlasUVRects;
    // TODO: This should be a const... set in constructor...?
    MTL::SamplerState* atlasSamplerState;
    
    
    // MARK: - PRIMITIVE PIPELINE VARs
    MTL::RenderPipelineState* primitivePipelineState = nullptr;
    MTL::Buffer* primitiveVertexBuffer = nullptr;
    MTL::Buffer* primitiveTriInstanceBuffer = nullptr;
    int primitiveTriInstanceBufferOffset = 0;
    PrimitiveInstanceData* primitiveInstancesPtr = nullptr;
    const int primitiveMaxInstanceCount = 150000;
    int primitiveInstanceCount = 0;
    
    const PrimitiveVertex primitiveSquareVertices[4] = {
        PrimitiveVertex{.position={-0.5, -0.5}},
        PrimitiveVertex{.position={0.5, -0.5}},
        PrimitiveVertex{.position={-0.5, 0.5}},
        PrimitiveVertex{.position={0.5, 0.5}}
    };
    
    PrimitiveUniforms primitiveUniforms = PrimitiveUniforms {.projectionMatrix=matrix_identity_float4x4};
    
    
    
    // MARK: - TEXT PIPELINE VARS
    MTL::Texture* fontTexture;
    FontAtlas fontAtlas;
    std::map<UInt32, Glyph> fontGlyphs;
    std::map<UInt64, Kerning> fontKerning;
    
    MTL::RenderPipelineState* textPipelineState;
    MTL::SamplerState* textSamplerState;
    MTL::Buffer* textTriVertexBuffer;
    const int textMaxVertexCount = 4096 * 6;
    int textTriInstanceBufferOffset = 0;
    TextVertex* textVertexBufferPtr = nullptr;
    int textVertexCount = 0;
    
    
    // MARK: - Draw Command Batching
    enum DrawBatchType {
        drawbatchtype_none = 0,
        drawbatchtype_atlas = 1,
        drawbatchtype_primitive = 2,
        drawbatchtype_text = 3,
        drawbatchtype_count = 4,
    };
    struct DrawBatch {
        DrawBatchType type;
        int startIndex;
        int count;
    };
    DrawBatch* drawBatchesArr = nullptr;
    int drawBatchCount = 0;
    const int drawBatchMaxCount = 1024;
    DrawBatchType curDrawBatchType = drawbatchtype_none;
    // TODO: Can rename these next two vars also...
    int nextStartIndexForTypePtr[drawbatchtype_count];
    int strideSizesPtr[drawbatchtype_count];
    
    
    // MARK: - GAME RELATED
    float time = 0.0f;
    
    void buildAtlasBuffers();
    void buildPrimitiveBuffers();
    void buildTextBuffers();
    void updateTriBufferStates();
    void buildAtlasPipeline(MTL::PixelFormat pixelFormat);
    void buildPrimitivePipeline(MTL::PixelFormat pixelFormat);
    void buildTextPipeline(MTL::PixelFormat pixelFormat);
    void loadAtlasTextureAndUV();
    void loadTextInfoAndTexture();
    
    // MARK: - Test functions
    void testDrawPrimitives();
    void testDrawAtlasSprites();
    
    // MARK: - Draw Helpers
    static inline simd_float4 colorFromBytes(UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    inline int addToDrawBatchAndGetAdjustedIndex(DrawBatchType type, int increment);
    
    void drawSprite(const char* spriteName, float x, float y, float width, float height, UInt8 r, UInt8 g, UInt8 b, UInt8 a, float rotationRadians);
    void drawSprite(const char* spriteName, float x, float y, float width, float height, simd_float4 color, float rotationRadians);
    
    void drawPrimitiveCircle(float x, float y, float radius, UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    void drawPrimitiveCirlce(float x, float y, float radius, simd_float4 color);
    
    void drawPrimitiveCircleLines(float x, float y, float radius, float thickness, UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    void drawPrimitiveCircleLines(float x, float y, float radius, float thickness, simd_float4 color);
    
    void drawPrimitiveLine(float x1, float y1, float x2, float y2, float thickness, UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    void drawPrimitiveLine(float x1, float y1, float x2, float y2, float thickness, simd_float4 color);
    
    void drawPrimitiveRect(float x, float y, float width, float height, UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    void drawPrimitiveRect(float x, float y, float width, float height, simd_float4 color);
    
    void drawPrimitiveRoundedRect(float x, float y, float width, float height, float cornerRadius, UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    void drawPrimitiveRoundedRect(float x, float y, float width, float height, float cornerRadius, simd_float4 color);
    
    void drawPrimitiveRectLines(float x, float y, float width, float height, float thickness, UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    void drawPrimitiveRectLines(float x, float y, float width, float height, float thickness, simd_float4 color);
    
    // TODO: Text Drawing Functions
};

#endif /* Renderer_hpp */
