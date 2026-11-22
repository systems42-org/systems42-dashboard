import SwiftUI

/// Shown when a folder is not a wiki: what it lacks, and a way to pick another.
struct PreflightFailureView: View {
    let failure: PreflightFailure
    let chooseAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This folder is not a Systems42 wiki").font(.title2)
            Text(failure.folder.path).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Text("It lacks:")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(failure.missing, id: \.self) { Text($0).font(.body.monospaced()) }
            }
            Button("Choose another folder", action: chooseAnother)
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 240, alignment: .topLeading)
    }
}
