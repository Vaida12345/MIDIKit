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


let container = try await MIDIContainer(at: "'/Users/vaida/Music/Piano Transcription/02 For When You Are Alone.mid'").indexed()
try await container.removingArtifacts(threshold: 40).makeContainer().write(to: .desktopDirectory/"file.mid")
