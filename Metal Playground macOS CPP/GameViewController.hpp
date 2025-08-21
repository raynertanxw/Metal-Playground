//
//  GameViewController.hpp
//  Metal Playground macOS CPP
//
//  Created by Rayner Tan on 21/8/25.
//

#ifndef GameViewController_hpp
#define GameViewController_hpp

#include "Renderer.hpp"

class GameViewController : public MTK::ViewDelegate
{
    public:
        GameViewController( MTL::Device* pDevice );
        virtual ~GameViewController() override;
        virtual void drawInMTKView( MTK::View* pView ) override;

    private:
        Renderer* _pRenderer;
};


#endif /* GameViewController_hpp */
