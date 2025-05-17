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


//let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/14 Ballade No. 1 in G minor, Op. 23.mid'")
let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/Ashes on The Fire - Shingeki no Kyojin.mid'")
let date = Date()
let indexed = container.indexed()
indexed.alignFirstNoteToZero()
indexed.normalize(preserve: .acousticResult)

print(indexed.contents.first)

print(date.distanceToNow())
//try indexed.makeContainer().write(to: .desktopDirectory/"MIDIs"/"file.mid")

await DebugView(container: indexed).render(to: .desktopDirectory/"debug.pdf", format: .pdf, scale: 1)
