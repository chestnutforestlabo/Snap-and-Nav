//
//  userStatusManager.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/06/04.
//

import Foundation

class userStatusManager: NSObject, NSCopying {
    
    var inIntersection: Bool = false
    var intersectionAhead: Bool = false
    var previousAlignmentAngle: Float = 0
    var lastInIntersectionID: String? = nil
    var lastSmallestAngleVector: SIMD2<Float>? = nil
    var pastPositions: [gridIndex] = [gridIndex(x: 0, y: 0),gridIndex(x: 0, y: 0)]
    var pastLocalPositions: [gridIndex] = [gridIndex(x: 0, y: 0),gridIndex(x: 0, y: 0)]
    var passedIntersectionPoints: [gridIndex] = [gridIndex(x: 0, y: 0)]
    var averageOrientation: SIMD2<Float> = SIMD2<Float>(0,0)
    var averageLocalOrientation: SIMD2<Float> = SIMD2<Float>(0,0)
    var enteredIntersections: Set<String> = Set()
    var deviceMatrix: simd_float4x4 = simd_float4x4()
    var lastIsAngleFromWall: Bool = false
    var directionsToScan: [SIMD2<Float>] = []
    var scannedDirection: [Bool] = []
    var conveyedScanned: Bool = false
    var previouslyIsUserInIntersection: Bool = false
    var conveyedUserWalkPastIntersectionToTurn: Bool = false
    
    private var consequtiveIntersectionAheadCount: Int = 0
    private var consecutiveInIntersectionCount: Int = 0
    private var consecutiveNotInIntersectionCount: Int = 0
    
    private var consequtiveIntersectionAheadThreshold: Int { return Int(fps) }
    private var consecutiveInIntersectionThreshold: Int { return 1 }
    private var consecutiveNotInIntersectionThreshold: Int  { return 2 }
    
    func updateDirectionsToScan(directionToScan:[SIMD2<Float>]) {
        self.directionsToScan = directionToScan
        self.scannedDirection = [Bool](repeating: false, count: directionToScan.count)
    }
    
    func determineAllScanned() -> Bool{
        let deviceOrientationCol1 = deviceMatrix.columns.1
        let deviceOrientaion = normalize(SIMD2<Float>(deviceOrientationCol1.z,-deviceOrientationCol1.x))

        for  (index, directionToScan) in directionsToScan.enumerated() {
            let cosine = dot(deviceOrientaion, directionToScan)
            let angle = abs(acos(cosine)) / .degreesToRadian
            if angle < 22.5 {
                scannedDirection[index] = true
            }
        }
        
        let allTrue = scannedDirection.allSatisfy { $0 == true }
        return allTrue
    }
    
    func discardDirectionToScan() {
        self.directionsToScan = []
        self.scannedDirection = []
        self.conveyedScanned = false
    }
    
    func getConveyedScanned() -> Bool {
        return conveyedScanned
    }
    
    
    func updatePassedIntersectionPoints(intersectionPoint: gridIndex) {
        passedIntersectionPoints.append(intersectionPoint)
    }
    
