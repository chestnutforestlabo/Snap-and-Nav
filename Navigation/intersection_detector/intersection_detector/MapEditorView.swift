//
//  MapEditorView.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/07/01.
//

import UIKit
import Foundation
import CoreGraphics

protocol MapEditorViewDelegate {
    func speakFromMapEditor(speechText: String)
    func didFinishEditingMap(intersectionJSON: Data, poiJSON: Data, initialJSON: Data, modifiedMapData: [String: [Node]], serverFunction: ServerFunction)
    func interruptSpeech()
}

enum MapEditorMode: String {
    case modifyUserPos = "modifyUserPos"
    case modifyUserOrientation = "modifyUserOrientation"
}

enum direction: Int {
    case normal = 0
    case reversed = 1
}

class MapEditorViewController: UIViewController {
    
    let imageView: UIImageView = {
        let iv = UIImageView()
        return iv
    }()
    
    let fingerImageView: UIImageView = {
        let iv = UIImageView()
        let image = UIImage(named: "finger.png")
        iv.image = image
        return iv
    }()
    
    let editorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = lang == .en ? "Touch or drag on the image to annotate\n the position of the blind user" : "視覚障害者の位置を\nタッチかドラッグで設定してください"
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        label.numberOfLines = 0
        return label
    }()
    
    let explanationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
//        label.text = "真ん中のボタンを使って\nユーザの方向を設定してください\n\nユーザの向きを設定したら終了ボタンを押してください"
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        label.numberOfLines = 0
        
        return label
    }()

    lazy var button: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(lang == .en ? "Finish Position Annotation" : "視覚障害者の位置修正終了", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold) // Set the font and size
        button.setTitleColor(.darkGray, for: .normal) // Set the text color
