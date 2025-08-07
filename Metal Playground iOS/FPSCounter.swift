//
//  FPSCounter.swift
//  Metal Playground
//
//  Created by Rayner Tan on 7/8/25.
//

import Foundation
import UIKit

// TODO: Expand to include more states, e.g. drawcalls, num instances, vertices, etc.
class FPSCounter: UILabel {
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        textColor = .white
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        textAlignment = .center
        layer.cornerRadius = 4
        clipsToBounds = true

        displayLink = CADisplayLink(target: self, selector: #selector(updateFPS))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateFPS(link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }

        frameCount += 1
        let delta = link.timestamp - lastTimestamp

        if delta >= 1.0 {
            let fps = Double(frameCount) / delta
            text = String(format: "FPS: %.0f", fps)
            lastTimestamp = link.timestamp
            frameCount = 0
        }
    }

    deinit {
        displayLink?.invalidate()
    }
}
