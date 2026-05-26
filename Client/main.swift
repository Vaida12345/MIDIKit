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

let source: FinderItem = "/Volumes/Vaida's T9/Library/Machine Learning/Dataset/PDMX/mid_two_tracks"
let destination: FinderItem = "/Users/vaida/Desktop/midi2hands/src/midi2hands/data/train"

var counter = 0
for child in try source.children(range: .enumeration.noOrder) {
    guard child.extension == "mid" else { continue }
    
    let dest = destination.appending(path: child.relativePath(to: source)!.replacingOccurrences(of: "/", with: ":"))
    try child.copy(to: dest)
    counter += 1
}
print(counter)
#endif