//        button.backgroundColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0) // Set the gray-ish background color
        button.backgroundColor = .green
        button.layer.cornerRadius = 10 // Round the button corners for a nice look
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        
        // Adjust button's frame to make it bigger
        let buttonWidth: CGFloat = 300
        let buttonHeight: CGFloat = 100
        
        button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
        
        return button
    }()
    
    lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(lang == .en ? "Go Back To Position" : "位置修正に戻る", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold) // Set the font and size
        button.setTitleColor(.white, for: .normal) // Set the text color
        button.backgroundColor = UIColor(red: 1.0, green: 0.6, blue: 0.6, alpha: 1.0)
        button.layer.cornerRadius = 10 // Round the button corners for a nice look
        button.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        
        // Adjust button's frame to make it bigger
        let buttonWidth: CGFloat = 150
        let buttonHeight: CGFloat = 50
        
        button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
        
        return button
    }()
    
    var selectedEditorMode: MapEditorMode = .modifyUserPos {
        didSet {
            if selectedEditorMode == .modifyUserPos {
                delegate?.interruptSpeech()
                button.setTitle(lang == .en ? "Finish Position Annotation" : "視覚障害者の位置修正終了", for: .normal)
                editorLabel.text = lang == .en ? "Touch or drag on the image to annotate\n the position of the blind user" : "視覚障害者の位置を\nタッチかドラッグで設定してください"
                delegate?.speakFromMapEditor(speechText: "視覚障害者の位置をタッチかドラッグで設定してください。終了したら画面の下の終了ボタンを押してください。")
                backButton.isHidden = true
            } else if selectedEditorMode == .modifyUserOrientation {
                backButton.isHidden = false
                delegate?.interruptSpeech()
                delegate?.speakFromMapEditor(speechText: "視覚障害者の方向をスワイプで設定してください。終了したら画面の下の終了ボタンを押してください。")
                editorLabel.text = lang == .en ? "Swipe on the image to annotate\n orientation of the blind user" : "視覚障害者の方向をスワイプで設定してください"
                button.setTitle(lang == .en ? "Finish Orientation Annotation" : "視覚障害者の方向修正終了", for: .normal)
                
                view.addSubview(fingerImageView)
                fingerImageView.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
                fingerImageView.center = view.center
                fingerImageView.alpha = 1

                UIView.animateKeyframes(withDuration: 1.5, delay: 0, options: [], animations: {
                    
                    // Fade in animation
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1/3) {
                        self.fingerImageView.alpha = 1
                    }
                    
                    // Swipe up animation
                    UIView.addKeyframe(withRelativeStartTime: 1/3, relativeDuration: 1/3) {
                        self.fingerImageView.center.y -= 100
                    }
                    
                    // Fade out animation
                    UIView.addKeyframe(withRelativeStartTime: 2/3, relativeDuration: 1/3) {
                        self.fingerImageView.alpha = 0
                    }
                    
                }) { finished in
                    self.fingerImageView.removeFromSuperview()
                }
            }
        }
    }
    var selectedDirection: direction = .normal
    
    var nodeMapManager: nodeMapManager!
    var capturedImage: UIImage!
    
    var mapData: [String: [Node]] = ["nodes":[]]
    var linkSet: Set<ExistingLink> = []
    
    var initialOrientation: InitialOrientationView!
    var scale: Float!
    
    var delegate: MapEditorViewDelegate?
    
    let deltaYTapped: CGFloat = 50
    
    // Constraints for portrait
    var portraitConstraints: [NSLayoutConstraint] = []
    // Constraints for landscape
    var landscapeConstraints: [NSLayoutConstraint] = []
    
    var serverFunction: ServerFunction!
    
    override func viewWillAppear(_ animated: Bool) {
        AppUtility.lockOrientation(.portrait)
    }
    
    override func viewDidLoad() {
//        self.view.layoutIfNeeded() // Forces a layout pass
        self.navigationItem.hidesBackButton = true
        self.view.backgroundColor = .white
        self.view.addSubview(imageView)
        self.view.addSubview(button)
        self.view.addSubview(explanationLabel)
        self.view.addSubview(editorLabel)
        self.view.addSubview(backButton)
        delegate?.speakFromMapEditor(speechText: "視覚障害者の位置をタッチかドラッグで設定してください。終了したら画面の下の終了ボタンを押してください。")
        
        mapData = nodeMapManager.mapData
        if mapData.isEmpty { mapData["nodes"] = [] }
                
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = capturedImage
        
        let labelTopConstant: CGFloat = capturedImage.size.height > capturedImage.size.width ? 50 : 100
        let imageViewTopConstant: CGFloat = capturedImage.size.height > capturedImage.size.width ? 50 : 100
        let buttonViewTopConstant: CGFloat = capturedImage.size.height > capturedImage.size.width ? 15 : 70
        let backButtonViewTopConstant: CGFloat = capturedImage.size.height > capturedImage.size.width ? 15 : 50

        portraitConstraints = [
            editorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            editorLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: labelTopConstant),
            
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: editorLabel.topAnchor, constant: imageViewTopConstant),
            
            imageView.widthAnchor.constraint(equalTo: view.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: capturedImage.size.height / capturedImage.size.width),
            
            explanationLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            explanationLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 0),
            
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.topAnchor.constraint(equalTo: explanationLabel.bottomAnchor, constant: buttonViewTopConstant),
            
            backButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            backButton.topAnchor.constraint(equalTo: button.bottomAnchor, constant: backButtonViewTopConstant),
        ]

        NSLayoutConstraint.activate(portraitConstraints)
        self.view.layoutIfNeeded()
        let scale = imageView.frame.width / capturedImage.size.width
        self.scale = Float(scale)
        
        backButton.isHidden = true
        
        placeComponentsToImageView()
    }
    
    func placeComponentsToImageView() {
        
        for (i, node) in mapData["nodes"]!.enumerated() where node.nodeClass == "intersection" {
            var tmpLink = [Link]()
            for link in node.outgoingLinks {
                let endNode = searchConnectedIntersection(endNodeID: link.endNode, passedNodes: [node.id])
                tmpLink.append(Link(endNode: endNode.id))
                let testLink = ExistingLink(start: node.id, end: endNode.id)
                
                if linkSet.contains(testLink) { continue }
                
                var newLink = ExistingLink(start: node.id, end: endNode.id)
                linkSet.insert(newLink)
                newLink = ExistingLink(start: endNode.id, end: node.id)
                linkSet.insert(newLink)
            }
            mapData["nodes"]![i].outgoingLinks = tmpLink
        }
        
        let initialNode = Node(id: "現在地", x: -100, y: -100, nodeClass: "initial", outgoingLinks: [], directionX: 1, directionY: 0)
        if let index = mapData["nodes"]!.firstIndex(where: { $0.nodeClass == "initial" }) {
            mapData["nodes"]![index] = initialNode
        } else {
            mapData["nodes"]!.append(initialNode)
        }
        initialOrientation = InitialOrientationView(frame: imageView.bounds, initalPosNode: initialNode, scale: CGFloat(self.scale), direction: selectedDirection)
        initialOrientation.layer.zPosition = 2
        let dotView = DotView(frame: imageView.bounds, node: initialNode, scale: CGFloat(self.scale), nodeClass: initialNode.nodeClass)
        imageView.addSubview(dotView)
        imageView.isUserInteractionEnabled = true
        let imgViewPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanImgView(_:)))
        let imgViewTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapImgView(_:)))
        imageView.addGestureRecognizer(imgViewPanGesture)
        imageView.addGestureRecognizer(imgViewTapGesture)
    }
    
    func searchConnectedIntersection(endNodeID: String, passedNodes: [String]) -> Node {
        let endNode = mapData["nodes"]!.first(where: { $0.id == endNodeID })
        if endNode!.nodeClass == "intersection" {
            return endNode!
        } else {
            let outgointLinks = endNode?.outgoingLinks
            for link in outgointLinks! {
                if !passedNodes.contains(link.endNode) {
                    return searchConnectedIntersection(endNodeID: link.endNode, passedNodes: passedNodes + [endNodeID])
                }
            }
        }
        return endNode!
    }
    
    

    
    @objc func handleTapImgView(_ recognizer: UITapGestureRecognizer) {

        guard let index = mapData["nodes"]!.firstIndex(where: { $0.nodeClass == "initial" }) else { return }
        
        if selectedEditorMode == .modifyUserPos{
            initialOrientation.removeFromSuperview()
            let initialLocation = recognizer.location(in: imageView)
            mapData["nodes"]![index].x = initialLocation.x / Double(self.scale!)
            mapData["nodes"]![index].y = initialLocation.y / Double(self.scale!)
            let dotViews = imageView.subviews.compactMap { $0 as? DotView }
            guard let initialDotView = dotViews.first(where: { $0.node.nodeClass == "initial" }) else { return }
            initialDotView.center = initialLocation
            
            for view in imageView.subviews {
                if let dotView = view as? DotView {
                    imageView.bringSubviewToFront(dotView)
                }
            }
        }
    }
    
    @objc func handlePanImgView(_ recognizer: UIPanGestureRecognizer) {
        
        guard let index = mapData["nodes"]!.firstIndex(where: { $0.nodeClass == "initial" }) else { return }
        let tappedLocation = recognizer.location(in: imageView)
        initialOrientation.removeFromSuperview()
        
        if selectedEditorMode == .modifyUserPos {
            if !imageView.bounds.contains(CGPoint(x: tappedLocation.x, y: tappedLocation.y - deltaYTapped)) { return }
            var initialLocation = recognizer.location(in: imageView)
            initialLocation.y -= deltaYTapped
            
            mapData["nodes"]![index].x = initialLocation.x / Double(self.scale!)
            mapData["nodes"]![index].y = initialLocation.y / Double(self.scale!)
            let dotViews = imageView.subviews.compactMap { $0 as? DotView }
            guard let initialDotView = dotViews.first(where: { $0.node.nodeClass == "initial" }) else { return }
            initialDotView.center = initialLocation
        } else if selectedEditorMode == .modifyUserOrientation {
            
            let finalLocation = recognizer.location(in: imageView)
            print(mapData["nodes"]![index])
            mapData["nodes"]![index].originalX = finalLocation.x / Double(self.scale!)
            mapData["nodes"]![index].originalY = finalLocation.y / Double(self.scale!)
            
            mapData["nodes"]![index].directionX = mapData["nodes"]![index].originalX! - mapData["nodes"]![index].x
            mapData["nodes"]![index].directionY = mapData["nodes"]![index].originalY! - mapData["nodes"]![index].y
            
            initialOrientation = InitialOrientationView(frame: imageView.bounds, initalPosNode: mapData["nodes"]![index], scale: CGFloat(scale), direction: selectedDirection)
            initialOrientation.layer.zPosition = 1
            imageView.addSubview(initialOrientation)
        }
        
        for view in imageView.subviews {
            if let dotView = view as? DotView {
                imageView.bringSubviewToFront(dotView)
            }
        }

    }
    
    @objc func backButtonTapped() {
        self.selectedEditorMode = .modifyUserPos
    }
    
    @objc func buttonTapped() {
        delegate?.interruptSpeech()
        
        if self.selectedEditorMode == .modifyUserPos {
            
            let dotViews = imageView.subviews.compactMap { $0 as? DotView }
            guard let initialDotView = dotViews.first(where: { $0.node.nodeClass == "initial" }) else { return }
            if initialDotView.center.x < 0 || initialDotView.center.y < 0 {
                delegate?.speakFromMapEditor(speechText: "位置設定が完了していません。視覚障害者の位置をタッチかドラッグで設定してください。")
                return
            }
            
            self.selectedEditorMode = .modifyUserOrientation
        } else if self.selectedEditorMode == .modifyUserOrientation {
            if !initialOrientation.isDescendant(of: imageView) {
                delegate?.speakFromMapEditor(speechText: "方向設定が完了していません。視覚障害者の方向をスワイプで設定してください。")
                return
            }
            guard let index = mapData["nodes"]!.firstIndex(where: { $0.nodeClass == "initial" }) else { return }
            
            mapData["nodes"]![index].originalX = initialOrientation.endPoint.x / Double(self.scale!)
            mapData["nodes"]![index].originalY = initialOrientation.endPoint.y / Double(self.scale!)
            
            mapData["nodes"]![index].directionX = Double(initialOrientation.directionX)
            mapData["nodes"]![index].directionY = Double(initialOrientation.directionY)
            
            let intersectionMapData = filterMapData(nodes: mapData, desiredClass: "intersection")
            let intersectionJSON = convertToJSON(nodes: intersectionMapData, fileName: "intersections")!
            let poiMapData = filterMapData(nodes: mapData, desiredClass: "poi")
            let poiJSON = convertToJSON(nodes: poiMapData, fileName: "poi")!
            let initialMapData = filterMapData(nodes: mapData, desiredClass: "initial")
            let initialJSON = convertToJSON(nodes: initialMapData, fileName: "initial")!
            delegate?.interruptSpeech()
            delegate?.didFinishEditingMap(intersectionJSON: intersectionJSON, poiJSON: poiJSON, initialJSON: initialJSON, modifiedMapData: mapData, serverFunction: serverFunction)
            
            self.navigationController?.popViewController(animated: true)
        }
    }
    
    func convertToJSON(nodes: [String:[Node]], fileName: String) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // This makes the JSON easier to read

        do {
            // Convert the Node array to JSON Data
            let jsonData = try encoder.encode(nodes)
            
            // Convert to a JSON string
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
                
                // Write JSON string to a file
                let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName + ".json")
                
                do {
                    try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
                    print("Successfully wrote JSON to file: \(fileURL)")
                } catch {
                    print("Error writing JSON to file: \(error)")
                }
            }
            return jsonData
        } catch {
            print("Error encoding Node array to JSON: \(error)")
        }
        return nil
    }
    
    func filterMapData(nodes: [String:[Node]], desiredClass: String) -> [String:[Node]] {

        // Filter nodes based on nodeClass
        let filteredNodes = nodes["nodes"]!.filter { node in
            return node.nodeClass == desiredClass
        }
        
        return ["nodes":filteredNodes]
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
//        AppUtility.lockOrientation(.portrait)
    }
}


