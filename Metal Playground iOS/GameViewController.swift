//
//  GameViewController.swift
//  Metal Playground
//
//  Created by Rayner Tan on 7/8/25.
//

import UIKit
import MetalKit

class GameViewController: UIViewController {

    var renderer: Renderer!
    var mtkView: MTKView!
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        self.view = UIView()
        view.backgroundColor = .black
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupMTKViewAndRenderer()
        setupFPSLabel()
    }

    private func setupMTKViewAndRenderer() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported")
        }

        let mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.backgroundColor = .black

        view.addSubview(mtkView)
        self.mtkView = mtkView

        guard let renderer = Renderer(mtkView: mtkView) else {
            fatalError("Renderer failed")
        }
        self.renderer = renderer
        mtkView.delegate = renderer
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
    }

    private func setupFPSLabel() {
        let fpsLabel = FPSCounter(frame: CGRect(x: 20, y: 50, width: 80, height: 30))
        view.addSubview(fpsLabel)

        renderer.onFramePresented = { fps in
            DispatchQueue.main.async {
                fpsLabel.updateFPS(fps)
            }
        }
    }
}

