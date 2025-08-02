//
//  Renderer.swift
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 25/7/25.
//

import MetalKit

struct AtlasVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

struct AtlasInstanceData {
    var transform: simd_float4x4
    var color: SIMD4<Float>
    var uvMin: SIMD2<Float>
    var uvMax: SIMD2<Float>
}

struct AtlasUVRect {
    var minUV: SIMD2<Float> // bottom-left
    var maxUV: SIMD2<Float> // top-right
}

struct PrimitiveVertex {
    var position: SIMD2<Float>
}

struct PrimitiveUniforms {
    var projectionMatrix: float4x4
}

struct PrimitiveInstanceData {
    var transform: simd_float4x4
    var color: SIMD4<Float>
    var shapeType: Int
    var sdfParams: SIMD4<Float>
}

let maxBuffersInFlight = 3

class Renderer: NSObject, MTKViewDelegate {
    var projectionMatrix = matrix_identity_float4x4
    var screenSize: CGSize = .zero
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var textRenderer: TextRenderer!

    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    var triBufferIndex = 0
    
    // MARK: - ATLAS PIPELINE VARS
    var atlasPipelineState: MTLRenderPipelineState
    var atlasVertexBuffer: MTLBuffer
    var atlasTriInstanceBuffer: MTLBuffer
    var atlasTriInstanceBufferOffset = 0
    var atlasInstancesPtr: UnsafeMutablePointer<AtlasInstanceData>
    let atlasMaxInstanceCount = 50000
    var atlasInstanceCount = 0
    
    let atlasSquareVertices: [AtlasVertex] = [
        AtlasVertex(position: [-0.5, -0.5], uv: [0, 1]),
        AtlasVertex(position: [ 0.5, -0.5], uv: [1, 1]),
        AtlasVertex(position: [-0.5,  0.5], uv: [0, 0]),
        AtlasVertex(position: [ 0.5,  0.5], uv: [1, 0]),
    ]
    
    // TODO: Use Arguement buffers to pass multiple texture atlasses?
    var mainAtlasTexture: MTLTexture!
    var mainAtlasUVRects: [String: AtlasUVRect] = [:]
    var atlasSamplerState: MTLSamplerState
    
    
    
    // MARK: - PRIMITIVE PIPELINE VARs
    var primitivePipelineState: MTLRenderPipelineState
    var primitiveVertexBuffer: MTLBuffer
    var primitiveTriInstanceBuffer: MTLBuffer
    var primitiveTriInstanceBufferOffset = 0
    var primitiveInstancesPtr: UnsafeMutablePointer<PrimitiveInstanceData>
    let primitiveMaxInstanceCount = 50000
    var primitiveInstanceCount = 0
    
    let primitiveSquareVertices: [PrimitiveVertex] = [
        PrimitiveVertex(position: [-0.5, -0.5]),
        PrimitiveVertex(position: [0.5, -0.5]),
        PrimitiveVertex(position: [-0.5, 0.5]),
        PrimitiveVertex(position: [0.5, 0.5])
    ]
    
    var primitiveUniforms = PrimitiveUniforms(projectionMatrix: matrix_identity_float4x4)
    
    
    // MARK: - GAME RELATED
    var time: Float = 0
    
