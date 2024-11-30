/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Manages user interaction with virtual objects to enable one-finger tap, one- and two-finger pan,
 and two-finger rotation gesture recognizers to let the user position and orient virtual objects.
 
 Note: this sample app doesn't allow object scaling because quite often, scaling doesn't make sense
 for certain virtual items. For example, a virtual television can be scaled within some small believable
 range, but a virtual guitar should always remain the same size.
*/

import UIKit
import ARKit
import AVFoundation

/// - Tag: VirtualObjectInteraction
class VirtualObjectInteraction: NSObject, UIGestureRecognizerDelegate {
    
    var spinDuration: CFTimeInterval = 1.0
    var audioRate: Float = 1.0
    
    /// Developer setting to translate assuming the detected plane extends infinitely.
    let translateAssumingInfinitePlane = true
    
    /// The scene view to hit test against when moving virtual content.
    let sceneView: VirtualObjectARView
    
    /// A reference to the view controller.
    let viewController: ViewController
    
    let virtualObjectLoader: VirtualObjectLoader
    
    /**
     The object that has been most recently intereacted with.
     The `selectedObject` can be moved at any time with the tap gesture.
     */
    var selectedObject: VirtualObject?
    
    /// The object that is tracked for use by the pan and rotation gestures.
    var trackedObject: VirtualObject? {
        didSet {
            guard trackedObject != nil else { return }
            selectedObject = trackedObject
        }
    }
    
    private var audioPlayer: AVAudioPlayer?
    
    private lazy var sittingModelURL: URL = {
        guard let url = Bundle.main.url(forResource: "Models.scnassets/oiiaioSitting", withExtension: "scn") else {
            fatalError("Error: Could not find oiiaioSitting.scn in Models.scnassets.")
        }
        return url
    }()
    
    // Initialize the standing model URL as a lazy property
        private lazy var standingModelURL: URL = {
            guard let url = Bundle.main.url(forResource: "Cat", withExtension: "scn", subdirectory: "Models.scnassets") else {
                fatalError("Error: Could not find Cat.scn in Models.scnassets.")
            }
            return url
        }()


    
    /// The tracked screen position used to update the `trackedObject`'s position.
    private var currentTrackingPosition: CGPoint?
    
