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


let container = try await MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/Hungarian Rhapsody No. 2 in C-sharp minor.mid'").indexed()
await container.normalize(preserve: .acousticResult)
try container.makeContainer().write(to: .desktopDirectory/"MIDIs"/"file.mid")
