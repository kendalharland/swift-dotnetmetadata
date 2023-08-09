import DotNetMetadataFormat

/// An unbound type definition, which may have generic parameters.
public class TypeDefinition: CustomDebugStringConvertible {
    internal typealias Kind = TypeDefinitionKind
    internal typealias Impl = TypeDefinitionImpl

    public static let nestedTypeSeparator: Character = "/"
    public static let genericParamCountSeparator: Character = "`"

    public let assembly: Assembly
    private let impl: any TypeDefinitionImpl

    fileprivate init(assembly: Assembly, impl: any TypeDefinitionImpl) {
        self.assembly = assembly
        self.impl = impl
        impl.initialize(owner: self)
    }

    internal static func create(assembly: Assembly, impl: any TypeDefinitionImpl) -> TypeDefinition {
        switch impl.kind {
            case .class: return ClassDefinition(assembly: assembly, impl: impl)
            case .interface: return InterfaceDefinition(assembly: assembly, impl: impl)
            case .delegate: return DelegateDefinition(assembly: assembly, impl: impl)
            case .struct: return StructDefinition(assembly: assembly, impl: impl)
            case .enum: return EnumDefinition(assembly: assembly, impl: impl)
        }
    }

    public var context: MetadataContext { assembly.context }

    public var name: String { impl.name }
    public var namespace: String? { impl.namespace }
    public var kind: TypeDefinitionKind { impl.kind }
    internal var metadataAttributes: DotNetMetadataFormat.TypeAttributes { impl.metadataAttributes }
    public var enclosingType: TypeDefinition? { impl.enclosingType }
    public var genericParams: [GenericTypeParam] { impl.genericParams }
    public var base: BoundType? { impl.base }
    public var baseInterfaces: [BaseInterface] { impl.baseInterfaces }
    public var fields: [Field] { impl.fields }
    public var methods: [Method] { impl.methods }
    public var properties: [Property] { impl.properties }
    public var events: [Event] { impl.events }
    public var attributes: [Attribute] { impl.attributes }
    public var nestedTypes: [TypeDefinition] { impl.nestedTypes }

    public var debugDescription: String { "\(fullName) (\(assembly.name) \(assembly.version))" }

    public var nameWithoutGenericSuffix: String {
        let name = name
        guard let index = name.firstIndex(of: Self.genericParamCountSeparator) else { return name }
        return String(name[..<index])
    }

    public private(set) lazy var fullName: String = {
        if let enclosingType {
            assert(namespace == nil)
            return "\(enclosingType.fullName)\(Self.nestedTypeSeparator)\(name)"
        }
        return makeFullTypeName(namespace: namespace, name: name)
    }()

    public var visibility: Visibility { metadataAttributes.visibility }
    public var isNested: Bool { metadataAttributes.isNested }
    public var isAbstract: Bool { metadataAttributes.contains(TypeAttributes.abstract) }
    public var isSealed: Bool { metadataAttributes.contains(TypeAttributes.sealed) }
    public var isValueType: Bool { kind.isValueType }
    public var isReferenceType: Bool { kind.isReferenceType }
    public var layoutKind: LayoutKind { metadataAttributes.layoutKind }

    /// The list of all generic params defined either directly on this
    /// type definition or on one of the enclosing type definitions.
    public private(set) lazy var fullGenericParams: [GenericTypeParam] = {
        var result = genericParams
        var type = self
        while let enclosingType = type.enclosingType {
            result.insert(contentsOf: enclosingType.genericParams, at: 0)
            type = enclosingType
        }
        return result
    }()

    public var layout: TypeLayout {
        switch metadataAttributes.layoutKind {
            case .auto: return .auto
            case .sequential:
                let layout = impl.classLayout
                return .sequential(pack: layout.pack == 0 ? nil : Int(layout.pack), minSize: Int(layout.size))
            case .explicit:
                return .explicit(minSize: Int(impl.classLayout.size))
        }
    }

    public func isMscorlib(namespace: String, name: String) -> Bool {
        assembly is Mscorlib && self.namespace == namespace && self.name == name
    }

    public func isMscorlib(fullName: String) -> Bool {
        assembly is Mscorlib && self.fullName == fullName
    }

