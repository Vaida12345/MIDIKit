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


let container = try MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/Unravel.mid'")
let date = Date()
let indexed = container.indexed()
indexed.normalize(preserve: .acousticResult)
print(date.distanceToNow())
try indexed.makeContainer().write(to: .desktopDirectory/"MIDIs"/"file.mid")
