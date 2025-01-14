//
//  yolov8Manager.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/05/30.
//

import Foundation
import UIKit

struct Prediction {
    let classIndex: Int
    let score: Float
    let rect: CGRect
    let distance: Float?
    let userInIntersection: Bool
    let aheadIntersection: Bool
    var confirmation: confirmedShape
    
}

struct confirmedShape {
    var front: Bool = false
    var left: Bool = false
    var right: Bool = false
    var back: Bool = false
    
    var frontLeft: Bool = false
    var frontRight: Bool = false
    var backRight: Bool = false
    var backLeft: Bool = false
    
    func shapes() -> [String] {
        if self.front {
            if self.right && self.left {
                return ["Front","Left","Right"]
            } else if self.right {
                return ["Front","Right"]
            } else if self.left {
                return ["Front","Left"]
            }
        } else {
            if self.right && self.left {
                return ["Left","Right"]
            } else if self.right {
                return ["Right"]
            } else if self.left {
                return ["Left"]
            }
        }
        return []
    }

}

struct PredictionSummary {
    var isUserInIntersection: Bool = false
    var userInIntersectionID: Int = -1
    var isIntersectionAhead: Bool = false
    var aheadIntersectionID: Int = -1
    var distance: Float? = nil
}

enum DiagnoalDirection {
    case topLeftToBottomRight
    case topRightToBottomLeft
    case bottomRightToTopLeft
    case bottomLeftToTopRight
}

class YOLOv8 {
    public static let inputWidth = 128
    public static let inputHeight = 128
    
    public let labels = ["LB",
                  "LF",
                  "LRB",
                  "LRF",
                  "RFB",
                  "RB",
                  "RF",
                  "LRFB",
                  "LFB"]
    
    public let labelsForScan = [["Left"],
                                ["Left"],
                                ["Left","Right"],
                                ["Left","Right"],
                                ["Right"],
                                ["Right"],
                                ["Right"],
                                ["Left","Right"],
                                ["Left"]]
    
    // Tweak these values to get more or fewer predictions.
    var confidenceThreshold: Double = 0.05
    
    var iouThreshold: Double = 0.01
    let model: yolov8_2!
    
    init() {
        do {
            model = try yolov8_2()
            // Do something with the model
        } catch {
            // Handle the error locally
            print("An error occurred: \(error)")
            model = nil
        }
    }
    
    func isUserInIntersection(xyxy: [Float]) -> Bool{
        let xmin = xyxy[0]
        let ymin = xyxy[1]
        let xmax = xyxy[2]
        let ymax = xyxy[3]
        
        if (xmin < 64.0 && 64.0 < xmax) && (ymin < 64.0 && 64.0 < ymax) {
            return true
        }
        
        return false
    }
    
    func isIntersectionAhead(xyxy: [Float]) -> Bool{
        let xmin = xyxy[0]
        let ymin = xyxy[1]
        let xmax = xyxy[2]
        let ymax = xyxy[3]
        
        if (xmin < 64.0 && 64.0 < xmax) &&  ymax < 64.0 {
            return true
        }
        
        return false
    }
    
    func determineDistance(xyxy: [Float]) -> Float?{
        let xmin = xyxy[0]
        let ymin = xyxy[1]
        let xmax = xyxy[2]
        let ymax = xyxy[3]
        
        if !(xmin < 64.0 && 64.0 < xmax) { return nil }
        if ymax < 64.0 {
            let deltaPix = 64 - ymax
            return Float(deltaPix) * gridMapLength
        } else {
            return nil
        }
    }
    
    func predict(image: UIImage) -> (predictions: [Prediction], summary: PredictionSummary){
        var  predictions = [Prediction]()
        if let pixelBuffer = buffer(from: image) {
            do {
                let result_yolo = try model.prediction(image: pixelBuffer, iouThreshold: self.iouThreshold, confidenceThreshold: self.confidenceThreshold)
                
                let classConfidences = result_yolo.confidenceShapedArray.scalars
                let xywh = result_yolo.coordinatesShapedArray.scalars
                
                let numDetected = Int(classConfidences.count / labels.count)
                
                for i in 0..<numDetected {
                    let (classIndex, confidence) = Array(classConfidences[i*labels.count..<i*labels.count+labels.count]).argmax()
                    let bbox = decodeBbox(xywh: Array(xywh[i*4..<(i+1)*4]), imgsz: 128.0)
                    let prediction = Prediction(classIndex: classIndex,
                                                score: confidence,
                                                rect: CGRect(x: bbox["xywh"]![0].cgFloat(),
                                                             y: bbox["xywh"]![1].cgFloat(),
                                                             width: bbox["xywh"]![2].cgFloat(),
                                                             height: bbox["xywh"]![3].cgFloat()),
                                                distance: determineDistance(xyxy: bbox["xyxy"]!),
                                                userInIntersection: isUserInIntersection(xyxy: bbox["xyxy"]!),
                                                aheadIntersection: isIntersectionAhead(xyxy: bbox["xyxy"]!),
                                                confirmation: confirmedShape())
                    
                    predictions.append(prediction)
                    
                }
                
            }
            catch {
                print("error")
            }
            
            predictions = NMS(boxes: predictions, threshold: 0.1)
            predictions = confirmIntersection(pixelBuffer:pixelBuffer, predictions: predictions)
        }
        let summary = writeSummary(predictions: predictions)

        return (predictions: predictions, summary: summary)
    }
    
