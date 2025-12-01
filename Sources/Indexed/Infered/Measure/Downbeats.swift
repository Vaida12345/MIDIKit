//
//  Downbeat.swift
//  MIDIKit
//
//  Created by Vaida on 2025-11-13.
//

import Foundation


extension IndexedContainer {
    
    /// Calculates the start of each measure in beats.
    ///
    /// This function relies on sustains to calculate downbeats.
    ///
    /// - Note: inaccurate.
    ///
    /// - Parameters:
    ///   - beatsPerMeasure: Number of beats in a measure. This value is ignored if prior is specified.
    ///   - prior: If you already know the first few measures are like, pass to inform inference.
    public func downbeats(
        beatsPerMeasure: Double = 4,
        prior: [Double]? = nil
    ) -> [Double] {
        var downbeats: [Double]
        let idealMeasureWidth: Double
        var onset: Double
        
        if let prior, prior.count > 1 {
            downbeats = prior
            let beatsPerMeasure = downbeats.gaps()
            idealMeasureWidth = self.baselineBarLength(beatsPerMeasure: beatsPerMeasure.mean!)
            onset = prior.last!
        } else {
            downbeats = [0]
            idealMeasureWidth = self.baselineBarLength(beatsPerMeasure: beatsPerMeasure)
            onset = 0
        }
        
        let chords = self.chords()
        let chordOnsets = chords.map { $0.leadingOnset }
        let sustainOnsets = self.sustains.map { $0.onset }
        
        let contentMax = self.contents.max(of: \.offset)
        let sustainMax = self.sustains.max(of: \.offset)
        guard let maxOffset = [contentMax, sustainMax].compactMap({ $0 }).max() else {
            return downbeats
        }
        guard idealMeasureWidth > 0, onset < maxOffset else { return downbeats }
        
        struct Candidate {
            enum Source {
                case chord
                case sustain
                case synthetic
            }
            let position: Double
            let penalty: Double
            let source: Source
        }
        
        struct Node {
            let position: Double
            let cost: Double
            let parent: Int
            let depth: Int
        }
        
        func lowerBound(_ values: [Double], target: Double) -> Int {
            var low = 0
            var high = values.count
            while low < high {
                let mid = (low + high) / 2
                if values[mid] < target {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            return low
        }
        
        func values(in array: [Double], lower: Double, upper: Double) -> ArraySlice<Double> {
            guard !array.isEmpty else { return [] }
            let start = lowerBound(array, target: lower)
            var end = start
            while end < array.count && array[end] <= upper {
                end += 1
            }
            return array[start..<end]
        }
        
        func candidates(around target: Double, window: Double) -> [Candidate] {
            var entries: [Double: (penalty: Double, source: Candidate.Source)] = [:]
            func record(_ position: Double, penalty: Double, source: Candidate.Source) {
                if let current = entries[position], current.penalty <= penalty { return }
                entries[position] = (penalty, source)
            }
            let lower = target - window
            let upper = target + window
            let chordSlice = values(in: chordOnsets, lower: lower, upper: upper)
            for onset in chordSlice {
                let deviation = abs(onset - target) / Swift.max(window, 1.0)
                record(onset, penalty: 0.05 + deviation * 0.1, source: .chord)
            }
            let sustainSlice = values(in: sustainOnsets, lower: lower, upper: upper)
            for onset in sustainSlice {
                let deviation = abs(onset - target) / Swift.max(window, 1.0)
                record(onset, penalty: 0.025 + deviation * 0.08, source: .sustain)
            }
            record(target, penalty: 0.35, source: .synthetic)
            return entries.map { Candidate(position: $0.key, penalty: $0.value.penalty, source: $0.value.source) }
                .sorted { abs($0.position - target) < abs($1.position - target) }
        }
        
        let spacingFloor = Swift.max(idealMeasureWidth * 0.25, 1e-3)
        let window = Swift.max(idealMeasureWidth * 0.75, 1.0)
        let alignmentScale = Swift.max(idealMeasureWidth * 0.4, 1.0)
        let spacingScale = Swift.max(idealMeasureWidth * 0.75, 1.0)
        let sustainAlignmentTolerance = Swift.max(idealMeasureWidth * 0.1, 1.0 / 48)
        let maxIterations = Swift.max(1, Int(ceil((maxOffset - onset) / Swift.max(idealMeasureWidth, 1e-3))) + 2)
        let beamWidth = 12
        
        var nodes: [Node] = [Node(position: onset, cost: 0, parent: -1, depth: 0)]
        var frontier: [Int] = [0]
        var bestTerminal: (index: Int, score: Double)?
        
        for _ in 0..<maxIterations {
            var nextFrontier: [Int] = []
            for stateIndex in frontier {
                let state = nodes[stateIndex]
                let expected = state.position + idealMeasureWidth
                let options = candidates(around: expected, window: window)
                let hasPreferredSustain = options.contains {
                    $0.source == .sustain && abs($0.position - expected) <= sustainAlignmentTolerance
                }
                for option in options {
                    let spacing = option.position - state.position
                    if spacing <= spacingFloor { continue }
                    let spacingCost = abs(spacing - idealMeasureWidth) / spacingScale
                    let alignmentCost = abs(option.position - expected) / alignmentScale
                    let nearIdealSpacing = abs(spacing - idealMeasureWidth) <= sustainAlignmentTolerance * 2
                    var sustainBias = 0.0
                    if option.source == .sustain && nearIdealSpacing {
                        sustainBias -= 0.25
                    } else if hasPreferredSustain && option.source != .sustain && nearIdealSpacing {
                        sustainBias += 0.2
                    }
                    let totalCost = state.cost + spacingCost * 0.85 + alignmentCost * 0.25 + option.penalty + sustainBias
                    let node = Node(position: option.position, cost: totalCost, parent: stateIndex, depth: state.depth + 1)
                    nodes.append(node)
                    let newIndex = nodes.count - 1
                    nextFrontier.append(newIndex)
                    if option.position + spacingFloor >= maxOffset {
                        let terminalScore = totalCost + abs(maxOffset - option.position) / spacingScale
                        if bestTerminal == nil || terminalScore < bestTerminal!.score {
                            bestTerminal = (newIndex, terminalScore)
                        }
                    }
                }
            }
            if nextFrontier.isEmpty {
                break
            }
            nextFrontier.sort { nodes[$0].cost < nodes[$1].cost }
            if nextFrontier.count > beamWidth {
                nextFrontier.removeSubrange(beamWidth..<nextFrontier.count)
            }
            frontier = nextFrontier
        }
        
        let targetIndex: Int
        if let bestTerminal {
            targetIndex = bestTerminal.index
        } else if let fallback = frontier.min(by: { nodes[$0].cost < nodes[$1].cost }) {
            targetIndex = fallback
        } else {
            return downbeats
        }
        
        var reconstructed: [Double] = []
        var cursor: Int? = targetIndex
        while let index = cursor, index > 0 {
            let node = nodes[index]
            reconstructed.append(node.position)
            cursor = nodes[index].parent >= 0 ? nodes[index].parent : nil
        }
        let additions = reconstructed.reversed().filter { $0 > onset + 1e-6 }
        downbeats.append(contentsOf: additions)
        
        return downbeats
    }
    
}


extension Sequence {
    
    func iterate(
        _ body: (_ curr: Element, _ next: Element?) -> Void
    ) {
        var iterator = self.makeIterator()
        var _curr = iterator.next()
        var next = iterator.next()
        
        while let curr = _curr {
            body(curr, next)
            _curr = next
            next = iterator.next()
        }
    }
    
}


extension Array<Double> {
    
    func gaps() -> [Double] {
        let sorted = self.sorted()
        guard sorted.count > 1 else { return [] }
        var gaps: [Double] = []
        gaps.reserveCapacity(sorted.count - 1)
        
        sorted.iterate { curr, next in
            if let next = next {
                gaps.append(next - curr)
            }
        }
        
        return gaps
    }
    
}
