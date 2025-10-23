//
//  NoteFeatures.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-18.
//

import Foundation
import Essentials


extension IndexedContainer {
    
    /// ## Features
    /// - note pitch
    /// - note octave
    /// - note pitch inside octave
    /// - note pitch class
    /// - note is sharp
    /// - note velocity
    /// - note onset
    /// - note offset
    /// - note duration
    /// - note distance from middle C
    /// - note duration to onset distance from prev note with same pitch
    /// - note onset distance from prev note with same pitch
    /// - note duration to onset distance from next note with same pitch
    /// - note onset distance from next note with same pitch
    /// - onset difference from previous note
    /// - pitch difference from previous note
    /// - pitch difference from previous note to onset distance
    /// - onset difference from next note
    /// - pitch difference from next note
    /// - pitch difference from next note to onset distance
    /// - chord index
    /// - chord size in notes
    /// - pitch rank within chord
    /// - distance to chord min pitch
    /// - distance to chord max pitch
    /// - distance to chord median pitch
    /// - distance to chord mean pitch
    /// - chord span in pitch
    /// - chord span in duration
    /// - chord is glissando
    /// - number of held notes with pitch >= 60 at onset
    /// - number of held notes with pitch < 60 at onset
    /// - distance from the running average pitch
    /// - running average pitch span
    /// - onset distance to the nearest upper held note
    /// - onset distance to the nearest lower held note
    ///
    /// - distance_to_keyboard_edges: min(pitch−21, 108−pitch) and normalized version
    /// - notes_per_second in ±50 ms, ±150 ms, ±500 ms windows
    /// - density_above_θ and density_below_θ: counts above/below an adaptive split θ in same windows
    /// - mean_velocity_window
    /// - time_since_last_pitch_in {p−2, p−1, p, p+1, p+2}; and to next occurrence (you already have “same pitch”; add ±1/±2 for trills/ornaments)
    /// - time_since_last_octave (p±12) and to next octave
    /// - repetition_rate_same_pitch: 1 / mean IOI for same pitch over last K hits (K=3–5)
    /// - naive_split_label
    /// - naive_split_margin
    /// - stay_with_naive_run_len: number of consecutive notes the naive rule keeps the same hand up to now
    ///
    /// - Need z_index:
    /// `[8, 9, 10, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 24, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38]` no 39, 40...
    public func _extractMIDINoteFeatures() async -> (_features: [[Float]], hands: [Float], chords: [Chord]) {
        let indexed = self
        guard let length = indexed.contents.last?.offset else { return ([], [], []) }
        let chords = await Chord.makeChords(from: indexed)
        let runningAverage = indexed.runningAverage()
        guard let pitchAverage = indexed.contents.mean(of: { Float($0.pitch) }) else { return ([], [], []) }
        let minPitch = indexed.contents.min(of: \.note)!
        let maxPitch = indexed.contents.max(of: \.note)!
        
        var _features: [[Float]] = []
        var hands: [Float] = []
        
        var consecutive: [Float] = [0.0, 0.0]
        var last: [Float] = [0.0, 0.0]
        
        for (chordIndex, chord) in chords.enumerated() {
            for (noteIndexWithinChord, note) in chord.enumerated() {
                var features: [Float] = []
                
                func _append(_ v: Float, line: Int = #line) {
                    if v.isNaN, v.isInfinite {
                        fatalError("invalid feature: \(v) @line:\(line)")
                    }
                    features.append(v)
                }
                
                func _append(_ v: Double) {
                    _append(Float(v))
                }
                
                
                // MARK: - Basics
                _append(Float(note.note) / 127)                                    // pitch
                _append(Float(note.note - minPitch) / Float(maxPitch - minPitch))
                let determined = MIDINote.determine(note: note.pitch)
                _append(linearInterpolate(Float(determined.group), in: -2...9, to: 0...1))  // octave group
                _append(Float(determined.index) / 7)                              // diatonic index
                _append((sin(2 * .pi * Float(note.note) / 12) + 1) / 2)                      // pitch class
                _append(determined.isSharp ? 1 : 0)                                 // is sharp
                _append(Float(note.velocity) / 127)                                // velocity
                _append(note.onset / length)                                        // 8, normalized onset
                _append(note.offset / length)                                       // 9, normalized offset
                _append(note.duration)                                        // 10, normalized duration
                _append(Float(Int(note.pitch) - 60) / 48)                     // distance from middle C (MIDI 60), normalized by max distance (48)
                _append(Float(Int(note.pitch) - 60) / Swift.max(Float(maxPitch - minPitch), 1))                     // distance from middle C (MIDI 60), normalized by pitch range of this piece.
                
                // MARK: - Context
                let prevNoteWithSamePitch = indexed.notes[note.pitch]?.last(before: note.onset)
                let nextNoteWithSamePitch = indexed.notes[note.pitch]?.first(after: note.offset)
                
                if let prevNoteWithSamePitch, prevNoteWithSamePitch.onset != note.onset, note.duration > 0.01 {
                    _append((note.onset - prevNoteWithSamePitch.onset) / note.duration)  // 13, note duration to onset distance from prev note with same pitch
                    _append(note.onset - prevNoteWithSamePitch.onset) // 14, onset distance from prev note with same pitch
                } else {
                    _append(0)
                    _append(0)
                }
                
                if let nextNoteWithSamePitch, nextNoteWithSamePitch.onset != note.onset, note.duration > 0.01 {
                    _append((nextNoteWithSamePitch.onset - note.onset) / note.duration) // 15, note duration to onset distance from next note with same pitch
                    _append(nextNoteWithSamePitch.onset - note.onset) // 16, onset distance from next note with same pitch
                } else {
                    _append(0)
                    _append(0)
                }
                
                let prevNote = indexed.contents.last(before: note.onset)
                let nextNote = indexed.contents.first(after: note.onset)
                
                if let prevNote {
                    _append(note.onset - prevNote.onset)  // 17
                    _append(Float(note.pitch) - Float(prevNote.pitch)) // 18, pitch difference from previous note
                    _append((Float(note.pitch) - Float(prevNote.pitch)) / Float((note.onset - prevNote.onset) == 0 ? 1 : (note.onset - prevNote.onset))) // 19, pitch difference from previous note to onset distance
                } else {
                    _append(0)
                    _append(0)
                    _append(0)
                }
                
                if let nextNote {
                    _append(nextNote.onset - note.onset) // 20
                    _append(Float(nextNote.pitch) - Float(note.pitch)) // 21, pitch difference to next note
                    _append((Float(nextNote.pitch) - Float(note.pitch)) / Float((nextNote.onset - note.onset) == 0 ? 1 : (nextNote.onset - note.onset))) // 22, pitch difference from next note to onset distance
                } else {
                    _append(0)
                    _append(0)
                    _append(0)
                }
                
                // MARK: - Chord
                _append(Float(chordIndex) / Float(chords.count))
                _append(Float(chord.count))                               // 24, Chord size (count of notes in the onset cluster)
                _append(chord.count == 1 ? 0 : Float(noteIndexWithinChord) / Float(chord.count - 1))  // Pitch rank within chord
                _append(Float(note.pitch - chord.min(of: \.pitch)!))      // 26, Distance to chord min, max, and median pitch
                _append(Float(chord.max(of: \.pitch)! - note.pitch))
                _append(Float(note.pitch) - chord.map({ Float($0.pitch) }).median!)
                _append(Float(note.pitch) - chord.map({ Float($0.pitch) }).mean!)
                _append(Float(chord.max(of: \.onset)! - chord.min(of: \.onset)!))
                _append(Float(chord.pitchSpan))  // Chord span (max−min pitch)
                _append(chord.features.contains(.glissando) ? 1 : 0)
                
                // MARK: - Window
                let heldNotes = indexed.contents[at: note.onset] // Number of held notes at onset (sustain included), split into below/above a split pitch (e.g., middle C)
                _append(Float(heldNotes.filter({ $0.pitch >= 60 }).count)) // 33
                _append(Float(heldNotes.filter({ $0.pitch < 60 }).count))
                
                if let average = runningAverage[at: note.onset] {
                    _append(Float(note.pitch) - Float(average.pitch)) // 35
                    _append(Float(average.span))
                } else {
                    _append(0)
                    _append(0)
                }
                
                if let nearestUpperNote = heldNotes.filter({ $0.pitch > note.pitch }).min() {
                    _append(note.onset - nearestUpperNote.onset) // 37
                } else {
                    _append(0)
                }
                
                if let nearestLowerNote = heldNotes.filter({ $0.pitch < note.pitch }).max() {
                    _append(note.onset - nearestLowerNote.onset) // 38
                } else {
                    _append(0)
                }
                
                _append(Float(Swift.min(note.pitch - 21, 108 - note.pitch)) / 44) // 39
                func addNotesPerSecond(_ duration: Double) {
                    if let indexBefore = indexed.contents.lastIndex(before: note.onset - duration / 2),
                       let indexAfter = indexed.contents.firstIndex(after: note.onset + duration / 2) {
                        let distance = Double(indexAfter - indexBefore)
                        _append(distance / duration)
                        
                        let elements = indexed.contents[indexBefore...indexAfter]
                        _append(Float(elements.count(where: { $0.pitch >= 60 })))
                        _append(Float(elements.count(where: { $0.pitch <  60 })))
                        _append(Float(elements.map({ Float($0.velocity / 127) }).mean ?? 0))
                    } else {
                        _append(0)
                        _append(0)
                        _append(0)
                        _append(0)
                    }
                }
                addNotesPerSecond(0.05)
                addNotesPerSecond(0.15)
                addNotesPerSecond(0.5)
                addNotesPerSecond(1)
                
                func addTimeSienceLastPitch(_ pitch: Int) {
                    if let last = indexed.notes[UInt8(Int(note.pitch) + pitch)]?.last(before: note.onset) {
                        _append(note.onset - last.onset)
                    } else {
                        _append(0)
                    }
                }
                
                func addTimeToNextPitch(_ pitch: Int) {
                    if let next = indexed.notes[UInt8(Int(note.pitch) + pitch)]?.first(after: note.onset) {
                        _append(next.onset - note.onset)
                    } else {
                        _append(0)
                    }
                }
                
                for i in [1, 2, 3, 5, 12] {
                    addTimeSienceLastPitch(i)
                    addTimeSienceLastPitch(-i)
                    addTimeToNextPitch(i)
                    addTimeToNextPitch(-i)
                }
                
                func repetitionRate(k: Int) {
                    let notes = indexed.notes[note.pitch]!
                    guard var index = notes.index(at: note.onset) else { _append(0); return }
                    var cumm: [MIDINote] = []
                    while index >= 0 && cumm.count < k {
                        cumm.append(notes[index].pointee)
                        
                        index -= 1
                    }
                    cumm.append(note.pointee)
                    guard notes.count > 1 else { _append(0); return }
                    
                    var distances: [Double] = []
                    var first = cumm.removeFirst().offset
                    while !cumm.isEmpty {
                        let next = cumm.removeFirst()
                        distances.append(next.onset - first)
                        first = next.offset
                    }
                    _append(distances.mean!)
                }
                
                repetitionRate(k: 2)
                repetitionRate(k: 3)
                repetitionRate(k: 4)
                repetitionRate(k: 5)
                
                func addNativeSplit(reference: Float, index: Int) {
                    let bool: Float = Float(note.pitch) >= reference ? 1 : 0
                    _append(bool)
                    _append(Float(note.pitch) - reference)
                    
                    if bool == last[index] {
                        consecutive[index] += 1
                        _append(consecutive[index])
                    } else {
                        consecutive[index] = 0
                        _append(0)
                    }
                    last[index] = bool
                }
                
                addNativeSplit(reference: 60, index: 0)
                addNativeSplit(reference: pitchAverage, index: 1)
                // the dataset has no sustain, ignore.
                
                // chord analysis.
                _features.append(features)
                hands.append(Float(note.channel))
            }
        }
        
        // MARK: - sentitation
        let z_index_mean: [Float] = [0.50796115, 0.36735708, 0.07511451, 8.822138, 29.90089, 8.827586, 0.46130326, -0.4500757, -3.4191978, 0.38926566, 0.34365404, -6.3848, 0.5033086, 0.3710171, 7.657323, -0.25146577, -8.739271e-09, 0.007241058, 15.637329, 0.0033543883, 1.8632815, 1.2064657, 1.9200063, 40.74409, 0.049862776, 0.027816897, 0.7389005, 3.9944785, 2.51478, 0.010337704, 37.55966, 4.0687747, 2.5623157, 0.010333601, 15.218754, 5.3409333, 3.2652323, 0.010621579, 11.516157, 7.776066, 4.7360773, 0.010678159, 31.743156, 29.610685, 32.023853, 31.484764, 23.12037, 24.759693, 24.131998, 23.625353, 26.418756, 25.255995, 26.624527, 25.051939, 19.836885, 20.792364, 21.088463, 21.256525, 18.88853, 20.29686, 22.193617, 22.95114, -0.36388317, -0.36400205, -0.3642616, -0.3644754, 0.61773694, 3.6054976, 8.076848, 0.50863206, -8.6373126e-07, 5.876535]
        let z_index_std: [Float] = [0.2849205, 0.37781093, 0.28072676, 28.160145, 105.8873, 28.198992, 0.5092437, 14.339809, 87.530975, 0.41639203, 15.151608, 612.81305, 0.2915275, 0.4280735, 10.925977, 8.923694, 8.58017, 0.040433086, 13.737691, 0.057819862, 1.4136865, 1.2139537, 11.930545, 12.016607, 0.2045139, 0.12380485, 0.17841479, 2.3174975, 2.12299, 0.0710907, 16.968796, 2.3713102, 2.173699, 0.071019076, 7.1419845, 3.3699741, 2.8307998, 0.07012527, 5.869135, 5.185024, 4.249212, 0.066234544, 60.05287, 56.89822, 62.126057, 61.707157, 51.434227, 53.98289, 56.056026, 54.085823, 55.27226, 55.826984, 58.488525, 57.062122, 45.302074, 50.69039, 55.399227, 52.174156, 51.90268, 54.66179, 64.47609, 65.79711, 0.31481424, 0.29272944, 0.28025684, 0.27232686, 0.48594034, 13.47469, 28.664387, 0.4999255, 13.1172285, 19.545404]
        let z_index_features = [8, 9, 10, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 24, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38] + [Int](40..<85)
        
        func sanitize(features: inout [Float]) {
            var offset = 0
            while offset < z_index_features.count {
                let featureIndex = z_index_features[offset]
                features[featureIndex] = (features[featureIndex] - z_index_mean[offset]) / z_index_std[offset]
                
                offset &+= 1
            }
        }
        
        
        var i = 0
        while i < _features.count {
            sanitize(features: &_features[i])
            
            i &+= 1
        }
        
        return (_features, hands, chords)
    }
    
}
