//
//  ReadTests.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-31.
//

import Testing
import MIDIKit
import FinderItem


@Suite
struct ReadTests {
    @Test func readEmptyData() async throws {
        let data = try FinderItem(at: "/Users/vaida/DataBase/Swift Package/Test Reference/MIDIKit/empty.mid").load(.data)
        let container = try MIDIContainer(data: data)
        #expect(container.tracks == [])
    }
}
