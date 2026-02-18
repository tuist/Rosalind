import SwiftProtobuf

/// Manual SwiftProtobuf.Message conformances for AAPT2's compiled XML format.
/// Proto schema: https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/tools/aapt2/Resources.proto

struct AaptXmlNode: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding, Sendable {
    static let protoMessageName = "aapt.pb.XmlNode"
    static let _protobuf_nameMap: SwiftProtobuf._NameMap = [1: .same(proto: "element")]
    var unknownFields = SwiftProtobuf.UnknownStorage()
    var element: AaptXmlElement?

    init() {}

    mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let field = try decoder.nextFieldNumber() {
            if field == 1 { try decoder.decodeSingularMessageField(value: &element) }
        }
    }

    func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        try visitor.visitSingularMessageField(value: element ?? AaptXmlElement(), fieldNumber: 1)
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.element == rhs.element && lhs.unknownFields == rhs.unknownFields
    }
}

struct AaptXmlElement: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding, Sendable {
    static let protoMessageName = "aapt.pb.XmlElement"
    static let _protobuf_nameMap: SwiftProtobuf._NameMap = [2: .same(proto: "name"), 3: .same(proto: "attribute")]
    var unknownFields = SwiftProtobuf.UnknownStorage()
    var name = ""
    var attributes: [AaptXmlAttribute] = []

    init() {}

    mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let field = try decoder.nextFieldNumber() {
            switch field {
            case 2: try decoder.decodeSingularStringField(value: &name)
            case 3: try decoder.decodeRepeatedMessageField(value: &attributes)
            default: break
            }
        }
    }

    func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if !name.isEmpty { try visitor.visitSingularStringField(value: name, fieldNumber: 2) }
        if !attributes.isEmpty { try visitor.visitRepeatedMessageField(value: attributes, fieldNumber: 3) }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.attributes == rhs.attributes && lhs.unknownFields == rhs.unknownFields
    }
}

struct AaptXmlAttribute: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding, Sendable {
    static let protoMessageName = "aapt.pb.XmlAttribute"
    static let _protobuf_nameMap: SwiftProtobuf._NameMap = [2: .same(proto: "name"), 3: .same(proto: "value")]
    var unknownFields = SwiftProtobuf.UnknownStorage()
    var name = ""
    var value = ""

    init() {}

    mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
        while let field = try decoder.nextFieldNumber() {
            switch field {
            case 2: try decoder.decodeSingularStringField(value: &name)
            case 3: try decoder.decodeSingularStringField(value: &value)
            default: break
            }
        }
    }

    func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
        if !name.isEmpty { try visitor.visitSingularStringField(value: name, fieldNumber: 2) }
        if !value.isEmpty { try visitor.visitSingularStringField(value: value, fieldNumber: 3) }
        try unknownFields.traverse(visitor: &visitor)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.value == rhs.value && lhs.unknownFields == rhs.unknownFields
    }
}
