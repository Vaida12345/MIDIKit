import CoreMIDI
import Foundation

enum EngravingMath {
    static func add(_ a: Double, _ b: Double) -> Double {
        if a == -.infinity { return b }
        if b == -.infinity { return a }
        let high = max(a, b)
        return high + log1p(exp(min(a, b) - high))
    }
    static func sum<S: Sequence>(_ values: S) -> Double where S.Element == Double {
        values.reduce(-Double.infinity, add)
    }
}

struct EngravingAssignment: Hashable {
    var offset: Int
    var pitches: UInt128
    var firstTime: MIDITimeStamp
    var lastTime: MIDITimeStamp
}

struct EngravingPath: Hashable {
    enum Hands: UInt8, CaseIterable { case left, right, both }
    var current: EngravingAssignment
    var previous: EngravingAssignment?
    var hands: Hands
    var episode: UInt64
    var start: Int
    var onsets = 1
    var onsetEvidence = 0.0
    var tempo = EngravingTempo()
    var errors = 0
    var recentFit: [Double] = []
    var matched = true
    var advanced = false
    var trailing = false
    var skippedAttacks = false
    var recoveryOnsets = 0
    var omittedAttacks = 0
    var omissionStart: Int?
    var lastObservation: UInt64
    var lastAttack: UInt8
    var leftAssignments = 0
    var rightAssignments = 0

    var fit: Double {
        let values = recentFit + [exp(-0.65 * Double(errors))]
        return values.reduce(0, +) / Double(values.count)
    }

    func mask(_ moment: EngravingScoreIndex.Moment) -> UInt128 {
        switch hands {
        case .left: moment.left
        case .right: moment.right
        case .both: moment.pitches
        }
    }

    mutating func recordHand(_ pitch: UInt128, moment: EngravingScoreIndex.Moment) {
        // Shared pitches supply no independent hand identity.
        if moment.left & pitch != 0 && moment.right & pitch == 0 { leftAssignments = min(16, leftAssignments + 1) }
        if moment.right & pitch != 0 && moment.left & pitch == 0 { rightAssignments = min(16, rightAssignments + 1) }
    }
}

struct EngravingWeightedPath {
    var path: EngravingPath
    var logMass: Double
}

/// An envelope covers *all* descendants of discarded paths, including their insertion branch.
/// Ranges may overestimate reachability. This weakens support but cannot certify a false tie.
struct EngravingResidual {
    var range: ClosedRange<Int>
    var logMass: Double
    var episode: UInt64? = nil
    var coherent = false
    var fresh = false
    var onsets = 0
    var separation = 0.0
    var onsetTime: MIDITimeStamp = 0
    var played: UInt128 = 0
    var possiblePlayed: UInt128 = .max
}

struct EngravingEvidence {
    let paths: [EngravingWeightedPath]
    let residualLogMass: Double
    let noiseLogMass: Double
    let totalLogMass: Double
    let best: EngravingPath?
    var residuals: [EngravingResidual] = []

    func support(where predicate: (EngravingPath) -> Bool,
                 compatibleResidual: (EngravingResidual) -> Bool = { _ in false }) -> Double {
        let mass = EngravingMath.sum(paths.filter { predicate($0.path) }.map(\.logMass))
        let opposingResidual = residuals.isEmpty ? residualLogMass : EngravingMath.sum(residuals.filter { !compatibleResidual($0) }.map(\.logMass))
        let denominator = EngravingMath.add(EngravingMath.sum(paths.map(\.logMass)), EngravingMath.add(opposingResidual, noiseLogMass))
        guard mass.isFinite, denominator.isFinite else { return 0 }
        return min(1, max(0, exp(mass - denominator)))
    }

    // Unknown nonnegative mass known to support the same proposition cannot lower its
    // probability. Minimize at zero for that mass, and at the upper bound for opposing mass.
    func exact(_ offset: Int) -> Double {
        support(where: { $0.current.offset == offset }, compatibleResidual: { $0.range == offset...offset })
    }
    func episode(_ episode: UInt64, at offset: Int) -> Double {
        support(where: { $0.episode == episode && $0.current.offset == offset },
                compatibleResidual: { $0.episode == episode && $0.range == offset...offset })
    }
    func mode(_ path: EngravingPath) -> Double {
        support(where: { $0.episode == path.episode && abs($0.current.offset - path.current.offset) <= 2 },
                compatibleResidual: { $0.episode == path.episode && $0.coherent && $0.range.lowerBound >= path.current.offset - 2 && $0.range.upperBound <= path.current.offset + 2 })
    }
    func acquisitionMode(_ path: EngravingPath) -> Double {
        support(where: { abs($0.current.offset - path.current.offset) <= 2 && $0.fit >= 0.55 },
                compatibleResidual: { $0.coherent && $0.range.lowerBound >= path.current.offset - 2 && $0.range.upperBound <= path.current.offset + 2 })
    }
    var noiseSupport: Double {
        totalLogMass.isFinite ? exp(noiseLogMass - totalLogMass) : 1
    }
}

