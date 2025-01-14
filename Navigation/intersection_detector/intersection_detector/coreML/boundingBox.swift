//
//  boundingBox.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2021/05/15.
//

import Foundation
import UIKit
import SceneKit

class BoundingBoxes {
    var boundingBoxes = [BoundingBox]()
    var colors: [UIColor] = []
    
    init(imgView: UIImageView) {
        
        for _ in 0..<20 {
            boundingBoxes.append(BoundingBox())
        }
        for box in boundingBoxes {
            box.addToLayer(imgView.layer)
        }
        for r: CGFloat in [0.2, 0.4, 0.6, 0.8, 1.0] {
            for g: CGFloat in [0.3, 0.7] {
                for b: CGFloat in [0.4, 0.8] {
                    let color = UIColor(red: r, green: g, blue: b, alpha: 1)
                    colors.append(color)
                }
            }
        }
        
    }
    
    func show(predictions: [Prediction], labels: [String]) {
        for i in 0..<boundingBoxes.count {
            if i < predictions.count {
                let prediction = predictions[i]
                
                // Translate and scale the rectangle to our own coordinate system.
                let rect = prediction.rect
                let classIndex = prediction.classIndex
                let newRect = CGRect(x: rect.minX * imageSize / 128, y: rect.minY * imageSize / 128, width: rect.width * imageSize / 128, height: rect.height * imageSize / 128)
                // Show the bounding box.
                
//                var confirmedLabel = ""
//                if prediction.confirmation.front { confirmedLabel += "F"}
//                if prediction.confirmation.back { confirmedLabel += "B"}
//                if prediction.confirmation.left { confirmedLabel += "L"}
//                if prediction.confirmation.right { confirmedLabel += "R"}
                
                let label = String(format: "%@ %.1f", labels[classIndex], prediction.score * 100)
//                let label = String(format: "%@ %.1f", confirmedLabel, prediction.score * 100)
                
                let color = colors[prediction.classIndex]
                boundingBoxes[i].show(frame: newRect, label: label, color: color)
            } else {
                boundingBoxes[i].hide()
            }
        }
    }
}

class BoundingBox {
    let shapeLayer: CAShapeLayer
    let textLayer: CATextLayer
    let lineWidth: CGFloat = 2.0
    let margin: CGFloat = 10.0
    
    init() {
        shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = lineWidth
        shapeLayer.isHidden = true
        
        textLayer = CATextLayer()
        textLayer.foregroundColor = UIColor.black.cgColor
        textLayer.isHidden = true
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.fontSize = 11
        textLayer.font = UIFont(name: "Avenir", size: textLayer.fontSize)
        textLayer.alignmentMode = CATextLayerAlignmentMode.center
        
    }
    
    func addToLayer(_ parent: CALayer) {
        parent.addSublayer(shapeLayer)
        parent.addSublayer(textLayer)
        
    }
    
    func show(frame: CGRect, label: String, color: UIColor) {
        CATransaction.setDisableActions(true)
        
        let path = UIBezierPath(rect: frame)
        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.isHidden = false
        
        textLayer.string = label
        textLayer.backgroundColor = color.cgColor
        textLayer.isHidden = false
        
        let attributes = [
            NSAttributedString.Key.font: textLayer.font as Any
        ]
        
        let textRect = label.boundingRect(with: CGSize(width: 400, height: 100),
                                          options: .truncatesLastVisibleLine,
                                          attributes: attributes, context: nil)
        let textSize = CGSize(width: textRect.width + 12, height: textRect.height)
        let textOrigin = CGPoint(x: frame.origin.x - 2, y: frame.origin.y - textSize.height)
        textLayer.frame = CGRect(origin: textOrigin, size: textSize)
        
        
    }
    
    func hide() {
        shapeLayer.isHidden = true
        textLayer.isHidden = true
        
    }
}


