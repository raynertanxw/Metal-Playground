//
//  TextTestRenderer.swift
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 2/8/25.
//

import MetalKit

// MARK: - Font Atlas Structs
struct FontAtlas: Codable {
    let atlas: AtlasMetrics
    let metrics: FontMetrics
    let glyphs: [Glyph]
    let kerning: [Kerning]
}

struct AtlasMetrics: Codable {
    let type: String
    let distanceRange: Double
    let size: Double
    let width: Int
    let height: Int
    let yOrigin: String
}

struct FontMetrics: Codable {
    let emSize: Double
    let lineHeight: Double
    let ascender: Double
    let descender: Double
    let underlineY: Double
    let underlineThickness: Double
}

struct Glyph: Codable {
    let unicode: Int
    let advance: Double
    let planeBounds: Bounds?
    let atlasBounds: Bounds?
}

struct Bounds: Codable {
    let left: Double
    let bottom: Double
    let right: Double
    let top: Double
}

struct Kerning: Codable {
    let unicode1: Int
    let unicode2: Int
    let advance: Double
}


// MARK: - Text Rendering Structs
struct TextVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

struct TextFragmentUniforms {
    var textColor: SIMD4<Float>
    var distanceRange: Float
}


// MARK: - TextRenderer
class TextRenderer {
    private let pipelineState: MTLRenderPipelineState
    private let texture: MTLTexture
    
    // Font Data
    private let fontAtlas: FontAtlas
    private var glyphs = [UInt32: Glyph]()
    private var kerning = [UInt64: Kerning]()

    // Dynamic buffer for vertices
    private var vertexBuffer: MTLBuffer!
    private var vertexBufferCapacity: Int = 1024 * 6 // Initial capacity in number of characters (6 vertice per character)
    
    private var textSamplerState: MTLSamplerState

