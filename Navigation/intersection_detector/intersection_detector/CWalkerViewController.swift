//
//  CWalkerViewController.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/06/11.
//


import UIKit
import SceneKit
import ARKit
import MetalKit
import Metal
import AVFoundation

protocol CWalkerViewControllerDelegate: AnyObject {
    func didFinishNavigation(arrivedDestination: String, scale: Float!, scaleTracker: ScaleTracker)
}

class CWalkerViewController: UIViewController, AVSpeechSynthesizerDelegate, CWalkerControllerDelegate, GridMapDelegate {
    
    var delegate: CWalkerViewControllerDelegate?
    var nodeMapManager: nodeMapManager!
    var CWalker: CWalkerController!
    var bboxes: BoundingBoxes!
    
    var scnView: SCNView!
    var scene: SCNScene!
    var arcnSceneView: ARSCNView!
    
    var TTS: AVSpeechSynthesizer!
    var systemMode: SystemMode!
    
    let confidenceControl: UISegmentedControl! = UISegmentedControl(items: ["Low", "Med", "High"])
    let label: UILabel = UILabel()
    let sessionInfoLabel: UILabel = UILabel()
    var stackView = UIStackView()
    let imgview = UIImageView()
    
    var userPosition: gridPlaneNode!
    let cameraNode = SCNNode()
    let camera = SCNCamera()
    let soundPlayer = SoundPlayer()
    
    var vibrationManager: VibrationManager!
    
    var feedBackManage: feedBackManager!
    
    var scaleTracker: ScaleTracker!
    
    var scale: Float!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if systemMode == .proposed {
            self.navigationItem.hidesBackButton = true
        }
        feedBackManage = feedBackManager(lang: lang)
        
        setupScene()
        AVSpeechSynthesisVoice.speechVoices()
        
        self.TTS.delegate = self
        if systemMode == .proposed {
            let initialInstruction = feedBackManage.generateInitialInstructionString(scale: scale)
            TTS.talk(text: initialInstruction, language: lang) //make jap vep
        }
        
        scnView.frame = view.frame
        scnView.translatesAutoresizingMaskIntoConstraints = false
        
        confidenceControl.selectedSegmentIndex = 1
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        sessionInfoLabel.textColor = .white
        sessionInfoLabel.textAlignment = .center
        
