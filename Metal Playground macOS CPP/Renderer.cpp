//
//  Renderer.cpp
//  Metal Playground macOS CPP
//
//  Created by Rayner Tan on 21/8/25.
//

// TODO: Cache all the sizeof stride sizes

#include <cassert>
#include <fstream>
#include <sstream>
#include "Renderer.hpp"
#include "ShaderTypes.h"
#include "ii_random.h"
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#include "json.hpp"
using json = nlohmann::json;

// JSON mapping
void from_json(const json& j, Bounds& b) {
    j.at("left").get_to(b.left);
    j.at("bottom").get_to(b.bottom);
    j.at("right").get_to(b.right);
    j.at("top").get_to(b.top);
}

void from_json(const json& j, Glyph& g) {
    j.at("unicode").get_to(g.unicode);
    j.at("advance").get_to(g.advance);
    
    if (j.contains("planeBounds") && !j["planeBounds"].is_null()) {
        g.planeBounds = j["planeBounds"].get<Bounds>();
    } else {
        g.planeBounds = std::nullopt;
    }
    
    if (j.contains("atlasBounds") && !j["atlasBounds"].is_null()) {
        g.atlasBounds = j["atlasBounds"].get<Bounds>();
    } else {
        g.atlasBounds = std::nullopt;
    }
}

void from_json(const json& j, Kerning& k) {
    j.at("unicode1").get_to(k.unicode1);
    j.at("unicode2").get_to(k.unicode2);
    j.at("advance").get_to(k.advance);
}

void from_json(const json& j, AtlasMetrics& a) {
    j.at("type").get_to(a.type);
    j.at("distanceRange").get_to(a.distanceRange);
    j.at("size").get_to(a.size);
    j.at("width").get_to(a.width);
    j.at("height").get_to(a.height);
    j.at("yOrigin").get_to(a.yOrigin);
}

void from_json(const json& j, FontMetrics& m) {
    j.at("emSize").get_to(m.emSize);
    j.at("lineHeight").get_to(m.lineHeight);
    j.at("ascender").get_to(m.ascender);
    j.at("descender").get_to(m.descender);
    j.at("underlineY").get_to(m.underlineY);
    j.at("underlineThickness").get_to(m.underlineThickness);
}

void from_json(const json& j, FontAtlas& f) {
    j.at("atlas").get_to(f.atlas);
    j.at("metrics").get_to(f.metrics);
    j.at("glyphs").get_to(f.glyphs);
    j.at("kerning").get_to(f.kerning);
}


// MARK: - Math Helpers
static inline simd_float4x4 makeTranslate(float tx, float ty)
{
    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[3].x = tx;
    m.columns[3].y = ty;
    return m;
}

static inline simd_float4x4 makeScale(float sx, float sy)
{
    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[0].x = sx;
    m.columns[1].y = sy;
    m.columns[2].z = 1.0f;
    return m;
}

static inline simd_float4x4 makeScale(float sXY)
{
    simd_float4x4 m = matrix_identity_float4x4;
    m.columns[0].x = sXY;
    m.columns[1].y = sXY;
    m.columns[2].z = 1.0f;
    return m;
}

static inline simd_float4x4 makeRotationZ(float angle)
{
    simd_float4x4 m = matrix_identity_float4x4;
    float c = std::cos(angle);
    float s = std::sin(angle);
    
    m.columns[0].x =  c;
    m.columns[0].y =  s;
    m.columns[1].x = -s;
    m.columns[1].y =  c;
    return m;
}

static inline simd_float4x4 pixelSpaceProjection(float screenWidth, float screenHeight)
{
    float scaleX = 2.0f / screenWidth;
    float scaleY = 2.0f / screenHeight;
    
    return simd_float4x4{
        simd_float4{ scaleX, 0.0f,   0.0f, 0.0f },
        simd_float4{ 0.0f,   scaleY, 0.0f, 0.0f },
        simd_float4{ 0.0f,   0.0f,   1.0f, 0.0f },
        simd_float4{ 0.0f,   0.0f,   0.0f, 1.0f }
    };
}



Renderer::Renderer( MTL::Device* pDevice, MTK::View* pView )
{
    // TODO: Figure out how to assert the padding and stride of the shader structs too!
    assert(sizeof(AtlasInstanceData) == 128);
    assert(sizeof(PrimitiveInstanceData) == 128);
    assert(sizeof(TextVertex) == 32);
    
    inFlightSemaphore = dispatch_semaphore_create(Renderer::maxBuffersInFlight);
    
    drawBatchesArr = new DrawBatch[drawBatchMaxCount];
    // TODO: Check but I think nextStartIndexForTypePtr and strideSizesPtr are already created via definition.
    for (int i = 0; i < drawbatchtype_count; ++i) nextStartIndexForTypePtr[i] = 0;
    for (int i = 0; i < drawbatchtype_count; ++i) strideSizesPtr[i] = 0;
    strideSizesPtr[drawbatchtype_atlas] = sizeof(AtlasInstanceData);
    strideSizesPtr[drawbatchtype_primitive] = sizeof(PrimitiveInstanceData);
    strideSizesPtr[drawbatchtype_text] = sizeof(TextVertex);

    device = pDevice->retain();
    commandQueue = device->newCommandQueue();
    
    buildAtlasBuffers();
    buildPrimitiveBuffers();
    buildTextBuffers();
    
    buildAtlasPipeline(pView->colorPixelFormat());
    buildPrimitivePipeline(pView->colorPixelFormat());
    buildTextPipeline(pView->colorPixelFormat());
    
    loadAtlasTextureAndUV();
    loadTextInfoAndTexture();
    textTempVertexBuffer = new TextVertex[textMaxSingleDrawVertCount];
}

Renderer::~Renderer()
{
    delete[] drawBatchesArr;
    drawBatchesArr = nullptr;
    device->release();
    commandQueue->release();
    
    atlasVertexBuffer->release();
    atlasTriInstanceBuffer->release();
    atlasSamplerState->release();
    atlasPipelineState->release();
    primitiveVertexBuffer->release();
    primitiveTriInstanceBuffer->release();
    primitivePipelineState->release();
    textTriVertexBuffer->release();
    textSamplerState->release();
    textPipelineState->release();
    
    mainAtlasTexture->release();
    fontTexture->release();
    delete[] textTempVertexBuffer;
    textTempVertexBuffer = nullptr;
}

