//
//  FontAtlas.swift
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 2/8/25.
//

import Foundation

// Maps to the root JSON object
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
