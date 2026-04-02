//
//  main.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

#if os(macOS)
import FinderItem
import Foundation
import MIDIKit
import DetailedDescription
import SwiftUI

let score = FinderItem.desktopDirectory/"score.mid"
let transcription = FinderItem.desktopDirectory/"transcription.mid"

let score_container = try await score.load(.MIDIContainer).indexed()
let transcription_container = try await transcription.load(.MIDIContainer).indexed()

let warping = score_container.timeWarp(other: transcription_container)

var copy = score_container.makeContainer()

copy.tracks[0].notes.mutatingForEach { i, note in
    let _onset = note.onset
    let _duration = note.duration
    note.onset = warping.map(_onset)
    note.duration = _duration
}
copy.tracks[0].sustains.mutatingForEach { i, sustain in
    let _duration = sustain.duration
    sustain.onset = warping.map(sustain.onset)
    sustain.duration = _duration
}
try copy.write(to: .desktopDirectory/"copy.mid")

await DebugView(container: copy.indexed()).render(to: .desktopDirectory/"copy.pdf")
await DebugView(container: transcription_container).render(to: .desktopDirectory/"transcription.pdf")
#endif
