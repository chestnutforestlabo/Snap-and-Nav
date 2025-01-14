//
//  ViewController.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/06/03.
//
import UIKit
import AVFAudio
import ReplayKit

enum ServerFunction: String {
    case detect = "/detect"
    case modify = "/modify"
}

class ViewController: UIViewController, UIImagePickerControllerDelegate, AVSpeechSynthesizerDelegate, UIPickerViewDelegate, UIPickerViewDataSource, UINavigationControllerDelegate, RPPreviewViewControllerDelegate, CWalkerViewControllerDelegate, MapEditorViewDelegate {
    
    let multipeerHandler = MultipeerHandler()
    
    var currentLocationPickerView: UIPickerView!
    var destinationPickerView: UIPickerView!
    var capturedImage: UIImage!
    
    var currentLocationLabel: UILabel = {
        let label = UILabel()
        label.text = lang == .en ? "Location" : "現在地"
        label.font = UIFont.systemFont(ofSize: 20, weight: .semibold) // Set the font and size
        label.isUserInteractionEnabled = true
        return label
    }()
    
    var destinationLabel: UILabel = {
        let label = UILabel()
        label.text = lang == .en ? "Destination" : "目的地"
        label.font = UIFont.systemFont(ofSize: 20, weight: .semibold) // Set the font and size
        label.isUserInteractionEnabled = true
        return label
    }()
    
    var locationList: [String] = []
    
