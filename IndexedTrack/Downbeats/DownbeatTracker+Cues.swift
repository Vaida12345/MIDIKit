//
//  DownbeatTracker+Cues.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Foundation
import MIDIKit


/// The evidence ``DownbeatTracker`` reads from a track: the onset envelope and the downbeat cues at any time.
struct DownbeatCues {

    /// The onsets of the notes, ascending.
    let onsets: [Double]

    /// The keys of the notes.
    let pitches: [Int]

    /// The velocities of the notes.
    let velocities: [Double]

    /// When each note stops sounding, with the pedal; or half a beat after its onset when offsets are not read.
    let soundingOffsets: [Double]

    /// The onsets of the sustains, ascending.
    let pedalOnsets: [Double]

    /// Whether the offsets are read, which decides whether the duration cue counts.
    let readsOffsets: Bool


    init(track: IndexedTrack, readsOffsets: Bool) {
        let notes = track.notes
        self.onsets = notes.map(\.onset)
        self.pitches = notes.map { Int($0.pitch) }
        self.velocities = notes.map { Double($0.velocity) }
        self.readsOffsets = readsOffsets
        let sustains = track.sustains.contents
        self.pedalOnsets = sustains.map(\.onset)
        if readsOffsets {
            // A note released while the pedal is down rings until the pedal is released.
            self.soundingOffsets = notes.map { note in
                var low = 0
                var high = sustains.count
                while low < high {
                    let middle = (low &+ high) / 2
                    if sustains[middle].onset <= note.offset { low = middle &+ 1 } else { high = middle }
                }
                if low > 0, sustains[low &- 1].offset >= note.offset { return Swift.max(note.offset, sustains[low &- 1].offset) }
                return note.offset
            }
        } else {
            self.soundingOffsets = notes.map { $0.onset + 0.5 }
        }
    }


    /// The onset envelope: each note adds a Gaussian bump, 0.04 beat wide, weighted by its velocity.
    func onsetEnvelope(frames: Int, hop: Double) -> [Double] {
        let sigma = 0.04
        var envelope = [Double](repeating: 0, count: frames)
        let radius = Int(ceil(3 * sigma / hop))
        var kernel: [Double] = []
        var offset = -radius
        while offset <= radius {
            kernel.append(exp(-0.5 * pow(Double(offset) * hop / sigma, 2)))
            offset &+= 1
        }
        var index = 0
        while index < onsets.count {
            let center = Int((onsets[index] / hop).rounded())
            let weight = 0.3 + velocities[index] / 127
            var offset = -radius
            while offset <= radius {
                let target = center &+ offset
                if target >= 0 && target < frames { envelope[target] += weight * kernel[offset &+ radius] }
                offset &+= 1
            }
            index &+= 1
        }
        return envelope
    }

    /// The first index whose value is not less than `time`.
    func lowerBound(_ values: [Double], _ time: Double) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let middle = (low &+ high) / 2
            if values[middle] < time { low = middle &+ 1 } else { high = middle }
        }
        return low
    }

    /// The pitch-class profile of the notes starting in `lower..<upper`, weighted by how long they ring and how loud they are, with the bass counted twice.
    func chroma(_ lower: Double, _ upper: Double) -> [Double] {
        var profile = [Double](repeating: 0, count: 12)
        var index = lowerBound(onsets, lower)
        while index < onsets.count && onsets[index] < upper {
            profile[pitches[index] % 12] += Swift.min(4, soundingOffsets[index] - onsets[index]) * (0.3 + velocities[index] / 127) * (pitches[index] < 55 ? 2 : 1)
            index &+= 1
        }
        return profile
    }

    /// One minus the cosine similarity of two profiles; `0` when both are empty, `1` when one is.
    static func cosineDistance(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0
        var squaresA = 0.0
        var squaresB = 0.0
        var index = 0
        while index < 12 {
            dot += a[index] * b[index]
            squaresA += a[index] * a[index]
            squaresB += b[index] * b[index]
            index &+= 1
        }
        if squaresA == 0 || squaresB == 0 { return (squaresA == 0 && squaresB == 0) ? 0 : 1 }
        return 1 - dot / sqrt(squaresA * squaresB)
    }

    /// The seven cues at `time`: bass, mass, duration, chroma change over `unit` and over twice `unit`, pedal, and gap.
    ///
    /// - Parameters:
    ///   - time: Where the cues are read, in beats.
    ///   - unit: The length of a beat, in beats.
    ///   - halfWidth: How far from `time` a note still counts as struck at `time`.
    func cues(at time: Double, unit: Double, halfWidth: Double) -> [Double] {
        var index = lowerBound(onsets, time - halfWidth)
        var lowest = 200
        var mass = 0.0
        var duration = 0.0
        while index < onsets.count && onsets[index] <= time + halfWidth {
            lowest = Swift.min(lowest, pitches[index])
            mass += velocities[index] / 64
            duration += Swift.min(4, soundingOffsets[index] - onsets[index])
            index &+= 1
        }
        let bass = lowest == 200 ? 0 : Swift.max(0, Double(66 &- lowest) / 24)
        let change = Self.cosineDistance(chroma(time - halfWidth - unit, time - halfWidth), chroma(time - halfWidth, time - halfWidth + unit))
        let wideChange = Self.cosineDistance(chroma(time - halfWidth - 2 * unit, time - halfWidth), chroma(time - halfWidth, time - halfWidth + 2 * unit))
        let pedalIndex = lowerBound(pedalOnsets, time - halfWidth)
        let pedal = (pedalIndex < pedalOnsets.count && pedalOnsets[pedalIndex] <= time + 0.5 * unit) ? 1.0 : 0.0
        let before = lowerBound(onsets, time - halfWidth)
        let gap = before > 0 ? Swift.min(2, (time - halfWidth - onsets[before &- 1]) / unit) : 1
        return [bass, log1p(mass), readsOffsets ? log1p(duration) : 0, change, wideChange, pedal, gap]
    }

}
