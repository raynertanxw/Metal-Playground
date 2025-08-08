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
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        textColor = .white
        font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        textAlignment = .center
        layer.cornerRadius = 4
        layer.masksToBounds = true
        text = "FPS: --"
    }

    /// Call this from the renderer when FPS changes
    func updateFPS(_ fps: Double) {
        text = String(format: "FPS: %.0f", fps)
    }
}