struct EngravingFilter {
    static let insertionProbability = 0.025
    static let noiseEmission = insertionProbability / 128
    var limits = EngravingLimits()
    private(set) var paths: [EngravingWeightedPath] = []
    private(set) var residuals: [EngravingResidual] = []
    private(set) var history: [EngravingInputState.Observation] = []
    private(set) var expansions = 0
    private(set) var destinations = 0
    private(set) var peakPaths = 0
    private(set) var noiseLogMass = -Double.infinity
    private var hint: ClosedRange<Double>?
    private var hintOffsets = 0..<0
    private var hasStarted = false
    private var searchFocus: ClosedRange<Int>?
    private var activeReach = 8
    var committedEpisode: UInt64?
    var committedOffset: Int?

    mutating func acquire(_ path: EngravingPath, preservingEpisode: UInt64? = nil) {
        // Before acquisition, different noise-prefix lengths can reach the same occurrence.
        // Give those paths a common continuity identity without pooling their onset evidence.
        for i in paths.indices where paths[i].path.current.offset == path.current.offset && paths[i].path.fit >= 0.55
            && paths[i].path.episode != preservingEpisode {
            paths[i].path.episode = path.episode
        }
        for i in residuals.indices where residuals[i].range == path.current.offset...path.current.offset && residuals[i].coherent
            && residuals[i].episode != preservingEpisode {
            residuals[i].episode = path.episode
        }
        committedEpisode = path.episode
        committedOffset = path.current.offset
    }

    mutating func refreshHint(_ range: ClosedRange<Double>?, score: EngravingScoreIndex) {
        guard committedEpisode == nil else { return }
        let next = score.usable(range)
        guard next != hint else { return }
        let offsets = score.visibleOffsets(next)
        if hasStarted {
            for i in paths.indices {
                let start = paths[i].path.start
                paths[i].logMass += log(prior(start, visible: offsets, count: score.moments.count))
                    - log(prior(start, visible: hintOffsets, count: score.moments.count))
            }
            // A residual may contain several starting positions. Apply the largest prior ratio.
            // This is intentionally conservative; visibility never erases search uncertainty.
            let oldInside = prior(hintOffsets.lowerBound, visible: hintOffsets, count: score.moments.count)
            let oldOutside = hintOffsets.isEmpty ? oldInside : 0.2 / Double(max(1, score.moments.count - hintOffsets.count))
            let newInside = offsets.isEmpty ? 1 / Double(score.moments.count) : 0.8 / Double(offsets.count)
            let newOutside = offsets.isEmpty ? newInside : 0.2 / Double(max(1, score.moments.count - offsets.count))
            let ratio = max(newInside, newOutside) / min(oldInside, oldOutside)
            for i in residuals.indices { residuals[i].logMass += log(max(1, ratio)) }
        }
        hint = next
        hintOffsets = offsets
    }

    private func prior(_ offset: Int, visible: Range<Int>, count: Int) -> Double {
        guard !visible.isEmpty, visible.count < count else { return 1 / Double(count) }
        return visible.contains(offset) ? 0.8 / Double(visible.count) : 0.2 / Double(count - visible.count)
    }

    private func postingPriorMass(_ pitch: UInt8, indices: Range<Int>, score: EngravingScoreIndex) -> Double {
        guard committedEpisode == nil, !hintOffsets.isEmpty, hintOffsets.count < score.moments.count else {
            return Double(indices.count) / Double(score.moments.count)
        }
        let values = score.postings[Int(pitch)]
        func bound(_ value: Int) -> Int {
            var low = indices.lowerBound, high = indices.upperBound
            while low < high {
                let middle = (low + high) / 2
                if values[middle] < value { low = middle + 1 } else { high = middle }
            }
            return low
        }
        let inside = bound(hintOffsets.upperBound) - bound(hintOffsets.lowerBound)
        return Double(inside) * 0.8 / Double(hintOffsets.count)
            + Double(indices.count - inside) * 0.2 / Double(score.moments.count - hintOffsets.count)
    }

