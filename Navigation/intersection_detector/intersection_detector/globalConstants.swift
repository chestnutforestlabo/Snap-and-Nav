//
//  globalConstants.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2021/05/14.
//
import Foundation
import UIKit

let defaultMapName = "121-5-1"

let testMapName = "b1"
let taskMapName1 = "1105"
let taskMapName2 = "1205"

let degreeToScan: Float = 75

let testMode: Bool = true

let useMultiPeer: Bool = false

let useEmergencyVibration: Bool = true

let useScaleTracker: Bool = true

let urlString = "http://XX.XXX.XXX:5001"

let lang: language = .jp

let shouldConfirmAll = true
let forceScanAll = false

let imgSize: Float = 128

// chageing this number will make the scale different
let gridMapLength: Float = 0.15

//fps
let fps: Double = 10 //this changes fps of mapping

//determine whther the user is stopping by this number
let velocityNormThreshold: Float = 2

// constants for alignment
let pastSecondsForAlignment: Double = 2.0
var N: Int { return Int(pastSecondsForAlignment * fps) }

//for TTS
let speakingRate: Float = 0.60
let speakingPitch: Float = 1.30

// sampling number from depth map
let threadgroupsPerGridWidth:Int = 80
let threadsPerThreadgroupWidth: Int = 60

//constants for mapping
let floorNormalY: Float = 0.80
let ceilingNormalY: Float = -0.7

//image constants
var imageSize: CGFloat = 200
let RGBImageWidth: CGFloat = 170
let RGBImageMarginY: CGFloat = 35
let cameraHeight: Float = 40

let colorUser: UIColor = UIColor.green

