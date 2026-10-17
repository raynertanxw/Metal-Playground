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

struct AtlasUVRect {
    simd_float2 minUV; // bottom-left
    simd_float2 maxUV; // top-right
};

struct EntityVertex {
    simd_float2 position;
};

struct EntityUniforms {
    simd_float4x4 projectionMatrix;
};

struct EntityInstanceData {
    simd_float4x4 transform;
    simd_float4 color;
    simd_float4 atlasUVs;
    simd_float4 sdfParams;
    uint32_t shapeType;
    uint32_t __padding[3];
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
struct AtlasMetrics {
    std::string type;
    float distanceRange;
    float size;
    int width;
    int height;
    std::string yOrigin;
};

struct FontMetrics {
    float emSize;
    float lineHeight;
    float ascender;
    float descender;
    float underlineY;
    float underlineThickness;
};

struct Bounds {
    float left;
    float bottom;
    float right;
    float top;
};

struct Glyph {
    int unicode;
    float advance;
    std::optional<Bounds> planeBounds;
    std::optional<Bounds> atlasBounds;
};

struct Kerning {
    int unicode1;
    int unicode2;
    float advance;
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
    
    
    // MARK: - ENTITY PIPELINE VARs
    MTL::RenderPipelineState* entityPipelineState = nullptr;
    MTL::Buffer* entityVertexBuffer = nullptr;
    MTL::Buffer* entityTriInstanceBuffer = nullptr;
    int entityTriInstanceBufferOffset = 0;
    EntityInstanceData* entityInstancesPtr = nullptr;
    const int entityMaxInstanceCount = 50000;
    int entityInstanceCount = 0;
    
    const EntityVertex entityBaseSquareVertices[4] = {
        EntityVertex{.position={-0.5f, -0.5f}},
        EntityVertex{.position={ 0.5f, -0.5f}},
        EntityVertex{.position={-0.5f,  0.5f}},
        EntityVertex{.position={ 0.5f,  0.5f}}
    };
    
    EntityUniforms entityUniforms = EntityUniforms{.projectionMatrix=matrix_identity_float4x4};
    
    // TODO: Use Argument buffers to pass multiple texture atlases?
    MTL::Texture* mainAtlasTexture = nullptr;
    std::map<std::string, AtlasUVRect> mainAtlasUVRects;
    MTL::SamplerState* atlasSamplerState = nullptr;
    
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
    const int textMaxSingleDrawVertCount = 320 * 6;
    TextVertex* textTempVertexBuffer = nullptr;
    
    // MARK: - Draw Command Batching
    enum DrawBatchType {
        drawbatchtype_none = 0,
        drawbatchtype_entity = 1,
        drawbatchtype_text = 2,
        drawbatchtype_count = 3,
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
    
    void buildEntityBuffers();
    void buildTextBuffers();
    void updateTriBufferStates();
    void buildEntityPipeline(MTL::PixelFormat pixelFormat);
    void buildTextPipeline(MTL::PixelFormat pixelFormat);
    void loadAtlasTextureAndUV();
    void loadTextInfoAndTexture();
    
    // MARK: - Test functions
    void testDrawEntities();
    void testDrawSprites();
    void testDrawTextWithBounds();
    void testDrawInterleavedTypes();
    
    // MARK: - Draw Helpers
    static inline simd_float4 colorFromBytes(UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    inline int addToDrawBatchAndGetAdjustedIndex(DrawBatchType type, int increment);
    
    // Atlas
    void drawSprite(const char* spriteName, float x, float y, float width, float height, UInt8 r, UInt8 g, UInt8 b, UInt8 a, float rotationRadians = 0.0f);
    void drawSprite(const char* spriteName, float x, float y, float width, float height, simd_float4 color, float rotationRadians = 0.0f);
    
    // Core Morph
    void drawMorph(float x, float y, float width, float height, float cornerRadius, simd_float4 color, float rotationRadians = 0.0f);
    void drawMorphLines(float x, float y, float width, float height, float cornerRadius, float thickness, simd_float4 color, float rotationRadians = 0.0f);
    
    // Backwards Compatible Wrappers
    void drawEntityCircle(float x, float y, float radius, UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    void drawEntityCircle(float x, float y, float radius, simd_float4 color);
    
    void drawEntityCircleLines(float x, float y, float radius, float thickness, UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    void drawEntityCircleLines(float x, float y, float radius, float thickness, simd_float4 color);
    
    void drawEntityLine(float x1, float y1, float x2, float y2, float thickness, UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    void drawEntityLine(float x1, float y1, float x2, float y2, float thickness, simd_float4 color);
    
    void drawEntityRect(float x, float y, float width, float height, UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    void drawEntityRect(float x, float y, float width, float height, simd_float4 color);
    
    void drawEntityRoundedRect(float x, float y, float width, float height, float cornerRadius, UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    void drawEntityRoundedRect(float x, float y, float width, float height, float cornerRadius, simd_float4 color);
    
    void drawEntityRectLines(float x, float y, float width, float height, float thickness, UInt8 r, UInt8 g, UInt8 b, UInt8 a);
    void drawEntityRectLines(float x, float y, float width, float height, float thickness, simd_float4 color);
    
    void drawText(const char* text, float posX, float posY, float fontSize, simd::float4 color);
    void buildMesh(const char* text, float posX, float posY, float fontSize, simd::float4 color, TextVertex* outVertices, int& outVertexCount);
    std::pair<float, float> measureTextBounds(const char* text, float fontSize);
};

#endif /* Renderer_hpp */