    /// Revisit a still-private bounded prefix when an indexed distinguishing attack arrives.
    /// This changes retrieval allocation, not the prior or the observations being compared.
    /// Every omitted occurrence is reintroduced as residual mass in the replay.
    mutating func refineAcquisition(score: EngravingScoreIndex, calibration: EngravingCalibration) {
        guard committedEpisode == nil, history.count <= 16, history.count >= 2,
              let pitch = history.last?.attack, let first = score.postings[Int(pitch)].first,
              let last = score.postings[Int(pitch)].last, score.postings[Int(pitch)].count <= 4,
              evidence().residualLogMass > log(0.01) else { return }
        let attacks = history.filter { $0.attack != nil }.count
        let remainingDestinations = limits.destinations - destinations
        let remainingWork = limits.expansions - expansions
        guard attacks > 0, remainingDestinations >= attacks, remainingWork >= attacks * 128 else { return }
        var replay = EngravingFilter()
        replay.limits = limits
        replay.limits.destinations = remainingDestinations / attacks
        replay.searchFocus = max(0, first - attacks * limits.localReach)...last
        replay.refreshHint(hint, score: score)
        var work = expansions
        var queries = destinations
        var attacksLeft = attacks
        for event in history {
            if event.attack != nil {
                replay.limits.expansions = limits.expansions - work - max(0, attacksLeft - 1) * 128
                attacksLeft -= 1
            }
            _ = replay.consume(event, score: score, calibration: calibration, lost: false)
            work += replay.expansions
            queries += replay.destinations
        }
        expansions = work
        destinations = queries
        guard work <= limits.expansions, queries <= limits.destinations,
              replay.evidence().residualLogMass < evidence().residualLogMass else { return }
        replay.limits = limits
        replay.expansions = work
        replay.destinations = queries
        replay.peakPaths = max(peakPaths, replay.peakPaths)
        replay.searchFocus = nil
        self = replay
    }

    mutating func consume(_ observation: EngravingInputState.Observation, score: EngravingScoreIndex,
                          calibration: EngravingCalibration, lost: Bool) -> EngravingEvidence {
        history.append(observation)
        if history.count > limits.history { history.removeFirst(history.count - limits.history) }
        expansions = 0
        destinations = 0
        activeReach = lost ? min(16, limits.localReach * 2) : limits.localReach
        if observation.discontinuity {
            for i in paths.indices { paths[i].path.tempo.detach() }
        }
        guard let pitch = observation.attack else {
            refineRelease(observation, score: score)
            return evidence()
        }
        let bit = EngravingScoreIndex.mask(pitch)
        let oldTotal = EngravingMath.add(EngravingMath.sum(paths.map(\.logMass)), noiseLogMass)
        // All branches use the same preceding evidence scale. A fresh change point receives
        // the mixture evidence, never a likelihood from an unrelated shorter suffix.
        let base = oldTotal.isFinite ? oldTotal : 0
        let hazard = !hasStarted ? 1.0 : committedEpisode == nil ? 0.12 : lost ? 0.04 : 0.001
        let logContinuity = log(max(0, 1 - hazard - 0.0001))
        var generated: [EngravingWeightedPath] = []
        generated.reserveCapacity(limits.expansions)
        var nextResiduals: [EngravingResidual] = []
        let reach = activeReach
        for residual in residuals {
            propagate(residual, observation: observation, score: score, calibration: calibration,
                      logContinuity: logContinuity, into: &nextResiduals)
        }
        if let first = score.postings[Int(pitch)].first, let last = score.postings[Int(pitch)].last, !residuals.isEmpty {
            // The unrepresented preceding evidence also has a change-point branch. Its mass
            // stays an upper envelope; it must not become represented destination evidence.
            let seedBound = min(1, postingPriorMass(pitch, indices: 0..<score.postings[Int(pitch)].count, score: score) * (1 - Self.insertionProbability))
            nextResiduals.append(EngravingResidual(range: first...last,
                logMass: EngravingMath.sum(residuals.map(\.logMass)) + log(hazard) + log(seedBound),
                episode: observation.id, coherent: true, fresh: true, onsets: 1, onsetTime: observation.timestamp,
                played: bit, possiblePlayed: bit))
        }
        for weighted in paths {
            let possible = weighted.path.current.offset...min(score.moments.count - 1, weighted.path.current.offset + reach)
            let previousPitches = weighted.path.previous.map { score.moments[$0.offset].pitches } ?? 0
            if (score.pitches(in: possible) | previousPitches) & bit == 0 {
                var noise = weighted.path
                noise.matched = false
                noise.advanced = false
                noise.errors = min(32, noise.errors + 1)
                noise.lastObservation = observation.id
                generated.append(EngravingWeightedPath(path: noise,
                    logMass: weighted.logMass + logContinuity + log(Self.noiseEmission)))
                expansions += 1
                continue
            }
            if expansions >= limits.expansions - limits.destinations * 3 - paths.count - 64 {
                let range = max(0, weighted.path.current.offset - 16)...min(score.moments.count - 1, weighted.path.current.offset + reach)
                let upper = score.pitches(in: range) & bit == 0 ? Self.noiseEmission : 1.0
                nextResiduals.append(EngravingResidual(range: range, logMass: weighted.logMass + logContinuity + log(upper)))
                continue
            }
            expand(weighted, observation: observation, bit: bit, score: score, calibration: calibration,
                   logContinuity: logContinuity, into: &generated)
        }

        // Prefix noise is score-less. A new episode starts at its first explained attack;
        // initial errors therefore cannot contaminate all subsequent acquisition candidates.
        seed(pitch, observation: observation, score: score, logMass: base + log(hazard),
             into: &generated, residuals: &nextResiduals)
        noiseLogMass = EngravingMath.add(noiseLogMass + logContinuity - log(128), base + log(0.0001 / 128))
        hasStarted = true
        prune(generated, into: &nextResiduals)
        residuals = compact(nextResiduals)
        normalize()
        return evidence()
    }

