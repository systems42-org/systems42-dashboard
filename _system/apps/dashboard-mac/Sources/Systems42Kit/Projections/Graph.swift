import Foundation

/// One value in the data of a graph node or edge: what the dashboard puts into its Cytoscape blocks.
public enum GraphValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case list([GraphValue])
    case map([String: GraphValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([GraphValue].self) {
            self = .list(value)
        } else {
            self = .map(try container.decode([String: GraphValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .list(let value): try container.encode(value)
        case .map(let value): try container.encode(value)
        }
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

/// The Cytoscape data of the dashboard: `{"nodes": [{"data": {...}}], "edges": [{"data": {...}}]}`,
/// and the extra keys a graph carries (`layer_counts` of the term network, `universal` of the metamodel graph).
public struct Graph: Codable, Equatable, Sendable {
    public struct Node: Codable, Equatable, Sendable {
        public let data: [String: GraphValue]
        public var id: String { data["id"]?.string ?? "" }
    }

    public struct Edge: Codable, Equatable, Sendable {
        public let data: [String: GraphValue]
        public var id: String { data["id"]?.string ?? "" }
        public var source: String { data["source"]?.string ?? "" }
        public var target: String { data["target"]?.string ?? "" }
    }

    public let nodes: [Node]
    public let edges: [Edge]
    public let extra: [String: GraphValue]

    public init(nodes: [Node] = [], edges: [Edge] = [], extra: [String: GraphValue] = [:]) {
        self.nodes = nodes
        self.edges = edges
        self.extra = extra
    }

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(_ name: String) { stringValue = name }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        nodes = try container.decodeIfPresent([Node].self, forKey: Key("nodes")) ?? []
        edges = try container.decodeIfPresent([Edge].self, forKey: Key("edges")) ?? []
        var rest: [String: GraphValue] = [:]
        for key in container.allKeys where key.stringValue != "nodes" && key.stringValue != "edges" {
            rest[key.stringValue] = try container.decode(GraphValue.self, forKey: key)
        }
        extra = rest
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(nodes, forKey: Key("nodes"))
        try container.encode(edges, forKey: Key("edges"))
        for (name, value) in extra { try container.encode(value, forKey: Key(name)) }
    }
}