        confidenceControl.addTarget(self, action: #selector(viewValueChanged), for: .valueChanged)
        stackView = UIStackView(arrangedSubviews: [confidenceControl, sessionInfoLabel, label])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 10
        view.backgroundColor = .gray
        
        let imgY: CGFloat = 60
        
        imgview.frame = CGRect(x: 0, y: imgY, width: imageSize , height: imageSize )
        imgview.layer.borderColor = UIColor.blue.cgColor
        imgview.layer.borderWidth = 1
        
        arcnSceneView.frame = CGRect(x:view.bounds.width - RGBImageWidth, y: RGBImageMarginY, width: RGBImageWidth, height: RGBImageWidth * 4 / 3)
        arcnSceneView.showsStatistics = true
        
        view.addSubview(scnView)
        view.addSubview(arcnSceneView)
        view.addSubview(stackView)
        view.addSubview(imgview)
        
        let dot = UIView()
        let dotSize = imageSize / 128
        dot.frame = CGRect(x: imageSize * 0.5, y: imageSize * 0.5, width: dotSize, height: dotSize)
        dot.backgroundColor = UIColor.cyan
        dot.layer.cornerRadius = 0
        imgview.addSubview(dot)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50),
        ])
        
        confidenceControl.isHidden = true
        
        bboxes = BoundingBoxes(imgView: imgview)
        CWalker = CWalkerController(session: &arcnSceneView.session, nodeMapManage: nodeMapManager, scale: scale, scaleTracker: scaleTracker, systemMode: systemMode)
        CWalker.gridMap.delegate = self
        CWalker.delegate = self
        
        if self.systemMode == .proposed {
            let directions = nodeMapManager.originalDirections
            let intersectionTypes = nodeMapManager.originalIntersectionTypes
            let routeTracker = routeTrackingManager(nodeMapManager: nodeMapManager, scale: scale, scaleTracker: scaleTracker)
            let routeDescription = feedBackManage.generateRouteDescription(directions: directions, intersectionTypes: intersectionTypes, routeTracker: routeTracker)
            self.TTS.talk(text: routeDescription, language: lang)
        }
        
        vibrationManager = VibrationManager()
        
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arcnSceneView.session.pause()
    }
    
    @objc
    private func viewValueChanged(view: UIView) {
        switch view {
            
        case confidenceControl:
            CWalker.setConfidenceLevel(confidence: confidenceControl.selectedSegmentIndex)
            
        default:
            break
        }
    }
    
    
    private func setupScene() {
        scnView = SCNView()
        scene = SCNScene()
        arcnSceneView = ARSCNView()
        TTS = AVSpeechSynthesizer()
    
        scnView.preferredFramesPerSecond = 10
        scnView.scene = scene
        scnView.allowsCameraControl = false
        scnView.showsStatistics = true
        scnView.backgroundColor = UIColor.gray
        scnView.cameraControlConfiguration.autoSwitchToFreeCamera = false
        
        userPosition = gridPlaneNode(gridIndex: gridIndex(x: 0, y: 0), gridType: .user)
        scene.rootNode.addChildNode(userPosition)
        
        camera.zNear = 0.1
        camera.zFar = 100
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(x: 0, y: cameraHeight, z: 0)
        cameraNode.look(at: userPosition.position)
        scene.rootNode.addChildNode(cameraNode)
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = .sceneDepth
        configuration.planeDetection = [.horizontal, .vertical]
        arcnSceneView.preferredFramesPerSecond = 15
        
        arcnSceneView.session.run(configuration)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        }

    
    func sceneViewUpdate(confirmedIntersections: [intersection]) {
        for node in scene.rootNode.childNodes where node.name == "arrow" || node.name == "intersection" {
            node.removeFromParentNode()
        }
        
        for intersection in confirmedIntersections{
            for (directionString, _) in  intersection.directions {
                let intersectionEdge = gridPlaneNode(gridIndex: intersection.keyPositions[directionString]!, gridType: .arrows, name: "intersection", dy: 0.1)
                scene.rootNode.addChildNode(intersectionEdge)
            }
                        
            let intersectionCenter = gridPlaneNode(gridIndex: intersection.position, gridType: .center, name: "intersection", dy: 0.1)
            scene.rootNode.addChildNode(intersectionCenter)
        }
    }

    func didFinishNavigation(arrivedDestination: String, scale: Float!, scaleTracker: ScaleTracker) {
        CWalker.stopSystem()
        delegate?.didFinishNavigation(arrivedDestination: arrivedDestination, scale: scale, scaleTracker: scaleTracker)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [self] in
            vibrationManager.stopVibration()
            self.navigationController?.popViewController(animated: true)
        }
    }
    
    func didUpdate(gridMapImage: UIImage) {
        imgview.image = gridMapImage
    }
    
    func didUpdateGridMap(node: gridPlaneNode) {
        scene.rootNode.addChildNode(node)
    }
    
    func didUpdate(intersections: [intersection]) {
        sceneViewUpdate(confirmedIntersections: intersections)
    }
    
    func didUpdate(userGridPosition: gridIndex) {
        userPosition.position = SCNVector3(x: Float(userGridPosition.x) * gridMapLength, y: 0.018, z: Float(userGridPosition.y) * gridMapLength)
        cameraNode.look(at: userPosition.position)
        cameraNode.position = SCNVector3(x: Float(userGridPosition.x) * gridMapLength, y: cameraHeight, z: Float(userGridPosition.y) * gridMapLength)
    }
    
    func didUpdate(labelString: String) {
        label.text = labelString
    }
    
    func didUpdate(boundingBoxes: [Prediction], labels: [String]) {
        bboxes.show(predictions: boundingBoxes, labels: labels)
    }

    
    func didUpdateSpeech(fbType: feedbackType, fbInfoCapsule: feedBackInformationCapsule) {
        print("Speak Reason: ",fbType.rawValue)
        let fbString = feedBackManage.generateFeedBackString(fbType: fbType, fbInfoCapsule: fbInfoCapsule)
        TTS.stopSpeaking(at: .immediate)
        TTS.talk(text: fbString, language: lang)
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        CWalker.startSystem()
        
        if systemMode == .baseline {
            TTS.talk(text: "スタート", language: lang)
        }
    }
    
    func didUpdate(sessionInfoString: String) {
        sessionInfoLabel.text = sessionInfoString
    }
    
    func didUpdateSound() {
//        soundPlayer.playSound(named: "fail")
    }
    
    func didUpdateClose(vibrationState: VibrationState) {
        if !useEmergencyVibration { return }
        
        vibrationManager.updateState(vibrationState: vibrationState)
        switch vibrationState {
        case .start:
            vibrationManager.startVibration()
        case .stop:
            vibrationManager.stopVibration()
        }
    }

    
}
