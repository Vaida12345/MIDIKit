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


let container = try await MIDIContainer(at: .desktopDirectory/"MIDIs"/"4-17 Prélude In G-Sharp Minor, Op. 32, No. 12.mid").indexed()
await container.normalize(preserve: .acousticResult)
try container.makeContainer().write(to: .desktopDirectory/"MIDIs"/"file.mid")
