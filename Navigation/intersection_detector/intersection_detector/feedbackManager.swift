//
//  feedbackManager.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/06/05.
//

import UIKit
import Foundation
import AVFAudio

enum language: String {
    case jp = "ja-JP"
    case en = "en-US"
}

enum feedbackType: String {
    case scanSurrondings = "scanSurrondings"
    case generateNextInstruction = "generateNextInstruction"
    case generateNecessaryTurn = "generateNecessaryTurn"
    case wrongIntersectionProceedForward = "wrongIntersectionProceedForward"
    case wrongDirection = "wrongDirection"
    case arrivedDestination = "arrivedDestination"
    case conveyShape = "conveyShape"
    case describeRouteDescription = "describeRouteDescription"
    case navigationStart = "navigationStart"
    case walkedPastIntersectionToTurn = "walkedPastIntersectionToTurn"
    case localizationError = "localizationError"
}

class feedBackInformationCapsule {
    var intersectionShapeToScan: [String]? = nil
    var turnedDiretion: String? = nil
    var userGridIndex: gridIndex? = nil
    var routeTracker: routeTrackingManager? = nil
    var directionToFace: String? = nil
    var additionalString: String? = nil
    var shapeToConvey: [String]? = nil
    var directions: [String]? = nil
    var intersectionTypes: [String]? = nil
    var correctDirectionToTurn: String? = nil
    var revertedCorrectDirectionToTurn: String? = nil
    
    init(intersectionShapeToScan: [String]? = nil, turnedDiretion: String? = nil, userGridIndex: gridIndex? = nil, routeTracker: routeTrackingManager? = nil, directionToFace: String? = nil, additionalString: String? = nil, shapeToConvey: [String]? = nil, directions: [String]? = nil, intersectionTypes: [String]? = nil, correctDirectionToTurn: String? = nil, revertedCorrectDirectionToTurn: String? = nil) {
        self.intersectionShapeToScan = intersectionShapeToScan
        self.turnedDiretion = turnedDiretion
        self.userGridIndex = userGridIndex
        self.routeTracker = routeTracker
        self.directionToFace = directionToFace
        self.additionalString = additionalString
        self.shapeToConvey = shapeToConvey
        self.directions = directions
        self.intersectionTypes = intersectionTypes
        self.correctDirectionToTurn = correctDirectionToTurn
        self.revertedCorrectDirectionToTurn = revertedCorrectDirectionToTurn
    }
}

class feedBackManager {
    
    var lang: language
    
    let translationENToJP: [String:String] = ["Left":"左",
                                              "Right":"右",
                                              "Back":"後ろ",
                                              "Forward":"前",
                                              "Front":"前",
                                              "Face Left":"左を向いてください",
                                              "Face Right":"右を向いてください",
                                              "turn left":"左を向いてください",
                                              "turn right":"右を向いてください",
                                              "X shaped intersection":"じゅうじろ",
                                              "intersection to left":"左と前に行く交差点",
                                              "intersection to right":"右と前に行く交差点",
                                              "T junction":"Tじろ",
                                              "corner":"Lじろ",
                                              "Intersection shape correct.":"交差点の形状を確認。"]
    
    init(lang: language) {
        self.lang = lang
    }
    
    func generateInitialInstructionString(scale: Float?) -> String {
        if lang == .en {
            if scale == nil {
                return "Please step back from the wall and scan surroundings for five seconds. Before starting the navigation, face to the direction of floor map."
            } else {
                return "Please step back from the wall and scan surroundings for five seconds. Before starting the navigation, face to the direction of point of interest."
            }
        } else {
            if scale == nil {
                return "壁から一歩下がり5秒周囲をスキャンしてください。スタートする前に体をフロアマップの方向に向けてください。"
            } else {
                return "壁から一歩下がり5秒周囲をスキャンしてください。スタートする前に体を部屋の方向に向けてください。"
            }
        }
    }
    
    
    func getScanDirectionString(intersectionShapeToScan: [String]) -> String {
        if intersectionShapeToScan.count > 1 || intersectionShapeToScan.count == 0 {
            if lang == .en {
                return "left and right"
            } else {
                return "左右"
            }
        } else {
            if lang == .en {
                return intersectionShapeToScan[0]
            } else {
                return translationENToJP[intersectionShapeToScan[0]]!
            }
        }
    }
    
