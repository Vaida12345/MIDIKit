//
//  debug.swift
//  MIDIKit
//
//  Created by Vaida on 12/21/24.
//

import MIDIKit


func flushAverage(container: IndexedContainer, track: inout MIDITrack) {
    var average = container.average.contents.makeIterator()
    var current = average.next()
    var next = average.next()
    while current != nil, next != nil {
        track.notes.append(MIDINotes.Note(onset: current!.onset, offset: max(current!.onset + 1/64, next!.onset), note: current!.note, velocity: 127 / 2, channel: 5))
        current = next
        next = average.next()
    }
}
