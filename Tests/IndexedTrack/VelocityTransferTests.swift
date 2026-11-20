//
//  VelocityTransferTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import Foundation
import MIDIKit
@testable
import IndexedTrack


// MARK: - Helpers

extension IndexedTrackRNG {
    
    /// A uniform value in `0..<1`.
    fileprivate mutating func unit() -> Double {
        Double(self.next() >> 11) / Double(1 << 53)
    }
    
    /// A standard normal value, by the Box-Muller transform.
    fileprivate mutating func normal() -> Double {
        let first = Swift.max(self.unit(), 1e-12)
        let second = self.unit()
        return (-2 * log(first)).squareRoot() * cos(2 * .pi * second)
    }
}


/// A profile that only tells itself apart from ``GenericProfile``.
private struct MarkedProfile: AnalysisProfile {
    
    func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        GenericProfile().formChords(in: track)
    }
}


/// The partners as the documentation states them, the plain way: every pair on a key closer than `window`, the closest first, ties to the earlier sheet note, then to the earlier performance note.
///
/// Within a key, notes are sorted by onset, so the order of note indices is the order of lane positions.
private func referencePartners(onsets: [Double], sheet: [MIDINote], performance: [MIDINote], window: Double) -> [Int] {
    var pairs: [(distance: Double, sheet: Int, performance: Int)] = []
    for i in sheet.indices {
        for j in performance.indices where performance[j].pitch == sheet[i].pitch {
            let distance = abs(performance[j].onset - onsets[i])
            if distance < window { pairs.append((distance, i, j)) }
        }
    }
    pairs.sort { ($0.distance, $0.sheet, $0.performance) < ($1.distance, $1.sheet, $1.performance) }
    var partners = [Int](repeating: -1, count: sheet.count)
    var taken = Set<Int>()
    for pair in pairs where partners[pair.sheet] < 0 && !taken.contains(pair.performance) {
        partners[pair.sheet] = pair.performance
        taken.insert(pair.performance)
    }
    return partners
}


/// The fill as the documentation states it, the plain way, over every note of the performance.
private func referenceFill(time: Double, pitch: UInt8, performance: [MIDINote]) -> UInt8 {
    func estimate(timeScale: Double, pitchScale: Double) -> Double? {
        let reach = (3 * pitchScale).rounded(.up)
        var total = 0.0
        var sum = 0.0
        // Visit the notes by key, then by onset, as the library does, so the sums round the same way.
        let ordered = performance.sorted { ($0.pitch, $0.onset) < ($1.pitch, $1.onset) }
        for note in ordered where abs(Double(note.pitch) - Double(pitch)) <= reach && note.onset >= time - 3 * timeScale && note.onset <= time + 3 * timeScale {
            let semitones = (Double(note.pitch) - Double(pitch)) / pitchScale
            let offset = (note.onset - time) / timeScale
            let weight = exp(-0.5 * semitones * semitones) * exp(-0.5 * offset * offset)
            total += weight
            sum += weight * Double(note.velocity)
        }
        return total > 1e-6 ? sum / total : nil
    }
    let velocities = performance.map { Double($0.velocity) }.sorted()
    let median = velocities.isEmpty ? 64 : (velocities[(velocities.count - 1) / 2] + velocities[velocities.count / 2]) / 2
    let value = estimate(timeScale: 0.5, pitchScale: 3) ?? estimate(timeScale: 2, pitchScale: 12) ?? median
    return UInt8(Swift.min(127, Swift.max(1, (value - 15).rounded())))
}


/// A performance of `sheet`: every note's times mapped through `map`, its onset moved by Gaussian jitter of `jitter` beats, and its velocity drawn around a smooth dynamic level with a spread of `accent`. Notes for which `drop`, given the note and its level, returns `true` are left out.
private func perform(_ sheet: IndexedTrack, seed: UInt64, jitter: Double, accent: Double = 4, map: (Double) -> Double, drop: (MIDINote, Double, inout IndexedTrackRNG) -> Bool = { _, _, _ in false }) -> (performance: [MIDINote], velocities: [UInt8], dropped: [Bool]) {
    var rng = IndexedTrackRNG(seed: seed)
    var performance: [MIDINote] = []
    var velocities: [UInt8] = []
    var dropped: [Bool] = []
    for note in sheet.notes {
        let level = 60 + 25 * sin(note.onset / 7) + Double(note.pitch) - 60
        let loudness = level + accent * rng.normal()
        var played = note
        played.velocity = UInt8(Swift.min(127, Swift.max(1, loudness.rounded())))
        let onset = map(note.onset) + jitter * rng.normal()
        played.offset = onset + (map(note.offset) - map(note.onset))
        played.onset = onset
        velocities.append(played.velocity)
        let isDropped = drop(played, level, &rng)
        dropped.append(isDropped)
        if !isDropped { performance.append(played) }
    }
    return (performance, velocities, dropped)
}


