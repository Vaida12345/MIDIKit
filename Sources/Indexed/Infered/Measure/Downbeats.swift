//
//  Downbeat.swift
//  MIDIKit
//
//  Created by Vaida on 2025-11-13.
//

import Foundation
import Accelerate


extension IndexedContainer {

    /// Infers measure starts (downbeats) in the fixed 120-BPM beat space used by `IndexedContainer`.
    ///
    /// The returned sequence is strictly increasing, starts at `0.0`, and preserves sanitized `prior`
    /// anchors as a leading prefix.
    ///
    /// The inference does not quantize or snap notes to a grid. It uses exact event times,
    /// chord structure (`makeChord` via `chords()`), sustain-aware sounding durations, and a
    /// beam search with a piecewise-constant bar-length model. Bar length changes are penalized
    /// and only favored around structural boundaries.
    ///
    /// - Parameters:
    ///   - beatsPerMeasure: Initial bar-length prior in beats when no reliable `prior` spacing exists.
    ///   - prior: Optional annotated downbeats in beats. Valid anchors are included exactly as prefix.
    /// - Returns: Strictly increasing downbeat positions in beats.
    /// - Complexity: O(c log c + b * k * m), where `c` is chord count, `b` is beam width,
    ///   `k` is max inferred bars, and `m` is candidate options per expansion.
    public func downbeats(
        beatsPerMeasure: Double = 4,
        prior: [Double]? = nil
    ) -> [Double] {
        let anchors = Self.sanitizePrior(prior)
        var downbeats = anchors.isEmpty ? [0.0] : anchors

        let contentMax = self.contents.max(of: \.offset)
        let sustainMax = self.sustains.max(of: \.offset)
        guard let maxOffset = [contentMax, sustainMax].compactMap({ $0 }).max(), maxOffset.isFinite else {
            return downbeats
        }

        let onset = downbeats.last ?? 0.0
        if onset >= maxOffset - 1e-6 {
            return downbeats
        }

        let chords = self.chords()
        if chords.isEmpty {
            return downbeats
        }

        let features = Self.buildChordFeatures(chords: chords, sustains: self.sustains)
        if features.isEmpty {
            return downbeats
        }

        let baseBarLength = Self.estimateBaseBarLength(
            anchors: downbeats,
            beatsPerMeasure: beatsPerMeasure,
            baseline: self.baselineBarLength(beatsPerMeasure: beatsPerMeasure)
        )
        guard baseBarLength.isFinite, baseBarLength > 1e-4 else {
            return downbeats
        }

        let modeLengths = Self.barLengthModes(base: baseBarLength, features: features, anchors: downbeats)
        if modeLengths.isEmpty {
            return downbeats
        }

        let seedMode = Self.closestModeIndex(modeLengths, to: baseBarLength)
        let inferred = Self.inferDownbeats(
            from: onset,
            to: maxOffset,
            features: features,
            modeLengths: modeLengths,
            initialMode: seedMode
        )

        for value in inferred where value > (downbeats.last ?? -Double.infinity) + 1e-6 {
            downbeats.append(value)
        }

        if downbeats.first != 0 {
            downbeats.insert(0, at: 0)
        }

        return downbeats
    }

}


private extension IndexedContainer {

    struct DownbeatFeature {
        let time: Double
        let score: Double
        let boundary: Double
        let ornamentPenalty: Double
    }

    struct DownbeatCandidate {
        enum Source {
            case feature
            case synthetic
        }

        let time: Double
        let source: Source
        let localScore: Double
        let boundary: Double
        let ornamentPenalty: Double
    }

    struct DownbeatNode {
        let time: Double
        let cost: Double
        let parent: Int
        let modeIndex: Int
        let depth: Int
    }

    static func sanitizePrior(_ prior: [Double]?) -> [Double] {
        var cleaned: [Double] = [0.0]
        guard let prior else { return cleaned }

        for anchor in prior {
            guard anchor.isFinite, anchor >= 0 else { continue }
            let last = cleaned.last ?? 0
            if abs(anchor - last) <= 1e-9 {
                continue
            }
            if anchor > last {
                cleaned.append(anchor)
            }
        }

        return cleaned
    }

