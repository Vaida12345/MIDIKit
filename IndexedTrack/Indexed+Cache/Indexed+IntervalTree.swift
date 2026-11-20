//
//  Indexed+IntervalTree.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit
import Intervals


extension IndexedTrack {
    
    /// The notes indexed for overlap queries, such as which notes are sounding at a time stamp.
    ///
    /// The tree is built the first time it is accessed, in O(*n*), and then shared by every copy of this track. It indexes ``notes``, so the indices it returns are indices of ``notes``.
    ///
    /// - Tip: Keep the return value cached instead of accessing it repeatedly.
    public var intervalTree: IntervalTree<[MIDINote]> {
        if let existing = self.cache.intervalTree.withLock({ $0 }) {
            return IntervalTree(self.notes, maxOffsets: existing)
        }
        
        let maxOffsets = IntervalTree<[MIDINote]>.buildMaxOffsets(for: self.notes)
        
        // Another caller may have stored its offsets in the meantime; keep the first, they are identical.
        let stored = self.cache.intervalTree.withLock { stored in
            if let stored { return stored }
            stored = maxOffsets
            return maxOffsets
        }
        return IntervalTree(self.notes, maxOffsets: stored)
    }
    
}
