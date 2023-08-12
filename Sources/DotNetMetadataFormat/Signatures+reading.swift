import Foundation

extension CustomAttribSig {
    public init(blob: UnsafeRawBufferPointer, params: [ParamSig]) throws {
        var remainder = blob
        try self.init(consuming: &remainder, params: params)
        if remainder.count > 0 { throw InvalidFormatError.signatureBlob }
    }

    init(consuming buffer: inout UnsafeRawBufferPointer, params: [ParamSig]) throws {
        guard SigToken.tryConsume(buffer: &buffer, token: SigToken.CustomAttrib.prolog_0),
            SigToken.tryConsume(buffer: &buffer, token: SigToken.CustomAttrib.prolog_1) else {
            throw InvalidFormatError.signatureBlob
        }

        fixedArgs = try params.map {
            guard !$0.byRef else { throw InvalidFormatError.signatureBlob }
            return try Self.consumeElem(buffer: &buffer, type: $0.type)
        }

        let namedCount = buffer.consume(type: UInt16.self).pointee
        namedArgs = try (0..<namedCount).map { _ in
            let kind: MemberKind
            switch buffer.consume(type: UInt8.self).pointee {
                case SigToken.CustomAttrib.field: kind = .field
                case SigToken.CustomAttrib.property: kind = .property
                default: throw InvalidFormatError.signatureBlob
            }

            let type = try TypeSig(consuming: &buffer)

            guard let name = try consumeSerString(buffer: &buffer) else {
                throw InvalidFormatError.signatureBlob
            }

            return NamedArg(
                memberKind: kind,
                name: name,
                value: try Self.consumeElem(buffer: &buffer, type: type))
        }
    }

    private static func consumeElem(buffer: inout UnsafeRawBufferPointer, type: TypeSig) throws -> Elem {
        switch type {
            case .boolean: return .constant(.boolean(buffer.consume(type: UInt8.self).pointee != 0))
            case .char: return .constant(.char(buffer.consume(type: UTF16.CodeUnit.self).pointee))
            case .integer(size: .int8, signed: true): return .constant(.int8(buffer.consume(type: Int8.self).pointee))
            case .integer(size: .int8, signed: false): return .constant(.uint8(buffer.consume(type: UInt8.self).pointee))
            case .integer(size: .int16, signed: true): return .constant(.int16(buffer.consume(type: Int16.self).pointee))
            case .integer(size: .int16, signed: false): return .constant(.uint16(buffer.consume(type: UInt16.self).pointee))
            case .integer(size: .int32, signed: true): return .constant(.int32(buffer.consume(type: Int32.self).pointee))
            case .integer(size: .int32, signed: false): return .constant(.uint32(buffer.consume(type: UInt32.self).pointee))
            case .integer(size: .int64, signed: true): return .constant(.int64(buffer.consume(type: Int64.self).pointee))
            case .integer(size: .int64, signed: false): return .constant(.uint64(buffer.consume(type: UInt64.self).pointee))
            case .real(double: false): return .constant(.single(buffer.consume(type: Float.self).pointee))
            case .real(double: true): return .constant(.double(buffer.consume(type: Double.self).pointee))
            case .string:
                guard let str = try consumeSerString(buffer: &buffer) else { return .constant(.null) }
                return .constant(.string(str))

            case let .szarray(_, element):
                let length = buffer.consume(type: UInt32.self).pointee
                return try .array((0..<length).map { _ in
                    try consumeElem(buffer: &buffer, type: element)
                })

            default: throw InvalidFormatError.signatureBlob
        }
    }
}

extension FieldSig {
    public init(blob: UnsafeRawBufferPointer) throws {
        var remainder = blob
        try self.init(consuming: &remainder)
        if remainder.count > 0 { throw InvalidFormatError.signatureBlob }
    }

    init(consuming buffer: inout UnsafeRawBufferPointer) throws {
        guard SigToken.tryConsume(buffer: &buffer, token: SigToken.CallingConvention.field) else {
            throw InvalidFormatError.signatureBlob
        }

        self.init(
            customMods: try consumeCustomMods(buffer: &buffer),
            type: try TypeSig(consuming: &buffer))
    }
}

