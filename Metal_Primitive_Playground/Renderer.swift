//
//  Renderer.swift
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 25/7/25.
//

// Our platform independent renderer class

import MetalKit

struct Vertex {
    var position: SIMD2<Float>
}

struct InstanceData {
    var transform: simd_float4x4
    var color: SIMD4<Float>
    // TODO: Texture & UVs?
}

class Renderer: NSObject, MTKViewDelegate {
    var projectionMatrix = float4x4(1)
    var screenSize: CGSize = .zero
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!

    var vertexBuffer: MTLBuffer!
    var instanceBuffer: MTLBuffer!
    var instanceData: [InstanceData] = []
    let maxInstanceCount = 1000
    var instanceCount = 0

    let squareVertices: [Vertex] = [
        Vertex(position: [-0.5, -0.5]),
        Vertex(position: [ 0.5, -0.5]),
        Vertex(position: [-0.5,  0.5]),
        Vertex(position: [ 0.5,  0.5]),
    ]

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
        buildPipeline(mtkView: mtkView)
        buildBuffers()
    }

    func buildPipeline(mtkView: MTKView) {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Unable to get default library")
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        
        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            fatalError("Unable to create render pipeline state")
        }
        self.pipelineState = pipelineState
    }
    
    func buildBuffers() {
        vertexBuffer = device.makeBuffer(bytes: squareVertices,
                                         length: squareVertices.count * MemoryLayout<Vertex>.stride,
                                         options: [])

        // Preallocate instance data array (will update it per-frame)
        instanceData = Array(repeating: InstanceData(transform: matrix_identity_float4x4, color: .zero),
                             count: maxInstanceCount)

        instanceBuffer = device.makeBuffer(length: maxInstanceCount * MemoryLayout<InstanceData>.stride,
                                           options: [])
    }
    
    func updateInstanceData() {
        // For test: oscillate count between 0 and 100
        instanceCount = Int((sin(time * 2.0) + 1.0) / 2.0 * 100)
        instanceCount = min(instanceCount, maxInstanceCount)

        for i in 0..<instanceCount {
            let angle = time + Float(i) * (2 * .pi / Float(instanceCount))
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

            instanceData[i] = InstanceData(transform: projectionMatrix * transform, color: color)
        }
    }


    func draw(in view: MTKView) {
        // TODO: Does this actually happen? Maybe it does, so maybe it's not to throw error here.
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }

        time += 1.0 / Float(view.preferredFramesPerSecond)

        updateInstanceData()
        memcpy(instanceBuffer.contents(), instanceData, instanceCount * MemoryLayout<InstanceData>.stride)

        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)

        if instanceCount > 0 {
            encoder.drawPrimitives(type: .triangleStrip,
                                   vertexStart: 0,
                                   vertexCount: squareVertices.count,
                                   instanceCount: instanceCount)
        }

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