void Renderer::buildAtlasBuffers()
{
    using namespace NS;
    int verticeCount = sizeof(atlasSquareVertices) / sizeof(atlasSquareVertices[0]);
    assert(verticeCount == 4);
    atlasVertexBuffer = device->newBuffer(&atlasSquareVertices, verticeCount * sizeof(AtlasVertex), MTL::ResourceStorageModeShared);
    atlasVertexBuffer->setLabel(String::string("Atlas Square Vertex Buffer", StringEncoding::UTF8StringEncoding));
    
    const int atlasTriInstanceBufferSize = sizeof(AtlasInstanceData) * atlasMaxInstanceCount * maxBuffersInFlight;
    atlasTriInstanceBuffer = device->newBuffer(atlasTriInstanceBufferSize, MTL::ResourceStorageModeShared);
    atlasTriInstanceBuffer->setLabel(String::string("Atlas Tri Instance Buffer", StringEncoding::UTF8StringEncoding));
}

void Renderer::buildPrimitiveBuffers()
{
    using namespace NS;
    int verticeCount = sizeof(primitiveSquareVertices) / sizeof(primitiveSquareVertices[0]);
    assert(verticeCount == 4);
    primitiveVertexBuffer = device->newBuffer(&primitiveSquareVertices, verticeCount * sizeof(PrimitiveVertex), MTL::ResourceStorageModeShared);
    primitiveVertexBuffer->setLabel(String::string("Primitive Square Vertex Buffer", StringEncoding::UTF8StringEncoding));
    
    const int primitiveTriInstanceBufferSize = sizeof(PrimitiveInstanceData) * primitiveMaxInstanceCount * maxBuffersInFlight;
    primitiveTriInstanceBuffer = device->newBuffer(primitiveTriInstanceBufferSize, MTL::ResourceStorageModeShared);
    primitiveTriInstanceBuffer->setLabel(String::string("Primitive Tri Instance Buffer", StringEncoding::UTF8StringEncoding));
}

void Renderer::buildTextBuffers()
{
    using namespace NS;
    const int textTriInstanceBufferSize = sizeof(TextVertex) * textMaxVertexCount * maxBuffersInFlight;
    textTriVertexBuffer = device->newBuffer(textTriInstanceBufferSize, MTL::ResourceStorageModeShared);
    textTriVertexBuffer->setLabel(String::string("Text Tri Vertex Buffer", StringEncoding::UTF8StringEncoding));
}

void Renderer::updateTriBufferStates()
{
    triBufferIndex = (triBufferIndex + 1) % maxBuffersInFlight;
    
    atlasTriInstanceBufferOffset = sizeof(AtlasInstanceData) * atlasMaxInstanceCount * triBufferIndex;
    atlasInstancesPtr = (static_cast<AtlasInstanceData*>(atlasTriInstanceBuffer->contents())) + (atlasMaxInstanceCount * triBufferIndex);
    
    primitiveTriInstanceBufferOffset = sizeof(PrimitiveInstanceData) * primitiveMaxInstanceCount * triBufferIndex;
    primitiveInstancesPtr = (static_cast<PrimitiveInstanceData*>(primitiveTriInstanceBuffer->contents())) + (primitiveMaxInstanceCount * triBufferIndex);
    
    textTriInstanceBufferOffset = sizeof(TextVertex) * textMaxVertexCount * triBufferIndex;
    textVertexBufferPtr = (static_cast<TextVertex*>(textTriVertexBuffer->contents())) + (textMaxVertexCount * triBufferIndex);
}

void Renderer::buildAtlasPipeline(MTL::PixelFormat pixelFormat)
{
    using namespace NS;
    using NS::StringEncoding::UTF8StringEncoding;
    MTL::Library* library = device->newDefaultLibrary();
    
    MTL::Function* vertFunc = library->newFunction(String::string("vertex_atlas", UTF8StringEncoding));
    MTL::Function* fragFunc = library->newFunction(String::string("fragment_atlas", UTF8StringEncoding));
    
    MTL::RenderPipelineDescriptor* pipelineDesc = MTL::RenderPipelineDescriptor::alloc()->init();
    pipelineDesc->setVertexFunction(vertFunc);
    pipelineDesc->setFragmentFunction(fragFunc);
    
    MTL::RenderPipelineColorAttachmentDescriptor* colorAttachment = pipelineDesc->colorAttachments()->object(0);
    colorAttachment->setPixelFormat(pixelFormat);
    colorAttachment->setBlendingEnabled(true);
    colorAttachment->setRgbBlendOperation(MTL::BlendOperationAdd);
    colorAttachment->setAlphaBlendOperation(MTL::BlendOperationAdd);
    colorAttachment->setSourceRGBBlendFactor(MTL::BlendFactorSourceAlpha);
    colorAttachment->setDestinationRGBBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
    colorAttachment->setSourceAlphaBlendFactor(MTL::BlendFactorSourceAlpha);
    colorAttachment->setDestinationAlphaBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
    
    MTL::VertexDescriptor* vertexDesc = MTL::VertexDescriptor::alloc()->init();
    // Position attribute
    MTL::VertexAttributeDescriptor* pPositionAttribute = vertexDesc->attributes()->object(static_cast<NS::UInteger>(AtlasVertAttrPosition));
    pPositionAttribute->setFormat(MTL::VertexFormatFloat2);
    pPositionAttribute->setOffset(0);
    pPositionAttribute->setBufferIndex(static_cast<NS::UInteger>(BufferIndexVertices));

    // UV attribute
    MTL::VertexAttributeDescriptor* pUVAttribute = vertexDesc->attributes()->object(static_cast<NS::UInteger>(AtlasVertAttrUV));
    pUVAttribute->setFormat(MTL::VertexFormatFloat2);
    pUVAttribute->setOffset(offsetof(AtlasVertex, uv));
    pUVAttribute->setBufferIndex(static_cast<NS::UInteger>(BufferIndexVertices));

    // Layouts
    MTL::VertexBufferLayoutDescriptor* pLayout = vertexDesc->layouts()->object(0);
    pLayout->setStride(sizeof(AtlasVertex));
    pLayout->setStepFunction(MTL::VertexStepFunctionPerVertex);
    pipelineDesc->setVertexDescriptor(vertexDesc);
    
    NS::Error* err = nullptr;
    atlasPipelineState = device->newRenderPipelineState(pipelineDesc, &err);
    if (!atlasPipelineState) {
        __builtin_printf("%s", err->localizedDescription()->utf8String());
        assert(false);
    }
    
    MTL::SamplerDescriptor* sampleDesc = MTL::SamplerDescriptor::alloc()->init();
    sampleDesc->setMinFilter(MTL::SamplerMinMagFilterLinear);
    sampleDesc->setMagFilter(MTL::SamplerMinMagFilterNearest); // NOTE: linear can cause some bleeding from neighbouring edges in atlas.
    sampleDesc->setMipFilter(MTL::SamplerMipFilterLinear);
    atlasSamplerState = device->newSamplerState(sampleDesc);
    assert(atlasSamplerState);
    
    
    sampleDesc->release();
    vertexDesc->release();
    pipelineDesc->release();
    library->release();
    fragFunc->release();
    vertFunc->release();
}

