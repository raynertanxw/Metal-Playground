//
//  Renderer.swift
//
//  Created by Rayner Tan on 25/7/25.
//

import MetalKit

// MARK: - Pipeline Structs
struct AtlasUVRect {
    var minUV: SIMD2<Float> // bottom-left
    var maxUV: SIMD2<Float> // top-right
}

struct EntityVertex {
    var position: SIMD2<Float>
}

struct EntityUniforms {
    var projectionMatrix: float4x4
}

struct EntityInstanceData {
    var transform: simd_float4x4  // 64 bytes
    var color: SIMD4<Float>       // 16 bytes
    var atlasUVs: SIMD4<Float>    // 16 bytes (x: minU, y: minV, z: maxU, w: maxV)
    var sdfParams: SIMD4<Float>   // 16 bytes
    var shapeType: UInt32         // 4  bytes
    var __padding: (UInt32, UInt32, UInt32) = (0,0,0) // 12 bytes
}

struct TextVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
    var textColor: SIMD4<Float>
}

struct TextFragmentUniforms {
    var distanceRange: Float
}


// MARK: - Renderer Class
class Renderer: NSObject, MTKViewDelegate {
    private var projectionMatrix = matrix_identity_float4x4
    private var screenSize: CGSize = .zero
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    private static let maxBuffersInFlight = 3
    private let inFlightSemaphore: DispatchSemaphore
    private var triBufferIndex = 0
    
    // MARK: - For debugging
    private var lastRenderTimestamp: CFTimeInterval = 0
    private var renderFrameCount: Int = 0
    var reportedFPS: Double = 0   // so GameViewController can read it
    var onFramePresented: ((Double) -> Void)?

    
    // MARK: - ATLAS PIPELINE VARS
    private var atlasPipelineState: MTLRenderPipelineState
    private var atlasVertexBuffer: MTLBuffer
    private var atlasTriInstanceBuffer: MTLBuffer
    private var atlasTriInstanceBufferOffset = 0
    private var atlasInstancesPtr: UnsafeMutablePointer<AtlasInstanceData>
    private let atlasMaxInstanceCount = 50000
    private var atlasInstanceCount = 0
    
    private let atlasSquareVertices: [AtlasVertex] = [
        AtlasVertex(position: [-0.5, -0.5], uv: [0, 1]),
        AtlasVertex(position: [ 0.5, -0.5], uv: [1, 1]),
        AtlasVertex(position: [-0.5,  0.5], uv: [0, 0]),
        AtlasVertex(position: [ 0.5,  0.5], uv: [1, 0]),
    ]
    
    // TODO: Use Arguement buffers to pass multiple texture atlasses?
    private var mainAtlasTexture: MTLTexture!
    private var mainAtlasUVRects: [String: AtlasUVRect] = [:]
    private let atlasSamplerState: MTLSamplerState
    
    
    // MARK: - ENTITY PIPELINE VARs
    private var entityPipelineState: MTLRenderPipelineState
    private var entityVertexBuffer: MTLBuffer
    private var entityTriInstanceBuffer: MTLBuffer
    private var entityTriInstanceBufferOffset = 0
    private var entityInstancesPtr: UnsafeMutablePointer<EntityInstanceData>
    private let entityMaxInstanceCount = 50000
    private var entityInstanceCount = 0
    
    private let entityBaseSquareVertices: [EntityVertex] = [
        EntityVertex(position: [-0.5, -0.5]),
        EntityVertex(position: [0.5, -0.5]),
        EntityVertex(position: [-0.5, 0.5]),
        EntityVertex(position: [0.5, 0.5])
    ]
    
    private var entityUniforms = EntityUniforms(projectionMatrix: matrix_identity_float4x4)
    
    
    // MARK: - TEXT PIPELINE VARS
    private let fontTexture: MTLTexture
    private let fontAtlas: FontAtlas
    private var fontGlyphs = [UInt32: Glyph]()
    private var fontKerning = [UInt64: Kerning]()
    
    private let textPipelineState: MTLRenderPipelineState
    private let textSamplerState: MTLSamplerState
    private var textTriVertexBuffer: MTLBuffer!
    private let textMaxVertexCount: Int = 4096 * 6
    private var textTriInstanceBufferOffset = 0
    private var textVertexBufferPtr: UnsafeMutablePointer<TextVertex>
    private var textVertexCount = 0
    
    
    // MARK: - Draw Command Batching
    enum DrawBatchType: Int {
        case none = 0
        case atlas = 1
        case entity = 2
        case text = 3
        case count = 4
    }
    struct DrawBatch {
        var type: DrawBatchType
        var startIndex: Int
        var count: Int
    }
    private var drawBatchesPtr: UnsafeMutablePointer<DrawBatch>
    private var drawBatchCount: Int = 0
    private let drawBatchMaxCount: Int = 1024
    private var curDrawBatchType: DrawBatchType = .none
    // TODO: try (Int, Int, Int) = (0, 0, 0), see if that speeds things up.
    private var nextStartIndexForTypePtr: UnsafeMutablePointer<Int>
    private let strideSizesPtr: UnsafeMutablePointer<Int>
    
    
    
    // MARK: - GAME RELATED
    var time: Float = 0
    
