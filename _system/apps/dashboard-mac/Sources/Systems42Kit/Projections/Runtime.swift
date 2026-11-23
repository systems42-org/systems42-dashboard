import Foundation

/// Runtime scenarios (arc42 section 6): one sequence diagram per scenario.
/// Port of `StepsOf`, `resolveEndpoint` and `BuildSequenceDiagram` in `internal/project/arch.go`.
struct RuntimeProjection {
    let model: ProjectionModel

    /// The projection page this reads. Go: arch.go `BuildSequenceDiagram`.
    static let projection = "sequence-diagram"
    static let declaration = ProjectionDeclaration(projection, [
        (Arch.scenarioType, [Arch.stepsRelation]),
        (Arch.blockType, []),
        (Arch.stakeholderType, []),
        (Arch.interfaceType, []),
    ])

    /// One drawn step of a scenario.
    struct Step {
        let fromStem, fromLabel, toStem, toLabel, message, note: String
    }

    /// Ports `endpointStem`.
    private func endpointStem(_ text: String) -> String {
        if text.contains("[[") { return Frontmatter.pageName(in: text) }
        if model.byStem[text] != nil { return text }
        if let slash = text.lastIndex(of: "/") {
            let last = Common.trim(String(text[text.index(after: slash)...]))
            if model.byStem[last] != nil { return last }
        }
        return text
    }

    /// Ports `resolveEndpoint`: the stem of the page an endpoint names, and its label.
    private func endpoint(_ raw: String?) -> (stem: String, label: String) {
        let text = Common.trim(raw ?? "")
        let stem = text.isEmpty ? "" : endpointStem(text)
        guard let page = model.byStem[stem] else { return ("", stem.isEmpty ? "?" : stem) }
        let plain = [model.folder(ofType: Arch.stakeholderType), model.folder(ofType: Arch.interfaceType)]
        if plain.contains(page.ref.folder) { return (stem, Common.cleanLabel(page.title, dropParenthetical: true)) }
        return (stem, "\(Common.label(page.id)) · \(Common.cleanLabel(page.title, dropParenthetical: true))")
    }

    /// Ports `StepsOf`: the steps that are mappings, in order.
    func steps(of page: Page) -> [Step] {
        var out: [Step] = []
        for case .entry(let entry) in page.entries(model.field(ofRelation: Arch.stepsRelation)) {
            let from = endpoint(entry[Arch.fromKey]), to = endpoint(entry[Arch.toKey])
            out.append(Step(
                fromStem: from.stem, fromLabel: from.label, toStem: to.stem, toLabel: to.label,
                message: entry[Arch.messageKey] ?? "", note: entry[Arch.noteKey] ?? ""
            ))
        }
        return out
    }

    /// Ports `BuildSequenceDiagram`. Nil when the page has no steps.
    func sequenceDiagram(of page: Page) -> String? {
        let steps = steps(of: page)
        if steps.isEmpty { return nil }

        struct Participant { let nid, label, keyword: String }
        var order: [Participant] = []
        var nidOf: [String: String] = [:]
        func key(_ stem: String, _ label: String) -> String { stem.isEmpty ? "text:" + label : "page:" + stem }
        let actorFolder = model.folder(ofType: Arch.stakeholderType)
        for step in steps {
            for (stem, label) in [(step.fromStem, step.fromLabel), (step.toStem, step.toLabel)] {
                let participantKey = key(stem, label)
                if nidOf[participantKey] != nil { continue }
                let nid = "L\(nidOf.count + 1)"
                nidOf[participantKey] = nid
                let isActor = actorFolder != nil && !stem.isEmpty && model.byStem[stem]?.ref.folder == actorFolder
                order.append(Participant(nid: nid, label: Common.mmEscape(label), keyword: isActor ? "actor" : "participant"))
            }
        }

        var lines = ["sequenceDiagram"]
        for participant in order { lines.append("  \(participant.keyword) \(participant.nid) as \(participant.label)") }
        for step in steps {
            let from = nidOf[key(step.fromStem, step.fromLabel)] ?? "", to = nidOf[key(step.toStem, step.toLabel)] ?? ""
            var message = Common.mmEscape(step.message)
            if message.isEmpty { message = " " }
            lines.append("  \(from)->>\(to): \(message)")
            if !step.note.isEmpty { lines.append("  Note over \(to): \(Common.mmEscape(step.note))") }
        }
        return lines.joined(separator: "\n")
    }
}