void Renderer::buildPrimitivePipeline(MTL::PixelFormat pixelFormat)
{
    using namespace NS;
    using NS::StringEncoding::UTF8StringEncoding;
    MTL::Library* library = device->newDefaultLibrary();
    
    MTL::Function* vertFunc = library->newFunction(String::string("vertex_primitive", UTF8StringEncoding));
    MTL::Function* fragFunc = library->newFunction(String::string("fragment_primitive", UTF8StringEncoding));
    
    MTL::RenderPipelineDescriptor* pipelineDesc = MTL::RenderPipelineDescriptor::alloc()->init();
    pipelineDesc->setVertexFunction(vertFunc);
    pipelineDesc->setFragmentFunction(fragFunc);

    MTL::RenderPipelineColorAttachmentDescriptor* colorAttachment = pipelineDesc->colorAttachments()->object(0);
    colorAttachment->setPixelFormat(pixelFormat);
    colorAttachment->setBlendingEnabled(true);
    colorAttachment->setRgbBlendOperation(MTL::BlendOperationAdd);
    colorAttachment->setAlphaBlendOperation(MTL::BlendOperationAdd);
    colorAttachment->setSourceRGBBlendFactor(MTL::BlendFactorSourceAlpha);
    colorAttachment->setDestinationRGBBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
    colorAttachment->setSourceAlphaBlendFactor(MTL::BlendFactorSourceAlpha);
    colorAttachment->setDestinationAlphaBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
    
    NS::Error* err = nullptr;
    primitivePipelineState = device->newRenderPipelineState(pipelineDesc, &err);
    if (!primitivePipelineState) {
        __builtin_printf("%s", err->localizedDescription()->utf8String());
        assert(false);
    }
    
    pipelineDesc->release();
    library->release();
    fragFunc->release();
    vertFunc->release();
}

void Renderer::buildTextPipeline(MTL::PixelFormat pixelFormat)
{
    using namespace NS;
    using NS::StringEncoding::UTF8StringEncoding;
    MTL::Library* library = device->newDefaultLibrary();
    
    MTL::Function* vertFunc = library->newFunction(String::string("vertex_text", UTF8StringEncoding));
    MTL::Function* fragFunc = library->newFunction(String::string("fragment_text", UTF8StringEncoding));
    
    MTL::RenderPipelineDescriptor* pipelineDesc = MTL::RenderPipelineDescriptor::alloc()->init();
    pipelineDesc->setVertexFunction(vertFunc);
    pipelineDesc->setFragmentFunction(fragFunc);
    
    MTL::RenderPipelineColorAttachmentDescriptor* colorAttachment = pipelineDesc->colorAttachments()->object(0);
    colorAttachment->setPixelFormat(pixelFormat);
    colorAttachment->setBlendingEnabled(true);
    colorAttachment->setRgbBlendOperation(MTL::BlendOperationAdd);
    colorAttachment->setAlphaBlendOperation(MTL::BlendOperationAdd);
    colorAttachment->setSourceRGBBlendFactor(MTL::BlendFactorSourceAlpha);
    colorAttachment->setDestinationRGBBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
    colorAttachment->setSourceAlphaBlendFactor(MTL::BlendFactorSourceAlpha);
    colorAttachment->setDestinationAlphaBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
    
    
    MTL::VertexDescriptor* vertexDesc = MTL::VertexDescriptor::alloc()->init();
    // Position attribute
    MTL::VertexAttributeDescriptor* pPositionAttribute = vertexDesc->attributes()->object(static_cast<NS::UInteger>(TextVertAttrPosition));
    pPositionAttribute->setFormat(MTL::VertexFormatFloat2);
    pPositionAttribute->setOffset(0);
    pPositionAttribute->setBufferIndex(static_cast<NS::UInteger>(TextBufferIndexVertices));
    
    // UV attribute
    MTL::VertexAttributeDescriptor* pUVAttribute = vertexDesc->attributes()->object(static_cast<NS::UInteger>(TextVertAttrUV));
    pUVAttribute->setFormat(MTL::VertexFormatFloat2);
    pUVAttribute->setOffset(offsetof(TextVertex, uv));
    pUVAttribute->setBufferIndex(static_cast<NS::UInteger>(TextBufferIndexVertices));
    
    // Color Attribute
    MTL::VertexAttributeDescriptor* pColorAttribute = vertexDesc->attributes()->object(static_cast<NS::UInteger>(TextVertAttrTextColor));
    pColorAttribute->setFormat(MTL::VertexFormatFloat4);
    pColorAttribute->setOffset(offsetof(TextVertex, textColor));
    pColorAttribute->setBufferIndex(static_cast<NS::UInteger>(TextBufferIndexVertices));
    
    // Layouts
    MTL::VertexBufferLayoutDescriptor* pLayout = vertexDesc->layouts()->object(0);
    pLayout->setStride(sizeof(TextVertex));
    pLayout->setStepFunction(MTL::VertexStepFunctionPerVertex);
    pipelineDesc->setVertexDescriptor(vertexDesc);
    
    NS::Error* err = nullptr;
    textPipelineState = device->newRenderPipelineState(pipelineDesc, &err);
    if (!textPipelineState) {
        __builtin_printf("%s", err->localizedDescription()->utf8String());
        assert(false);
    }
    
    MTL::SamplerDescriptor* sampleDesc = MTL::SamplerDescriptor::alloc()->init();
    sampleDesc->setMinFilter(MTL::SamplerMinMagFilterLinear);
    sampleDesc->setMagFilter(MTL::SamplerMinMagFilterLinear);
    sampleDesc->setMipFilter(MTL::SamplerMipFilterLinear);
    textSamplerState = device->newSamplerState(sampleDesc);
    assert(textSamplerState);
    
    
    sampleDesc->release();
    vertexDesc->release();
    pipelineDesc->release();
    library->release();
    fragFunc->release();
    vertFunc->release();
}

