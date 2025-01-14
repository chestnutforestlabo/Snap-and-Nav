//
//  CWalkerController.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/06/04.
//


import UIKit
import SceneKit
import ARKit
import MetalKit
import Metal
import AVFoundation

protocol CWalkerControllerDelegate: AnyObject {
    func didFinishNavigation(arrivedDestination: String, scale: Float!, scaleTracker: ScaleTracker)
    func didUpdate(gridMapImage: UIImage)
    func didUpdate(userGridPosition: gridIndex)
    func didUpdate(intersections: [intersection])
    func didUpdate(labelString: String)
    func didUpdate(sessionInfoString: String)
    func didUpdate(boundingBoxes: [Prediction], labels: [String])
    func didUpdateSpeech(fbType: feedbackType, fbInfoCapsule: feedBackInformationCapsule)
    func didUpdateSound()
    func didUpdateClose(vibrationState: VibrationState)
}

enum VibrationState {
    case start
    case stop
}

enum SystemState: Int {
    case initial = 0
    case corridorNavigation = 1
    case inIntersection = 2
}


class CWalkerController: NSObject, ARSessionDelegate {
    
    weak var delegate: CWalkerControllerDelegate?

    var session: ARSession!
    
    var yolov8Model: YOLOv8!
    var pcCalculator: pointCloudCalculator!
    var gridMap: gMapping!
    var imageManager: imageRotationManager!
    var gMapUtils: gridMapUtilities!
    var statusManager: userStatusManager!
    var intersectionTracker: intersectionTrackingManager!
    var routeTracker: routeTrackingManager!
    var nodeMapManager: nodeMapManager!
    
    var wallInformation: [UUID:simd_float4x4] = [:]

    var floorHeight: Float = 0
    var start: Bool = false
    var systemMode: SystemMode!
    
    let remainingDistanceThreshold: Float = 2.0
    
    var systemState: SystemState = .initial
    