    func wrongDirection(turnedDirection: String, correctDirectionToTurn: String) -> String {
        if lang == .en {
            return "You went \(turnedDirection) but should go \(correctDirectionToTurn)"
        } else {
            let japaneseTurnedDirection = translationENToJP[turnedDirection]!
            let japaneseCorrectDirectionToTurn = translationENToJP[correctDirectionToTurn]!
            return "\(japaneseTurnedDirection)に行きましたが、\(japaneseCorrectDirectionToTurn)に行くべきでした"
        }
    }
    
    func wrongIntersectionProceedForward() -> String{
        if lang == .en {
            return "This may not be the insersection to turn. Proceed forward."
        } else {
            return "曲がるべき交差点でないので直進してください"
        }
    }
    
    func scanSurrondings(intersectionShapeToScan: [String]) -> String{
        let directionToScanString = getScanDirectionString(intersectionShapeToScan: intersectionShapeToScan)
        
        if lang == .en {
            return "You are in an intersection. Scan \(directionToScanString) for confirmation"
        } else {
            return "交差点に到着しました。確認のため\(directionToScanString) をスキャンしてください"
        }
    }
    
    func arrivedDestination(directionToFace: String) -> String {
        if lang == .en {
            return "\(directionToFace). You have arrived at the destination."
        } else {
            return "\(translationENToJP[directionToFace]!)。目的地に到着しました。"
        }
    }
    
    func generateNecessaryTurn(routeTracker: routeTrackingManager, additionalString: String = "") -> String {
        let numWalkedIntersections = routeTracker.numWalkedIntersections
        let directions = routeTracker.nodeMapManager.directions
        let nextTurn = Array(directions[1...])[numWalkedIntersections-1]
        if nextTurn == "Front" {
            if lang == .en {
                return additionalString + " Go straight"
            } else {
                return translationENToJP[additionalString]! + "直進してください。"
            }
        } else {
            if lang == .en {
                return additionalString + " Turn \(nextTurn)"
            } else {
                print(nextTurn) //the wrong nextTurn is being referring. Specifically, the turn for next turn is referred.
                return translationENToJP[additionalString]! + " \(translationENToJP[nextTurn]!)に曲がってください。"
            }
        }
    }
    