    func updateStatus(summary: PredictionSummary, alignmentAngle: Float, deviceMatrix: simd_float4x4, isUserInIntersection: Bool, inIntersectionID: String?, smallestAngleVector: SIMD2<Float>?, userGridPosition: gridIndex, isAngleFromWall: Bool, maybeNextIntersection: Bool, isIntersectionAhead: Bool) {
        
        self.previouslyIsUserInIntersection = isUserInIntersection
        
        self.lastIsAngleFromWall = isAngleFromWall
        
        self.deviceMatrix = deviceMatrix
        
        if lastInIntersectionID == nil && inIntersectionID != nil {
            lastInIntersectionID = inIntersectionID
        }
        
        
        if self.consecutiveNotInIntersectionThreshold <= self.consecutiveNotInIntersectionCount{
            self.inIntersection = false
            if !isUserInIntersection { self.consecutiveInIntersectionCount = 0 }
        }
        
        if self.consecutiveInIntersectionThreshold <= self.consecutiveInIntersectionCount {
            self.inIntersection = true
            if isUserInIntersection { self.consecutiveNotInIntersectionCount = 0 }
        }
        
        if isUserInIntersection {
            if (lastInIntersectionID == inIntersectionID) {
                self.consecutiveInIntersectionCount += 1
            } else {
                self.consecutiveNotInIntersectionCount = consecutiveNotInIntersectionThreshold // id the ID changed, immediately set to threshold
            }
        } else {
            self.consecutiveNotInIntersectionCount += 1
        }
        
        if isIntersectionAhead {
            self.consequtiveIntersectionAheadCount += 1
        } else {
            self.consequtiveIntersectionAheadCount = 0
        }
        
        if self.consequtiveIntersectionAheadThreshold <= self.consequtiveIntersectionAheadCount {
            self.intersectionAhead = true
        } else {
            self.intersectionAhead = false
        }
        
        self.previousAlignmentAngle = alignmentAngle
        
        if inIntersectionID == nil && smallestAngleVector == nil {
            if !inIntersection {
                self.lastSmallestAngleVector = smallestAngleVector // which is nil
                self.lastInIntersectionID = inIntersectionID //which is nil
            }
        } else {
            self.lastSmallestAngleVector = smallestAngleVector
            self.lastInIntersectionID = inIntersectionID
        }
        
        if inIntersection && maybeNextIntersection { pastPositions = [userGridPosition] }
        if pastPositions.last!.distanceTo(other: userGridPosition) != 0 && !inIntersection { pastPositions.append(userGridPosition) }
        if pastPositions.count >= N + 1{ pastPositions.remove(at: 0) }
        let n = Int(pastPositions.count / 2)
        let aveposA = calculateAverage(i: pastPositions.count - 1, n: n / 2, pastPositions: pastPositions)
        let aveposB = calculateAverage(i: pastPositions.count - 1 - n / 2, n: n / 2, pastPositions: pastPositions)
        self.averageOrientation = normalize(SIMD2<Float>(Float(aveposA.x - aveposB.x), Float(aveposA.y - aveposB.y)))

        if inIntersection && maybeNextIntersection { pastLocalPositions = [userGridPosition] }
        if pastLocalPositions.last!.distanceTo(other: userGridPosition) != 0 && !inIntersection { pastLocalPositions.append(userGridPosition) }
        if pastLocalPositions.count >= N + 1{
            pastLocalPositions.remove(at: 0)
            let n = Int(pastLocalPositions.count / 2)
            let aveposA = calculateAverage(i: pastLocalPositions.count - 1, n: n / 2, pastPositions: pastLocalPositions)
            let aveposB = calculateAverage(i: pastLocalPositions.count - 1 - n / 2, n: n / 2, pastPositions: pastLocalPositions)
            self.averageLocalOrientation = normalize(SIMD2<Float>(Float(aveposA.x - aveposB.x), Float(aveposA.y - aveposB.y)))
        } else {
            let deviceOrientationCol1 = deviceMatrix.columns.1
            let deviceOrientaion = normalize(SIMD2<Float>(deviceOrientationCol1.z,-deviceOrientationCol1.x))
            self.averageLocalOrientation = deviceOrientaion
        }
        
    }
    
    func copy(with zone: NSZone? = nil) -> Any {
        let copy = userStatusManager()
        copy.inIntersection = self.inIntersection
        copy.intersectionAhead = self.intersectionAhead
        copy.previousAlignmentAngle = self.previousAlignmentAngle
        copy.lastInIntersectionID = self.lastInIntersectionID
        copy.lastSmallestAngleVector = self.lastSmallestAngleVector
        copy.pastPositions = self.pastPositions
        copy.averageOrientation = self.averageOrientation
        return copy
    }
    
    func printAll() {
        var printAll: String {
            return """
            inIntersection: \(inIntersection)
            intersectionAhead: \(intersectionAhead)
            previousAlignmentAngle: \(previousAlignmentAngle)
            lastInIntersectionID: \(lastInIntersectionID)
            lastSmallestAngleVector: \(lastSmallestAngleVector)
            averageOrientation: \(averageOrientation)
            """
        }
        print(printAll)
    }
    
}
