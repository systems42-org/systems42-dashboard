import Foundation

/// One step of the guided tour (FR-012). A step names a type and a projection, never a folder or
/// a section id (CON-006). The tour looks the section up in the wiki's metamodel.
public struct TourStep: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    /// Only a step with no section has a title. Others take the title of their section.
    public let title: String?
    public let text: String
    public let showsType: String?
    public let showsProjection: String?
    /// The step shows the page that `WikiSession.orientation` finds.
    public let showsVision: Bool

    public init(id: String, title: String? = nil, text: String, showsType: String? = nil,
                showsProjection: String? = nil, showsVision: Bool = false) {
        self.id = id
        self.title = title
        self.text = text
        self.showsType = showsType
        self.showsProjection = showsProjection
        self.showsVision = showsVision
    }
}

/// The steps in the order FR-012 fixes: vision, goals, stakeholders, scope and context,
/// requirements, architecture, decisions, open issues, how the wiki came about.
/// The dashboard has no guided path yet. Its plan (`docs/superpowers/plans/2026-11-12-close-requirement-gaps.md`,
/// WP5 task 2) lists these steps by section id. Only the goals text is FR-012's own example. The other
/// seven texts are new wording in its style and need human review.
/// Type and projection names are constants here, which is open debt against CON-006.
/// Step titles are the titles of the sections in the open wiki's metamodel, except for the method step.
public enum TourSteps {
    public static let all: [TourStep] = [
        TourStep(
            id: "tour-vision",
            text: "Vision: the one sentence that says what the system is for.",
            showsVision: true),
        TourStep(
            id: "tour-goal",
            text: "Goals: what the system should achieve, and how we measure it. Every requirement names the goal it serves.",
            showsType: "goal", showsProjection: "goal-tree"),
        TourStep(
            id: "tour-stakeholder",
            text: "Stakeholders: who uses the system or is affected by it, and what each of them needs.",
            showsType: "stakeholder"),
        TourStep(
            id: "tour-scope",
            text: "Scope and context: what is inside the system, what is outside, and which neighbours it talks to.",
            showsType: "context", showsProjection: "context-diagram"),
        TourStep(
            id: "tour-requirement",
            text: "Requirements: what the system must do, ranked by priority. Each one traces back to a goal.",
            showsType: "functional-requirement", showsProjection: "story-map"),
        TourStep(
            id: "tour-architecture",
            text: "Architecture: the building blocks that answer the requirements. Each block names the requirements it serves.",
            showsType: "building-block", showsProjection: "whitebox"),
        TourStep(
            id: "tour-decision",
            text: "Decisions: the choices that are expensive to reverse, with the alternatives that were weighed.",
            showsType: "decision-record"),
        TourStep(
            id: "tour-issue",
            text: "Open issues: questions, gaps and contradictions nobody has settled yet.",
            showsType: "issue"),
        TourStep(
            id: "tour-method",
            title: "How this wiki came about",
            text: "Three loops, capture, inspect and clarify, write and maintain these pages. Open The Method to read how."),
    ]
}