extension MethodDefSig {
    public init(blob: UnsafeRawBufferPointer) throws {
        var remainder = blob
        try self.init(consuming: &remainder)
        if remainder.count > 0 { throw InvalidFormatError.signatureBlob }
    }

    init(consuming buffer: inout UnsafeRawBufferPointer) throws {
        let callingConvention = SigToken.consume(buffer: &buffer)
        let hasThis = (callingConvention & SigToken.CallingConvention.hasThis) != 0
        let hasExplicitThis = hasThis && (callingConvention & SigToken.CallingConvention.explicitThis) != 0

        guard (callingConvention & SigToken.CallingConvention.mask) == SigToken.CallingConvention.default else {
            fatalError("Not implemented: non-default calling convention")
        }

        var paramCount = try consumeSigUInt(buffer: &buffer)
        let returnParam = try ParamSig(consuming: &buffer, return: true)

        let explicitThis: TypeSig?
        if hasExplicitThis {
            assert(paramCount > 0)
            explicitThis = try TypeSig(consuming: &buffer)
            paramCount -= 1
        } else {
            explicitThis = nil
        }

        let params = try (0 ..< paramCount).map { _ in
            try ParamSig(consuming: &buffer, return: false)
        }

        self.init(
            hasThis: hasThis,
            explicitThis: explicitThis,
            genericArity: 0, // TODO: Support generic method signatures
            returnParam: returnParam,
            params: params)
    }
}

extension ParamSig {
    init(consuming buffer: inout UnsafeRawBufferPointer, return: Bool) throws {
        let customMods = try consumeCustomMods(buffer: &buffer)
        if `return` && SigToken.tryConsume(buffer: &buffer, token: SigToken.ElementType.void) {
            self.init(customMods: customMods, byRef: false, type: .void)
        }
        else {
            let byRef = SigToken.tryConsume(buffer: &buffer, token: SigToken.ElementType.byref)
            let type = try TypeSig(consuming: &buffer)
            self.init(customMods: customMods, byRef: byRef, type: type)
        }
    }
}

extension PropertySig {
    public init(blob: UnsafeRawBufferPointer) throws {
        var remainder = blob
        try self.init(consuming: &remainder)
        if remainder.count > 0 { throw InvalidFormatError.signatureBlob }
    }

    init(consuming buffer: inout UnsafeRawBufferPointer) throws {
        let hasThis = SigToken.tryConsume(buffer: &buffer, token: SigToken.CallingConvention.property | SigToken.CallingConvention.hasThis)
        guard hasThis || SigToken.tryConsume(buffer: &buffer, token: SigToken.CallingConvention.property) else {
            throw InvalidFormatError.signatureBlob
        }

        let paramCount = try consumeSigUInt(buffer: &buffer)
        let customMods = try consumeCustomMods(buffer: &buffer)
        let type = try TypeSig(consuming: &buffer)
        let params = try (0 ..< paramCount).map { _ in
            try ParamSig(consuming: &buffer, return: false)
        }

        self.init(
            hasThis: hasThis,
            customMods: customMods,
            type: type,
            params: params)
    }
}

extension TypeSig {
    public init(blob: UnsafeRawBufferPointer) throws {
        var remainder = blob
        try self.init(consuming: &remainder)
        if remainder.count > 0 { throw InvalidFormatError.signatureBlob }
    }

