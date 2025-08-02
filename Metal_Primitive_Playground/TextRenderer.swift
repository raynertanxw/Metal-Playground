//
//  TextTestRenderer.swift
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 2/8/25.
//

import MetalKit

// The vertex structure must match the `VertexIn` in Metal.
struct TextVertex {
    var position: SIMD2<Float>
    var texCoord: SIMD2<Float>
}

class TextRenderer {

    // MARK: - Properties
    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let texture: MTLTexture
    
    // Font Data
    private let fontAtlas: FontAtlas
    private var glyphs = [UInt32: Glyph]()
    private var kerning = [UInt64: Kerning]()
    
    // Dynamic buffer for vertices
    private var vertexBuffer: MTLBuffer!
    private var vertexBufferCapacity: Int = 256 // Initial capacity for 256 characters

    // MARK: - Initialization

    init(device: MTLDevice, fontName: String) {
        self.device = device

        // 1. Load Font Atlas Data (JSON and PNG)
        (self.fontAtlas, self.texture) = Self.loadFontAtlas(device: device, fontName: fontName)
        
        // 2. Create Metal Render Pipeline State
        let library = device.makeDefaultLibrary()!
        let vertexFunction = library.makeFunction(name: "text_vertex_shader")
        let fragmentFunction = library.makeFunction(name: "text_fragment_shader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm // Match your MTKView's pixelFormat
        
        // Enable alpha blending
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2 // position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2 // texCoord
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<TextVertex>.stride
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create text rendering pipeline state: \(error)")
        }
        
        // 3. Create initial (empty) vertex buffer
        self.vertexBuffer = device.makeBuffer(length: MemoryLayout<TextVertex>.stride * 6 * vertexBufferCapacity, options: .storageModeShared)
        self.vertexBuffer.label = "Text Vertex Buffer"
        
        // 4. Pre-process font data for quick lookups
        preprocessFontData()
    }

    private static func loadFontAtlas(device: MTLDevice, fontName: String) -> (FontAtlas, MTLTexture) {
        // Load JSON
        guard let jsonURL = Bundle.main.url(forResource: fontName, withExtension: "json") else {
            fatalError("Font atlas JSON file not found: \(fontName).json")
        }
        let jsonData = try! Data(contentsOf: jsonURL)
        let fontAtlas = try! JSONDecoder().decode(FontAtlas.self, from: jsonData)
        
        // Load PNG Texture
        let textureLoader = MTKTextureLoader(device: device)
        guard let textureURL = Bundle.main.url(forResource: fontName, withExtension: "png") else {
            fatalError("Font atlas texture not found: \(fontName).png")
        }
        let texture = try! textureLoader.newTexture(URL: textureURL, options: nil)
        
        return (fontAtlas, texture)
    }
    
    private func preprocessFontData() {
        for glyph in fontAtlas.glyphs {
            glyphs[UInt32(glyph.unicode)] = glyph
        }
        for kern in fontAtlas.kerning {
            // Combine the two unicode values into a single key for dictionary lookup
            let key = (UInt64(kern.unicode1) << 32) | UInt64(kern.unicode2)
            kerning[key] = kern
        }
    }

    // MARK: - Drawing

    /// Call this from your MTKView's `draw(in:)` method.
    public func draw(text: String,
                     at position: SIMD2<Float>,
                     withSize fontSize: Float,
                     color: SIMD4<Float>,
                     projectionMatrix: simd_float4x4,
                     on encoder: MTLRenderCommandEncoder) {
        guard !text.isEmpty else { return }
        
        // 1. Build the vertex mesh for the text string
        let vertices = buildMesh(for: text, at: position, withSize: fontSize)
        guard !vertices.isEmpty else { return }
        
        // 2. Ensure vertex buffer is large enough
        let requiredCapacity = vertices.count / 6
        if requiredCapacity > vertexBufferCapacity {
            vertexBufferCapacity = requiredCapacity.nextPowerOf2()
            vertexBuffer = device.makeBuffer(length: MemoryLayout<TextVertex>.stride * 6 * vertexBufferCapacity, options: .storageModeShared)
        }
        
        // 3. Copy vertex data into the buffer
        vertexBuffer.contents().copyMemory(from: vertices, byteCount: vertices.count * MemoryLayout<TextVertex>.stride)
        
        // 4. Set state and resources on the EXISTING encoder
        encoder.setRenderPipelineState(pipelineState)
        
        // 5. Set Buffers and Textures
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        var projectionMatrix = projectionMatrix
        encoder.setVertexBytes(&projectionMatrix, length: MemoryLayout<float4x4>.stride, index: 1) // projection matrix at buffer(1)
        
        var textColor = color
        encoder.setFragmentBytes(&textColor, length: MemoryLayout<SIMD4<Float>>.stride, index: 0) // text color at buffer(0)
        var distanceRange = Float(fontAtlas.atlas.distanceRange)
        encoder.setFragmentBytes(&distanceRange, length: MemoryLayout<Float>.stride, index: 1) // distanceRange at buffer(1)
        encoder.setFragmentTexture(texture, index: 0)
        
        // 6. Draw
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    // MARK: - Mesh Generation
    private func buildMesh(for text: String, at origin: SIMD2<Float>, withSize fontSize: Float) -> [TextVertex] {
        var vertices: [TextVertex] = []
        var cursorX = origin.x
        let cursorY = origin.y

        let scale = fontSize
        let atlasWidth = Float(fontAtlas.atlas.width)
        let atlasHeight = Float(fontAtlas.atlas.height)

        var previousChar: UInt32 = 0

        for char in text.unicodeScalars {
            let unicode = char.value

            // Apply kerning
            if previousChar != 0 {
                let key = (UInt64(previousChar) << 32) | UInt64(unicode)
                if let kern = kerning[key] {
                    cursorX += Float(kern.advance) * scale
                }
            }

            guard let glyph = glyphs[unicode],
                  let plane = glyph.planeBounds,
                  let atlas = glyph.atlasBounds else {
                previousChar = unicode
                continue
            }

            // Vertex positions
            let x0 = cursorX + Float(plane.left) * scale
            let y0 = cursorY + Float(plane.bottom) * scale
            let x1 = cursorX + Float(plane.right) * scale
            let y1 = cursorY + Float(plane.top) * scale

            // UVs (flip Y)
            let u0 = Float(atlas.left) / atlasWidth
            let u1 = Float(atlas.right) / atlasWidth
            let v0 = Float(atlasHeight - Float(atlas.top)) / atlasHeight
            let v1 = Float(atlasHeight - Float(atlas.bottom)) / atlasHeight

            // Quad verts
            let topLeft     = TextVertex(position: [x0, y1], texCoord: [u0, v0])
            let topRight    = TextVertex(position: [x1, y1], texCoord: [u1, v0])
            let bottomLeft  = TextVertex(position: [x0, y0], texCoord: [u0, v1])
            let bottomRight = TextVertex(position: [x1, y0], texCoord: [u1, v1])

            vertices.append(contentsOf: [
                bottomLeft, bottomRight, topRight,
                bottomLeft, topRight, topLeft
            ])

            cursorX += Float(glyph.advance) * scale
            previousChar = unicode
        }

        return vertices
    }
}

// Helper to get next power of two for buffer resizing
extension Int {
    func nextPowerOf2() -> Int {
        var n = self - 1
        n |= n >> 1
        n |= n >> 2
        n |= n >> 4
        n |= n >> 8
        n |= n >> 16
        n |= n >> 32 // for 64-bit
        return n + 1
    }
}
