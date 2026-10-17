//
//  RenderTester.swift
//  Metal Playground
//
//  Created by Rayner Tan on 14/10/26.
//

import MetalKit

struct RendererTester {
    public static func testUpdateGameState(renderer: Renderer) {
        testDrawEntitiesStressTest(renderer: renderer)
//        testDrawEntitiesShapes(renderer: renderer)
        testDrawSprites(renderer: renderer)
        testDrawTextWithBounds(renderer: renderer)
        testDrawAnimations(renderer: renderer)
    }
    
    private static func testDrawAnimations(renderer: Renderer) {
        let wave1 = sin(renderer.time * 1.5) * 300
        let wave2 = cos(renderer.time * 0.8) * 200
        let wave3 = sin(renderer.time * 3.2) * 100
        let circleX = sin(renderer.time * 2.0) * 256
        let circleY = cos(renderer.time * 1.0) * 128
        
        renderer.drawSprite(spriteName: "player_2",
                   x: wave1,
                   y: wave2,
                   width: 256 + wave3,
                   height: 256 + wave3,
                   color: SIMD4<Float>.one)
        
        renderer.drawEntityCircle(
            x: circleX,
            y: circleY,
            radius: 128 + sin(renderer.time * 4.0) * 64,
            color: [1, 0.3, 0.5, 1])
        
        renderer.drawSprite(
            spriteName: "player_2",
            x: -circleX,
            y: -circleY,
            width: 128,
            height: 128,
            color: SIMD4<Float>(1, 1, 1, 1))
        
        let textYOffset = sin(renderer.time * 1.2) * 40
        renderer.drawText(
            text: "Dynamic Text\nis Alive!",
            posX: -200,
            posY: 300 + textYOffset,
            fontSize: 64 + sin(renderer.time * 2.5) * 8,
            color: SIMD4<Float>(1, 0.8, 0.2, 1))
        
                
        renderer.drawText(text: "Another Test", posX: -150, posY: -50, fontSize: 48, color: [1,0,1,1])

        let scrollOffset = sin(renderer.time * 0.5) * 150
        
        renderer.drawText(
            text: "This is a much\nLonger test of a block\nOf text here and there\nAnother line here\nAnother line there\n  Here's one with 2 spaces before",
            posX: -600 + scrollOffset,
            posY: 600,
            fontSize: 96,
            color: SIMD4<Float>(0.1, 1.0, 0.5, 1.0))
        
        renderer.drawEntityCircle(
            x: sin(renderer.time * 0.7) * 600,
            y: cos(renderer.time * 0.9) * 500,
            radius: 64,
            color: [0, 0.5, 0.5, 1])
        
        renderer.drawText(
            text: "This is a much\nLonger test of a block\nOf text here and there\nAnother line here\nAnother line there\n  Here's one with 2 spaces before",
            posX: -900 - scrollOffset,
            posY: 100,
            fontSize: 96,
            color: SIMD4<Float>(0.1, 1.0, 0.5, 1.0))
    }
    
