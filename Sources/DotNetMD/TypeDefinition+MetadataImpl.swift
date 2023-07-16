import DotNetMDFormat

extension TypeDefinition {
    final class MetadataImpl: Impl {
        internal private(set) unowned var owner: TypeDefinition!
        internal unowned let assemblyImpl: Assembly.MetadataImpl
        internal let tableRowIndex: TypeDefTable.RowIndex

        init(assemblyImpl: Assembly.MetadataImpl, tableRowIndex: TypeDefTable.RowIndex) {
            self.assemblyImpl = assemblyImpl
            self.tableRowIndex = tableRowIndex
        }

        func initialize(owner: TypeDefinition) {
            self.owner = owner
        }

        internal var assembly: Assembly { assemblyImpl.owner }
        internal var database: Database { assemblyImpl.database }

        private var tableRow: TypeDefTable.Row { database.tables.typeDef[tableRowIndex] }

        internal var kind: TypeDefinitionKind {
            // Figuring out the kind requires checking the base type,
            // but we must be careful to not look up any other `TypeDefinition`
            // instances since they might not have been created yet.
            // For safety, implement this at the physical layer.
            database.getTypeDefinitionKind(tableRow, isMscorlib: assembly.name == Mscorlib.name)
        }

        public var name: String { database.heaps.resolve(tableRow.typeName) }

        public var namespace: String? {
            let tableRow = tableRow
            // Normally, no namespace is represented by a zero string heap index
            guard tableRow.typeNamespace.value != 0 else { return nil }
            let value = database.heaps.resolve(tableRow.typeNamespace)
            return value.isEmpty ? nil : value
        }

        internal var metadataAttributes: DotNetMDFormat.TypeAttributes { tableRow.flags }

        public private(set) lazy var enclosingType: TypeDefinition? = {
            guard let nestedClassRowIndex = database.tables.nestedClass.findAny(primaryKey: MetadataToken(tableRowIndex).tableKey) else { return nil }
            guard let enclosingTypeDefRowIndex = database.tables.nestedClass[nestedClassRowIndex].enclosingClass else { return nil }
            return assemblyImpl.resolve(enclosingTypeDefRowIndex)
        }()

        public private(set) lazy var genericParams: [GenericTypeParam] = {
            GenericParam.resolve(from: database, forOwner: .typeDef(tableRowIndex)) {
                GenericTypeParam(definingTypeImpl: self, tableRowIndex: $0)
            }
        }()

        public private(set) lazy var base: BoundType? = assemblyImpl.resolve(tableRow.extends)

        public private(set) lazy var baseInterfaces: [BaseInterface] = {
            let primaryKey = MetadataToken(tableRowIndex).tableKey
            var result: [BaseInterface] = []
            guard var interfaceImplRowIndex = database.tables.interfaceImpl
                .findFirst(primaryKey: primaryKey) else { return [] }
            while interfaceImplRowIndex != database.tables.interfaceImpl.endIndex {
                let interfaceImpl = database.tables.interfaceImpl[interfaceImplRowIndex]
                guard interfaceImpl.primaryKey == primaryKey else { break }
                result.append(BaseInterface(inheritingTypeImpl: self, tableRowIndex: interfaceImplRowIndex))
                interfaceImplRowIndex = database.tables.interfaceImpl.index(after: interfaceImplRowIndex)
            }

            return result
        }()

        public private(set) lazy var methods: [Method] = {
            getChildRowRange(parent: database.tables.typeDef,
                parentRowIndex: tableRowIndex,
                childTable: database.tables.methodDef,
                childSelector: { $0.methodList }).map {
                Method.create(definingTypeImpl: self, tableRowIndex: $0)
            }
        }()

        public private(set) lazy var fields: [Field] = {
            getChildRowRange(parent: database.tables.typeDef,
                parentRowIndex: tableRowIndex,
                childTable: database.tables.field,
                childSelector: { $0.fieldList }).map {
                Field(definingTypeImpl: self, tableRowIndex: $0)
            }
        }()

        public private(set) lazy var properties: [Property] = {
            guard let propertyMapRowIndex = assemblyImpl.findPropertyMap(forTypeDef: tableRowIndex) else { return [] }
            return getChildRowRange(parent: database.tables.propertyMap,
                parentRowIndex: propertyMapRowIndex,
                childTable: database.tables.property,
                childSelector: { $0.propertyList }).map {
                Property.create(definingTypeImpl: self, tableRowIndex: $0)
            }
        }()

        public private(set) lazy var events: [Event] = {
            guard let eventMapRowIndex: EventMapTable.RowIndex = assemblyImpl.findEventMap(forTypeDef: tableRowIndex) else { return [] }
            return getChildRowRange(parent: database.tables.eventMap,
                parentRowIndex: eventMapRowIndex,
                childTable: database.tables.event,
                childSelector: { $0.eventList }).map {
                Event(definingTypeImpl: self, tableRowIndex: $0)
            }
        }()

        internal func getAccessors(owner: HasSemantics) -> [(method: Method, attributes: MethodSemanticsAttributes)] {
            let primaryKey = owner.metadataToken.tableKey
            var result = [(method: Method, attributes: MethodSemanticsAttributes)].init()
            guard var semanticsRowIndex = database.tables.methodSemantics.findFirst(primaryKey: primaryKey) else { return result }
            while semanticsRowIndex != database.tables.methodSemantics.endIndex {
                let semanticsRow = database.tables.methodSemantics[semanticsRowIndex]
                guard semanticsRow.primaryKey == primaryKey else { break }

                let method = methods.first { $0.tableRowIndex == semanticsRow.method }!
                result.append((method, semanticsRow.semantics))
                semanticsRowIndex = database.tables.methodSemantics.index(after: semanticsRowIndex)
            }

            return result
        }
    }
}