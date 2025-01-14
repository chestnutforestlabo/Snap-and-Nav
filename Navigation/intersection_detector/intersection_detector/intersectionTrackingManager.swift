//
//  intersectionTrackingManager.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/06/04.
//

import Foundation

struct intersection {
    var position: gridIndex
    var keyPositions: [String:gridIndex]
    var directions: [String:SIMD2<Float>]
    var consequtiveTrackedCount: Int
    var consequtiveUnTrackedCount: Int
    var size: Float
    var id: String
    var shapeCorrect: Bool = false
    var yoloShape: [String] = []
    var description: String {
        return """
        Position: \(position.x), \(position.y)
        Key Positions: \(keyPositions.map{ "\($0.key): (\($0.value.x), \($0.value.y))" }.joined(separator: ", "))
        Directions: \(directions.map{ "\($0.key): (\($0.value.x), \($0.value.y))" }.joined(separator: ", "))
        Consequtive Tracked Count: \(consequtiveTrackedCount)
        Consequtive UnTracked Count: \(consequtiveUnTrackedCount)
        Size: \(size)
        ID: \(id)
        Shape Correct: \(shapeCorrect)
        """
    }
    
    func determineConfirmedDirections(statusManager: userStatusManager) -> [String] {
        
        let previousIntersection = statusManager.passedIntersectionPoints.last!
        let intersectionPosition = self.position
        let vector = normalize(SIMD2<Float>(Float(intersectionPosition.x - previousIntersection.x),Float(intersectionPosition.y - previousIntersection.y)))

        
        var directions: [String] = []
        for (_, direction) in self.directions {
            let cosine = dot(vector, direction)
            let angle = acos(cosine) / .degreesToRadian
            let crossProductZ = direction.x * vector.y - direction.y * vector.x

            var direction = ""
            if abs(angle) < 40 {
                direction = "Front"
            } else if abs(angle) > 140 {
                direction = "Back"
            }else if crossProductZ < 0 {
                direction = "Right"
            } else {
                direction = "Left"
            }
            directions.append(direction)
        }
        
        directions.sort()
        
        return directions
        
    }
    
    func getLeftRightDirection(statusManager: userStatusManager, intersectionShapeToScan: [String], degreeToRotate: Float = degreeToScan) -> [SIMD2<Float>] {

        let deviceOrientationCol1 = statusManager.deviceMatrix.columns.1
        let vector = normalize(SIMD2<Float>(deviceOrientationCol1.z,-deviceOrientationCol1.x))
        var vectors: [SIMD2<Float>] = []

        // Convert degrees to radians
        let radians: Float = degreeToRotate * .pi / 180

        // Rotate +degreeToRotate degrees
        if intersectionShapeToScan.contains("Right") {
            let vectorPlus: SIMD2<Float> = SIMD2<Float>(x: vector.x * cos(radians) - vector.y * sin(radians),
                                                        y: vector.x * sin(radians) + vector.y * cos(radians))
            vectors.append(vectorPlus)
        }

        // Rotate -degreeToRotate degrees
        if intersectionShapeToScan.contains("Left") {
            let vectorMinus: SIMD2<Float> = SIMD2<Float>(x: vector.x * cos(-radians) - vector.y * sin(-radians),
                                                         y: vector.x * sin(-radians) + vector.y * cos(-radians))
            vectors.append(vectorMinus)
        }

        return vectors
    }

}


class intersectionTrackingManager {
    
    var trackedIntersections: [intersection] = []
    var intersectionTrackingDistanceTheshold: Float { return 2.0 / gridMapLength }
    var consequtiveUnTrackedCountThreshold: Int { return Int(fps/2) }
    var consequtiveTrackedCountThreshold: Int { return Int(fps) }
    
    let labelsIntersectionShape = [["Left","Back"],
                                ["Left","Front"],
                                ["Left","Right","Back"],
                                ["Left","Right","Front"],
                                ["Right","Front","Back"],
                                ["Right","Back"],
                                ["Right","Front"],
                                ["Left","Right","Front","Back"],
                                ["Left","Front","Back"]]
    
    func intersectionAhead(predictions: [Prediction], userGridPosition: gridIndex, alignmentAngle: Float, deviceMatrix: simd_float4x4, minAngleThresh: Float = 70, minDistanceThresh: Float = 64) -> Bool {
        let deviceOrientationCol1 = deviceMatrix.columns.1
        let deviceOrientaion = normalize(SIMD2<Float>(deviceOrientationCol1.z,-deviceOrientationCol1.x))
        
        for prediction in predictions {
            let centerGIndex = imgToWorldCoord(x: prediction.rect.midX, y: prediction.rect.midY, angle: alignmentAngle, userGridPosition: userGridPosition, imgSize: imgSize)
            let userToIntersectionVector = normalize(SIMD2<Float>(centerGIndex.x.float() - userGridPosition.x.float(),centerGIndex.y.float() - userGridPosition.y.float()))
            let distanceToIntersection = centerGIndex.distanceTo(other: userGridPosition)
            let cosine = dot(deviceOrientaion, userToIntersectionVector)
            let angle = acos(cosine) / .degreesToRadian
            
            if angle < minAngleThresh && distanceToIntersection < minDistanceThresh{
                return true
            }
        }
        
        return false
    }