static std::string formatResourceURL(std::string filename, std::string extension)
{
    using namespace std;
    string result;
    
    CFStringRef cf_filename = CFStringCreateWithCString(kCFAllocatorDefault, filename.c_str(), kCFStringEncodingUTF8);
    CFStringRef cf_ext = CFStringCreateWithCString(kCFAllocatorDefault, extension.c_str(), kCFStringEncodingUTF8);
    CFURLRef cf_rscUrl = CFBundleCopyResourceURL(CFBundleGetMainBundle(), cf_filename, cf_ext, nullptr);
    
    CFStringRef path = CFURLCopyFileSystemPath(cf_rscUrl, kCFURLPOSIXPathStyle);
    assert(path);
    
    const char* cPath = CFStringGetCStringPtr(path, kCFStringEncodingUTF8);
    
    if (cPath) {
        result = string(cPath);
    } else {
        // Fallback
        CFIndex length = CFStringGetLength(path);
        CFIndex maxSize = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
        char* buffer = new char[maxSize];
        if (CFStringGetCString(path, buffer, maxSize, kCFStringEncodingUTF8)) {
            result = string(buffer);
        }
        delete[] buffer;
    }
    
    // TODO: Check all the mem releases!
    CFRelease(path);
    CFRelease(cf_rscUrl);
    CFRelease(cf_ext);
    CFRelease(cf_filename);
    
    return result;
}

static MTL::Texture* loadTexture(int width, int height, std::string imageUrl, MTL::Device* device, bool hasAlpha)
{
    MTL::Texture* resultTexture;
    MTL::TextureDescriptor* textureDesc = MTL::TextureDescriptor::alloc()->init();
    
    textureDesc->setWidth(width);
    textureDesc->setHeight(height);
    textureDesc->setPixelFormat( MTL::PixelFormatRGBA8Unorm );
    textureDesc->setTextureType( MTL::TextureType2D );
    textureDesc->setStorageMode( MTL::StorageModeShared );
    textureDesc->setUsage( MTL::ResourceUsageSample | MTL::ResourceUsageRead );
    
    resultTexture = device->newTexture(textureDesc);
    int numChannels = 4;
    if (!hasAlpha) numChannels = 3;
    unsigned char* imageData = stbi_load(imageUrl.c_str(), &width, &height, &numChannels, 4); // NOTE: Force to always return 4 channels
    if (imageData) {
        resultTexture->replaceRegion( MTL::Region( 0, 0, 0, width, height, 1 ), 0, (uint8_t*)imageData, width * 4 );
        stbi_image_free(imageData);
    }
    textureDesc->release();
    return resultTexture;
}

void Renderer::loadAtlasTextureAndUV()
{
    using namespace std;
    
    int mainAtlasTWidth = 256;
    int mainAtlasTHeight = 256;
    
    string imageFileUrl = formatResourceURL("main_atlas", "png");
    string uvFileUrl = formatResourceURL("main_atlas", "txt");
    
    // Load the Texture data
    mainAtlasTexture = loadTexture(mainAtlasTWidth, mainAtlasTHeight, imageFileUrl, device, true);
    
    { // Load the UV data
        ifstream file(uvFileUrl);
        assert(file.is_open());
        string line;
        
        // Skip the first line (count line)
        getline(file, line);
        while (std::getline(file, line)) {
            if (line.empty()) continue;
            
            std::istringstream iss(line);
            std::string name;
            float x, y, w, h;
            
            if (iss >> name >> x >> y >> w >> h) {
                simd::float2 minUV = {x / mainAtlasTWidth, y / mainAtlasTHeight};
                simd::float2 maxUV = {(x + w) / mainAtlasTWidth, (y + h) / mainAtlasTHeight};
                
                mainAtlasUVRects[name] = {minUV, maxUV};
                __builtin_printf("name: %s, (%0.f, %0.f), w:%0.f, h%0.f\n", name.c_str(), x, y, w, h);
            }
        }
        file.close();
    }
}

void Renderer::loadTextInfoAndTexture()
{
    using namespace std;
    
    int fontTextureWidth = 792;
    int fontTextureHeight = 792;

    string fontName = "roboto";
    string fontImageUrl = formatResourceURL(fontName, "png");
    string fontJsonUrl = formatResourceURL(fontName, "json");

    // Load the Texture data
    fontTexture = loadTexture(fontTextureWidth, fontTextureHeight, fontImageUrl, device, false);
 
    { // Load JSON file
        ifstream file(fontJsonUrl);
        assert(file.is_open());
        
        json j;
        file >> j;
        fontAtlas = j.get<FontAtlas>();
        
        file.close();
        
        for (const auto& glyph : fontAtlas.glyphs) {
            fontGlyphs[(uint32_t)glyph.unicode] = glyph;
        }
        
        for (const auto& kern : fontAtlas.kerning) {
            uint64_t key = ((uint64_t)kern.unicode1 << 32) | (uint64_t)kern.unicode2;
            fontKerning[key] = kern;
        }
    }
}

void Renderer::testDrawPrimitives() {
    const int circleCount = 100000;
    RNG rng = {U32(time * 1000000)};
    simd_float4 color = {};
    
    for (int iCircle = 0; iCircle < circleCount; ++iCircle) {
        const float x = RandomRangeF32(&rng, -screenSize.width, screenSize.width);
        const float y = RandomRangeF32(&rng, -screenSize.height, screenSize.height);
        const float radius = RandomRangeF32(&rng, 5, 25);
        
        color.x = RandomF01(&rng);
        color.y = RandomF01(&rng);
        color.z = RandomF01(&rng);
        color.w = 1.0;
        
        drawPrimitiveCircle(x, y, radius, color);
    }
    
//    drawPrimitiveCircle(0, 0, 50, 0, 255, 255, 255);
//    drawPrimitiveCircle(0, 0, 800.0, 255, 255, 255, 64);
//    drawPrimitiveCircle(0, 0, 512.0, 0, 255, 255, 64);
//    drawPrimitiveCircle(0, 0, 256.0, 255, 0, 255, 64);
//    drawPrimitiveCircle(256, 256, 128.0, 255, 0, 0, 64);
//    drawPrimitiveCircle(0, 0, 128.0, 0, 255, 0, 64);
//    drawPrimitiveCircle(-256, -256, 128.0, 0, 0, 255, 64);
//    drawPrimitiveLine(-800, -600, 800, 600, 10, 200, 100, 0, 128);
//    drawPrimitiveRectLines(0, 0, 800, 600, 48, 0, 255, 255, 255);
//    drawPrimitiveRect(0, 0, 800, 600, 255, 0, 0, 64);
//    drawPrimitiveRect(-800, -600, 800, 600, 255, 0, 0, 64);
//    drawPrimitiveRect(0, 0, 24, 600, 255, 0, 0, 64);
//    drawPrimitiveRect(0, 0, 128, 196, 0, 255, 0, 128);
//    drawPrimitiveRect(-800, -600, 800, 600, 128, 255, 0, 128);
//    drawPrimitiveRect(-800, -600, 1600, 1200, 0, 255, 255, 32);
//    drawPrimitiveRoundedRect(0, 0, 800, 600, 100, 0, 0, 255, 255);
//    drawPrimitiveRoundedRect(0, 0, 800, 100, 100, 0, 255, 255, 255);
//    drawPrimitiveCircle(100, 100, 100, 255, 0, 0, 128);
//    drawPrimitiveRect(-600, -600, 1200, 1200, 255, 0, 255, 255);
//    drawPrimitiveCircle(0, 0, 600, 255, 255, 255, 255);
//    drawPrimitiveCircleLines(0, 0, 600, 48, 255, 0, 255, 128);
//    drawPrimitiveRect(-600, -600, 48, 1200, 0, 255, 0, 128);

}

