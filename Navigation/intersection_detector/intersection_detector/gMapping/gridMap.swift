//
//  gridMap.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/05/14.
//

import Foundation
import SceneKit
import UIKit
import ARKit

enum gridtype: Int {
    case none = 0
    case obstacle = 1
    case floor = 2
    case user = 3
    case center = 4
    case arrows = 5
}

struct gridIndex: Hashable, Equatable{
    var x: Int
    var y: Int
    
    static func == (left: gridIndex, right: gridIndex) -> Bool {
        if left.x == right.x && left.y == right.y {
            return true
        }
        return false
    }
    
    static func != (left: gridIndex, right: gridIndex) -> Bool {
        if left.x != right.x || left.y != right.y {
            return true
        }
        return false
    }
    
    func distanceTo(other: gridIndex) -> Float {
        let dx = Float(self.x - other.x)
        let dy = Float(self.y - other.y)
        return sqrt(dx*dx + dy*dy)
    }
}

struct gridValue: Hashable, Equatable {
    var obstacleCount: Int = 0
    var floorCount: Int = 0
    var gridClass: gridtype = .none
    
    static func += (left: inout gridValue, right: gridValue) {
        left.obstacleCount += right.obstacleCount
        left.floorCount += right.floorCount
        
        if left.obstacleCount > left.floorCount {
            left.gridClass = .obstacle
        } else if left.obstacleCount < left.floorCount {
            left.gridClass = .floor
        } else {
            left.gridClass = .obstacle
        }
    }
}

let gridColor:[gridtype:UIColor] = [gridtype.obstacle:UIColor.black,
                                    gridtype.floor:UIColor.white,
                                    gridtype.user:UIColor.cyan,
                                    gridtype.center:UIColor.red,
                                    gridtype.arrows:UIColor.green]

class gridPlaneNode: SCNNode {
    var gridIndex: gridIndex!
    var gridType: gridtype! {
        didSet {
            let material = SCNMaterial()
            material.diffuse.contents = gridColor[self.gridType]
            self.geometry?.firstMaterial = material
        }
    }
    
