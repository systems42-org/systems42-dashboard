import Foundation
import Observation
import Systems42Kit

/// The term network of the open wiki (FR-040, FR-051): it opens with terms only, and one layer per
/// page type adds the pages of that type that terms link to. The session owns the model and the model
/// holds the session weakly. A result for an older key is dropped.
@MainActor @Observable public final class TermNetworkModel {
    /// One toggle: the pages of a type that terms link to.
    public struct Layer: Identifiable, Equatable, Sendable {
        /// The name of the type, as `Projections.termNetwork(layers:)` takes it.
        public let id: String
        public let prefix: String
        public let label: String
        /// The edges the layer adds.
        public let count: Int
    }

    struct Key: Hashable, Sendable {
        let revision: Int
        let agreedOnly: Bool
        let layers: Set<String>
    }

    private weak var session: WikiSession?
    public private(set) var graph = Graph()
    public private(set) var layers: [Layer] = []
    public private(set) var enabled: Set<String> = []
    /// The key the graph and the layers were computed for.
    private(set) var loadedKey: Key?
    @ObservationIgnored private var layersKey: Key?

    public init(session: WikiSession) {
        self.session = session
    }

    /// The key the data should have now. Nil when the session is gone.
    var currentKey: Key? {
        session.map { Key(revision: $0.revision, agreedOnly: $0.agreedOnly, layers: enabled) }
    }

    var isCurrent: Bool { loadedKey != nil && loadedKey == currentKey }

    /// Switches a layer on or off. A type that is not a layer does nothing.
    public func toggle(_ layer: String) {
        if enabled.contains(layer) { enabled.remove(layer) } else if layers.contains(where: { $0.id == layer }) { enabled.insert(layer) }
    }

    public func isOn(_ layer: String) -> Bool { enabled.contains(layer) }

    /// Computes the graph for the current key, unless it is on hand.
    public func load() async {
        guard let session else { return }
        await session.projections.load()
        guard let key = currentKey, !isCurrent, let projections = session.projections.data?.projections,
              session.projections.isCurrent else { return }
        let metamodel = session.metamodel
        let wantLayers = layersKey != Key(revision: key.revision, agreedOnly: key.agreedOnly, layers: [])
        let result = await Task.detached(priority: .userInitiated) {
            (graph: projections.termNetwork(layers: key.layers),
             layers: wantLayers ? Self.layers(of: projections, metamodel: metamodel) : nil)
        }.value
        guard currentKey == key, !Task.isCancelled else { return }
        graph = result.graph
        if let found = result.layers {
            layers = found
            layersKey = Key(revision: key.revision, agreedOnly: key.agreedOnly, layers: [])
            // A layer the wiki no longer has cannot stay on.
            let names = Set(found.map(\.id))
            if !enabled.isSubset(of: names) {
                enabled.formIntersection(names)
                await load()
                return
            }
        }
        loadedKey = key
    }

    /// One layer per type of page that terms link to, in the order of the metamodel, with the edges it adds.
    nonisolated static func layers(of projections: Projections, metamodel: Metamodel) -> [Layer] {
        guard let full = projections.graph("term-network") else { return [] }
        var counts: [String: Int] = [:]
        if case .map(let found)? = full.extra["layer_counts"] {
            for (prefix, value) in found { if case .int(let n) = value { counts[prefix] = n } }
        }
        var layers: [Layer] = []
        var seen = Set<String>()
        for type in metamodel.types {
            guard let count = counts[type.prefix], seen.insert(type.prefix).inserted else { continue }
            layers.append(Layer(id: type.name, prefix: type.prefix, label: type.label.isEmpty ? type.name : type.label, count: count))
        }
        return layers
    }
}

extension WikiSession {
    /// The term network of this wiki. One per session, so the view and the tests share its layers.
    public var termNetwork: TermNetworkModel {
        if let model = termNetworkModelStore { return model }
        let model = TermNetworkModel(session: self)
        termNetworkModelStore = model
        return model
    }
}