void Renderer::testDrawAtlasSprites()
{
    const int testMaxCount = 100;
    const int testCount = MIN
    ((int)((sin(time * 2.0f) + 1.0f) / 2.0f * testMaxCount),
     atlasMaxInstanceCount - 1);
    
    simd_float4 color;
    for (int i = 0; i < testCount; ++i) {
        const float angle = time + ((float)i) * (2.0f * M_PI / ((float)testCount));
        const float radius = ((float)screenSize.width) / 3.0f;
        color.x = 0.5f + 0.5f * sin(angle);
        color.y = 0.5f + 0.5f * cos(angle);
        color.z = 0.5f + 0.5f * sin(angle * 0.5f);
        color.w = 1.0f;
        
        drawSprite("Circle_White", cos(angle) * radius, sin(angle) * radius, 100.0f + 100.0f * sin(angle), 100.0f + 100.0f * sin(angle), color, angle * 2);
    }
    
    { // Test anything static here, adds to last insance count
        const char* spriteName = "player_1";
        drawSprite(spriteName, 100, 100, 256, 256, colorFromBytes(255, 255, 255, 255), 0.0f);
    }
}

void Renderer::testDrawTextWithBounds()
{
    const float fontSize = 96.0f;
    
    // Generate timestamp as string
    std::time_t now = std::time(nullptr);
    char timeBuffer[32];
    std::snprintf(timeBuffer, sizeof(timeBuffer), "%ld", now);
    
    // Build text with multiple lines: "Hello, SDF\nWorld!\n\n<timestamp>"
    char text[256];
    std::snprintf(text, sizeof(text), "Hello, SDF\nWorld!\n\n%s", timeBuffer);
    
    // Measure text bounds
    auto bounds = measureTextBounds(text, fontSize); // returns std::pair<float, float>
    float textWidth  = bounds.first;
    float textHeight = bounds.second;
    
    // Draw a circle at the top-left of the text bounds
    simd::float4 white = {1.0f, 1.0f, 1.0f, 1.0f};
    drawPrimitiveCircle(-textWidth / 2.0f,
                        textHeight / 2.0f,
                        16.0f,
                        white);
        
    // Draw a rectangle behind the text to visualize bounds
    drawPrimitiveRect(-textWidth / 2.0f,
                      -textHeight / 2.0f,
                      textWidth,
                      textHeight,
                      simd::float4{0.0f, 1.0f, 1.0f, 0.25f} // semi-transparent cyan
                      );
    
    // Draw the main multi-line text
    simd::float4 yellow = {0.9f, 0.9f, 0.1f, 1.0f};
    drawText(
             text,
             -textWidth / 2.0f,
             textHeight / 2.0f,
             fontSize,
             yellow
             );
    
    // Draw another text at fixed offset
    simd::float4 purple = {0.3f, 0.2f, 0.7f, 1.0f};
    drawText("HELLO       AGAIN!!!",
             20.0f - screenSize.width / 2.0f,
             -20.0f + screenSize.height / 2.0f,
             48.0f,
             purple
             );
}

void Renderer::testDrawInterleavedTypes()
{
    // Waves and circle positions
    float wave1   = std::sin(time * 1.5f) * 300.0f;
    float wave2   = std::cos(time * 0.8f) * 200.0f;
    float wave3   = std::sin(time * 3.2f) * 100.0f;
    float circleX = std::sin(time * 2.0f) * 256.0f;
    float circleY = std::cos(time * 1.0f) * 128.0f;

    // Draw first sprite
    drawSprite(
        "player_2",
        wave1,
        wave2,
        256.0f + wave3,
        256.0f + wave3,
        simd::float4{1.0f, 1.0f, 1.0f, 1.0f},
        0.0f
    );

    // Draw moving circle
    drawPrimitiveCircle(
        circleX,
        circleY,
        128.0f + std::sin(time * 4.0f) * 64.0f,
        simd::float4{1.0f, 0.3f, 0.5f, 1.0f}
    );

    // Draw mirrored sprite
    drawSprite(
        "player_2",
        -circleX,
        -circleY,
        128.0f,
        128.0f,
        simd::float4{1.0f, 1.0f, 1.0f, 1.0f},
        0.0f
    );

    // Dynamic text Y offset
    float textYOffset = std::sin(time * 1.2f) * 40.0f;

    // Draw first dynamic text
    drawText(
        "Dynamic Text\nis Alive!",
        -200.0f,
        300.0f + textYOffset,
        64.0f + std::sin(time * 2.5f) * 8.0f,
        simd::float4{1.0f, 0.8f, 0.2f, 1.0f}
    );

    // Draw static text
    drawText(
        "Another Test",
        -150.0f,
        -50.0f,
        48.0f,
        simd::float4{1.0f, 0.0f, 1.0f, 1.0f}
    );

    // Scroll offset for moving text block
    float scrollOffset = std::sin(time * 0.5f) * 150.0f;

    // Draw first scrolling text block
    drawText(
        "This is a much\nLonger test of a block\nOf text here and there\nAnother line here\nAnother line there\n  Here's one with 2 spaces before",
        -600.0f + scrollOffset,
        600.0f,
        96.0f,
        simd::float4{0.1f, 1.0f, 0.5f, 1.0f}
    );

    // Another moving circle
    drawPrimitiveCircle(
        std::sin(time * 0.7f) * 600.0f,
        std::cos(time * 0.9f) * 500.0f,
        64.0f,
        simd::float4{0.0f, 0.5f, 0.5f, 1.0f}
    );

    // Draw mirrored scrolling text block
    drawText(
        "This is a much\nLonger test of a block\nOf text here and there\nAnother line here\nAnother line there\n  Here's one with 2 spaces before",
        -900.0f - scrollOffset,
        100.0f,
        96.0f,
        simd::float4{0.1f, 1.0f, 0.5f, 1.0f}
    );
}

