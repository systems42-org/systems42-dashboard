import Foundation

/// One class of the data model: a domain term with a stereotype. Go: the maps of `DataModelNodes`.
struct DataModelNode {
    let page: Page
    let stereotype: String
    let context: String
    let attributes: [String]
}

/// One edge of the data model. Go: the maps of `DataModelEdges`.
struct DataModelEdge {
    let source, target, verb, cardinality, kind: String
}

/// The entity diagram, a Mermaid class diagram over the stereotyped domain terms (DR-027).
/// Port of `DataModelNodes`, `DataModelEdges` and `BuildDataModelFullDiagram` in `internal/project/entity.go`.
///
/// Open debt (CON-006): `proj-entity-diagram` declares the type and the fields it reads. The stereotype
/// values, the relationship kinds, the keys of a relationship and the arrow syntax are fixed here.
struct DataModelProjection {
    let model: ProjectionModel

    // Content type. Go: web/projections.go `handleEntityDiagram`, the pages of the domain term folder.
    static let termType = "domain-term"
    static let parentRelation = "parent"
    /// The projection page this reads.
    static let projection = "entity-diagram"
    static let declaration = ProjectionDeclaration(projection, [
        (termType, [stereotypeField, parentRelation, attributesField, relationshipsField, contextField]),
    ])

    // Fields and keys. Go: entity.go and wiki/page.go `DataModelPages`.
    static let stereotypeField = "stereotype", contextField = "bounded-context", attributesField = "attributes"
    static let relationshipsField = "relationships"
    static let nameKey = "name", toKey = "to", kindKey = "kind", multiplicityKey = "multiplicity", labelKey = "label"

    // Values. Go: wiki/page.go `domainModelStereotypes`, entity.go `dmArrows`.
    static let modelStereotypes: Set<String> = ["entity", "value-object", "sum-type"]
    static let plainStereotype = "entity"
    static let association = "association", inheritance = "inheritance", generalization = "generalization"
    /// Kind to arrow syntax and whether the arrow carries a cardinality.
    static let arrows: [String: (syntax: String, carded: Bool)] = [
        "association": ("-->", true), "aggregation": ("o--", true), "composition": ("*--", true), "inheritance": ("<|--", false),
    ]

    private static let transliteration: [Unicode.Scalar: String] = [
        "ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss", "Ä": "Ae", "Ö": "Oe", "Ü": "Ue", "ẞ": "Ss",
    ]

    /// Ports `wiki.DataModelPages` and `DataModelNodes`: the structured terms by id.
    func nodes() -> [DataModelNode] {
        let terms = model.pages(ofType: Self.termType).filter { Self.modelStereotypes.contains($0.lowered(Self.stereotypeField)) }
        return ProjectionModel.sortedByID(terms).map { page in
            DataModelNode(
                page: page, stereotype: page.lowered(Self.stereotypeField), context: page.trimmed(Self.contextField),
                attributes: attributeNames(page)
            )
        }
    }

    /// Ports `ExtractDMAttributeNames`.
    private func attributeNames(_ page: Page) -> [String] {
        page.entries(Self.attributesField).compactMap { item in
            guard case .entry(let entry) = item, let name = entry[Self.nameKey],
                  !Common.trim(name).isEmpty else { return nil }
            return name
        }
    }

    /// Ports `DataModelEdges`: sum-type parents as inheritance, then the `relationships`.
    func edges(of nodes: [DataModelNode]) -> [DataModelEdge] {
        let known = Set(nodes.map(\.page.stem))
        var out: [DataModelEdge] = []
        let parentField = model.field(ofRelation: Self.parentRelation)
        for node in nodes {
            let page = node.page
            for target in page.names(parentField) where known.contains(target) && target != page.stem {
                out.append(DataModelEdge(source: page.stem, target: target, verb: "", cardinality: "", kind: Self.inheritance))
            }
            for case .entry(let entry) in page.entries(Self.relationshipsField) {
                let to = entry[Self.toKey] ?? ""
                let target = to.isEmpty ? "" : Frontmatter.pageName(in: to)
                guard !target.isEmpty, known.contains(target) else { continue }
                var kind = Common.trim(entry[Self.kindKey] ?? "").lowercased()
                if kind.isEmpty { kind = Self.association }
                if kind == Self.generalization { kind = Self.inheritance }
                if Self.arrows[kind] == nil { kind = Self.association }
                if target == page.stem && kind == Self.inheritance { continue }  // a term may refer to itself, not inherit from itself
                out.append(DataModelEdge(
                    source: page.stem, target: target, verb: Common.cleanLabel(entry[Self.labelKey] ?? "", dropParenthetical: true),
                    cardinality: Common.trim(entry[Self.multiplicityKey] ?? ""), kind: kind
                ))
            }
        }
        return out
    }

