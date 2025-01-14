//
//  helpers.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2021/05/14.
//

import Foundation
import SceneKit
import ARKit

typealias Float2 = SIMD2<Float>
typealias Float3 = SIMD3<Float>

extension Float {
    static let degreesToRadian = Float.pi / 180
}

extension simd_float4x4{
    func makeSCNVector3ForSceneview() -> SCNVector3{
        return SCNVector3(x: self.columns.3[0], y: self.columns.3[1], z: self.columns.3[2])
    }
    
    func getGridIndex() -> gridIndex{
        return gridIndex(x: Int(round(self.columns.3[0] / gridMapLength)) , y: Int(round(self.columns.3[2] / gridMapLength)))
    }
}

extension SCNVector3{
    func getGridIndex() -> gridIndex{
        return gridIndex(x: Int(round(self.x / gridMapLength)) , y: Int(round(self.z / gridMapLength)))
    }
}

extension simd_float3 {
    func getGridIndex() -> gridIndex {
        return gridIndex(x: Int(roundf(self.x / gridMapLength)) , y: Int(roundf(self.z / gridMapLength)))
    }
}

extension simd_float2 {
    func determinant() -> Float {
        return (self.x * self.x + self.y * self.y).squareRoot()
    }
}

func calculateAngle(vectorA: simd_float2, vectorB: simd_float2) -> Float{
    let corssProduct = cross(vectorA, vectorB)
    let cosine = dot(normalize(vectorA),normalize(vectorB))
    var angle = acos(cosine) / .degreesToRadian
    angle *= corssProduct.z > 0 ? 1 : -1 //left is plus, right is minus
    return angle
}


func imgToWorldCoord(x: CGFloat, y: CGFloat, angle: Float, userGridPosition: gridIndex, imgSize: Float) -> gridIndex { //convert img coordinate to world coordinate
    let rotated = rotateInImg(gIndex: gridIndex(x: Int(x), y: Int(y)), degree: -angle, imgSize: imgSize)
    let gIndex = convertImageToWorld(imgX: Float(rotated.x), imgY: Float(rotated.y), userGridPosition: userGridPosition, imgSize: imgSize)
    return gIndex
}

func rotateInImg(gIndex: gridIndex, degree: Float, imgSize: Float) -> gridIndex {
    let angle = degree * Float.degreesToRadian
    let half = Int(imgSize * 0.5)
    let newGridIndex = gridIndex(x: gIndex.x - half, y: -(gIndex.y - half) )
    let xRotated = Float(newGridIndex.x) * cos(angle) - Float(newGridIndex.y) * sin(angle)
    let yRotated = Float(newGridIndex.x) * sin(angle) + Float(newGridIndex.y) * cos(angle)
    let imageIndex = gridIndex(x: Int(xRotated + Float(half)), y: Int(-yRotated + Float(half)))
    return imageIndex
}

func convertImageToWorld(imgX: Float, imgY: Float, userGridPosition: gridIndex, imgSize: Float) -> gridIndex {
    let half = Float(imgSize * 0.5)
    let x = Float(imgX - half) + Float(userGridPosition.x)
    let y = Float(imgY - half) + Float(userGridPosition.y)
    return gridIndex(x: Int(x), y: Int(y))
}

func rotateVector(vector: SIMD2<Float> , angleDegrees: Float) -> SIMD2<Float> {
    let angleRadians = angleDegrees * .pi / 180.0
    let cosAngle = cos(angleRadians)
    let sinAngle = sin(angleRadians)
    
    let rotatedX = vector.x * cosAngle - vector.y * sinAngle
    let rotatedY = vector.x * sinAngle + vector.y * cosAngle
    
    return normalize(SIMD2<Float>(rotatedX, rotatedY))
}

func calculateAngle(_ vector1: SIMD2<Float>,_ vector2: SIMD2<Float>) -> Float{
    var cosine = dot(vector1,vector2) / (length(vector1) * length(vector2))
    cosine = max(-1,cosine)
    cosine = min(1,cosine)
    let angle = acos(cosine) * 180 / .pi
    return angle
}