    // MARK: - INIT
    init?(mtkView: MTKView) {
        // TODO: Figure out how to assert the padding and stride of the shader structs too!
        assert(MemoryLayout<AtlasInstanceData>.stride == 128);
        assert(MemoryLayout<EntityInstanceData>.stride == 128);
        assert(MemoryLayout<TextVertex>.stride == 32);
        
        self.inFlightSemaphore = DispatchSemaphore(value: Self.maxBuffersInFlight)
        
        self.drawBatchesPtr = .allocate(capacity: self.drawBatchMaxCount)
        self.nextStartIndexForTypePtr = .allocate(capacity: DrawBatchType.count.rawValue)
        self.nextStartIndexForTypePtr.initialize(repeating: 0, count: DrawBatchType.count.rawValue)
        self.strideSizesPtr = .allocate(capacity: DrawBatchType.count.rawValue)
        self.strideSizesPtr.initialize(repeating: 0, count: DrawBatchType.count.rawValue)
        self.strideSizesPtr[DrawBatchType.atlas.rawValue] = MemoryLayout<AtlasInstanceData>.stride
        self.strideSizesPtr[DrawBatchType.entity.rawValue] = MemoryLayout<EntityInstanceData>.stride
        self.strideSizesPtr[DrawBatchType.text.rawValue] = MemoryLayout<TextVertex>.stride

        guard let device = mtkView.device else { fatalError("Unable to obtain MTLDevice from MTKView") }
        self.device = device
        guard let cmdQueue = device.makeCommandQueue() else { fatalError("Unable to obtain MTLCommandQueue from MTLDevice") }
        self.commandQueue = cmdQueue
        
        // Build Atlas Buffers
        (self.atlasVertexBuffer, self.atlasTriInstanceBuffer) = Self.buildAtlasBuffers(device: device, vertices: atlasSquareVertices, maxCount: atlasMaxInstanceCount)
        self.atlasInstancesPtr = UnsafeMutableRawPointer(atlasTriInstanceBuffer.contents()).bindMemory(to: AtlasInstanceData.self, capacity: atlasMaxInstanceCount)

        // Build Entity Buffers
        (self.entityVertexBuffer, self.entityTriInstanceBuffer) = Self.buildEntityBuffers(device: device, vertices: entityBaseSquareVertices, maxCount: entityMaxInstanceCount)
        self.entityInstancesPtr = UnsafeMutableRawPointer(entityTriInstanceBuffer.contents()).bindMemory(to: EntityInstanceData.self, capacity: entityMaxInstanceCount)
        
        // Build Text Buffers
        self.textTriVertexBuffer = Self.buildTextBuffers(device: device, maxSize:   textMaxVertexCount)
        self.textVertexBufferPtr = UnsafeMutableRawPointer(textTriVertexBuffer.contents()).bindMemory(to: TextVertex.self, capacity: textMaxVertexCount)

        // Build Pipelines & Descriptors & Misc
        (self.atlasPipelineState, self.atlasSamplerState) = Self.buildAtlasPipeline(device: device, mtkView: mtkView)
        self.entityPipelineState = Self.buildEntityPipeline(device: device, mtkView: mtkView)
        (self.textPipelineState, self.textSamplerState) = Self.buildTextPipeline(device: device, mtkView: mtkView)
        
        // Load Textures & Fonts
        self.mainAtlasTexture = Renderer.loadTexture(device: device, name: "main_atlas")
        self.mainAtlasUVRects = Renderer.loadAtlasUV(named: "main_atlas", textureWidth: 2048, textureHeight: 2048)
        let fontName = "roboto"
        (self.fontAtlas, self.fontTexture) = Self.loadFontAtlas(device: device, fontName: fontName)
        (self.fontGlyphs, self.fontKerning) = Self.preprocessFontData(fontAtlas: fontAtlas)

        
        super.init()
    }
    
    private class func buildAtlasBuffers(device: MTLDevice, vertices atlasSquareVertices: [AtlasVertex], maxCount atlasMaxInstanceCount: Int) -> (MTLBuffer, MTLBuffer) {
        guard let atlasVertexBuffer = device.makeBuffer(
            bytes: atlasSquareVertices,
            length: atlasSquareVertices.count * MemoryLayout<AtlasVertex>.stride,
            options: []) else { fatalError("Unable to create vertex buffer for atlas") }
        atlasVertexBuffer.label = "Atlas Square Vertex Buffer"
        
        let atlasTriInstanceBufferSize = MemoryLayout<AtlasInstanceData>.stride * atlasMaxInstanceCount * maxBuffersInFlight
        guard let atlasTriInstanceBuffer = device.makeBuffer(
            length: atlasTriInstanceBufferSize,
            options: [MTLResourceOptions.storageModeShared]) else { fatalError("Unable to create tri instance buffer for atlas") }
        atlasTriInstanceBuffer.label = "Atlas Tri Instance Buffer"
        
        return (atlasVertexBuffer, atlasTriInstanceBuffer)
    }
    
    private class func buildEntityBuffers(device: MTLDevice, vertices entityBaseSquareVertices: [EntityVertex], maxCount entityMaxInstanceCount: Int) -> (MTLBuffer, MTLBuffer) {
        guard let entityVertexBuffer = device.makeBuffer(
            bytes: entityBaseSquareVertices,
            length: entityBaseSquareVertices.count * MemoryLayout<EntityVertex>.stride,
            options: []) else { fatalError("Unable to create vertex buffer for entities") }
        entityVertexBuffer.label = "Entity Square Vertex Buffer"
        
        let entityTriInstanceBufferSize = MemoryLayout<EntityInstanceData>.stride * entityMaxInstanceCount * maxBuffersInFlight
        guard let entityTriInstanceBuffer = device.makeBuffer(
            length: entityTriInstanceBufferSize,
            options: [MTLResourceOptions.storageModeShared]) else { fatalError("Unable to create tri instance buffer for entities") }
        entityTriInstanceBuffer.label = "Entity Tri Instance Buffer"
        
        return (entityVertexBuffer, entityTriInstanceBuffer)
    }
    
    private class func buildTextBuffers(device: MTLDevice, maxSize vertexBufferCapacity: Int) -> (MTLBuffer) {
        let textTriInstanceBufferSize = MemoryLayout<TextVertex>.stride * vertexBufferCapacity * maxBuffersInFlight
        guard let textTriVertexBuffer = device.makeBuffer(
            length: textTriInstanceBufferSize,
            options: [MTLResourceOptions.storageModeShared]) else { fatalError("Unable to create vertex buffer for text") }
        textTriVertexBuffer.label = "Text Tri Vertex Buffer"
        
        return textTriVertexBuffer
    }
    
    private func updateTriBufferStates() {
        triBufferIndex = (triBufferIndex + 1) % Self.maxBuffersInFlight
        
        atlasTriInstanceBufferOffset = MemoryLayout<AtlasInstanceData>.stride * atlasMaxInstanceCount * triBufferIndex
        atlasInstancesPtr = UnsafeMutableRawPointer(atlasTriInstanceBuffer.contents()).advanced(by: atlasTriInstanceBufferOffset).bindMemory(to: AtlasInstanceData.self, capacity: atlasMaxInstanceCount)
        
        entityTriInstanceBufferOffset = MemoryLayout<EntityInstanceData>.stride * entityMaxInstanceCount * triBufferIndex
        entityInstancesPtr = UnsafeMutableRawPointer(entityTriInstanceBuffer.contents()).advanced(by: entityTriInstanceBufferOffset).bindMemory(to: EntityInstanceData.self, capacity: entityMaxInstanceCount)
        
        textTriInstanceBufferOffset = MemoryLayout<TextVertex>.stride * textMaxVertexCount * triBufferIndex
        textVertexBufferPtr = UnsafeMutableRawPointer(textTriVertexBuffer.contents()).advanced(by: textTriInstanceBufferOffset).bindMemory(to: TextVertex.self, capacity: textMaxVertexCount)
    }
    