    init(mtkView: MTKView, textRenderer: TextRenderer) {
        self.textRenderer = textRenderer
        
        guard let device = mtkView.device else { fatalError("Unable to obtain MTLDevice from MTKView") }
        self.device = device
        guard let cmdQueue = device.makeCommandQueue() else { fatalError("Unable to obtain MTLCommandQueue from MTLDevice") }
        self.commandQueue = cmdQueue
        
        // MARK: - Build Atlas Buffers
        guard let atlasVertexBuffer = device.makeBuffer(
            bytes: atlasSquareVertices,
            length: atlasSquareVertices.count * MemoryLayout<AtlasVertex>.stride,
            options: []) else { fatalError("Unable to create vertex buffer for atlas") }
        self.atlasVertexBuffer = atlasVertexBuffer
        
        let atlasTriInstanceBufferSize = MemoryLayout<AtlasInstanceData>.stride * atlasMaxInstanceCount * maxBuffersInFlight
        guard let atlasTriInstanceBuffer = device.makeBuffer(
            length: atlasTriInstanceBufferSize,
            options: [MTLResourceOptions.storageModeShared]) else { fatalError("Unable to create tri instance buffer for atlas") }
        self.atlasTriInstanceBuffer = atlasTriInstanceBuffer
        self.atlasTriInstanceBuffer.label = "Atlas Tri Instance Buffer"
        
        self.atlasInstancesPtr = UnsafeMutableRawPointer(atlasTriInstanceBuffer.contents())
            .bindMemory(to: AtlasInstanceData.self, capacity: atlasMaxInstanceCount)
        
        // MARK: - Build Primitive Buffers
        guard let primitiveVertexBuffer = device.makeBuffer(
            bytes: primitiveSquareVertices,
            length: primitiveSquareVertices.count * MemoryLayout<PrimitiveVertex>.stride,
            options: []) else { fatalError("Unabled to create vertex buffer for primitives") }
        self.primitiveVertexBuffer = primitiveVertexBuffer
        
        let primitiveTriInstanceBufferSize = MemoryLayout<PrimitiveInstanceData>.stride * primitiveMaxInstanceCount * maxBuffersInFlight
        guard let primitiveTriInstanceBuffer = device.makeBuffer(
            length: primitiveTriInstanceBufferSize,
            options: [MTLResourceOptions.storageModeShared]) else { fatalError("Unable to create tri instance buffer for primitives") }
        self.primitiveTriInstanceBuffer = primitiveTriInstanceBuffer
        self.primitiveTriInstanceBuffer.label = "Primitive Tri Instance Buffer"
        
        self.primitiveInstancesPtr = UnsafeMutableRawPointer(primitiveTriInstanceBuffer.contents())
            .bindMemory(to: PrimitiveInstanceData.self, capacity: primitiveMaxInstanceCount)
        
        // MARK: - Build Pipelines & Descriptors & Misc
        self.atlasPipelineState = Renderer.buildAtlasPipeline(device: device, mtkView: mtkView)
        self.primitivePipelineState = Renderer.buildPrimitivePipeline(device: device, mtkView: mtkView)
        let atlasSamplerDescriptor = MTLSamplerDescriptor()
        atlasSamplerDescriptor.minFilter = .linear
        atlasSamplerDescriptor.magFilter = .linear
        atlasSamplerDescriptor.mipFilter = .linear
        guard let atlasSamplerState = device.makeSamplerState(descriptor: atlasSamplerDescriptor) else { fatalError("Unabled to create atlas sampler state") }
        self.atlasSamplerState = atlasSamplerState
        
        
        super.init()
        
        // MARK: - Load Textures
        let texture = loadTexture(device: device, name: "main_atlas")
        self.mainAtlasTexture = texture
        
        let atlasUVs = loadAtlasUV(named: "main_atlas", textureWidth: 256, textureHeight: 256)
        self.mainAtlasUVRects = atlasUVs
    }
    
