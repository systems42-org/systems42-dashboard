/// The text of the Method window (FR-011).
/// Wording copied from `_system/apps/dashboard/templates/method.html`, the dashboard's /method page.
/// The dashboard adds a link to the open Clarify issue there. This text has none, because
/// it would need that issue's id here (CON-006).
public enum MethodText {
    public static let markdown = """
    # Three loops

    Three loops write and maintain the pages of this wiki: capture, inspect and clarify. The AI does the bookkeeping. Humans supply the sources and decide.

    ## Capture

    A human drops a raw source into the inbox, such as interview notes, a transcript or a ticket. The AI grills it against the wiki, turns it into typed, linked pages and records where each page came from.

    **In:** a raw source. **Out:** new or updated pages, and the questions the source leaves open.

    ## Inspect

    The wiki is checked against fixed rules, after each capture, at intervals or on request. Findings such as contradictions, broken links or untestable requirements become questions.

    **In:** the pages as they stand. **Out:** findings, as questions.

    ## Clarify

    Being defined by the Systems42 team.

    ## How they feed each other

    Capture and inspect feed clarify with the questions they raise. Clarify feeds the pages, and the next capture and inspection start from those pages.
    """
}
