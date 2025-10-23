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
                    if v.isNaN {
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
                _append(Float(Int(note.pitch) - 60) / Float(maxPitch - minPitch))                     // distance from middle C (MIDI 60), normalized by pitch range of this piece.
                
                // MARK: - Context
                let prevNoteWithSamePitch = indexed.notes[note.pitch]?.last(before: note.onset)
                let nextNoteWithSamePitch = indexed.notes[note.pitch]?.first(after: note.offset)
                
                if let prevNoteWithSamePitch, prevNoteWithSamePitch.onset != note.onset {
                    _append((note.onset - prevNoteWithSamePitch.onset) / note.duration)  // 13, note duration to onset distance from prev note with same pitch
                    _append(note.onset - prevNoteWithSamePitch.onset) // 14, onset distance from prev note with same pitch
                } else {
                    _append(0)
                    _append(0)
                }
                
                if let nextNoteWithSamePitch, nextNoteWithSamePitch.onset != note.onset {
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
        let z_index_mean: [Float] = [400.58560124065207, 0.5065642101144798, 0.07580230769866388, 8.437072096348489, 29.26587312630198, 8.565308135269921, 0.4699071916099486, 1.1700888189600993, -663.0841068864909, 0.38496637687882695, 2.9609012842367126, -2411.1821064498276, 0.5023642179465778, 0.36381360121438894, 7.466094663425574, -0.2479479480939139, -7.957350874464396e-17, 0.007206765747500872, 15.250100251247854, 0.0102992663795957, 1.8003563840723733, 1.2181685883311921, 2.0078247010325514, 40.85694912486129, 0.05841350929649344, 0.057100172587897485, 0.739146783336787, 4.76393783985173, 2.8609125123764723, 0.01076809393752088, 45.174539245265024, 4.854799738107285, 2.9185157857437622, 0.010765980339241176, 18.537110460105836, 6.722239153544082, 3.5431430333767393, 0.010988321653513343, 14.181694632511736, 10.174093036074408, 5.003684871321144, 0.01094331936222911, 31.852410808869692, 29.685367785549715, 31.84302164553349, 31.240415020199684, 23.138198559646195, 24.95036906995148, 24.01162011333397, 23.422591085920697, 26.515633736957472, 25.62346961554205, 26.472280723981402, 24.9310685652544, 19.93310092343354, 21.205861547544178, 21.01170528710681, 21.20319692779389, 19.04944164339853, 20.572265286283617, 22.195396523099998, 22.792424158825536, -0.5054887889780301, -0.5056637117163275, -0.5041970153110494, -0.5044822896900707, 0.6198253951357365, 3.6385107695358694, 8.842470657371129, 0.5092063455029842, -1.3822788804196548e-16, 6.15795513701976]
        let z_index_std: [Float] = [420.82672445161074, 0.6800031106721081, 0.28063483006924717, 27.63031110388381, 1618.6908077668768, 27.79157360418914, 0.5579784470327706, 13.94353385079306, 152094.35513642844, 0.4139601319091651, 13.977495043607316, 151517.8273382315, 0.2917396726799991, 0.42747713659737435, 10.844066461589506, 8.80929991744519, 8.470707766713124, 0.04023279506879845, 13.754874799429487, 0.10096133661772623, 1.293352942923658, 1.0989917471939608, 11.981889830362604, 11.97162692184481, 0.29330196921658425, 0.25422839302825523, 0.17850584704535535, 4.434252051042448, 2.458804200255526, 0.07136243121788542, 31.197203786126753, 4.474144166308305, 2.523996003395223, 0.071269853262935, 26.896983005818527, 13.282094738980918, 3.1169045028807374, 0.07046611304240294, 27.26716204873089, 26.839212989553065, 4.5590704724451685, 0.06665791783734917, 59.90989538290775, 56.693503117033565, 62.45685901301934, 61.72560644153847, 51.49471786744176, 54.95239390352454, 56.06715394617567, 53.928780928417886, 55.11837827858817, 56.061789829627614, 58.92783639176886, 57.56075983519258, 45.581320601438364, 50.85320117554969, 55.40521564200137, 52.68149487577152, 51.78649249965473, 55.29305588180004, 64.37433489527008, 65.49907074724595, 0.5596488751151942, 0.5131000814254528, 0.4859356864973775, 0.4685476574473271, 0.48542957746779775, 13.470471843322889, 31.81011602032557, 0.49991523601754706, 13.102528288292728, 20.597890891174043]
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
