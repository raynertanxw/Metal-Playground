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
}

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!

    var vertexBuffer: MTLBuffer!
    var instanceBuffer: MTLBuffer!

    let squareVertices: [Vertex] = [
        Vertex(position: [-0.5, -0.5]),
        Vertex(position: [ 0.5, -0.5]),
        Vertex(position: [-0.5,  0.5]),
        Vertex(position: [ 0.5,  0.5]),
    ]

    let maxInstanceCount = 1000
    var instanceCount = 0
    var time: Float = 0
    var instanceData: [InstanceData] = []

    init(mtkView: MTKView) {
        self.device = mtkView.device!
        self.commandQueue = device.makeCommandQueue()!

        super.init()
        buildPipeline(mtkView: mtkView)
        buildBuffers()
    }

    func buildPipeline(mtkView: MTKView) {
        let library = device.makeDefaultLibrary()!
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

        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
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


    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }

        time += 1.0 / Float(view.preferredFramesPerSecond)

//        for i in 0..<instanceCount {
//            let angle = time + Float(i) * (2 * .pi / Float(instanceCount))
//            let radius: Float = 0.5
//
//            let x = cos(angle) * radius
//            let y = sin(angle) * radius
//            let rotation = float4x4(rotationZ: angle * 2)
//            let scale = float4x4(scaling: SIMD3<Float>(repeating: 0.5))
//            let translation = float4x4(translation: [x, y, 0])
//
//            let transform = translation * rotation * scale
//            let color = SIMD4<Float>(
//                0.5 + 0.5 * sin(angle),
//                0.5 + 0.5 * cos(angle),
//                0.5 + 0.5 * sin(angle * 0.5),
//                1.0
//            )
//
//            instanceData[i] = InstanceData(transform: transform, color: color)
//        }
//
//        // Write to the GPU buffer
//        memcpy(instanceBuffer.contents(), instanceData, instanceCount * MemoryLayout<InstanceData>.stride)
        

        // For test: oscillate count between 1 and 100
        instanceCount = Int(10 + 90 * (0.5 + 0.5 * sin(time * 0.5)))
        instanceCount = min(instanceCount, maxInstanceCount)

        for i in 0..<instanceCount {
            let angle = time + Float(i) * (2 * .pi / Float(instanceCount))
            let radius: Float = 0.5

            let x = cos(angle) * radius
            let y = sin(angle) * radius
            let rotation = float4x4(rotationZ: angle * 2)
            let scale = float4x4(scaling: SIMD3<Float>(repeating: 0.05 + 0.05 * sin(angle)))
            let translation = float4x4(translation: [x, y, 0])

            let transform = translation * rotation * scale
            let color = SIMD4<Float>(
                0.5 + 0.5 * sin(angle),
                0.5 + 0.5 * cos(angle),
                0.5 + 0.5 * sin(angle * 0.5),
                1.0
            )

            instanceData[i] = InstanceData(transform: transform, color: color)
        }

        memcpy(instanceBuffer.contents(), instanceData, instanceCount * MemoryLayout<InstanceData>.stride)

        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)

        encoder.drawPrimitives(type: .triangleStrip,
                               vertexStart: 0,
                               vertexCount: squareVertices.count,
                               instanceCount: instanceCount)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
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
}
