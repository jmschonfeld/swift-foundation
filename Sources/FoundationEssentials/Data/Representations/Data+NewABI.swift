//
//  Data+NewABI.swift
//  swift-foundation
//
//  Created by Jeremy Schonfeld on 11/10/25.
//

import Builtin

extension Data {
    @frozen
    @usableFromInline
    internal struct _Representation : Sendable {
        @usableFromInline var storage: __DataStorage
        @usableFromInline var slice: Range<Int>
        
        @inlinable // This is @inlinable as a trivial initializer.
        init(_ buffer: UnsafeRawBufferPointer) {
            self.init(__DataStorage(bytes: buffer.baseAddress, length: buffer.count), count: buffer.count)
        }
        
        @inlinable // This is @inlinable as a trivial initializer.
        init(_ buffer: UnsafeRawBufferPointer, owner: AnyObject) {
            let count = buffer.count
            let storage = __DataStorage(bytes: UnsafeMutableRawPointer(mutating: buffer.baseAddress), length: count, copy: false, deallocator: { _, _ in
                _fixLifetime(owner)
            }, offset: 0)
            self.init(storage, count: count)
        }
        
        @inlinable // This is @inlinable as a trivial initializer.
        init(capacity: Int) {
            self.init(__DataStorage(capacity: capacity), count: 0)
        }
        
        @inlinable // This is @inlinable as a trivial initializer.
        init(count: Int) {
            self.init(__DataStorage(length: count), count: count)
        }
        
        @inlinable // This is @inlinable as a trivial initializer.
        init(_ storage: __DataStorage, count: Int) {
            self.storage = storage
            self.slice = 0..<count
        }
        
        @inlinable @inline(__always) // This is @inlinable as trivially computable (and inlining may help avoid retain-release traffic).
        mutating func ensureUniqueReference() {
            if _slowPath(!isKnownUniquelyReferenced(&storage)) {
                _makeUniqueSlow()
            }
        }
        
        @inlinable
        mutating func _makeUniqueSlow() {
            storage = storage.mutableCopy(self.slice)
        }
        
        @inlinable // This is @inlinable as trivially computable (and inlining may help avoid retain-release traffic).
        mutating func reserveCapacity(_ minimumCapacity: Int) {
            ensureUniqueReference()
            // the current capacity can be zero (representing externally owned buffer), and count can be greater than the capacity
            storage.ensureUniqueBufferReference(growingTo: Swift.max(minimumCapacity, count))
        }
        
        @inlinable // This is @inlinable as reasonably small.
        var count: Int {
            get {
                slice.upperBound - slice.lowerBound
            }
            set(newValue) {
                ensureUniqueReference()
                
                let difference = newValue - count
                if difference > 0 {
                    let additionalRange = Range(uncheckedBounds: (slice.upperBound, slice.upperBound + difference))
                    storage.resetBytes(in: additionalRange) // Also extends storage length
                } else {
                    storage.length += difference
                }
                slice = Range(uncheckedBounds: (slice.lowerBound, (slice.lowerBound + newValue)))
            }
        }
        
        @inlinable @inline(__always) // This is @inlinable as a generic, trivially forwarding function.
        func withUnsafeBytes<Result>(_ apply: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
            return try storage.withUnsafeBytes(in: slice, apply: apply)
        }
        
        @inlinable // This is @inlinable as a generic, trivially forwarding function.
        mutating func withUnsafeMutableBytes<Result>(_ apply: (UnsafeMutableRawBufferPointer) throws -> Result) rethrows -> Result {
            ensureUniqueReference()
            return try storage.withUnsafeMutableBytes(in: slice, apply: apply)
        }
        
        @usableFromInline // This is not @inlinable as it is a non-trivial, non-generic function.
        func enumerateBytes(_ block: (_ buffer: UnsafeBufferPointer<UInt8>, _ byteIndex: Index, _ stop: inout Bool) -> Void) {
            storage.enumerateBytes(in: slice, block)
        }
        
        @inlinable // This is @inlinable as reasonably small.
        mutating func append(contentsOf buffer: UnsafeRawBufferPointer) {
            ensureUniqueReference()
            let upperbound = storage.length + storage._offset
            storage.replaceBytes(in: slice.upperBound ..< upperbound, with: buffer.baseAddress, length: buffer.count)
            slice = Range(uncheckedBounds: (slice.lowerBound, (slice.upperBound + buffer.count)))
        }
        
