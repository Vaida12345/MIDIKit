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

//let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/14 Ballade No. 1 in G minor, Op. 23.mid'")
//let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/Ashes on The Fire - Shingeki no Kyojin.mid'")
let container = try MIDIContainer(at: "/Users/vaida/Music/Piano Transcription/Nuvole Bianche.mid")

var indexed = container.indexed()
let date = Date()
await indexed.normalize(preserve: .notesDisplay)
try await indexed.inferHand()
print(date.distanceToNow())
print("done")

DebugView(container: indexed).render(to: .desktopDirectory/"debug.pdf", format: .pdf, scale: 1)
#endif
