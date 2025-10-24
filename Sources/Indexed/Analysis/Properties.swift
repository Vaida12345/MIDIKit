//
//  Properties.swift
//  MIDIKit
//
//  Created by Vaida on 2025-10-24.
//


extension IndexedContainer {
    
    /// The percentage in the sustain track where the sustain is `on`.
    ///
    /// - Returns: If `self.isEmpty`, returns `1`.
    public var sustainCoverage: Double {
        guard let maxOffset = self.contents.last?.offset else { return 1 }
        guard maxOffset > 0 else { return 1 }
        
        var cumulative = 0.0
        var i = 0
        while i < self.sustains.count {
            cumulative += self.sustains[i].duration
            
            i &+= 1
        }
        return cumulative / Double(maxOffset)
    }
    
}
