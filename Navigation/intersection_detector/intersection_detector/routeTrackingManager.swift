//
//  routeTrackingManager.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/06/06.
//

import Foundation
import Collections

class routeTrackingManager {
    
    var walkedPath: OrderedDictionary<String, SIMD2<Float>> = [:]
    var distanceBetweenEachIntersection: [Float] = []
    var turnedDirections: [String] = []
    var lastNodeGridPosition: gridIndex = gridIndex(x: 0, y: 0)
    var reachedDestination: Bool = false
    var turnedIntersections: Set<String> { return Set(walkedPath.keys) }
    var enteredIntersections: Set<String> = []
    
    var nodeMapManager: nodeMapManager!
    var numWalkedIntersections: Int = 0
    var scale: Float? = nil
    var didNotifyLastDistance = false
    
    var scaleTracker = ScaleTracker()
    
    init(nodeMapManager: nodeMapManager, scale: Float?, scaleTracker: ScaleTracker) {
        walkedPath["Initial Point"] = SIMD2<Float>(0.0,-1.0)
        self.nodeMapManager = nodeMapManager
        self.scale = scale
        self.scaleTracker = scaleTracker
//        self.scaleTracker.saveScale(scale)
        nodeMapManager.pathPlanning(from: nodeMapManager.selectedCurrentLocation, to: nodeMapManager.selectedDestination)
        print("Navigation from \(nodeMapManager.selectedCurrentLocation) to \(nodeMapManager.selectedDestination)")
        print("directions: ",nodeMapManager.directions)
        print("paths: ",nodeMapManager.paths.nodeIdsFromPath())
        print("intersectionShapes: ",nodeMapManager.intersectionShapes)
        print("intersectionTypes: ",nodeMapManager.intersectionTypes)
        print("distances: ",nodeMapManager.distances)
        
    }
    
    func getDirectionToHead() -> String {
        return Array(nodeMapManager.directions[1...])[numWalkedIntersections]
    }
    
    func getIntersectionShapeToScan(shouldConfirmAll: Bool = shouldConfirmAll, forceScanAll: Bool = forceScanAll) -> [String] {
        if forceScanAll { return ["Left", "Right"] }
        
        var intersectionShape = nodeMapManager.intersectionShapes[numWalkedIntersections]
        let intersectionType = determineIntersectionType(intersectionShape: intersectionShape)
        
        intersectionShape = intersectionShape.filter( { $0 == "Left" || $0 == "Right"} )
        
        if !(intersectionType == "T junction" || intersectionType == "X shaped intersection") || !shouldConfirmAll {
            let directionToHead = Array(nodeMapManager.directions[1...])[numWalkedIntersections]
            let filterDirection = directionToHead == "Right" ? "Left" : "Right"
            intersectionShape = intersectionShape.filter { $0 != filterDirection }
        }
        
        if intersectionShape == [] { intersectionShape = ["Left", "Right"]}

        return intersectionShape
    }

    
    func updateEnteredIntersections(intersectionID: String) {
        enteredIntersections.insert(intersectionID)
    }
    
    func isEnteredIntersectionInPast(intersectionID: String?) -> Bool {
        if let intersectionID = intersectionID {
            if enteredIntersections.contains(intersectionID) {
                return true
            }
        }
        return false
    }

    func updateRoute(confirmedIntersections: [intersection], currentIntersection: intersection){
        self.lastNodeGridPosition = currentIntersection.position
        walkedPath[currentIntersection.id] = SIMD2<Float>(0,1) // just put template for this moment
        let distance = calculateDistanceBetweenEachIntersection(confirmedIntersections: confirmedIntersections)
        distanceBetweenEachIntersection.append(distance)
        
        let scale = distance / nodeMapManager.distances[numWalkedIntersections]
        
        if useScaleTracker {
            scaleTracker.saveScale(scale)
            self.scale = scaleTracker.averageScale()
        } else {
            self.scale = scale
        }

        numWalkedIntersections += 1
        
        if numWalkedIntersections < nodeMapManager.distances.count {
            let predictedDistance = nodeMapManager.distances[numWalkedIntersections] * self.scale!
            print("distance to the next intersection is ",predictedDistance)
        }
        
    }
    
    func postPathCheck(intersectionID: String, vector: SIMD2<Float>, turnedDirection: String) -> Bool{
        walkedPath[intersectionID] = vector
        turnedDirections.append(turnedDirection)
        
        let nodeMapManagerDirections = Array(nodeMapManager.directions[1...])
        if !(turnedDirection == nodeMapManagerDirections[numWalkedIntersections-1]) {
            return false
        }
        return true
    }
    
    func correctDirectionToTurn() -> String{
        let nodeMapManagerDirections = Array(nodeMapManager.directions[1...])
        return nodeMapManagerDirections[numWalkedIntersections-1]
    }
    
    func correctDirectionShouldHaveTurned() -> String{
        let nodeMapManagerDirections = Array(nodeMapManager.directions[1...])
        return nodeMapManagerDirections[numWalkedIntersections]
    }
    
    func revertedCorrectDirectionToTurn() -> String {
        let correctDirection = correctDirectionShouldHaveTurned()
        
        if correctDirection == "Right" {
            return "Left"
        } else if correctDirection == "Left" {
            return "Right"
        } else if correctDirection == "Front" {
            return "Front"
        }
        return "error"
    }
    