void Renderer::draw( MTK::View* pView )
{
    NS::AutoreleasePool* pPool = NS::AutoreleasePool::alloc()->init();
    
    dispatch_semaphore_wait(inFlightSemaphore, DISPATCH_TIME_FOREVER);
    MTL::CommandBuffer* cmdBuffer = commandQueue->commandBuffer();
    if (cmdBuffer) {
        cmdBuffer->addCompletedHandler(^void(MTL::CommandBuffer* completedBuffer) {
            dispatch_semaphore_signal(inFlightSemaphore);
        });
        
        updateTriBufferStates();
        drawBatchCount = 0;
        for (int iBatchType = 0; iBatchType < drawbatchtype_count; ++iBatchType) { nextStartIndexForTypePtr[iBatchType] = 0; }
        curDrawBatchType = drawbatchtype_none;
        atlasInstanceCount = 0;
        primitiveInstanceCount = 0;
        textVertexCount = 0;
        
        time += 1.0 / pView->preferredFramesPerSecond();
        testDrawPrimitives();
        testDrawAtlasSprites();
        testDrawTextWithBounds();
        testDrawInterleavedTypes();

        MTL::RenderPassDescriptor* renderPassDesc = pView->currentRenderPassDescriptor();
        MTL::RenderCommandEncoder* encoder = cmdBuffer->renderCommandEncoder(renderPassDesc);
        if (renderPassDesc && encoder) {
            encoder->setLabel(NS::String::string("Primary Render Encoder", NS::StringEncoding::UTF8StringEncoding));
            
            for (int iBatch = 0; iBatch < drawBatchCount; ++iBatch) {
                const DrawBatch batch = drawBatchesArr[iBatch];
                assert(batch.count > 0);
                assert(batch.startIndex >= 0);
                switch (batch.type) {
                    case drawbatchtype_count: {
                        __builtin_printf("Draw Batch with type count, should never be implemented");
                        assert(false);
                    } break;
                    case drawbatchtype_none: {
                        __builtin_printf("Draw Batch with type none");
                        assert(false);
                    } break;
                    case drawbatchtype_atlas: {
                        encoder->setRenderPipelineState(atlasPipelineState);
                        encoder->setVertexBuffer(atlasVertexBuffer, 0, BufferIndexVertices);
                        
                        encoder->setVertexBuffer(atlasTriInstanceBuffer, atlasTriInstanceBufferOffset + (sizeof(AtlasInstanceData) * batch.startIndex), BufferIndexInstances);
                        
                        encoder->setFragmentTexture(mainAtlasTexture, 0);
                        encoder->setFragmentSamplerState(atlasSamplerState, 0);
                        encoder->drawPrimitives(MTL::PrimitiveTypeTriangleStrip, 0, sizeof(atlasSquareVertices) / sizeof(atlasSquareVertices[0]), batch.count);
                    } break;
                    case drawbatchtype_primitive: {
                        encoder->setRenderPipelineState(primitivePipelineState);
                        encoder->setVertexBuffer(primitiveVertexBuffer, 0, BufferIndexVertices);
                        
                        encoder->setVertexBuffer(primitiveTriInstanceBuffer, primitiveTriInstanceBufferOffset + (sizeof(PrimitiveInstanceData) * batch.startIndex), BufferIndexInstances);
                        
                        encoder->setVertexBytes(&primitiveUniforms, sizeof(primitiveUniforms), BufferIndexUniforms);
                        encoder->drawPrimitives(MTL::PrimitiveTypeTriangleStrip, 0, sizeof(primitiveSquareVertices) / sizeof(primitiveSquareVertices[0]), batch.count);
                    } break;
                    case drawbatchtype_text: {
                        encoder->setRenderPipelineState(textPipelineState);
                        encoder->setVertexBuffer(textTriVertexBuffer, textTriInstanceBufferOffset + (sizeof(TextVertex) * batch.startIndex), TextBufferIndexVertices);
                        
                        simd_float4x4 bindableProjMatrix = projectionMatrix;
                        encoder->setVertexBytes(&bindableProjMatrix, sizeof(simd_float4x4), TextBufferIndexProjectionMatrix);
                        
                        TextFragmentUniforms uniforms = (TextFragmentUniforms){
                            .distanceRange = static_cast<float>(fontAtlas.atlas.distanceRange)
                        };
                        encoder->setFragmentBytes(&uniforms, sizeof(TextFragmentUniforms), 0);
                        encoder->setFragmentTexture(fontTexture, 0);
                        encoder->setFragmentSamplerState(textSamplerState, 0);
                        
                        encoder->drawPrimitives(MTL::PrimitiveType::PrimitiveTypeTriangle, static_cast<NS::UInteger>(0), static_cast<NS::UInteger>(batch.count));
                    } break;
                }
            }
            
            encoder->endEncoding();
            if (pView->currentDrawable()) {
                cmdBuffer->presentDrawable(pView->currentDrawable());
                
                // TODO: The Render Frame Count debugging stuff
            }
        }
        
        cmdBuffer->commit();
    }
    
    pPool->release();
}

void Renderer::drawableSizeWillChange( MTK::View* pView, CGSize size )
{
    __builtin_printf("drawableSizeWillChange called, (%0.f, %0.f)\n", size.width, size.height);
    screenSize = size;
    projectionMatrix = pixelSpaceProjection((float)size.width, (float)size.height);
    primitiveUniforms = (PrimitiveUniforms){projectionMatrix};
}

inline simd_float4 Renderer::colorFromBytes(UInt8 r, UInt8 g, UInt8 b, UInt8 a) {
    const float scale = 1.0 / 255.0;
    return {
        (float)r * scale,
        (float)g * scale,
        (float)b * scale,
        (float)a * scale,
    };
}

inline int Renderer::addToDrawBatchAndGetAdjustedIndex(DrawBatchType type, int increment) {
    int nextStartIndex = nextStartIndexForTypePtr[type];
    const int batchIndex = drawBatchCount;
    const DrawBatchType curType = curDrawBatchType;
    
    // Fast path: return early
    if (curType == type) {
        drawBatchesArr[batchIndex - 1].count += increment;
        nextStartIndexForTypePtr[type] = nextStartIndex + increment;
        return nextStartIndex;
    }
    
    // Infrequent path: Switching types
    const int alignmentSize = 256;
    const int alignmentCount = alignmentSize / strideSizesPtr[type];
    const int misalignment = nextStartIndex % alignmentCount;
    
    if (misalignment != 0) {
        nextStartIndex += alignmentCount - misalignment;
    }
    
    assert(type == drawbatchtype_atlas ? (nextStartIndex + increment) < atlasMaxInstanceCount : true);
    assert(type == drawbatchtype_primitive ? (nextStartIndex + increment) < primitiveMaxInstanceCount : true);
    //    assert(type == drawbatchtype_text ? (nextStartIndex + increment) < textMaxVertexCount : true);
    
    curDrawBatchType = type;
    drawBatchesArr[batchIndex] = (DrawBatch){
        .type = type,
        .startIndex = nextStartIndex,
        .count = increment
    };
    drawBatchCount += 1;
    
    nextStartIndexForTypePtr[type] = nextStartIndex + increment;
    return nextStartIndex;
}