    func generateNextInstruction(userGridIndex: gridIndex, routeTracker: routeTrackingManager) -> String {
        let numWalkedIntersections = routeTracker.numWalkedIntersections
        let distances = routeTracker.nodeMapManager.distances
        let directions = routeTracker.nodeMapManager.directions
        let intersectionShapes = routeTracker.nodeMapManager.intersectionShapes
        let skip = routeTracker.nodeMapManager.filteredSkip
        let numSkip = skip[numWalkedIntersections].1
        
        if numWalkedIntersections == 0 {
            let firstFace = directions[0]
            let nextTurn = directions[1]
            
            if let scale = routeTracker.scale {
                let predictedDistance = distances[numWalkedIntersections] * scale
                if nextTurn == "Front" {
                    if lang == .en {
                        return String(format:"\(firstFace), and go straight for %.0f meters",predictedDistance)
                    } else {
                        return String(format:"\(translationENToJP[firstFace]!)。 その後、%.0fメートル進んでください",predictedDistance)
                    }
                } else {
                    let intersectionType = routeTracker.determineIntersectionType(intersectionShape: intersectionShapes[0])
                    if lang == .en {
                        return String(format:"\(firstFace), go straight for %.0f meters and turn \(nextTurn) in the next \(intersectionType)",predictedDistance)
                    } else {
                        if numSkip > 0 {
                            return String(format:"\(translationENToJP[firstFace]!)。 その後、%.0fメートル進んで\(translationENToJP[intersectionType]!)で\(translationENToJP[nextTurn]!)に曲がってください。\(numSkip)つ交差点を通り過ぎます。",predictedDistance)
                        } else {
                            return String(format:"\(translationENToJP[firstFace]!)。 その後、%.0fメートル進んで\(translationENToJP[intersectionType]!)で\(translationENToJP[nextTurn]!)に曲がってください。",predictedDistance)
                        }
                    }
                }
            } else {
                if nextTurn == "Front" {
                    if lang == .en {
                        return "\(firstFace), and go straight."
                    } else {
                        return "\(translationENToJP[firstFace]!)。その後直進してください。"
                    }
                } else {
                    let intersectionType = routeTracker.determineIntersectionType(intersectionShape: intersectionShapes[0])
                    if lang == .en {
                        return "\(firstFace), go straight and turn \(nextTurn) in the next \(intersectionType)"
                    } else {
                        if numSkip > 0 {
                            return "\(translationENToJP[firstFace]!)。 その後、直進して\(translationENToJP[intersectionType]!)で\(translationENToJP[nextTurn]!)に曲がってください。\(numSkip)つ交差点を通り過ぎます。"
                        } else {
                            return "\(translationENToJP[firstFace]!)。 その後、直進して\(translationENToJP[intersectionType]!)で\(translationENToJP[nextTurn]!)に曲がってください。"
                        }
                    }
                }
            }
        } else if numWalkedIntersections == distances.count - 1 {
            if let scale = routeTracker.scale {
                let distanceFromLastIntersection = routeTracker.calculateDistanceFromLastIntersection(userGridIndex: userGridIndex)
                let predictedDistance = distances[numWalkedIntersections] * scale - distanceFromLastIntersection
                if lang == .en {
                    return String(format: "Walk for %.0f meters", predictedDistance)
                } else {
                    if numSkip > 0 {
                        return String(format: "%.0fメートル直進してください。\(numSkip)つ交差点を通り過ぎます。", predictedDistance)
                    } else {
                        return String(format: "%.0fメートル直進してください。", predictedDistance)
                    }
                }
            } else {
                if lang == .en {
                    return String(format: "Walk straight")
                } else {
                    return String(format: "直進してください")
                }
            }
        } else {
            let nextTurn = Array(directions[1...])[numWalkedIntersections]
            let intersectionType = routeTracker.determineIntersectionType(intersectionShape: intersectionShapes[numWalkedIntersections])
            
            if let scale = routeTracker.scale {
                let distanceFromLastIntersection = routeTracker.calculateDistanceFromLastIntersection(userGridIndex: userGridIndex)
                var predictedDistance = distances[numWalkedIntersections] * scale - distanceFromLastIntersection
                if predictedDistance < 0.50 { predictedDistance = 1 }
                
                if nextTurn == "Front" {
                    if lang == .en {
                        return String(format:"Proceed for %.0f meters and go straight in the next \(intersectionType)",predictedDistance)
                    } else {
                        
                        return String(format:"%.0fメートル進み、次の\(translationENToJP[intersectionType]!)で直進してください。",predictedDistance)
                    }
                } else {
                    if lang == .en {
                        return String(format:"Proceed for %.0f meters and turn \(nextTurn) in the next \(intersectionType)",predictedDistance)
                    } else {
                        if numSkip > 0 {
                            return String(format:"%.0fメートル進み、次の\(translationENToJP[intersectionType]!)で\(translationENToJP[nextTurn]!)に曲がってください。\(numSkip)つ交差点を通り過ぎます。",predictedDistance)
                        } else {
                            return String(format:"%.0fメートル進み、次の\(translationENToJP[intersectionType]!)で\(translationENToJP[nextTurn]!)に曲がってください。",predictedDistance)
                        }
                    }
                }
            } else {
                if nextTurn == "Front" {
                    if lang == .en {
                        return "Go straight in the next \(intersectionType)"
                    } else {
                        return "次の\(translationENToJP[intersectionType]!)で直進してください"
                    }
                } else {
                    if lang == .en {
                        return "Turn \(nextTurn) in the next \(intersectionType)"
                    } else {
                        return "次の\(translationENToJP[intersectionType]!)で\(translationENToJP[nextTurn]!)に曲がってください。"
                    }
                }
            }
        }
    }
    
