//
//  NotesProviding.swift
//  MIDIKit
//
//  Created by Vaida on 2025-10-24.
//


public protocol NotesProviding: OverlappingIntervals where Index == Int, Element == ReferenceNote {
    
    var contents: [ReferenceNote] { get }
    
    var sustains: MIDISustainEvents { get }
    
}


extension NotesProviding {
    
    public var startIndex: Int { self.contents.startIndex }
    public var endIndex: Index { self.contents.endIndex }
    public var isEmpty: Bool { self.contents.isEmpty }
    public var count: Int { self.contents.count }
    
    public subscript(_ index: Index) -> Element { self.contents[index] }
    
}