    init(gridIndex: gridIndex, gridType: gridtype, name: String = "", dy: Float = 0.0) {
        super.init()
        self.gridIndex = gridIndex
        self.gridType = gridType
        self.geometry = SCNPlane(width: CGFloat(gridMapLength), height: CGFloat(gridMapLength))
        let material = SCNMaterial()
        material.diffuse.contents = gridColor[self.gridType]
        self.geometry?.firstMaterial = material
        self.simdPosition = simd_float3(Float(gridIndex.x) * gridMapLength,dy,Float(gridIndex.y) * gridMapLength)
        self.eulerAngles.x -= .pi / 2
        self.name = name
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

protocol GridMapDelegate: AnyObject {
    func didUpdateGridMap(node: gridPlaneNode)
}

class gMapping{
    var map: [gridIndex: gridValue] = [:]
    var node: [gridIndex:gridPlaneNode] = [:]
    var delegate: GridMapDelegate!
    
    init() {
    }
    
    func GridMapping2D(outputGridInfo: [simd_float4], outputPositions: [simd_float3], outputNormals: [simd_float3],userGridPosition: gridIndex ,camera: ARCamera, rayCastingOption: Bool = true){
        var localGridMap: [gridIndex: gridValue] = [:]
        
        for info in outputGridInfo where info.z != 0 || info.w != 0 {
            let index = gridIndex(x: Int(info[0]), y: Int(info[1]))
            let value = gridValue(obstacleCount: Int(info[3]), floorCount: Int(info[2]))
            localGridMap[index, default: gridValue()] += value
        }
        
        if rayCastingOption {
            for (gridIndexKey, gridvalue) in localGridMap where gridvalue.gridClass != gridtype.obstacle {
                let indexInBetween  = indexBetweenTwoPoints(from : userGridPosition, to: gridIndexKey, localGridMap: localGridMap)
                let value = gridValue(obstacleCount: 0, floorCount: 1)
                for index in indexInBetween { localGridMap[index, default: gridValue()] += value }
            }
        }
        
        for (gridIndexKey, gridvalue) in localGridMap where gridvalue.gridClass != gridtype.none {
            
            if map[gridIndexKey] == nil {
                map[gridIndexKey] = gridvalue
                let newNode = gridPlaneNode(gridIndex: gridIndexKey, gridType: gridvalue.gridClass)
                node[gridIndexKey] = newNode
                delegate.didUpdateGridMap(node: newNode)
            } else {
                map[gridIndexKey]?.gridClass = gridvalue.gridClass
                node[gridIndexKey]?.gridType = gridvalue.gridClass
            }
        }
        
        if map.count > 0{
            deleteGridsOut(userGridPosition: userGridPosition)
        }
    }
        
    func deleteGridsOut(userGridPosition: gridIndex, indexWithIn: Int = 64) {
        for grid in map where !(abs(grid.key.x - userGridPosition.x) < indexWithIn && abs(grid.key.y - userGridPosition.y) < indexWithIn){
            node[grid.key]?.removeFromParentNode()
            map.removeValue(forKey: grid.key)
            node.removeValue(forKey: grid.key)
        }
    }
    
    func indexBetweenTwoPoints(from pointA: gridIndex, to pointB: gridIndex, localGridMap: [gridIndex: gridValue]) -> [gridIndex] {
        var gridInBetween: [gridIndex] = []
        
        if pointB.x == pointA.x {
            if pointB.y == pointA.y { return [] }
            let y1: Int!
            let y2: Int!
            if pointA.y < pointB.y {
                y1 = pointA.y
                y2 = pointB.y
            } else {
                y1 = pointB.y
                y2 = pointA.y
            }
            for y in y1..<y2 {
                let index = gridIndex(x: pointA.x, y: y)
                if localGridMap[index] != nil { continue }
                gridInBetween.append(index)
            }
        } else {
            let deltaX = pointB.x - pointA.x
            let deltaY = pointB.y - pointA.y
            let slope = Float(deltaY) / Float(deltaX)
            let x1: Int!
            let x2: Int!
            if pointA.x < pointB.x {
                x1 = pointA.x
                x2 = pointB.x
            } else {
                x1 = pointB.x
                x2 = pointA.x
            }
            for x in x1..<x2{
                let y = Int(round(linerFunction(slope: slope, passPoint: pointA, x: Float(x))))
                let index = gridIndex(x: x, y: y)
                if localGridMap[index] != nil { continue }
                gridInBetween.append(index)
            }
        }
        return gridInBetween
    }
    
    func linerFunction(slope: Float, passPoint: gridIndex, x: Float) -> Float {
        return slope * ( x - Float(passPoint.x) ) + Float(passPoint.y)
    }
}

class pointCloudCalculator {
    private let orientation = UIInterfaceOrientation.portrait
    lazy var pointCloudUniforms: PointCloudUniforms = PointCloudUniforms()
    var pointCloudUniformBuffers: MetalBuffer<PointCloudUniforms>!
    var selectedPointCloudConfidence: Int = 1 // 0:low, 1:medium, 2:high
    private let device = MTLCreateSystemDefaultDevice()!
    private var library: MTLLibrary!
    private var commandQueue: MTLCommandQueue!
    private var computePipelineState: MTLComputePipelineState!
    private lazy var textureCache = makeTextureCache()
    var gridPoints: [Float2] = []
    
    init() {
        initMetal()
    }
    
    func acquirePointCloudInfo(camera: ARCamera, depthMap: CVPixelBuffer, confidenceMap: CVPixelBuffer, floorHeight: Float, necessaryMatrixForPointCloudCalculation: NecessaryMatrixForPointCloudCalculation) -> ([simd_float3], [simd_float3], [simd_float4]) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else
        {return ([], [], [])}
        
        let gridPoints = gridPoints.count == 0 ? self.makeGridPoints(camera: camera) : gridPoints
        
        pointCloudUniforms.localToWorld = necessaryMatrixForPointCloudCalculation.localToWorld
        pointCloudUniforms.cameraIntrinsicsInversed = necessaryMatrixForPointCloudCalculation.cameraIntrinsicsInversed
        pointCloudUniforms.cameraResolution = necessaryMatrixForPointCloudCalculation.cameraResolution
        pointCloudUniforms.currentHeight = necessaryMatrixForPointCloudCalculation.currentHeight
        
        pointCloudUniforms.confidenceThreshold = UInt32(selectedPointCloudConfidence)
        pointCloudUniforms.gridWidth = UInt32(threadgroupsPerGridWidth)
        pointCloudUniforms.gridHeight = UInt32(threadsPerThreadgroupWidth)
        pointCloudUniforms.gridMapLength = gridMapLength
        pointCloudUniforms.floorHeight = floorHeight
        pointCloudUniforms.floorNormalY = floorNormalY
        pointCloudUniforms.ceilingNormalY = ceilingNormalY
        
        pointCloudUniformBuffers = MetalBuffer<PointCloudUniforms>(device: device, count: 1, index: 0)
        pointCloudUniformBuffers[0] = pointCloudUniforms
        
        let depthTexture = makeTexture(fromPixelBuffer: depthMap, pixelFormat: .r32Float, planeIndex: 0)
        let confidenceTexture = makeTexture(fromPixelBuffer: confidenceMap, pixelFormat: .r8Uint, planeIndex: 0)
        
        let gridPointsBuffer = MetalBuffer<Float2>(device: device, array: gridPoints, index: 2, options: [])
        
        var outputPosition = [simd_float3](repeating: simd_float3(0, 0, 0), count: threadsPerThreadgroupWidth * threadgroupsPerGridWidth)
        let outputPositionBuffer = device.makeBuffer(bytes: outputPosition, length: MemoryLayout<simd_float3>.stride * outputPosition.count, options: [])
        
        var outputNormal = [simd_float3](repeating: simd_float3(0, 0, 0), count: threadsPerThreadgroupWidth * threadgroupsPerGridWidth)
        let outputNormalBuffer = device.makeBuffer(bytes: outputNormal, length: MemoryLayout<simd_float3>.stride * outputNormal.count, options: [])
        
        var outputGridInfo = [simd_float4](repeating: simd_float4(0, 0, 0, 0), count: threadsPerThreadgroupWidth * threadgroupsPerGridWidth)
        let outputGridInfoBuffer = device.makeBuffer(bytes: outputGridInfo, length: MemoryLayout<simd_float4>.stride * outputGridInfo.count, options: [])
        
        let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeCommandEncoder.setComputePipelineState(computePipelineState)
        computeCommandEncoder.setBuffer(pointCloudUniformBuffers.buffer, offset: 0, index: 0)
        computeCommandEncoder.setBuffer(gridPointsBuffer.buffer, offset: 0, index: 1)
        computeCommandEncoder.setBuffer(outputPositionBuffer, offset: 0, index: 2)
        computeCommandEncoder.setBuffer(outputNormalBuffer, offset: 0, index: 3)
        computeCommandEncoder.setBuffer(outputGridInfoBuffer, offset: 0, index: 4)
        computeCommandEncoder.setTexture(CVMetalTextureGetTexture(depthTexture!), index: 0)
        computeCommandEncoder.setTexture(CVMetalTextureGetTexture(confidenceTexture!), index: 1)
        
        let threadgroupsPerGrid = MTLSize(width: threadgroupsPerGridWidth, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: threadsPerThreadgroupWidth, height: 1, depth: 1)
        computeCommandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        computeCommandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let resultPosition = Data(bytesNoCopy: outputPositionBuffer!.contents(), count: MemoryLayout<simd_float3>.stride * outputPosition.count, deallocator: .none)
        outputPosition = resultPosition.withUnsafeBytes { Array(UnsafeBufferPointer(start: $0.baseAddress!.assumingMemoryBound(to: simd_float3.self ), count: $0.count / MemoryLayout<simd_float3>.size)) }
        
        let resultNormal = Data(bytesNoCopy: outputNormalBuffer!.contents(), count: MemoryLayout<simd_float3>.stride * outputNormal.count, deallocator: .none)
        outputNormal = resultNormal.withUnsafeBytes { Array(UnsafeBufferPointer(start: $0.baseAddress!.assumingMemoryBound(to: simd_float3.self ), count: $0.count / MemoryLayout<simd_float3>.size)) }
        
        let resultGridInfo = Data(bytesNoCopy: outputGridInfoBuffer!.contents(), count: MemoryLayout<simd_float4>.stride * outputGridInfo.count, deallocator: .none)
        outputGridInfo = resultGridInfo.withUnsafeBytes { Array(UnsafeBufferPointer(start: $0.baseAddress!.assumingMemoryBound(to: simd_float4.self ), count: $0.count / MemoryLayout<simd_float4>.size)) }
        
        return (outputPosition, outputNormal, outputGridInfo)
    }
    
    func makeTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
    func makeTextureCache() -> CVMetalTextureCache {
        // Create captured image texture cache
        var cache: CVMetalTextureCache!
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        
        return cache
    }
    
    func makeGridPoints(camera: ARCamera) -> [Float2] {
        let cameraResolution = Float2(Float(camera.imageResolution.width), Float(camera.imageResolution.height))
        let numGridPoints = threadgroupsPerGridWidth * threadsPerThreadgroupWidth
        
        let gridArea = cameraResolution.x * cameraResolution.y
        let spacing = sqrt(gridArea / Float(numGridPoints))
        let deltaX = Int(round(cameraResolution.x / spacing))
        let deltaY = Int(round(cameraResolution.y / spacing))
        
        var points = [Float2]()
        for gridY in 0 ..< deltaY {
            let alternatingOffsetX = Float(gridY % 2) * spacing / 2
            for gridX in 0 ..< deltaX {
                let cameraPoint = Float2(alternatingOffsetX + (Float(gridX) + 0.5) * spacing, (Float(gridY) + 0.5) * spacing)
                points.append(cameraPoint)
            }
        }
        
        return points
    }
    
    private func initMetal() {
        library = device.makeDefaultLibrary()
        let function = library.makeFunction(name: "computeFunction")!
        computePipelineState = try! device.makeComputePipelineState(function: function)
        commandQueue = device.makeCommandQueue()!
    }
    
    
}
