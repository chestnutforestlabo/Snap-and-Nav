//
//  scaleTracker.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/08/12.
//

import Foundation

class ScaleTracker {
    var scales: [Float] = []
    
    func saveScale(_ scale: Float?) {
        if let scale = scale {
            scales.append(scale)
        }
    }
    
    func averageScale() -> Float? {
        guard !scales.isEmpty else { return nil }
        let total = scales.reduce(0, +)
        return total / Float(scales.count)
    }
}
