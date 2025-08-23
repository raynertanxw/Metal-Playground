//
//  GameViewController.cpp
//  Metal Playground macOS CPP
//
//  Created by Rayner Tan on 21/8/25.
//

#include "GameViewController.hpp"

GameViewController::GameViewController( MTL::Device* pDevice, MTK::View* pView )
: MTK::ViewDelegate()
{
    _pRenderer = new Renderer(pDevice, pView);
    _pRenderer->drawableSizeWillChange(pView, pView->drawableSize());
}

GameViewController::~GameViewController()
{
    delete _pRenderer;
}

void GameViewController::drawInMTKView( MTK::View* pView )
{
    _pRenderer->draw( pView );
}

void GameViewController::drawableSizeWillChange( MTK::View* pView, CGSize size )
{
    _pRenderer->drawableSizeWillChange(pView, size);
}