    func revertedIntersectionShapeToTurn() -> [String] {
        let correctDirection = correctDirectionShouldHaveTurned()
        
        if correctDirection == "Right" {
            return ["Left", "Front", "Back"]
        } else if correctDirection == "Left" {
            return ["Right", "Front", "Back"]
        } else {
            return ["error"]
        }
    }
    
    func revertCorrectDirectionToTurn() {
        let revertedDirection = revertedCorrectDirectionToTurn()
        let revertedIntersection = revertedIntersectionShapeToTurn()
        
        nodeMapManager.intersectionShapes[numWalkedIntersections] = revertedIntersection
        nodeMapManager.directions[numWalkedIntersections+1] = revertedDirection
        
    }
    
    
    func currentIntersectionFromNodeMap() -> [String] {
        return nodeMapManager.intersectionShapes[numWalkedIntersections].sorted()
    }
    
    
    func determineIntersectionType(intersectionShape: [String]) -> String{
        let hasFront = intersectionShape.contains("Front")
        let hasLeft = intersectionShape.contains("Left")
        let hasRight = intersectionShape.contains("Right")
        
        if hasFront {
            if hasLeft && hasRight {
                return "X shaped intersection"
            } else if hasLeft {
                return "intersection to left"
            } else if hasRight {
                return "intersection to right"
            }
            return "destination"
        } else {
            if hasLeft && hasRight {
                return "T junction"
            } else if hasLeft {
                return "corner"
            } else if hasRight {
                return "corner"
            }
        }
        return ""
        
    }
    
    func generateNecessaryTurn(additionalString: String = "") -> String {
        let nextTurn = Array(nodeMapManager.directions[1...])[numWalkedIntersections]
        if nextTurn == "Front" {
            return additionalString + " Go straight"
        } else {
            return additionalString + " Turn \(nextTurn)"
        }
    }
    
    func calculateDistanceFromLastIntersection(userGridIndex: gridIndex) -> Float {
        return lastNodeGridPosition.distanceTo(other: userGridIndex) * gridMapLength
    }
    
    func distanceToDestination() -> Float {
        let predictedDistance = nodeMapManager.distances[numWalkedIntersections] * self.scale!
        return predictedDistance
    }
    func getFinalFacingDirection() -> String {
        return nodeMapManager.directions.last!
    }
    
    func shouldTrackDistance() -> Bool {
        if reachedDestination {
            return false
        }
        
        if numWalkedIntersections == nodeMapManager.distances.count - 1 {
            return true
        }
        return false
    }

    
    func calculateDistanceBetweenEachIntersection(confirmedIntersections: [intersection]) -> Float {
        var tmpConfirmedIntersections = confirmedIntersections
        tmpConfirmedIntersections.append(intersection(position: gridIndex(x: 0, y: 0),
                                                   keyPositions: [:],
                                                   directions: [:],
                                                   consequtiveTrackedCount: 0,
                                                   consequtiveUnTrackedCount: 0,
                                                   size: 0,
                                                   id: "Initial Point"))
        
        let lastID = walkedPath.elements[walkedPath.count - 1].key
        let secondLastID = walkedPath.elements[walkedPath.count - 2].key
        
        let elementLastPos = tmpConfirmedIntersections.first(where: { $0.id == lastID })!.position
        let elementSecondLastPos = tmpConfirmedIntersections.first(where: { $0.id == secondLastID })!.position
        
        let distance = elementLastPos.distanceTo(other: elementSecondLastPos) * gridMapLength
        return distance
    }
    
    func lastIntersection(confirmedIntersections: [intersection]) -> gridIndex {
        
        let lastID = walkedPath.elements[walkedPath.count - 1].key
        let elementLastPos = confirmedIntersections.first(where: { $0.id == lastID })!.position
    
        return elementLastPos
    }
    
    func calculateOrientationAngle(mainVector: SIMD2<Float>, subVector: SIMD2<Float>) -> Float {
        let dotProduct = dot(mainVector, subVector)
        let mainVectorMagnitude = length(mainVector)
        let subVectorMagnitude = length(subVector)
        
        let cosAngle = dotProduct / (mainVectorMagnitude * subVectorMagnitude)
        let angleInRadians = acos(cosAngle)
        var angleInDegrees = angleInRadians * 180 / .pi
        
        let determinant = mainVector.x * subVector.y - mainVector.y * subVector.x
        
        if determinant < 0 {
            angleInDegrees *= -1 // Reverse the sign for left rotation
        }
        
        return angleInDegrees
    }

    func calculateOrientation(angle: Float) -> String {
        if -45 <= angle && angle <= 45 {
            return "Front"
        } else if 45 < angle && angle <= 135 {
            return "Left"
        } else if -135 < angle && angle <= -45 {
            return "Right"
        } else {
            return "Back"
        }
    }
    
    func determineWalkedPastByDistance(userGridIndex: gridIndex, multiplier: Float) -> Bool{
    
        if let scale = scale {
            let distanceFromLastIntersection = calculateDistanceFromLastIntersection(userGridIndex: userGridIndex)
            let predictedDistance = nodeMapManager.distances[numWalkedIntersections] * scale
            if predictedDistance * multiplier < distanceFromLastIntersection {
                return true
            }
        }
        return false
    }
}
