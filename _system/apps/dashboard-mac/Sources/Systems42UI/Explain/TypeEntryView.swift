import SwiftUI
import Systems42Kit

/// A content type: its facts, fields, relations, anchors, projections and one live example (FR-010).
struct TypeEntryView: View {
    let model: MetamodelModel
    let store: WikiStore
    let entry: MetamodelModel.Entry

    var body: some View {
        EntryFrame(entry: entry) {
            FactsView(facts: entry.facts)
            if !entry.fields.isEmpty {
                Text("Fields").font(.headline)
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Name").font(.caption).foregroundStyle(.secondary)
                        Text("Kind").font(.caption).foregroundStyle(.secondary)
                        Text("Values").font(.caption).foregroundStyle(.secondary)
                        Text("Meaning").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(entry.fields.enumerated()), id: \.offset) { _, field in
                        GridRow {
                            Text(verbatim: field.name + (field.required ? " *" : "")).font(.system(.callout, design: .monospaced))
                            Text(verbatim: field.kind)
                            Text(verbatim: field.values.joined(separator: ", "))
                            Text(verbatim: field.doc ?? "").foregroundStyle(.secondary)
                        }
                    }
                }
                Text("* required").font(.caption).foregroundStyle(.secondary)
            }
            LinkGroupsView(model: model, groups: entry.groups)
            Text("Example").font(.headline)
            Text(verbatim: entry.exampleText)
            EntryBody(model: model, store: store, entry: entry)
        }
    }
}

/// A relation, projection, rule, notation or framework.
struct ConstructEntryView: View {
    let model: MetamodelModel
    let store: WikiStore
    let entry: MetamodelModel.Entry

    var body: some View {
        EntryFrame(entry: entry) {
            FactsView(facts: entry.facts)
            LinkGroupsView(model: model, groups: entry.groups)
            EntryBody(model: model, store: store, entry: entry)
        }
    }
}
