//
//  Renderer.swift
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 25/7/25.
//

// Our platform independent renderer class

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
    var colorRGB: SIMD3<Float> // TODO: Make this RGBA?
}

class Renderer: NSObject, MTKViewDelegate {
    var projectionMatrix = float4x4(1)
    var screenSize: CGSize = .zero
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    // MARK: - ATLAS PIPELINE VARS
    var atlasPipelineState: MTLRenderPipelineState!
    
    var atlasVertexBuffer: MTLBuffer!
    var atlasInstanceBuffer: MTLBuffer!
    var atlasInstanceData: [AtlasInstanceData] = []
    let atlasMaxInstanceCount = 1000
    var atlasInstanceCount = 0

    let atlasAquareVertices: [AtlasVertex] = [
        AtlasVertex(position: [-0.5, -0.5], uv: [0, 1]),
        AtlasVertex(position: [ 0.5, -0.5], uv: [1, 1]),
        AtlasVertex(position: [-0.5,  0.5], uv: [0, 0]),
        AtlasVertex(position: [ 0.5,  0.5], uv: [1, 0]),
    ]
    
    // TODO: Create a system where you can draw stuff batched by atlas texture. 1 draw call per atlas tex.
    var mainAtlasTexture: MTLTexture!
    var mainAtlasUVRects: [String: AtlasUVRect] = [:]
    
    // MARK: - PRIMITIVE PIPELINE VARs
    var primitivePipelineState: MTLRenderPipelineState!
    var primitiveVertexBuffer: MTLBuffer!
    
    // TODO: Convert this into index vertices and all that.
    // TODO: Then create all the other fancy stuff like draw circles / rects / lines
    let primitiveVertices: [PrimitiveVertex] = [
        PrimitiveVertex(position: [0, 0.5], colorRGB: [0, 0, 1]),
        PrimitiveVertex(position: [-0.5, -0.5], colorRGB: [1, 1, 1]),
        PrimitiveVertex(position: [0.5, -0.5], colorRGB: [1, 0, 0])
    ]

    // MARK: - GAME RELATED
    var time: Float = 0

    init(mtkView: MTKView) {
        guard let device = mtkView.device else {
            fatalError("Unable to obtain MTLDevice from MTKView")
        }
        
        guard let cmdQueue = device.makeCommandQueue() else {
            fatalError("Unable to obtain MTLCommandQueue from MTLDevice")
        }
        
        self.device = device
        self.commandQueue = cmdQueue

        super.init()
        buildAtlasPipeline(mtkView: mtkView)
        buildAtlasBuffers()
        
        buildPrimitivePipeline(mtkView: mtkView)
        buildPrimitiveBuffers()
        
        let texture = loadTexture(device: device, name: "main_atlas")
        self.mainAtlasTexture = texture
        
        let atlasUVs = loadAtlasUV(named: "main_atlas", textureWidth: 256, textureHeight: 256)
        self.mainAtlasUVRects = atlasUVs
    }