    private class func buildAtlasPipeline(device: MTLDevice, mtkView: MTKView) -> (MTLRenderPipelineState, MTLSamplerState) {
        guard let library = device.makeDefaultLibrary() else { fatalError("Unable to get default library") }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_atlas")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_atlas")
        
        // Enable alpha blending
        let colorAttachment = pipelineDescriptor.colorAttachments[0]!
        colorAttachment.pixelFormat = mtkView.colorPixelFormat
        colorAttachment.isBlendingEnabled = true
        colorAttachment.rgbBlendOperation = .add
        colorAttachment.alphaBlendOperation = .add
        colorAttachment.sourceRGBBlendFactor = .sourceAlpha
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        // Vertex Descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        
        // Position
        vertexDescriptor.attributes[AtlasVertAttr.position.rawValue].format = .float2
        vertexDescriptor.attributes[AtlasVertAttr.position.rawValue].offset = 0
        vertexDescriptor.attributes[AtlasVertAttr.position.rawValue].bufferIndex = BufferIndex.vertices.rawValue
        
        // UV
        vertexDescriptor.attributes[AtlasVertAttr.UV.rawValue].format = .float2
        vertexDescriptor.attributes[AtlasVertAttr.UV.rawValue].offset = MemoryLayout<AtlasVertex>.offset(of: \.uv)!
        vertexDescriptor.attributes[AtlasVertAttr.UV.rawValue].bufferIndex = BufferIndex.vertices.rawValue
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<AtlasVertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        
        