    func conveyShape(shapeToConvey: [String]) -> String {

        if lang == .en {
            if shapeToConvey.count == 1 {
                return shapeToConvey[0]
            } else if shapeToConvey.count == 2 {
                return shapeToConvey[0] + " and " + shapeToConvey[1]
            } else if shapeToConvey.count == 3 {
                return shapeToConvey[0] + ", " + shapeToConvey[1] + " and" + shapeToConvey[2]
            }
        } else {
            if shapeToConvey.count == 1 {
                return translationENToJP[shapeToConvey[0]]! + "に続くこうさてん"
            } else if shapeToConvey.count == 2 {
                return translationENToJP[shapeToConvey[0]]! + "と" + translationENToJP[shapeToConvey[1]]! + "に続くこうさてん"
            } else if shapeToConvey.count == 3 {
                return translationENToJP[shapeToConvey[0]]! + ", " + translationENToJP[shapeToConvey[1]]! + "と" + translationENToJP[shapeToConvey[2]]! + "に続くこうさてん"
            } else {
                return "エラー。交差点形状パス\(shapeToConvey.count)個です"
            }
        }
        
        return "error"
    }
    
    func generateRouteDescription(directions: [String], intersectionTypes: [String], routeTracker: routeTrackingManager) -> String{
        let translationENToJP4RouteDescription: [String:String] = ["Left":"左",
                                                                   "Right":"右",
                                                                   "Back":"後ろ",
                                                                   "Forward":"前",
                                                                   "Front":"前",
                                                  "Face Left":"まず、左を向きます。",
                                                  "Face Right":"まず、右を向きます。",
                                                  "turn left":"左に曲がってください。",
                                                  "turn right":"右に曲がってください。",
                                                  "X shaped intersection":"じゅうじろ",
                                                  "intersection to left":"左と前に行く交差点",
                                                  "intersection to right":"右と前に行く交差点",
                                                  "T junction":"つきあたりのTじろ",
                                                  "corner":"つきあたりのLじろ"]
        
        let translationENToJP4RouteDescriptionDestination: [String:String] = [
                                                  "Face Left":"左にあります。",
                                                  "Face Right":"右にあります。"]
        
        var routeDescription = "目的地に行くためには"
        var frontCount: Int = 0
        
        for index in 0..<directions.count {
            let direction = directions[index]
            let intersectionType: String
            if index == 0 {
                intersectionType = ""
            } else {
                intersectionType = intersectionTypes[index-1]
            }
            
            if index == 0 {
                routeDescription += translationENToJP4RouteDescription[direction]!
            } else if index == directions.count - 1 {
                if let lastDistance = routeTracker.nodeMapManager.distances.last,
                   let scale = routeTracker.scaleTracker.averageScale() {
                    let lastDistanceMeters = String(format: "%.0f", lastDistance * scale)
                    routeDescription += "最後に、" + lastDistanceMeters + "メートル直進すると、目的地は" + translationENToJP4RouteDescriptionDestination[direction]!
                    
                } else {
                    routeDescription += "最後に、何メートルか直進すると、目的地は" + translationENToJP4RouteDescriptionDestination[direction]!
                }
            } else {
                if direction == "Front" {
                    frontCount += 1
                    continue
                }
                
                if frontCount == 0 {
                    routeDescription += "その次の" + translationENToJP4RouteDescription[intersectionType]! + "で" + translationENToJP4RouteDescription[direction]! + "に曲がってください。"
                } else {
                    routeDescription += String(frontCount) + "つこうさてんを通り過ぎて" + translationENToJP4RouteDescription[intersectionType]! + "で" + translationENToJP4RouteDescription[direction]! + "に曲がってください。"
                }
                
                frontCount = 0
            }
        }
        return routeDescription
    }
    
