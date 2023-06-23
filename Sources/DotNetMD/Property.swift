import DotNetMDFormat

public class Property {
    internal unowned let definingTypeImpl: TypeDefinition.MetadataImpl
    internal let tableRowIndex: Table<DotNetMDFormat.Property>.RowIndex
    internal let propertySig: PropertySig

    fileprivate init(definingTypeImpl: TypeDefinition.MetadataImpl, tableRowIndex: Table<DotNetMDFormat.Property>.RowIndex, propertySig: PropertySig) {
        self.definingTypeImpl = definingTypeImpl
        self.tableRowIndex = tableRowIndex
        self.propertySig = propertySig
    }

    internal static func create(definingTypeImpl: TypeDefinition.MetadataImpl, tableRowIndex: Table<DotNetMDFormat.Property>.RowIndex) -> Property {
        let row = definingTypeImpl.database.tables.property[tableRowIndex]
        let propertySig = try! PropertySig(blob: definingTypeImpl.database.heaps.resolve(row.type))
        if propertySig.params.count == 0 {
            return Property(definingTypeImpl: definingTypeImpl, tableRowIndex: tableRowIndex, propertySig: propertySig)
        }
        else {
            return Indexer(definingTypeImpl: definingTypeImpl, tableRowIndex: tableRowIndex, propertySig: propertySig)
        }
    }

    public var definingType: TypeDefinition { definingTypeImpl.owner }
    internal var assemblyImpl: Assembly.MetadataImpl { definingTypeImpl.assemblyImpl }
    internal var database: Database { definingTypeImpl.database }
    private var tableRow: DotNetMDFormat.Property { database.tables.property[tableRowIndex] }

    public var name: String { database.heaps.resolve(tableRow.name) }

    private lazy var _type = Result { assemblyImpl.resolve(propertySig.type, typeContext: definingType) }
    public var type: BoundType { get throws { try _type.get() } }

    private struct Accessors {
        var getter: Method?
        var setter: Method?
        var others: [Method] = []
    }

    private lazy var accessors = Result { [self] in
        var accessors = Accessors()
        for entry in definingTypeImpl.getAccessors(token: MetadataToken(tableRowIndex)) {
            if entry.attributes == .getter { accessors.getter = entry.method }
            else if entry.attributes == .setter { accessors.setter = entry.method }
            else if entry.attributes == .other { accessors.others.append(entry.method) }
            else { fatalError("Unexpected property accessor attributes value") }
        }
        return accessors
    }

    public var getter: Method? { get throws { try accessors.get().getter } }
    public var setter: Method? { get throws { try accessors.get().setter } }
    public var otherAccessors: [Method] { get throws { try accessors.get().others } }

    // CLS adds some uniformity guarantees:
    // §II.22.28 "All methods for a given Property or Event shall have the same accessibility"
    private var anyAccessor: Method? { get throws { try getter ?? setter ?? otherAccessors.first } }
    public var visibility: Visibility { get throws { try anyAccessor?.visibility ?? .public } }
    public var isStatic: Bool { get throws { try anyAccessor?.isStatic ?? false } }
    public var isVirtual: Bool { get throws { try anyAccessor?.isAbstract ?? false } }
    public var isAbstract: Bool { get throws { try anyAccessor?.isVirtual ?? false } }
    public var isFinal: Bool { get throws { try anyAccessor?.isFinal ?? false } }
}

public final class Indexer: Property {
    internal override init(definingTypeImpl: TypeDefinition.MetadataImpl, tableRowIndex: Table<DotNetMDFormat.Property>.RowIndex, propertySig: PropertySig) {
        super.init(definingTypeImpl: definingTypeImpl, tableRowIndex: tableRowIndex, propertySig: propertySig)
    }
}