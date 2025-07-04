//
//  main.swift
//  MIDIKit
//
//  Created by Vaida on 8/23/24.
//

import FinderItem
import Foundation
import MIDIKit
import DetailedDescription
import SwiftUI
#if os(macOS)

//let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/14 Ballade No. 1 in G minor, Op. 23.mid'")
//let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/Ashes on The Fire - Shingeki no Kyojin.mid'")
let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/10 Clair de lune.mid'")
let date = Date()
var indexed = container.indexed()
indexed.alignFirstNoteToZero()
indexed = indexed.removingArtifacts(threshold: 40)
indexed.normalize(preserve: .acousticResult)

try container.data().write(to: .desktopDirectory/"file.mid")

print(date.distanceToNow())
//try indexed.makeContainer().write(to: .desktopDirectory/"MIDIs"/"file.mid")

indexed.assignHands()
//await DebugView(container: indexed).render(to: .desktopDirectory/"debug.pdf", format: .pdf, scale: 1)
//await DebugPointsPlot().render(to: .desktopDirectory/"points plot.pdf", format: .pdf, scale: 1)
#endif