        @inlinable // This is @inlinable as reasonably small.
        mutating func resetBytes(in range: Range<Index>) {
            precondition(range.lowerBound <= endIndex, "Index out of bounds")
            ensureUniqueReference()
            storage.resetBytes(in: range)
            if slice.upperBound < range.upperBound {
                slice = Range(uncheckedBounds: (slice.lowerBound, range.upperBound))
            }
        }
        
        @_alwaysEmitIntoClient // This is not @inlinable as it is a non-trivial, non-generic function.
        mutating func replaceSubrange(_ subrange: Range<Index>, with bytes: UnsafeRawPointer?, count cnt: Int) {
            precondition(startIndex <= subrange.lowerBound, "Index out of bounds")
            precondition(subrange.upperBound <= endIndex, "Index out of bounds")
            
            ensureUniqueReference()
            let upper = slice.upperBound
            storage.replaceBytes(in: subrange, with: bytes, length: cnt)
            let resultingUpper = upper &- (subrange.upperBound &- subrange.lowerBound) + cnt
            slice = Range(uncheckedBounds: (slice.lowerBound, resultingUpper))
        }
        
        @_alwaysEmitIntoClient
        @inline(never)
        mutating func _appendSlow(_ byte: UInt8) {
            Swift.withUnsafeBytes(of: byte) {
                self.replaceSubrange(endIndex ..< endIndex, with: $0.baseAddress, count: 1)
            }
        }
        
        @_alwaysEmitIntoClient
        @inline(__always)
        mutating func append(_ byte: UInt8) {
            ensureUniqueReference()
            if _slowPath(endIndex != storage._length &+ storage._offset) {
                _appendSlow(byte)
            } else {
                let newLength = storage._length &+ 1
                storage.ensureUniqueBufferReference(growingTo: newLength)
                storage._bytes.unsafelyUnwrapped.storeBytes(of: byte, toByteOffset: storage._length, as: UInt8.self)
                storage._length = newLength
                slice = Range(uncheckedBounds: (slice.lowerBound, slice.upperBound &+ 1))
            }
        }
        
        @inlinable // This is @inlinable as reasonably small.
        subscript(index: Index) -> UInt8 {
            get {
                precondition(startIndex <= index, "Index out of bounds")
                precondition(index < endIndex, "Index out of bounds")
                return storage.get(index)
            }
            set(newValue) {
                precondition(startIndex <= index, "Index out of bounds")
                precondition(index < endIndex, "Index out of bounds")
                ensureUniqueReference()
                storage.set(index, to: newValue)
            }
        }
        
        @inlinable // This is @inlinable as reasonably small.
        subscript(bounds: Range<Index>) -> Data {
            get {
                precondition(slice.startIndex <= bounds.lowerBound, "Index out of bounds")
                precondition(bounds.lowerBound <= slice.endIndex, "Index out of bounds")
                precondition(slice.startIndex <= bounds.upperBound, "Index out of bounds")
                precondition(bounds.upperBound <= slice.endIndex, "Index out of bounds")
                var newRep = self
                newRep.slice = bounds
                return Data(representation: newRep)
            }
        }
        
        @inlinable // This is @inlinable as trivially forwarding.
        var startIndex: Int {
            slice.lowerBound
        }
        
        @inlinable @inline(__always) // This is @inlinable as trivially forwarding.
        var endIndex: Int {
            slice.upperBound
        }
        
        @inlinable // This is @inlinable as trivially forwarding.
        func copyBytes(to pointer: UnsafeMutableRawPointer, from range: Range<Int>) {
            precondition(startIndex <= range.lowerBound, "Index out of bounds")
            precondition(range.lowerBound <= endIndex, "Index out of bounds")
            precondition(startIndex <= range.upperBound, "Index out of bounds")
            precondition(range.upperBound <= endIndex, "Index out of bounds")
            storage.copyBytes(to: pointer, from: range)
        }
        
        @inline(__always) // This should always be inlined into Data.hash(into:).
        func hash(into hasher: inout Hasher) {
            hasher.combine(count)
            
            // At most, hash the first 80 bytes of this data.
            let range = startIndex ..< Swift.min(startIndex + 80, endIndex)
            storage.withUnsafeBytes(in: range) {
                hasher.combine(bytes: $0)
            }
        }
    }
}
