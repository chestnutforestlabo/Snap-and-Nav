//
//  vibrationManager.swift
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2023/08/13.
//

import Foundation
import AudioToolbox
import CoreHaptics

class VibrationManager {
    private var engine: CHHapticEngine!
    private var continuousPlayer: CHHapticAdvancedPatternPlayer!
    private var engineNeedsStart = true
    private let intensity: Float = 1.00
    private let sharpness: Float = 0.15
    
    private var consequtiveStartRequestCount: Int = 0
    private let consequtiveStartRequestCountThresh: Int = 10
    
    init() {
        createAndStartHapticEngine()
        createContinuousHapticPlayer()
    }
    
    func updateState(vibrationState: VibrationState) {
        if vibrationState == .start {
            consequtiveStartRequestCount += 1
        } else {
            consequtiveStartRequestCount = 0
        }
    }
    
    func startVibration() {
        if !(consequtiveStartRequestCount > consequtiveStartRequestCountThresh) { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("Device doesn't support advanced haptics")
            return
        }
        
        let intensityParameter = CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                          value: intensity,
                                                          relativeTime: 0)
        
        let sharpnessParameter = CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                                          value: sharpness,
                                                          relativeTime: 0)
        
        // Send dynamic parameters to the haptic player.
        do {
            try continuousPlayer.sendParameters([intensityParameter, sharpnessParameter],
                                                atTime: 0)
        } catch let error {
            print("Dynamic Parameter Error: \(error)")
        }
        
        do {
            // Begin playing continuous pattern.
            try continuousPlayer.start(atTime: CHHapticTimeImmediate)
        } catch let error {
            print("Error starting the continuous haptic player: \(error)")
        }
    }
    
    func stopVibration() {
        do {
            try continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
        } catch let error {
            print("Error stopping the haptic pattern: \(error.localizedDescription)")
        }
    }

    
    func createContinuousHapticPlayer() {
        // Create an intensity parameter:
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity,
                                               value: intensity)
        
        // Create a sharpness parameter:
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness,
                                               value: sharpness)
        
        // Create a continuous event with a long duration from the parameters.
        let continuousEvent = CHHapticEvent(eventType: .hapticContinuous,
                                            parameters: [intensity, sharpness],
                                            relativeTime: 0,
                                            duration: 100)
        
        do {
            // Create a pattern from the continuous haptic event.
            let pattern = try CHHapticPattern(events: [continuousEvent], parameters: [])
            
            // Create a player from the continuous haptic pattern.
            continuousPlayer = try engine!.makeAdvancedPlayer(with: pattern)
            
        } catch let error {
            print("Pattern Player Creation Error: \(error)")
        }
        
    }
    
    func createAndStartHapticEngine() {
        
        // Create and configure a haptic engine.
        do {
            if engine == nil {
                engine = try CHHapticEngine()

                // Mute audio to reduce latency for collision haptics.
                engine.playsHapticsOnly = true

                // The stopped handler alerts you of engine stoppage.
                engine.stoppedHandler = { reason in
                    print("Stop Handler: The engine stopped for reason: \(reason.rawValue)")

                    // set flag for restart
                    self.engineNeedsStart = true


                    switch reason {
                    case .audioSessionInterrupt:
                        print("Audio session interrupt")
                    case .applicationSuspended:
                        print("Application suspended")
                    case .idleTimeout:
                        print("Idle timeout")
                    case .systemError:
                        print("System error")
                    case .notifyWhenFinished:
                        print("Playback finished")
                    case .gameControllerDisconnect:
                        print("Controller disconnected.")
                    case .engineDestroyed:
                        print("Engine destroyed.")
                    @unknown default:
                        print("Unknown error")
                    }
                }

                // The reset handler provides an opportunity to restart the engine.
                engine.resetHandler = {

                    print("Reset Handler: Restarting the engine.")

                    do {
                        // Try restarting the engine.
                        try self.engine.start()

                        // Indicate that the next time the app requires a haptic, the app doesn't need to call engine.start().
                        self.engineNeedsStart = false

                        // Recreate the continuous player.
                        self.createContinuousHapticPlayer()

                    } catch {
                        print("Failed to start the engine")
                    }
                }
            }
        } catch let error {
            fatalError("Engine Creation Error: \(error)")
        }

        // Start the haptic engine for the first time.
        do {
            if engineNeedsStart {
                print("Start engine")
                try self.engine.start()
                engineNeedsStart = false
            }
        } catch {
            print("Failed to start the engine: \(error)")
        }
    }
}
