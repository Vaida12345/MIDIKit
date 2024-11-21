//
//  Heap.swift
//  The Stratum Module - Algorithms
//
//  Created by Vaida on 10/18/22.
//  Copyright © 2019 - 2024 Vaida. All rights reserved.
//


/// A specialized tree-based data structure.
internal struct Heap<Element>: ExpressibleByArrayLiteral where Element: Comparable {
    
    private var contents: [Element]
    
    
    // MARK: - Basic Properties
    
    private var heapType: HeapType
    
    
    // MARK: - Instance Properties
    
    public var count: Int {
        self.contents.count
    }
    
    public var isEmpty: Bool {
        self.contents.isEmpty
    }
    
    
    // MARK: - Instance Methods
    
    /// Up-heap, used in adding elements.
    ///
    /// - Complexity: O(log *n*), where *n*: length of heap
    private mutating func upHeap(at index: Int) {
        
        var index = index
        var parentIndex = Heap.parentIndex(of: index)
        
        while index > 0 && isInOrder(self.contents[index], self.contents[parentIndex]) { // Compare priority of current child and its parent
            self.contents.swapAt(index, parentIndex) // If the child's position is incorrect, swap it with its parent
            index = parentIndex
            parentIndex = Heap.parentIndex(of: index)
        }
    }
    
    /// Fixing the heap after deleting an element.
    ///
    /// - Complexity: O(log *n*), where *n*: length of heap
    private mutating func downHeap(at index: Int) {
        let leftChildIndex = Heap.leftChildIndex(of: index)
        let rightChildIndex = leftChildIndex + 1
        var maxIndex = index
        
        if leftChildIndex < self.count && isInOrder(self.contents[leftChildIndex], self.contents[maxIndex]) { maxIndex = leftChildIndex } // Compare priority of current parent and its children
        if rightChildIndex < self.count && isInOrder(self.contents[rightChildIndex], self.contents[maxIndex]) { maxIndex = rightChildIndex }
        
        guard maxIndex != index else { return }
           
        contents.swapAt(index, maxIndex) // If the parent's position is incorrect, swap it with the highest-priority child
        self.downHeap(at: maxIndex)
    }
    
    /// Add an element to its correct location.
    ///
    /// - Complexity: O(log *n*), where *n*: length of heap
    public mutating func append(_ element: Element) {
        self.contents.append(element)
        self.upHeap(at: self.count - 1)
    }
    
    
    /// Add an element to its correct location.
    ///
    /// - Complexity: O(*n* log *n*), where *n*: length of resulting heap.
    public mutating func append(contentsOf sequence: some Sequence<Element>) {
        self.contents.append(contentsOf: sequence)
        self.heapify()
    }
    
    /// Access the first element without modifying the heap.
    public var first: Element? {
        self.contents.first
    }
    
    /// Dequeues the element with the highest / lowest priority.
    ///
    /// - Complexity: O(log *n*), where *n*: length of heap
    @discardableResult
    public mutating func removeFirst() -> Element? {
        guard !self.isEmpty else { return nil }
        
        if self.count > 1 {
            let value = self.contents.first!
            self.contents[0] = self.contents.removeLast()
            
            self.downHeap(at: 0)
            
            return value
        } else {
            return self.contents.removeLast()
        }
    }
    
    private func isInOrder(_ lhs: Element, _ rhs: Element) -> Bool {
        heapType == .maxHeap ? lhs > rhs : lhs < rhs
    }
    
    /// Restore heap property
    ///
    /// - Complexity: O(*n* log *n*), where *n*: the array length
    private mutating func heapify() {
        for i in stride(from: self.contents.count / 2 - 1, through: 0, by: -1) {
            downHeap(at: i) // Join the freshly-verified sub-heap with its parent, Verify the heap condition for this larger sub-heap
        }
    }
    
    
    // MARK: - Designated Initializers
    
    /// Initialize with the type. (ie, `maxHeap` or `minHeap`)
    public init(_ type: HeapType = .maxHeap) {
        self.contents = []
        self.heapType = type
    }
    
    
    // MARK: - Initializers
    
    /// Initialize using Bottom-Up Heap Construction
    ///
    /// - Complexity: O(*n*), where *n*: the array length
    public init(_ type: HeapType = .maxHeap, from array: [Element]) {
        self.init(type)
        self.contents = array
        
        self.heapify()
    }
    
    /// Create an instance given the array literal of element.
    public init(arrayLiteral elements: Element...) {
        self.init(from: elements)
    }
    
    
    // MARK: - Type Methods
    
    private static func parentIndex(of index: Int) -> Int {
        (index - 1) / 2
    }
    
    private static func leftChildIndex(of index: Int) -> Int {
        2 * index + 1
    }
    
    
    //MARK: - Substructures
    
    /// Th type of heap, ie, max or min.
    public enum HeapType: Sendable {
        /// A heap whose max element is at the start.
        case maxHeap
        
        /// A heap whose min element is at the start.
        case minHeap
    }
    
}


internal extension Array {
    
    init(_ heap: Heap<Element>) where Element: Comparable {
        self = Array(unsafeUninitializedCapacity: heap.count) { buffer, initializedCount in
            var heap = heap
            initializedCount = 0
            while let next = heap.next() {
                buffer[initializedCount] = next
                initializedCount &+= 1
            }
        }
    }
    
}


extension Heap: IteratorProtocol {
    
    @inlinable
    public mutating func next() -> Element? {
        self.removeFirst()
    }
    
}

extension Heap: Sequence { }


extension Heap: Sendable where Element: Sendable { }


internal extension Sequence {
    
    /// Returns the `k`th minimum value.
    ///
    /// - Parameters:
    ///   - k: The `k`th value.
    ///
    /// - Complexity: O(*n* log *k*), where *n*: number of elements.
    func min(k: Int) -> Element? where Element: Comparable {
        var heap = Heap<Element>(.maxHeap)
        
        for element in self {
            if heap.count >= k { heap.removeFirst() }
            heap.append(element)
        }
        
        return heap.removeFirst()
    }
    
    /// Returns the `k`th maximum value.
    ///
    /// - Parameters:
    ///   - k: The `k`th value.
    ///
    /// - Complexity: O(*n* log *k*), where *n*: number of elements.
    func max(k: Int) -> Element? where Element: Comparable {
        var heap = Heap<Element>(.minHeap)
        
        for element in self {
            if heap.count >= k { heap.removeFirst() }
            heap.append(element)
        }
        
        return heap.removeFirst()
    }
    
}
