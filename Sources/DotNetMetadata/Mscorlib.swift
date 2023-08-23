import DotNetMetadataFormat

// The mscorlib assembly, exposing definitions for special types core to the CLI
public final class Mscorlib: Assembly {
    public static let name: String = "mscorlib"

    struct MissingSpecialType: Error {}

    override init(context: AssemblyLoadContext, moduleFile: ModuleFile, tableRow: AssemblyTable.Row) throws {
        try super.init(context: context, moduleFile: moduleFile, tableRow: tableRow)
        specialTypes = try SpecialTypes(assembly: self)
    }

    public var specialTypes: SpecialTypes!

    public final class SpecialTypes {
        init(assembly: Assembly) throws {
            func find<T: TypeDefinition>(_ name: String) throws -> T {
                guard let typeDefinition = assembly.findDefinedType(fullName: "System." + name),
                        let typeDefinition = typeDefinition as? T else {
                    throw MissingSpecialType()
                }
                return typeDefinition
            }

            void = try find("Void")
            object = try find("Object")
            valueType = try find("ValueType")
            `enum` = try find("Enum")
            delegate = try find("Delegate")
            multicastDelegate = try find("MulticastDelegate")
            type = try find("Type")
            typedReference = try find("TypedReference")
            exception = try find("Exception")
            attribute = try find("Attribute")
            string = try find("String")
            array = try find("Array")

            boolean = try find("Boolean")
            char = try find("Char")
            byte = try find("Byte")
            sbyte = try find("SByte")
            uint16 = try find("UInt16")
            int16 = try find("Int16")
            uint32 = try find("UInt32")
            int32 = try find("Int32")
            uint64 = try find("UInt64")
            int64 = try find("Int64")
            uintPtr = try find("UIntPtr")
            intPtr = try find("IntPtr")
            single = try find("Single")
            double = try find("Double")
            guid = try find("Guid")
        }

        public let void: StructDefinition
        public let object: ClassDefinition
        public let valueType: ClassDefinition
        public let `enum`: ClassDefinition
        public let delegate: ClassDefinition
        public let multicastDelegate: ClassDefinition
        public let type: ClassDefinition
        public let typedReference: StructDefinition
        public let exception: ClassDefinition
        public let attribute: ClassDefinition
        public let string: ClassDefinition
        public let array: ClassDefinition

        public let boolean: StructDefinition
        public let char: StructDefinition
        public let byte: StructDefinition
        public let sbyte: StructDefinition
        public let uint16: StructDefinition
        public let int16: StructDefinition
        public let uint32: StructDefinition
        public let int32: StructDefinition
        public let uint64: StructDefinition
        public let int64: StructDefinition
        public let uintPtr: StructDefinition
        public let intPtr: StructDefinition
        public let single: StructDefinition
        public let double: StructDefinition
        public let guid: StructDefinition

        public func getInteger(_ size: IntegerSize, signed: Bool) -> StructDefinition {
            switch size {
                case .int8: return signed ? byte : sbyte
                case .int16: return signed ? int16 : uint16
                case .int32: return signed ? int32 : uint32
                case .int64: return signed ? int64 : uint64
                case .intPtr: return signed ? intPtr : uintPtr
            }
        }
    }
}