    public func findMethod(
        name: String,
        public: Bool? = nil,
        static: Bool? = nil,
        genericArity: Int? = nil,
        arity: Int? = nil,
        paramTypes: [TypeNode]? = nil,
        inherited: Bool = false) -> Method? {

        findMember(
            getter: { $0.methods },
            name: name,
            public: `public`,
            static: `static`,
            predicate: {
                if let genericArity { guard $0.genericArity == genericArity else { return false } }
                if let arity { guard (try? $0.arity) == arity else { return false } }
                if let paramTypes {
                    guard let params = try? $0.params,
                        params.map(\.type) == paramTypes else { return false }
                }
                return true
            },
            inherited: inherited)
    }

    public func findField(
        name: String, 
        public: Bool? = nil,
        static: Bool? = nil,
        inherited: Bool = false) -> Field? {

        findMember(
            getter: { $0.fields },
            name: name,
            public: `public`,
            static: `static`,
            inherited: inherited)
    }

    public func findProperty(
        name: String,
        public: Bool? = nil,
        static: Bool? = nil,
        inherited: Bool = false) -> Property? {

        findMember(
            getter: { $0.properties },
            name: name,
            public: `public`,
            static: `static`,
            inherited: inherited)
    }

    public func findEvent(
        name: String,
        public: Bool? = nil,
        static: Bool? = nil,
        inherited: Bool = false) -> Event? {

        findMember(
            getter: { $0.events },
            name: name,
            public: `public`,
            static: `static`,
            inherited: inherited)
    }

    private func findMember<M: Member>(
        getter: (TypeDefinition) -> [M],
        name: String,
        public: Bool? = nil,
        static: Bool? = nil,
        predicate: ((M) -> Bool)? = nil,
        inherited: Bool = false) -> M? {

        var typeDefinition = self
        while true {
            let member = getter(typeDefinition).single {
                guard $0.name == name else { return false }
                if let `public` { guard ($0.visibility == .public) == `public` else { return false } }
                if let `static` { guard $0.isStatic == `static` else { return false } }
                if let predicate { guard predicate($0) else { return false } }
                return true
            }

            if let member { return member }
            guard inherited, let base = typeDefinition.base else { return nil }
            typeDefinition = base.definition
        }
    }
}

public final class ClassDefinition: TypeDefinition {
    public var finalizer: Method? { findMethod(name: "Finalize", static: false, arity: 0) }
}

public final class InterfaceDefinition: TypeDefinition {
}

public final class DelegateDefinition: TypeDefinition {
    public var invokeMethod: Method { findMethod(name: "Invoke", public: true, static: false)! }
    public var arity: Int { get throws { try invokeMethod.arity } }
}

public final class StructDefinition: TypeDefinition {
}

public final class EnumDefinition: TypeDefinition {
    public var backingField: Field {
        // The backing field is public but with specialName and rtSpecialName
        findField(name: "value__", public: true, static: false)!
    }

    public var underlyingType: TypeDefinition { get throws { try backingField.type.asDefinition! } }

    public private(set) lazy var isFlags: Bool = {
        attributes.contains { (try? $0.type)?.isMscorlib(namespace: "System", name: "FlagsAttribute") == true }
    }()
}

extension TypeDefinition: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    public static func == (lhs: TypeDefinition, rhs: TypeDefinition) -> Bool { lhs === rhs }
}

internal typealias ClassLayoutData = (pack: UInt16, size: UInt32)

internal protocol TypeDefinitionImpl {
    func initialize(owner: TypeDefinition)

    var name: String { get }
    var namespace: String? { get }
    var kind: TypeDefinitionKind { get }
    var metadataAttributes: DotNetMetadataFormat.TypeAttributes { get }
    var classLayout: ClassLayoutData { get }
    var enclosingType: TypeDefinition? { get }
    var genericParams: [GenericTypeParam] { get }
    var base: BoundType? { get }
    var baseInterfaces: [BaseInterface] { get }
    var fields: [Field] { get }
    var methods: [Method] { get }
    var properties: [Property] { get }
    var events: [Event] { get }
    var attributes: [Attribute] { get }
    var nestedTypes: [TypeDefinition] { get }
}

public func makeFullTypeName(namespace: String?, name: String) -> String {
    if let namespace { return "\(namespace).\(name)" }
    else { return name }
}

public func makeFullTypeName(namespace: String?, enclosingName: String, nestedNames: [String]) -> String {
    var result: String
    if let namespace { result = "\(namespace).\(enclosingName)" }
    else { result = enclosingName }

    for nestedName in nestedNames {
        result.append(TypeDefinition.nestedTypeSeparator)
        result += nestedName
    }

    return result
}