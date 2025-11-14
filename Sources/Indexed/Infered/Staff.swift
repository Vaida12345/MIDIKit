//
//  Staff.swift
//  MIDIKit
//
//  Created by Vaida on 2025-10-24.
//


extension IndexedContainer {
    
    public struct Staff {
        
        var contents: [ReferenceNote] = []
        
    }
    
    
    /// Split the *grand staff* to the *base staff* and *treble staff*.
    ///
    /// Uses naive split.
    public func splitStaves() -> (bass: Staff, treble: Staff) {
        let regions = self.regions()
        // store now contains region info.
        
        var chords = self.chords()
        guard !chords.isEmpty else { return (.init(), .init()) }
        
        // make sure chords are in the same region
        var i = 0
        while i < chords.count {
            let stores = chords[i].map(\.store)
            let group = stores.reduce(into: [:]) { partialResult, new in
                partialResult[new, default: 0] += 1
            }
            guard let major = group.max(by: { $0.value < $1.value })?.key else { i &+= 1; continue }
            
            var ii = 0
            while ii < chords[i].count {
                chords[i][ii].store = major
                ii &+= 1
            }

            i &+= 1
        }
        
        let leftPitch: UInt8 = 0
        let rightPitch: UInt8 = 15
        
        chords.forEach { _, chord in
//            let min = chord.min(of: \.pitch)!
//            let max = chord.max(of: \.pitch)!
//            let mean = (min + max) / 2
//            
            chord.forEach { _, note in
                note.channel = note.pitch >= 60 ? rightPitch : leftPitch
            }
        }
        
        return (.init(), .init())
    }
    
}