    func writeSummary(predictions: [Prediction]) -> PredictionSummary{
        var summary = PredictionSummary()
        
        for (i, prediction) in predictions.enumerated() {
            if prediction.userInIntersection {
                summary.isUserInIntersection = true
                summary.userInIntersectionID = i
            }
            
            if prediction.aheadIntersection, let distance = prediction.distance {
                if !summary.isIntersectionAhead {
                    summary.isIntersectionAhead = true
                    summary.aheadIntersectionID = i
                    summary.distance = distance
                } else {
                    if distance < summary.distance! {
                        summary.aheadIntersectionID = i
                        summary.distance = prediction.distance
                    }
                }
            }
        }
        
        return summary
    }
    
    func decodeBbox(xywh: [Float], imgsz: Float) -> [String: [Float]]{
        var result: [String: [Float]] = [:]
        let scaled = xywh.map{$0 * imgsz}
        let xmin = scaled[0] - scaled[2] / 2
        let xmax = scaled[0] + scaled[2] / 2
        let ymin = scaled[1] - scaled[3] / 2
        let ymax = scaled[1] + scaled[3] / 2
        
        result["xywh"] = [xmin, ymin, scaled[2], scaled[3]]
        result["xyxy"] = [xmin, ymin, xmax, ymax]
        return result
    }
    