    init(sceneView: VirtualObjectARView, viewController: ViewController, virtualObjectLoader: VirtualObjectLoader) {
        self.sceneView = sceneView
        self.viewController = viewController
        self.virtualObjectLoader = virtualObjectLoader
        super.init()
        
        // Prepare the audio
        if let audioURL = Bundle.main.url(forResource: "oiiaSound", withExtension: "m4a") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                audioPlayer?.prepareToPlay()
                audioPlayer?.numberOfLoops = -1 // Loop while moving
            } catch {
                print("Error loading audio file: \(error)")
            }
        }
        
        createPanGestureRecognizer(sceneView)
        
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(didRotate(_:)))
        rotationGesture.delegate = self
        sceneView.addGestureRecognizer(rotationGesture)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
    }
    
    // - Tag: CreatePanGesture
    func createPanGestureRecognizer(_ sceneView: VirtualObjectARView) {
        let panGesture = ThresholdPanGesture(target: self, action: #selector(didPan(_:)))
        panGesture.delegate = self
        sceneView.addGestureRecognizer(panGesture)
    }
    
    
    // MARK: - Gesture Actions
    
    @objc
    func didPan(_ gesture: ThresholdPanGesture) {
        switch gesture.state {
        case .began:
            // Check for an object at the touch location.
            if let object = objectInteracting(with: gesture, in: sceneView) {
                print("Pan began on object: \(object.modelName)")
                // Replace the object with the sitting model
                if let sittingModel = VirtualObject(url: sittingModelURL) {
                    print("Creating sitting model for replacement.")
                    sittingModel.load()
                    print("Sitting model loaded.")

                    virtualObjectLoader.replaceVirtualObject(object, with: sittingModel, in: sceneView)
                    print("Replaced object with sitting model.")

                    // Set the tracked object to the new sitting model
                    trackedObject = sittingModel

                    // Start spinning and audio
                    startSpinningAndAudio(for: sittingModel)
                } else {
                    print("Error: Could not create sittingModel")
                    // Fall back to using the original object
                    trackedObject = object
                    startSpinningAndAudio(for: object)
                }
            } else {
                print("No object found at pan gesture location.")
            }

        case .changed where gesture.isThresholdExceeded:
            guard let object = trackedObject else { return }
            // Move the object if the displacement threshold has been met.
            translate(object, basedOn: updatedTrackingPosition(for: object, from: gesture))
            gesture.setTranslation(.zero, in: sceneView)

        case .changed:
            // Ignore the pan gesture until the displacement threshold is exceeded.
            break

        case .ended:
            // Update the object's position when the user stops panning.
            guard let object = trackedObject else { break }
            setDown(object, basedOn: updatedTrackingPosition(for: object, from: gesture))
            stopSpinningAndAudio(for: object) // Stop spinning and audio

            // Replace the sitting cat with the standing cat
            if let standingModel = VirtualObject(url: standingModelURL) {
                print("Creating standing model for replacement.")
                standingModel.load()
                print("Standing model loaded.")

                virtualObjectLoader.replaceVirtualObject(object, with: standingModel, in: sceneView)
                print("Replaced sitting model with standing model.")

                // Update the selected object
                selectedObject = standingModel
            } else {
                print("Error: Could not create standingModel")
            }
            fallthrough

        default:
            // Reset the current position tracking.
            currentTrackingPosition = nil
            trackedObject = nil
        }
    }


    
    func updatedTrackingPosition(for object: VirtualObject, from gesture: UIPanGestureRecognizer) -> CGPoint {
        let translation = gesture.translation(in: sceneView)
        
        let currentPosition = currentTrackingPosition ?? CGPoint(sceneView.projectPoint(object.position))
        let updatedPosition = CGPoint(x: currentPosition.x + translation.x, y: currentPosition.y + translation.y)
        currentTrackingPosition = updatedPosition
        return updatedPosition
    }

    /**
     For looking down on the object (99% of all use cases), you subtract the angle.
     To make rotation also work correctly when looking from below the object one would have to
     flip the sign of the angle depending on whether the object is above or below the camera.
     - Tag: didRotate */
    @objc
    func didRotate(_ gesture: UIRotationGestureRecognizer) {
        guard gesture.state == .changed else { return }
        
        trackedObject?.objectRotation -= Float(gesture.rotation)
        
        gesture.rotation = 0
    }
    
    @objc
    func didTap(_ gesture: UITapGestureRecognizer) {
        let touchLocation = gesture.location(in: sceneView)
        if let tappedObject = sceneView.virtualObject(at: touchLocation) {
            // Select the tapped object
            selectedObject = tappedObject
        } else if let object = selectedObject {
            // Move the selected object to the new position
            setDown(object, basedOn: touchLocation)
        }
    }




    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow objects to be translated and rotated at the same time.
        return true
    }

    /** A helper method to return the first object that is found under the provided `gesture`s touch locations.
     Performs hit tests using the touch locations provided by gesture recognizers. By hit testing against the bounding
     boxes of the virtual objects, this function makes it more likely that a user touch will affect the object even if the
     touch location isn't on a point where the object has visible content. By performing multiple hit tests for multitouch
     gestures, the method makes it more likely that the user touch affects the intended object.
      - Tag: TouchTesting
    */
    private func objectInteracting(with gesture: UIGestureRecognizer, in view: ARSCNView) -> VirtualObject? {
        for index in 0..<gesture.numberOfTouches {
            let touchLocation = gesture.location(ofTouch: index, in: view)
            
            // Look for an object directly under the `touchLocation`.
            if let object = sceneView.virtualObject(at: touchLocation) {
                return object
            }
        }
        
        // As a last resort look for an object under the center of the touches.
        if let center = gesture.center(in: view) {
            return sceneView.virtualObject(at: center)
        }
        
        return nil
    }
    
    // MARK: - Update object position
    /// - Tag: DragVirtualObject
    func translate(_ object: VirtualObject, basedOn screenPos: CGPoint) {
        object.stopTrackedRaycast()
        
        // Update the object by using a one-time position request.
        if let query = sceneView.raycastQuery(from: screenPos, allowing: .estimatedPlane, alignment: object.allowedAlignment) {
            viewController.createRaycastAndUpdate3DPosition(of: object, from: query)
        }
    }
    
    func setDown(_ object: VirtualObject, basedOn screenPos: CGPoint) {
        object.stopTrackedRaycast()
        
        // Prepare to update the object's anchor to the current location.
        object.shouldUpdateAnchor = true
        
        // Attempt to create a new tracked raycast from the current location.
        if let query = sceneView.raycastQuery(from: screenPos, allowing: .estimatedPlane, alignment: object.allowedAlignment),
            let raycast = viewController.createTrackedRaycastAndSet3DPosition(of: object, from: query) {
            object.raycast = raycast
        } else {
            // If the tracked raycast did not succeed, simply update the anchor to the object's current position.
            object.shouldUpdateAnchor = false
            viewController.updateQueue.async {
                self.sceneView.addOrUpdateAnchor(for: object)
            }
        }
    }
    
    func startSpinningAndAudio(for object: VirtualObject) {
        // Reset audio playback to the beginning
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        audioPlayer?.enableRate = true
        audioPlayer?.rate = audioRate // Use the audioRate property
        audioPlayer?.play()

        // Apply a rotation animation to the object
        let spinAnimation = CABasicAnimation(keyPath: "rotation")
        spinAnimation.fromValue = SCNVector4(0, 1, 0, 0)
        spinAnimation.toValue = SCNVector4(0, 1, 0, Float.pi * 2)
        spinAnimation.duration = spinDuration // Use the adjusted spinDuration
        spinAnimation.repeatCount = .infinity
        object.addAnimation(spinAnimation, forKey: "spin")
    }




    func stopSpinningAndAudio(for object: VirtualObject) {
        // Remove the spin animation
        object.removeAnimation(forKey: "spin", blendOutDuration: 0)
        
        // Stop audio
        audioPlayer?.stop()
    }
}

/// Extends `UIGestureRecognizer` to provide the center point resulting from multiple touches.
extension UIGestureRecognizer {
    func center(in view: UIView) -> CGPoint? {
        guard numberOfTouches > 0 else { return nil }
        
        let first = CGRect(origin: location(ofTouch: 0, in: view), size: .zero)

        let touchBounds = (1..<numberOfTouches).reduce(first) { touchBounds, index in
            return touchBounds.union(CGRect(origin: location(ofTouch: index, in: view), size: .zero))
        }

        return CGPoint(x: touchBounds.midX, y: touchBounds.midY)
    }
}
