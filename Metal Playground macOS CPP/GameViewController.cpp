//
//  GameViewController.cpp
//  Metal Playground macOS CPP
//
//  Created by Rayner Tan on 21/8/25.
//

#include "GameViewController.hpp"

GameViewController::GameViewController( MTL::Device* pDevice )
: MTK::ViewDelegate()
, _pRenderer( new Renderer( pDevice ) )
{
}

GameViewController::~GameViewController()
{
    delete _pRenderer;
}

void GameViewController::drawInMTKView( MTK::View* pView )
{
    _pRenderer->draw( pView );
}