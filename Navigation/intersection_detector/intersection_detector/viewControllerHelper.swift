//
//  viewControllerHelper.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2021/06/13.
//

import UIKit
import ARKit
import Foundation

enum SystemMode: Int {
    case baseline = 0
    case proposed = 1
}

func CustomNSLog(_ fmt: String, _ args: CVarArg...) {
    let msg = String(format: fmt, arguments: args)
    if (isatty(STDERR_FILENO) == 0) {
        print(msg)
    }
    NSLogv(fmt, getVaList(args))
}


func calculateAverage(i: Int, n: Int, pastPositions: [gridIndex]) -> (x: Float, y: Float){
    let j = i - n
    var averageX: Float = 0
    var averageY: Float = 0
    for index in j...i {
        averageX += Float(pastPositions[index].x)
        averageY += Float(pastPositions[index].y)
    }
    averageX /= Float(n)
    averageY /= Float(n)
    return (x: averageX, y: averageY)
}

func confirmIntersectionShape(correctIntersectionShape: [String], scanedIntersectionshape: [String], directionToHead: String, shouldConfirmAll: Bool = shouldConfirmAll) -> Bool {
    
    var set1 = Set(correctIntersectionShape)
    var set2 = Set(scanedIntersectionshape)
    set1.remove("Back")
    set2.remove("Back")
    
    if shouldConfirmAll {
        if set1 == set2 {
            return true
        }
        
        return false
    } else {
        if set2.count > set1.count { return false }
        return set2.contains(directionToHead)
    }
    
}

func isValueInRange(value: Int, min: Int, max: Int) -> Bool {
    return value >= min && value <= max
}

func fetchAPIKey() -> String? {
    if let url = Bundle.main.url(forResource: "API", withExtension: "json") {
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            
            if let object = json as? [String: Any], let apiKey = object["APIkey"] as? String {
                // json is a dictionary and APIkey is found
                return apiKey
            } else {
                print("No API key found or JSON is invalid")
            }
        } catch {
            print("Error reading JSON: \(error)")
        }
    } else {
        print("No JSON file found")
    }
    
    return nil
}

extension CGFloat {
    func float() -> Float{
        return Float(self)
    }
}

func biImplication(a: Bool, b: Bool) -> Bool {
    return a == b
}

extension simd_float2 {
    func norm() -> Float {
        return sqrt(self.x * self.x + self.y * self.y)
    }
}

extension Int {
    func float() -> Float {
        return Float(self)
    }
}
