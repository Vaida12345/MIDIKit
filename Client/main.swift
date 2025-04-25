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


let date = Date()
defer {
    print(date.distanceToNow())
}


let container = try await MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/09 Variations on the Kanon.mid'").indexed()
await container.normalize(preserve: .acousticResult)
try container.makeContainer().write(to: .desktopDirectory/"MIDIs"/"file.mid")


let engine = PianoEngine()
try await engine.start()
engine.play(note: 88, velocity: 100)
try await Task.sleep(for: .seconds(10))