    private mutating func expand(_ weighted: EngravingWeightedPath, observation: EngravingInputState.Observation,
                                 bit: UInt128, score: EngravingScoreIndex, calibration: EngravingCalibration,
                                 logContinuity: Double, into output: inout [EngravingWeightedPath]) {
        let source = weighted.path
        let offset = source.current.offset
        let moment = score.moments[offset]
        let remaining = source.mask(moment) & ~source.current.pitches
        var noise = source
        noise.matched = false
        noise.advanced = false
        noise.trailing = false
        noise.errors = min(32, noise.errors + 1)
        noise.lastObservation = observation.id
        output.append(EngravingWeightedPath(path: noise, logMass: weighted.logMass + logContinuity + log(Self.noiseEmission)))
        expansions += 1

        struct Transition {
            var offset: Int
            var hands: EngravingPath.Hands
            var mask: UInt128
            var weight: Double
            var kind: Int // 0 extension, 1 restrike, 2 progression, 3 trailing hand
            var omissions: Int = 0
        }
        var transitions: [Transition] = []
        let spread = exp(moment.rolled ? calibration.rolledSpread : calibration.blockSpread)
        var extensionWeight = 0.80
        if let elapsed = EngravingHostTime.seconds(from: source.current.firstTime, to: observation.timestamp) {
            // No deadline: the heavy tail always retains a rolled/current-onset explanation.
            extensionWeight *= 0.08 + 0.92 / (1 + pow(elapsed / (spread * 3), 2))
        }
        if remaining != 0 { transitions.append(Transition(offset: offset, hands: source.hands, mask: remaining, weight: extensionWeight, kind: 0)) }
        transitions.append(Transition(offset: offset, hands: source.hands, mask: source.mask(moment),
                                      weight: remaining == 0 ? 0.12 : 0.025, kind: 1))
        if let previous = source.previous {
            let missing = source.mask(score.moments[previous.offset]) & ~previous.pitches
            if missing != 0 {
                var lagWeight = 0.18
                if let elapsed = EngravingHostTime.seconds(from: previous.firstTime, to: observation.timestamp) {
                    lagWeight *= 0.1 + 0.9 / (1 + pow(elapsed / (exp(calibration.handSpread) * 3), 2))
                }
                transitions.append(Transition(offset: previous.offset, hands: source.hands, mask: missing, weight: lagWeight, kind: 3))
            }
        }
        let last = min(score.moments.count - 1, offset + activeReach)
        if last > offset {
            for target in (offset + 1)...last {
                let missing = remaining.nonzeroBitCount
                let coverageCost = exp(-0.35 * Double(min(4, missing)))
                let skip = target - offset - 1
                // Omission costs depend on relevant lane attacks, not line geometry.
                var relevantSkip = 0
                if skip > 0 {
                    for omitted in (offset + 1)..<target where source.mask(score.moments[omitted]) != 0 { relevantSkip += 1 }
                }
                let weight = (remaining == 0 ? 0.86 : 0.16) * coverageCost * pow(0.12, Double(relevantSkip))
                    * source.tempo.compatibility(beat: score.moments[target].beat, time: observation.timestamp)
                for hands in EngravingPath.Hands.allCases {
                    var alternative = source
                    alternative.hands = hands
                    let mask = alternative.mask(score.moments[target])
                    if mask != 0 {
                        transitions.append(Transition(offset: target, hands: hands, mask: mask,
                                                      weight: weight * (hands == source.hands ? 0.98 : 0.01), kind: 2, omissions: relevantSkip))
                    }
                }
            }
        }
        let total = transitions.reduce(0.0) { $0 + $1.weight }
        for transition in transitions {
            expansions += 1
            guard transition.mask & bit != 0, total > 0 else { continue }
            var path = source
            path.hands = transition.hands
            path.matched = true
            path.advanced = transition.kind == 2
            path.trailing = transition.kind == 3
            path.lastObservation = observation.id
            path.lastAttack = observation.attack!
            if transition.kind == 2 {
                path.recentFit.append(exp(-0.65 * Double(path.errors)))
                if path.recentFit.count > 3 { path.recentFit.removeFirst() }
                path.errors = 0
                path.previous = source.current
                path.current = EngravingAssignment(offset: transition.offset, pitches: bit,
                                                  firstTime: observation.timestamp, lastTime: observation.timestamp)
                path.onsets = min(1_024, path.onsets + 1)
                path.skippedAttacks = source.skippedAttacks || transition.offset > offset + 1
                path.recoveryOnsets = transition.offset > offset + 1 ? 1 : source.recoveryOnsets > 0 ? min(1_024, source.recoveryOnsets + 1) : 0
                if transition.omissions > 0 {
                    path.omittedAttacks = transition.omissions
                    path.omissionStart = offset + 1
                }
                // Sequence and tempo compete with the possibility of a single spread cohort.
                // Equal/invalid timestamps add no separation evidence.
                if let elapsed = EngravingHostTime.seconds(from: source.current.firstTime, to: observation.timestamp) {
                    path.onsetEvidence += log1p(elapsed / exp(calibration.rolledSpread))
                } else if source.current.pitches & bit == 0 {
                    path.onsetEvidence += log(1.5)
                }
                path.tempo.observe(beat: score.moments[transition.offset].beat, time: observation.timestamp)
            } else if transition.kind == 3 {
                path.previous?.pitches |= bit
                path.previous?.lastTime = observation.timestamp
            } else {
                path.current.pitches |= bit
                path.current.lastTime = observation.timestamp
            }
            path.recordHand(bit, moment: score.moments[transition.offset])
            let emission = (1 - Self.insertionProbability) / Double(transition.mask.nonzeroBitCount)
            output.append(EngravingWeightedPath(path: path,
                logMass: weighted.logMass + logContinuity + log(transition.weight / total) + log(emission)))
        }
    }

