import CoreMIDI
import Darwin
import Foundation

struct EngravingInputState {
    enum Certainty { case unknown, up, down }
    struct Key {
        var state: Certainty = .unknown
        var sounding = false
        var sostenuto = false
        var generation: UInt64 = 0
        var attackTime: MIDITimeStamp = 0
        var ambiguousReattack = false
    }
    struct Observation {
        let event: ParsedInputEvent
        let timestamp: MIDITimeStamp
        let id: UInt64
        let attack: UInt8?
        let released: UInt8?
        let dwell: Double?
        let changed: Bool
        let discontinuity: Bool
    }

    private(set) var keys = Array(repeating: Key(), count: 128)
    private(set) var sustain: Bool?
    private(set) var sostenuto: Bool?
    private(set) var serial: UInt64 = 0
    private var lastValidAttack: MIDITimeStamp = 0

    mutating func consume(_ raw: ParsedInputEvent, timestamp: MIDITimeStamp) -> Observation {
        serial &+= 1
        let event: ParsedInputEvent
        if case let .noteOn(pitch, 0) = raw { event = .noteOff(pitch: pitch) } else { event = raw }
        var attack: UInt8?
        var release: UInt8?
        var dwell: Double?
        var changed = false
        var discontinuity = false
        switch event {
        case let .noteOn(pitch, _) where pitch < 128:
            attack = pitch
            changed = true
            let index = Int(pitch)
            if timestamp != 0 {
                discontinuity = lastValidAttack != 0 && timestamp < lastValidAttack
                lastValidAttack = timestamp
            }
            keys[index].generation = serial
            keys[index].ambiguousReattack = keys[index].state == .down
            // A missing release makes the old duration unknown; this is still a fresh attack.
            keys[index].state = .down
            keys[index].sounding = true
            keys[index].attackTime = timestamp
        case let .noteOff(pitch) where pitch < 128:
            let index = Int(pitch)
            changed = keys[index].state == .down
            if changed {
                release = pitch
                if sustain == false, sostenuto == false, !keys[index].ambiguousReattack {
                    dwell = EngravingHostTime.seconds(from: keys[index].attackTime, to: timestamp)
                }
            }
            keys[index].state = .up
            if sustain == false && !keys[index].sostenuto { keys[index].sounding = false }
        case let .controlChange(control, value):
            let down = value >= 64
            if control == 64 {
                changed = sustain != down
                sustain = down
            } else if control == 66 {
                changed = sostenuto != down
                if down && sostenuto != true {
                    for i in keys.indices { keys[i].sostenuto = keys[i].state == .down }
                } else if !down {
                    for i in keys.indices { keys[i].sostenuto = false }
                }
                sostenuto = down
            } else if control == 120 || control == 123 {
                for i in keys.indices {
                    keys[i].state = .up
                    if control == 120 || sustain == false && !keys[i].sostenuto { keys[i].sounding = false }
                }
                // Channel-mode cleanup is physical information, not alignment evidence.
            } else if control == 121 {
                sustain = false
                sostenuto = false
                for i in keys.indices { keys[i].sostenuto = false }
            }
            if sustain == false {
                for i in keys.indices where keys[i].state == .up && !keys[i].sostenuto { keys[i].sounding = false }
            }
        default: break
        }
        return Observation(event: event, timestamp: timestamp, id: serial, attack: attack,
                           released: release, dwell: dwell, changed: changed, discontinuity: discontinuity)
    }
}

enum EngravingHostTime {
    static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    static func seconds(from start: MIDITimeStamp, to end: MIDITimeStamp) -> Double? {
        guard start != 0, end > start else { return nil }
        let result = Double(end - start) * secondsPerTick
        return result.isFinite ? result : nil
    }
}

/// Robust log-domain distributions. These broad initial scales are uncalibrated policy.
struct EngravingCalibration {
    var blockSpread = log(0.045)
    var rolledSpread = log(0.20)
    var handSpread = log(0.09)
    var support = 0

    mutating func observe(spread: Double, rolled: Bool) {
        guard spread > 0, spread < 5 else { return }
        let value = log(spread)
        let rate = 0.02
        if rolled { rolledSpread += rate * max(-1, min(1, value - rolledSpread)) }
        else { blockSpread += rate * max(-1, min(1, value - blockSpread)) }
        support = min(1_000, support + 1)
    }

    mutating func observeHandOffset(_ spread: Double) {
        guard spread > 0, spread < 5 else { return }
        handSpread += 0.02 * max(-1, min(1, log(spread) - handSpread))
        support = min(1_000, support + 1)
    }
}

struct EngravingTempo: Hashable {
    var secondsPerBeat: Double?
    var logDeviation = 1.2
    var anchorBeat: Double?
    var anchorTime: MIDITimeStamp = 0

    mutating func detach() { anchorBeat = nil; anchorTime = 0; logDeviation = max(1.2, logDeviation) }

    /// A bounded timing compatibility factor. Pitch emissions remain normalized separately.
    func compatibility(beat: Double, time: MIDITimeStamp) -> Double {
        guard let anchorBeat, beat > anchorBeat, let tempo = secondsPerBeat,
              let elapsed = EngravingHostTime.seconds(from: anchorTime, to: time), elapsed < 20 else { return 1 }
        let residual = log(elapsed / ((beat - anchorBeat) * tempo))
        // Student-t shaped contamination mixture: rubato never makes a transition impossible.
        return 0.90 + 0.10 * pow(1 + residual * residual / (4 * logDeviation * logDeviation), -2.5)
    }

    mutating func observe(beat: Double, time: MIDITimeStamp) {
        guard time != 0 else { return }
        if let anchorBeat, beat > anchorBeat,
           let elapsed = EngravingHostTime.seconds(from: anchorTime, to: time) {
            if elapsed < 20 {
                let sample = elapsed / (beat - anchorBeat)
                if let old = secondsPerBeat {
                    let delta = max(-1.5, min(1.5, log(sample / old)))
                    secondsPerBeat = old * exp(0.25 * delta)
                    logDeviation = max(0.45, 0.9 * logDeviation + 0.1 * abs(delta))
                } else { secondsPerBeat = sample }
            } else { detach() }
        }
        anchorBeat = beat
        anchorTime = time
    }
}
