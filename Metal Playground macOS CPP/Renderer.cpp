//
//  Renderer.cpp
//  Metal Playground macOS CPP
//
//  Created by Rayner Tan on 21/8/25.
//

// TODO: Cache all the sizeof stride sizes

#include "Renderer.hpp"
#include <cassert>
#include "ShaderTypes.h"
#include "ii_random.h"

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

// TODO: Font Atlas Structs



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
    
    // TODO: Load Textures and Fonts
    loadAtlasTextureAndUV();
}

Renderer::~Renderer()
{
    delete[] drawBatchesArr;
    device->release();
    commandQueue->release();
    
    atlasVertexBuffer->release();
    atlasTriInstanceBuffer->release();
    atlasSamplerState->release();
    atlasPipelineState->release();
    primitiveVertexBuffer->release();
    primitiveTriInstanceBuffer->release();
    primitivePipelineState->release();
    mainAtlasTexture->release();
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
    // TODO: implement buildTextBuffers
}

void Renderer::updateTriBufferStates()
{
    triBufferIndex = (triBufferIndex + 1) % maxBuffersInFlight;
    
    atlasTriInstanceBufferOffset = sizeof(AtlasInstanceData) * atlasMaxInstanceCount * triBufferIndex;
    atlasInstancesPtr = (static_cast<AtlasInstanceData*>(atlasTriInstanceBuffer->contents())) + (atlasMaxInstanceCount * triBufferIndex);
    
    primitiveTriInstanceBufferOffset = sizeof(PrimitiveInstanceData) * primitiveMaxInstanceCount * triBufferIndex;
    primitiveInstancesPtr = (static_cast<PrimitiveInstanceData*>(primitiveTriInstanceBuffer->contents())) + (primitiveMaxInstanceCount * triBufferIndex);
    
    // TODO: Handle text tri instance buffer.
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
    // TODO: Implement this
}

void Renderer::loadAtlasTextureAndUV()
{
    // "main_atlas", 256, 256
    // TODO: Load up mainAtlasTexture and the UVs
    // Problem is that TextureLoader is not implemented in metal-cpp.
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
        
        drawPrimitiveCirlce(x, y, radius, color);
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
        // TODO: textVertexCount = 0;
        
        time += 1.0 / pView->preferredFramesPerSecond();
        // TODO TEST DRAW CODE HERE
        testDrawPrimitives();

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
                        // TODO: Implement this
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
    
//    MTL::CommandBuffer* pCmd = _pCommandQueue->commandBuffer();
//    MTL::RenderPassDescriptor* pRpd = pView->currentRenderPassDescriptor();
//    MTL::RenderCommandEncoder* pEnc = pCmd->renderCommandEncoder( pRpd );
//
//    pEnc->setRenderPipelineState( _pPSO );
//    pEnc->setVertexBuffer( _pVertexPositionsBuffer, 0, 0 );
//    pEnc->setVertexBuffer( _pVertexColorsBuffer, 0, 1 );
//    pEnc->drawPrimitives( MTL::PrimitiveType::PrimitiveTypeTriangle, NS::UInteger(0), NS::UInteger(3) );
//
//    pEnc->endEncoding();
//    pCmd->presentDrawable( pView->currentDrawable() );
//    pCmd->commit();

    pPool->release();
}

void Renderer::drawableSizeWillChange( MTK::View* pView, CGSize size )
{
    __builtin_printf("drawableSizeWillChange called, (%0.f, %0.f)\n", size.width, size.height);
    screenSize = size;
    projectionMatrix = pixelSpaceProjection((float)size.width, (float)size.height);
    primitiveUniforms = (PrimitiveUniforms){projectionMatrix};
}

static inline simd_float4 colorFromBytes(UInt8 r, UInt8 g, UInt8 b, UInt8 a) {
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

// TODO: Atlas Drawing Functions

// MARK: - Primitive Drawing Functions
void Renderer::drawPrimitiveCircle(float x, float y, float radius,
                             UInt8 r, UInt8 g, UInt8 b, UInt8 a)
{
    drawPrimitiveCirlce(x, y, radius, colorFromBytes(r, g, b, a));
}
void Renderer::drawPrimitiveCirlce(float x, float y, float radius, simd_float4 color)
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

// TODO: Implement the text drawing functions


