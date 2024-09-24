//
//  Extensions.swift
//  MIDIKit
//
//  Created by Vaida on 9/9/24.
//


extension Array {
    
    @inlinable
    public mutating func forEach(body: (_ index: Index, _ element: inout Element) -> Void) {
        var i = 0
        while i < self.endIndex {
            body(i, &self[i])
            
            i &+= 1
        }
    }
    
}