    func buffer(from image: UIImage) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        var pixelBuffer : CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.size.width), Int(image.size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard (status == kCVReturnSuccess) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData, width: Int(image.size.width), height: Int(image.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        context?.translateBy(x: 0, y: image.size.height)
        context?.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context!)
        image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
    
    func NMS(boxes: [Prediction], threshold: Float) -> [Prediction] {
        // Do an argsort on the confidence scores, from high to low.
        let sortedIndices = boxes.indices.sorted { boxes[$0].score > boxes[$1].score }
        var selected = [Prediction]()
        
        // The algorithm is simple: Start with the box that has the highest score.
        // Remove any remaining boxes that overlap it more than the given threshold
        // amount. If there are any boxes left (i.e. these did not overlap with any
        // previous boxes), then repeat this procedure, until no more boxes remain
        // or the limit has been reached.
        var remaining = Set(sortedIndices)
        
        while let currentIdx = remaining.first {
            selected.append(boxes[currentIdx])
            remaining.remove(currentIdx)
            
            for idx in remaining {
                let boxB = boxes[sortedIndices[idx]]
                if IOU(a: boxes[currentIdx].rect, b: boxB.rect) > threshold {
                    remaining.remove(idx)
                }
            }
        }
        
        return selected
    }

    
    private func IOU(a: CGRect, b: CGRect) -> Float {
       let areaA = a.width * a.height
       if areaA <= 0 { return 0 }
       
       let areaB = b.width * b.height
       if areaB <= 0 { return 0 }
       
       let intersectionMinX = max(a.minX, b.minX)
       let intersectionMinY = max(a.minY, b.minY)
       let intersectionMaxX = min(a.maxX, b.maxX)
       let intersectionMaxY = min(a.maxY, b.maxY)
       let intersectionArea = max(intersectionMaxY - intersectionMinY, 0) *
           max(intersectionMaxX - intersectionMinX, 0)
       return Float(intersectionArea / (areaA + areaB - intersectionArea))
    }
    
    func confirmIntersection(pixelBuffer: CVPixelBuffer, predictions: [Prediction]) -> [Prediction]{
                
        var confirmed = [Prediction]()
        for prediction in predictions {
            let frontPath = determinePathExistsFB(prediction: prediction, pixelBuffer: pixelBuffer, direction: "Front")
            let leftPath = determinePathExistsLR(prediction: prediction, pixelBuffer: pixelBuffer, direction: "Left")
            let rightPath = determinePathExistsLR(prediction: prediction, pixelBuffer: pixelBuffer, direction: "Right")
            let backPath = determinePathExistsFB(prediction: prediction, pixelBuffer: pixelBuffer, direction: "Back")
            
            let frontLeft = determinePathExistsDiag(prediction: prediction, pixelBuffer: pixelBuffer, direction: .bottomRightToTopLeft)
            let frontRight = determinePathExistsDiag(prediction: prediction, pixelBuffer: pixelBuffer, direction: .bottomLeftToTopRight)
            let backLeft = determinePathExistsDiag(prediction: prediction, pixelBuffer: pixelBuffer, direction: .topRightToBottomLeft)
            let backRight = determinePathExistsDiag(prediction: prediction, pixelBuffer: pixelBuffer, direction: .topLeftToBottomRight)
            
            var tmpPrediction = prediction
            tmpPrediction.confirmation.front = frontPath
            tmpPrediction.confirmation.left = leftPath
            tmpPrediction.confirmation.right = rightPath
            tmpPrediction.confirmation.back = backPath
            
            tmpPrediction.confirmation.frontLeft = frontLeft
            tmpPrediction.confirmation.frontRight = frontRight
            tmpPrediction.confirmation.backRight = backLeft
            tmpPrediction.confirmation.backLeft = backRight
            
            confirmed.append(tmpPrediction)
        }
        return confirmed
    }
    
    func determinePathExistsFB(prediction: Prediction, pixelBuffer: CVPixelBuffer, direction: String, ratio: CGFloat = 0.20, lengthThreshold: Float = 1.0) -> Bool{
        
        var minX: Int!
        var maxX: Int!
        var minY: Int!
        var maxY: Int!
        
        assert(direction == "Front" || direction == "Back")
        let rect = adjustRectWithinImageBounds(rect: prediction.rect)
        
        minX = rect.minX.int()
        maxX = rect.maxX.int()
        var rangeY: [Int]!
        
        
        if direction == "Front" {
            minY = 0
            maxY = max(0, rect.minY.int())
            rangeY = Array(minY..<maxY).reversed()
        } else {
            minY = min(rect.maxY.int(), 127)
            maxY = 127
            rangeY = Array(minY..<maxY)
        }
        
        var floorCount: Int = 0
        var noFloorCount: Int = 0
        
        var maxDist = -1
        
        for y in rangeY{
            var floorFound = false
            
            for x in minX..<maxX{
                let (_, red, green, blue) = getColorFromPixelBuffer(pixelBuffer: pixelBuffer, x: x, y: y)
                let classifiedColor = checkColorCategory(value: red)
                if classifiedColor == "White" {
                    floorFound = true
                    noFloorCount = 0
                    floorCount += 1
                    let dist: Int!
                    
                    if direction == "Front" {
                        dist = abs(rect.minY.int() - y)
                    } else if  direction == "Left" {
                        dist = abs(rect.minX.int() - x)
                    } else if direction == "Right"{
                        dist = abs(rect.maxX.int() - x)
                    } else {
                        dist = abs(rect.maxY.int() - y)
                    }
                    
                    if dist > maxDist {
                        maxDist = dist
                    }
                }
            }
            
            if !floorFound { noFloorCount += 1 }
            if noFloorCount >= 3 { break }
        }
        
        let sufficientLength = maxDist > Int(lengthThreshold / gridMapLength)
        let sufficientCount = floorCount > Int(prediction.rect.height * prediction.rect.width * ratio)
        let confirmed = sufficientLength && sufficientCount
        return confirmed
    }
    
    func determinePathExistsLR(prediction: Prediction, pixelBuffer: CVPixelBuffer, direction: String, ratio: CGFloat = 0.20, lengthThreshold: Float = 1.0) -> Bool{
        
        var minX: Int!
        var maxX: Int!
        var minY: Int!
        var maxY: Int!
        var rangeX: [Int]!
        
        assert(direction == "Left" || direction == "Right")
        let rect = adjustRectWithinImageBounds(rect: prediction.rect)

        minY = rect.minY.int()
        maxY = rect.maxY.int()

        if  direction == "Left" {
            minX = 0
            maxX = min(127, rect.minX.int())
            rangeX = Array(minX..<maxX).reversed()
        } else {
            minX = max(0, rect.maxX.int())
            maxX = 127
            rangeX = Array(minX..<maxX)
        }
        
        var floorCount: Int = 0
        var noFloorCount: Int = 0
        var maxDist = -1
        
        for x in rangeX{
            var floorFound = false
            
            for y in minY..<maxY{
                let (alpha, red, green, blue) = getColorFromPixelBuffer(pixelBuffer: pixelBuffer, x: x, y: y)
                let classifiedColor = checkColorCategory(value: red)
                if classifiedColor == "White" {
                    floorFound = true
                    floorCount += 1
                    let dist: Int!
                    
                    if direction == "Front" {
                        dist = abs(rect.minY.int() - y)
                    } else if  direction == "Left" {
                        dist = abs(rect.minX.int() - x)
                    } else if direction == "Right"{
                        dist = abs(rect.maxX.int() - x)
                    } else {
                        dist = abs(rect.maxY.int() - y)
                    }
                    
                    if dist > maxDist {
                        maxDist = dist
                    }
                }
            }
            
            if !floorFound { noFloorCount += 1 }
            if noFloorCount >= 3 { break }
        }
        
        let sufficientLength = maxDist > Int(lengthThreshold / gridMapLength)
        let sufficientCount = floorCount > Int(prediction.rect.height * prediction.rect.width * ratio)
        let confirmed = sufficientLength && sufficientCount
        return confirmed
    }
    
    func determinePathExistsDiag(prediction: Prediction, pixelBuffer: CVPixelBuffer, direction: DiagnoalDirection, ratio: CGFloat = 0.20, lengthThreshold: Float = 1.0) -> Bool{

        var floorCount: Int = 0
        var maxDist: Float = -1
        
        switch direction {
        case .topLeftToBottomRight:
            let translatedRect = translateRect(rect: prediction.rect, dx: prediction.rect.width, dy: prediction.rect.height)
            let rect = adjustRectWithinImageBounds(rect: translatedRect)
            let bottomRight = SIMD2<Int>(Int(prediction.rect.maxX),Int(prediction.rect.maxY))
            
            let width = Int(rect.width)
            let height = Int(rect.height)
            for i in 0..<(width + height) {
                for j in max(0, i - height)..<min(i + 1, width) {
                    let x = j
                    let y = i - j
                    if !isValueInRange(value: x, min: 0, max: 127) { continue }
                    if !isValueInRange(value: y, min: 0, max: 127) { continue }

                    let (alpha, red, green, blue) = getColorFromPixelBuffer(pixelBuffer: pixelBuffer, x: x, y: y)
                    let classifiedColor = checkColorCategory(value: red)
                    if classifiedColor == "White" {
                        floorCount += 1
                        let dist = bottomRight.distanceTo(x: x, y: y)
                        
                        if dist > maxDist {
                            maxDist = dist
                        }
                    }
                }
            }
        case .topRightToBottomLeft:
            let translatedRect = translateRect(rect: prediction.rect, dx: -prediction.rect.width, dy: prediction.rect.height)
            let rect = adjustRectWithinImageBounds(rect: translatedRect)
            let bottomLeft = SIMD2<Int>(Int(prediction.rect.maxX),Int(prediction.rect.maxY))
            
            let width = Int(rect.width)
            let height = Int(rect.height)
            for i in 0..<(width + height) {
                for j in max(0, i - height)..<min(i + 1, width) {
                    let x = width - j - 1
                    let y = i - j
                    if !isValueInRange(value: x, min: 0, max: 127) { continue }
                    if !isValueInRange(value: y, min: 0, max: 127) { continue }

                    let (alpha, red, green, blue) = getColorFromPixelBuffer(pixelBuffer: pixelBuffer, x: x, y: y)
                    let classifiedColor = checkColorCategory(value: red)
                    if classifiedColor == "White" {
                        floorCount += 1
                        let dist = bottomLeft.distanceTo(x: x, y: y)
                        
                        if dist > maxDist {
                            maxDist = dist
                        }
                    }
                }
            }
        case .bottomRightToTopLeft:
            let translatedRect = translateRect(rect: prediction.rect, dx: -prediction.rect.width, dy: -prediction.rect.height)
            let rect = adjustRectWithinImageBounds(rect: translatedRect)
            let topLeft = SIMD2<Int>(Int(prediction.rect.maxX),Int(prediction.rect.maxY))
            
            let width = Int(rect.width)
            let height = Int(rect.height)
            for i in 0..<(width + height) {
                for j in max(0, i - height)..<min(i + 1, width) {
                    let x = width - j - 1
                    let y = height - (i - j) - 1
                    if !isValueInRange(value: x, min: 0, max: 127) { continue }
                    if !isValueInRange(value: y, min: 0, max: 127) { continue }

                    let (alpha, red, green, blue) = getColorFromPixelBuffer(pixelBuffer: pixelBuffer, x: x, y: y)
                    let classifiedColor = checkColorCategory(value: red)
                    if classifiedColor == "White" {
                        floorCount += 1
                        let dist = topLeft.distanceTo(x: x, y: y)
                        
                        if dist > maxDist {
                            maxDist = dist
                        }
                    }
                }
            }
        case .bottomLeftToTopRight:
            let translatedRect = translateRect(rect: prediction.rect, dx: -prediction.rect.width, dy: prediction.rect.height)
            let rect = adjustRectWithinImageBounds(rect: translatedRect)
            let topRight = SIMD2<Int>(Int(prediction.rect.maxX),Int(prediction.rect.maxY))
            
            let width = Int(rect.width)
            let height = Int(rect.height)
            for i in 0..<(width + height) {
                for j in max(0, i - height)..<min(i + 1, width) {
                    let x = j
                    let y = height - (i - j) - 1
                    if !isValueInRange(value: x, min: 0, max: 127) { continue }
                    if !isValueInRange(value: y, min: 0, max: 127) { continue }
                    
                    let (alpha, red, green, blue) = getColorFromPixelBuffer(pixelBuffer: pixelBuffer, x: x, y: y)
                    let classifiedColor = checkColorCategory(value: red)
                    if classifiedColor == "White" {
                        floorCount += 1
                        let dist = topRight.distanceTo(x: x, y: y)
                        
                        if dist > maxDist {
                            maxDist = dist
                        }
                    }
                }
            }
        }
        
        let sufficientLength = maxDist > Float(lengthThreshold / gridMapLength)
        let sufficientCount = floorCount > Int(prediction.rect.height * prediction.rect.width * ratio)
        let confirmed = sufficientLength && sufficientCount
        return confirmed
    }

    func translateRect(rect: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        return CGRect(x: rect.minX + dx, y: rect.minY + dy, width: rect.width, height: rect.height)
    }
    
    
    func adjustRectWithinImageBounds(rect: CGRect) -> CGRect {
        let imageWidth: CGFloat = 127
        let imageHeight: CGFloat = 127
        
        var adjustedRect = rect
        
        // Check if any part of the rect is outside the image boundaries and adjust if needed
        if adjustedRect.minX < 0 {
            adjustedRect.origin.x = 0
        }
        
        if adjustedRect.maxX > imageWidth {
            let overflow = adjustedRect.maxX - imageWidth
            adjustedRect.size.width -= overflow
        }
        
        if adjustedRect.minY < 0 {
            adjustedRect.origin.y = 0
        }
        
        if adjustedRect.maxY > imageHeight {
            let overflow = adjustedRect.maxY - imageHeight
            adjustedRect.size.height -= overflow
        }
        
        return adjustedRect
    }
    
    func getColorFromPixelBuffer(pixelBuffer: CVPixelBuffer, x: Int, y: Int) -> (alpha: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat){
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return (0,0,0,0) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerPixel = 4 // Assuming 32-bit RGBA pixel format
        
        let pixelData = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        let pixelOffset = y * bytesPerRow + x * bytesPerPixel
        let alpha = CGFloat(pixelData[pixelOffset])
        let red = CGFloat(pixelData[pixelOffset + 1])
        let green = CGFloat(pixelData[pixelOffset + 2])
        let blue = CGFloat(pixelData[pixelOffset + 3])
        
        return (alpha: alpha ,red: red, green: green, blue: blue)
        
        
    }
    
    func checkColorCategory(value: CGFloat) -> String {
        let closestValue: CGFloat = [0.0, 128.0, 255.0].min { abs($0 - value) < abs($1 - value) } ?? 0.0
        
        if closestValue == 0.0 {
            return "Black"
        } else if closestValue == 128.0 {
            return "Gray"
        } else {
            return "White"
        }
    }
    
}

extension Float{
    func cgFloat() -> CGFloat{
        return CGFloat(self)
    }
}

extension [Float] {
   public func argmax() -> (Int, Element) {
       precondition(self.count > 0)
       var maxIndex = 0
       var maxValue = self[0]
       for i in 1..<self.count {
           if self[i] > maxValue {
               maxValue = self[i]
               maxIndex = i
           }
       }
       return (maxIndex, maxValue)
   }
}

extension CGFloat {
    func int() -> Int{
        return Int(self)
    }
}

extension SIMD2<Int> {
    func distanceTo(x: Int, y: Int) -> Float {
        let dx = Float(self.x - x)
        let dy = Float(self.y - y)
        return sqrt(dx*dx+dy*dy)
    }
}