        guard let atlasPipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            fatalError("Unable to create atlas pipeline state")
        }
        
        let atlasSamplerDescriptor = MTLSamplerDescriptor()
        atlasSamplerDescriptor.minFilter = .linear
        atlasSamplerDescriptor.magFilter = .nearest // NOTE: linear can cause some bleeding from neighbouring edges in atlas.
        atlasSamplerDescriptor.mipFilter = .linear
        guard let atlasSamplerState = device.makeSamplerState(descriptor: atlasSamplerDescriptor) else { fatalError("Unable to create atlas sampler state") }

        return (atlasPipelineState, atlasSamplerState)
    }
    
    private class func buildEntityPipeline(device: MTLDevice, mtkView: MTKView) -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Unable to get default library")
        }
        
        let entityPipelineDescriptor = MTLRenderPipelineDescriptor()
        entityPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_entity")
        entityPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_entity")
        
        // Enable alpha blending
        let colorAttachment = entityPipelineDescriptor.colorAttachments[0]!
        colorAttachment.pixelFormat = mtkView.colorPixelFormat
        colorAttachment.isBlendingEnabled = true
        colorAttachment.rgbBlendOperation = .add
        colorAttachment.alphaBlendOperation = .add
        colorAttachment.sourceRGBBlendFactor = .sourceAlpha
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        guard let entityPipelineState = try? device.makeRenderPipelineState(descriptor: entityPipelineDescriptor) else {
            fatalError("Unable to create entity pipeline state")
        }
        return entityPipelineState
    }
    
    private class func buildTextPipeline(device: MTLDevice, mtkView: MTKView) -> (MTLRenderPipelineState, MTLSamplerState) {
        guard let library = device.makeDefaultLibrary() else { fatalError("Unable to get default library") }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_text")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_text")
                
        // Enable alpha blending
        let colorAttachment = pipelineDescriptor.colorAttachments[0]!
        colorAttachment.pixelFormat = mtkView.colorPixelFormat
        colorAttachment.isBlendingEnabled = true
        colorAttachment.rgbBlendOperation = .add
        colorAttachment.alphaBlendOperation = .add
        colorAttachment.sourceRGBBlendFactor = .sourceAlpha
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // Vertex Descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        
        // Position
        vertexDescriptor.attributes[TextVertAttr.position.rawValue].format = .float2
        vertexDescriptor.attributes[TextVertAttr.position.rawValue].offset = 0
        vertexDescriptor.attributes[TextVertAttr.position.rawValue].bufferIndex = TextBufferIndex.vertices.rawValue
        
        // UV
        vertexDescriptor.attributes[TextVertAttr.UV.rawValue].format = .float2
        vertexDescriptor.attributes[TextVertAttr.UV.rawValue].offset = MemoryLayout<TextVertex>.offset(of: \.uv)!
        vertexDescriptor.attributes[TextVertAttr.UV.rawValue].bufferIndex = TextBufferIndex.vertices.rawValue
        
        // Color
        vertexDescriptor.attributes[TextVertAttr.textColor.rawValue].format = .float4
        vertexDescriptor.attributes[TextVertAttr.textColor.rawValue].offset = MemoryLayout<TextVertex>.offset(of: \.textColor)!
        vertexDescriptor.attributes[TextVertAttr.textColor.rawValue].bufferIndex = TextBufferIndex.vertices.rawValue
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<TextVertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        guard let textPipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            fatalError("Unable to create text pipeline state")
        }
        
        let textSamplerDescriptor = MTLSamplerDescriptor()
        textSamplerDescriptor.minFilter = .linear
        textSamplerDescriptor.magFilter = .linear
        textSamplerDescriptor.mipFilter = .linear
        guard let textSamplerState = device.makeSamplerState(descriptor: textSamplerDescriptor) else { fatalError("Unabled to create text sampler state") }
        
        return (textPipelineState, textSamplerState)
    }
    
    private class func loadTexture(device: MTLDevice, name: String) -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: device)
        let url = Bundle.main.url(forResource: name, withExtension: "png")!
        let options: [MTKTextureLoader.Option: Any] = [.SRGB: false]
        
        do {
            return try textureLoader.newTexture(URL: url, options: options)
        } catch {
            fatalError("Failed to load texture: \(error)")
        }
    }
    
    private class func loadAtlasUV(named filename: String, textureWidth: Float, textureHeight: Float) -> [String: AtlasUVRect] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "txt") else {
            fatalError("Atlas file not found.")
        }
        
        let contents = try! String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n").dropFirst() // skip the count
        
        var atlasUV = [String: AtlasUVRect]()
        
        for line in lines {
            let parts = line.split(separator: " ")
            guard parts.count == 5 else { continue }
            
            let name = String(parts[0])
            let x = Float(parts[1])!
            let y = Float(parts[2])!
            let w = Float(parts[3])!
            let h = Float(parts[4])!
            
            let minUV = SIMD2<Float>(x / textureWidth, y / textureHeight)
            let maxUV = SIMD2<Float>((x + w) / textureWidth, (y + h) / textureHeight)
            
            atlasUV[name] = AtlasUVRect(minUV: minUV, maxUV: maxUV)
        }
        
        return atlasUV
    }
    
    private class func loadFontAtlas(device: MTLDevice, fontName: String) -> (FontAtlas, MTLTexture) {
        // Load JSON
        guard let jsonURL = Bundle.main.url(forResource: fontName, withExtension: "json") else {
            fatalError("Font atlas JSON file not found: \(fontName).json")
        }
        let jsonData = try! Data(contentsOf: jsonURL)
        let fontAtlas = try! JSONDecoder().decode(FontAtlas.self, from: jsonData)
        
        // Load PNG Texture
        let textureLoader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false, // NOTE: Specify non SRGB, since the font image is data, not to be influenced by colour space.
            .textureUsage : MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode : MTLStorageMode.shared.rawValue,
        ]
        guard let textureURL = Bundle.main.url(forResource: fontName, withExtension: "png") else {
            fatalError("Font atlas texture not found: \(fontName).png")
        }
        let texture = try! textureLoader.newTexture(URL: textureURL, options: options)
        
        return (fontAtlas, texture)
    }
    
    private class func preprocessFontData(fontAtlas: FontAtlas) -> ([UInt32: Glyph], [UInt64: Kerning]) {
        var glyphs = [UInt32: Glyph]()
        var kerning = [UInt64: Kerning]()
        
        for glyph in fontAtlas.glyphs {
            glyphs[UInt32(glyph.unicode)] = glyph
        }
        for kern in fontAtlas.kerning {
            // Combine the two unicode values into a single key for dictionary lookup
            let key = (UInt64(kern.unicode1) << 32) | UInt64(kern.unicode2)
            kerning[key] = kern
        }
        
        return (glyphs, kerning)
    }
    
    private func testDrawSprites() {
        // For test: oscillate count between 0 and testMaxCount
        let testMaxCount: Float = 100
        let testCount = min(Int((sin(time * 2.0) + 1.0) / 2.0 * testMaxCount), atlasMaxInstanceCount - 1)
        
        var color = SIMD4<Float>.zero
        for i in 0..<testCount {
            let angle = time + Float(i) * (2 * .pi / Float(testCount))
            let radius: Float = Float(screenSize.width) / 3.0
            color.x = 0.5 + 0.5 * sin(angle)
            color.y = 0.5 + 0.5 * cos(angle)
            color.z = 0.5 + 0.5 * sin(angle * 0.5)
            color.w = 1.0
            
            drawSprite(
                spriteName: "Circle_White",
                x: cos(angle) * radius,
                y: sin(angle) * radius,
                width: 100.0 + 100.0 * sin(angle),
                height: 100.0 + 100.0 * sin(angle),
                color: color,
                rotationRadians: angle * 2)
        }
        
        { // Test anything static here, adds to last instance count
            let spriteName = "player_1"
            drawSprite(spriteName: spriteName, x: 100, y: 100, width: 256, height: 256, color: SIMD4<Float>.one)
        }()
    }
    
    private func testDrawEntities() {
        let circleCount = 30000
        var rng = FastRandom(seed: UInt64(time * 1000000))
        var color = SIMD4<Float>.zero
        
//        for _ in 0..<circleCount {
//            let x = rng.nextFloat(min: Float(-screenSize.width), max: Float(screenSize.width))
//            let y = rng.nextFloat(min: Float(-screenSize.height), max: Float(screenSize.height))
//            let radius = rng.nextFloat(min: 5, max: 25)
//            
//            color.x = rng.nextUnitFloat()
//            color.y = rng.nextUnitFloat()
//            color.z = rng.nextUnitFloat()
//            color.w = 1.0
//            
//            drawEntityCircle(x: x, y: y, radius: radius, color: color)
//        }
        
        drawEntityCircle(x: 0, y: 0, radius: 800.0, r: 255, g: 255, b: 255, a: 64)
        drawEntityCircle(x: 0, y: 0, radius: 512.0, r: 0, g: 255, b: 255, a: 64)
        drawEntityCircle(x: 0, y: 0, radius: 256.0, r: 255, g: 0, b: 255, a: 64)
        drawEntityCircle(x: 256, y: 256, radius: 128.0, r: 255, g: 0, b: 0, a: 64)
        drawEntityCircle(x: 0, y: 0, radius: 128.0, r: 0, g: 255, b: 0, a: 64)
        drawEntityCircle(x: -256, y: -256, radius: 128.0, r: 0, g: 0, b: 255, a: 64)
        drawEntityLine(x1: -800, y1: -600, x2: 800, y2: 600, thickness: 10, r: 200, g: 100, b: 0, a: 128)
        drawEntityRectLines(x: 0, y: 0, width: 800, height: 600, thickness: 48, r: 0, g: 255, b: 255, a: 255)
        drawEntityRect(x: 0, y: 0, width: 800, height: 600, r: 255, g: 0, b: 0, a: 64)
        drawEntityRect(x: -800, y: -600, width: 800, height: 600, r: 255, g: 0, b: 0, a: 64)
        drawEntityRect(x: 0, y: 0, width: 24, height: 600, r: 255, g: 0, b: 0, a: 64)
        drawEntityRect(x: 0, y: 0, width: 128, height: 196, r: 0, g: 255, b: 0, a: 128)
        drawEntityRect(x: -800, y: -600, width: 800, height: 600, r: 128, g: 255, b: 0, a: 128)
        drawEntityRect(x: -800, y: -600, width: 1600, height: 1200, r: 0, g: 255, b: 255, a: 32)
        drawEntityRoundedRect(x: 0, y: 0, width: 800, height: 600, cornerRadius: 100, r: 0, g: 0, b: 255, a: 255)
        drawEntityRoundedRect(x: 0, y: 0, width: 800, height: 100, cornerRadius: 100, r: 0, g: 255, b: 255, a: 255)
        drawEntityCircle(x: 100, y: 100, radius: 100, r: 255, g: 0, b: 0, a: 128)
        drawEntityRect(x: -600, y: -600, width: 1200, height: 1200, r: 255, g: 0, b: 255, a: 255)
        drawEntityCircle(x: 0, y: 0, radius: 600, r: 255, g: 255, b: 255, a: 255)
        drawEntityCircleLines(x: 0, y: 0, radius: 600, thickness: 48, r: 255, g: 0, b: 255, a: 128)
        drawEntityRect(x: -600, y:-600, width: 48, height: 1200, r: 0, g: 255, b: 0, a: 128)
    }
    
    private func testDrawTextWithBounds() {
        // Testing for text bounds checking
        let fontSize: Float = 96
        let now = Date().timeIntervalSince1970
        let text = "Hello, SDF\nWorld!\n\n\(Int(now))"
        let textBounds = measureTextBounds(for: text, withSize: fontSize)
        drawEntityCircle(x: -Float(textBounds.width / 2.0),
                            y: Float(textBounds.height / 2.0),
                            radius: 16, color: SIMD4<Float>.one)
        drawEntityRect(
            x: -Float(textBounds.width / 2.0),
            y: -(textBounds.height / 2.0),
            width: textBounds.width,
            height: textBounds.height,
            color: SIMD4<Float>(0,1.0,1.0,0.25))
        
        let color: SIMD4<Float> = [0.9, 0.9, 0.1, 1.0] // Yellow
        drawText(
            text: text,
            posX: -Float(textBounds.width / 2.0),
            posY: Float(textBounds.height / 2.0),
            fontSize: fontSize,
            color: color,
        )
        
        
        drawText(text: "HELLO       AGAIN!!!",
                 posX: Float(20 - screenSize.width / 2.0),
                 posY: Float(-20 + screenSize.height / 2.0),
                 fontSize: 48,
                 color: [0.3, 0.2, 0.7, 1.0])
    }
    
    private func testUpdateGameState() {
        testDrawEntities()
//        testDrawSprites()
//        testDrawTextWithBounds()
        
//        let wave1 = sin(time * 1.5) * 300
//        let wave2 = cos(time * 0.8) * 200
//        let wave3 = sin(time * 3.2) * 100
//        let circleX = sin(time * 2.0) * 256
//        let circleY = cos(time * 1.0) * 128
        
//        drawSprite(spriteName: "player_2",
//                   x: wave1,
//                   y: wave2,
//                   width: 256 + wave3,
//                   height: 256 + wave3,
//                   color: SIMD4<Float>.one)
//        
//        drawEntityCircle(x: circleX,
//                            y: circleY,
//                            radius: 128 + sin(time * 4.0) * 64,
//                            color: [1, 0.3, 0.5, 1])
//        
//        drawSprite(spriteName: "player_2",
//                   x: -circleX,
//                   y: -circleY,
//                   width: 128,
//                   height: 128,
//                   color: SIMD4<Float>(1, 1, 1, 1))
//        
//        let textYOffset = sin(time * 1.2) * 40
//        drawText(text: "Dynamic Text\nis Alive!",
//                 posX: -200,
//                 posY: 300 + textYOffset,
//                 fontSize: 64 + sin(time * 2.5) * 8,
//                 color: SIMD4<Float>(1, 0.8, 0.2, 1))
//        
//                
//        drawText(text: "Another Test", posX: -150, posY: -50, fontSize: 48, color: [1,0,1,1])
//
//        let scrollOffset = sin(time * 0.5) * 150
//        
//        drawText(text: "This is a much\nLonger test of a block\nOf text here and there\nAnother line here\nAnother line there\n  Here's one with 2 spaces before",
//                 posX: -600 + scrollOffset,
//                 posY: 600,
//                 fontSize: 96,
//                 color: SIMD4<Float>(0.1, 1.0, 0.5, 1.0))
//        
//        drawEntityCircle(x: sin(time * 0.7) * 600,
//                            y: cos(time * 0.9) * 500,
//                            radius: 64,
//                            color: [0, 0.5, 0.5, 1])
//        
//        drawText(text: "This is a much\nLonger test of a block\nOf text here and there\nAnother line here\nAnother line there\n  Here's one with 2 spaces before",
//                 posX: -900 - scrollOffset,
//                 posY: 100,
//                 fontSize: 96,
//                 color: SIMD4<Float>(0.1, 1.0, 0.5, 1.0))
    }
    
    // MARK: - DRAW FUNCTION
    func draw(in view: MTKView) {
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer) -> Swift.Void in
                semaphore.signal()
            }
            
            self.updateTriBufferStates()
            drawBatchCount = 0
            for index in 0..<DrawBatchType.count.rawValue { self.nextStartIndexForTypePtr[index] = 0 }
            curDrawBatchType = .none
            atlasInstanceCount = 0
            entityInstanceCount = 0
            textVertexCount = 0

            
            time += 1.0 / Float(view.preferredFramesPerSecond)
            self.testUpdateGameState()
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            if let renderPassDescriptor = renderPassDescriptor, let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                encoder.label = "Primary Render Encoder"
                            
                for batchIndex in 0..<drawBatchCount {
                    let batch = self.drawBatchesPtr[batchIndex]
                    assert(batch.count > 0)
                    assert(batch.startIndex >= 0)
                    switch batch.type {
                    case .count:
                        fatalError("Draw Batch with type count, should never be implemented")
                    case .none:
                        fatalError("Draw Batch with type none")
                    case .atlas:
                        encoder.setRenderPipelineState(atlasPipelineState)
                        encoder.setVertexBuffer(atlasVertexBuffer, offset: 0, index: BufferIndex.vertices.rawValue)
                        
                        encoder.setVertexBuffer(atlasTriInstanceBuffer,
                                                offset: atlasTriInstanceBufferOffset + (MemoryLayout<AtlasInstanceData>.stride * batch.startIndex),
                                                index: BufferIndex.instances.rawValue)
                        
                        encoder.setFragmentTexture(mainAtlasTexture, index: 0)
                        encoder.setFragmentSamplerState(atlasSamplerState, index: 0)
                        encoder.drawPrimitives(type: .triangleStrip,
                                               vertexStart: 0,
                                               vertexCount: atlasSquareVertices.count,
                                               instanceCount: batch.count)
                        
                    case .entity:
                        encoder.setRenderPipelineState(entityPipelineState)
                        encoder.setVertexBuffer(entityVertexBuffer, offset: 0, index: BufferIndex.vertices.rawValue)
                        
                        encoder.setVertexBuffer(entityTriInstanceBuffer,
                                                offset: entityTriInstanceBufferOffset + (MemoryLayout<EntityInstanceData>.stride * batch.startIndex),
                                                index: BufferIndex.instances.rawValue)
                        
                        encoder.setVertexBytes(&entityUniforms, length: MemoryLayout<EntityUniforms>.stride, index: BufferIndex.uniforms.rawValue)
                        encoder.drawPrimitives(type: .triangleStrip,
                                               vertexStart: 0,
                                               vertexCount: entityBaseSquareVertices.count,
                                               instanceCount: batch.count)
                        
                    case .text:
                        encoder.setRenderPipelineState(textPipelineState)
                        encoder.setVertexBuffer(textTriVertexBuffer,
                                                offset: textTriInstanceBufferOffset + (MemoryLayout<TextVertex>.stride * batch.startIndex),
                                                index: TextBufferIndex.vertices.rawValue)
                        var projectionMatrix = projectionMatrix
                        encoder.setVertexBytes(&projectionMatrix, length: MemoryLayout<float4x4>.stride, index: TextBufferIndex.projectionMatrix.rawValue)
                        
                        var uniforms = TextFragmentUniforms(distanceRange: Float(fontAtlas.atlas.distanceRange))
                        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TextFragmentUniforms>.stride, index: 0)
                        encoder.setFragmentTexture(fontTexture, index: 0)
                        encoder.setFragmentSamplerState(textSamplerState, index: 0)
                        
                        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: batch.count)
                    }
                }
                
                encoder.endEncoding()
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                    
                    // NOTE: For debugging
                    let now = CACurrentMediaTime()
                    if lastRenderTimestamp == 0 {
                        lastRenderTimestamp = now
                    }
                    renderFrameCount += 1
                    let delta = now - lastRenderTimestamp
                    if delta >= 1.0 {
                        reportedFPS = Double(renderFrameCount) / delta
                        lastRenderTimestamp = now
                        renderFrameCount = 0
                    }
                    
                    onFramePresented?(reportedFPS)
                }
            }
            
            commandBuffer.commit()
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("drawableSizeWillChange called, \(size.debugDescription)")
        screenSize = size
        projectionMatrix = float4x4.pixelSpaceProjection(screenWidth: Float(size.width), screenHeight: Float(size.height))
        entityUniforms = EntityUniforms(projectionMatrix: projectionMatrix)
    }
    
    @inline(__always)
    func colorFromBytes(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> SIMD4<Float> {
        let scale: Float = 1.0 / 255.0
        return SIMD4(Float(r) * scale, Float(g) * scale, Float(b) * scale, Float(a) * scale)
    }
    
    /// NOTE: offsets must be 256 byte aligned on iOS platforms. Hence we pad the structs to be factor of 256, and then modulo to figure out the offsets
    /// for the next starting index. We then store it for future reference. This has some over-head costs but is necessary in order to maintain the flexibility
    /// of interleaved draw calls across the pipelines.
    @inline(__always)
    private func addToDrawBatchAndGetAdjustedIndex(type: DrawBatchType, increment: Int) -> Int {
        var nextStartIndex: Int = nextStartIndexForTypePtr[type.rawValue]
        let batchIndex = drawBatchCount
        let curType = curDrawBatchType
        
        // Fast path: return early
        if curType == type {
            drawBatchesPtr[batchIndex - 1].count += increment
            nextStartIndexForTypePtr[type.rawValue] = nextStartIndex + increment
            return nextStartIndex
        }
        
        // Infrequent path: switching types
        let alignmentSize: Int = 256
        let alignmentCount = alignmentSize / strideSizesPtr[type.rawValue]
        let misalignment = nextStartIndex % alignmentCount
        
        if misalignment != 0 {
            nextStartIndex += alignmentCount - misalignment
        }
        assert(type == .atlas ? (nextStartIndex + increment) < atlasMaxInstanceCount : true)
        assert(type == .entity ? (nextStartIndex + increment) < entityMaxInstanceCount : true)
        assert(type == .text ? (nextStartIndex + increment) < textMaxVertexCount : true)
        
        curDrawBatchType = type
        drawBatchesPtr[batchIndex] = DrawBatch(type: type, startIndex: nextStartIndex, count: increment)
        drawBatchCount += 1
        
        nextStartIndexForTypePtr[type.rawValue] = nextStartIndex + increment
        return nextStartIndex
    }
    
    // MARK: - ATLAS DRAWING FUNCTIONS
    private func drawSprite(spriteName: String, x: Float, y: Float, width: Float, height: Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8, rotationRadians: Float = 0) {
        drawSprite(spriteName: spriteName, x: x, y: y, width: width, height: height, color: colorFromBytes(r: r, g: g, b: b, a: a), rotationRadians: rotationRadians)
    }
    private func drawSprite(spriteName: String, x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>, rotationRadians: Float = 0) {
        // TODO: Handle if from another atlas
        let index = addToDrawBatchAndGetAdjustedIndex(type: .atlas, increment: 1)
        let uvRect = mainAtlasUVRects[spriteName]!
        atlasInstancesPtr[index] = AtlasInstanceData(
            transform: projectionMatrix *
                float4x4(tx: x, ty: y) *
                float4x4(rotationZ: rotationRadians) *
                float4x4(scaleX: width, scaleY: height),
            color: color,
            uvMin: uvRect.minUV,
            uvMax: uvRect.maxUV)
        atlasInstanceCount += 1
    }
    
    // MARK: - PRIMITIVE DRAWING FUNCTIONS
    private func drawEntityCircle(x: Float, y: Float, radius: Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        drawEntityCircle(x: x, y: y, radius: radius, color: colorFromBytes(r: r, g: g, b: b, a: a))
    }
    private func drawEntityCircle(x: Float, y: Float, radius: Float, color: SIMD4<Float>) {
        let index = addToDrawBatchAndGetAdjustedIndex(type: .entity, increment: 1)
        entityInstancesPtr[index] = EntityInstanceData(
            transform: float4x4(tx: x, ty: y) * float4x4(scaleXY: (radius * 2)),
            color: color,
            shapeType: ShapeType.circle.rawValue,
            sdfParams: SIMD4<Float>(radius, 0.5, 0, 0) // hardcode edge softness to 0.5
        )
        entityInstanceCount += 1
    }
    
    private func drawEntityCircleLines(x: Float, y: Float, radius: Float, thickness:Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        drawEntityCircle(x: x, y: y, radius: radius, color: colorFromBytes(r: r, g: g, b: b, a: a))
    }
    private func drawEntityCircleLines(x: Float, y: Float, radius: Float, thickness:Float, color: SIMD4<Float>) {
        let index = addToDrawBatchAndGetAdjustedIndex(type: .entity, increment: 1)
        entityInstancesPtr[index] = EntityInstanceData(
            transform: float4x4(tx: x, ty: y) * float4x4(scaleXY: (radius * 2)),
            color: color,
            shapeType: ShapeType.circleLines.rawValue,
            sdfParams: SIMD4<Float>(radius, 0.5, thickness / 2.0, 0) // hardcode edge softness to 0.5
        )
        entityInstanceCount += 1
    }
    
    private func drawEntityLine(x1: Float, y1: Float, x2: Float, y2: Float, thickness: Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        drawEntityLine(x1: x1, y1: y1, x2: x2, y2: y2, thickness: thickness, color: colorFromBytes(r: r, g: g, b: b, a: a))
    }
    private func drawEntityLine(x1: Float, y1: Float, x2: Float, y2: Float, thickness: Float, color: SIMD4<Float>) {
        let dx = x2 - x1
        let dy = y2 - y1
        let length = sqrt(dx * dx + dy * dy)
        let angle = atan2(dy, dx)
        
        // Center between endpoints
        let cx = (x1 + x2) * 0.5
        let cy = (y1 + y2) * 0.5
        
        // Build transform: scale -> rotate -> translate
        // Multiply: translate * rotation * scale
        let transform = float4x4(tx: cx, ty: cy) *
        float4x4(rotationZ: angle) *
        float4x4(scaleX: length, scaleY: thickness)
        
        let index = addToDrawBatchAndGetAdjustedIndex(type: .entity, increment: 1)
        entityInstancesPtr[index] = EntityInstanceData(
            transform: transform,
            color: color,
            shapeType: ShapeType.rect.rawValue,
            sdfParams: SIMD4<Float>(0, 0, 0, 0)
        )
        entityInstanceCount += 1
    }
    
    private func drawEntityRect(x: Float, y: Float, width: Float, height: Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        drawEntityRect(x: x, y: y, width: width, height: height, color: colorFromBytes(r: r, g: g, b: b, a: a))
    }
    private func drawEntityRect(x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>) {
        let index = addToDrawBatchAndGetAdjustedIndex(type: .entity, increment: 1)
        entityInstancesPtr[index] = EntityInstanceData(
            transform: float4x4(tx: x + (width / 2.0), ty: y + (height / 2.0)) * float4x4(scaleX: width, scaleY: height),
            color: color,
            shapeType: ShapeType.rect.rawValue,
            sdfParams: SIMD4<Float>(0, 0, 0, 0) // not used for rects
        )
        entityInstanceCount += 1
    }
    
    private func drawEntityRoundedRect(x: Float, y: Float, width: Float, height: Float, cornerRadius: Float,
                                  r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        drawEntityRoundedRect(x: x, y: y, width: width, height: height, cornerRadius: cornerRadius,
                                 color: colorFromBytes(r: r, g: g, b: b, a: a))
    }
    private func drawEntityRoundedRect(x: Float, y: Float, width: Float, height: Float, cornerRadius: Float, color: SIMD4<Float>) {
        let halfWidth = width / 2.0
        let halfHeight = height / 2.0
        
        let index = addToDrawBatchAndGetAdjustedIndex(type: .entity, increment: 1)
        entityInstancesPtr[index] = EntityInstanceData(
            transform: float4x4(tx: x + halfWidth, ty: y + halfHeight) * float4x4(scaleX: width, scaleY: height),
            color: color,
            shapeType: ShapeType.roundedRect.rawValue,
            sdfParams: SIMD4<Float>(halfWidth, halfHeight, cornerRadius, 0)
        )
        entityInstanceCount += 1
    }
    
    private func drawEntityRectLines(x: Float, y: Float, width: Float, height: Float, thickness: Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        drawEntityRectLines(x: x, y: y, width: width, height: height, thickness: thickness, color: colorFromBytes(r: r, g: g, b: b, a: a))
    }
    private func drawEntityRectLines(x: Float, y: Float, width: Float, height: Float, thickness: Float, color: SIMD4<Float>) {
        let halfWidth = width / 2.0
        let halfHeight = height / 2.0
        
        let index = addToDrawBatchAndGetAdjustedIndex(type: .entity, increment: 1)
        entityInstancesPtr[index] = EntityInstanceData(
            transform: float4x4(tx: x + halfWidth, ty: y + halfHeight) * float4x4(scaleX: width, scaleY: height),
            color: color,
            shapeType: ShapeType.rectLines.rawValue,
            sdfParams: SIMD4<Float>(halfWidth, halfHeight, thickness, 0)
        )
        entityInstanceCount += 1
    }
    // MARK: - Text Drawing Functions
    private func drawText(text: String,
                  posX: Float, posY: Float,
                  fontSize: Float,
                  color: SIMD4<Float>) {
        
        // TODO: Assert precondition that not beyond certain point in text.
        guard !text.isEmpty else { return }
        
        let vertices = buildMesh(for: text, posX: posX, posY: posY, withSize: fontSize, color: color)
        guard !vertices.isEmpty else { return }
        
        let startIndex = addToDrawBatchAndGetAdjustedIndex(type: .text, increment: vertices.count)
        for index in 0..<vertices.count {
            textVertexBufferPtr[startIndex + index] = vertices[index]
        }
        textVertexCount += vertices.count
    }

    
    private func buildMesh(for text: String, posX: Float, posY: Float, withSize fontSize: Float, color: SIMD4<Float>) -> [TextVertex] {
        var vertices: [TextVertex] = []
        let atlasWidth = Float(fontAtlas.atlas.width)
        let atlasHeight = Float(fontAtlas.atlas.height)
        
        let scale = Float(fontSize) / Float(fontAtlas.metrics.emSize)
        let lineHeight = Float(fontAtlas.metrics.lineHeight) * scale
        let ascender = Float(fontAtlas.metrics.ascender) * scale
        
        var cursorX = posX
        var cursorY = posY - ascender // shift down so top of first line is at origin.y
        
        var previousChar: UInt32 = 0
        
        for char in text.unicodeScalars {
            if char == "\n" {
                cursorX = posX
                cursorY -= lineHeight
                previousChar = 0
                continue
            }
            
            let unicode = char.value
            
            // Kerning
            if previousChar != 0 {
                let key = (UInt64(previousChar) << 32) | UInt64(unicode)
                if let kern = fontKerning[key] {
                    cursorX += Float(kern.advance) * scale
                }
            }
            
            guard let glyph = fontGlyphs[unicode] else {
                previousChar = unicode
                continue
            }

            // Skip rendering, but still apply advance if glyph has no visible bounds (e.g. space)
            if let plane = glyph.planeBounds, let atlas = glyph.atlasBounds {
                let x0 = cursorX + Float(plane.left) * scale
                let y0 = cursorY + Float(plane.bottom) * scale
                let x1 = cursorX + Float(plane.right) * scale
                let y1 = cursorY + Float(plane.top) * scale

                let u0 = Float(atlas.left) / atlasWidth
                let u1 = Float(atlas.right) / atlasWidth
                let v0 = Float(atlasHeight - Float(atlas.top)) / atlasHeight
                let v1 = Float(atlasHeight - Float(atlas.bottom)) / atlasHeight

                let topLeft     = TextVertex(position: [x0, y1], uv: [u0, v0], textColor: color)
                let topRight    = TextVertex(position: [x1, y1], uv: [u1, v0], textColor: color)
                let bottomLeft  = TextVertex(position: [x0, y0], uv: [u0, v1], textColor: color)
                let bottomRight = TextVertex(position: [x1, y0], uv: [u1, v1], textColor: color)

                vertices.append(contentsOf: [
                    bottomLeft, bottomRight, topRight,
                    bottomLeft, topRight, topLeft
                ])
            }

            // Always apply advance even if glyph wasn't rendered (e.g. space)
            cursorX += Float(glyph.advance) * scale
            previousChar = unicode
        }
        
        return vertices
    }
    
    public func measureTextBounds(for text: String, withSize fontSize: Float) -> (width: Float, height: Float) {
        let scale = fontSize / Float(fontAtlas.metrics.emSize)
        let lineHeight = Float(fontAtlas.metrics.lineHeight) * scale
        
        var maxXInLine: Float = 0
        var maxLineWidth: Float = 0
        var cursorX: Float = 0
        var lineCount = 1
        
        var previousChar: UInt32 = 0
        
        for char in text.unicodeScalars {
            if char == "\n" {
                maxLineWidth = max(maxLineWidth, maxXInLine)
                cursorX = 0
                maxXInLine = 0
                lineCount += 1
                previousChar = 0
                continue
            }
            
            let unicode = char.value
            
            if previousChar != 0 {
                let key = (UInt64(previousChar) << 32) | UInt64(unicode)
                if let kern = fontKerning[key] {
                    cursorX += Float(kern.advance) * scale
                }
            }
            
            if let glyph = fontGlyphs[unicode] {
                // Even if no planeBounds, space still moves the cursor
                if let plane = glyph.planeBounds {
                    let glyphRight = cursorX + Float(plane.right) * scale
                    maxXInLine = max(maxXInLine, glyphRight)
                } else {
                    // Approximate advance-only glyphs to still extend line length
                    let glyphRight = cursorX + Float(glyph.advance) * scale
                    maxXInLine = max(maxXInLine, glyphRight)
                }
                
                cursorX += Float(glyph.advance) * scale
            }
            
            previousChar = unicode
        }
        
        let textWidth = max(maxLineWidth, maxXInLine)
        let textHeight = Float(lineCount) * lineHeight
        
        return (textWidth, textHeight)
    }
}

