@testable import DotNetXMLDocs
import XCTest

final class MemberKeyTests: XCTestCase {
    func testParseInvalid() throws {
        XCTAssertThrowsError(try MemberKey(parsing: ""))
        XCTAssertThrowsError(try MemberKey(parsing: "Hello"))
        XCTAssertThrowsError(try MemberKey(parsing: "K:Identifier"))
    }

    func testParseType() throws {
        XCTAssertEqual(try MemberKey(parsing: "T:TypeName"), .type(fullName: "TypeName"))
        XCTAssertEqual(try MemberKey(parsing: "T:Namespace.TypeName"), .type(fullName: "Namespace.TypeName"))
        XCTAssertEqual(try MemberKey(parsing: "T:Namespace.GenericTypeName`1"), .type(fullName: "Namespace.GenericTypeName`1"))
    }

    func testParseParameterlessMember() throws {
        XCTAssertEqual(
            try MemberKey(parsing: "F:TypeName.Field"),
            .field(declaringType: "TypeName", name: "Field"))
        XCTAssertEqual(
            try MemberKey(parsing: "P:Namespace.TypeName.Property"),
            .property(declaringType: "Namespace.TypeName", name: "Property"))
        XCTAssertEqual(
            try MemberKey(parsing: "E:TypeName`1.Event"),
            .event(declaringType: "TypeName`1", name: "Event"))
        XCTAssertEqual(
            try MemberKey(parsing: "M:TypeName.Method"),
            .method(declaringType: "TypeName", name: "Method"))

        // Should have a type name followed by a member name
        XCTAssertThrowsError(
            try MemberKey(parsing: "F:Identifier"))
    }

    func testParseMethod() throws {
        XCTAssertEqual(
            try MemberKey(parsing: "M:TypeName.Method(InParamType,OutParamType@)"),
            .method(declaringType: "TypeName", name: "Method", params: [
                .init(typeFullName: "InParamType"),
                .init(typeFullName: "OutParamType", isByRef: true)
            ]))
    }

    func testParseConstructor() throws {
        XCTAssertEqual(
            try MemberKey(parsing: "M:TypeName.#ctor"),
            .method(declaringType: "TypeName", name: MemberKey.constructorName))
    }

    func testParseConversionOperator() throws {
        XCTAssertEqual(
            try MemberKey(parsing: "M:TypeName.op_Implicit()~ReturnType"),
            .method(
                declaringType: "TypeName",
                name: "op_Implicit",
                params: [],
                conversionTarget: .init(typeFullName: "ReturnType")))
    }

    func testParseIndexer() throws {
        XCTAssertEqual(
            try MemberKey(parsing: "M:TypeName.Property(System.Int32)"),
            .method(declaringType: "TypeName", name: "Property", params: [
                .init(typeFullName: "System.Int32")
            ]))
    }

    func testParseParamTypes() throws {
        XCTAssertEqual(
            try MemberKey.ParamType(parsing: "TypeName"),
            .bound(fullName: "TypeName"))
        XCTAssertEqual(
            try MemberKey.ParamType(parsing: "TypeName{TypeName2}"),
            .bound(fullName: "TypeName", genericArgs: [ .bound(fullName: "TypeName2") ]))
        XCTAssertEqual(
            try MemberKey.ParamType(parsing: "TypeName[]"),
            .array(of: .bound(fullName: "TypeName")))
        XCTAssertEqual(
            try MemberKey.ParamType(parsing: "TypeName*"),
            .pointer(to: .bound(fullName: "TypeName")))
        XCTAssertEqual(
            try MemberKey.ParamType(parsing: "`42"),
            .genericArg(index: 42, kind: .type))
        XCTAssertEqual(
            try MemberKey.ParamType(parsing: "``42"),
            .genericArg(index: 42, kind: .method))
    }
}