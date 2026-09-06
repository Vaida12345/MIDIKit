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

/// Future pitch/onset state of a discarded path. Unlike a score interval this retains
/// chord coverage and the actual unresolved preceding onset. Tempo is marginalized with
/// the transition model's [0.90, 1] envelope, rather than choosing a representative tempo.
struct EngravingContinuation: Hashable {
    var current: EngravingAssignment
    var previous: EngravingAssignment?
    var hands: EngravingPath.Hands
    var errors: Int
    var recentFit: [Double]

    init(_ path: EngravingPath, score: EngravingScoreIndex) {
        current = path.current
        previous = path.previous
        if let previous, path.mask(score.moments[previous.offset]) & ~previous.pitches == 0 {
            self.previous = nil
        }
        hands = path.hands
        errors = path.errors
        recentFit = path.recentFit
    }
}

/// A bounded summary includes every descendant of discarded paths, including insertions.
/// Unmerged exact states can be refined; envelope mass is always an upper bound.
struct EngravingResidual {
    var range: ClosedRange<Int>
    var logMass: Double
    var episode: UInt64? = nil
    var coherent = false
    var fresh = false
    var onsets = 0
    var separation = 0.0
    var onsetTime: MIDITimeStamp = 0
    var lastTime: MIDITimeStamp = 0
    var played: UInt128 = 0
    var possiblePlayed: UInt128 = .max
    var continuation: EngravingContinuation? = nil
    var exactPath: EngravingPath? = nil
    var handsMask: UInt8 = 7
    var lagPitches: UInt128 = .max
    var lagKnown = false
    var lagCount: Int? = nil
    var lagOrigins: UInt16? = nil
    var lagPlayed: UInt128 = 0
    var fitDebt: UInt8 = 15
    var earliestOnsetTime: MIDITimeStamp? = nil
    var earliestLastTime: MIDITimeStamp? = nil
    var latestLagTime: MIDITimeStamp = 0

    mutating func mergeTiming(_ other: Self) {
        earliestOnsetTime = min(earliestOnsetTime ?? onsetTime, other.earliestOnsetTime ?? other.onsetTime)
        earliestLastTime = min(earliestLastTime ?? lastTime, other.earliestLastTime ?? other.lastTime)
        onsetTime = onsetTime == 0 || other.onsetTime == 0 ? 0 : max(onsetTime, other.onsetTime)
        lastTime = lastTime == 0 || other.lastTime == 0 ? 0 : max(lastTime, other.lastTime)
        if lagKnown && lagPitches == 0 { latestLagTime = other.latestLagTime }
        else if !other.lagKnown || other.lagPitches != 0 {
            latestLagTime = latestLagTime == 0 || other.latestLagTime == 0 ? 0 : max(latestLagTime, other.latestLagTime)
        }
    }

    mutating func formEnvelopeUnion(_ other: Self) {
        mergeTiming(other)
        range = min(range.lowerBound, other.range.lowerBound)...max(range.upperBound, other.range.upperBound)
        logMass = EngravingMath.add(logMass, other.logMass)
        if episode != other.episode { episode = nil }
        coherent = coherent && other.coherent
        fresh = fresh && other.fresh
        onsets = min(onsets, other.onsets)
        separation = min(separation, other.separation)
        played &= other.played
        possiblePlayed |= other.possiblePlayed
        handsMask |= other.handsMask
        lagKnown = lagKnown && other.lagKnown && lagPitches == other.lagPitches
        lagPitches |= other.lagPitches
        if lagCount != other.lagCount { lagCount = nil }
        if lagCount == 0 { lagKnown = true; lagPitches = 0 }
        lagOrigins = lagOrigins.flatMap { a in other.lagOrigins.map { a | $0 } }
        lagPlayed &= other.lagPlayed
        fitDebt |= other.fitDebt
        continuation = nil
        exactPath = nil
    }

    /// Earliest reading anchor possible in this group. Unknown hand participation assumes
    /// both hands are active; only completed or absent lagging tones release that anchor.
    func readingOffset(score: EngravingScoreIndex) -> Int {
        if !score.hasChords(in: max(0, range.lowerBound - 16)...range.upperBound) { return range.lowerBound }
        if let state = continuation {
            guard state.hands == .both, let previous = state.previous,
                  score.moments[previous.offset].pitches & ~previous.pitches != 0 else {
                return range.lowerBound
            }
            return min(range.lowerBound, previous.offset)
        }
        if handsMask & (1 << EngravingPath.Hands.both.rawValue) == 0 || lagKnown && lagPitches == 0 {
            return range.lowerBound
        }
        return max(0, range.lowerBound - 16)
    }
}

struct EngravingEvidence {
    let paths: [EngravingWeightedPath]
    let residualLogMass: Double
    let noiseLogMass: Double
    let totalLogMass: Double
    let best: EngravingPath?
    var residuals: [EngravingResidual] = []
    var noiseUpperLogMass = -Double.infinity

    func support(where predicate: (EngravingPath) -> Bool,
                 compatibleResidual: (EngravingResidual) -> Bool = { _ in false }) -> Double {
        let mass = EngravingMath.sum(paths.filter { predicate($0.path) }.map(\.logMass))
        let opposingResidual = residuals.isEmpty ? residualLogMass : EngravingMath.sum(residuals.filter { !compatibleResidual($0) }.map(\.logMass))
        let denominator = EngravingMath.add(EngravingMath.sum(paths.map(\.logMass)), EngravingMath.add(opposingResidual, EngravingMath.add(noiseLogMass, noiseUpperLogMass)))
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
        // A change point's age is not a different musical occurrence. Position coherence
        // marginalizes those histories; relocation still requires its separate certificate.
        acquisitionMode(path)
    }
    func acquisitionMode(_ path: EngravingPath) -> Double {
        support(where: { abs($0.current.offset - path.current.offset) <= 2 && $0.fit >= 0.55 },
                compatibleResidual: { $0.coherent && $0.range.lowerBound >= path.current.offset - 2 && $0.range.upperBound <= path.current.offset + 2 })
    }
    var noiseSupport: Double {
        totalLogMass.isFinite ? exp(noiseLogMass - totalLogMass) : 1
    }
}

