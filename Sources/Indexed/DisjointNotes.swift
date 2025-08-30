//
//  DisjointNotes.swift
//  PianoVisualizer
//
//  Created by Vaida on 11/25/24.
//

import AudioToolbox


/// > Warning:
/// > The `DisjointNote`s hold non-owning references to `IndexedContainer.contents`.
/// >
/// > You can use `extendLifetime(_:)` to ensure a container is not deallocated until it returns.
/// > ```swift
/// > extendLifetime(container)
/// > ```
public struct DisjointNotes: ArrayRepresentable, DisjointIntervals {
    
    public var contents: [ReferenceNote]
    
    @inlinable
    public init(_ contents: [ReferenceNote]) {
        self.contents = contents
    }
    
    public typealias Element = ReferenceNote
    
}