    func walkedPastIntersectionToTurn(revertedCorrectDirectionToTurn: String) -> String {
        if lang == .en {
            return "you have walked past intersection to turn. go back and turn \(revertedCorrectDirectionToTurn)"
        } else {
            let japaneseRevertedCorrectDirectionToTurn = translationENToJP[revertedCorrectDirectionToTurn]!
            return  "曲がるべき交差点を通り過ぎてしまったようです。戻って一つ前の交差点で\(japaneseRevertedCorrectDirectionToTurn)に曲がってください"
        }
    }
    
    func generateFeedBackString(fbType: feedbackType, fbInfoCapsule: feedBackInformationCapsule) -> String{
        var feedbackString: String!
        
        switch fbType {
        case .scanSurrondings:
            let intersectionShapeToScan = fbInfoCapsule.intersectionShapeToScan!
            feedbackString = scanSurrondings(intersectionShapeToScan: intersectionShapeToScan)
            
        case .generateNextInstruction:
            let userGridIndex = fbInfoCapsule.userGridIndex!
            let routeTracker = fbInfoCapsule.routeTracker!
            feedbackString = generateNextInstruction(userGridIndex: userGridIndex, routeTracker: routeTracker)
            
        case .generateNecessaryTurn:
            let additionalString = fbInfoCapsule.additionalString!
            let routeTracker = fbInfoCapsule.routeTracker!
            feedbackString = generateNecessaryTurn(routeTracker: routeTracker, additionalString: additionalString)
            
        case .wrongIntersectionProceedForward:
            feedbackString = wrongIntersectionProceedForward()
            
        case .wrongDirection:
            let turnedDirection = fbInfoCapsule.turnedDiretion!
            let correctDirectionToTurn = fbInfoCapsule.correctDirectionToTurn!
            feedbackString = wrongDirection(turnedDirection: turnedDirection, correctDirectionToTurn: correctDirectionToTurn)
            
        case .arrivedDestination:
            let directionToFace = fbInfoCapsule.directionToFace!
            feedbackString = arrivedDestination(directionToFace: directionToFace)
            
        case .conveyShape:
            let shapeToConvey = fbInfoCapsule.shapeToConvey!
            feedbackString = conveyShape(shapeToConvey: shapeToConvey)
            
        case .describeRouteDescription:
            let directions = fbInfoCapsule.directions!
            let intersectionTypes = fbInfoCapsule.intersectionTypes!
            let routeTracker = fbInfoCapsule.routeTracker!
            feedbackString = generateRouteDescription(directions: directions, intersectionTypes: intersectionTypes, routeTracker: routeTracker)
             
        case .navigationStart:
            feedbackString = lang == .en ? "start" : "スタート"

        case .walkedPastIntersectionToTurn:
            let revertedCorrectDirectionToTurn = fbInfoCapsule.revertedCorrectDirectionToTurn!
            feedbackString = walkedPastIntersectionToTurn(revertedCorrectDirectionToTurn: revertedCorrectDirectionToTurn)
            
        case .localizationError:
            feedbackString = lang == .en ? "localization error occured" : "エラーが起きました。システムを実験者に渡してください"
        }
        return feedbackString
    }
    
}

extension AVSpeechSynthesizer {
    
    func talk(text: String ,rate: Float = speakingRate, pitch: Float = speakingPitch, language: language){
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.voice = AVSpeechSynthesisVoice(language: language.rawValue)
        self.speak(utterance)
        
        print("Spoke: ",text)
        
    }
}