// MARK: - Atlas Drawing Functions
void Renderer::drawSprite(const char* spriteName, float x, float y, float width, float height, UInt8 r, UInt8 g, UInt8 b, UInt8 a, float rotationRadians)
{
    drawSprite(spriteName, x, y, width, height, colorFromBytes(r, g, b, a), rotationRadians);
}
void Renderer::drawSprite(const char* spriteName, float x, float y, float width, float height, simd_float4 color, float rotationRadians)
{
    const int index = addToDrawBatchAndGetAdjustedIndex(drawbatchtype_atlas, 1);
    atlasInstancesPtr[index] = (AtlasInstanceData){
        .transform =
        simd_mul(projectionMatrix,
                 simd_mul(makeTranslate(x, y),
                          simd_mul(makeRotationZ(rotationRadians),
                                   makeScale(width, height)))),
        .color = color,
        .uvMin = mainAtlasUVRects[spriteName].minUV,
        .uvMax = mainAtlasUVRects[spriteName].maxUV
    };
    ++atlasInstanceCount;
}


// MARK: - Primitive Drawing Functions
void Renderer::drawPrimitiveCircle(float x, float y, float radius,
                             UInt8 r, UInt8 g, UInt8 b, UInt8 a)
{
    drawPrimitiveCircle(x, y, radius, colorFromBytes(r, g, b, a));
}
void Renderer::drawPrimitiveCircle(float x, float y, float radius, simd_float4 color)
{
    const int index = addToDrawBatchAndGetAdjustedIndex(drawbatchtype_primitive, 1);
    primitiveInstancesPtr[index] = (PrimitiveInstanceData){
        .transform = simd_mul(makeTranslate(x, y), makeScale(radius * 2)),
        .color = color,
        .shapeType = ShapeTypeCircle,
        .sdfParams = (simd_float4){radius, 0.5f, 0.0f, 0.0f} // hardcode edge softness to 0.5
    };
    ++primitiveInstanceCount;
}

void Renderer::drawPrimitiveCircleLines(float x, float y, float radius, float thickness, UInt8 r, UInt8 g, UInt8 b, UInt8 a)
{
    drawPrimitiveCircleLines(x, y, radius, thickness, colorFromBytes(r, g, b, a));
}
void Renderer::drawPrimitiveCircleLines(float x, float y, float radius, float thickness, simd_float4 color)
{
    const int index = addToDrawBatchAndGetAdjustedIndex(drawbatchtype_primitive, 1);
    primitiveInstancesPtr[index] = (PrimitiveInstanceData){
        .transform = simd_mul(makeTranslate(x, y), makeScale(radius * 2)),
        .color = color,
        .shapeType = ShapeTypeCircleLines,
        .sdfParams = (simd_float4){radius, 0.5f, thickness / 2.0f, 0.0f}
    };
    ++primitiveInstanceCount;
}
    
void Renderer::drawPrimitiveLine(float x1, float y1, float x2, float y2, float thickness, UInt8 r, UInt8 g, UInt8 b, UInt8 a)
{
    drawPrimitiveLine(x1, y1, x2, y2, thickness, colorFromBytes(r, g, b, a));
}
void Renderer::drawPrimitiveLine(float x1, float y1, float x2, float y2, float thickness, simd_float4 color)
{
    const float dx = x2 - x1;
    const float dy = y2 - y1;
    const float length = sqrt(dx * dx + dy * dy);
    const float angle = atan2(dy, dx);
    
    // Center between endpoints
    const float cx = (x1 + x2) * 0.5f;
    const float cy = (y1 + y2) * 0.5f;
    
    // Build transform: scale -> rotate -> translate
    // Multiple: translate * rotation * scale
    const simd_float4x4 transform = simd_mul(makeTranslate(cx, cy), simd_mul(makeRotationZ(angle), makeScale(length, thickness)));
    
    const int index = addToDrawBatchAndGetAdjustedIndex(drawbatchtype_primitive, 1);
    primitiveInstancesPtr[index] = (PrimitiveInstanceData){
        .transform = transform,
        .color = color,
        .shapeType = ShapeTypeRect,
        .sdfParams = (simd_float4){0.0f, 0.0f, 0.0f, 0.0f}
    };
    ++primitiveInstanceCount;
}
    
void Renderer::drawPrimitiveRect(float x, float y, float width, float height, UInt8 r, UInt8 g, UInt8 b, UInt8 a)
{
    drawPrimitiveRect(x, y, width, height, colorFromBytes(r, g, b, a));
}
void Renderer::drawPrimitiveRect(float x, float y, float width, float height, simd_float4 color)
{
    const int index = addToDrawBatchAndGetAdjustedIndex(drawbatchtype_primitive, 1);
    primitiveInstancesPtr[index] = (PrimitiveInstanceData){
        .transform = simd_mul(makeTranslate(x + (width / 2.0f), y + (height / 2.0f)), makeScale(width, height)),
        .color = color,
        .shapeType = ShapeTypeRect,
        .sdfParams = (simd_float4){0.0f, 0.0f, 0.0f, 0.0f}
    };
    ++primitiveInstanceCount;
}

void Renderer::drawPrimitiveRoundedRect(float x, float y, float width, float height, float cornerRadius, UInt8 r, UInt8 g, UInt8 b, UInt8 a)
{
    drawPrimitiveRoundedRect(x, y, width, height, cornerRadius, colorFromBytes(r, g, b, a));
}
void Renderer::drawPrimitiveRoundedRect(float x, float y, float width, float height, float cornerRadius, simd_float4 color)
{
    const float halfWidth = width / 2.0f;
    const float halfHeight = height / 2.0f;
    
    const int index = addToDrawBatchAndGetAdjustedIndex(drawbatchtype_primitive, 1);
    primitiveInstancesPtr[index] = (PrimitiveInstanceData){
        .transform = simd_mul(makeTranslate(x + halfWidth, y + halfHeight), makeScale(width, height)),
        .color = color,
        .shapeType = ShapeTypeRoundedRect,
        .sdfParams = (simd_float4){halfWidth, halfHeight, cornerRadius, 0.0f}
    };
    ++primitiveInstanceCount;
}