    /// Ports `dmASCII`: umlauts spelled out, other accents dropped.
    private func ascii(_ label: String) -> String {
        var spelled = ""
        for scalar in label.unicodeScalars {
            if let replacement = Self.transliteration[scalar] { spelled += replacement } else { spelled.unicodeScalars.append(scalar) }
        }
        let decomposed = spelled.decomposedStringWithCompatibilityMapping
        return String(String.UnicodeScalarView(decomposed.unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark }))
    }

    /// Ports `dmClassName`: a safe, unique class name from a label.
    private func className(_ label: String, taken: inout Set<String>) -> String {
        let text = ascii(Common.cleanLabel(label, dropParenthetical: true))
        var base = ""
        var word = ""
        func flush() {
            if let first = word.first { base += first.uppercased() + word.dropFirst() }
            word = ""
        }
        for scalar in text.unicodeScalars {
            let isWordCharacter = (scalar.value >= 0x30 && scalar.value <= 0x39) || (scalar.value >= 0x41 && scalar.value <= 0x5A)
                || (scalar.value >= 0x61 && scalar.value <= 0x7A)
            if isWordCharacter { word.unicodeScalars.append(scalar) } else { flush() }
        }
        flush()
        if base.isEmpty { base = "Entity" }
        if let first = base.unicodeScalars.first, first.value >= 0x30, first.value <= 0x39 { base = "E" + base }
        var name = base
        var n = 2
        while taken.contains(name) {
            name = "\(base)\(n)"
            n += 1
        }
        taken.insert(name)
        return name
    }

    /// Ports `encodeMermaidMember`: letters, digits, underscore, space and dash stay, the rest becomes `#<code>;`.
    private func member(_ name: String) -> String {
        var out = ""
        for scalar in Common.cutText(Common.fields(name).joined(separator: " ")).unicodeScalars {
            let category = scalar.properties.generalCategory
            let isLetter = [.uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter].contains(category)
            if isLetter || category == .decimalNumber || scalar == "_" || scalar == " " || scalar == "-" {
                out.unicodeScalars.append(scalar)
            } else {
                out += "#\(scalar.value);"
            }
        }
        return out
    }

    /// Ports `BuildDataModelFullDiagram`, for all terms. Nil when there is no class.
    func diagram() -> String? {
        let nodes = nodes()
        let edges = edges(of: nodes)
        if nodes.isEmpty { return nil }

        var taken = Set<String>()
        var nameOf: [String: String] = [:]
        for node in nodes { nameOf[node.page.stem] = className(node.page.title, taken: &taken) }

        func declaration(_ node: DataModelNode) -> String {
            let ident = nameOf[node.page.stem] ?? ""
            let label = Common.cleanLabel(node.page.title, dropParenthetical: true).replacingOccurrences(of: "\"", with: "'")
            return label != ident ? "\(ident)[\"\(label)\"]" : ident
        }

        var lines = ["classDiagram"]
        for node in nodes {
            var body: [String] = []
            if !node.stereotype.isEmpty && node.stereotype != Self.plainStereotype { body.append("    <<\(node.stereotype)>>") }
            for attribute in node.attributes { body.append("    +" + member(attribute)) }
            if body.isEmpty {
                lines.append("  class \(declaration(node))")
            } else {
                lines.append("  class \(declaration(node)) {")
                lines += body.map { "  " + $0 }
                lines.append("  }")
            }
        }

        for edge in edges {
            guard let arrow = Self.arrows[edge.kind] else { continue }
            var source = nameOf[edge.source] ?? "", target = nameOf[edge.target] ?? ""
            if edge.kind == Self.inheritance { swap(&source, &target) }
            let cardinality = Common.cleanLabel(edge.cardinality, dropParenthetical: false).replacingOccurrences(of: "\\", with: "")
            var line = arrow.carded && !cardinality.isEmpty
                ? "  \(source) \(arrow.syntax) \"\(cardinality)\" \(target)"
                : "  \(source) \(arrow.syntax) \(target)"
            if !edge.verb.isEmpty { line += " : " + edge.verb }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