    private static func testDrawSprites(renderer: Renderer) {
        // For test: oscillate count between 0 and testMaxCount
        let testMaxCount: Float = 100
        let testCount = min(Int((sin(renderer.time * 2.0) + 1.0) / 2.0 * testMaxCount), 5000 - 1)
        
        var color = SIMD4<Float>.zero
        for i in 0..<testCount {
            let angle = renderer.time + Float(i) * (2 * .pi / Float(testCount))
            let radius: Float = Float(renderer.screenSize.width) / 3.0
            color.x = 0.5 + 0.5 * sin(angle)
            color.y = 0.5 + 0.5 * cos(angle)
            color.z = 0.5 + 0.5 * sin(angle * 0.5)
            color.w = 1.0
            
            renderer.drawSprite(
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
            renderer.drawSprite(spriteName: spriteName, x: 100, y: 100, width: 256, height: 256, color: SIMD4<Float>.one)
        }()
    }
    
    private static func testDrawEntitiesStressTest(renderer: Renderer) {
        let circleCount = 40000
        var rng = FastRandom(seed: UInt64(renderer.time * 1000000))
        var color = SIMD4<Float>.zero
        
        for _ in 0..<circleCount {
            let x = rng.nextFloat(min: Float(-renderer.screenSize.width), max: Float(renderer.screenSize.width))
            let y = rng.nextFloat(min: Float(-renderer.screenSize.height), max: Float(renderer.screenSize.height))
            let radius = rng.nextFloat(min: 5, max: 25)
            
            color.x = rng.nextUnitFloat()
            color.y = rng.nextUnitFloat()
            color.z = rng.nextUnitFloat()
            color.w = 1.0
            
            renderer.drawEntityCircle(x: x, y: y, radius: radius, color: color)
        }
    }
    
    private static func testDrawEntitiesShapes(renderer: Renderer) {
//        renderer.drawEntityCircle(x: 0, y: 0, radius: 800.0, r: 255, g: 255, b: 255, a: 64)
//        renderer.drawEntityCircle(x: 0, y: 0, radius: 512.0, r: 0, g: 255, b: 255, a: 64)
//        renderer.drawEntityCircle(x: 0, y: 0, radius: 256.0, r: 255, g: 0, b: 255, a: 64)
//        renderer.drawEntityCircle(x: 256, y: 256, radius: 128.0, r: 255, g: 0, b: 0, a: 64)
//        renderer.drawEntityCircle(x: 0, y: 0, radius: 128.0, r: 0, g: 255, b: 0, a: 64)
        renderer.drawEntityCircle(x: -256, y: -256, radius: 128.0, r: 0, g: 255, b: 255, a: 64)
        renderer.drawEntityLine(x1: -800, y1: -600, x2: 800, y2: 600, thickness: 10, r: 200, g: 100, b: 0, a: 128)
        renderer.drawEntityRectLines(x: 0, y: 0, width: 800, height: 600, thickness: 48, r: 0, g: 255, b: 255, a: 255)
        renderer.drawEntityRect(x: 0, y: 0, width: 800, height: 600, r: 255, g: 0, b: 0, a: 64)
//        renderer.drawEntityRect(x: -800, y: -600, width: 800, height: 600, r: 255, g: 0, b: 0, a: 64)
//        renderer.drawEntityRect(x: 0, y: 0, width: 24, height: 600, r: 255, g: 0, b: 0, a: 64)
//        renderer.drawEntityRect(x: 0, y: 0, width: 128, height: 196, r: 0, g: 255, b: 0, a: 128)
//        renderer.drawEntityRect(x: -800, y: -600, width: 800, height: 600, r: 128, g: 255, b: 0, a: 128)
//        renderer.drawEntityRect(x: -800, y: -600, width: 1600, height: 1200, r: 0, g: 255, b: 255, a: 32)
        renderer.drawEntityRoundedRect(x: 0, y: 0, width: 800, height: 600, cornerRadius: 100, r: 0, g: 0, b: 255, a: 255)
        renderer.drawEntityRoundedRect(x: 0, y: 0, width: 800, height: 100, cornerRadius: 100, r: 0, g: 255, b: 255, a: 255)
//        renderer.drawEntityCircle(x: 100, y: 100, radius: 100, r: 255, g: 0, b: 0, a: 128)
//        renderer.drawEntityRect(x: -600, y: -600, width: 1200, height: 1200, r: 255, g: 0, b: 255, a: 255)
//        renderer.drawEntityCircle(x: 0, y: 0, radius: 600, r: 255, g: 255, b: 255, a: 255)
        renderer.drawEntityCircleLines(x: 0, y: 0, radius: 600, thickness: 48, r: 255, g: 0, b: 255, a: 128)
        renderer.drawEntityRect(x: -600, y:-600, width: 48, height: 1200, r: 0, g: 255, b: 0, a: 128)
    }
    
    private static func testDrawTextWithBounds(renderer: Renderer) {
        // Testing for text bounds checking
        let fontSize: Float = 96
        let now = Date().timeIntervalSince1970
        let text = "Hello, SDF\nWorld!\n\n\(Int(now))"
        let textBounds = renderer.measureTextBounds(for: text, withSize: fontSize)
        renderer.drawEntityCircle(x: -Float(textBounds.width / 2.0),
                            y: Float(textBounds.height / 2.0),
                            radius: 16, color: SIMD4<Float>.one)
        renderer.drawEntityRect(
            x: -Float(textBounds.width / 2.0),
            y: -(textBounds.height / 2.0),
            width: textBounds.width,
            height: textBounds.height,
            color: SIMD4<Float>(0,1.0,1.0,0.25))
        
        let color: SIMD4<Float> = [0.9, 0.9, 0.1, 1.0] // Yellow
        renderer.drawText(
            text: text,
            posX: -Float(textBounds.width / 2.0),
            posY: Float(textBounds.height / 2.0),
            fontSize: fontSize,
            color: color,
        )
        
        
        renderer.drawText(
            text: "HELLO       AGAIN!!!",
            posX: Float(20 - renderer.screenSize.width / 2.0),
            posY: Float(-20 + renderer.screenSize.height / 2.0),
            fontSize: 48,
            color: [0.3, 0.2, 0.7, 1.0])
    }
}