    let imageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        return iv
    }()
    
    let imagePickerController = UIImagePickerController()
    let nodeMapManage = nodeMapManager()
    var C_WalkerViewController: CWalkerViewController!
    var mapEditorViewController: MapEditorViewController!
    var TTS: AVSpeechSynthesizer!
    var scaleTracker: ScaleTracker = ScaleTracker()
    
    lazy var nextButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(lang == .en ? "Start\nNavi" : "案内\n開始", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold) // Set the font and size
        button.setTitleColor(.white, for: .normal) // Set the text color
        button.backgroundColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0) // Set the gray-ish background color
        button.layer.cornerRadius = 16 // Round the button corners for a nice look
        button.addTarget(self, action: #selector(goToC_WalkerController), for: .touchUpInside)
        
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        
        // Adjust button's frame to make it bigger
        let buttonWidth: CGFloat = 100
        let buttonHeight: CGFloat = 70
        button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
        
        return button
    }()
    
    lazy var captureButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(lang == .en ? "Capture\nMap" : "フロアマップ\n撮影", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold) // Set the font and size
        button.setTitleColor(.white, for: .normal) // Set the text color
        button.backgroundColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0) // Set the gray-ish background color
        button.layer.cornerRadius = 16 // Round the button corners for a nice look
        button.addTarget(self, action: #selector(captureImage), for: .touchUpInside)
        
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        
        // Adjust button's frame to make it bigger
        let buttonWidth: CGFloat = 100
        let buttonHeight: CGFloat = 70
        button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
        
        return button
    }()
    
    lazy var editButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(lang == .en ? "Edit\nMap" : "向いてる方向\n修正", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold) // Set the font and size
        button.setTitleColor(.white, for: .normal) // Set the text color
        button.backgroundColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0) // Set the gray-ish background color
        button.layer.cornerRadius = 16 // Round the button corners for a nice look
        button.addTarget(self, action: #selector(goToMapEditor), for: .touchUpInside)
        
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        
        // Adjust button's frame to make it bigger
        let buttonWidth: CGFloat = 100
        let buttonHeight: CGFloat = 70
        button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
        
        return button
    }()
    
    
    let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = lang == .en ? "Please capture floor map image" :  "フロアマップの写真を撮影してください"
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        label.isUserInteractionEnabled = true
        return label
    }()
        
    let systemModeSwitch: UISegmentedControl = {
        let items = ["test", "121-5-1", "121-5-3"]
        let segmentedControl = UISegmentedControl(items: items)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        return segmentedControl
    }()
    
    var systemMode: SystemMode = .proposed
    
    var scale: Float? = nil
    
    let margin: CGFloat = 10
    
    let recordIndicator: UIView = {
        let uiView = UIView()
        uiView.backgroundColor = UIColor.red // Sets the background color to red.
        uiView.frame = CGRect(x: 0, y: 0, width: 10, height: 10) // Sets the size of the view.
        uiView.layer.cornerRadius = uiView.frame.size.width / 2 // Makes the view circular.
        uiView.clipsToBounds = true // Ensures the corners don't overflow.
        return uiView
    }()
    
    var timeStart = Date()
    var activityIndicator: UIActivityIndicatorView = UIActivityIndicatorView()
    var loadingView = UIView()
    
    var processStateTimerScreen: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        clearCache()
        
        if useMultiPeer {
            multipeerHandler.startHostingOrBrowsing(host: true)
            self.processStateTimerScreen = Timer.scheduledTimer(timeInterval: 2.5, target: self, selector: #selector(self.procesMultipeerLog), userInfo: nil, repeats: true)
        }
        AppUtility.lockOrientation(.portrait)
        AVSpeechSynthesisVoice.speechVoices()
        TTS = AVSpeechSynthesizer()
        TTS.delegate = self
        
        loadingView = UIView(frame: UIScreen.main.bounds)
        loadingView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        loadingView.isHidden = true
        
        activityIndicator = UIActivityIndicatorView()
        activityIndicator.frame = CGRect(x: 0, y: 0, width: 150, height: 150)
        activityIndicator.center = view.center
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = UIColor.white
        activityIndicator.style = UIActivityIndicatorView.Style.large
        
        currentLocationPickerView = createPickerView()
        destinationPickerView = createPickerView()
        
        currentLocationPickerView.tag = 1
        destinationPickerView.tag = 2
        
        currentLocationPickerView.dataSource = self
        currentLocationPickerView.delegate = self
        
        destinationPickerView.dataSource = self
        destinationPickerView.delegate = self
        
        imagePickerController.delegate = self
        
        view.addSubview(imageView)
        view.addSubview(nextButton)
        view.addSubview(captureButton)
        if testMode {
            view.addSubview(editButton)
        }
        view.addSubview(label)
        view.addSubview(currentLocationLabel)
        view.addSubview(currentLocationPickerView)
        view.addSubview(destinationLabel)
        view.addSubview(destinationPickerView)
        view.addSubview(systemModeSwitch)
        view.addSubview(loadingView)
        view.addSubview(activityIndicator)
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(labelTapped))
        label.addGestureRecognizer(tapRecognizer)
        
        let currentLocationLabelTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(currentLocationLabelTapped))
        currentLocationLabel.addGestureRecognizer(currentLocationLabelTapRecognizer)
        
        let destinationLabelTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(destinationLabelTapped))
        destinationLabel.addGestureRecognizer(destinationLabelTapRecognizer)
        
        if testMode {
            getDefaultMap()
        } else {
            nextButton.isEnabled = false
            editButton.isEnabled = false
            nextButton.isHidden = true
            editButton.isHidden = true
        }
        
        // Set accessibility features for the picker views
        currentLocationPickerView.isAccessibilityElement = true
        currentLocationPickerView.accessibilityTraits = .adjustable
        currentLocationPickerView.accessibilityLabel = "Current Location Picker"
        
        destinationPickerView.isAccessibilityElement = true
        destinationPickerView.accessibilityTraits = .adjustable
        destinationPickerView.accessibilityLabel = "Desitionaion Picker"
        
        label.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        currentLocationLabel.translatesAutoresizingMaskIntoConstraints = false
        currentLocationPickerView.translatesAutoresizingMaskIntoConstraints = false
        destinationLabel.translatesAutoresizingMaskIntoConstraints = false
        destinationPickerView.translatesAutoresizingMaskIntoConstraints = false
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        systemModeSwitch.translatesAutoresizingMaskIntoConstraints = false

        if testMode {
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: view.topAnchor, constant: 100),
                
                imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                imageView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 25),
                imageView.widthAnchor.constraint(equalTo: view.widthAnchor),
                imageView.heightAnchor.constraint(equalToConstant: 380),
                
                currentLocationLabel.trailingAnchor.constraint(equalTo: currentLocationPickerView.centerXAnchor, constant: 25),
                currentLocationLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),

                currentLocationPickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                currentLocationPickerView.topAnchor.constraint(equalTo: currentLocationLabel.bottomAnchor, constant: 10),
                currentLocationPickerView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),
                currentLocationPickerView.heightAnchor.constraint(equalToConstant: 150),
                
                destinationLabel.centerXAnchor.constraint(equalTo: destinationPickerView.centerXAnchor),
                destinationLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),

                destinationPickerView.leadingAnchor.constraint(equalTo: view.centerXAnchor),
                destinationPickerView.topAnchor.constraint(equalTo: destinationLabel.bottomAnchor, constant: 10),
                destinationPickerView.widthAnchor.constraint(equalTo: currentLocationPickerView.widthAnchor),
                destinationPickerView.heightAnchor.constraint(equalTo: currentLocationPickerView.heightAnchor),
                
                // Next Button constraints
                nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                nextButton.topAnchor.constraint(equalTo: destinationPickerView.bottomAnchor, constant: 30),

                // Capture Button constraints
                captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                captureButton.topAnchor.constraint(equalTo: destinationPickerView.bottomAnchor, constant: 30),

                // Edit Button constraints
                editButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                editButton.topAnchor.constraint(equalTo: destinationPickerView.bottomAnchor, constant: 30),

                // Make all three buttons equal widths
                nextButton.widthAnchor.constraint(equalTo: captureButton.widthAnchor),
                captureButton.widthAnchor.constraint(equalTo: editButton.widthAnchor),
                
                // I want to add systemModeSwitch under capture button
                // Add constraints here
                systemModeSwitch.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                systemModeSwitch.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: 5),
                // If you want to set a specific width and height you can do so like this:
                systemModeSwitch.widthAnchor.constraint(equalToConstant: 100), // Or any other width
                systemModeSwitch.heightAnchor.constraint(equalToConstant: 50), // Or any other height
            ])
        } else {
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: view.topAnchor, constant: 100),
                
                imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                imageView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 25),
                imageView.widthAnchor.constraint(equalTo: view.widthAnchor),
                imageView.heightAnchor.constraint(equalToConstant: 380),
                
                currentLocationLabel.trailingAnchor.constraint(equalTo: currentLocationPickerView.centerXAnchor),
                currentLocationLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),

                currentLocationPickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                currentLocationPickerView.topAnchor.constraint(equalTo: currentLocationLabel.bottomAnchor, constant: 10),
                currentLocationPickerView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),
                currentLocationPickerView.heightAnchor.constraint(equalToConstant: 150),
                
                destinationLabel.centerXAnchor.constraint(equalTo: destinationPickerView.centerXAnchor),
                destinationLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),

                destinationPickerView.leadingAnchor.constraint(equalTo: view.centerXAnchor),
                destinationPickerView.topAnchor.constraint(equalTo: destinationLabel.bottomAnchor, constant: 10),
                destinationPickerView.widthAnchor.constraint(equalTo: currentLocationPickerView.widthAnchor),
                destinationPickerView.heightAnchor.constraint(equalTo: currentLocationPickerView.heightAnchor),
                
                // Next Button constraints
                nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                nextButton.topAnchor.constraint(equalTo: destinationPickerView.bottomAnchor, constant: 30),
                nextButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),

                // Capture Button constraints
                captureButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor),
                captureButton.topAnchor.constraint(equalTo: destinationPickerView.bottomAnchor, constant: 30),
                captureButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),

                // Both buttons should have the same height. Use either one's height.
                nextButton.heightAnchor.constraint(equalTo: captureButton.heightAnchor),
                
                // I want to add systemModeSwitch under capture button
                // Add constraints here
                systemModeSwitch.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                systemModeSwitch.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: 5),
                // If you want to set a specific width and height you can do so like this:
                systemModeSwitch.widthAnchor.constraint(equalToConstant: 100), // Or any other width
                systemModeSwitch.heightAnchor.constraint(equalToConstant: 50), // Or any other height
            ])
        }
        
        systemModeSwitch.isHidden = true
        
        if !RPScreenRecorder.shared().isRecording {
            RPScreenRecorder.shared().startRecording { [self] (error) in
                if let error = error {
                    print("Failed to start recording: \(error)")
                } else {
                    print("Started recording!")
                    let padding: CGFloat = 10
                    let xPosition = view.frame.width - recordIndicator.frame.width - padding
                    let yPosition = padding
                    recordIndicator.frame.origin = CGPoint(x: xPosition, y: yPosition)
                    view.addSubview(recordIndicator)
                    TTS.talk(text: "録画開始", language: .jp)
                    timeStart = Date()
                }
            }
        }
    }
    
    func clearCache() {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil, options: [])
            for fileURL in contents {
                try FileManager.default.removeItem(at: fileURL)
            }
            print("Cache is cleared!")
        } catch {
            print("Failed to clear cache: \(error)")
        }
    }

    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
    }
    
    @objc func procesMultipeerLog() {
        DispatchQueue.main.async { [self] in
            let currentDate = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeString = formatter.string(from: currentDate)
            multipeerHandler.sendText(timeString)  // Once connected
            if let image = captureScreen() {
                multipeerHandler.sendImage(image)
            }
        }
    }
    
    func getDefaultMap(defaultMapName: String = defaultMapName) {
        nodeMapManage.readDefaultNodeMap(defaultName: defaultMapName)
        let image = UIImage(named: defaultMapName)
        capturedImage = UIImage(named: defaultMapName + "-captured")
        locationList = nodeMapManage.poiIDs
        
        imageView.image = image
        
        let initialLocation = "511"
        let destination = "501"
        if let defaultValueIndex1 = locationList.firstIndex(of: initialLocation),
            let defaultValueIndex2 = locationList.firstIndex(of: destination){
            currentLocationPickerView.selectRow(defaultValueIndex1, inComponent: 0, animated: false)
            nodeMapManage.selectedCurrentLocation = initialLocation
            
            destinationPickerView.selectRow(defaultValueIndex2, inComponent: 0, animated: false)
            nodeMapManage.selectedDestination = destination
        }
    }

    
    @objc
    func captureImage() {
        TTS.talk(text: "スマートフォンを横方向に持って、フロアマップを綺麗に撮影してください。光の反射がないように撮影してください。", language: .jp)
        imagePickerController.sourceType = .camera
        imagePickerController.view.layoutIfNeeded()
        present(imagePickerController, animated: true, completion: nil)
//        label.text = lang == .en ? "Please wait...." : "少々お待ちください...."
    }
    
    @objc
    func goToC_WalkerController() {
        if nodeMapManage.selectedDestination == nodeMapManage.selectedCurrentLocation {
            label.text = lang == .en ? "Please select another location" : "別の場所を選んでください"
            return
        }
        
        C_WalkerViewController = CWalkerViewController()
        C_WalkerViewController.nodeMapManager = nodeMapManage
        C_WalkerViewController.scale = self.scale
        C_WalkerViewController.systemMode = self.systemMode
        C_WalkerViewController.delegate = self
        C_WalkerViewController.scaleTracker = self.scaleTracker
        navigationController?.pushViewController(C_WalkerViewController, animated: true)
    }

    @objc
    func goToMapEditor() {
        mapEditorViewController = MapEditorViewController()
        mapEditorViewController.nodeMapManager = nodeMapManage
        mapEditorViewController.capturedImage = capturedImage
        mapEditorViewController.serverFunction = .detect
        mapEditorViewController.delegate = self
        
        navigationController?.pushViewController(mapEditorViewController, animated: true)
    }
    
    @objc
    func goToMapEditorForModifyLocation() {
        mapEditorViewController = MapEditorViewController()
        mapEditorViewController.nodeMapManager = nodeMapManage
        mapEditorViewController.capturedImage = capturedImage
        mapEditorViewController.serverFunction = .modify
        mapEditorViewController.delegate = self
        
        navigationController?.pushViewController(mapEditorViewController, animated: true)
    }
    
    @objc
    func switchChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            getDefaultMap(defaultMapName: testMapName)
        case 1:
            getDefaultMap(defaultMapName: taskMapName1)
        case 2:
            getDefaultMap(defaultMapName: taskMapName2)
        default:
            break
        }
        view.layoutIfNeeded()
        currentLocationPickerView.reloadAllComponents()
        destinationPickerView.reloadAllComponents()
    }
    
    private func uploadMap(intersectionJSON: Data, poiJSON: Data, initialJSON: Data, urlString: String, serverFunction: ServerFunction) {
        
        let url = URL(string: urlString + serverFunction.rawValue)
        let boundary = UUID().uuidString
        let session = URLSession.shared
        
        var urlRequest = URLRequest(url: url!)
        urlRequest.httpMethod = "POST"
        
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var data = Data()
        
        let paramNameImage = "image"
        let fileNameImage = "test.JPG"
        
        // Add the image data to the raw http request data
        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(paramNameImage)\"; filename=\"\(fileNameImage)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: image/jpg\r\n\r\n".data(using: .utf8)!)
        data.append(capturedImage.jpegData(compressionQuality: 1.0)!)

        
        // Add JSON data to the raw http request data
        for (paramName, json) in [("map", intersectionJSON),
                                  ("poi_nodes", poiJSON),
                                  ("initial_node", initialJSON)] {
            data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"\(paramName)\"; filename=\"\(paramName + ".json")\"\r\n".data(using: .utf8)!)
            data.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            data.append(json)
        }
        
        // Append the current date and time to the data
        let dateFormatter = ISO8601DateFormatter()
        let currentDateString = dateFormatter.string(from: Date())
        
        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"currentTime\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
        data.append(currentDateString.data(using: .utf8)!)
        
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Send a POST request to the URL, with the data we created earlier
        NSLog("Uploading JSON....")
        label.text = lang == .en ? "Please wait...." : "画像を処理中...少々お待ちください"
        TTS.talk(text: "地図の認識をしてます。少々お待ちください。", language: .jp)
        session.uploadTask(with: urlRequest, from: data, completionHandler: { [self] responseData, response, error in
            NSLog("session.uploadTask")
            DispatchQueue.main.async {
                loadingView.isHidden = true
                activityIndicator.stopAnimating()
            }
            if error == nil {
                let flaskResponse = try! JSONDecoder().decode(FlaskResponse.self, from: responseData!)
                if let mapData = flaskResponse.mapData,
                   let image = flaskResponse.image {
                    nodeMapManage.updateNodeMap(mapData: mapData)
                    if let imageData = Data(base64Encoded: image) {
                        if let image = UIImage(data: imageData) {
                            // Use the image here
                            DispatchQueue.main.async { [self] in
                                // Update UI with the received image
                                imageView.image = image
                            }
                        }
                    }
                    
                    DispatchQueue.main.async { [self] in
                        label.text = lang == .en ? "Please hand back the \nsmartphone to the blind user." : "認識結果を受信しました。\nこの地図で良い場合、ユーザにスマートフォンを返してください。"
                        TTS.talk(text: "認識結果を受信しました。この地図で良い場合、ユーザにスマートフォンを返してください。\n再度撮影する必要がある場合は右側の撮影ボタンを押してください。", language: .jp)
                        captureButton.isEnabled = true
                        captureButton.setTitle("フロアマップ\n撮影", for: .normal)
                        locationList = nodeMapManage.poiIDs
                        currentLocationPickerView.reloadAllComponents()
                        destinationPickerView.reloadAllComponents()
                        nextButton.isHidden = false
                        nextButton.isEnabled = true
                        
                        if let time = flaskResponse.time {
                            let dateFormatter = ISO8601DateFormatter()
                            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            let time = flaskResponse.time!
                            if let serverDate = dateFormatter.date(from: time) {
                                
                                let currentDate = Date()
                                let difference = currentDate.timeIntervalSince(serverDate)
                                
                                uploadTime(fileName: flaskResponse.savePath!, responseTime: String(difference))
                            }
                        }
                        
                    }
                    
                } else {
                    DispatchQueue.main.async { [self] in
                        label.text = lang == .en ? "Failed to \nrecognize map." : "地図認識に失敗しました。\n再度撮影してください。"
                        TTS.talk(text: "地図認識に失敗しました。再度撮影してください。", language: .jp)
                        captureButton.isEnabled = true
                        captureButton.setTitle("フロアマップ\n撮影", for: .normal)
                    }
                }
                
            } else {
                DispatchQueue.main.async {
                    self.label.text = "実験者に確認をしてください"
                    TTS.talk(text: "実験者に確認をしてください", language: .jp)
                }
                print(error!)
            }
                
        }).resume()
    }
    
    private func uploadTime(fileName: String, responseTime: String) {
        
        let url = URL(string: urlString + "/time")
        let boundary = UUID().uuidString
        let session = URLSession.shared
        
        var urlRequest = URLRequest(url: url!)
        urlRequest.httpMethod = "POST"
        
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var data = Data()
        
        // Append the responseTime to the data
        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"time\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
        data.append(responseTime.data(using: .utf8)!)
        data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)  // Move this boundary to here
        
        // Append the fileName to the data
        data.append("Content-Disposition: form-data; name=\"name\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: text/plain\r\n\r\n".data(using: .utf8)!)
        data.append(fileName.data(using: .utf8)!)
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)  // This is the final ending boundary
        
        let task = session.uploadTask(with: urlRequest, from: data) { (data, response, error) in
            if let error = error {
                print("Upload error: \(error)")
            } else if let data = data, let responseString = String(data: data, encoding: .utf8) {
                print("Server response: \(responseString)")
            }
        }
        task.resume()

    }

    
    func didFinishEditingMap(intersectionJSON: Data, poiJSON: Data, initialJSON: Data, modifiedMapData: [String: [Node]], serverFunction: ServerFunction) {
        loadingView.isHidden = false
        activityIndicator.startAnimating()
        uploadMap(intersectionJSON: intersectionJSON, poiJSON: poiJSON, initialJSON: initialJSON, urlString: urlString, serverFunction: serverFunction)
        
        if let indexModifiedMapData = modifiedMapData["nodes"]!.firstIndex(where: { $0.nodeClass == "initial" }),
            let mapData = nodeMapManage.mapData["nodes"]{
            
            let id = mapData.firstIndex(where: { $0.nodeClass == "initial" })!
            nodeMapManage.mapData["nodes"]![id].originalX = modifiedMapData["nodes"]![indexModifiedMapData].originalX
            nodeMapManage.mapData["nodes"]![id].originalY = modifiedMapData["nodes"]![indexModifiedMapData].originalY
            
            nodeMapManage.mapData["nodes"]![id].directionX = modifiedMapData["nodes"]![indexModifiedMapData].directionX
            nodeMapManage.mapData["nodes"]![id].directionY = modifiedMapData["nodes"]![indexModifiedMapData].directionY
        }
    }
    
    func speakFromMapEditor(speechText: String) {
        self.TTS.talk(text: speechText, language: .jp)
    }

    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
            imageView.image = image
            capturedImage = image
            goToMapEditor()
        }
        
        picker.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
    // MARK: - UIPickerViewDataSource
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1 // Assuming one column (component) in the picker view
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return locationList.count
    }
    
    // MARK: - UIPickerViewDelegate
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return locationList[row]
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        // Handle the selected option based on the pickerView.tag
        if locationList.count == 0 { return }
        let selectedOption = locationList[row]
        if pickerView.tag == 1 {
            nodeMapManage.selectedCurrentLocation = selectedOption
        } else if pickerView.tag == 2 {
            nodeMapManage.selectedDestination = selectedOption
        }
    }
    
    // MARK: - Helper Methods
    
    func createPickerView() -> UIPickerView {
        let pickerView = UIPickerView()
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        return pickerView
    }
    
    // MARK: - CWalkerViewControllerDelegate
    
    func didFinishNavigation(arrivedDestination: String, scale: Float!, scaleTracker: ScaleTracker) {
        self.scale = scale
        currentLocationPickerView.isUserInteractionEnabled = false
        let defaultValueIndex = locationList.firstIndex(of: arrivedDestination)
        currentLocationPickerView.selectRow(defaultValueIndex!, inComponent: 0, animated: false)
        nodeMapManage.selectedCurrentLocation = arrivedDestination
    }
    
    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        dismiss(animated: true)
        TTS.talk(text: "録画終了", language: .jp)
    }
    
    @objc func destinationLabelTapped(_ recognizer: UITapGestureRecognizer) {
        goToMapEditorForModifyLocation()
    }
    
    @objc func labelTapped(_ recognizer: UITapGestureRecognizer) {
        print("Label tapped!")
        if RPScreenRecorder.shared().isRecording {
            let timeFinish = Date()
            let taskCompletionTime = timeFinish.timeIntervalSince(timeStart)
            label.text = String(format: "Time was %.2f s", taskCompletionTime)
            RPScreenRecorder.shared().stopRecording { (previewViewController, error) in
                if let error = error {
                    print("Failed to stop recording: \(error)")
                } else if let previewViewController = previewViewController {
                    previewViewController.previewControllerDelegate = self
                    self.present(previewViewController, animated: true, completion: nil)
                    self.recordIndicator.removeFromSuperview()
                    
                }
            }
        } else {
            RPScreenRecorder.shared().startRecording { [self] (error) in
                if let error = error {
                    print("Failed to start recording: \(error)")
                } else {
                    print("Started recording!")
                    let padding: CGFloat = 10
                    let xPosition = view.frame.width - recordIndicator.frame.width - padding
                    let yPosition = padding
                    recordIndicator.frame.origin = CGPoint(x: xPosition, y: yPosition)
                    view.addSubview(recordIndicator)
                    TTS.talk(text: "録画開始", language: .jp)
                    timeStart = Date()
                }
            }
        }

    }
    
    @objc func currentLocationLabelTapped(_ recognizer: UITapGestureRecognizer) {
        systemModeSwitch.isHidden = !systemModeSwitch.isHidden
        currentLocationPickerView.isUserInteractionEnabled = !currentLocationPickerView.isUserInteractionEnabled
    }

    func interruptSpeech() {
        TTS.stopSpeaking(at: .immediate)
    }


}
