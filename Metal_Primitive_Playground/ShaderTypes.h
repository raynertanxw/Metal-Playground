//
//  ShaderTypes.h
//  Metal_Primitive_Playground
//
//  Created by Rayner Tan on 1/8/25.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

typedef NS_ENUM(EnumBackingType, ShapeType) {
    ShapeTypeNone = 0,
    ShapeTypeRect = 1,
    ShapeTypeRoundedRect = 2,
    ShapeTypeCircle = 3,
};

typedef NS_ENUM(EnumBackingType, BufferIndex) {
    BufferIndexVertices = 0,
    BufferIndexInstances = 1,
    BufferIndexUniforms = 2,
};


#endif /* ShaderTypes_h */
