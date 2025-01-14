//
//  multipeer.swift
//  multipeer
//
//  Created by Masaki Kuribayashi on 2023/08/14.
//

import Foundation
import MultipeerConnectivity
protocol peerDelegate: AnyObject {
    func didReceiveText(label: String)
    func didReceiveImage(image: UIImage) // New method to handle received images
    func didConnect()
}

class MultipeerHandler: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {

    // MARK: Properties
    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    weak var delegate: peerDelegate?
    
    private let serviceType = "serviceType1"
    
    override init() {
        super.init()
        
        peerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
    }
    
    func startHostingOrBrowsing(host: Bool) {
        if host {
            startHosting()
        } else {
            startBrowsing()
        }
    }
    
    // MARK: Public methods
    func startHosting() {
        advertiser.startAdvertisingPeer()
    }
    
    func startBrowsing() {
        browser.startBrowsingForPeers()
    }
    
    func sendText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        if session.connectedPeers.count > 0 {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                print("Error sending data: \(error.localizedDescription)")
            }
        } else {
            print("No peers to send data to")
        }
    }
    
    func sendImage(_ image: UIImage) {
        // Convert image to Data
        guard let imageData = image.jpegData(compressionQuality: 0.5) else {
            print("Error converting image to data.")
            return
        }
        
        // Send Data
        if session.connectedPeers.count > 0 {
            do {
                try session.send(imageData, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                print("Error sending image data: \(error.localizedDescription)")
            }
        } else {
            print("No peers to send image to")
        }
    }
    
    // MARK: MCSessionDelegate methods
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            print("Connected to \(peerID.displayName)")
            // You can also update the UI or perform other actions here.
            delegate?.didConnect()
        case .connecting:
            print("Connecting to \(peerID.displayName)")
        case .notConnected:
            print("Not connected to \(peerID.displayName)")
            // You can also handle disconnections or errors here.
        @unknown default:
            print("Unknown state received for \(peerID.displayName)")
        }
    }

    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Try to interpret the data as text
        if let text = String(data: data, encoding: .utf8) {
            print("Received text: \(text)")
            delegate?.didReceiveText(label: text)
        }
        // Try to interpret the data as an image
        else if let image = UIImage(data: data) {
            print("Received an image.")
            // Handle the received image (you might want to add a new delegate method)
            delegate?.didReceiveImage(image: image) // Note: you'd have to declare this in your delegate protocol
        }
        else {
            print("Unknown data received.")
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    
    // MARK: MCNearbyServiceAdvertiserDelegate methods
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Accept the invitation
        invitationHandler(true, session)
    }
    
    // MARK: MCNearbyServiceBrowserDelegate methods
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Invite the found peer to the session
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Handle the lost peer
    }
    
}

func captureScreen() -> UIImage? {
    guard let window = UIApplication.shared.keyWindow else {
        return nil
    }
    
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, false, 0.0)
    window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return image
}
