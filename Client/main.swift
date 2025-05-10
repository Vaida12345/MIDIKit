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


let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/09 Variations on the Kanon.mid'")
let date = Date()
let indexed = await container.indexed()
await indexed.normalize(preserve: .acousticResult)
print(date.distanceToNow())
try indexed.makeContainer().write(to: .desktopDirectory/"MIDIs"/"file.mid")
