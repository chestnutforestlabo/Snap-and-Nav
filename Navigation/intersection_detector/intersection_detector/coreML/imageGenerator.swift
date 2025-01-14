//
//  imageGenerator.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/05/30.
//

import UIKit
import Foundation
import CoreML
import Vision

let customGray = UIColor.init(white: 128 / 255, alpha: 1.0)

extension UIColor {
    func image(_ size: CGSize = CGSize(width: 1, height: 1)) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { rendererContext in
            self.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: size))
        }
    }
}

extension UIImage {
    func rotatedBy(degree: CGFloat) -> UIImage? {
        guard let cgImage = cgImage else { return nil }
        UIGraphicsBeginImageContextWithOptions(size, false, 0) //checkout if set to true
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        defer { UIGraphicsEndImageContext() }
        UIColor.init(white: 128 / 255, alpha: 1.0).setFill()
        context.fill(.init(origin: .zero, size: size))
        context.translateBy(x: size.width/2, y: size.height/2)
        context.scaleBy(x: 1, y: -1)
        context.rotate(by: -degree * .pi / 180)
        context.draw(cgImage, in: CGRect(origin: .init(x: -size.width/2, y: -size.height/2), size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

class imageRotationManager {
    
    var pastPositions: [gridIndex] = []
    let distanceThreshold: Float = 3.0
    let imageOrientation = SIMD2<Float>(0,-1)
    let useWallAnglesDiffThresh: Float = 45
    
    func generateRotatedImage(imageDict: [gridIndex : gridValue], userGridPosition: gridIndex, deviceMatrix: simd_float4x4, statusManager: userStatusManager) -> UIImage{
        let angle = calculateAverageAngleOverTime(userGridPosition: userGridPosition, deviceMatrix: deviceMatrix)
        let image = rotatedImage(imageDict: imageDict, userGridPosition: userGridPosition, angle: Float(-angle))!
        return image
    }
    
    func generateRotatedImage(imageDict: [gridIndex : gridValue], userGridPosition: gridIndex, deviceMatrix: simd_float4x4, wallInformation: [UUID:simd_float4x4], statusManager: userStatusManager) -> (image: UIImage, alignmentAngle: Float, isAngleFromWall: Bool){
        let alignmentAngle: Float!
        let isAngleFromWall: Bool!
        print("==================================================================")
        print("statusManager.inIntersection \(statusManager.inIntersection) statusManager.intersectionAhead \(statusManager.intersectionAhead) statusManager.previouslyIsUserInIntersection \(statusManager.previouslyIsUserInIntersection)")
        if statusManager.inIntersection || statusManager.intersectionAhead || statusManager.previouslyIsUserInIntersection {
            alignmentAngle = statusManager.previousAlignmentAngle
            isAngleFromWall = true
            print("use previous alignment \(alignmentAngle)")
        } else {
            print("calculateAngle")
            (alignmentAngle, isAngleFromWall) = calculateAngle(userGridPosition: userGridPosition, deviceMatrix: deviceMatrix, wallInformation: wallInformation, statusManager: statusManager)
        }
        
        let image = rotatedImage(imageDict: imageDict, userGridPosition: userGridPosition, angle: Float(-alignmentAngle))!
        return (image: image, alignmentAngle: alignmentAngle, isAngleFromWall: isAngleFromWall)
    }
    
    
    func calculateAngle(userGridPosition: gridIndex, deviceMatrix: simd_float4x4, wallInformation: [UUID:simd_float4x4], statusManager: userStatusManager) -> (Float, Bool) {
        
        let deviceOrientaion = statusManager.averageOrientation
        let cosine = dot(imageOrientation,deviceOrientaion)
        let angleOriginal = acos(cosine)
        let finalAngleOriginal = deviceOrientaion.x > 0 ? angleOriginal * 180 / Float.pi : -angleOriginal * 180 / Float.pi
        
        let devicePosition = deviceMatrix.columns.3
    
        if wallInformation.count > 0 {
            
            var selectedWallUuid: UUID? = nil
            var biggestAngle: Float = 0
            
            for (uuid, wallMatrix) in wallInformation {
                let planeOrientation = wallMatrix.columns.1
                let wallNormal = normalize(SIMD2<Float>(planeOrientation.x, planeOrientation.z))
                let dotProduct = dot(deviceOrientaion, wallNormal)
                let magProduct = length(deviceOrientaion) * length(wallNormal)
                let angle = acos(abs(dotProduct) / magProduct)
                let angleDegrees = angle * 180 / .pi
                
                let planePosition = wallMatrix.columns.3
                let distanceXY = simd_distance(simd_float2(devicePosition.x, devicePosition.z), simd_float2(planePosition.x, planePosition.z))

                if angleDegrees > biggestAngle && distanceXY < distanceThreshold {
                    biggestAngle = angleDegrees
                    selectedWallUuid = uuid
                }
            
            }
            
            guard let selectedSafeWallUuid = selectedWallUuid else {
                print("no wall finalAngleOriginal \((finalAngleOriginal, false))")
                return (finalAngleOriginal, false)
            }
            
            let planeAnchorTransform = wallInformation[selectedSafeWallUuid]
            let planeOrientation = planeAnchorTransform!.columns.1
            
            let normalVectorPlane = normalize(SIMD2<Float>(planeOrientation.x, planeOrientation.z))
            let normalVectorRotatedPlus = SIMD2<Float>(-normalVectorPlane.y, normalVectorPlane.x) // +90deg
            let normalVectorRotatedMinus = SIMD2<Float>(normalVectorPlane.y, -normalVectorPlane.x) // -90deg
            let dotProductPlus = dot(normalVectorRotatedPlus, deviceOrientaion)
            let dotProductMinus = dot(normalVectorRotatedMinus, deviceOrientaion)
            
            let wallOrientation: SIMD2<Float> = dotProductPlus > dotProductMinus ? normalVectorRotatedPlus : normalVectorRotatedMinus
            let dotProductWall = dot(imageOrientation, wallOrientation)
            let angleWithhWall = acos(dotProductWall)
            let finalAngleWall = deviceOrientaion.x > 0 ? angleWithhWall * 180 / Float.pi : -angleWithhWall * 180 / Float.pi
            
            if abs(finalAngleWall - finalAngleOriginal) < useWallAnglesDiffThresh {
                print("finalAngleWall \((finalAngleOriginal, true))")
                return (finalAngleWall, true)
            } else {
                print("finalAngleOriginal \((finalAngleOriginal, false))")
                return (finalAngleOriginal, false)
            }
        }
        
        print("END finalAngleOriginal \((finalAngleOriginal, false))")
        return (finalAngleOriginal, false)
    }
    
    func calculateAverageAngleOverTime(userGridPosition: gridIndex, deviceMatrix: simd_float4x4) -> Float{
        pastPositions.append(userGridPosition)
        if pastPositions.count >= N + 1{ pastPositions.remove(at: 0) }
        
        let deviceOrientationCol1 = deviceMatrix.columns.1
        let deviceOrientation = normalize(SIMD2<Float>(deviceOrientationCol1.z,-deviceOrientationCol1.x))
        
        
        if pastPositions.count < N  {
            let cosine = dot(imageOrientation,deviceOrientation)
            let angle = acos(cosine)
            if deviceOrientation.x > 0 {
                return angle * 180 / Float.pi
            } else {
                return -angle * 180 / Float.pi
            }
        } else {
            let aveposA = calculateAverage(i: pastPositions.count - 1, n: N / 2, pastPositions: pastPositions)
            let aveposB = calculateAverage(i: pastPositions.count - 1 - N / 2, n: N / 2, pastPositions: pastPositions)
            let tmp_averageVelocity = simd_float2(Float(aveposA.x - aveposB.x), Float(aveposA.y - aveposB.y))
            let velocityNorm = (tmp_averageVelocity / Float((Float(N) / 2) * (1 / Float(fps)))).determinant()
            if velocityNorm > velocityNormThreshold{
                let averageVelocity = normalize(tmp_averageVelocity)
                let cosine = dot(imageOrientation,averageVelocity)
                let angle = acos(cosine)
                if angle.isNaN {
                    let cosine = dot(imageOrientation,deviceOrientation)
                    let angle = acos(cosine)
                    if deviceOrientation.x > 0 {
                        return angle * 180 / Float.pi
                    } else {
                        return -angle * 180 / Float.pi
                    }
                } else {
                    if averageVelocity.x > 0 {
                        return angle * 180 / Float.pi
                    } else {
                        return -angle * 180 / Float.pi
                    }
                }
            } else {
                let cosine = dot(imageOrientation,deviceOrientation)
                let angle = acos(cosine)
                if deviceOrientation.x > 0 {
                    return angle * 180 / Float.pi
                } else {
                    return -angle * 180 / Float.pi
                }
            }
        }
    }
    
    
    func rotatedImage(width: CGFloat = 128, height: CGFloat = 128, imageDict:[gridIndex:gridValue], userGridPosition: gridIndex, angle: Float) -> UIImage? {
        let grayimg = customGray.image(CGSize(width: width, height: height))
        
        guard let gray =  grayimg.cgImage else {
            return nil
        }
        
        let colorSpace       = CGColorSpaceCreateDeviceGray()
        let width            = Int(width)
        let height           = Int(height)
        
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            print("error")
            return nil
        }
        
        context.draw(gray, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let buffer = context.data else {
            return nil
        }
        
        let pixelBuffer = buffer.bindMemory(to: UInt8.self, capacity: width * height)
        
        let black: UInt8 = 0
        let white: UInt8 = 255
        
        for (gridIndexKey, gridvalue) in imageDict {
            let column = gridIndexKey.x + width / 2 - userGridPosition.x
            let row = gridIndexKey.y + width / 2 - userGridPosition.y
            let offset = row * width + column
            if gridvalue.gridClass == .floor {
                pixelBuffer[offset] = white
            } else {
                pixelBuffer[offset] = black
            }
        }
        
        let outputCGImage = context.makeImage()!
        let outputImage = UIImage(cgImage: outputCGImage).rotatedBy(degree: CGFloat(angle))
        return outputImage
    }

}
