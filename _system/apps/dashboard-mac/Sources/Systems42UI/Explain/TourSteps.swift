import Foundation

/// One step of the guided tour (FR-012). A step names a type and a projection, never a folder or
/// a section id (CON-006). The tour looks the section up in the wiki's metamodel.
public struct TourStep: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title, text: String
    public let showsType: String?
    public let showsProjection: String?

    public init(id: String, title: String, text: String, showsType: String? = nil, showsProjection: String? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.showsType = showsType
        self.showsProjection = showsProjection
    }
}

/// The steps in the order FR-012 fixes: vision and goals, stakeholders, scope and context,
/// requirements, architecture, decisions, open issues, how the wiki came about.
/// The dashboard has no guided path yet. Its plan (`docs/superpowers/plans/2026-11-12-close-requirement-gaps.md`,
/// WP5 task 2) lists these steps by section id. Only the first text is FR-012's own example. The others
/// are written in its style and need review.
/// Type and projection names are constants here, which is open debt against CON-006.
public enum TourSteps {
    public static let all: [TourStep] = [
        TourStep(
            id: "tour-vision",
            title: "Vision and goals",
            text: "Goals: what the system should achieve, and how we measure it. Every requirement names the goal it serves.",
            showsType: "goal", showsProjection: "goal-tree"),
        TourStep(
            id: "tour-stakeholders",
            title: "Who is involved",
            text: "Stakeholders: who uses the system or is affected by it, and what each of them needs.",
            showsType: "stakeholder"),
        TourStep(
            id: "tour-context",
            title: "Scope and context",
            text: "Scope and context: what is inside the system, what is outside, and which neighbours it talks to.",
            showsType: "context", showsProjection: "context-diagram"),
        TourStep(
            id: "tour-requirements",
            title: "Requirements",
            text: "Requirements: what the system must do, ranked by priority. Each one traces back to a goal.",
            showsType: "functional-requirement", showsProjection: "story-map"),
        TourStep(
            id: "tour-architecture",
            title: "Architecture",
            text: "Architecture: the building blocks that answer the requirements. Each block names the requirements it serves.",
            showsType: "building-block", showsProjection: "whitebox"),
        TourStep(
            id: "tour-decisions",
            title: "Hard choices",
            text: "Decisions: the choices that are expensive to reverse, with the alternatives that were weighed.",
            showsType: "decision-record"),
        TourStep(
            id: "tour-issues",
            title: "Open issues",
            text: "Open issues: questions, gaps and contradictions nobody has settled yet.",
            showsType: "issue"),
        TourStep(
            id: "tour-method",
            title: "How this wiki came about",
            text: "Three loops, capture, inspect and clarify, write and maintain these pages. Open The Method to read how."),
    ]
}
