//
//  KeyFeature.swift
//  MIDIKit
//
//  Created by Vaida on 12/23/24.
//

import AudioToolbox
import Essentials


extension IndexedContainer {
    
    public func keyFeatures(interval: Double) async -> KeyFeatures {
        guard !self.combinedNotes.isEmpty else { return [] }
        let end = self.combinedNotes.last!.offset
        
        var features: [KeyFeature] = []
        features.reserveCapacity(Int(end / interval))
        var beat: Double = 0
        let max = interval * 127 * 7
        
        while beat < end {
            var normal: [UInt8 : Double] = [:]
            normal.reserveCapacity(12)
            for i in (21 as UInt8)...108 {
                guard let _notes = self.notes[i] else { continue }
                var onset = _notes.index(at: beat) ?? _notes.firstIndex(after: beat) ?? .max
                let offset = _notes.index(at: beat + interval) ?? _notes.firstIndex(after: beat + interval) ?? .min
                
                var value = 0.0
                
                while onset <= offset {
                    let note = _notes[onset]
                    let normal = MIDINote(onset: clamp(note.onset, min: beat), offset: clamp(note.offset, max: beat + interval), note: note.note, velocity: note.velocity)
                    value += Double(normal.velocity) * Swift.max(normal.duration, 0)
                    
                    onset &+= 1
                }
                
                let index = i % 12
                normal[index, default: 0] += value / max
            }
            
            features.append(KeyFeature(onset: beat, keys: normal, duration: interval))
            beat += interval
        }
        return KeyFeatures(features)
    }
    
}


public struct KeyFeatures: ArrayRepresentable {
    
    public var contents: [Element]
    
    
    public func makeContainer() -> MIDIContainer {
        MIDIContainer(
            tracks: [
                MIDITrack(
                    notes: self.contents.flatMap { content in
                        content.keys.map { (key: UInt8, value: Double) in
                            MIDINote(
                                onset: content.onset,
                                offset: content.onset + content.duration,
                                note: 60 + key,
                                velocity: UInt8(value * 127)
                            )
                        }
                    },
                    sustains: []
                )
            ]
        )
    }
    
    
    public init(_ contents: [Element]) {
        self.contents = contents
    }
    
    public typealias Element = KeyFeature
    
}


public struct KeyFeature {
    
    public let onset: Double
    
    public let keys: [UInt8 : Double]
    
    /// Duration in beats.
    public let duration: Double
    
    
    /// Calculate the similarity score, normalized between 0 and 1.
    public func similarity(to other: KeyFeature) -> Double {
        var value = 0.0
        for i in (0 as UInt8)...12 {
            guard let lhs = self.keys[i], let rhs = other.keys[i] else { continue }
            value += Swift.min(lhs, rhs)
        }
        return value / 12
    }
    
}
