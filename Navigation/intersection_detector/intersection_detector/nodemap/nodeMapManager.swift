//
//  nodeMapManager.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/05/14.
//
import Foundation
import UIKit

struct Link: Codable {
    let endNode: String
}

struct Node: Codable {
    var id: String
    var x: Double
    var y: Double
    var nodeClass: String
    var outgoingLinks: [Link]
    var originalX: Double?
    var originalY: Double?
    var directionX: Double?
    var directionY: Double?
}

struct FlaskResponse: Codable {
    let mapData: [String: [Node]]?
    let image: String?
    let time: String?
    let savePath: String?
}

class nodeMapManager {
    
    var mapData: [String: [Node]] = [:]
    var paths: [Node] = []
    var distances: [Float] = []
    var directions: [String] = []
    var poiIDs: [String] = []
    var intersectionTypes: [String] = []
    var intersectionShapes: [[String]] = []
    var selectedCurrentLocation: String = ""
    var selectedDestination: String = ""
    
    var originalDirections: [String] = []
    var originalIntersectionTypes: [String] = []
    
    func readDefaultNodeMap(defaultName: String)  {
        let url = Bundle.main.url(forResource: defaultName, withExtension: "json")
        let jsonData = try? Data(contentsOf: url!)
        self.mapData = try! JSONDecoder().decode([String: [Node]].self, from: jsonData!)
        self.poiIDs = mapData["nodes"]!.filter { $0.nodeClass == "poi" || $0.nodeClass == "initial"}.map { $0.id }
    }
    
    func updateNodeMap(mapData: [String: [Node]])  {
        self.mapData = mapData
        self.poiIDs = mapData["nodes"]!.filter { $0.nodeClass == "poi" || $0.nodeClass == "initial" }.map { $0.id }
    }
    