    func trackIntersection(predictions: [Prediction], alignmentAngle: Float, userGridPosition: gridIndex) {
        var trackedIndex: [Int] = []
        
        for prediction in predictions {
            var closestIndex: Int = -1
            var found: Bool = false
            
            let predictedClass = labelsIntersectionShape[prediction.classIndex]
            let centerGIndex = imgToWorldCoord(x: prediction.rect.midX, y: prediction.rect.midY, angle: alignmentAngle, userGridPosition: userGridPosition, imgSize: imgSize)
            let keyPoints = getKeyPoints(prediction: prediction, angle: alignmentAngle, userGridPosition: userGridPosition, imgSize: imgSize)
            let directions = calculateIntersectionConfirmedPath(confirm: prediction.confirmation, centerIndex: centerGIndex, keyPoints: keyPoints)
            let size = determineSize(centerGIndex: centerGIndex, userGridPosition: userGridPosition, prediction: prediction, angle: alignmentAngle)
            
            for (index, intersection) in trackedIntersections.enumerated() {
                let distance = intersection.position.distanceTo(other: centerGIndex)
                if distance < intersectionTrackingDistanceTheshold && !trackedIndex.contains(index){
                    closestIndex = index
                    found = true
                }
            }
            
            if found {
                trackedIndex.append(closestIndex)
                trackedIntersections[closestIndex].consequtiveTrackedCount += 1
                trackedIntersections[closestIndex].directions = directions
                
                trackedIntersections[closestIndex].position = centerGIndex
                trackedIntersections[closestIndex].keyPositions = keyPoints
                trackedIntersections[closestIndex].size = size
                trackedIntersections[closestIndex].yoloShape = predictedClass
            } else {
                let newIntersection = intersection(position: centerGIndex,
                                                   keyPositions: keyPoints,
                                                   directions: directions,
                                                   consequtiveTrackedCount: 0,
                                                   consequtiveUnTrackedCount: 0,
                                                   size: size,
                                                   id: generateUniqueId(),
                                                   yoloShape: predictedClass)
                trackedIntersections.append(newIntersection)
            }
        }
        
        for index in 0..<trackedIntersections.count {
            if !trackedIndex.contains(index) && !(trackedIntersections[index].consequtiveTrackedCount > consequtiveTrackedCountThreshold){
                trackedIntersections[index].consequtiveUnTrackedCount += 1
                trackedIntersections[index].consequtiveTrackedCount = 0
            }
        }
        
        for index in (0..<trackedIntersections.count).reversed() {
            if trackedIntersections[index].consequtiveUnTrackedCount > consequtiveUnTrackedCountThreshold  && !(trackedIntersections[index].consequtiveTrackedCount > consequtiveTrackedCountThreshold){
                trackedIntersections.remove(at: index)
            }
        }
        
    }
    
    func determineSize(centerGIndex: gridIndex, userGridPosition: gridIndex, prediction: Prediction, angle: Float) -> Float{
        let bottomRight = imgToWorldCoord(x: prediction.rect.maxX, y: prediction.rect.maxY, angle: angle, userGridPosition: userGridPosition, imgSize: imgSize)
        return bottomRight.distanceTo(other: centerGIndex)
        
    }
    
    func updateShapeCorrect(intersectionID: String?, shapeCorrect: Bool) {
        if let intersectionIndex = trackedIntersections.firstIndex(where: {$0.id == intersectionID} ) {
            trackedIntersections[intersectionIndex].shapeCorrect = shapeCorrect
        }
    }
    
    func getShapeCorrect(intersectionID: String?) -> Bool{
        if let currentIntersection = trackedIntersections.first(where: {$0.id == intersectionID} ) {
            return currentIntersection.shapeCorrect
        } else {
            return false
        }
    }
    
    func getIntersectionWithID(id: String) -> intersection {
        return trackedIntersections.first(where: {$0.id == id} )!
    }
    
