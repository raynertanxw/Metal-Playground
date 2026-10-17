//
//  RendererTester.cpp
//  Metal Playground
//
//  Created by Rayner Tan on 17/10/26.
//

#include "RendererTester.hpp"
#include "ii_random.h"

void testDrawEntities(Renderer *ren) {
    const int circleCount = 70000;
    RNG rng = {U32(ren->readTime() * 1000000)};
    simd_float4 color = {};
    CGSize screenSize = ren->readScreenSize();
    
    for (int iCircle = 0; iCircle < circleCount; ++iCircle) {
        const float x = RandomRangeF32(&rng, -screenSize.width, screenSize.width);
        const float y = RandomRangeF32(&rng, -screenSize.height, screenSize.height);
        const float radius = RandomRangeF32(&rng, 5, 25);
        
        color.x = RandomF01(&rng);
        color.y = RandomF01(&rng);
        color.z = RandomF01(&rng);
        color.w = 1.0;
        
        ren->drawEntityCircle(x, y, radius, color);
    }
    
//    ren->drawEntityCircle(0, 0, 50, 0, 255, 255, 255);
//    ren->drawEntityCircle(0, 0, 800.0, 255, 255, 255, 64);
//    ren->drawEntityCircle(0, 0, 512.0, 0, 255, 255, 64);
//    ren->drawEntityCircle(0, 0, 256.0, 255, 0, 255, 64);
//    ren->drawEntityCircle(256, 256, 128.0, 255, 0, 0, 64);
//    ren->drawEntityCircle(0, 0, 128.0, 0, 255, 0, 64);
//    ren->drawEntityCircle(-256, -256, 128.0, 0, 0, 255, 64);
//    ren->drawEntityLine(-800, -600, 800, 600, 10, 200, 100, 0, 128);
//    ren->drawEntityRectLines(0, 0, 800, 600, 48, 0, 255, 255, 255);
//    ren->drawEntityRect(0, 0, 800, 600, 255, 0, 0, 64);
//    ren->drawEntityRect(-800, -600, 800, 600, 255, 0, 0, 64);
//    ren->drawEntityRect(0, 0, 24, 600, 255, 0, 0, 64);
//    ren->drawEntityRect(0, 0, 128, 196, 0, 255, 0, 128);
//    ren->drawEntityRect(-800, -600, 800, 600, 128, 255, 0, 128);
//    ren->drawEntityRect(-800, -600, 1600, 1200, 0, 255, 255, 32);
//    ren->drawEntityRoundedRect(0, 0, 800, 600, 100, 0, 0, 255, 255);
//    ren->drawEntityRoundedRect(0, 0, 800, 100, 100, 0, 255, 255, 255);
//    ren->drawEntityCircle(100, 100, 100, 255, 0, 0, 128);
//    ren->drawEntityRect(-600, -600, 1200, 1200, 255, 0, 255, 255);
//    ren->drawEntityCircle(0, 0, 600, 255, 255, 255, 255);
//    ren->drawEntityCircleLines(0, 0, 600, 48, 255, 0, 255, 128);
//    ren->drawEntityRect(-600, -600, 48, 1200, 0, 255, 0, 128);

}

void testDrawSprites(Renderer *ren)
{
    const int testMaxCount = 100;
    const int testCount = MIN
    ((int)((sin(ren->readTime() * 2.0f) + 1.0f) / 2.0f * testMaxCount), 5000);
    
    simd_float4 color;
    for (int i = 0; i < testCount; ++i) {
        const float angle = ren->readTime() + ((float)i) * (2.0f * M_PI / ((float)testCount));
        const float radius = ((float)ren->readScreenSize().width) / 3.0f;
        color.x = 0.5f + 0.5f * sin(angle);
        color.y = 0.5f + 0.5f * cos(angle);
        color.z = 0.5f + 0.5f * sin(angle * 0.5f);
        color.w = 1.0f;
        
        ren->drawSprite("Circle_White", cos(angle) * radius, sin(angle) * radius, 100.0f + 100.0f * sin(angle), 100.0f + 100.0f * sin(angle), color, angle * 2);
    }
    
    { // Test anything static here, adds to last insance count
        const char* spriteName = "player_1";
        ren->drawSprite(spriteName, 100, 100, 256, 256, ren->colorFromBytes(255, 255, 255, 255), 0.0f);
    }
}

