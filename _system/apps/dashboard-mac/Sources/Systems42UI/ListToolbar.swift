import SwiftUI

/// Mode switch, sort and filter of the list column.
struct ListToolbar: ToolbarContent {
    let model: ListModel
    @State private var sorting = false

    var body: some ToolbarContent {
        ToolbarItemGroup {
            // The switch shows once a section offers a second mode.
            if model.modes.count > 1 {
                Picker("Mode", selection: Binding(get: { model.state.mode }, set: { model.state.mode = $0 })) {
                    ForEach(model.modes, id: \.self) { Text(FieldLabel.text($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Button("Sort", systemImage: "arrow.up.arrow.down") { sorting.toggle() }
                .help("Sort the list")
                .popover(isPresented: $sorting, arrowEdge: .bottom) { SortEditor(model: model) }
            FilterMenu(model: model)
        }
    }
}

private struct FilterMenu: View {
    let model: ListModel

    var body: some View {
        Menu {
            ForEach(model.filterFields, id: \.field) { entry in
                Menu(FieldLabel.text(entry.field)) {
                    ForEach(entry.values, id: \.self) { value in
                        Toggle(value, isOn: Binding(
                            get: { model.state.filters[entry.field]?.contains(value) == true },
                            set: { _ in model.toggleFilter(field: entry.field, value: value) }
                        ))
                    }
                }
            }
            Divider()
            Button("Clear filters") { model.clearFilters() }.disabled(!model.hasFilters)
        } label: {
            Label("Filter", systemImage: model.hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help("Filter the list")
    }
}

private struct SortEditor: View {
    let model: ListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.presets.isEmpty {
                ForEach(model.presets, id: \.self) { preset in
                    Button {
                        model.apply(preset: preset)
                    } label: {
                        HStack {
                            Image(systemName: "checkmark").opacity(model.state.sort == preset.keys ? 1 : 0)
                            Text(preset.label)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            }
            ForEach(Array(model.state.sort.enumerated()), id: \.offset) { index, key in
                HStack {
                    Picker("Column \(index + 1)", selection: Binding(
                        get: { key.field }, set: { model.replaceSortKey(at: index, with: $0) }
                    )) {
                        ForEach(model.columns.filter { $0 == key.field || model.unusedColumns.contains($0) }, id: \.self) {
                            Text(FieldLabel.text($0)).tag($0)
                        }
                    }
                    .labelsHidden()
                    Button(key.ascending ? "Ascending" : "Descending", systemImage: key.ascending ? "arrow.up" : "arrow.down") {
                        model.toggleDirection(at: index)
                    }
                    .labelStyle(.iconOnly)
                    .help(key.ascending ? "Ascending, click for descending" : "Descending, click for ascending")
                    Button("Remove", systemImage: "minus.circle") { model.removeSortKey(at: index) }
                        .labelStyle(.iconOnly)
                }
            }
            Menu("Add column") {
                ForEach(model.unusedColumns, id: \.self) { column in
                    Button(FieldLabel.text(column)) { model.addSortKey(column) }
                }
            }
            .fixedSize()
        }
        .padding(12)
    }
}