    // MARK: - Initialization
    init(device: MTLDevice, fontName: String, pixelFormat: MTLPixelFormat) {
        // 1. Load Font Atlas Data (JSON and PNG) and process data for quick lookups
        (self.fontAtlas, self.texture) = Self.loadFontAtlas(device: device, fontName: fontName)
        (self.glyphs, self.kerning) = Self.preprocessFontData(fontAtlas: fontAtlas)
        
        // 2. Create Metal Render Pipeline State
        let library = device.makeDefaultLibrary()!
        let vertexFunction = library.makeFunction(name: "text_vertex_shader")
        let fragmentFunction = library.makeFunction(name: "text_fragment_shader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        
        let textSamplerDescriptor = MTLSamplerDescriptor()
        textSamplerDescriptor.minFilter = .linear
        textSamplerDescriptor.magFilter = .linear
        textSamplerDescriptor.mipFilter = .linear
        guard let textSamplerState = device.makeSamplerState(descriptor: textSamplerDescriptor) else { fatalError("Unabled to create text sampler state") }
        self.textSamplerState = textSamplerState

        
        // Enable alpha blending
        let colorAttachment = pipelineDescriptor.colorAttachments[0]!
        colorAttachment.pixelFormat = pixelFormat
        colorAttachment.isBlendingEnabled = true
        colorAttachment.rgbBlendOperation = .add
        colorAttachment.alphaBlendOperation = .add
        colorAttachment.sourceRGBBlendFactor = .sourceAlpha
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
        colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[TextVertAttr.position.rawValue].format = .float2 // position
        vertexDescriptor.attributes[TextVertAttr.position.rawValue].offset = 0
        vertexDescriptor.attributes[TextVertAttr.position.rawValue].bufferIndex = TextBufferIndex.vertices.rawValue
        vertexDescriptor.attributes[TextVertAttr.UV.rawValue].format = .float2 // uv
        vertexDescriptor.attributes[TextVertAttr.UV.rawValue].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[TextVertAttr.UV.rawValue].bufferIndex = TextBufferIndex.vertices.rawValue
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
    
    private static func preprocessFontData(fontAtlas: FontAtlas) -> ([UInt32: Glyph], [UInt64: Kerning]) {
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

    // MARK: - Drawing
    public func draw(text: String,
                     at position: SIMD2<Float>,
                     fontSize: Float,
                     color: SIMD4<Float>,
                     projectionMatrix: simd_float4x4,
                     device: MTLDevice,
                     encoder: MTLRenderCommandEncoder) {
        
        guard !text.isEmpty else { return }
        
        // Build text vertices
        let vertices = buildMesh(for: text, at: position, withSize: fontSize)
        guard !vertices.isEmpty else { return }
        
        if vertices.count > vertexBufferCapacity { // grow buffer capacity if needed
            let numCharacters = vertices.count / 6
            vertexBufferCapacity = numCharacters.nextPowerOf2() * 6
            vertexBuffer = device.makeBuffer(length: MemoryLayout<TextVertex>.stride * 6 * vertexBufferCapacity, options: .storageModeShared)
        }
        vertexBuffer.contents().copyMemory(from: vertices, byteCount: vertices.count * MemoryLayout<TextVertex>.stride)
        
        // Get encoder to draw
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: TextBufferIndex.vertices.rawValue)
        var projectionMatrix = projectionMatrix
        encoder.setVertexBytes(&projectionMatrix, length: MemoryLayout<float4x4>.stride, index: TextBufferIndex.projectionMatrix.rawValue)
        
        var uniforms = TextFragmentUniforms(textColor: color, distanceRange: Float(fontAtlas.atlas.distanceRange))
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TextFragmentUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(textSamplerState, index: 0)
        
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    // MARK: - Mesh Generation
    private func buildMesh(for text: String, at origin: SIMD2<Float>, withSize fontSize: Float) -> [TextVertex] {
        var vertices: [TextVertex] = []
        let atlasWidth = Float(fontAtlas.atlas.width)
        let atlasHeight = Float(fontAtlas.atlas.height)

        let scale = Float(fontSize) / Float(fontAtlas.metrics.emSize)
        let lineHeight = Float(fontAtlas.metrics.lineHeight) * scale
        let ascender = Float(fontAtlas.metrics.ascender) * scale

        var cursorX = origin.x
        var cursorY = origin.y - ascender // shift down so top of first line is at origin.y

        var previousChar: UInt32 = 0

        for char in text.unicodeScalars {
            if char == "\n" {
                cursorX = origin.x
                cursorY -= lineHeight
                previousChar = 0
                continue
            }

            let unicode = char.value

            // Kerning
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

            let x0 = cursorX + Float(plane.left) * scale
            let y0 = cursorY + Float(plane.bottom) * scale
            let x1 = cursorX + Float(plane.right) * scale
            let y1 = cursorY + Float(plane.top) * scale

            let u0 = Float(atlas.left) / atlasWidth
            let u1 = Float(atlas.right) / atlasWidth
            let v0 = Float(atlasHeight - Float(atlas.top)) / atlasHeight
            let v1 = Float(atlasHeight - Float(atlas.bottom)) / atlasHeight

            let topLeft     = TextVertex(position: [x0, y1], uv: [u0, v0])
            let topRight    = TextVertex(position: [x1, y1], uv: [u1, v0])
            let bottomLeft  = TextVertex(position: [x0, y0], uv: [u0, v1])
            let bottomRight = TextVertex(position: [x1, y0], uv: [u1, v1])

            vertices.append(contentsOf: [
                bottomLeft, bottomRight, topRight,
                bottomLeft, topRight, topLeft
            ])

            cursorX += Float(glyph.advance) * scale
            previousChar = unicode
        }

        return vertices
    }

    
    // MARK: - MEASURE TEXT
    func measureTextBounds(for text: String, withSize fontSize: Float) -> (width: Float, height: Float) {
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
                if let kern = kerning[key] {
                    cursorX += Float(kern.advance) * scale
                }
            }
            
            guard let glyph = glyphs[unicode],
                  let plane = glyph.planeBounds else {
                previousChar = unicode
                continue
            }
            
            let glyphRight = cursorX + Float(plane.right) * scale
            maxXInLine = max(maxXInLine, glyphRight)
            
            cursorX += Float(glyph.advance) * scale
            previousChar = unicode
        }
        
        let textWidth = max(maxLineWidth, maxXInLine)
        let textHeight = Float(lineCount) * lineHeight;
        return (textWidth, textHeight)
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