    static func estimateBaseBarLength(anchors: [Double], beatsPerMeasure: Double, baseline: Double) -> Double {
        if anchors.count >= 3 {
            let anchorGaps = Array(anchors.dropFirst()).enumerated().map { index, value in
                value - anchors[index]
            }.filter { $0 > 1e-6 }
            if let median = anchorGaps.median, median.isFinite, median > 1e-6 {
                return median
            }
        }

        if baseline.isFinite, baseline > 1e-6 {
            return baseline
        }

        return Swift.max(1e-3, beatsPerMeasure)
    }

    static func barLengthModes(base: Double, features: [DownbeatFeature], anchors: [Double]) -> [Double] {
        var deltas: [Double] = []

        if anchors.count >= 3 {
            for i in 1..<anchors.count {
                let gap = anchors[i] - anchors[i - 1]
                if gap > 1e-6 {
                    deltas.append(gap)
                }
            }
        }

        let strong = features.filter { $0.score > 0.9 }
        if strong.count >= 2 {
            var previous = strong[0].time
            for current in strong.dropFirst() {
                let delta = current.time - previous
                if delta > base * 0.55 && delta < base * 2.2 {
                    deltas.append(delta)
                }
                previous = current.time
            }
        }

        deltas.append(base)
        deltas.sort()

        var clusters: [[Double]] = []
        for value in deltas {
            if var last = clusters.last,
               let center = last.mean,
               abs(value - center) <= center * 0.18 {
                last.append(value)
                clusters[clusters.count - 1] = last
            } else {
                clusters.append([value])
            }
        }

        var modes = clusters.compactMap { cluster -> (count: Int, center: Double)? in
            guard let center = cluster.mean else { return nil }
            return (cluster.count, center)
        }.sorted {
            if $0.count != $1.count {
                return $0.count > $1.count
            }
            return abs($0.center - base) < abs($1.center - base)
        }.prefix(3).map { $0.center }

        if !modes.contains(where: { abs($0 - base) <= base * 0.08 }) {
            modes.append(base)
        }

        return Array(Set(modes.filter { $0.isFinite && $0 > 1e-4 })).sorted()
    }

