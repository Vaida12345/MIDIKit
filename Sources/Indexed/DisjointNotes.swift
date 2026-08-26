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
public struct DisjointNotes: DisjointIntervals {
    
    public var contents: [ReferenceNote]
    
    @inlinable
    public init(_ contents: [ReferenceNote]) {
        self.contents = contents
    }
    
    public typealias Element = ReferenceNote
    
}


extension DisjointNotes: ExpressibleByArrayLiteral, RandomAccessCollection, MutableCollection, BidirectionalCollection {
    
    @inlinable public var startIndex: Int { 0 }
    @inlinable public var endIndex: Int { self.contents.count }
    @inlinable public var count: Int { self.contents.count }
    
    @inlinable
    public subscript(position: Index) -> Element {
        get {
            self.contents[position]
        }
        set {
            self.contents[position] = newValue
        }
    }
    
    @inlinable
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
    
}