void testDrawTextWithBounds(Renderer *ren)
{
    const float fontSize = 96.0f;
    
    // Generate timestamp as string
    std::time_t now = std::time(nullptr);
    char timeBuffer[32];
    std::snprintf(timeBuffer, sizeof(timeBuffer), "%ld", now);
    
    // Build text with multiple lines: "Hello, SDF\nWorld!\n\n<timestamp>"
    char text[256];
    std::snprintf(text, sizeof(text), "Hello, SDF\nWorld!\n\n%s", timeBuffer);
    
    // Measure text bounds
    auto bounds = ren->measureTextBounds(text, fontSize); // returns std::pair<float, float>
    float textWidth  = bounds.first;
    float textHeight = bounds.second;
    
    // Draw a circle at the top-left of the text bounds
    simd::float4 white = {1.0f, 1.0f, 1.0f, 1.0f};
    ren->drawEntityCircle(-textWidth / 2.0f,
                        textHeight / 2.0f,
                        16.0f,
                        white);
        
    // Draw a rectangle behind the text to visualize bounds
    ren->drawEntityRect(-textWidth / 2.0f,
                      -textHeight / 2.0f,
                      textWidth,
                      textHeight,
                      simd::float4{0.0f, 1.0f, 1.0f, 0.25f} // semi-transparent cyan
                      );
    
    // Draw the main multi-line text
    simd::float4 yellow = {0.9f, 0.9f, 0.1f, 1.0f};
    ren->drawText(
             text,
             -textWidth / 2.0f,
             textHeight / 2.0f,
             fontSize,
             yellow
             );
    
    // Draw another text at fixed offset
    CGSize screenSize = ren->readScreenSize();
    simd::float4 purple = {0.3f, 0.2f, 0.7f, 1.0f};
    ren->drawText("HELLO       AGAIN!!!",
             20.0f - screenSize.width / 2.0f,
             -20.0f + screenSize.height / 2.0f,
             48.0f,
             purple
             );
}

void testDrawInterleavedTypes(Renderer *ren)
{
    float time = ren->readTime();
    
    // Waves and circle positions
    float wave1   = std::sin(time * 1.5f) * 300.0f;
    float wave2   = std::cos(time * 0.8f) * 200.0f;
    float wave3   = std::sin(time * 3.2f) * 100.0f;
    float circleX = std::sin(time * 2.0f) * 256.0f;
    float circleY = std::cos(time * 1.0f) * 128.0f;

    // Draw first sprite
    ren->drawSprite(
        "player_2",
        wave1,
        wave2,
        256.0f + wave3,
        256.0f + wave3,
        simd::float4{1.0f, 1.0f, 1.0f, 1.0f},
        0.0f
    );

    // Draw moving circle
    ren->drawEntityCircle(
        circleX,
        circleY,
        128.0f + std::sin(time * 4.0f) * 64.0f,
        simd::float4{1.0f, 0.3f, 0.5f, 1.0f}
    );

    // Draw mirrored sprite
    ren->drawSprite(
        "player_2",
        -circleX,
        -circleY,
        128.0f,
        128.0f,
        simd::float4{1.0f, 1.0f, 1.0f, 1.0f},
        0.0f
    );

    // Dynamic text Y offset
    float textYOffset = std::sin(time * 1.2f) * 40.0f;

    // Draw first dynamic text
    ren->drawText(
        "Dynamic Text\nis Alive!",
        -200.0f,
        300.0f + textYOffset,
        64.0f + std::sin(time * 2.5f) * 8.0f,
        simd::float4{1.0f, 0.8f, 0.2f, 1.0f}
    );

    // Draw static text
    ren->drawText(
        "Another Test",
        -150.0f,
        -50.0f,
        48.0f,
        simd::float4{1.0f, 0.0f, 1.0f, 1.0f}
    );

    // Scroll offset for moving text block
    float scrollOffset = std::sin(time * 0.5f) * 150.0f;

    // Draw first scrolling text block
    ren->drawText(
        "This is a much\nLonger test of a block\nOf text here and there\nAnother line here\nAnother line there\n  Here's one with 2 spaces before",
        -600.0f + scrollOffset,
        600.0f,
        96.0f,
        simd::float4{0.1f, 1.0f, 0.5f, 1.0f}
    );

    // Another moving circle
    ren->drawEntityCircle(
        std::sin(time * 0.7f) * 600.0f,
        std::cos(time * 0.9f) * 500.0f,
        64.0f,
        simd::float4{0.0f, 0.5f, 0.5f, 1.0f}
    );

    // Draw mirrored scrolling text block
    ren->drawText(
        "This is a much\nLonger test of a block\nOf text here and there\nAnother line here\nAnother line there\n  Here's one with 2 spaces before",
        -900.0f - scrollOffset,
        100.0f,
        96.0f,
        simd::float4{0.1f, 1.0f, 0.5f, 1.0f}
    );
}

void testUpdateGameState(Renderer *ren) {
    testDrawEntities(ren);
    testDrawSprites(ren);
    testDrawTextWithBounds(ren);
    testDrawInterleavedTypes(ren);
}