class DotView: UIView {
    var dotDiameter: CGFloat = 15.0 // adjust this to the size you want for the dots
    let node: Node // Assuming you have a Node object with properties like x, y, id, and nodeClass
    var scale: CGFloat // Assuming you have a scale value
    
    init(frame: CGRect, node: Node, scale: CGFloat, nodeClass: String) {
        self.node = node
        self.scale = scale
        
        if nodeClass == "intersection" {
            dotDiameter = 10
        } else if nodeClass == "initial" {
            dotDiameter = 20
        }
        
        super.init(frame: CGRect(x: 0, y: 0, width: dotDiameter, height: dotDiameter))
        
        self.layer.cornerRadius = dotDiameter / 2
        
        if node.nodeClass == "intersection" {
            self.center = CGPoint(x: node.x * scale, y: node.y * scale)
            self.backgroundColor = .red
        } else if node.nodeClass == "poi" {
            self.center = CGPoint(x: node.x * scale, y: node.y * scale)
            self.backgroundColor = .orange
        } else if node.nodeClass == "initial" {
            self.center = CGPoint(x: -100, y: -100)
            self.backgroundColor = colorUser
        }
        
        self.isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class LinkView: UIView {
    let startNode: Node
    let endNode: Node
    var scale: CGFloat
    
    init(frame: CGRect, startNode: Node, endNode: Node, scale: CGFloat) {
        self.startNode = startNode
        self.endNode = endNode
        self.scale = scale
        
        super.init(frame: frame)
        
        self.backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        
        let path = UIBezierPath()
        path.move(to: CGPoint(x: startNode.x * scale, y: startNode.y * scale))
        path.addLine(to: CGPoint(x: endNode.x * scale, y: endNode.y * scale))
                
        UIColor.white.setStroke()
        path.lineWidth = 2
        path.stroke()
        
        context.restoreGState()
    }
    
    func updateScale(newScale: CGFloat) {
        self.scale = newScale
        setNeedsDisplay() // Calls draw method with updated scale
    }
}

class InitialOrientationView: UIView {
    let node: Node
    var scale: CGFloat
    let desiredLength: CGFloat = 30
    let direction: direction
    var endPoint: CGPoint = CGPoint()
    var directionX: Float = 0
    var directionY: Float = 0
    
    init(frame: CGRect, initalPosNode: Node, scale: CGFloat, direction: direction) {
        self.node = initalPosNode
        self.scale = scale
        self.direction = direction
        
        super.init(frame: frame)
        self.backgroundColor = .clear
        let startPoint = CGPoint(x: node.x * scale, y: node.y * scale)
        var vectorX: CGFloat
        var vectorY: CGFloat

        if node.directionX == 0 && node.directionY == 0 {
            vectorX = node.originalX! - node.x
            vectorY = node.originalY! - node.y
            let norm = sqrt(vectorX * vectorX + vectorY * vectorY)
            vectorX /= norm
            vectorY /= norm
        } else {
            vectorX = node.directionX!
            vectorY = node.directionY!
        }

        if direction == .reversed {
            vectorX *= -1.0
            vectorY *= -1.0
        }

        let endPoint = CGPoint(x: startPoint.x + vectorX, y: startPoint.y + vectorY)

        // Get the difference between the start and end points
        var dx = endPoint.x - startPoint.x
        var dy = endPoint.y - startPoint.y

        // Calculate the length of this difference vector
        let length = sqrt(dx * dx + dy * dy)

        // Normalize the difference vector to have length 1 and Scale the difference vector to the desired length
        dx *= desiredLength / length
        dy *= desiredLength / length

        // Calculate the new end point
        let newEndPoint = CGPoint(x: startPoint.x + dx, y: startPoint.y + dy)
        self.endPoint = newEndPoint
        self.directionX = vectorX.float()
        self.directionY = vectorY.float()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        
        let startPoint = CGPoint(x: node.x * scale, y: node.y * scale)
        
        let path = UIBezierPath()
        path.move(to: startPoint)
        path.addLine(to: self.endPoint)
        drawArrow(from: startPoint, to: self.endPoint, in: context)
        
        colorUser.setStroke()
        path.lineWidth = 2
        path.lineCapStyle = .round // This rounds the corners
        path.stroke()
        
        context.restoreGState()
    }
    
    private func drawArrow(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        let length = CGFloat(10.0)
        let headWidth = CGFloat(10.0)
        let headLength = CGFloat(10.0)

        // The points we're going to draw
        var points = [
            end
        ]
        
        // Calculate the segment direction before normalize
        var dx = end.x - start.x
        var dy = end.y - start.y
        
        // Normalize it to adjust the length (making length = 1)
        let vectorLength = sqrt(dx*dx + dy*dy)
        dx /= vectorLength
        dy /= vectorLength
        
        // Calculate the tail of arrow
        let tailEnd = CGPoint(x: end.x - length * dx, y: end.y - length * dy)
        
        // Calculate the arrowhead points
        let headEnd1 = CGPoint(x: tailEnd.x - headLength * dx - headWidth * dy,
                               y: tailEnd.y - headLength * dy + headWidth * dx)
        let headEnd2 = CGPoint(x: tailEnd.x - headLength * dx + headWidth * dy,
                               y: tailEnd.y - headLength * dy - headWidth * dx)

        points.append(headEnd1)
        points.append(end)
        points.append(headEnd2)

        // Add our path
        context.beginPath()
        context.move(to: points[0])
        for p in points.dropFirst() {
            context.addLine(to: p)
        }
        context.closePath()
        colorUser.setStroke()
        context.setLineWidth(2.0)
        // Stroke path
        context.strokePath()
    }
    
    func updateScale(newScale: CGFloat) {
        self.scale = newScale
        setNeedsDisplay() // Calls draw method with updated scale
    }


}


struct ExistingLink: Hashable {
    let start: String
    let end: String
}