/// The tests of `IndexedTrack.applyingVelocities(from:warp:)`.
@Suite(.timeLimit(.minutes(1)))
struct VelocityTransferTests {
    
    // MARK: Matching
    
    @Test(arguments: 0..<20)
    func partnersMatchThePlainReference(seed: Int) {
        var rng = IndexedTrackRNG(seed: UInt64(seed) &+ 500)
        let sheet = track(cleanInput(seed: UInt64(seed) &+ 100, count: 300))
        var played: [MIDINote] = []
        for note in sheet.notes where rng.int(0...9) != 0 {
            var moved = note
            moved.onset += Double(rng.int(-24...24)) / 128
            moved.offset = moved.onset + note.duration
            played.append(moved)
        }
        for _ in 0..<30 {
            let onset = Double(rng.int(0...800)) / 16
            played.append(note(onset, onset + 0.25, UInt8(rng.int(48...72))))
        }
        let performance = track(played)
        let onsets = sheet.notes.map(\.onset)
        
        let partners = VelocityTransfer.partners(onsets: onsets, sheet: sheet.lanes, performance: performance.lanes, window: VelocityTransfer.matchWindow)
        #expect(partners == referencePartners(onsets: onsets, sheet: sheet.notes, performance: performance.notes, window: VelocityTransfer.matchWindow))
        #expect(partners.filter { $0 >= 0 }.count > sheet.notes.count / 2)
    }
    
    @Test
    func aPartnerIsNeverShared() {
        // A fast repeated note, played 0.08 beats late: each sheet note can reach two performance notes, and the third performance note is missing.
        let sheet = track((0..<6).map { note(Double($0) * 0.2, Double($0) * 0.2 + 0.1, 60, velocity: 64) })
        var played: [MIDINote] = []
        for index in 0..<6 where index != 3 {
            let onset = Double(index) * 0.2 + 0.08
            played.append(note(onset, onset + 0.1, 60, velocity: UInt8(10 * (index + 1))))
        }
        let performance = track(played)
        let result = sheet.applyingVelocities(from: performance, warp: .identity)
        let velocities: [UInt8] = result.notes.map(\.velocity)
        
        #expect(Array(velocities[0..<3]) == [10, 20, 30])
        #expect(Array(velocities[4...]) == [50, 60])
        // The fourth note keeps no partner, as the one it could reach belongs to the third.
        #expect(result.notes[3].velocity == referenceFill(time: sheet.notes[3].onset, pitch: 60, performance: performance.notes))
    }
    
    @Test
    func tiesGoToTheEarlierNote() {
        // 0.125 is exact in binary, so both distances are equal.
        let performance = track([note(0.875, 0.95, 60, velocity: 30), note(1.125, 1.2, 60, velocity: 90)])
        let one = track([note(1, 1.05, 60)]).applyingVelocities(from: performance, warp: .identity)
        #expect(one.notes[0].velocity == 30)
        
        let two = track([note(0.875, 0.95, 62), note(1.125, 1.2, 62)])
        let single = track([note(1, 1.05, 62, velocity: 100)])
        let result = two.applyingVelocities(from: single, warp: .identity)
        #expect(result.notes[0].velocity == 100)
        #expect(result.notes[1].velocity == referenceFill(time: 1.125, pitch: 62, performance: single.notes))
    }
    
    @Test
    func theWindowIsExclusive() {
        let performance = track([note(1.25, 1.5, 60, velocity: 100)])
        let result = track([note(1, 1.1, 60)]).applyingVelocities(from: performance, warp: .identity)
        // 0.25 apart is out of reach: the note is filled, from the same note, less the offset.
        #expect(result.notes[0].velocity == 85)
    }
    
    // MARK: Copying
    
    @Test(arguments: 0..<4)
    func theSameNotesGiveTheirVelocities(seed: Int) {
        let sheet = track(cleanInput(seed: UInt64(seed) &+ 10, count: 400).map { var note = $0; note.velocity = 64; return note })
        var rng = IndexedTrackRNG(seed: UInt64(seed))
        let performance = track(sheet.notes.map { var note = $0; note.velocity = UInt8(rng.int(1...127)); return note })
        
        let passed = sheet.applyingVelocities(from: performance, warp: .identity)
        #expect(passed.notes.map(\.velocity) == performance.notes.map(\.velocity))
        let computed = sheet.applyingVelocities(from: performance)
        #expect(computed.notes.map(\.velocity) == performance.notes.map(\.velocity))
    }
    