    func pathPlanning(from pointA: String, to pointB: String, removeUnnecessaryFront: Bool = true) {
        if !doesNodeExist(mapData["nodes"]!, pointA) { return }
        if !doesNodeExist(mapData["nodes"]!, pointB) { return }
        
        let path = shortestPath(mapData["nodes"]!, pointA, pointB)
        var filteredPath = filterPOINodesExceptLast(from: path)
        filteredPath = filterInitialNodesExceptFirst(from: filteredPath)
        var distances = distancesBetweenNodes(path: filteredPath)
        var directions = getDirections(path: filteredPath)
        var intersectionShapes = getIntersectionShapes(paths: filteredPath)
        
        var intersectionTypes: [String] = []
        for intersectionShape in intersectionShapes {
            intersectionTypes.append(determineIntersectionType(intersectionShape: intersectionShape))
        }
        
        originalDirections = directions
        originalIntersectionTypes = intersectionTypes
        
        if removeUnnecessaryFront && filteredPath.count > 0 {
            filteredPath = modifyRouteToRemoveUnnecessaryFront(paths: filteredPath, directions: directions, intersectionShapes: intersectionShapes)
            distances = distancesBetweenNodes(path: filteredPath)
            directions = getDirections(path: filteredPath)
            intersectionShapes = getIntersectionShapes(paths: filteredPath)
        }
        
        intersectionTypes = []
        for intersectionShape in intersectionShapes {
            intersectionTypes.append(determineIntersectionType(intersectionShape: intersectionShape))
        }

        self.paths = filteredPath
        self.distances = distances
        self.directions = directions
        self.intersectionShapes = intersectionShapes
        self.intersectionTypes = intersectionTypes
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
    
    var filteredSkip = [(String, Int)]()
    func modifyRouteToRemoveUnnecessaryFront(paths: [Node], directions: [String], intersectionShapes: [[String]]) -> [Node]{
        var tmpIntersectionShapes = intersectionShapes
        tmpIntersectionShapes[tmpIntersectionShapes.count - 1] = ["Back"]
        
        var discard = [String]()
        var skip = [(String,Int)]()
        
        for i in (1..<paths.count).reversed() {
            var tmpDiscard = [String]()
            let direction = directions[i]
            let prevDirection = directions[i-1]
            let intersectionShape = tmpIntersectionShapes[i-1]
            
            if !(direction == "Front") && prevDirection == "Front" && !intersectionShape.contains("Front") {
                
                for j in (1..<i).reversed() {
                    if directions[j] == "Front" {
                        discard.append(paths[j].id)
                        tmpDiscard.append(paths[j].id)
                    } else {
                        break
                    }
                }
                
            }
            skip.append((paths[i].id,tmpDiscard.count))
        }
        
        var filteredSkip = [(String,Int)]()
        var resultNodes = [Node]()
        
        for path in paths where !discard.contains(path.id) {
            resultNodes.append(path)
        }
        
        let rids = resultNodes.map { $0.id }
        for sk in skip where rids.contains(sk.0) { filteredSkip.append(sk) }
        self.filteredSkip = filteredSkip.reversed()
        
        return resultNodes
    }
    
    func filterPOINodesExceptLast(from path: [Node]) -> [Node] {
        var result = [Node]()
        for (index, node) in path.enumerated() {
            if node.nodeClass != "poi" || index == path.count - 1 || index == 0{
                result.append(node)
            }
        }
        return result
    }
    
    func filterInitialNodesExceptFirst(from path: [Node]) -> [Node] {
        var result = [Node]()
        for (index, node) in path.enumerated() {
            if node.nodeClass == "initial" {
                if !(index == path.count - 1 || index == 0) { continue }
            }
            result.append(node)
        }
        return result
    }
    
    func distancesBetweenNodes(path: [Node]) -> [Float] {
        var distances = [Float]()
        for i in 0..<path.count - 1 {
            let node1 = path[i]
            let node2 = path[i+1]
            let distance = Float(euclideanDistance(node1,node2))
            distances.append(distance)
        }
        return distances
    }
    
    func euclideanDistance(_ a: Node, _ b: Node) -> Double {
        return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }

    func dijkstra(_ nodes: [Node], _ initialNodeId: String) -> ([String: Double], [String: String?]) {
        var distances = [String: Double]()
        var previousNodes = [String: String?]()

        for node in nodes {
            distances[node.id] = Double.infinity
            previousNodes[node.id] = nil
        }

        distances[initialNodeId] = 0

        var queue = [(Double, String)]()  // (distance, nodeId)
        queue.append((0, initialNodeId))

        while !queue.isEmpty {
            queue.sort{ $0.0 < $1.0 }  // Sort queue by distance
            let (currentDistance, currentNodeId) = queue.removeFirst()

            if currentDistance == distances[currentNodeId] {
                let currentNode = nodes.first{ $0.id == currentNodeId }!
                for link in currentNode.outgoingLinks {
                    let neighbor = link.endNode
                    let neighborNode = nodes.first{ $0.id == neighbor }!
                    let altDistance = currentDistance + euclideanDistance(currentNode, neighborNode)

                    if altDistance < distances[neighbor]! {
                        distances[neighbor] = altDistance
                        previousNodes[neighbor] = currentNode.id
                        queue.append((altDistance, neighbor))
                    }
                }
            }
        }

        return (distances, previousNodes)
    }

    func shortestPath(_ nodes: [Node], _ initialNodeId: String, _ targetNodeId: String) -> [Node] {
        let (_, previousNodes) = dijkstra(nodes, initialNodeId)

        var path = [Node]()
        var current: String? = targetNodeId
        while current != nil {
            if let node = nodes.first(where: { $0.id == current }) {
                path.append(node)
            }
            current = previousNodes[current!]?.flatMap { $0 }
        }

        return path.reversed()
    }

    
    func doesNodeExist(_ nodes: [Node], _ nodeId: String) -> Bool {
        for node in nodes {
            if node.id == nodeId {
                return true
            }
        }
        return false
    }
    
    func getIntersectionShapes(paths: [Node]) -> [[String]] {
        var intersectionDirections: [[String]] = []
        
        for (i, path) in paths.enumerated(){
            if i == 0 { continue }
            let neighbourNodeIDs = path.outgoingLinks.map { $0.endNode }
            let pathNodePosition = SIMD2<Float>(x: path.x.float(), y: path.y.float())
            let vectorFrom = normalize(SIMD2<Float>(x: pathNodePosition.x - paths[i-1].x.float(), y: pathNodePosition.y - paths[i-1].y.float()))
            var directions: [String] = []
            
            for neighbourNodeID in neighbourNodeIDs {
                
                let neighborNode = self.mapData["nodes"]!.first{ $0.id == neighbourNodeID }!
                let neighborNodePosition = SIMD2<Float>(x: neighborNode.x.float(), y: neighborNode.y.float())
                let vectorTo = normalize(SIMD2<Float>(x: neighborNodePosition.x - pathNodePosition.x, y: neighborNodePosition.y - pathNodePosition.y))
                // Calculate cross product
                let crossProductZ = vectorTo.x * vectorFrom.y - vectorTo.y * vectorFrom.x
                
                // Calculate angle in degrees
                let dotProduct = max(min(dot(vectorFrom, vectorTo), 1.0), -1.0)
                let angle = acos(dotProduct) * 180 / Float.pi
                
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
            intersectionDirections.append(directions)
        }
        
        return intersectionDirections
    }

    // Extracted function to get vector from original to current location or opposite direction
    func getFacingVector(node: Node) -> SIMD2<Float> {
        if node.nodeClass == "initial" && !(node.directionX == 0 && node.directionY == 0) {
            return normalize(SIMD2<Float>(-Float(node.directionX!), -Float(node.directionY!)))
        } else {
            // cannot use intersection as the destination cuz it assumes originalX is there
            let dx = Float(node.x - node.originalX!)
            let dy = Float(node.y - node.originalY!)
            return normalize(SIMD2<Float>(dx, dy))
        }
    }

    func getDirections(path: [Node]) -> [String] {
        var directions = [String]()

        for i in 0..<path.count {
            let A: Node
            let B = path[i]
            let C: Node
            let BA: SIMD2<Float>

            var additionalString = ""
            if i == 0 ||  i == path.count - 1{
                if i == 0 {
                    C = path[i + 1]
                } else {
                    C = path[i - 1]
                }
                A = path[i]
                BA = getFacingVector(node: A)
                additionalString = "Face "
            } else {
                A = path[i - 1]
                C = path[i + 1]
                let dx = Float(A.x - B.x)
                let dy = Float(A.y - B.y)
                BA = normalize(SIMD2<Float>(dx, dy))
            }

            let dx = Float(C.x - B.x)
            let dy = Float(C.y - B.y)
            let BC = normalize(SIMD2<Float>(dx, dy))

            // Calculate cross product
            let crossProductZ = BA.x * BC.y - BA.y * BC.x

            // Calculate angle in degrees
            let dotProduct = dot(BA, BC)
            let angle = acos(dotProduct) * 180 / Float.pi
            
            let angleRelativeUser = angle - 180
            
            if abs(angleRelativeUser) < 40 {
                directions.append("Front")
            } else if abs(angleRelativeUser) > 140{
                directions.append("Backward")
            }else if crossProductZ < 0 {
                directions.append(additionalString + "Right")
            } else {
                directions.append(additionalString + "Left")
            }
        }

        return directions
    }
}

extension [Node] {
    func nodeIdsFromPath() -> [String] {
        return self.map { $0.id }
    }
}

extension Double {
    func float() -> Float {
        return Float(self)
    }
}

extension [String] {
    func containFront() -> Bool {
        return self.contains("Front")
    }
}