void Renderer::drawPrimitiveRectLines(float x, float y, float width, float height, float thickness, UInt8 r, UInt8 g, UInt8 b, UInt8 a)
{
    drawPrimitiveRectLines(x, y, width, height, thickness, colorFromBytes(r, g, b, a));
}
void Renderer::drawPrimitiveRectLines(float x, float y, float width, float height, float thickness, simd_float4 color)
{
    const float halfWidth = width / 2.0f;
    const float halfHeight = height / 2.0f;
    
    const int index = addToDrawBatchAndGetAdjustedIndex(drawbatchtype_primitive, 1);
    primitiveInstancesPtr[index] = (PrimitiveInstanceData){
        .transform = simd_mul(makeTranslate(x + halfWidth, y + halfHeight), makeScale(width, height)),
        .color = color,
        .shapeType = ShapeTypeRectLines,
        .sdfParams = (simd_float4){halfWidth, halfHeight, thickness, 0.0f}
    };
    ++primitiveInstanceCount;
}

void Renderer::drawText(const char* text,
                        float posX, float posY,
                        float fontSize,
                        simd::float4 color)
{
    if (!text || text[0] == '\0') return;
    
    const int predictedMaxVertices = (int)strlen(text) * 6;
    assert(predictedMaxVertices <= textMaxSingleDrawVertCount);
    
    int vertexCount = 0;
    buildMesh(text, posX, posY, fontSize, color,
              textTempVertexBuffer,
              vertexCount);
    
    assert(vertexCount > 0);

    int startIndex = addToDrawBatchAndGetAdjustedIndex(drawbatchtype_text, vertexCount);
    memcpy(textVertexBufferPtr + startIndex, textTempVertexBuffer, sizeof(TextVertex) * vertexCount);
    textVertexCount += vertexCount;
}


void Renderer::buildMesh(const char* text,
                         float posX, float posY,
                         float fontSize,
                         simd::float4 color,
                         TextVertex* outVertices,
                         int& outVertexCount)
{
    outVertexCount = 0;

    float atlasWidth  = static_cast<float>(fontAtlas.atlas.width);
    float atlasHeight = static_cast<float>(fontAtlas.atlas.height);

    float scale      = fontSize / static_cast<float>(fontAtlas.metrics.emSize);
    float lineHeight = static_cast<float>(fontAtlas.metrics.lineHeight) * scale;
    float ascender   = static_cast<float>(fontAtlas.metrics.ascender) * scale;

    float cursorX = posX;
    float cursorY = posY - ascender;
    uint32_t previousChar = 0;

    for (const char* p = text; *p; ++p) {
        uint32_t unicode = static_cast<unsigned char>(*p); // ensures 0-255
        if (unicode > 127) continue; // skip non-ASCII


        if (unicode == '\n') {
            cursorX = posX;
            cursorY -= lineHeight;
            previousChar = 0;
            continue;
        }

        // Kerning
        if (previousChar != 0) {
            uint64_t key = (static_cast<uint64_t>(previousChar) << 32) | unicode;
            auto it = fontKerning.find(key);
            if (it != fontKerning.end()) {
                cursorX += static_cast<float>(it->second.advance) * scale;
            }
        }

        auto gIt = fontGlyphs.find(unicode);
        if (gIt == fontGlyphs.end()) {
            previousChar = unicode;
            continue;
        }
        const Glyph& glyph = gIt->second;

        if (glyph.planeBounds && glyph.atlasBounds) {
            const Bounds& plane = *glyph.planeBounds;
            const Bounds& atlas = *glyph.atlasBounds;

            float x0 = cursorX + static_cast<float>(plane.left) * scale;
            float y0 = cursorY + static_cast<float>(plane.bottom) * scale;
            float x1 = cursorX + static_cast<float>(plane.right) * scale;
            float y1 = cursorY + static_cast<float>(plane.top) * scale;

            float u0 = static_cast<float>(atlas.left) / atlasWidth;
            float u1 = static_cast<float>(atlas.right) / atlasWidth;
            float v0 = (atlasHeight - static_cast<float>(atlas.top)) / atlasHeight;
            float v1 = (atlasHeight - static_cast<float>(atlas.bottom)) / atlasHeight;

            TextVertex topLeft     {{x0, y1}, {u0, v0}, color};
            TextVertex topRight    {{x1, y1}, {u1, v0}, color};
            TextVertex bottomLeft  {{x0, y0}, {u0, v1}, color};
            TextVertex bottomRight {{x1, y0}, {u1, v1}, color};

            // Two triangles = 6 vertices
            outVertices[outVertexCount++] = bottomLeft;
            outVertices[outVertexCount++] = bottomRight;
            outVertices[outVertexCount++] = topRight;
            outVertices[outVertexCount++] = bottomLeft;
            outVertices[outVertexCount++] = topRight;
            outVertices[outVertexCount++] = topLeft;
        }

        cursorX += static_cast<float>(glyph.advance) * scale;
        previousChar = unicode;
    }
}


// TODO: Convert into a Vector2 return type.
std::pair<float, float> Renderer::measureTextBounds(const char* text, float fontSize)
{
    if (!text || text[0] == '\0') return {0.0f, 0.0f};

    float scale      = fontSize / static_cast<float>(fontAtlas.metrics.emSize);
    float lineHeight = static_cast<float>(fontAtlas.metrics.lineHeight) * scale;

    float maxXInLine = 0.0f;
    float maxLineWidth = 0.0f;
    float cursorX = 0.0f;
    int lineCount = 1;
    uint32_t previousChar = 0;

    for (const char* p = text; *p; ++p) {
        uint32_t unicode = static_cast<unsigned char>(*p); // ensures 0-255
        if (unicode > 127) continue; // skip non-ASCII

        if (unicode == '\n') {
            maxLineWidth = std::max(maxLineWidth, maxXInLine);
            cursorX = 0;
            maxXInLine = 0;
            lineCount++;
            previousChar = 0;
            continue;
        }

        if (previousChar != 0) {
            uint64_t key = (static_cast<uint64_t>(previousChar) << 32) | unicode;
            auto it = fontKerning.find(key);
            if (it != fontKerning.end()) {
                cursorX += static_cast<float>(it->second.advance) * scale;
            }
        }

        auto gIt = fontGlyphs.find(unicode);
        if (gIt != fontGlyphs.end()) {
            const Glyph& glyph = gIt->second;
            float glyphRight = 0.0f;
            if (glyph.planeBounds) {
                glyphRight = cursorX + static_cast<float>(glyph.planeBounds->right) * scale;
            } else {
                glyphRight = cursorX + static_cast<float>(glyph.advance) * scale;
            }
            maxXInLine = std::max(maxXInLine, glyphRight);
            cursorX += static_cast<float>(glyph.advance) * scale;
        }

        previousChar = unicode;
    }

    float textWidth  = std::max(maxLineWidth, maxXInLine);
    float textHeight = static_cast<float>(lineCount) * lineHeight;

    return {textWidth, textHeight};
}