    static func inferDownbeats(
        from start: Double,
        to maxOffset: Double,
        features: [DownbeatFeature],
        modeLengths: [Double],
        initialMode: Int
    ) -> [Double] {
        guard !features.isEmpty else { return [] }

        let maxMode = modeLengths.max() ?? 4
        let minMode = modeLengths.min() ?? 4
        let beamWidth = 20
        let switchBasePenalty = 1.2
        let spacingScale = Swift.max(0.4, minMode * 0.45)
        let minSpacing = Swift.max(0.4, minMode * 0.5)
        let maxSpacing = Swift.max(minSpacing * 1.2, maxMode * 2.4)
        let maxIterations = Swift.max(1, Int(ceil((maxOffset - start) / Swift.max(minMode, 1e-3))) + 3)

        var nodes: [DownbeatNode] = [
            DownbeatNode(time: start, cost: 0, parent: -1, modeIndex: initialMode, depth: 0)
        ]
        var frontier: [Int] = [0]
        var bestTerminal: (index: Int, score: Double)?

        for _ in 0..<maxIterations {
            var nextFrontier: [Int] = []

            for index in frontier {
                let state = nodes[index]
                let mode = modeLengths[state.modeIndex]
                let expected = state.time + mode
                let window = Swift.max(0.7, mode * 0.38)

                let options = candidateOptions(
                    expected: expected,
                    window: window,
                    lowerBound: state.time + minSpacing,
                    upperBound: state.time + maxSpacing,
                    features: features
                )
                if options.isEmpty {
                    continue
                }

                for option in options {
                    let spacing = option.time - state.time
                    if spacing <= minSpacing || spacing >= maxSpacing {
                        continue
                    }

                    for nextModeIndex in modeLengths.indices {
                        let nextMode = modeLengths[nextModeIndex]
                        let spacingCost = abs(spacing - nextMode) / spacingScale
                        let alignmentCost = abs(option.time - (state.time + nextMode)) / Swift.max(nextMode * 0.5, 0.4)

                        var switchPenalty = 0.0
                        if nextModeIndex != state.modeIndex {
                            let ratio = abs(nextMode - mode) / Swift.max(mode, 1e-4)
                            let boundaryRelief = Swift.min(0.8, option.boundary * 0.45)
                            switchPenalty = switchBasePenalty * ratio * (1 - boundaryRelief)
                        }

                        let sourcePenalty: Double = option.source == .synthetic ? 0.7 : 0.0
                        let ornamentPenalty = option.ornamentPenalty * 0.45
                        let evidenceGain = option.localScore * 1.1 + option.boundary * 0.4

                        let deltaCost = spacingCost * 1.1
                            + alignmentCost * 0.7
                            + switchPenalty
                            + sourcePenalty
                            + ornamentPenalty
                            - evidenceGain

                        let totalCost = state.cost + deltaCost
                        let node = DownbeatNode(
                            time: option.time,
                            cost: totalCost,
                            parent: index,
                            modeIndex: nextModeIndex,
                            depth: state.depth + 1
                        )
                        nodes.append(node)
                        let newIndex = nodes.count - 1
                        nextFrontier.append(newIndex)

                        if option.time + minMode * 0.45 >= maxOffset {
                            let terminalGap = abs(maxOffset - option.time)
                            let terminalScore = totalCost + terminalGap / Swift.max(nextMode, 1e-3)
                            if bestTerminal == nil || terminalScore < bestTerminal!.score {
                                bestTerminal = (newIndex, terminalScore)
                            }
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
            return []
        }

        var inferred: [Double] = []
        var cursor: Int? = targetIndex
        while let index = cursor, index > 0 {
            inferred.append(nodes[index].time)
            let parent = nodes[index].parent
            cursor = parent >= 0 ? parent : nil
        }

        inferred.reverse()

        var compacted: [Double] = []
        compacted.reserveCapacity(inferred.count)
        for time in inferred where time > start + 1e-6 {
            if let last = compacted.last, time - last <= 1e-6 {
                continue
            }
            compacted.append(time)
        }

        return compacted
    }

    static func candidateOptions(
        expected: Double,
        window: Double,
        lowerBound: Double,
        upperBound: Double,
        features: [DownbeatFeature]
    ) -> [DownbeatCandidate] {
        var options: [DownbeatCandidate] = []
        let lower = Swift.max(lowerBound, expected - window)
        let upper = Swift.min(upperBound, expected + window)

        let nearby = featuresInRange(features, lower: lower, upper: upper)
        options.reserveCapacity(nearby.count + 1)

        for feature in nearby {
            let distance = abs(feature.time - expected)
            let distanceScale = Swift.max(window, 1e-5)
            let decayedScore = feature.score * exp(-distance / distanceScale)
            options.append(
                DownbeatCandidate(
                    time: feature.time,
                    source: .feature,
                    localScore: decayedScore,
                    boundary: feature.boundary,
                    ornamentPenalty: feature.ornamentPenalty
                )
            )
        }

        let syntheticScore = syntheticEvidence(at: expected, features: features)
        options.append(
            DownbeatCandidate(
                time: expected,
                source: .synthetic,
                localScore: syntheticScore.score,
                boundary: syntheticScore.boundary,
                ornamentPenalty: syntheticScore.ornamentPenalty
            )
        )

        return options.sorted {
            let lhs = $0.localScore + $0.boundary * 0.5 - ($0.source == .synthetic ? 0.2 : 0)
            let rhs = $1.localScore + $1.boundary * 0.5 - ($1.source == .synthetic ? 0.2 : 0)
            if lhs != rhs {
                return lhs > rhs
            }
            return abs($0.time - expected) < abs($1.time - expected)
        }.prefix(8).map { $0 }
    }

    static func syntheticEvidence(at time: Double, features: [DownbeatFeature]) -> (score: Double, boundary: Double, ornamentPenalty: Double) {
        guard let nearestIndex = nearestFeatureIndex(features, to: time) else {
            return (0, 0, 0)
        }

        let nearest = features[nearestIndex]
        let distance = abs(nearest.time - time)
        if distance > 0.7 {
            return (0, 0, 0)
        }

        let decay = exp(-distance / 0.4)
        return (
            score: nearest.score * 0.6 * decay,
            boundary: nearest.boundary * 0.5 * decay,
            ornamentPenalty: nearest.ornamentPenalty * 0.5 * decay
        )
    }

    static func buildChordFeatures(chords: [Chord], sustains: MIDISustainEvents) -> [DownbeatFeature] {
        guard !chords.isEmpty else { return [] }

        var times: [Double] = []
        var avgVelocity: [Double] = []
        var bass: [Double] = []
        var size: [Double] = []
        var ioi: [Double] = []
        var physicalMaxOffset: [Double] = []
        var soundingMaxOffset: [Double] = []

        times.reserveCapacity(chords.count)
        avgVelocity.reserveCapacity(chords.count)
        bass.reserveCapacity(chords.count)
        size.reserveCapacity(chords.count)
        ioi.reserveCapacity(chords.count)
        physicalMaxOffset.reserveCapacity(chords.count)
        soundingMaxOffset.reserveCapacity(chords.count)

        for (index, chord) in chords.enumerated() {
            let onset = chord.leadingOnset
            times.append(onset)

            let count = Double(chord.count)
            size.append(count)

            var velocitySum = 0.0
            var lowest = Double.infinity
            var localPhysicalMax = onset
            var localSoundingMax = onset

            for note in chord {
                velocitySum += Double(note.velocity)
                lowest = Swift.min(lowest, Double(note.note))
                localPhysicalMax = Swift.max(localPhysicalMax, note.offset)
                localSoundingMax = Swift.max(localSoundingMax, soundingOffset(of: note, sustains: sustains))
            }

            avgVelocity.append(velocitySum / Swift.max(1.0, count))
            bass.append(lowest.isFinite ? lowest : 64)
            physicalMaxOffset.append(localPhysicalMax)
            soundingMaxOffset.append(localSoundingMax)

            if index == 0 {
                ioi.append(onset)
            } else {
                ioi.append(onset - times[index - 1])
            }
        }

        let medianVelocity = avgVelocity.median ?? 64
        let velocityScale = Swift.max(4.0, Self.medianAbsoluteDeviation(avgVelocity) ?? 10)
        let medianIOI = ioi.filter { $0 > 1e-6 }.median ?? 0.7
        let ioiScale = Swift.max(0.1, Self.medianAbsoluteDeviation(ioi.filter { $0 > 1e-6 }) ?? medianIOI * 0.5)

        var densityPrefix: [Double] = Array(repeating: 0, count: times.count + 1)
        for i in times.indices {
            densityPrefix[i + 1] = densityPrefix[i] + 1
        }

        var sustainBoundaries: [Double] = []
        sustainBoundaries.reserveCapacity(sustains.count * 2)
        for sustain in sustains {
            sustainBoundaries.append(sustain.onset)
            sustainBoundaries.append(sustain.offset)
        }
        sustainBoundaries.sort()

        var features: [DownbeatFeature] = []
        features.reserveCapacity(chords.count)

        for i in times.indices {
            let time = times[i]
            let velocityZ = (avgVelocity[i] - medianVelocity) / velocityScale
            let sizeScore = log1p(size[i])

            let bassWeight: Double
            if bass[i] <= 48 {
                bassWeight = 0.8
            } else if bass[i] <= 55 {
                bassWeight = 0.45
            } else {
                bassWeight = 0.1
            }

            let bassChange: Double
            if i == 0 {
                bassChange = 0.4
            } else {
                let delta = abs(bass[i] - bass[i - 1])
                bassChange = Swift.min(0.8, delta / 10)
            }

            let ioiGap = ioi[i]
            let ioiCue = Swift.max(0, (ioiGap - medianIOI) / ioiScale)

            let previousPhysical = i > 0 ? physicalMaxOffset[i - 1] : 0
            let previousSounding = i > 0 ? soundingMaxOffset[i - 1] : 0
            let keyGap = Swift.max(0, time - previousPhysical)
            let soundingGap = Swift.max(0, time - previousSounding)
            let phraseCue = Swift.min(1.2, keyGap * 0.9 + soundingGap * 1.1)

            let leftWindow = densityInRange(prefix: densityPrefix, times: times, lower: time - 0.8, upper: time - 0.05)
            let rightWindow = densityInRange(prefix: densityPrefix, times: times, lower: time + 0.05, upper: time + 0.8)
            let textureChange = abs(rightWindow - leftWindow) / 4.0

            let ornamentPenalty: Double = {
                let shortIOI = ioiGap < Swift.max(0.18, medianIOI * 0.55)
                let shortSupport = (soundingMaxOffset[i] - time) < 0.2
                let highRegister = bass[i] > 60
                let singleNote = size[i] <= 1
                return (shortIOI && shortSupport && highRegister && singleNote) ? 1.0 : 0.0
            }()

            let pedalBoundary = boundarySupport(at: time, boundaries: sustainBoundaries)

            let accent = 0.7 * velocityZ + 0.55 * sizeScore + 0.6 * bassWeight
            let boundary = Swift.min(2.0, 0.5 * ioiCue + 0.9 * phraseCue + 0.6 * textureChange + pedalBoundary)
            let score = accent + 0.55 * bassChange + boundary - 0.9 * ornamentPenalty

            features.append(
                DownbeatFeature(
                    time: time,
                    score: score,
                    boundary: boundary,
                    ornamentPenalty: ornamentPenalty
                )
            )
        }

        return features
    }

    static func soundingOffset(of note: ReferenceNote, sustains: MIDISustainEvents) -> Double {
        let physical = note.offset

        if let sustainIndex = sustains.index(at: physical) {
            return Swift.max(physical, sustains[sustainIndex].offset)
        }

        guard let previousIndex = sustains.lastIndex(before: physical) else {
            return physical
        }

        let previous = sustains[previousIndex]
        let next = sustains.first(after: physical)
        if previous.offset >= physical - 1 / 32,
           next.map({ $0.onset - previous.offset <= 1 / 16 }) ?? false {
            return Swift.max(physical, previous.offset)
        }

        return physical
    }

    static func boundarySupport(at time: Double, boundaries: [Double]) -> Double {
        guard !boundaries.isEmpty else { return 0 }
        var low = 0
        var high = boundaries.count
        while low < high {
            let mid = (low + high) / 2
            if boundaries[mid] < time {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var distance = Double.greatestFiniteMagnitude
        if low < boundaries.count {
            distance = Swift.min(distance, abs(boundaries[low] - time))
        }
        if low > 0 {
            distance = Swift.min(distance, abs(boundaries[low - 1] - time))
        }

        if distance > 0.25 {
            return 0
        }
        return exp(-distance / 0.08)
    }

    static func densityInRange(prefix: [Double], times: [Double], lower: Double, upper: Double) -> Double {
        if times.isEmpty || upper < lower {
            return 0
        }
        let left = lowerBound(times, target: lower)
        let right = upperBound(times, target: upper)
        if right <= left {
            return 0
        }
        return prefix[right] - prefix[left]
    }

    static func featuresInRange(_ features: [DownbeatFeature], lower: Double, upper: Double) -> ArraySlice<DownbeatFeature> {
        if features.isEmpty || upper < lower {
            return []
        }
        let times = features.map(\.time)
        let start = lowerBound(times, target: lower)
        let end = upperBound(times, target: upper)
        if end <= start {
            return []
        }
        return features[start..<end]
    }

    static func nearestFeatureIndex(_ features: [DownbeatFeature], to target: Double) -> Int? {
        guard !features.isEmpty else { return nil }

        let times = features.map(\.time)
        let right = lowerBound(times, target: target)
        if right == 0 {
            return 0
        }
        if right >= times.count {
            return times.count - 1
        }

        let left = right - 1
        return abs(times[left] - target) <= abs(times[right] - target) ? left : right
    }

    static func closestModeIndex(_ modes: [Double], to value: Double) -> Int {
        guard !modes.isEmpty else { return 0 }
        var best = 0
        var bestDistance = abs(modes[0] - value)

        for index in 1..<modes.count {
            let distance = abs(modes[index] - value)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }

        return best
    }

    static func lowerBound(_ values: [Double], target: Double) -> Int {
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

    static func upperBound(_ values: [Double], target: Double) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let mid = (low + high) / 2
            if values[mid] <= target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
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
