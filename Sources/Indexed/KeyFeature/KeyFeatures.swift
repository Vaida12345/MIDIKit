//
//  KeyFeature.swift
//  MIDIKit
//
//  Created by Vaida on 12/23/24.
//

import AudioToolbox
import Essentials


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
                    }.sorted { $0.onset < $1.onset },
                    sustains: []
                )
            ]
        )
    }
    
    public func pivots() -> Pivots {
        var index = 0
        var pivots: [Pivot] = []
        var beat = 0.0
        while index &+ 1 < self.count {
            beat += self[index].duration
            var similarity = self[index].similarity(to: self[index + 1])
            
            var isConsecutive: Bool {
                print(similarity)
                return similarity.count(where: { $0 == 0 }) <= 1
            }
            
            while index &+ 1 < self.count, isConsecutive {
                index &+= 1
                beat += self[index].duration
                similarity = self[index].similarity(to: self[index + 1])
            }
            
            print("^pivot^")
            pivots.append(Pivot(onset: beat, duration: 0, similarity: similarity))
            index &+= 1
        }
        pivots.append(Pivot(onset: beat, duration: 0, similarity: []))
        
        let count = pivots.count
        // calculate duration
        let _pivots: [Pivot] = pivots.enumerated().compactMap { index, element in
            guard index + 1 < count else { return nil }
            let duration = pivots[index + 1].onset - element.onset
            return Pivot(onset: element.onset, duration: duration, similarity: element.similarity)
        }
        return Pivots(_pivots)
    }
    
    
    public init(_ contents: [Element]) {
        self.contents = contents
    }
    
    /// - Parameter interval: The default value is 1/2, 8th note.
    init(container: IndexedContainer, interval: Double = 1/2) {
        guard !container.isEmpty else {
            self.init([])
            return
        }
        let end = container.contents.last!.offset
        
        var features: [KeyFeature] = []
        features.reserveCapacity(Int(end / interval))
        var beat: Double = 0
        let max = interval * 127 * 7
        
        while beat < end {
            var normal: [UInt8 : Double] = [:]
            normal.reserveCapacity(12)
            for i in (21 as UInt8)...108 {
                guard let _notes = container.notes[i] else { continue }
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
        self.init(features)
    }
    
    public typealias Element = KeyFeature
    
}


extension IndexedContainer {
    
    public func keyFeatures() async -> KeyFeatures {
        KeyFeatures(container: self)
    }
    
}
