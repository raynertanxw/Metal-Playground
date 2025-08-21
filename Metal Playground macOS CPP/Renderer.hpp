//
//  Renderer.hpp
//  Metal Playground macOS CPP
//
//  Created by Rayner Tan on 21/8/25.
//

#ifndef Renderer_hpp
#define Renderer_hpp

#include <Metal/Metal.hpp>
#include <MetalKit/MetalKit.hpp>
#include <simd/simd.h>

class Renderer
{
    public:
        Renderer( MTL::Device* pDevice );
        ~Renderer();
        void buildShaders();
        void buildBuffers();
        void draw( MTK::View* pView );

    private:
        MTL::Device* _pDevice;
        MTL::CommandQueue* _pCommandQueue;
        MTL::RenderPipelineState* _pPSO;
        MTL::Buffer* _pVertexPositionsBuffer;
        MTL::Buffer* _pVertexColorsBuffer;
};

#endif /* Renderer_hpp */
