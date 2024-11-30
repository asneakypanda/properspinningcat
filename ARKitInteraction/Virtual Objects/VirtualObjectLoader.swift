/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A type which loads and tracks virtual objects.
*/

import Foundation
import ARKit

/**
 Loads multiple `VirtualObject`s on a background queue to be able to display the
 objects quickly once they are needed.
*/
class VirtualObjectLoader {
    private(set) var loadedObjects = [VirtualObject]()
    
    private(set) var isLoading = false
    
    // MARK: - Loading object

    /**
     Loads a `VirtualObject` on a background queue. `loadedHandler` is invoked
     on a background queue once `object` has been loaded.
    */
    func loadVirtualObject(_ object: VirtualObject, loadedHandler: @escaping (VirtualObject) -> Void) {
        isLoading = true
        loadedObjects.append(object)
        
        // Load the content into the reference node.
        DispatchQueue.global(qos: .userInitiated).async {
            object.load()
            self.isLoading = false
            loadedHandler(object)
        }
    }
    
    func replaceVirtualObject(_ oldObject: VirtualObject, with newObject: VirtualObject, in sceneView: ARSCNView) {
        DispatchQueue.global(qos: .userInitiated).async {
            newObject.load()
            DispatchQueue.main.async {
                print("Replacing \(oldObject.modelName) with \(newObject.modelName).")
                
                // Match position, rotation, and scale
                newObject.position = oldObject.position
                newObject.rotation = oldObject.rotation
                newObject.scale = oldObject.scale
                
                // Remove the old object
                oldObject.removeFromParentNode()
                print("Removed old object from the scene.")
                
                // Add the new object to the scene
                sceneView.scene.rootNode.addChildNode(newObject)
                print("Added new object to the scene.")
                
                // Update the loadedObjects array
                if let index = self.loadedObjects.firstIndex(of: oldObject) {
                    self.loadedObjects[index] = newObject
                    print("Updated loadedObjects array.")
                } else {
                    self.loadedObjects.append(newObject)
                    print("Added new object to loadedObjects.")
                }
            }
        }
    }



    
    
    // MARK: - Removing Objects
    
    func removeAllVirtualObjects() {
        // Reverse the indices so we don't trample over indices as objects are removed.
        for index in loadedObjects.indices.reversed() {
            removeVirtualObject(at: index)
        }
    }

    /// - Tag: RemoveVirtualObject
    func removeVirtualObject(at index: Int) {
        guard loadedObjects.indices.contains(index) else { return }
        
        // Stop the object's tracked ray cast.
        loadedObjects[index].stopTrackedRaycast()
        
        // Remove the visual node from the scene graph.
        loadedObjects[index].removeFromParentNode()
        // Recoup resources allocated by the object.
        loadedObjects[index].unload()
        loadedObjects.remove(at: index)
    }
}
