//
//  UndoTracking.swift
//  The Stratum Module
//
//  Created by Vaida on 2024/2/2.
//  Copyright © 2019 - 2024 Vaida. All rights reserved.
//

import Foundation
import SwiftUI


/// A protocol providing methods for dealing with undos.
///
/// This protocol does not have any requirement other than being a `class`. However, this protocol provides methods such as ``append(_:to:undoManager:)``.
///
/// > Example:
/// > Start by declaring a class that conforms to this protocol
/// >
/// > ```swift
/// > final class Model: UndoTracking {
/// >     var container: [Double]
/// > }
/// > ```
/// >
/// > When making modifications, use one of the methods this protocol provide to support Undo / Redo.
/// > ```
/// > let model = Model()
/// > model.append(0, to \.container)
/// > ```
public protocol UndoTracking: AnyObject {
    
}

extension UndoTracking {
    
    /// Adds a new element at the end of the array.
    ///
    /// Use this method to append a single element to the end of a mutable array, with the `UndoManager` tracking the changes.
    ///
    /// - Parameters:
    ///   - newElement: The element to append to the array.
    ///   - keyPath: The key path to the array.
    ///   - undoManager: The `UndoManager` tracking the changes.
    @preconcurrency
    public func append<E>(_ newElement: E, to keyPath: ReferenceWritableKeyPath<Self, Array<E>>, undoManager: UndoManager?) {
        let index = self[keyPath: keyPath].count
        
        withAnimation {
            self[keyPath: keyPath].append(newElement)
        }
        
        undoManager?.registerUndo(withTarget: self) { document in
            document.remove(at: index, from: keyPath, undoManager: undoManager)
        }
    }
    
    /// Adds the elements of a sequence to the end of the array.
    ///
    /// Use this method to append the elements of a sequence to the end of this array.
    ///
    /// - Parameters:
    ///   - sequence: The elements to append to the array.
    ///   - keyPath: The key path to the array.
    ///   - undoManager: The `UndoManager` tracking the changes.
    @preconcurrency
    public func append<E>(contentsOf sequence: some Sequence<E>, to keyPath: ReferenceWritableKeyPath<Self, Array<E>>, undoManager: UndoManager?) {
        let index = self[keyPath: keyPath].count
        
        withAnimation {
            self[keyPath: keyPath].append(contentsOf: sequence)
        }
        
        undoManager?.registerUndo(withTarget: self) { document in
            document.remove(at: index, from: keyPath, undoManager: undoManager)
        }
    }
    
    /// Inserts a new element at the specified position.
    ///
    /// The new element is inserted before the element currently at the specified index. If you pass the array's `endIndex` property as the `index` parameter, the new element is appended to the array.
    ///
    /// - Parameters:
    ///   - newElement: The element to append to the array.
    ///   - index: The index indicating the position where the `newElement` is inserted.
    ///   - keyPath: The key path to the array.
    ///   - undoManager: The `UndoManager` tracking the changes.
    @preconcurrency
    public func insert<E>(_ newElement: E, at index: Int, to keyPath: ReferenceWritableKeyPath<Self, Array<E>>, undoManager: UndoManager?) {
        withAnimation {
            self[keyPath: keyPath].insert(newElement, at: index)
        }
        
        undoManager?.registerUndo(withTarget: self) { document in
            document.remove(at: index, from: keyPath, undoManager: undoManager)
        }
    }
    
    /// Removes all the elements that satisfy the given predicate.
    ///
    /// Use this method to remove every element in a collection that meets particular criteria. The order of the remaining elements is preserved.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the array.
    ///   - undoManager: The `UndoManager` tracking the changes.
    ///   - shouldBeRemoved: A closure that takes an element of the sequence as its argument and returns a Boolean value indicating whether the element should be removed from the collection.
    @preconcurrency
    public func removeAll<E>(from keyPath: ReferenceWritableKeyPath<Self, Array<E>>, undoManager: UndoManager?, where shouldBeRemoved: (E) -> Bool) {
        var removed: [(Int, E)] = []
        for tuple in self[keyPath: keyPath].enumerated() {
            if shouldBeRemoved(tuple.element) {
                removed.append(tuple)
            }
        }
        
        withAnimation {
            self[keyPath: keyPath].removeAll(where: shouldBeRemoved)
        }
        
        undoManager?.registerUndo(withTarget: self) { document in
            undoManager?.beginUndoGrouping()
            for tuple in removed {
                document.insert(tuple.1, at: tuple.0, to: keyPath, undoManager: undoManager)
            }
            undoManager?.endUndoGrouping()
        }
    }
    
    /// Removes the element at the specified position.
    ///
    /// - Parameters:
    ///   - index: The index of the removing element.
    ///   - keyPath: The key path to the array.
    ///   - undoManager: The `UndoManager` tracking the changes.
    @preconcurrency
    public func remove<E>(at index: Int, from keyPath: ReferenceWritableKeyPath<Self, Array<E>>, undoManager: UndoManager?) {
        let removed = withAnimation {
            self[keyPath: keyPath].remove(at: index)
        }
        
        undoManager?.registerUndo(withTarget: self) { document in
            document.insert(removed, at: index, to: keyPath, undoManager: undoManager)
        }
    }
    
    /// Removes the element by matching its id.
    ///
    /// - Warning: All elements with the id matching that of `element` will be removed.
    ///
    /// - Parameters:
    ///   - element: The element to be removed.
    ///   - keyPath: The key path to the array.
    ///   - undoManager: The `UndoManager` tracking the changes.
    @preconcurrency
    public func remove<E>(_ element: E, from keyPath: ReferenceWritableKeyPath<Self, Array<E>>, undoManager: UndoManager?) where E: Identifiable {
        self.removeAll(from: keyPath, undoManager: undoManager, where: { $0.id == element.id })
    }
    
    /// Removes the specified number of elements from the end of the collection.
    ///
    /// Attempting to remove more elements than exist in the collection triggers a runtime error.
    ///
    /// - Parameters:
    ///   - k: The number of elements to be removed.
    ///   - keyPath: The key path to the array.
    ///   - undoManager: The `UndoManager` tracking the changes.
    @preconcurrency
    public func removeLast<E>(_ k: Int, from keyPath: ReferenceWritableKeyPath<Self, Array<E>>, undoManager: UndoManager?) {
        let removed = self[keyPath: keyPath][(self[keyPath: keyPath].count - 1 - k)..<self[keyPath: keyPath].count]
        withAnimation {
            self[keyPath: keyPath].removeLast(k)
        }
        
        undoManager?.registerUndo(withTarget: self) { document in
            document.append(contentsOf: removed, to: keyPath, undoManager: undoManager)
        }
    }
    
    /// Replace the value indicated by the `keyPath` with the `newValue`
    ///
    /// - Precondition: You need to ensure the `T` is a `struct`.
    @preconcurrency
    public func replace<T>(_ keyPath: ReferenceWritableKeyPath<Self, T>, with newValue: T, undoManager: UndoManager?, actionName: ((T) -> String)? = nil) {
        let removed = self[keyPath: keyPath]
        self[keyPath: keyPath] = newValue
        
        if let actionName {
            undoManager?.setActionName(actionName(newValue))
        }
        
        undoManager?.registerUndo(withTarget: self) { document in
            document.replace(keyPath, with: removed, undoManager: undoManager, actionName: actionName)
        }
    }
    
}
