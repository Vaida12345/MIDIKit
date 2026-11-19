//
//  Indexed+Cache.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Synchronization


extension IndexedTrack {
    
    /// The storage for the structures derived from an ``IndexedTrack``'s notes.
    ///
    /// Each value starts as `nil` and is stored the first time it is computed. As a track never changes, a stored value stays valid for the lifetime of the cache.
    internal final class Cache: Sendable {
        
        /// The notes grouped by key, see ``IndexedTrack/lanes``.
        let lanes = Mutex<Lanes?>(nil)
        
    }
    
}