    init(session: inout ARSession ,nodeMapManage: nodeMapManager, scale: Float!, scaleTracker: ScaleTracker, systemMode: SystemMode) {
        super.init()
        
        self.session = session
        self.session.delegate = self
        self.systemMode = systemMode
        
        yolov8Model = YOLOv8()
        pcCalculator = pointCloudCalculator()
        gridMap = gMapping()
        imageManager = imageRotationManager()
        gMapUtils = gridMapUtilities()
        statusManager = userStatusManager()
        intersectionTracker = intersectionTrackingManager()
        nodeMapManager = nodeMapManage
        routeTracker = routeTrackingManager(nodeMapManager: nodeMapManager, scale: scale, scaleTracker: scaleTracker)
        
        mainFunction()
    }
    
    
    func mainFunction() {
        let timeStartProcess = Date()
        
        if start,
           let depthMap = session.currentFrame?.sceneDepth?.depthMap,
           let confidenceMap = session.currentFrame?.sceneDepth?.confidenceMap,
           let camera = session.currentFrame?.camera{
            
            let deviceMatrix = camera.transform
            let userGridPosition = deviceMatrix.getGridIndex()
                        
            let necessaryMatrixForPointCloudCalculation = gMapUtils.getNecessaryMatrixForPointCloudCalculation(camera: camera)
            let (outputPosition, outputNormal, outputGridInfo) = pcCalculator.acquirePointCloudInfo(camera: camera, depthMap: depthMap, confidenceMap: confidenceMap, floorHeight: floorHeight, necessaryMatrixForPointCloudCalculation: necessaryMatrixForPointCloudCalculation)
            
            gridMap.GridMapping2D(outputGridInfo: outputGridInfo, outputPositions: outputPosition, outputNormals: outputNormal, userGridPosition: userGridPosition, camera: camera)
            
            let (image, alignmentAngle, isAngleFromWall) = imageManager.generateRotatedImage(imageDict: gridMap.map, userGridPosition: userGridPosition, deviceMatrix: deviceMatrix, wallInformation: wallInformation, statusManager: statusManager)
            let (predictions, summary) = yolov8Model.predict(image: image)
            let isIntersectionAhead = intersectionTracker.intersectionAhead(predictions: predictions, userGridPosition: userGridPosition, alignmentAngle: alignmentAngle, deviceMatrix: deviceMatrix)
            intersectionTracker.trackIntersection(predictions: predictions, alignmentAngle: alignmentAngle, userGridPosition: userGridPosition)
            
            let confirmedIntersections = intersectionTracker.getConfirmedIntersection()
            let intersectionUserIsIn = intersectionTracker.determineIntersectionUserIsIn(confirmedIntersections: confirmedIntersections, userGridPosition: userGridPosition)
                
            let isUserInIntersection = intersectionUserIsIn != nil
            let inIntersectionID = isUserInIntersection ? intersectionUserIsIn!.id : nil
            let smallestAngleVector = intersectionTracker.determineTurn(closestElement: intersectionUserIsIn, deviceMatrix: deviceMatrix, userGridPosition: userGridPosition, statusManager: statusManager)
            
            let previousStatusManager = statusManager.copy() as! userStatusManager
            
            var maybeNextIntersection = true
            var walkedPastIntersectionToTurn = false
            let correctNextIntersectionShape = routeTracker.currentIntersectionFromNodeMap()
            let correctNextIntersectionShapeHasFront = correctNextIntersectionShape.containFront()
            if let intersectionUserIsIn = intersectionUserIsIn {
                let nextIntersectionContainsFront = intersectionUserIsIn.yoloShape.containFront()
                maybeNextIntersection = biImplication(a: correctNextIntersectionShapeHasFront,b: nextIntersectionContainsFront)
                if correctNextIntersectionShapeHasFront && !nextIntersectionContainsFront{
                    walkedPastIntersectionToTurn = true
                }
            }
            
            let walkedMultiplierDistance = routeTracker.determineWalkedPastByDistance(userGridIndex: userGridPosition, multiplier: 2.5)
            walkedPastIntersectionToTurn = walkedPastIntersectionToTurn || walkedMultiplierDistance
            
            statusManager.updateStatus(summary: summary, alignmentAngle: alignmentAngle, deviceMatrix: deviceMatrix, isUserInIntersection: isUserInIntersection, inIntersectionID: inIntersectionID, smallestAngleVector: smallestAngleVector, userGridPosition: userGridPosition, isAngleFromWall: isAngleFromWall, maybeNextIntersection: maybeNextIntersection, isIntersectionAhead: isIntersectionAhead)

            let shouldTrackDistanceForlast = routeTracker.shouldTrackDistance()
            var enteredIntersection = !previousStatusManager.inIntersection && statusManager.inIntersection
            let exitedIntersection = previousStatusManager.inIntersection && !statusManager.inIntersection
            let shouldCheckShapeInIntersection = isUserInIntersection && previousStatusManager.inIntersection && statusManager.inIntersection && !intersectionTracker.getShapeCorrect(intersectionID: statusManager.lastInIntersectionID)
            
            var enteredIntersectionClose: Bool = false
            if let currentIntersectionID = intersectionUserIsIn?.id,
               let previousStatusManagerLastInIntersectionID = previousStatusManager.lastInIntersectionID{
                enteredIntersectionClose = currentIntersectionID != previousStatusManagerLastInIntersectionID && !routeTracker.isEnteredIntersectionInPast(intersectionID: currentIntersectionID)
            }
            
            enteredIntersection = enteredIntersection || enteredIntersectionClose
        
            if let intersectionUserIsIn = intersectionUserIsIn {
                enteredIntersection = enteredIntersection && maybeNextIntersection
            }
            
            if alignmentAngle.isNaN {
                statusManager.conveyedUserWalkPastIntersectionToTurn = false
            }
            
            //:DEBUG
            let sManager = statusManager
            let sState = systemState
            let rTracker = routeTracker
            let iTracker = intersectionTracker
            //:DEBUG
            
            if shouldTrackDistanceForlast && systemState == .corridorNavigation {
                
                let didNotifyLastDistance = routeTracker.didNotifyLastDistance
                if exitedIntersection && !didNotifyLastDistance {
                    routeTracker.didNotifyLastDistance = true
                    let fbInfoCapsule = feedBackInformationCapsule(userGridIndex: userGridPosition, routeTracker: routeTracker)
                    delegate?.didUpdateSpeech(fbType: .generateNextInstruction, fbInfoCapsule: fbInfoCapsule) // next instruction
                }
                
                let distanceFromIntersection = routeTracker.distanceToDestination()
                let walkedDistance = routeTracker.calculateDistanceFromLastIntersection(userGridIndex: userGridPosition)
                let remainingDistance = distanceFromIntersection - walkedDistance
                if remainingDistance < remainingDistanceThreshold {
                    let directionToFace = routeTracker.getFinalFacingDirection()
                    routeTracker.reachedDestination = true
                    let fbInfoCapsule = feedBackInformationCapsule(directionToFace: directionToFace)
                    delegate?.didUpdateClose(vibrationState: VibrationState.stop)
                    delegate?.didUpdateSpeech(fbType: .arrivedDestination, fbInfoCapsule: fbInfoCapsule)
                    delegate?.didFinishNavigation(arrivedDestination: nodeMapManager.selectedDestination, scale: routeTracker.scale, scaleTracker: routeTracker.scaleTracker)
                }
            } else if enteredIntersection && systemState == .corridorNavigation {
                
                statusManager.discardDirectionToScan()
                let intersectionShapeToScan = routeTracker.getIntersectionShapeToScan()
                let directionsToScan = intersectionUserIsIn!.getLeftRightDirection(statusManager: statusManager, intersectionShapeToScan: intersectionShapeToScan)
                let fbInfoCapsule = feedBackInformationCapsule(intersectionShapeToScan: intersectionShapeToScan)
                delegate?.didUpdateSpeech(fbType: .scanSurrondings, fbInfoCapsule: fbInfoCapsule)
                routeTracker.updateEnteredIntersections(intersectionID: statusManager.lastInIntersectionID!)
                statusManager.updateDirectionsToScan(directionToScan: directionsToScan)
                systemState = .inIntersection
                
            } else if walkedPastIntersectionToTurn && systemState == .corridorNavigation {
                
                systemState = .corridorNavigation
                if !statusManager.conveyedUserWalkPastIntersectionToTurn {
                    let revertedCorrectDirectionToTurn = routeTracker.revertedCorrectDirectionToTurn()
                    let fbInfoCapsule = feedBackInformationCapsule(revertedCorrectDirectionToTurn: revertedCorrectDirectionToTurn)
                    delegate?.didUpdateSpeech(fbType: .walkedPastIntersectionToTurn, fbInfoCapsule: fbInfoCapsule)
                    routeTracker.revertCorrectDirectionToTurn()
                    statusManager.conveyedUserWalkPastIntersectionToTurn = true //should set this to false once the user have turned different direction
                }
                
            } else if exitedIntersection && systemState == .inIntersection {
                
                let isShapeCorrect = intersectionTracker.getShapeCorrect(intersectionID: previousStatusManager.lastInIntersectionID)
                systemState = .corridorNavigation

                if isShapeCorrect,
                    let lastIntersectionID = previousStatusManager.lastInIntersectionID,
                   let lastSmallestAngleVector = previousStatusManager.lastSmallestAngleVector{
                    statusManager.discardDirectionToScan()
                    let deviceOrientationCol1 = deviceMatrix.columns.1
                    let deviceOrientaion = normalize(SIMD2<Float>(deviceOrientationCol1.z,-deviceOrientationCol1.x))
                    let intersectionPosition = intersectionTracker.getIntersectionWithID(id: lastIntersectionID).position
                    let previousIntersection = statusManager.passedIntersectionPoints.last!
                    let vector = normalize(SIMD2<Float>(Float(intersectionPosition.x - previousIntersection.x),Float(intersectionPosition.y - previousIntersection.y)))
                    statusManager.updatePassedIntersectionPoints(intersectionPoint: intersectionPosition)
                    let angle = routeTracker.calculateOrientationAngle(mainVector: deviceOrientaion, subVector: vector)
                    let turnedDiretion = routeTracker.calculateOrientation(angle: angle)
                    let isProceedPathCorrect = routeTracker.postPathCheck(intersectionID: lastIntersectionID, vector: lastSmallestAngleVector, turnedDirection: turnedDiretion)
                    
                    if exitedIntersection {
                        if isProceedPathCorrect {
                            let fbInfoCapsule = feedBackInformationCapsule(userGridIndex: userGridPosition, routeTracker: routeTracker)
                            delegate?.didUpdateSpeech(fbType: .generateNextInstruction, fbInfoCapsule: fbInfoCapsule)
                        } else {
                            let correctDirectionToTurn = routeTracker.correctDirectionToTurn()
                            let fbInfoCapsule = feedBackInformationCapsule(turnedDiretion: turnedDiretion, correctDirectionToTurn: correctDirectionToTurn)
                            delegate?.didUpdateSpeech(fbType: .wrongDirection, fbInfoCapsule: fbInfoCapsule)
                        }
                    } else if enteredIntersectionClose {
                        if !isProceedPathCorrect {
                            let correctDirectionToTurn = routeTracker.correctDirectionToTurn()
                            let fbInfoCapsule = feedBackInformationCapsule(turnedDiretion: turnedDiretion, correctDirectionToTurn: correctDirectionToTurn)
                            delegate?.didUpdateSpeech(fbType: .wrongDirection, fbInfoCapsule: fbInfoCapsule)
                        }
                        let fbInfoCapsule = feedBackInformationCapsule(userGridIndex: userGridPosition, routeTracker: routeTracker)
                        delegate?.didUpdateSpeech(fbType: .generateNextInstruction, fbInfoCapsule: fbInfoCapsule)
                    }
                    
                }
                
            } else if shouldCheckShapeInIntersection && systemState == .inIntersection {
                
                let currentIntersectionShape = intersectionUserIsIn!.determineConfirmedDirections(statusManager: statusManager)
                
                let directionToHead = routeTracker.getDirectionToHead()
                let isIntersectionShapeCorrect = confirmIntersectionShape(correctIntersectionShape: correctNextIntersectionShape, scanedIntersectionshape: currentIntersectionShape, directionToHead: directionToHead)
                
                if isIntersectionShapeCorrect {
                    intersectionTracker.updateShapeCorrect(intersectionID: inIntersectionID, shapeCorrect: true)
                    routeTracker.updateRoute(confirmedIntersections: confirmedIntersections, currentIntersection: intersectionUserIsIn!)
                    let fbInfoCapsule = feedBackInformationCapsule(routeTracker: routeTracker, additionalString: "Intersection shape correct.")
                    delegate?.didUpdateSpeech(fbType: .generateNecessaryTurn, fbInfoCapsule: fbInfoCapsule)
                    
                } else {
                    let allScanned = statusManager.determineAllScanned()
                    let conveyedScanned = statusManager.getConveyedScanned()
                    if !conveyedScanned && allScanned {
                        let fbInfoCapsule = feedBackInformationCapsule()
                        delegate?.didUpdateSpeech(fbType: .wrongIntersectionProceedForward, fbInfoCapsule: fbInfoCapsule)
                        statusManager.conveyedScanned = true
                    }
                }
            }

            delegate?.didUpdate(intersections: confirmedIntersections)
            delegate?.didUpdate(gridMapImage: image)
            delegate?.didUpdate(boundingBoxes: predictions, labels: yolov8Model.labels)
            
        }
        
        let ready = floorHeight != 0
        let string = String(format: "fps:%.2f \n Ready: \(ready)", 1 / Date().timeIntervalSince(timeStartProcess))
        delegate?.didUpdate(labelString: string)

        let remainingTime = Date().timeIntervalSince(timeStartProcess) < Double(1 / fps) ? Double(1 / fps) - Date().timeIntervalSince(timeStartProcess) : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime){ [self] in
            mainFunction()
        }
        
    }
    
    func checkDepth(in depthMap: CVPixelBuffer, with sampleCount: Int, closeDistance: Float) -> Bool {
        
        guard sampleCount > 0 else { return false }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // Generate sample points
        let stepX = width / sampleCount
        let stepY = height / sampleCount
        var closeCount = 0
        
        CVPixelBufferLockBaseAddress(depthMap, [])
        let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthMap), to: UnsafeMutablePointer<Float>.self)
        
        for i in 0..<sampleCount {
            for j in 0..<sampleCount {
                let x = i * stepX
                let y = j * stepY
                
                let depthAtSample = floatBuffer[y * width + x]
                
                if depthAtSample < closeDistance {
                    closeCount += 1
                }
                
                // Break early if we already have more than half of the points closer than the given distance
                if closeCount > (sampleCount * sampleCount) / 2 {
                    CVPixelBufferUnlockBaseAddress(depthMap, [])
                    return true
                }
            }
        }
        
        CVPixelBufferUnlockBaseAddress(depthMap, [])
        return false
    }
    
    func startSystem() {
        start = true
        if self.systemMode == .proposed {
            let camera = session.currentFrame?.camera
            let deviceMatrix = camera!.transform
            let userGridPosition = deviceMatrix.getGridIndex()
            let fbInfoCapsule = feedBackInformationCapsule(userGridIndex: userGridPosition, routeTracker: routeTracker)
            delegate?.didUpdateSpeech(fbType: .generateNextInstruction, fbInfoCapsule: fbInfoCapsule) // next instruction
        }
        
        if systemState == .initial {
            systemState = .corridorNavigation
        }
    }
    
    func stopSystem() {
        start = false
    }
    
    func setConfidenceLevel(confidence: Int) {
        pcCalculator.selectedPointCloudConfidence = confidence
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let userGridPosition = frame.camera.transform.getGridIndex()
        delegate?.didUpdate(userGridPosition: userGridPosition)
        
        if let depthMap = frame.sceneDepth?.depthMap {
            let isSomeThingClose = checkDepth(in: depthMap, with: 20, closeDistance: 1.0)
            if isSomeThingClose && !routeTracker.reachedDestination{
                delegate?.didUpdateClose(vibrationState: VibrationState.start)
            } else {
                delegate?.didUpdateClose(vibrationState: VibrationState.stop)
            }
            
        }
        
        if routeTracker.reachedDestination {
            delegate?.didUpdateClose(vibrationState: VibrationState.stop)
        }

    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        
        for anchor in anchors {
            guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
            let classification = planeAnchor.classification
            if classification == .floor {
                floorHeight = planeAnchor.transform.columns.3[1]
            } else if classification == .wall || classification == .window {
                let uuid = planeAnchor.identifier
                wallInformation[uuid] = planeAnchor.transform
            }
        }
        
        var keysToRemove: [UUID] = []
        
        let devicePosition = session.currentFrame?.camera.transform.columns.3
        for (key, value) in wallInformation {
            let planePosition = value.columns.3
            let distanceXY = simd_distance(simd_float2(devicePosition!.x, devicePosition!.z), simd_float2(planePosition.x, planePosition.z))
            if distanceXY > 3.0 {
                keysToRemove.append(key)
            }
        }
        
        for key in keysToRemove { wallInformation.removeValue(forKey: key) }
        
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message: String

        switch camera.trackingState {
        case .normal:
            message = "Tracking normal"

        case .notAvailable:
            message = "Tracking unavailable."
            delegate?.didUpdateSound()

        case .limited(.excessiveMotion):
            message = "Tracking limited - excessive motion."
            delegate?.didUpdateSound()

        case .limited(.insufficientFeatures):
            message = "Tracking limited - insufficient features."
            delegate?.didUpdateSound()

        case .limited(.initializing):
            message = "Initializing AR session."

        case .limited(.relocalizing):
            message = "relocalizing"

        case .limited(_):
            message = "limited"
        }
        delegate?.didUpdate(sessionInfoString: message)
    }
    
    
}
