import SwiftUI
import Systems42Kit

/// A method standard: name, definition, the types it applies to and the outside reference (FR-035).
struct AnchorEntryView: View {
    let model: MetamodelModel
    let store: WikiStore
    let entry: MetamodelModel.Entry

    var body: some View {
        EntryFrame(entry: entry) {
            FactsView(facts: entry.facts)
            LinkGroupsView(model: model, groups: entry.groups)
            if let reference = entry.reference {
                Button(reference.absoluteString) { OutgoingLinks.open(reference) }.buttonStyle(.link)
            }
            EntryBody(model: model, store: store, entry: entry)
        }
    }
}