    @Test
    func aKnownWarpWithJitterKeepsEveryPartner() throws {
        let sheet = track(cleanInput(seed: 77, count: 600))
        let (played, velocities, _) = perform(sheet, seed: 3, jitter: 0.02, map: { 1.3 * $0 + 4 })
        let performance = track(played)
        
        let warp = try #require(TimeWarp(knots: [.init(source: 0, target: 4), .init(source: 100, target: 134)]))
        let passed = sheet.applyingVelocities(from: performance, warp: warp)
        let computed = sheet.applyingVelocities(from: performance)
        let exactPassed = zip(passed.notes, velocities).filter { $0.velocity == $1 }.count
        let exactComputed = zip(computed.notes, velocities).filter { $0.velocity == $1 }.count
        print("known warp: \(exactPassed) of \(velocities.count) exact with the warp passed, \(exactComputed) with the warp computed")
        #expect(exactPassed == velocities.count)
        #expect(Double(exactComputed) >= 0.99 * Double(velocities.count))
    }
    
    @Test
    func extraPerformanceNotesAreIgnored() {
        let sheet = track([note(0, 0.5, 60), note(1, 1.5, 64), note(2, 2.5, 67)])
        let performance = track([note(0, 0.5, 60, velocity: 40), note(0.5, 0.8, 72, velocity: 1), note(1, 1.5, 64, velocity: 50), note(1.02, 1.3, 65, velocity: 127), note(2, 2.5, 67, velocity: 60)])
        #expect(sheet.applyingVelocities(from: performance, warp: .identity).notes.map(\.velocity) == [40, 50, 60])
    }
    
    // MARK: Filling
    
    @Test
    func aMissingNoteTakesAfterItsNeighborsLessTheOffset() {
        // A note of the melody is missing: the note 2 semitones away at the same time counts, the bass 12 semitones away is out of reach.
        let performance = track([note(4, 4.5, 62, velocity: 90), note(4, 4.5, 48, velocity: 30), note(20, 20.5, 60, velocity: 10)])
        let result = track([note(4, 4.5, 60)]).applyingVelocities(from: performance, warp: .identity)
        #expect(result.notes[0].velocity == 75)
        
        // Two neighbors, weighed by time and pitch.
        let two = track([note(4, 4.5, 62, velocity: 90), note(4.25, 4.5, 63, velocity: 50)])
        let filled = track([note(4, 4.5, 60)]).applyingVelocities(from: two, warp: .identity)
        #expect(filled.notes[0].velocity == referenceFill(time: 4, pitch: 60, performance: two.notes))
        #expect(filled.notes[0].velocity == 59)
    }
    
    @Test
    func farNeighborsCountThroughTheWiderReach() {
        // Two beats away is beyond 1.5 beats, but within 6 once the reach is widened.
        let performance = track([note(12, 12.5, 62, velocity: 100)])
        let result = track([note(10, 10.5, 60)]).applyingVelocities(from: performance, warp: .identity)
        #expect(result.notes[0].velocity == 85)
    }
    
    @Test
    func withNothingInReachTheMedianIsUsed() {
        let performance = track([note(100, 100.5, 60, velocity: 20), note(101, 101.5, 62, velocity: 40), note(102, 102.5, 64, velocity: 100), note(103, 103.5, 65, velocity: 50)])
        let result = track([note(0, 0.5, 30)]).applyingVelocities(from: performance, warp: .identity)
        // median of 20, 40, 50, 100 is 45
        #expect(result.notes[0].velocity == 30)
        #expect(VelocityTransfer.Fill.median(of: performance.notes) == 45)
        #expect(VelocityTransfer.Fill.median(of: Array(performance.notes.prefix(3))) == 40)
    }
    
    @Test
    func aFillIsNeverBelowOne() {
        let performance = track([note(4, 4.5, 62, velocity: 10)])
        let result = track([note(4, 4.5, 60)]).applyingVelocities(from: performance, warp: .identity)
        #expect(result.notes[0].velocity == 1)
    }
    
    @Test(arguments: 0..<6)
    func fillsMatchThePlainReference(seed: Int) {
        let sheet = track(cleanInput(seed: UInt64(seed) &+ 40, count: 300))
        let (played, _, _) = perform(sheet, seed: UInt64(seed), jitter: 0, map: { $0 }, drop: { _, _, rng in rng.int(0...4) == 0 })
        let performance = track(played)
        let result = sheet.applyingVelocities(from: performance, warp: .identity)
        let partners = VelocityTransfer.partners(onsets: sheet.notes.map(\.onset), sheet: sheet.lanes, performance: performance.lanes, window: VelocityTransfer.matchWindow)
        
        var filled = 0
        for index in sheet.notes.indices where partners[index] < 0 {
            filled += 1
            #expect(result.notes[index].velocity == referenceFill(time: sheet.notes[index].onset, pitch: sheet.notes[index].pitch, performance: performance.notes))
        }
        #expect(filled > 30)
    }
    