    func calculateIntersectionConfirmedPath(confirm: confirmedShape, centerIndex: gridIndex, keyPoints: [String:gridIndex]) -> [String:SIMD2<Float>]{
        var confirmedPath: [String:SIMD2<Float>] = [:]
        
        if confirm.front {
            let dx = keyPoints["Front"]!.x - centerIndex.x
            let dy = keyPoints["Front"]!.y - centerIndex.y
            let frontVec = normalize(SIMD2<Float>(Float(dx), Float(dy)))
            confirmedPath["Front"] = frontVec
        }
        
        if confirm.left {
            let dx = keyPoints["Left"]!.x - centerIndex.x
            let dy = keyPoints["Left"]!.y - centerIndex.y
            let leftVec = normalize(SIMD2<Float>(Float(dx), Float(dy)))
            confirmedPath["Left"] = leftVec
        }
        
        if confirm.right {
            let dx = keyPoints["Right"]!.x - centerIndex.x
            let dy = keyPoints["Right"]!.y - centerIndex.y
            let rightVec = normalize(SIMD2<Float>(Float(dx), Float(dy)))
            confirmedPath["Right"] = rightVec
        }
        
        if confirm.back {
            let dx = keyPoints["Back"]!.x - centerIndex.x
            let dy = keyPoints["Back"]!.y - centerIndex.y
            let backVec = normalize(SIMD2<Float>(Float(dx), Float(dy)))
            confirmedPath["Back"] = backVec
        }
    
        return confirmedPath
    }
    
    func getConfirmedIntersection() -> [intersection]{
        var confirmedIntersection: [intersection] = []
        for trackedIntersection in trackedIntersections where trackedIntersection.consequtiveTrackedCount > consequtiveTrackedCountThreshold{
            confirmedIntersection.append(trackedIntersection)
        }
        return confirmedIntersection
    }
    
    func getKeyPoints(prediction: Prediction, angle: Float, userGridPosition: gridIndex, imgSize: Float) ->  [String:gridIndex]{
        var keyPoints = [String:gridIndex]()
        let top = imgToWorldCoord(x: prediction.rect.midX, y: prediction.rect.minY, angle: angle, userGridPosition: userGridPosition, imgSize: imgSize)
        let bottom = imgToWorldCoord(x: prediction.rect.midX, y: prediction.rect.maxY, angle: angle, userGridPosition: userGridPosition, imgSize: imgSize)
        let left = imgToWorldCoord(x: prediction.rect.minX, y: prediction.rect.midY, angle: angle, userGridPosition: userGridPosition, imgSize: imgSize)
        let right = imgToWorldCoord(x: prediction.rect.maxX, y: prediction.rect.midY, angle: angle, userGridPosition: userGridPosition, imgSize: imgSize)
        
        let topLeft = imgToWorldCoord(x: prediction.rect.minX, y: prediction.rect.minY, angle: angle, userGridPosition: userGridPosition, imgSize: imgSize)
        let topRight = imgToWorldCoord(x: prediction.rect.maxX, y: prediction.rect.minY, angle: angle, userGridPosition: userGridPosition, imgSize: imgSize)
        let bottomLeft = imgToWorldCoord(x: prediction.rect.minX, y: prediction.rect.maxY, angle: angle, userGridPosition: userGridPosition, imgSize: imgSize)
        let bottomRight = imgToWorldCoord(x: prediction.rect.maxX, y: prediction.rect.maxY, angle: angle, userGridPosition: userGridPosition, imgSize: imgSize)
        
        keyPoints["Front"] = top
        keyPoints["Back"] = bottom
        keyPoints["Left"] = left
        keyPoints["Right"] = right
        
        keyPoints["FrontLeft"] = topLeft
        keyPoints["FrontRight"] = topRight
        keyPoints["BackLeft"] = bottomLeft
        keyPoints["BackRight"] = bottomRight

        return keyPoints

    }
    
    func determineIntersectionUserIsIn(confirmedIntersections: [intersection], userGridPosition: gridIndex) -> intersection? {
        if let (_, closestElement) = confirmedIntersections.enumerated().min(by: { $0.element.position.distanceTo(other: userGridPosition) < $1.element.position.distanceTo(other: userGridPosition) }) {
            if closestElement.position.distanceTo(other: userGridPosition) < closestElement.size{
                return closestElement
            } else {
                return nil
            }
        }
        
        return nil
    }
    
    func determineTurn(closestElement: intersection?, deviceMatrix: simd_float4x4, userGridPosition: gridIndex, statusManager: userStatusManager) -> SIMD2<Float>?{
        
        guard let closestElement = closestElement else { return nil }
        let deviceOrientationCol1 = deviceMatrix.columns.1
        let deviceOrientaion = normalize(SIMD2<Float>(deviceOrientationCol1.z,-deviceOrientationCol1.x))
        
        var smallestAngleVector = SIMD2<Float>(0,0)
        var smallestAngle: Float = 181.0
        let directions = closestElement.directions
        for (_, direction) in directions {
            let cosine = dot(deviceOrientaion, direction)
            let angle = acos(cosine) / .degreesToRadian
            
            if angle < smallestAngle {
                smallestAngle = angle
                smallestAngleVector = direction
            }
        }
        
        return smallestAngleVector
        
    }
    
    func generateUniqueId() -> String {
        return UUID().uuidString
    }
    
    
    
}
