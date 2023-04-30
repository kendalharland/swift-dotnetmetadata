extension UnsafeRawBufferPointer {
    func sub(offset: Int) -> UnsafeRawBufferPointer {
        UnsafeRawBufferPointer(rebasing: self[offset...])
    }

    func sub(offset: Int, count: Int) -> UnsafeRawBufferPointer {
        UnsafeRawBufferPointer(rebasing: self[offset ..< (offset + count)])
    }

    func bindMemory<T>(offset: Int, to: T.Type) -> UnsafePointer<T> {
        sub(offset: offset).bindMemory(to: T.self).baseAddress!
    }
    
    func bindMemory<T>(offset: Int, to: T.Type, count: Int) -> UnsafeBufferPointer<T> {
        let rebased = UnsafeRawBufferPointer(rebasing: self[offset...])
        let bound = rebased.bindMemory(to: T.self)
        return UnsafeBufferPointer<T>(rebasing: bound[0 ..< count])
    }

    mutating func consume<T>(type: T.Type) -> UnsafePointer<T> {
        let result = bindMemory(offset: 0, to: type)
        self = self.sub(offset: MemoryLayout<T>.stride)
        return result
    }
    
    mutating func consume<T>(type: T.Type, count: Int) -> UnsafeBufferPointer<T> {
        let result = bindMemory(offset: 0, to: type, count: count)
        self = self.sub(offset: MemoryLayout<T>.stride * count)
        return result
    }
    
    mutating func consumeNulPaddedUTF8String(maxLength: Int) -> String {
        let buffer = consume(type: UInt8.self, count: maxLength)
        return String(bytes: buffer.prefix(while: { $0 != 0 }), encoding: .utf8)!
    }
}