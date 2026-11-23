import SwiftUI
import Systems42Kit

/// The open issues that name this page, and the provenance records it links to.
/// Who must answer an issue (FR-028) is left out: the metamodel does not mark that field apart from its name.
struct IssuesPanel: View {
    let issues: [Page]
    @Environment(\.pageLinks) private var links

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Open issues").font(.headline)
                ForEach(issues, id: \.ref) { issue in
                    HStack(spacing: 8) {
                        Button { links.open(.page(issue.ref)) } label: {
                            Text(verbatim: "\(issue.id)  \(issue.title)").lineLimit(2)
                        }
                        .buttonStyle(.link)
                        Text(verbatim: issue.status)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }
}

struct SourcesPanel: View {
    let sources: [String]

    var body: some View {
        if !sources.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sources").font(.headline)
                ForEach(sources, id: \.self) { name in
                    Text(verbatim: name).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
    }
}