    private mutating func seed(_ pitch: UInt8, observation: EngravingInputState.Observation,
                              score: EngravingScoreIndex, logMass: Double,
                              into output: inout [EngravingWeightedPath], residuals: inout [EngravingResidual]) {
        let posting = score.postings[Int(pitch)]
        guard !posting.isEmpty else { return }
        // Select a bounded union: visible occurrences, ordinary posting order, and a rotating
        // deterministic sample. Selection changes representation, never the denominator.
        var selected: Set<Int> = []
        let cap = limits.destinations
        if let searchFocus, committedEpisode == nil {
            var low = 0, high = posting.count
            while low < high {
                let middle = (low + high) / 2
                if posting[middle] < searchFocus.lowerBound { low = middle + 1 } else { high = middle }
            }
            var cursor = low
            while cursor < posting.count, posting[cursor] <= searchFocus.upperBound, selected.count < cap {
                selected.insert(cursor); cursor += 1
            }
        }
        if !hintOffsets.isEmpty && committedEpisode == nil {
            var low = 0
            var high = posting.count
            while low < high {
                let middle = (low + high) / 2
                if posting[middle] < hintOffsets.lowerBound { low = middle + 1 } else { high = middle }
            }
            var cursor = low
            while cursor < posting.count, hintOffsets.contains(posting[cursor]), selected.count < cap / 2 {
                selected.insert(cursor)
                cursor += 1
            }
        }
        if searchFocus == nil || committedEpisode != nil {
            for i in 0..<min(posting.count, cap / 2) where selected.count < cap { selected.insert(i) }
            let start = Int(observation.id % UInt64(posting.count))
            for step in 0..<min(posting.count, cap) where selected.count < cap { selected.insert((start + step) % posting.count) }
        }
        let ordered = selected.sorted()
        destinations = ordered.count
        let bit = EngravingScoreIndex.mask(pitch)
        for postingOffset in ordered {
            let offset = posting[postingOffset]
            let moment = score.moments[offset]
            let destinationPrior = committedEpisode == nil ? prior(offset, visible: hintOffsets, count: score.moments.count) : 1 / Double(score.moments.count)
            for hands in EngravingPath.Hands.allCases {
                var path = EngravingPath(current: EngravingAssignment(offset: offset, pitches: bit,
                    firstTime: observation.timestamp, lastTime: observation.timestamp), hands: hands,
                    episode: observation.id, start: offset, lastObservation: observation.id, lastAttack: pitch)
                let expected = path.mask(moment)
                guard expected & bit != 0 else { continue }
                expansions += 1
                path.recordHand(bit, moment: moment)
                path.tempo.observe(beat: moment.beat, time: observation.timestamp)
                output.append(EngravingWeightedPath(path: path, logMass: logMass + log(destinationPrior)
                    + log(1.0 / 3) + log((1 - Self.insertionProbability) / Double(expected.nonzeroBitCount))))
            }
        }
        // The unselected posting runs are represented without iterating over their elements.
        var cursor = 0
        for selectedOffset in ordered + [posting.count] {
            if cursor < selectedOffset {
                let range = posting[cursor]...posting[selectedOffset - 1]
                residuals.append(EngravingResidual(range: range, logMass: logMass
                    + log(postingPriorMass(pitch, indices: cursor..<selectedOffset, score: score) * (1 - Self.insertionProbability)),
                    episode: observation.id, coherent: true, fresh: true, onsets: 1, onsetTime: observation.timestamp,
                    played: bit, possiblePlayed: bit))
            }
            cursor = selectedOffset + 1
        }
    }