private struct EngravingEnvelopeKey: Hashable {
    let family: Int
    let played: UInt128
    let possiblePlayed: UInt128
    let hands: UInt8
    let lagMasks: [UInt128]
    let lagKnown: Bool
    let lagCount: Int?
    let onsetTime: MIDITimeStamp
    let earliestOnsetTime: MIDITimeStamp
    let lastTime: MIDITimeStamp
    let earliestLastTime: MIDITimeStamp
    let lagTime: MIDITimeStamp
}

private struct EngravingEnvelopeRow {
    let delta: Int
    let hands: EngravingPath.Hands
    let kind: Int
    let probability: Double
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
    private var noiseUpperLogMass = -Double.infinity
    private var hint: ClosedRange<Double>?
    private var hintOffsets = 0..<0
    private var hasStarted = false
    private var searchFocus: ClosedRange<Int>?
    private var activeReach = 8
    private var envelopeCache: [EngravingEnvelopeKey: [EngravingEnvelopeRow]] = [:]
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
            residuals[i].exactPath?.episode = path.episode
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
            for i in residuals.indices {
                if let path = residuals[i].exactPath {
                    residuals[i].logMass += log(prior(path.start, visible: offsets, count: score.moments.count))
                        - log(prior(path.start, visible: hintOffsets, count: score.moments.count))
                } else { residuals[i].logMass += log(max(1, ratio)) }
            }
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
            for i in residuals.indices { residuals[i].exactPath?.tempo.detach() }
        }
        guard let pitch = observation.attack else {
            refineRelease(observation, score: score)
            return evidence()
        }
        envelopeCache.removeAll(keepingCapacity: true)
        let bit = EngravingScoreIndex.mask(pitch)
        let oldTotal = EngravingMath.add(EngravingMath.sum(paths.map(\.logMass)), noiseLogMass)
        // All branches use the same preceding evidence scale. A fresh change point receives
        // the mixture evidence, never a likelihood from an unrelated shorter suffix.
        let base = oldTotal.isFinite ? oldTotal : 0
        let hazard = !hasStarted ? 1.0 : lost ? 0.04 : 0.001
        // A score-less prefix can end without claiming that a coherent musical passage
        // restarted. Keep the two hazards on their own mass, on the same history scale.
        let seedMass = !hasStarted ? 0 : EngravingMath.add(
            EngravingMath.sum(paths.map(\.logMass)) + log(hazard), noiseLogMass + log(0.12))
        let logContinuity = log(max(0, 1 - hazard - 0.0001))
        var generated: [EngravingWeightedPath] = []
        generated.reserveCapacity(limits.expansions)
        var nextResiduals: [EngravingResidual] = []
        let reach = activeReach
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

        for residual in residuals.sorted(by: { $0.logMass > $1.logMass }) {
            propagate(residual, observation: observation, score: score, calibration: calibration,
                      logContinuity: logContinuity, into: &nextResiduals, represented: &generated)
        }

        // Prefix noise is score-less. A new episode starts at its first explained attack;
        // initial errors therefore cannot contaminate all subsequent acquisition candidates.
        let residualMass = EngravingMath.sum(residuals.map(\.logMass))
        let unrepresentedSeed = EngravingMath.add(residualMass + log(hazard), noiseUpperLogMass + log(0.12))
        seed(pitch, observation: observation, score: score, logMass: seedMass,
             unrepresentedMass: unrepresentedSeed, into: &generated, residuals: &nextResiduals)
        // Discarded histories can also enter the score-less process. Keep that branch on
        // the common evidence scale without turning its upper bound into a represented vote.
        noiseUpperLogMass = EngravingMath.add(noiseUpperLogMass + log(1 - 0.12 - 0.0001) - log(128),
            EngravingMath.add(residualMass, noiseUpperLogMass) + log(0.0001 / 128))
        noiseLogMass = EngravingMath.add(noiseLogMass + log(1 - 0.12 - 0.0001) - log(128), base + log(0.0001 / 128))
        hasStarted = true
        prune(generated, score: score, into: &nextResiduals)
        residuals = compact(nextResiduals, score: score)
        normalize()
        return evidence()
    }

    private mutating func expand(_ weighted: EngravingWeightedPath, observation: EngravingInputState.Observation,
                                 bit: UInt128, score: EngravingScoreIndex, calibration: EngravingCalibration,
                                 logContinuity: Double, into output: inout [EngravingWeightedPath], boundedTiming: Bool = false) {
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
                                      weight: (remaining == 0 ? 0.12 : 0.025) * calibration.restrikeFactor(from: source.current.lastTime, to: observation.timestamp, rolled: moment.rolled), kind: 1))
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
                let weight = (remaining == 0 ? 0.86 : 0.16) * coverageCost * pow(0.04, Double(relevantSkip))
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
        let progressWeight = boundedTiming ? transitions.filter { $0.kind == 2 }.reduce(0.0) { $0 + $1.weight } : 0
        for transition in transitions {
            guard transition.mask & bit != 0, total > 0 else { continue }
            expansions += 1
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
            // Residual structural states use a fresh tempo below. Their numerator is the
            // upper transition weight; only competing progression weights use the floor.
            let denominator = total - 0.10 * (progressWeight - (boundedTiming && transition.kind == 2 ? transition.weight : 0))
            output.append(EngravingWeightedPath(path: path,
                logMass: weighted.logMass + logContinuity + log(transition.weight / denominator) + log(emission)))
        }
    }

    private mutating func seed(_ pitch: UInt8, observation: EngravingInputState.Observation,
                              score: EngravingScoreIndex, logMass: Double, unrepresentedMass: Double,
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
        let monophonic = !score.hasChords(in: 0...(score.moments.count - 1))
        if monophonic, unrepresentedMass.isFinite {
            let bound = postingPriorMass(pitch, indices: 0..<posting.count, score: score) * (1 - Self.insertionProbability)
            residuals.append(EngravingResidual(range: posting.first!...posting.last!, logMass: unrepresentedMass + log(bound),
                episode: observation.id, coherent: true, fresh: true, onsets: 1, onsetTime: observation.timestamp,
                lastTime: observation.timestamp, played: bit, possiblePlayed: bit))
        }
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
                let likelihood = log(destinationPrior) + log(1.0 / 3)
                    + log((1 - Self.insertionProbability) / Double(expected.nonzeroBitCount))
                output.append(EngravingWeightedPath(path: path, logMass: logMass + likelihood))
                if !monophonic, unrepresentedMass.isFinite {
                    residuals.append(EngravingResidual(range: offset...offset,
                        logMass: unrepresentedMass + likelihood, episode: observation.id,
                        coherent: true, fresh: true, onsets: 1, onsetTime: observation.timestamp,
                        lastTime: observation.timestamp, played: bit, possiblePlayed: bit,
                        continuation: EngravingContinuation(path, score: score), fitDebt: Self.fitDebt(path), latestLagTime: path.previous?.firstTime ?? 0))
                }
            }
        }
        // The unselected posting runs are represented without iterating over their elements.
        var cursor = 0
        for selectedOffset in ordered + [posting.count] {
            if cursor < selectedOffset {
                let range = posting[cursor]...posting[selectedOffset - 1]
                residuals.append(EngravingResidual(range: range, logMass: (monophonic ? logMass : EngravingMath.add(logMass, unrepresentedMass))
                    + log(postingPriorMass(pitch, indices: cursor..<selectedOffset, score: score) * (1 - Self.insertionProbability)),
                    episode: observation.id, coherent: true, fresh: true, onsets: 1, onsetTime: observation.timestamp,
                    played: bit, possiblePlayed: bit, lagPitches: 0, lagKnown: true))
            }
            cursor = selectedOffset + 1
        }
    }

    private mutating func prune(_ generated: [EngravingWeightedPath], score: EngravingScoreIndex, into residuals: inout [EngravingResidual]) {
        if !score.hasChords(in: 0...(score.moments.count - 1)) {
            pruneMonophonic(generated, into: &residuals)
            return
        }
        // Reporting history is not a new musical explanation. Marginalize paths with
        // identical future transition state before spending the per-destination budget.
        struct Key: Hashable {
            let current: EngravingAssignment
            let previous: EngravingAssignment?
            let hands: EngravingPath.Hands
            let episode: UInt64
            let start: Int?
            let tempo: EngravingTempo
            let recentFit: [Double]
            let errors: Int
            let matched: Bool
            let advanced: Bool
            let trailing: Bool
        }
        var positions: [Key: Int] = [:]
        var merged: [EngravingWeightedPath] = []
        for var item in generated {
            if let previous = item.path.previous, item.path.mask(score.moments[previous.offset]) & ~previous.pitches == 0 {
                item.path.previous = nil
            }
            let path = item.path
            let key = Key(current: path.current, previous: path.previous, hands: path.hands,
                          episode: path.episode, start: committedEpisode == nil ? path.start : nil,
                          tempo: path.tempo, recentFit: path.recentFit, errors: path.errors,
                          matched: path.matched, advanced: path.advanced, trailing: path.trailing)
            if let i = positions[key] {
                merged[i].logMass = EngravingMath.add(merged[i].logMass, item.logMass)
                merged[i].path.onsets = min(merged[i].path.onsets, path.onsets)
                merged[i].path.onsetEvidence = min(merged[i].path.onsetEvidence, path.onsetEvidence)
                merged[i].path.errors = max(merged[i].path.errors, path.errors)
                merged[i].path.recentFit = zip(merged[i].path.recentFit, path.recentFit).map { min($0, $1) }
                merged[i].path.leftAssignments = min(merged[i].path.leftAssignments, path.leftAssignments)
                merged[i].path.rightAssignments = min(merged[i].path.rightAssignments, path.rightAssignments)
                merged[i].path.skippedAttacks = merged[i].path.skippedAttacks || path.skippedAttacks
                merged[i].path.omittedAttacks = max(merged[i].path.omittedAttacks, path.omittedAttacks)
                if let start = path.omissionStart { merged[i].path.omissionStart = min(merged[i].path.omissionStart ?? start, start) }
                merged[i].path.recoveryOnsets = min(merged[i].path.recoveryOnsets, path.recoveryOnsets)
            } else {
                positions[key] = merged.count
                merged.append(item)
            }
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
        // The upper hand often arrives first. Reserve a plausible coupled-hand state
        // before filling the destination's remaining slots with variations of one hand.
        struct LaneKey: Hashable { let offset: Int; let hands: EngravingPath.Hands }
        var lanes = Set(retained.map { LaneKey(offset: $0.path.current.offset, hands: $0.path.hands) })
        for (i, item) in sorted.enumerated() where !used.contains(i) {
            let lane = LaneKey(offset: item.path.current.offset, hands: item.path.hands)
            if !lanes.contains(lane), retained.count < limits.hypotheses,
               counts[item.path.current.offset, default: 0] < limits.perDestination {
                lanes.insert(lane)
                retained.append(item)
                used.insert(i)
                counts[item.path.current.offset, default: 0] += 1
            }
        }
        for (i, item) in sorted.enumerated() where !used.contains(i) {
            if retained.count < limits.hypotheses && counts[item.path.current.offset, default: 0] < limits.perDestination {
                retained.append(item)
                counts[item.path.current.offset, default: 0] += 1
            } else {
                residuals.append(EngravingResidual(range: item.path.current.offset...item.path.current.offset, logMass: item.logMass,
                    episode: item.path.episode, coherent: item.path.fit >= 0.55, fresh: item.path.matched,
                    onsets: item.path.onsets, separation: item.path.onsetEvidence, onsetTime: item.path.current.firstTime, lastTime: item.path.current.lastTime,
                    played: item.path.current.pitches, possiblePlayed: item.path.current.pitches,
                    continuation: EngravingContinuation(item.path, score: score), exactPath: item.path, fitDebt: Self.fitDebt(item.path), latestLagTime: item.path.previous?.firstTime ?? 0))
            }
        }
        paths = retained.sorted(by: Self.ordered)
        peakPaths = max(peakPaths, paths.count)
    }

    private mutating func pruneMonophonic(_ generated: [EngravingWeightedPath], into residuals: inout [EngravingResidual]) {
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
                    onsets: item.path.onsets, separation: item.path.onsetEvidence, onsetTime: item.path.current.firstTime, lastTime: item.path.current.lastTime,
                    played: item.path.current.pitches, possiblePlayed: item.path.current.pitches))
            }
        }
        paths = retained.sorted(by: Self.ordered)
        peakPaths = max(peakPaths, paths.count)
    }

    /// Four pessimistic onset-fit slots; bit zero is the current onset. Padding short
    /// histories with their worst slot keeps the bound below the actual recent-fit mean.
    private static func fitDebt(_ path: EngravingPath) -> UInt8 {
        var failed = path.recentFit.map { $0 < 1 } + [path.errors != 0]
        while failed.count < 4 { failed.insert(failed.contains(true), at: 0) }
        return failed.suffix(4).reversed().enumerated().reduce(0) { $0 | ($1.element ? UInt8(1) << $1.offset : 0) }
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

    private func compact(_ values: [EngravingResidual], score: EngravingScoreIndex) -> [EngravingResidual] {
        if !score.hasChords(in: 0...(score.moments.count - 1)) {
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
                        lastTime: last.lastTime == value.lastTime ? last.lastTime : 0,
                        played: last.played & value.played, possiblePlayed: last.possiblePlayed | value.possiblePlayed)
                } else { result.append(value) }
            }
            if result.count > min(limits.residuals, 128) {
                result.sort { $0.logMass > $1.logMass }
                let excess = result.suffix(from: min(limits.residuals, 128) - 1)
                let combined = EngravingResidual(range: excess.map(\.range.lowerBound).min()!...excess.map(\.range.upperBound).max()!,
                                                logMass: EngravingMath.sum(excess.map(\.logMass)))
                result = Array(result.prefix(min(limits.residuals, 128) - 1)) + [combined]
            }
            return result
        }
        struct Key: Hashable {
            let range: ClosedRange<Int>
            let episode: UInt64?
            let coherent: Bool
            let fresh: Bool
            let continuation: EngravingContinuation?
            let exactPath: EngravingPath?
            let played: UInt128
            let possiblePlayed: UInt128
            let lagPitches: UInt128
            let handsMask: UInt8
            let lagOrigins: UInt16?
            let lagPlayed: UInt128
            let lagCount: Int?
        }
        var indices: [Key: Int] = [:]
        var result: [EngravingResidual] = []
        for value in values {
            let key = Key(range: value.range, episode: value.episode, coherent: value.coherent,
                          fresh: value.fresh, continuation: value.continuation, exactPath: value.exactPath, played: value.played,
                          possiblePlayed: value.possiblePlayed, lagPitches: value.lagPitches, handsMask: value.handsMask,
                          lagOrigins: value.lagOrigins, lagPlayed: value.lagPlayed, lagCount: value.lagCount)
            if let index = indices[key] {
                let last = result[index]
                var timing = last
                timing.mergeTiming(value)
                result[index] = EngravingResidual(range: last.range,
                    logMass: EngravingMath.add(last.logMass, value.logMass), episode: last.episode, coherent: last.coherent, fresh: last.fresh,
                    onsets: min(last.onsets, value.onsets), separation: min(last.separation, value.separation),
                    onsetTime: timing.onsetTime, lastTime: timing.lastTime,
                    played: last.played & value.played, possiblePlayed: last.possiblePlayed | value.possiblePlayed,
                    continuation: last.continuation, exactPath: last.exactPath, handsMask: last.handsMask | value.handsMask,
                    lagPitches: last.lagPitches | value.lagPitches, lagKnown: last.lagKnown && value.lagKnown, lagCount: last.lagCount,
                    lagOrigins: last.lagOrigins, lagPlayed: last.lagPlayed, fitDebt: last.fitDebt | value.fitDebt, earliestOnsetTime: timing.earliestOnsetTime,
                    earliestLastTime: timing.earliestLastTime, latestLagTime: timing.latestLagTime)
            } else {
                indices[key] = result.count
                result.append(value)
            }
        }
        let capacity = limits.residuals
        if result.count > capacity {
            result = result.enumerated().sorted {
                $0.element.logMass == $1.element.logMass ? $0.offset < $1.offset : $0.element.logMass > $1.element.logMass
            }.map(\.element)
            let preciseCount = min(limits.hypotheses, capacity / 4)
            var coarse: [EngravingResidual] = []
            struct CoverageKey: Hashable {
                var range: ClosedRange<Int>
                var played: UInt128
                var lag: UInt128
                var hands: UInt8
                var fresh: Bool
                var coherent: Bool
                var origins: UInt16?
                var lagPlayed: UInt128
                var lagCount: Int?
            }
            var ranges: [CoverageKey: Int] = [:]
            for var value in result.dropFirst(preciseCount) {
                if let state = value.continuation {
                    value.handsMask = 1 << state.hands.rawValue
                    value.latestLagTime = state.previous?.firstTime ?? 0
                    value.lagKnown = true
                    value.lagPitches = state.previous.map { previous in
                        laneMask(previous.offset, hands: state.hands, score: score) & ~previous.pitches
                    } ?? 0
                }
                if value.lagKnown { value.lagCount = value.lagPitches.nonzeroBitCount }
                value.continuation = nil
                value.exactPath = nil
                let key = CoverageKey(range: value.range, played: value.played, lag: value.lagPitches, hands: value.handsMask, fresh: value.fresh, coherent: value.coherent,
                                      origins: value.lagOrigins, lagPlayed: value.lagPlayed, lagCount: value.lagCount)
                if let index = ranges[key] {
                    var merged = coarse[index]
                    merged.logMass = EngravingMath.add(merged.logMass, value.logMass)
                    if merged.episode != value.episode { merged.episode = nil }
                    merged.fitDebt |= value.fitDebt
                    merged.coherent = merged.coherent && value.coherent
                    merged.fresh = merged.fresh && value.fresh
                    merged.onsets = min(merged.onsets, value.onsets)
                    merged.separation = min(merged.separation, value.separation)
                    merged.mergeTiming(value)
                    merged.played &= value.played
                    merged.possiblePlayed |= value.possiblePlayed
                    merged.handsMask |= value.handsMask
                    merged.lagPitches |= value.lagPitches
                    merged.lagKnown = merged.lagKnown && value.lagKnown
                    coarse[index] = merged
                } else {
                    ranges[key] = coarse.count
                    coarse.append(value)
                }
            }
            let available = capacity - preciseCount
            if coarse.count > available {
                coarse = coarse.enumerated().sorted {
                    $0.element.logMass == $1.element.logMass ? $0.offset < $1.offset : $0.element.logMass > $1.element.logMass
                }.map(\.element)
                // Spend the tail budget on musical frontiers. Collapsing all tail mass
                // into one interval would let it choose an unrelated chord on each attack.
                let retainedCount = available / 4
                struct Frontier: Hashable {
                    let range: ClosedRange<Int>
                    let hands: UInt8
                    let played: UInt128
                    let lagCount: Int?
                }
                var indices: [Frontier: Int] = [:]
                var tail: [EngravingResidual] = []
                for value in coarse.dropFirst(retainedCount) {
                    let key = Frontier(range: value.range, hands: value.handsMask, played: value.played, lagCount: value.lagCount)
                    if let i = indices[key] {
                        var merged = tail[i]
                        merged.logMass = EngravingMath.add(merged.logMass, value.logMass)
                        if merged.episode != value.episode { merged.episode = nil }
                        merged.fitDebt |= value.fitDebt
                        merged.coherent = merged.coherent && value.coherent
                        merged.fresh = merged.fresh && value.fresh
                        merged.onsets = min(merged.onsets, value.onsets)
                        merged.separation = min(merged.separation, value.separation)
                        merged.mergeTiming(value)
                        merged.played &= value.played
                        merged.possiblePlayed |= value.possiblePlayed
                        if merged.lagKnown != value.lagKnown || merged.lagPitches != value.lagPitches {
                            merged.lagKnown = false
                            merged.lagOrigins = nil
                        } else if merged.lagOrigins != value.lagOrigins {
                            merged.lagOrigins = merged.lagOrigins.flatMap { a in value.lagOrigins.map { a | $0 } }
                        }
                        merged.lagPitches |= value.lagPitches
                        merged.lagPlayed &= value.lagPlayed
                        tail[i] = merged
                    } else {
                        indices[key] = tail.count
                        tail.append(value)
                    }
                }
                if tail.count > available - retainedCount {
                    let tailBudget = available - retainedCount
                    tail = tail.enumerated().sorted {
                        $0.element.logMass == $1.element.logMass ? $0.offset < $1.offset : $0.element.logMass > $1.element.logMass
                    }.map(\.element)
                    struct Location: Hashable { let range: ClosedRange<Int>; let hands: UInt8; let coherent: Bool; let fresh: Bool }
                    var indices: [Location: Int] = [:]
                    var locations: [EngravingResidual] = []
                    let locationCount = Set(tail.map { Location(range: $0.range, hands: $0.handsMask, coherent: $0.coherent, fresh: $0.fresh) }).count
                    let detailedCount = max(0, tailBudget - locationCount)
                    for value in tail.dropFirst(detailedCount) {
                        let key = Location(range: value.range, hands: value.handsMask, coherent: value.coherent, fresh: value.fresh)
                        if let i = indices[key] { locations[i].formEnvelopeUnion(value) }
                        else { indices[key] = locations.count; locations.append(value) }
                    }
                    tail = Array(tail.prefix(detailedCount)) + locations
                }
                if tail.count > available - retainedCount {
                    tail.sort { $0.logMass > $1.logMass }
                    let count = available - retainedCount - 1
                    let excess = tail.dropFirst(count)
                    let combined = EngravingResidual(range: excess.map(\.range.lowerBound).min()!...excess.map(\.range.upperBound).max()!,
                        logMass: EngravingMath.sum(excess.map(\.logMass)))
                    tail = Array(tail.prefix(count)) + [combined]
                }
                coarse = Array(coarse.prefix(retainedCount)) + tail
            }
            result = Array(result.prefix(preciseCount)) + coarse
        }
        return result
    }

    private mutating func propagate(_ residual: EngravingResidual, observation: EngravingInputState.Observation,
                           score: EngravingScoreIndex, calibration: EngravingCalibration,
                           logContinuity: Double, into output: inout [EngravingResidual],
                           represented: inout [EngravingWeightedPath]) {
        let pitch = observation.attack!
        let monophonicScore = !score.hasChords(in: 0...(score.moments.count - 1))
        // An unmerged discarded state is still exact. Re-evaluate it against the next
        // attack and let it compete for the active beam; a former pruning decision must
        // not permanently exile the hand/onset assignment that the new attack confirms.
        if !monophonicScore, let path = residual.exactPath,
           expansions < limits.expansions - limits.destinations * 3 - 64 {
            expand(.init(path: path, logMass: residual.logMass), observation: observation,
                   bit: EngravingScoreIndex.mask(pitch), score: score, calibration: calibration,
                   logContinuity: logContinuity, into: &represented)
            return
        }
        if !monophonicScore, let state = residual.continuation,
           expansions < limits.expansions - limits.destinations * 3 - 64 {
            var path = EngravingPath(current: state.current, previous: state.previous, hands: state.hands,
                episode: residual.episode ?? 0, start: state.current.offset,
                lastObservation: observation.id, lastAttack: pitch)
            path.errors = state.errors
            path.recentFit = state.recentFit
            path.onsets = residual.onsets
            path.onsetEvidence = residual.separation
            var descendants: [EngravingWeightedPath] = []
            expand(.init(path: path, logMass: residual.logMass), observation: observation,
                   bit: EngravingScoreIndex.mask(pitch), score: score, calibration: calibration,
                   logContinuity: logContinuity, into: &descendants, boundedTiming: true)
            for descendant in descendants {
                let path = descendant.path
                output.append(EngravingResidual(range: path.current.offset...path.current.offset,
                    logMass: descendant.logMass, episode: residual.episode, coherent: path.fit >= 0.55,
                    fresh: path.matched, onsets: path.onsets, separation: path.onsetEvidence,
                    onsetTime: path.current.firstTime, lastTime: path.current.lastTime,
                    played: path.current.pitches, possiblePlayed: path.current.pitches,
                    continuation: EngravingContinuation(path, score: score), fitDebt: Self.fitDebt(path), latestLagTime: path.previous?.firstTime ?? 0))
            }
            return
        }
        if !monophonicScore, residual.range.count == 1 {
            var envelope = residual
            envelope.exactPath = nil
            if let state = residual.continuation {
                envelope.continuation = nil
                envelope.handsMask = 1 << state.hands.rawValue
                envelope.latestLagTime = state.previous?.firstTime ?? 0
                envelope.lagKnown = true
                envelope.lagPitches = state.previous.map { laneMask($0.offset, hands: state.hands, score: score) & ~$0.pitches } ?? 0
            }
            if envelope.lagKnown { envelope.lagCount = envelope.lagPitches.nonzeroBitCount }
            propagateChordEnvelope(envelope, observation: observation, score: score,
                                   calibration: calibration, logContinuity: logContinuity, into: &output)
            return
        }
        // Split noise from musical descendants. A mismatching observation can stay at the old
        // location, but cannot broaden that location as if it were a performed score attack.
        output.append(EngravingResidual(range: residual.range,
            logMass: residual.logMass + logContinuity + log(Self.noiseEmission), episode: residual.episode,
            onsets: residual.onsets, separation: residual.separation, onsetTime: residual.onsetTime, lastTime: residual.lastTime,
            played: residual.played, possiblePlayed: residual.possiblePlayed))
        // Keep destinations separate when a discarded monophonic state has an exact
        // frontier. A single interval would let mass assigned to a very unlikely omission
        // migrate back onto the ordinary successor on each subsequent repeated pitch.
        let forward = residual.range.lowerBound...min(score.moments.count - 1, residual.range.upperBound + activeReach)
        if residual.range.count == 1, !score.hasChords(in: 0...(score.moments.count - 1)),
           residual.played == score.moments[residual.range.lowerBound].pitches {
            let source = residual.range.lowerBound
            for destination in forward where score.moments[destination].pitches & EngravingScoreIndex.mask(pitch) != 0 {
                let upper = monophonicTransitionBound(from: source, to: destination, score: score,
                    restrike: EngravingHostTime.seconds(from: residual.lastTime, to: observation.timestamp).map { _ in
                        0.12 * calibration.restrikeFactor(from: residual.lastTime, to: observation.timestamp, rolled: score.moments[source].rolled)
                    })
                guard upper > 0 else { continue }
                let progressed = destination > source
                let elapsed = EngravingHostTime.seconds(from: residual.onsetTime, to: observation.timestamp)
                output.append(EngravingResidual(range: destination...destination,
                    logMass: residual.logMass + logContinuity + log(upper), episode: residual.episode,
                    coherent: residual.coherent, fresh: true,
                    onsets: min(1_024, residual.onsets + (progressed ? 1 : 0)),
                    separation: residual.separation + (progressed ? elapsed.map { log1p($0 / exp(calibration.rolledSpread)) } ?? 0 : 0),
                    onsetTime: progressed ? observation.timestamp : residual.onsetTime, lastTime: observation.timestamp,
                    played: EngravingScoreIndex.mask(pitch), possiblePlayed: EngravingScoreIndex.mask(pitch)))
            }
            return
        }
        let search = max(0, residual.range.lowerBound - 16)...min(score.moments.count - 1, residual.range.upperBound + activeReach)
        guard let matches = score.matchingRange(pitch: pitch, within: search) else { return }
        let couldLag = score.hasChords(in: search)
        let low = max(residual.range.lowerBound, matches.lowerBound)
        let high = min(score.moments.count - 1, max(matches.upperBound, couldLag ? residual.range.upperBound : matches.upperBound))
        guard low <= high else { return }
        var upper = 1 - Self.insertionProbability
        let minimumRestrike = EngravingHostTime.seconds(from: residual.lastTime, to: observation.timestamp).map { _ in
            0.12 * min(calibration.restrikeFactor(from: residual.lastTime, to: observation.timestamp, rolled: false),
                       calibration.restrikeFactor(from: residual.lastTime, to: observation.timestamp, rolled: true))
        }
        if let familyBound = score.monophonicBound(from: residual.played, to: pitch, reach: activeReach, restrike: minimumRestrike) {
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
                lastTime: monophonic ? observation.timestamp : 0,
                played: played, possiblePlayed: possiblePlayed))
        }
    }

    private func laneMask(_ offset: Int, hands: EngravingPath.Hands, score: EngravingScoreIndex) -> UInt128 {
        switch hands {
        case .left: score.moments[offset].left
        case .right: score.moments[offset].right
        case .both: score.moments[offset].pitches
        }
    }

    /// Keep the previous onset's identity when a coarse group contains several possible
    /// predecessors. Successive trailing tones must fit the same predecessor, not a union
    /// assembled from unrelated chords throughout the look-behind region.
    private func lagPossibilities(at source: Int, hands: EngravingPath.Hands, origins: UInt16?,
                                  played: UInt128, matching: UInt128 = 0,
                                  score: EngravingScoreIndex) -> (origins: UInt16, pitches: UInt128) {
        var candidates: UInt16 = 0
        var pitches: UInt128 = 0
        for distance in 1..<(min(16, source) + 1) {
            let flag = UInt16(1) << (distance - 1)
            guard origins == nil || origins! & flag != 0 else { continue }
            let remaining = laneMask(source - distance, hands: hands, score: score) & ~played
            guard matching == 0 || remaining & matching != 0 else { continue }
            candidates |= flag
            pitches |= remaining
        }
        return (candidates, pitches)
    }

    /// An interval of chord coverages has a bounded transition row for each possible hand.
    /// Maximize the probability of each *destination/assignment*, never a whole reachable
    /// interval. Keeping the old-frontier and successor contributions separate lets later
    /// chord tones disprove omissions and restrikes instead of recycling their entire mass.
    private mutating func propagateChordEnvelope(_ residual: EngravingResidual,
        observation: EngravingInputState.Observation, score: EngravingScoreIndex,
        calibration: EngravingCalibration, logContinuity: Double, into output: inout [EngravingResidual]) {
        let source = residual.range.lowerBound
        let moment = score.moments[source]
        let bit = EngravingScoreIndex.mask(observation.attack!)
        var noise = residual
        noise.logMass += logContinuity + log(Self.noiseEmission)
        noise.fitDebt |= 1
        noise.coherent = noise.fitDebt.nonzeroBitCount <= 1
        noise.fresh = false
        output.append(noise)

        let lagMasks = EngravingPath.Hands.allCases.map { hand in
            residual.lagCount == 0 ? UInt128(0) : residual.lagKnown ? residual.lagPitches
                : lagPossibilities(at: source, hands: hand, origins: residual.lagOrigins,
                                   played: residual.lagPlayed, score: score).pitches & residual.lagPitches
        }
        let cacheKey = EngravingEnvelopeKey(family: score.transitionFamily(at: source, reach: activeReach),
            played: residual.played, possiblePlayed: residual.possiblePlayed, hands: residual.handsMask,
            lagMasks: lagMasks, lagKnown: residual.lagKnown, lagCount: residual.lagCount,
            onsetTime: residual.onsetTime, earliestOnsetTime: residual.earliestOnsetTime ?? residual.onsetTime,
            lastTime: residual.lastTime, earliestLastTime: residual.earliestLastTime ?? residual.lastTime,
            lagTime: residual.latestLagTime)
        let rows: [EngravingEnvelopeRow]
        if let cached = envelopeCache[cacheKey] { rows = cached }
        else {
            struct Key: Hashable {
                let target: Int
                let hands: EngravingPath.Hands
                let kind: Int // 0 current onset, 1 progression, 2 trailing hand
            }
            struct Progression {
                let key: Key
                let weight: Double
                let pitchCount: Int
            }
            var maxima: [Key: Double] = [:]
            var order: [Key] = []
            func record(_ key: Key, _ probability: Double) {
                guard probability > 0 else { return }
                if maxima[key] == nil { order.append(key) }
                maxima[key] = max(maxima[key] ?? 0, min(1 - Self.insertionProbability, probability))
            }
            let last = min(score.moments.count - 1, source + activeReach)
            let spread = exp(moment.rolled ? calibration.rolledSpread : calibration.blockSpread)
            func extensionWeight(_ time: MIDITimeStamp, fallback: Double) -> Double {
                EngravingHostTime.seconds(from: time, to: observation.timestamp).map {
                    0.80 * (0.08 + 0.92 / (1 + pow($0 / (spread * 3), 2)))
                } ?? fallback
            }
            let extensionMinimum = extensionWeight(residual.earliestOnsetTime ?? residual.onsetTime, fallback: 0.064)
            let extensionMaximum = extensionWeight(residual.onsetTime, fallback: 0.80)
            func restrikeFactor(_ time: MIDITimeStamp, fallback: Double) -> Double {
                guard EngravingHostTime.seconds(from: time, to: observation.timestamp) != nil else { return fallback }
                return calibration.restrikeFactor(from: time, to: observation.timestamp, rolled: moment.rolled)
            }
            let restrikeMinimum = restrikeFactor(residual.earliestLastTime ?? residual.lastTime, fallback: 0.05)
            let restrikeMaximum = restrikeFactor(residual.lastTime, fallback: 1)
            let lagMaximum = EngravingHostTime.seconds(from: residual.latestLagTime, to: observation.timestamp).map {
                0.18 * (0.1 + 0.9 / (1 + pow($0 / (exp(calibration.handSpread) * 3), 2)))
            } ?? 0.18
            for hand in EngravingPath.Hands.allCases where residual.handsMask & (1 << hand.rawValue) != 0 {
                let expected = laneMask(source, hands: hand, score: score)
                guard expected != 0, residual.played & ~expected == 0 else { continue }
                let possibleLag = lagMasks[Int(hand.rawValue)]
                let lagLow = possibleLag != 0 && (residual.lagKnown || residual.lagCount != nil) ? 0.018 : 0.0
                var progressions: [Progression] = []
                var totalProgression = 0.0
                var omitted = 0
                for target in (source + 1)..<(last + 1) {
                    let omissionWeight = pow(0.04, Double(omitted))
                    for nextHand in EngravingPath.Hands.allCases {
                        let pitches = laneMask(target, hands: nextHand, score: score)
                        guard pitches != 0 else { continue }
                        let weight = omissionWeight * (nextHand == hand ? 0.98 : 0.01)
                        totalProgression += weight
                        if pitches & bit != 0 {
                            progressions.append(Progression(key: Key(target: target, hands: nextHand, kind: 1),
                                                           weight: weight, pitchCount: pitches.nonzeroBitCount))
                        }
                    }
                    if laneMask(target, hands: hand, score: score) != 0 { omitted += 1 }
                }
                // Coverage affects a normalized row only through its missing-tone count and
                // whether this pitch is still missing. Enumerating counts is exact for this
                // envelope, including large chords, without enumerating 2^n pitch subsets.
                let mandatoryMissing = expected & ~residual.possiblePlayed
                let minimumMissing = mandatoryMissing.nonzeroBitCount
                let maximumMissing = (expected & ~residual.played).nonzeroBitCount
                for missing in minimumMissing...maximumMissing {
                    let extensionLow = missing == 0 ? 0 : extensionMinimum
                    let extensionHigh = missing == 0 ? 0 : extensionMaximum
                    let correction = missing == 0 ? 0.12 : 0.025
                    let correctionLow = correction * restrikeMinimum
                    let correctionHigh = correction * restrikeMaximum
                    let progression = (missing == 0 ? 0.86 : 0.16) * exp(-0.35 * Double(min(4, missing)))
                    let totalLow = extensionLow + correctionLow + lagLow + 0.90 * progression * totalProgression
                    var currentProbability = 0.0
                    if expected & bit != 0 {
                        currentProbability = correctionHigh / (totalLow - correctionLow + correctionHigh)
                            / Double(expected.nonzeroBitCount)
                        let canBeMissing = residual.played & bit == 0
                            && (mandatoryMissing & bit != 0 || missing > minimumMissing)
                        if missing > 0, canBeMissing {
                            currentProbability += extensionHigh / (totalLow - extensionLow + extensionHigh) / Double(missing)
                        }
                    }
                    record(Key(target: source, hands: hand, kind: 0), (1 - Self.insertionProbability) * currentProbability)
                    if possibleLag & bit != 0 {
                        let count = residual.lagCount ?? (residual.lagKnown ? possibleLag.nonzeroBitCount : 1)
                        record(Key(target: source, hands: hand, kind: 2),
                               (1 - Self.insertionProbability) * lagMaximum / (totalLow - lagLow + lagMaximum) / Double(count))
                    }
                    for row in progressions {
                        let high = progression * row.weight
                        record(row.key, (1 - Self.insertionProbability) * high / (totalLow + 0.10 * high) / Double(row.pitchCount))
                    }
                }
            }
            rows = order.map { EngravingEnvelopeRow(delta: $0.target - source, hands: $0.hands, kind: $0.kind, probability: maxima[$0]!) }
            if envelopeCache.count < limits.residuals { envelopeCache[cacheKey] = rows }
        }
        for key in rows {
            let target = source + key.delta
            let probability = key.probability
            guard probability > 0 else { continue }
            let advanced = key.kind == 1
            let elapsed = EngravingHostTime.seconds(from: residual.onsetTime, to: observation.timestamp)
            var lagOrigins = residual.lagOrigins
            var lagPlayed = residual.lagPlayed
            var lagPitches = residual.lagPitches
            if key.kind == 2 {
                if residual.lagKnown { lagPitches &= ~bit }
                else {
                    let possible = lagPossibilities(at: source, hands: key.hands, origins: residual.lagOrigins,
                                                    played: residual.lagPlayed, matching: bit, score: score)
                    lagOrigins = possible.origins
                    lagPlayed |= bit
                    lagPitches = possible.pitches & ~bit
                }
            }
            // A matched continuation cannot worsen fit: a new onset adds a perfect
            // current slot, replacing an older slot no greater than one.
            let debt = advanced ? (residual.fitDebt << 1) & 15 : residual.fitDebt
            output.append(EngravingResidual(range: target...target,
                logMass: residual.logMass + logContinuity + log(probability), episode: residual.episode,
                coherent: residual.coherent || debt.nonzeroBitCount <= 1, fresh: true, onsets: min(1_024, residual.onsets + (advanced ? 1 : 0)),
                separation: residual.separation + (advanced ? elapsed.map { log1p($0 / exp(calibration.rolledSpread)) } ?? 0 : 0),
                onsetTime: advanced ? observation.timestamp : residual.onsetTime,
                lastTime: key.kind == 2 ? residual.lastTime : observation.timestamp,
                played: advanced ? bit : key.kind == 2 ? residual.played : residual.played | bit,
                possiblePlayed: advanced ? bit : key.kind == 2 ? residual.possiblePlayed : residual.possiblePlayed | bit,
                handsMask: 1 << key.hands.rawValue,
                lagPitches: advanced ? laneMask(source, hands: key.hands, score: score) & ~residual.played
                    : key.kind == 2 && residual.lagCount == 1 ? 0 : lagPitches,
                lagKnown: advanced ? residual.played == residual.possiblePlayed : residual.lagKnown || key.kind == 2 && residual.lagCount == 1,
                lagCount: advanced ? (residual.played == residual.possiblePlayed ? (laneMask(source, hands: key.hands, score: score) & ~residual.played).nonzeroBitCount : nil)
                    : key.kind == 2 ? residual.lagCount.map { max(0, $0 - 1) } : residual.lagCount,
                lagOrigins: advanced ? UInt16(1) << (target - source - 1) : lagOrigins,
                lagPlayed: advanced ? residual.played : lagPlayed, fitDebt: debt,
                earliestOnsetTime: advanced ? nil : residual.earliestOnsetTime,
                earliestLastTime: key.kind == 2 ? residual.earliestLastTime : nil,
                latestLagTime: advanced ? residual.onsetTime : residual.latestLagTime))
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
                if EngravingHostTime.seconds(from: residual.lastTime, to: timestamp) != nil {
                    let factor = calibration.restrikeFactor(from: residual.lastTime, to: timestamp, rolled: moment.rolled)
                    add(expected, low: restrike * factor, high: restrike * factor)
                } else { add(expected, low: restrike * 0.05, high: restrike) }
                let last = min(score.moments.count - 1, source + activeReach)
                if last > source {
                    var omitted = 0
                    for target in (source + 1)...last {
                        let weight = (remaining == 0 ? 0.86 : 0.16)
                            * exp(-0.35 * Double(min(4, remaining.nonzeroBitCount))) * pow(0.04, Double(omitted))
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
    private func monophonicTransitionBound(from source: Int, to target: Int, score: EngravingScoreIndex,
                                           restrike: Double? = nil) -> Double {
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
            let correction = restrike ?? (target == source ? 0.12 : 0.006)
            var total = correction
            var matching = target == source ? correction : 0.0
            let last = min(score.moments.count - 1, source + activeReach)
            var omitted = 0
            for destination in (source + 1)..<(last + 1) {
                let weight = 0.86 * pow(0.04, Double(omitted))
                for nextHand in EngravingPath.Hands.allCases {
                    let pitches = mask(destination, nextHand)
                    guard pitches != 0 else { continue }
                    let contribution = weight * (nextHand == hand ? 0.98 : 0.01)
                    total += contribution
                    if destination == target { matching += contribution / Double(pitches.nonzeroBitCount) }
                }
                if mask(destination, hand) != 0 { omitted += 1 }
            }
            let minimumDenominator = target == source
                ? correction + 0.90 * (total - correction)
                : correction + matching + 0.90 * (total - correction - matching)
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
        noiseUpperLogMass -= total
    }

    private mutating func refineRelease(_ observation: EngravingInputState.Observation, score: EngravingScoreIndex) {
        guard observation.changed, let pitch = observation.released, let dwell = observation.dwell, dwell > 0 else { return }
        let bit = EngravingScoreIndex.mask(pitch)
        // Weak, bounded evidence only. A release never creates a transition or confirmation.
        func factor(_ path: EngravingPath) -> Double {
            guard path.current.pitches & bit != 0, let tempo = path.tempo.secondsPerBeat else { return 0 }
            let duration = score.moments[path.current.offset].notes.filter { $0.pitch == pitch }.map(\.duration).max() ?? 0
            guard duration > 0 else { return 0 }
            let residual = abs(log(dwell / (duration * tempo)))
            return log(0.95 + 0.05 / (1 + residual * residual))
        }
        for i in paths.indices { paths[i].logMass += factor(paths[i].path) }
        for i in residuals.indices {
            if let path = residuals[i].exactPath { residuals[i].logMass += factor(path) }
        }
        normalize()
    }

    func evidence() -> EngravingEvidence {
        let residual = EngravingMath.sum(residuals.map(\.logMass))
        let total = EngravingMath.add(EngravingMath.sum(paths.map(\.logMass)),
            EngravingMath.add(residual, EngravingMath.add(noiseLogMass, noiseUpperLogMass)))
        // Select the exact destination by marginalized mass, not the best latent substate.
        var masses: [Int: Double] = [:]
        for item in paths { masses[item.path.current.offset] = EngravingMath.add(masses[item.path.current.offset] ?? -.infinity, item.logMass) }
        let offset = masses.keys.sorted().max { masses[$0]! < masses[$1]! }
        let best = paths.first { $0.path.current.offset == offset }?.path
        return EngravingEvidence(paths: paths, residualLogMass: residual, noiseLogMass: noiseLogMass,
                                 totalLogMass: total, best: best, residuals: residuals, noiseUpperLogMass: noiseUpperLogMass)
    }
}
