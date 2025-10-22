//
//  main.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

#if os(macOS)
import FinderItem
import Foundation
import MIDIKit
import DetailedDescription
import SwiftUI
import Essentials

var _features: [[Double]] = []
var hands: [Double] = []

func sigmoid(_ x: Double) -> Double {
    1 / (1 + exp(-x))
}

func _1_x(_ x: Double) -> Double {
    x / (1 + x)
}

func extractFeatures(container: MIDIContainer) async -> (_features: [[Double]], hands: [Double]) {
    let indexed = container.indexed()
    guard let length = indexed.contents.last?.offset else { return ([], []) }
    let chords = await Chord.makeChords(from: indexed)
    let runningAverage = indexed.runningAverage()
    
    var _features: [[Double]] = []
    var hands: [Double] = []
    
    for (chordIndex, chord) in chords.enumerated() {
        for (noteIndexWithinChord, note) in chord.enumerated() {
            var features: [Double] = []
            // MARK: - Basics
            features.append(Double(note.note) / 127)                                    // pitch
            let determined = MIDINote.determine(note: note.pitch)
            features.append(linearInterpolate(Double(determined.group), in: -2...9, to: 0...1))  // octave group
            features.append(Double(determined.index) / 7)                              // diatonic index
            features.append((sin(2 * .pi * Double(note.note) / 12) + 1) / 2)                      // pitch class
            features.append(determined.isSharp ? 1 : 0)                                 // is sharp
            features.append(Double(note.velocity) / 127)                                // velocity
            features.append(note.onset / length)                                        // normalized onset
            features.append(clamp(note.offset / length, min: 0, max: 1))                                       // normalized offset
            features.append(_1_x(clamp(note.duration, min: 1/128)))                                        // normalized duration
            features.append(Double(abs(Int(note.pitch) - 60)) / 48)                     // distance from middle C (MIDI 60), normalized by max distance (48)
            
            // MARK: - Context
            let prevNoteWithSamePitch = indexed.notes[note.pitch]?.last(before: note.onset)
            let nextNoteWithSamePitch = indexed.notes[note.pitch]?.first(after: note.offset)
            
            if let prevNoteWithSamePitch, prevNoteWithSamePitch.onset != note.onset {
                features.append(_1_x(note.duration / (note.onset - prevNoteWithSamePitch.onset)))  // 10
                features.append(clamp(_1_x(note.onset - prevNoteWithSamePitch.onset), min: 0, max: 1)) // 11
            } else {
                features.append(0)
                features.append(0)
            }
            
            if let nextNoteWithSamePitch, nextNoteWithSamePitch.onset != note.onset {
                features.append(_1_x(note.duration / (nextNoteWithSamePitch.onset - note.onset)))
                features.append(clamp(_1_x(nextNoteWithSamePitch.onset - note.onset), min: 0, max: 1)) // 13
            } else {
                features.append(0)
                features.append(0)
            }
            
            let prevNote = indexed.contents.last(before: note.onset)
            let nextNote = indexed.contents.first(after: note.onset)
            
            if let prevNote {
                features.append(clamp(_1_x(note.onset - prevNote.onset), min: 0, max: 1))  // 14
                features.append(sigmoid(Double(note.pitch) - Double(prevNote.pitch)))
                features.append(sigmoid((Double(note.pitch) - Double(prevNote.pitch)) / ((note.onset - prevNote.onset) == 0 ? 1 : (note.onset - prevNote.onset)))) // 16
            } else {
                features.append(0)
                features.append(0)
                features.append(0)
            }
            
            if let nextNote {
                features.append(_1_x(nextNote.onset - note.onset))
                features.append(sigmoid(Double(nextNote.pitch) - Double(note.pitch)))
                features.append(sigmoid((Double(nextNote.pitch) - Double(note.pitch)) / ((nextNote.onset - note.onset) == 0 ? 1 : (nextNote.onset - note.onset))))
            } else {
                features.append(0)
                features.append(0)
                features.append(0)
            }
            
            // MARK: - Chord
            features.append(Double(chordIndex) / Double(chords.count))
            features.append(_1_x(Double(chord.count)))                               // Chord size (count of notes in the onset cluster)
            features.append(chord.count == 1 ? 0 : Double(noteIndexWithinChord) / Double(chord.count - 1))  // Pitch rank within chord, 22
            features.append(_1_x(Double(note.pitch - chord.min(of: \.pitch)!)))      // Distance to chord min, max, and median pitch
            features.append(_1_x(Double(chord.max(of: \.pitch)! - note.pitch)))
            features.append(sigmoid(Double(note.pitch) - chord.map({ Double($0.pitch) }).median!))
            features.append(sigmoid(Double(note.pitch) - chord.map({ Double($0.pitch) }).mean!))
            features.append(_1_x(Double(chord.max(of: \.pitch)! - chord.min(of: \.pitch)!)))  // Chord span (max−min pitch)
            features.append(_1_x(Double(chord.pitchSpan)))
            features.append(chord.features.contains(.glissando) ? 1 : 0)
            
            // MARK: - Window
            let heldNotes = indexed.contents[at: note.onset] // Number of held notes at onset (sustain included), split into below/above a split pitch (e.g., middle C)
            features.append(_1_x(Double(heldNotes.filter({ $0.pitch >= 60 }).count)))
            features.append(_1_x(Double(heldNotes.filter({ $0.pitch < 60 }).count)))
            
            if let average = runningAverage[at: note.onset] {
                features.append(sigmoid(Double(note.pitch) - Double(average.pitch)))
                features.append(_1_x(Double(average.span)))
            } else {
                features.append(0)
                features.append(0)
            }
            
            if let nearestUpperNote = heldNotes.filter({ $0.pitch > note.pitch }).min() {
                features.append(_1_x(note.onset - nearestUpperNote.onset))
            } else {
                features.append(0)
            }
            
            if let nearestLowerNote = heldNotes.filter({ $0.pitch < note.pitch }).max() {
                features.append(_1_x(note.onset - nearestLowerNote.onset))
            } else {
                features.append(0)
            }
            
            
            /*
             Pitch interval to previous note (global onset order) and to next note
             Time-normalized interval: interval / max(1, IOI) to discount fast ornaments
             */
            // the dataset has no sustain, ignore.
            
            // chord analysis.
            _features.append(features)
            hands.append(Double(note.channel))
            
            // sanity check: all normalized
            for (i, v) in features.enumerated() {
                if v < 0 && v > -0.000001 {
                    features[i] = 0
                    continue
                }
                
                if v < 0 || v > 1 || v.isNaN {
                    fatalError("Feature \(i) out of [0,1]: \(v)")
                }
            }
        }
    }
    
    return (_features, hands)
}

for child in try FinderItem(at: "/Users/vaida/Desktop/Hands/asap-dataset-master").children(range: .enumeration) {
    guard child.extension == "mid" else { continue }
    guard let container = try? MIDIContainer(at: child) else { continue }
    guard container.tracks.count == 2 else { continue }
    let new = await extractFeatures(container: container)
    _features.append(contentsOf: new.0)
    hands.append(contentsOf: new.1)
}

print("Input size: \(_features[0].count), \(_features.count)")

try """
_X = \(_features)
_y = \(hands)
""".write(to: .desktopDirectory/"Hands/dataset.py")

#endif
