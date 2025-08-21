//
//  AppDelegate.hpp
//  Metal Playground macOS CPP
//
//  Created by Rayner Tan on 21/8/25.
//

#ifndef AppDelegate_hpp
#define AppDelegate_hpp

#include "GameViewController.hpp"

class AppDelegate : public NS::ApplicationDelegate
{
    public:
        ~AppDelegate();

        NS::Menu* createMenuBar();

        virtual void applicationWillFinishLaunching( NS::Notification* pNotification ) override;
        virtual void applicationDidFinishLaunching( NS::Notification* pNotification ) override;
        virtual bool applicationShouldTerminateAfterLastWindowClosed( NS::Application* pSender ) override;

    private:
        NS::Window* _pWindow;
        MTK::View* _pMtkView;
        MTL::Device* _pDevice;
        GameViewController* _pViewDelegate = nullptr;
};


#endif /* AppDelegate_hpp */