    private mutating func prune(_ generated: [EngravingWeightedPath], into residuals: inout [EngravingResidual]) {
        var positions: [EngravingPath: Int] = [:]
        var merged: [EngravingWeightedPath] = []
        for item in generated {
            if let i = positions[item.path] { merged[i].logMass = EngravingMath.add(merged[i].logMass, item.logMass) }
            else { positions[item.path] = merged.count; merged.append(item) }
        }
        let sorted = merged.sorted(by: Self.ordered)
        var retained: [EngravingWeightedPath] = []
        var used: Set<Int> = []
        var counts: [Int: Int] = [:]
        // Destination diversity first; reserve half the beam for each episode class.
        for incumbent in [true, false] {
            // Reserve diversity in half the slots, leaving room for meaningful hand/onset
            // alternatives at the leading destinations in the other half.
            let capacity = max(1, limits.hypotheses / 4)
            var taken = 0
            var offsets: Set<Int> = []
            for (i, item) in sorted.enumerated() where (item.path.episode == committedEpisode) == incumbent {
                guard taken < capacity else { break }
                if offsets.insert(item.path.current.offset).inserted {
                    retained.append(item); used.insert(i); taken += 1
                    counts[item.path.current.offset, default: 0] += 1
                }
            }
        }
        for (i, item) in sorted.enumerated() where !used.contains(i) {
            if retained.count < limits.hypotheses && counts[item.path.current.offset, default: 0] < limits.perDestination {
                retained.append(item)
                counts[item.path.current.offset, default: 0] += 1
            } else {
                residuals.append(EngravingResidual(range: item.path.current.offset...item.path.current.offset, logMass: item.logMass,
                    episode: item.path.episode, coherent: item.path.fit >= 0.55, fresh: item.path.matched,
                    onsets: item.path.onsets, separation: item.path.onsetEvidence, onsetTime: item.path.current.firstTime,
                    played: item.path.current.pitches, possiblePlayed: item.path.current.pitches))
            }
        }
        paths = retained.sorted(by: Self.ordered)
        peakPaths = max(peakPaths, paths.count)
    }

    private static func ordered(_ lhs: EngravingWeightedPath, _ rhs: EngravingWeightedPath) -> Bool {
        if lhs.logMass != rhs.logMass { return lhs.logMass > rhs.logMass }
        let a = lhs.path, b = rhs.path
        if a.current.offset != b.current.offset { return a.current.offset < b.current.offset }
        if a.episode != b.episode { return a.episode < b.episode }
        if a.hands != b.hands { return a.hands.rawValue < b.hands.rawValue }
        if a.current.pitches != b.current.pitches { return a.current.pitches < b.current.pitches }
        if a.onsets != b.onsets { return a.onsets < b.onsets }
        if a.errors != b.errors { return a.errors < b.errors }
        if a.previous?.offset != b.previous?.offset { return (a.previous?.offset ?? -1) < (b.previous?.offset ?? -1) }
        return a.lastObservation < b.lastObservation
    }

    private func compact(_ values: [EngravingResidual]) -> [EngravingResidual] {
        let sorted = values.sorted {
            if $0.range.lowerBound != $1.range.lowerBound { return $0.range.lowerBound < $1.range.lowerBound }
            if $0.range.upperBound != $1.range.upperBound { return $0.range.upperBound < $1.range.upperBound }
            if $0.episode != $1.episode { return ($0.episode ?? 0) < ($1.episode ?? 0) }
            if $0.coherent != $1.coherent { return !$0.coherent }
            return !$0.fresh && $1.fresh
        }
        var result: [EngravingResidual] = []
        for value in sorted {
            if let last = result.last, value.range == last.range, value.episode == last.episode,
               value.coherent == last.coherent, value.fresh == last.fresh {
                result[result.count - 1] = EngravingResidual(range: last.range.lowerBound...max(last.range.upperBound, value.range.upperBound),
                    logMass: EngravingMath.add(last.logMass, value.logMass), episode: last.episode, coherent: last.coherent, fresh: last.fresh,
                    onsets: min(last.onsets, value.onsets), separation: min(last.separation, value.separation),
                    onsetTime: last.onsetTime == value.onsetTime ? last.onsetTime : 0,
                    played: last.played & value.played, possiblePlayed: last.possiblePlayed | value.possiblePlayed)
            } else { result.append(value) }
        }
        if result.count > limits.residuals {
            result.sort { $0.logMass > $1.logMass }
            let excess = result.suffix(from: limits.residuals - 1)
            let combined = EngravingResidual(range: excess.map(\.range.lowerBound).min()!...excess.map(\.range.upperBound).max()!,
                                            logMass: EngravingMath.sum(excess.map(\.logMass)))
            result = Array(result.prefix(limits.residuals - 1)) + [combined]
        }
        return result
    }