    class func buildAtlasPipeline(device: MTLDevice, mtkView: MTKView) -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Unable to get default library")
        }
        
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
        
        // MARK: - VERTEX DESCRIPTOR
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
            fatalError("Unable to create render pipeline state")
        }
        return atlasPipelineState
    }
    
    class func buildPrimitivePipeline(device: MTLDevice, mtkView: MTKView) -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Unable to get default library")
        }
        
        let primitivePipelineDescriptor = MTLRenderPipelineDescriptor()
        primitivePipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_primitive")
        primitivePipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_primitive")
        
        // Enable alpha blending
        let colorAttachment = primitivePipelineDescriptor.colorAttachments[0]!
        colorAttachment.pixelFormat = mtkView.colorPixelFormat
        colorAttachment.isBlendingEnabled = true
        colorAttachment.rgbBlendOperation = .add
        colorAttachment.alphaBlendOperation = .add
        colorAttachment.sourceRGBBlendFactor = .sourceAlpha
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        guard let primitivePipelineState = try? device.makeRenderPipelineState(descriptor: primitivePipelineDescriptor) else {
            fatalError("Unable to create render pipeline state")
        }
        return primitivePipelineState
    }
    
    private func updateTriBufferStates() {
        triBufferIndex = (triBufferIndex + 1) % maxBuffersInFlight
        
        atlasTriInstanceBufferOffset = MemoryLayout<AtlasInstanceData>.stride * atlasMaxInstanceCount * triBufferIndex
        atlasInstancesPtr = UnsafeMutableRawPointer(atlasTriInstanceBuffer.contents()).advanced(by: atlasTriInstanceBufferOffset).bindMemory(to: AtlasInstanceData.self, capacity: atlasMaxInstanceCount)
        
        primitiveTriInstanceBufferOffset = MemoryLayout<PrimitiveInstanceData>.stride * primitiveMaxInstanceCount * triBufferIndex
        primitiveInstancesPtr = UnsafeMutableRawPointer(primitiveTriInstanceBuffer.contents()).advanced(by: primitiveTriInstanceBufferOffset).bindMemory(to: PrimitiveInstanceData.self, capacity: primitiveMaxInstanceCount)
    }
    
    func loadTexture(device: MTLDevice, name: String) -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: device)
        let url = Bundle.main.url(forResource: name, withExtension: "png")!
        let options: [MTKTextureLoader.Option: Any] = [.SRGB: false]
        
        do {
            return try textureLoader.newTexture(URL: url, options: options)
        } catch {
            fatalError("Failed to load texture: \(error)")
        }
    }
    
    func loadAtlasUV(named filename: String, textureWidth: Float, textureHeight: Float) -> [String: AtlasUVRect] {
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
    
    func updateAtlasInstanceData() {
        // For test: oscillate count between 0 and testMaxCount
        let testMaxCount: Float = 1//100
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
    
    func drawPrimitives() {
        // TEST: Draw many primitive circles
        let circleCount = 1//1000
        var rng = FastRandom(seed: UInt64(time * 1000000))
        var color = SIMD4<Float>.zero
        
        for _ in 0..<circleCount {
            let x = rng.nextFloat(min: Float(-screenSize.width), max: Float(screenSize.width))
            let y = rng.nextFloat(min: Float(-screenSize.height), max: Float(screenSize.height))
            let radius = rng.nextFloat(min: 5, max: 25)
            
            color.x = rng.nextUnitFloat()
            color.y = rng.nextUnitFloat()
            color.z = rng.nextUnitFloat()
            color.w = 1.0
            
            drawPrimitiveCircle(x: x, y: y, radius: radius, color: color)
        }
        
        //        drawPrimitiveCircle(x: 0, y: 0, radius: 800.0, r: 255, g: 255, b: 255, a: 64)
        //        drawPrimitiveCircle(x: 0, y: 0, radius: 512.0, r: 0, g: 255, b: 255, a: 64)
        //        drawPrimitiveCircle(x: 0, y: 0, radius: 256.0, r: 255, g: 0, b: 255, a: 64)
        //        drawPrimitiveCircle(x: 256, y: 256, radius: 128.0, r: 255, g: 0, b: 0, a: 64)
        //        drawPrimitiveCircle(x: 0, y: 0, radius: 128.0, r: 0, g: 255, b: 0, a: 64)
        //        drawPrimitiveCircle(x: -256, y: -256, radius: 128.0, r: 0, g: 0, b: 255, a: 64)
        //        drawPrimitiveLine(x1: -800, y1: -600, x2: 800, y2: 600, thickness: 10, r: 200, g: 100, b: 0, a: 128)
        //        drawPrimitiveRectLines(x: 0, y: 0, width: 800, height: 600, thickness: 48, r: 0, g: 255, b: 255, a: 255)
        //        drawPrimitiveRect(x: 0, y: 0, width: 800, height: 600, r: 255, g: 0, b: 0, a: 64)
        //        drawPrimitiveRect(x: -800, y: -600, width: 800, height: 600, r: 255, g: 0, b: 0, a: 64)
        //        drawPrimitiveRect(x: 0, y: 0, width: 24, height: 600, r: 255, g: 0, b: 0, a: 64)
        //        drawPrimitiveRect(x: 0, y: 0, width: 128, height: 196, r: 0, g: 255, b: 0, a: 128)
        //        drawPrimitiveRect(x: -800, y: -600, width: 800, height: 600, r: 128, g: 255, b: 0, a: 128)
        //        drawPrimitiveRect(x: -800, y: -600, width: 1600, height: 1200, r: 0, g: 255, b: 255, a: 32)
        //        drawPrimitiveRoundedRect(x: 0, y: 0, width: 800, height: 600, cornerRadius: 100, r: 0, g: 0, b: 255, a: 255)
        //        drawPrimitiveRoundedRect(x: 0, y: 0, width: 800, height: 100, cornerRadius: 100, r: 0, g: 255, b: 255, a: 255)
        //        drawPrimitiveCircle(x: 100, y: 100, radius: 100, r: 255, g: 0, b: 0, a: 128)
        //        drawPrimitiveRect(x: -600, y: -600, width: 1200, height: 1200, r: 255, g: 0, b: 255, a: 255)
        //        drawPrimitiveCircle(x: 0, y: 0, radius: 600, r: 255, g: 255, b: 255, a: 255)
        //        drawPrimitiveCircleLines(x: 0, y: 0, radius: 600, thickness: 48, r: 255, g: 0, b: 255, a: 128)
        //        drawPrimitiveRect(x: -600, y:-600, width: 48, height: 1200, r: 0, g: 255, b: 0, a: 128)
    }
    
    func updateGameState() {
        atlasInstanceCount = 0
        primitiveInstanceCount = 0
        
        updateAtlasInstanceData()
        drawPrimitives()
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
            
            time += 1.0 / Float(view.preferredFramesPerSecond)
            self.updateGameState()
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            if let renderPassDescriptor = renderPassDescriptor, let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                encoder.label = "Primary Render Encoder"
                
                // MARK: - ATLAS PIPELINE
                if atlasInstanceCount > 0 {
                    encoder.setRenderPipelineState(atlasPipelineState)
                    encoder.setVertexBuffer(atlasVertexBuffer, offset: 0, index: BufferIndex.vertices.rawValue)
                    encoder.setVertexBuffer(atlasTriInstanceBuffer, offset: atlasTriInstanceBufferOffset, index: BufferIndex.instances.rawValue)
                    
                    // Load Main Texture at tex buffer 0.
                    encoder.setFragmentTexture(mainAtlasTexture, index: 0)
                    
                    // Load TexSampler at sampler buffer 0.
                    encoder.setFragmentSamplerState(atlasSamplerState, index: 0)
                    
                    encoder.drawPrimitives(type: .triangleStrip,
                                           vertexStart: 0,
                                           vertexCount: atlasSquareVertices.count,
                                           instanceCount: atlasInstanceCount)
                }
                
                // MARK: - PRIMITIVE PIPELINE
                if primitiveInstanceCount > 0 { // Only do if there are primitives to draw
                    encoder.setRenderPipelineState(primitivePipelineState)
                    encoder.setVertexBuffer(primitiveVertexBuffer, offset: 0, index: BufferIndex.vertices.rawValue)
                    encoder.setVertexBuffer(primitiveTriInstanceBuffer, offset: primitiveTriInstanceBufferOffset, index: BufferIndex.instances.rawValue)
                    encoder.setVertexBytes(&primitiveUniforms, length: MemoryLayout<PrimitiveUniforms>.stride, index: BufferIndex.uniforms.rawValue)
                    encoder.drawPrimitives(type: .triangleStrip,
                                           vertexStart: 0,
                                           vertexCount: primitiveSquareVertices.count,
                                           instanceCount: primitiveInstanceCount)
                }
                
                // MARK: - TEXT RENDERING
                let now = Date().timeIntervalSince1970
                let text = "Hello, SDF World! \(Int(now))"
                let color: SIMD4<Float> = [0.9, 0.9, 0.1, 1.0] // Yellow
                
                // TODO: Maybe need to pass in the encoder here instead.
                textRenderer.draw(
                    text: text,
                    at: [-Float(screenSize.width / 2.0) + 50, Float(screenSize.height / 2.0) - 100],      // X, Y position
                    withSize: 96,       // Font size in points/pixels
                    color: color,
                    projectionMatrix: projectionMatrix,
                    on: encoder
                )
                
                encoder.endEncoding()
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
            }
            
            commandBuffer.commit()
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("drawableSizeWillChange called, \(size.debugDescription)")
        screenSize = size
        projectionMatrix = float4x4.pixelSpaceProjection(screenWidth: Float(size.width), screenHeight: Float(size.height))
        primitiveUniforms = PrimitiveUniforms(projectionMatrix: projectionMatrix)
    }
    
    @inline(__always)
    func colorFromBytes(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> SIMD4<Float> {
        let scale: Float = 1.0 / 255.0
        return SIMD4(Float(r) * scale, Float(g) * scale, Float(b) * scale, Float(a) * scale)
    }
    
    // MARK: - ATLAS DRAWING FUNCTIONS
    func drawSprite(spriteName: String, x: Float, y: Float, width: Float, height: Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8, rotationRadians: Float = 0) {
        drawSprite(spriteName: spriteName, x: x, y: y, width: width, height: height, color: colorFromBytes(r: r, g: g, b: b, a: a), rotationRadians: rotationRadians)
    }
    func drawSprite(spriteName: String, x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>, rotationRadians: Float = 0) {
        // TODO: Handle if from another atlas
        let uvRect = mainAtlasUVRects[spriteName]!
        atlasInstancesPtr[atlasInstanceCount] = AtlasInstanceData(
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
    func drawPrimitiveCircle(x: Float, y: Float, radius: Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        drawPrimitiveCircle(x: x, y: y, radius: radius, color: colorFromBytes(r: r, g: g, b: b, a: a))
    }
    func drawPrimitiveCircle(x: Float, y: Float, radius: Float, color: SIMD4<Float>) {
        primitiveInstancesPtr[primitiveInstanceCount] = PrimitiveInstanceData(
            transform: float4x4(tx: x, ty: y) * float4x4(scaleXY: (radius * 2)),
            color: color,
            shapeType: ShapeType.circle.rawValue,
            sdfParams: SIMD4<Float>(radius, 0.5, 0, 0) // hardcode edge softness to 0.5
        )
        primitiveInstanceCount += 1
    }
    
    func drawPrimitiveCircleLines(x: Float, y: Float, radius: Float, thickness:Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        drawPrimitiveCircle(x: x, y: y, radius: radius, color: colorFromBytes(r: r, g: g, b: b, a: a))
    }
    func drawPrimitiveCircleLines(x: Float, y: Float, radius: Float, thickness:Float, color: SIMD4<Float>) {
        primitiveInstancesPtr[primitiveInstanceCount] = PrimitiveInstanceData(
            transform: float4x4(tx: x, ty: y) * float4x4(scaleXY: (radius * 2)),
            color: color,
            shapeType: ShapeType.circleLines.rawValue,
            sdfParams: SIMD4<Float>(radius, 0.5, thickness / 2.0, 0) // hardcode edge softness to 0.5
        )
        primitiveInstanceCount += 1
    }
    
    func drawPrimitiveLine(x1: Float, y1: Float, x2: Float, y2: Float, thickness: Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        drawPrimitiveLine(x1: x1, y1: y1, x2: x2, y2: y2, thickness: thickness, color: colorFromBytes(r: r, g: g, b: b, a: a))
    }
    func drawPrimitiveLine(x1: Float, y1: Float, x2: Float, y2: Float, thickness: Float, color: SIMD4<Float>) {
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
        
        primitiveInstancesPtr[primitiveInstanceCount] = PrimitiveInstanceData(
            transform: transform,
            color: color,
            shapeType: ShapeType.rect.rawValue,
            sdfParams: SIMD4<Float>(0, 0, 0, 0)
        )
        primitiveInstanceCount += 1
    }
    
    func drawPrimitiveRect(x: Float, y: Float, width: Float, height: Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        drawPrimitiveRect(x: x, y: y, width: width, height: height, color: colorFromBytes(r: r, g: g, b: b, a: a))
    }
    func drawPrimitiveRect(x: Float, y: Float, width: Float, height: Float, color: SIMD4<Float>) {
        let instance = PrimitiveInstanceData(
            transform: float4x4(tx: x + (width / 2.0), ty: y + (height / 2.0)) * float4x4(scaleX: width, scaleY: height),
            color: color,
            shapeType: ShapeType.rect.rawValue,
            sdfParams: SIMD4<Float>(0, 0, 0, 0) // not used for rects
        )
        
        primitiveInstancesPtr[primitiveInstanceCount] = instance
        primitiveInstanceCount += 1
    }
    
    func drawPrimitiveRoundedRect(x: Float, y: Float, width: Float, height: Float, cornerRadius: Float,
                                  r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        drawPrimitiveRoundedRect(x: x, y: y, width: width, height: height, cornerRadius: cornerRadius,
                                 color: colorFromBytes(r: r, g: g, b: b, a: a))
    }
    func drawPrimitiveRoundedRect(x: Float, y: Float, width: Float, height: Float, cornerRadius: Float, color: SIMD4<Float>) {
        let halfWidth = width / 2.0
        let halfHeight = height / 2.0
        
        primitiveInstancesPtr[primitiveInstanceCount] = PrimitiveInstanceData(
            transform: float4x4(tx: x + halfWidth, ty: y + halfHeight) * float4x4(scaleX: width, scaleY: height),
            color: color,
            shapeType: ShapeType.roundedRect.rawValue,
            sdfParams: SIMD4<Float>(halfWidth, halfHeight, cornerRadius, 0)
        )
        primitiveInstanceCount += 1
    }
    
    func drawPrimitiveRectLines(x: Float, y: Float, width: Float, height: Float, thickness: Float, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        drawPrimitiveRectLines(x: x, y: y, width: width, height: height, thickness: thickness, color: colorFromBytes(r: r, g: g, b: b, a: a))
    }
    func drawPrimitiveRectLines(x: Float, y: Float, width: Float, height: Float, thickness: Float, color: SIMD4<Float>) {
        let halfWidth = width / 2.0
        let halfHeight = height / 2.0
        
        primitiveInstancesPtr[primitiveInstanceCount] = PrimitiveInstanceData(
            transform: float4x4(tx: x + halfWidth, ty: y + halfHeight) * float4x4(scaleX: width, scaleY: height),
            color: color,
            shapeType: ShapeType.rectLines.rawValue,
            sdfParams: SIMD4<Float>(halfWidth, halfHeight, thickness, 0)
        )
        primitiveInstanceCount += 1
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
