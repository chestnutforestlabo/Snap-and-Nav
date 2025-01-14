//
//  utils.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/06/01.
//

import Foundation
import SceneKit
import UIKit
import ARKit

struct NecessaryMatrixForPointCloudCalculation {
    var localToWorld: matrix_float4x4!
    var cameraIntrinsicsInversed: matrix_float3x3!
    var cameraResolution: simd_float2!
    var currentHeight: Float!
}

class gridMapUtilities {
    private let orientation = UIInterfaceOrientation.portrait
    
    func getLocaltoWorld(camera: ARCamera) -> matrix_float4x4{
        let viewMatrix = camera.viewMatrix(for: orientation)
        let viewMatrixInversed = viewMatrix.inverse
        let rotateToARCamera = makeRotateToARCameraMatrix(orientation: orientation)
        let localToWorld = viewMatrixInversed * rotateToARCamera
        return localToWorld
    }
    
    func getNecessaryMatrixForPointCloudCalculation(camera: ARCamera) -> NecessaryMatrixForPointCloudCalculation{
        let viewMatrix = camera.viewMatrix(for: orientation)
        let viewMatrixInversed = viewMatrix.inverse
        let rotateToARCamera = makeRotateToARCameraMatrix(orientation: orientation)
        let cameraIntrinsicsInversed = camera.intrinsics.inverse
        let localToWorld = viewMatrixInversed * rotateToARCamera
        let currentHeight = camera.transform.columns.3[1]
        let cameraResolution = simd_float2(Float(camera.imageResolution.width), Float(camera.imageResolution.height))
        let necessaryMatrixForPointCloudCalculation =  NecessaryMatrixForPointCloudCalculation(localToWorld: localToWorld,
                                                                                               cameraIntrinsicsInversed: cameraIntrinsicsInversed,
                                                                                               cameraResolution: cameraResolution,
                                                                                               currentHeight: currentHeight)
        return necessaryMatrixForPointCloudCalculation
    }
    
    func getMatrix(camera: ARCamera, localToWorld: matrix_float4x4) -> matrix_float4x4{

        let rotationMatrixZ = simd_float4x4(simd_quatf(angle: camera.eulerAngles.z, axis: simd_float3(0, 0, 1)))
        let rotationMatrixY = simd_float4x4(simd_quatf(angle: -camera.eulerAngles.y, axis: simd_float3(1, 0, 0)))
        let translationMatrixPlus = simd_float4x4([1,0,0,0],[0,1,0,0],[0,0,1,0],localToWorld[3])
        let matrix = translationMatrixPlus * rotationMatrixZ * rotationMatrixY
        return matrix
    }
    
    private func makeRotateToARCameraMatrix(orientation: UIInterfaceOrientation) -> matrix_float4x4 {
        let identityMatrix = matrix_float4x4(
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1] )
        
        let rotationAngle = Float(cameraToDisplayRotation(orientation: orientation)) * .degreesToRadian
        return identityMatrix * matrix_float4x4(simd_quaternion(rotationAngle, Float3(0, 0, 1)))
    }
    
    private func cameraToDisplayRotation(orientation: UIInterfaceOrientation) -> Int {
        switch orientation {
        case .landscapeLeft:
            return 180
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return -90
        default:
            return 0
        }
    }
    
    func getWorldPositionIndexKey(angle: Float, radius: Float = 1, matrix: matrix_float4x4) -> gridIndex{
        let sine = sin(angle * .degreesToRadian) * radius
        let cosine = cos(angle * .degreesToRadian) * radius
        let pos = simd_float4(0,-sine,-cosine,1)
        let worldPos = matrix * pos
        let gridIndexKey = simd_float3(worldPos.x,worldPos.y,worldPos.z).getGridIndex()
        return gridIndexKey
    }
    
    func getIndexInFrontOfUser(matrix: matrix_float4x4) -> gridIndex {
        return getWorldPositionIndexKey(angle: 0, matrix: matrix)
    }
}



struct AppUtility {

    static func lockOrientation(_ orientation: UIInterfaceOrientationMask) {
    
        if let delegate = UIApplication.shared.delegate as? AppDelegate {
            delegate.orientationLock = orientation
        }
    }

    /// OPTIONAL Added method to adjust lock and rotate to the desired orientation
    static func lockOrientation(_ orientation: UIInterfaceOrientationMask, andRotateTo rotateOrientation:UIInterfaceOrientation) {
   
        self.lockOrientation(orientation)
    
        UIDevice.current.setValue(rotateOrientation.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
    }

}