    // MARK: Recovery
    
    @Test
    func recoveryOfAWarpedPerformanceWithMissedQuietNotes() {
        // A performance that drifts and wanders around the sheet, with 15 ms of jitter and accents of 12 around a smooth level. Like a transcriber, it misses the notes played well under their surroundings far more often: 40% of those 10 or more under the level, 1% of the others.
        let sheet = track(cleanInput(seed: 2026, count: 1500))
        let (played, velocities, dropped) = perform(sheet, seed: 11, jitter: 0.03, accent: 12, map: { 1.15 * $0 + 0.8 * sin($0 / 9) + 2 }, drop: { note, level, rng in rng.int(0...99) < (Double(note.velocity) <= level - 10 ? 40 : 1) })
        let result = sheet.applyingVelocities(from: track(played))
        
        var keptErrors: [Double] = []
        var droppedErrors: [Double] = []
        var droppedWithoutOffset: [Double] = []
        for index in sheet.notes.indices {
            let error = abs(Double(result.notes[index].velocity) - Double(velocities[index]))
            if dropped[index] {
                droppedErrors.append(error)
                droppedWithoutOffset.append(abs(Double(result.notes[index].velocity) + 15 - Double(velocities[index])))
            } else {
                keptErrors.append(error)
            }
        }
        let keptExact = keptErrors.filter { $0 == 0 }.count
        let keptMean = keptErrors.reduce(0, +) / Double(keptErrors.count)
        let droppedMean = droppedErrors.reduce(0, +) / Double(droppedErrors.count)
        let withoutOffset = droppedWithoutOffset.reduce(0, +) / Double(droppedWithoutOffset.count)
        print(String(format: "recovery: %d of %d played notes exact (mean error %.2f); %d missed notes, mean error %.1f (%.1f without the offset)", keptExact, keptErrors.count, keptMean, droppedErrors.count, droppedMean, withoutOffset))
        
        #expect(Double(keptExact) >= 0.97 * Double(keptErrors.count))
        #expect(keptMean <= 0.5)
        #expect(droppedErrors.count > 60)
        #expect(droppedMean <= 10)
        #expect(droppedMean < withoutOffset)
    }
    
    // MARK: Everything else
    
    @Test
    func onlyVelocitiesChange() {
        let container = MIDIContainer(tracks: [MIDITrack(
            notes: [note(1, 2, 60, velocity: 70), note(1, 2, 64, velocity: 70), note(3, 4.5, 62, velocity: 90)],
            sustains: [MIDISustainEvent(onset: 0.5, offset: 2.5)],
            metaEvents: [MIDIMetaEvent(timestamp: 1.5, type: 0x06, data: Data("marker".utf8))],
            controlEvents: MIDIControlEvents([MIDIControlEvent(onset: 2, channel: 1, velocity: 64)])
        )])
        let sheet = IndexedTrack(container, profile: MarkedProfile())
        let performance = track([note(1.05, 2, 60, velocity: 11), note(1, 2, 64, velocity: 22), note(3.1, 4, 62, velocity: 33)])
        let result = sheet.applyingVelocities(from: performance, warp: .identity)
        
        #expect(result.notes.map(\.velocity) == [11, 22, 33])
        for (before, after) in zip(sheet.notes, result.notes) {
            #expect(after.onset == before.onset && after.offset == before.offset && after.pitch == before.pitch && after.channel == before.channel && after.releaseVelocity == before.releaseVelocity)
        }
        #expect(result.notes.count == sheet.notes.count)
        #expect(result.sustains.contents == sheet.sustains.contents)
        #expect(result.controlEvents == sheet.controlEvents)
        #expect(result.metaEvents.map(\.data) == sheet.metaEvents.map(\.data))
        #expect(result.profile is MarkedProfile)
        #expect(result.lanes[lane: 62].map(\.velocity) == [33])
        #expect(IndexedTrack.isValid(notes: result.notes, lanes: result.lanes))
    }
    
    @Test
    func emptyTracksChangeNothing() {
        let sheet = track([note(0, 1, 60, velocity: 42)])
        #expect(sheet.applyingVelocities(from: track([])).notes == sheet.notes)
        #expect(track([]).applyingVelocities(from: sheet).notes.isEmpty)
    }
    
    @Test
    func theResultIsDeterministic() {
        let sheet = track(cleanInput(seed: 5, count: 500))
        let (played, _, _) = perform(sheet, seed: 9, jitter: 0.04, map: { 0.9 * $0 + 1 }, drop: { _, _, rng in rng.int(0...9) == 0 })
        let performance = track(played)
        #expect(sheet.applyingVelocities(from: performance).notes == sheet.applyingVelocities(from: performance).notes)
    }
    
}
