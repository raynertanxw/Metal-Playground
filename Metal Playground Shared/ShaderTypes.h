//
//  ShaderTypes.h
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 1/8/25.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

// Metal Shaders
#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::uint32_t GPUEnumBackingType;
typedef metal::int32_t APIEnumBackingType;

// Swift (Objective-C)
#elif defined(__OBJC__)
#import <Foundation/Foundation.h>
typedef uint32_t GPUEnumBackingType;
typedef NSInteger APIEnumBackingType; // Translates to standard Swift Int

// C++ (metal-cpp)
#else
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef uint32_t GPUEnumBackingType;
typedef int64_t APIEnumBackingType;
#endif

// Struct Payloads (Strict 32-bit for GPU memory alignment)
typedef NS_ENUM(GPUEnumBackingType, ShapeType) {
    ShapeTypeNone = 0,
    ShapeTypeRoundBoxSDF = 1,
    ShapeTypeRoundBoxSDFLines = 2,
    ShapeTypeAtlas = 3,
};

// API Bindings (Standard Int for seamless Metal framework configuration)
typedef NS_ENUM(APIEnumBackingType, BufferIndex) {
    BufferIndexVertices = 0,
    BufferIndexInstances = 1,
    BufferIndexUniforms = 2,
};

typedef NS_ENUM(APIEnumBackingType, TextBufferIndex) {
    TextBufferIndexVertices = 0,
    TextBufferIndexProjectionMatrix = 1,
};

typedef NS_ENUM(APIEnumBackingType, AtlasVertAttr) {
    AtlasVertAttrPosition = 0,
    AtlasVertAttrUV = 1,
};

typedef NS_ENUM(APIEnumBackingType, TextVertAttr) {
    TextVertAttrPosition = 0,
    TextVertAttrUV = 1,
    TextVertAttrTextColor = 2,
};

#endif /* ShaderTypes_h */
