//
//  Container + Trim.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import AudioToolbox


extension MIDIContainer {

    /// Shifts everything so that the earliest note starts at 0, removing the silence before it.
    ///
    /// Every timestamp of every track and of the tempo track moves back by the onset of the earliest note, in beats. Relative timing doesn't change. What would land before 0 is handled so that the opening sounds the same:
    ///
    /// - A sustain that is down at the first note starts at 0 instead. One that ends by then is removed.
    /// - Control events, meta events and raw data from before the first note move to 0, in their original order, so the track name, key and time signatures, and the last value of each controller are kept.
    /// - The tempo in effect at the first note moves to 0, and earlier tempos are removed.
    ///
    /// Nothing changes when there are no notes, or when the earliest note already starts at 0. If a note starts before 0, everything moves later instead.
    ///
    /// - Note: Unless the silence is a whole number of measures, the measures move relative to the notes.
    ///
    /// - Complexity: O(*n*), where *n* is the number of events.
    public mutating func trimLeadingSilence() {
        var shift: MusicTimeStamp? = nil
        for track in self.tracks {
            for note in track.notes {
                shift = Swift.min(shift ?? note.onset, note.onset)
            }
        }
        guard let shift, shift != 0 else { return }

        var index = 0
        while index < self.tracks.count {
            self.tracks[index].shiftTimes(by: shift)
            index &+= 1
        }
        self.tempo.shiftTimes(by: shift)
    }

    /// Returns the container shifted so that the earliest note starts at 0, removing the silence before it.
    ///
    /// - SeeAlso: ``trimLeadingSilence()``
    public func trimmingLeadingSilence() -> MIDIContainer {
        var copy = self
        copy.trimLeadingSilence()
        return copy
    }

}


extension MIDITrack {

    /// Moves every timestamp back by `shift` beats, clamping what would land before 0 to 0, and removing sustains that would end by 0.
    ///
    /// Clamping never reorders events, so sorted lists stay sorted.
    mutating func shiftTimes(by shift: MusicTimeStamp) {
        var index = 0
        while index < self.notes.contents.count {
            self.notes.contents[index].onset -= shift
            self.notes.contents[index].offset -= shift
            index &+= 1
        }

        index = 0
        while index < self.sustains.contents.count {
            self.sustains.contents[index].onset = Swift.max(self.sustains.contents[index].onset - shift, 0)
            self.sustains.contents[index].offset -= shift
            index &+= 1
        }
        self.sustains.contents.removeAll { $0.offset <= 0 }

        index = 0
        while index < self.channelEvents.contents.count {
            self.channelEvents.contents[index].onset = Swift.max(self.channelEvents.contents[index].onset - shift, 0)
            index &+= 1
        }

        index = 0
        while index < self.metaEvents.count {
            self.metaEvents[index].timestamp = Swift.max(self.metaEvents[index].timestamp - shift, 0)
            index &+= 1
        }

        self.rawData = self.rawData.map {
            MIDIRawData(timestamp: Swift.max($0.timestamp - shift, 0), data: $0.data)
        }
    }

}


extension MIDITempoTrack {

    /// Moves every timestamp back by `shift` beats. The tempo in effect at `shift` moves to 0 and earlier tempos are removed; meta events that would land before 0 move to 0.
    mutating func shiftTimes(by shift: MusicTimeStamp) {
        // The tempo in effect at `shift` is the last one at or before it.
        var inEffect: Int? = nil
        var index = 0
        while index < self.contents.count {
            if self.contents[index].timestamp <= shift && inEffect.isNil(or: { self.contents[$0].timestamp <= self.contents[index].timestamp }) {
                inEffect = index
            }
            index &+= 1
        }

        var tempos: [Tempo] = []
        tempos.reserveCapacity(self.contents.count)
        index = 0
        while index < self.contents.count {
            let tempo = self.contents[index]
            if index == inEffect {
                tempos.append(Tempo(timestamp: 0, tempo: tempo.tempo))
            } else if tempo.timestamp > shift {
                tempos.append(Tempo(timestamp: tempo.timestamp - shift, tempo: tempo.tempo))
            }
            index &+= 1
        }
        self.contents = tempos

        index = 0
        while index < self.events.count {
            self.events[index].timestamp = Swift.max(self.events[index].timestamp - shift, 0)
            index &+= 1
        }
    }

}
