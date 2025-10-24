//
//  Indexed + Iterator.swift
//  MIDIKit
//
//  Created by Vaida on 2025-07-12.
//


extension IndexedContainer: Sequence {
    
    public func makeIterator() -> Iterator {
        Iterator(base: self)
    }
    
    
    public struct Iterator: IteratorProtocol {
        
        let base: IndexedContainer
        
        var index = 0
        
        
        public mutating func next() -> ReferenceNote? {
            defer { index += 1 }
            guard index < base.count else { return nil }
            return ReferenceNote(base.contents.baseAddress! + index)
        }
    }
    
}