    private func propagate(_ residual: EngravingResidual, observation: EngravingInputState.Observation,
                           score: EngravingScoreIndex, calibration: EngravingCalibration,
                           logContinuity: Double, into output: inout [EngravingResidual]) {
        let pitch = observation.attack!
        // Split noise from musical descendants. A mismatching observation can stay at the old
        // location, but cannot broaden that location as if it were a performed score attack.
        output.append(EngravingResidual(range: residual.range,
            logMass: residual.logMass + logContinuity + log(Self.noiseEmission), episode: residual.episode,
            onsets: residual.onsets, separation: residual.separation, onsetTime: residual.onsetTime,
            played: residual.played, possiblePlayed: residual.possiblePlayed))
        let search = max(0, residual.range.lowerBound - 16)...min(score.moments.count - 1, residual.range.upperBound + activeReach)
        guard let matches = score.matchingRange(pitch: pitch, within: search) else { return }
        let couldLag = score.hasChords(in: search)
        let low = max(residual.range.lowerBound, matches.lowerBound)
        let high = min(score.moments.count - 1, max(matches.upperBound, couldLag ? residual.range.upperBound : matches.upperBound))
        guard low <= high else { return }
        var upper = 1 - Self.insertionProbability
        if let familyBound = score.monophonicBound(from: residual.played, to: pitch, reach: activeReach) {
            upper = min(upper, familyBound)
        }
        if residual.range.lowerBound == residual.range.upperBound {
            upper = min(upper, emissionBound(residual, pitch: pitch, timestamp: observation.timestamp, score: score, calibration: calibration))
        }
        if residual.range.lowerBound == residual.range.upperBound, low == high,
           score.moments[residual.range.lowerBound].pitches.nonzeroBitCount == 1,
           low > residual.range.lowerBound, !couldLag {
            upper = min(upper, monophonicTransitionBound(from: residual.range.lowerBound, to: low, score: score))
        }
        if upper > 0 {
            let monophonic = !score.hasChords(in: search)
            let progressed = low > residual.range.upperBound || monophonic && residual.played != 0 && residual.played & EngravingScoreIndex.mask(pitch) == 0
            let sameFrontier = low == high && residual.range == low...high
            let bit = EngravingScoreIndex.mask(pitch)
            let couldBeLag = low > 0 && score.pitches(in: max(0, low - 16)...(low - 1)) & bit != 0
            let played = progressed || monophonic ? bit : sameFrontier ? residual.played | (couldBeLag ? 0 : bit) : 0
            let possiblePlayed = progressed || monophonic ? bit : sameFrontier ? residual.possiblePlayed | bit : .max
            let separation: Double
            if progressed, let elapsed = EngravingHostTime.seconds(from: residual.onsetTime, to: observation.timestamp) {
                separation = residual.separation + log1p(elapsed / exp(calibration.rolledSpread))
            } else { separation = residual.separation }
            output.append(EngravingResidual(range: low...high,
                logMass: residual.logMass + logContinuity + log(upper), episode: residual.episode,
                coherent: residual.coherent, fresh: true, onsets: min(1_024, residual.onsets + (progressed ? 1 : 0)),
                separation: separation, onsetTime: progressed ? observation.timestamp : sameFrontier ? residual.onsetTime : 0,
                played: played, possiblePlayed: possiblePlayed))
        }
    }

    /// Bound a normalized transition row from an exact frontier and an interval of known
    /// onset coverage. Enumerate at most eight coverage masks; larger ambiguity stays broad.
    private func emissionBound(_ residual: EngravingResidual, pitch: UInt8, timestamp: MIDITimeStamp,
                               score: EngravingScoreIndex, calibration: EngravingCalibration) -> Double {
        let source = residual.range.lowerBound
        let bit = EngravingScoreIndex.mask(pitch)
        if source > 0, score.pitches(in: max(0, source - 16)...(source - 1)) & bit != 0 { return 1 }
        let moment = score.moments[source]
        var unknown = residual.possiblePlayed & moment.pitches & ~residual.played
        guard unknown.nonzeroBitCount <= 3 else { return 1 }
        var coverages = [residual.played]
        while unknown != 0 {
            let next = UInt128(1) << UInt128(unknown.trailingZeroBitCount)
            coverages += coverages.map { $0 | next }
            unknown &= unknown - 1
        }
        func mask(_ i: Int, _ hand: EngravingPath.Hands) -> UInt128 {
            switch hand {
            case .left: score.moments[i].left
            case .right: score.moments[i].right
            case .both: score.moments[i].pitches
            }
        }
        var bound = 0.0
        for played in coverages {
            for hand in EngravingPath.Hands.allCases {
                let expected = mask(source, hand)
                guard expected != 0, played & ~expected == 0 else { continue }
                let remaining = expected & ~played
                var numerator = 0.0, denominator = 0.0
                func add(_ pitches: UInt128, low: Double, high: Double) {
                    denominator += low
                    if pitches & bit != 0 { numerator += high / Double(pitches.nonzeroBitCount) }
                }
                if remaining != 0 {
                    var low = 0.064, high = 0.80
                    if let elapsed = EngravingHostTime.seconds(from: residual.onsetTime, to: timestamp) {
                        let spread = exp(moment.rolled ? calibration.rolledSpread : calibration.blockSpread)
                        let value = 0.80 * (0.08 + 0.92 / (1 + pow(elapsed / (spread * 3), 2)))
                        low = value; high = value
                    }
                    add(remaining, low: low, high: high)
                }
                let restrike = remaining == 0 ? 0.12 : 0.025
                add(expected, low: restrike, high: restrike)
                let last = min(score.moments.count - 1, source + activeReach)
                if last > source {
                    var omitted = 0
                    for target in (source + 1)...last {
                        let weight = (remaining == 0 ? 0.86 : 0.16)
                            * exp(-0.35 * Double(min(4, remaining.nonzeroBitCount))) * pow(0.12, Double(omitted))
                        for nextHand in EngravingPath.Hands.allCases {
                            let pitches = mask(target, nextHand)
                            guard pitches != 0 else { continue }
                            let contribution = weight * (nextHand == hand ? 0.98 : 0.01)
                            add(pitches, low: 0.90 * contribution, high: contribution)
                        }
                        if mask(target, hand) != 0 { omitted += 1 }
                    }
                }
                if denominator > 0 { bound = max(bound, (1 - Self.insertionProbability) * numerator / denominator) }
            }
        }
        return min(1, bound)
    }