    init(consuming buffer: inout UnsafeRawBufferPointer) throws {
        let token = SigToken.consume(buffer: &buffer)
        switch token {
            // Leaf types
            case SigToken.ElementType.boolean: self = .boolean
            case SigToken.ElementType.char: self = .char
            case SigToken.ElementType.i1: self = .integer(size: .int8, signed: true)
            case SigToken.ElementType.u1: self = .integer(size: .int8, signed: false)
            case SigToken.ElementType.i2: self = .integer(size: .int16, signed: true)
            case SigToken.ElementType.u2: self = .integer(size: .int16, signed: false)
            case SigToken.ElementType.i4: self = .integer(size: .int32, signed: true)
            case SigToken.ElementType.u4: self = .integer(size: .int32, signed: false)
            case SigToken.ElementType.i8: self = .integer(size: .int64, signed: true)
            case SigToken.ElementType.u8: self = .integer(size: .int64, signed: false)
            case SigToken.ElementType.i: self = .integer(size: .intPtr, signed: true)
            case SigToken.ElementType.u: self = .integer(size: .intPtr, signed: false)
            case SigToken.ElementType.r4: self = .real(double: false)
            case SigToken.ElementType.r8: self = .real(double: true)
            case SigToken.ElementType.object: self = .object
            case SigToken.ElementType.string: self = .string

            case SigToken.ElementType.`class`, SigToken.ElementType.valueType, SigToken.ElementType.genericInst:
                let `class`: Bool
                if token == SigToken.ElementType.genericInst {
                    `class` = SigToken.tryConsume(buffer: &buffer, token: SigToken.ElementType.`class`)
                    guard `class` || SigToken.tryConsume(buffer: &buffer, token: SigToken.ElementType.valueType) else {
                        throw InvalidFormatError.signatureBlob
                    }
                }
                else {
                    `class` = token == SigToken.ElementType.`class`
                }

                let index = try consumeTypeDefOrRefEncoded(buffer: &buffer, allowSpec: true)

                let genericArgs: [TypeSig]
                if token == SigToken.ElementType.genericInst {
                    let genericArgCount = try consumeSigUInt(buffer: &buffer)
                    genericArgs = try (0..<genericArgCount).map { _ in try TypeSig(consuming: &buffer) }
                }
                else {
                    genericArgs = []
                }

                self = .defOrRef(index: index, class: `class`, genericArgs: genericArgs)

            case SigToken.ElementType.szarray:
                let customMods = try consumeCustomMods(buffer: &buffer)
                self = .szarray(customMods: customMods, element: try TypeSig(consuming: &buffer))

            case SigToken.ElementType.var, SigToken.ElementType.mvar:
                let index = try consumeSigUInt(buffer: &buffer)
                self = .genericArg(index: index, method: token == SigToken.ElementType.mvar)

            case let b:
                print(b)
                fflush(stdout)
                throw InvalidFormatError.signatureBlob
        }
    }
}

fileprivate func consumeSerString(buffer: inout UnsafeRawBufferPointer) throws -> String? {
    let length = consumeCompressedUInt(buffer: &buffer)
    guard let length else { return nil }
    return String(decoding: buffer.consume(type: UTF8.CodeUnit.self, count: Int(length)), as: UTF8.self)
}

fileprivate func consumeSigUInt(buffer: inout UnsafeRawBufferPointer) throws -> UInt32 {
    try consumeCompressedUInt(buffer: &buffer) ?? { throw InvalidFormatError.signatureBlob }()
}

// §II.23.2.8
fileprivate func consumeTypeDefOrRefEncoded(buffer: inout UnsafeRawBufferPointer, allowSpec: Bool) throws -> TypeDefOrRef {
    let encoded = try consumeSigUInt(buffer: &buffer)
    let tag = encoded & 0b11
    let index = encoded >> 2

    if tag == 0 {
        return .typeDef(.init(oneBased: index))
    }
    else if tag == 1 {
        return .typeRef(.init(oneBased: index))
    } else if tag == 2 && allowSpec {
        return .typeSpec(.init(oneBased: index))
    }

    throw InvalidFormatError.signatureBlob
}

fileprivate func consumeCustomMods(buffer: inout UnsafeRawBufferPointer) throws -> [CustomModSig] {
    var customMods: [CustomModSig] = []
    while true {
        let isRequired = SigToken.tryConsume(buffer: &buffer, token: SigToken.ElementType.cmodReqd)
        guard isRequired || SigToken.tryConsume(buffer: &buffer, token: SigToken.ElementType.cmodOpt) else {
            break
        }

        let type = try consumeTypeDefOrRefEncoded(buffer: &buffer, allowSpec: false)
        customMods.append(.init(isRequired: isRequired, type: type))
    }

    return customMods
}