    func buildAtlasPipeline(mtkView: MTKView) {
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
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = 0
        
        // UV
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[1].offset = MemoryLayout<AtlasVertex>.offset(of: \.uv)!
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<AtlasVertex>.stride
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        

        
        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            fatalError("Unable to create render pipeline state")
        }
        self.atlasPipelineState = pipelineState
    }
    
    func buildPrimitivePipeline(mtkView: MTKView) {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Unable to get default library")
        }
        
        let primitivePipelineDescriptor = MTLRenderPipelineDescriptor()
        primitivePipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_primitive")
        primitivePipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_primitive")
        primitivePipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        
        guard let primitivePipelineState = try? device.makeRenderPipelineState(descriptor: primitivePipelineDescriptor) else {
            fatalError("Unable to create render pipeline state")
        }
        self.primitivePipelineState = primitivePipelineState
    }
    
    func buildAtlasBuffers() {
        atlasVertexBuffer = device.makeBuffer(bytes: atlasAquareVertices,
                                         length: atlasAquareVertices.count * MemoryLayout<AtlasVertex>.stride,
                                         options: [])

        // Preallocate instance data array (will update it per-frame)
        atlasInstanceData = Array(repeating:
                                AtlasInstanceData(
                                    transform: matrix_identity_float4x4,
                                    color: .zero,
                                    uvMin: SIMD2<Float>.zero,
                                    uvMax: SIMD2<Float>.zero
                                ),
                             count: atlasMaxInstanceCount)

        atlasInstanceBuffer = device.makeBuffer(length: atlasMaxInstanceCount * MemoryLayout<AtlasInstanceData>.stride,
                                           options: [])
    }
    
    func buildPrimitiveBuffers() {
        guard let primitiveVertexBuffer = device.makeBuffer(bytes: primitiveVertices,
                                                            length: MemoryLayout<PrimitiveVertex>.stride * primitiveVertices.count,
                                                            options: []) else {
            fatalError("Could not create the vertex buffer")
        }
        
        self.primitiveVertexBuffer = primitiveVertexBuffer
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


    
    func updateInstanceData() {
        // For test: oscillate count between 0 and 100
        atlasInstanceCount = Int((sin(time * 2.0) + 1.0) / 2.0 * 100)
        atlasInstanceCount = min(atlasInstanceCount, atlasMaxInstanceCount)

        for i in 0..<atlasInstanceCount {
            let angle = time + Float(i) * (2 * .pi / Float(atlasInstanceCount))
            let radius: Float = Float(screenSize.width) / 3.0

            let x = cos(angle) * radius
            let y = sin(angle) * radius
            let rotation = float4x4(rotationZ: angle * 2)
            let scale = float4x4(scaling: SIMD3<Float>(repeating: 100.0 + 100.0 * sin(angle)))
            let translation = float4x4(translation: [x, y, 0])

            let transform = translation * rotation * scale
            let color = SIMD4<Float>(
                0.5 + 0.5 * sin(angle),
                0.5 + 0.5 * cos(angle),
                0.5 + 0.5 * sin(angle * 0.5),
                1.0
            )

            let spriteName = "Circle_White"
            let uvRect = mainAtlasUVRects[spriteName]!
            atlasInstanceData[i] = AtlasInstanceData(
                transform: projectionMatrix * transform,
                color: color,
                uvMin: uvRect.minUV,
                uvMax: uvRect.maxUV
            )
        }
        
        { // Test anything static here, replaces the last instance count
            let spriteName = "player_1"
            let uvRect = mainAtlasUVRects[spriteName]!
            let index = max(0, atlasInstanceCount - 1)
            atlasInstanceData[index] = AtlasInstanceData(
                transform: projectionMatrix * float4x4(translation: [100, 100, 0]) * float4x4(scaling: [256, 256, 1]),
                color: SIMD4<Float>(1, 1, 1, 1),
                uvMin: uvRect.minUV,
                uvMax: uvRect.maxUV
            )
        }()
    }


    // MARK: - DRAW FUNCTION
    func draw(in view: MTKView) {
        // TODO: Does this actually happen? Maybe it does, so maybe it's not to throw error here.
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }

        time += 1.0 / Float(view.preferredFramesPerSecond)
        updateInstanceData()
        memcpy(atlasInstanceBuffer.contents(), atlasInstanceData, atlasInstanceCount * MemoryLayout<AtlasInstanceData>.stride)

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        // MARK: - ATLAS PIPELINE
        encoder.setRenderPipelineState(atlasPipelineState)
        encoder.setVertexBuffer(atlasVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(atlasInstanceBuffer, offset: 0, index: 1)
        
        // Load Main Texture at tex buffer 0.
        encoder.setFragmentTexture(mainAtlasTexture, index: 0)
        
        // Load TexSampler at sampler buffer 0.
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        let samplerState = device.makeSamplerState(descriptor: samplerDescriptor)!
        encoder.setFragmentSamplerState(samplerState, index: 0)

        if atlasInstanceCount > 0 {
            encoder.drawPrimitives(type: .triangleStrip,
                                   vertexStart: 0,
                                   vertexCount: atlasAquareVertices.count,
                                   instanceCount: atlasInstanceCount)
        }

        // MARK: - PRIMITIVE PIPELINE
        encoder.setRenderPipelineState(primitivePipelineState)
        encoder.setVertexBuffer(primitiveVertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        
        encoder.endEncoding()
        
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("drawableSizeWillChange called, \(size.debugDescription)")
        screenSize = size
        projectionMatrix = float4x4.pixelSpaceProjection(screenWidth: Float(size.width), screenHeight: Float(size.height))
    }
}

// MARK: - Math Helpers

extension float4x4 {
    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
    }

    init(scaling s: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.0.x = s.x
        columns.1.y = s.y
        columns.2.z = s.z
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