// MARK: - Math Helpers
extension float4x4 {
    init(tx: Float, ty: Float) {
        self = matrix_identity_float4x4
        columns.3.x = tx
        columns.3.y = ty
    }
    
    init (scaleX: Float, scaleY: Float) {
        self = matrix_identity_float4x4
        columns.0.x = scaleX
        columns.1.y = scaleY
        columns.2.z = 1.0
    }
    
    init (scaleXY: Float) {
        self = matrix_identity_float4x4
        columns.0.x = scaleXY
        columns.1.y = scaleXY
        columns.2.z = 1.0
    }

    init(rotationZ angle: Float) {
        self = matrix_identity_float4x4
        columns.0.x = cos(angle)
        columns.0.y = sin(angle)
        columns.1.x = -sin(angle)
        columns.1.y = cos(angle)
    }
    
    static func pixelSpaceProjection(screenWidth: Float, screenHeight: Float) -> float4x4 {
        let scaleX = 2.0 / screenWidth
        let scaleY = 2.0 / screenHeight
        return float4x4(columns: (
            SIMD4<Float>( scaleX,      0, 0, 0),
            SIMD4<Float>(     0,  scaleY, 0, 0),
            SIMD4<Float>(     0,      0, 1, 0),
            SIMD4<Float>(     0,      0, 0, 1)
        ))
    }
}

// MARK: - Font Atlas Structs
struct FontAtlas: Codable {
    let atlas: AtlasMetrics
    let metrics: FontMetrics
    let glyphs: [Glyph]
    let kerning: [Kerning]
}

struct AtlasMetrics: Codable {
    let type: String
    let distanceRange: Float
    let size: Float
    let width: Int
    let height: Int
    let yOrigin: String
}

struct FontMetrics: Codable {
    let emSize: Float
    let lineHeight: Float
    let ascender: Float
    let descender: Float
    let underlineY: Float
    let underlineThickness: Float
}

struct Glyph: Codable {
    let unicode: Int
    let advance: Float
    let planeBounds: Bounds?
    let atlasBounds: Bounds?
}

struct Bounds: Codable {
    let left: Float
    let bottom: Float
    let right: Float
    let top: Float
}

struct Kerning: Codable {
    let unicode1: Int
    let unicode2: Int
    let advance: Float
}