    /// For a complete monophonic source the structural row is known exactly apart from
    /// hand mode. Maximize the matching timing factor and minimize the competing factors.
    /// This avoids an ever-growing generic envelope on a long distinctive melody.
    private func monophonicTransitionBound(from source: Int, to target: Int, score: EngravingScoreIndex) -> Double {
        var maximum = 0.0
        for hand in EngravingPath.Hands.allCases {
            func mask(_ i: Int, _ hand: EngravingPath.Hands) -> UInt128 {
                switch hand {
                case .left: score.moments[i].left
                case .right: score.moments[i].right
                case .both: score.moments[i].pitches
                }
            }
            guard mask(source, hand) != 0 else { continue }
            var total = 0.12
            var matching = 0.0
            let last = min(score.moments.count - 1, source + activeReach)
            guard last > source else { continue }
            var omitted = 0
            for destination in (source + 1)...last {
                let weight = 0.86 * pow(0.12, Double(omitted))
                for nextHand in EngravingPath.Hands.allCases {
                    let pitches = mask(destination, nextHand)
                    guard pitches != 0 else { continue }
                    let contribution = weight * (nextHand == hand ? 0.98 : 0.01)
                    total += contribution
                    if destination == target { matching += contribution / Double(pitches.nonzeroBitCount) }
                }
                if mask(destination, hand) != 0 { omitted += 1 }
            }
            let minimumDenominator = 0.12 + matching + 0.90 * (total - 0.12 - matching)
            maximum = max(maximum, (1 - Self.insertionProbability) * matching / minimumDenominator)
        }
        return maximum
    }

    private mutating func normalize() {
        let total = evidence().totalLogMass
        guard total.isFinite else { return }
        for i in paths.indices { paths[i].logMass -= total }
        for i in residuals.indices { residuals[i].logMass -= total }
        noiseLogMass -= total
    }

    private mutating func refineRelease(_ observation: EngravingInputState.Observation, score: EngravingScoreIndex) {
        guard observation.changed, let pitch = observation.released, let dwell = observation.dwell, dwell > 0 else { return }
        let bit = EngravingScoreIndex.mask(pitch)
        // Weak, bounded evidence only. A release never creates a transition or confirmation.
        for i in paths.indices {
            let path = paths[i].path
            guard path.current.pitches & bit != 0, let tempo = path.tempo.secondsPerBeat else { continue }
            let duration = score.moments[path.current.offset].notes.filter { $0.pitch == pitch }.map(\.duration).max() ?? 0
            guard duration > 0 else { continue }
            let residual = abs(log(dwell / (duration * tempo)))
            paths[i].logMass += log(0.95 + 0.05 / (1 + residual * residual))
        }
        normalize()
    }

    func evidence() -> EngravingEvidence {
        let residual = EngravingMath.sum(residuals.map(\.logMass))
        let total = EngravingMath.add(EngravingMath.sum(paths.map(\.logMass)), EngravingMath.add(residual, noiseLogMass))
        // Select the exact destination by marginalized mass, not the best latent substate.
        var masses: [Int: Double] = [:]
        for item in paths { masses[item.path.current.offset] = EngravingMath.add(masses[item.path.current.offset] ?? -.infinity, item.logMass) }
        let offset = masses.keys.sorted().max { masses[$0]! < masses[$1]! }
        let best = paths.first { $0.path.current.offset == offset }?.path
        return EngravingEvidence(paths: paths, residualLogMass: residual, noiseLogMass: noiseLogMass,
                                 totalLogMass: total, best: best, residuals: residuals)
    }
}
