import Foundation
import Testing
import Systems42Kit
import Systems42TestSupport
@testable import Systems42UI

@MainActor
private func session(_ fixture: String) async throws -> WikiSession {
    await WikiSession.open(try Preflight.open(Fixture.url(fixture)))
}

@MainActor
private func folder(of type: String, in s: WikiSession) -> String? {
    s.metamodel.type(named: type)?.folder.split(separator: "/").last.map(String.init)
}

@MainActor @Suite struct TourModelTests {
    private func pages(of step: TourStep, in s: WikiSession) -> [Page] {
        guard let type = step.showsType, let f = folder(of: type, in: s) else { return [] }
        return s.store.pages(in: f)
    }

    @Test func tourFollowsTheWiki() async throws {
        let basic = try await session("basic")
        let basicTour = TourModel(session: basic)
        #expect(!basicTour.steps.isEmpty)
        for step in basicTour.steps where step.showsType != nil {
            #expect(!pages(of: step, in: basic).isEmpty, "\(step.id)")
        }
        let views = try await session("arc42-views")
        let viewsTour = TourModel(session: views)
        for step in viewsTour.steps where step.showsType != nil {
            #expect(!pages(of: step, in: views).isEmpty, "\(step.id)")
        }
        #expect(viewsTour.steps.map(\.id) != basicTour.steps.map(\.id))
        #expect(viewsTour.steps.map(\.id).contains("tour-architecture"))
        #expect(!basicTour.steps.map(\.id).contains("tour-architecture"))
    }

    @Test func stepsWithoutPagesAreLeftOut() async throws {
        let s = try await session("domain-model")
        let tour = TourModel(session: s)
        for step in tour.steps where step.showsType != nil {
            #expect(!pages(of: step, in: s).isEmpty, "\(step.id)")
        }
        #expect(!tour.steps.map(\.id).contains("tour-vision"))
    }

    @Test func everyFixtureHasAStepAndNoEmptyOne() async throws {
        for name in Fixture.names {
            let s = try await session(name)
            let tour = TourModel(session: s)
            #expect(!tour.steps.isEmpty, "\(name)")
            for step in tour.steps {
                #expect(step.showsType == nil ? (step.id == "tour-method" || step.showsVision) : !pages(of: step, in: s).isEmpty, "\(name) \(step.id)")
                #expect(!step.text.isEmpty)
            }
        }
    }

    @Test func aTypeTheMetamodelLacksLeavesItsStepOut() async throws {
        let copy = try Fixture.tempCopy("arc42-views")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(copy))
        #expect(TourModel(session: s).steps.map(\.id).contains("tour-architecture"))
        try FileManager.default.removeItem(at: copy.appending(path: "_system/metamodel/types/type-building-block.md"))
        let after = await WikiSession.open(try Preflight.open(copy))
        #expect(!TourModel(session: after).steps.map(\.id).contains("tour-architecture"))
    }

    @Test func nextSelectsALivePage() async throws {
        let s = try await session("basic")
        let tour = TourModel(session: s)
        tour.start()
        for index in tour.steps.indices.dropLast() {
            #expect(tour.current == index)
            let step = tour.steps[index]
            if step.showsType != nil {
                let ref = try #require(s.selectedPage)
                #expect(pages(of: step, in: s).contains { $0.ref == ref })
                let section = try #require(s.metamodel.sections.first { $0.types.contains(step.showsType ?? "") })
                #expect(s.selectedSection == section.id)
            }
            tour.next()
        }
    }

    @Test func theFirstStepShowsTheVisionPage() async throws {
        let s = try await session("basic")
        let tour = TourModel(session: s)
        tour.start()
        let ref = try #require(s.selectedPage)
        #expect(tour.steps[0].id == "tour-vision")
        #expect(ref == s.orientation?.ref)
        #expect(tour.currentStop?.title == s.orientation?.title)
        tour.next()
        #expect(tour.steps[1].id == "tour-goal")
        #expect(s.selectedPage != ref)
        #expect(s.selectedPage?.folder == ref.folder)
    }

    @Test func noVisionMeansNoVisionStep() async throws {
        let s = try await session("arc42-views")
        #expect(s.orientation == nil)
        #expect(!TourModel(session: s).steps.map(\.id).contains("tour-vision"))
    }

    @Test func titlesAreTheSidebarTitlesOfTheSections() async throws {
        let s = try await session("basic")
        let tour = TourModel(session: s)
        let titles = Dictionary(s.sidebar.flatMap(\.rows).map { ($0.section.id, $0.section.title) }, uniquingKeysWith: { a, _ in a })
        var checked = 0
        for stop in tour.stops where stop.step.showsType != nil {
            #expect(stop.title == titles[stop.section ?? ""], "\(stop.id)")
            checked += 1
        }
        #expect(checked > 3)
        #expect(tour.stops.last?.title == "How this wiki came about")
        #expect(TourSteps.all.filter { $0.title != nil }.map(\.id) == ["tour-method"])
    }

    @Test func theIssuesStepShowsAnOpenIssueFirst() async throws {
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let issues = copy.appending(path: "wiki/issues")
        try FileManager.default.createDirectory(at: issues, withIntermediateDirectories: true)
        func issue(_ n: Int, _ status: String) -> String {
            "---\nid: ISS-00\(n)\ntype: issue\ntitle: Issue \(n)\nstatus: \(status)\n---\n\nBody.\n"
        }
        try issue(1, "resolved").write(to: issues.appending(path: "ISS-001-a.md"), atomically: true, encoding: .utf8)
        try issue(2, "open").write(to: issues.appending(path: "ISS-002-b.md"), atomically: true, encoding: .utf8)
        let s = await WikiSession.open(try Preflight.open(copy))
        let stop = try #require(TourModel(session: s).stops.first { $0.id == "tour-issue" })
        #expect(stop.page?.stem == "ISS-002-b")
        try FileManager.default.removeItem(at: issues.appending(path: "ISS-002-b.md"))
        let after = await WikiSession.open(try Preflight.open(copy))
        #expect(try #require(TourModel(session: after).stops.first { $0.id == "tour-issue" }).page?.stem == "ISS-001-a")
    }

    @Test func theTourDoesNotAddHistory() async throws {
        let s = try await session("basic")
        let a = try #require(s.store.pages(in: "functional-requirements").first?.ref)
        let b = try #require(s.store.pages(in: "functional-requirements").dropFirst().first?.ref)
        s.select(page: a)
        s.select(page: b)
        let count = s.historyCount
        let tour = TourModel(session: s)
        tour.start()
        tour.next(); tour.next(); tour.next()
        tour.previous()
        tour.returnToStep()
        tour.stop()
        #expect(s.historyCount == count)
        #expect(s.selectedPage == b)
        s.back()
        #expect(s.selectedPage == a)
    }

    @Test func aReadersClickDuringTheTourAddsOneEntry() async throws {
        let s = try await session("basic")
        let a = try #require(s.store.pages(in: "functional-requirements").first?.ref)
        s.select(page: a)
        let count = s.historyCount
        let tour = TourModel(session: s)
        tour.start()
        tour.next()
        let other = try #require(s.store.pages(in: "decisions").first?.ref)
        s.select(page: other)
        #expect(s.historyCount == count + 1)
        tour.next()
        #expect(s.historyCount == count + 1)
        s.back()
        #expect(s.selectedPage == a)
    }

    @Test func clickingThePreTourPageDuringTheTourStillShowsIt() async throws {
        let s = try await session("basic")
        let a = try #require(s.store.pages(in: "functional-requirements").first?.ref)
        s.select(page: a)
        let tour = TourModel(session: s)
        tour.start()
        s.select(page: a)
        #expect(s.selectedPage == a)
    }

    @Test func twoSessionsKeepTheirOwnTours() async throws {
        let one = try await session("basic")
        let two = try await session("arc42-views")
        let a = one.tour, b = two.tour
        a.start(); b.start()
        a.next(); a.next()
        b.next()
        #expect(a.current == 2)
        #expect(b.current == 1)
        let pageB = two.selectedPage
        a.next()
        #expect(two.selectedPage == pageB)
        b.stop()
        #expect(a.isActive)
        #expect(!b.isActive)
    }

    @Test func previousAtTheStartStays() async throws {
        let s = try await session("basic")
        let tour = TourModel(session: s)
        tour.start()
        let page = s.selectedPage
        tour.previous()
        #expect(tour.current == 0)
        #expect(tour.isActive)
        #expect(s.selectedPage == page)
    }

    @Test func previousGoesBack() async throws {
        let s = try await session("basic")
        let tour = TourModel(session: s)
        tour.start()
        let first = s.selectedPage
        tour.next()
        tour.previous()
        #expect(tour.current == 0)
        #expect(s.selectedPage == first)
    }

    @Test func nextAtTheEndStops() async throws {
        let s = try await session("basic")
        let tour = TourModel(session: s)
        tour.start()
        for _ in tour.steps.indices { tour.next() }
        #expect(!tour.isActive)
    }

    @Test func stopRestoresTheSelection() async throws {
        let s = try await session("basic")
        let ref = try #require(s.store.pages(in: "functional-requirements").first?.ref)
        s.select(page: ref)
        let section = s.selectedSection
        let tour = TourModel(session: s)
        tour.start()
        tour.next()
        #expect(s.selectedPage != ref)
        tour.stop()
        #expect(!tour.isActive)
        #expect(s.selectedPage == ref)
        #expect(s.selectedSection == section)
    }

    @Test func stopRestoresASectionWithoutPage() async throws {
        let s = try await session("basic")
        let section = try #require(s.metamodel.sections.first { $0.folders.contains("glossary") || $0.folders.contains("domain-terms") })
        s.select(section: section.id)
        let tour = TourModel(session: s)
        tour.start()
        tour.next()
        tour.stop()
        #expect(s.selectedSection == section.id)
        #expect(s.selectedPage == nil)
    }

    @Test func stopWithNothingSelectedBeforeClearsTheSelection() async throws {
        let s = try await session("basic")
        let tour = TourModel(session: s)
        tour.start()
        #expect(s.selectedPage != nil)
        tour.stop()
        #expect(s.selectedPage == nil)
        #expect(s.selectedSection == nil)
    }

    @Test func startingAgainWhileActiveKeepsTheFirstSelection() async throws {
        let s = try await session("basic")
        let ref = try #require(s.store.pages(in: "functional-requirements").first?.ref)
        s.select(page: ref)
        let tour = TourModel(session: s)
        tour.start()
        tour.next()
        tour.start()
        #expect(tour.current == 0)
        tour.stop()
        #expect(s.selectedPage == ref)
    }

    @Test func stopWhenThePreTourPageIsGoneFallsBackToItsSection() async throws {
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(copy))
        let ref = try #require(s.store.pages(in: "functional-requirements").first?.ref)
        s.select(page: ref)
        let section = s.selectedSection
        let tour = TourModel(session: s)
        tour.start()
        tour.next()
        try FileManager.default.removeItem(at: copy.appending(path: "wiki/functional-requirements/\(ref.stem).md"))
        s.replace(with: LoadedWiki(root: try Preflight.open(copy)))
        tour.stop()
        #expect(s.selectedPage == nil)
        #expect(s.selectedSection == section)
    }

    @Test func aReloadKeepsTheCurrentStepWhenItStillExists() async throws {
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(copy))
        let tour = TourModel(session: s)
        tour.start()
        while tour.steps[tour.current].id != "tour-requirement" { tour.next() }
        let before = tour.current
        // An earlier step goes: the stakeholders have no page after the reload.
        try FileManager.default.removeItem(at: copy.appending(path: "wiki/stakeholders"))
        s.replace(with: LoadedWiki(root: try Preflight.open(copy)))
        tour.followWiki()
        #expect(!tour.steps.map(\.id).contains("tour-stakeholder"))
        #expect(tour.steps[tour.current].id == "tour-requirement")
        #expect(tour.current == before - 1)
        #expect(tour.isActive)
    }

    @Test func aReloadThatDropsTheCurrentStepClampsTheStep() async throws {
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(copy))
        let tour = TourModel(session: s)
        tour.start()
        let ids = tour.steps.map(\.id)
        let last = ids.count - 1
        for _ in 0..<last { tour.next() }
        #expect(tour.current == last)
        // The decisions have no page after the reload, so their step goes.
        try FileManager.default.removeItem(at: copy.appending(path: "wiki/decisions"))
        s.replace(with: LoadedWiki(root: try Preflight.open(copy)))
        tour.followWiki()
        #expect(!tour.steps.map(\.id).contains("tour-decision"))
        #expect(tour.steps.count == ids.count - 1)
        #expect(tour.steps[tour.current].id == "tour-method")
        #expect(tour.isActive)
    }

    @Test func aReloadThatLeavesOnlyTheMethodStepKeepsTheTour() async throws {
        let copy = try Fixture.tempCopy("basic")
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let s = await WikiSession.open(try Preflight.open(copy))
        let tour = TourModel(session: s)
        tour.start()
        // Without these types in the metamodel their steps go. The method step stays.
        for type in ["goal", "stakeholder", "functional-requirement", "decision-record"] {
            try? FileManager.default.removeItem(at: copy.appending(path: "_system/metamodel/types/type-\(type).md"))
        }
        s.replace(with: LoadedWiki(root: try Preflight.open(copy)))
        tour.followWiki()
        #expect(tour.steps.map(\.id) == ["tour-method"])
        #expect(tour.isActive)
    }

    @Test func leavingTheStepAndComingBack() async throws {
        let s = try await session("basic")
        let tour = TourModel(session: s)
        tour.start()
        tour.next()
        #expect(tour.isOnStep)
        let step = tour.current
        let other = try #require(s.store.pages(in: "functional-requirements").first?.ref)
        s.select(page: other)
        #expect(!tour.isOnStep)
        #expect(tour.current == step)
        tour.returnToStep()
        #expect(tour.isOnStep)
    }

    @Test func aProjectionShowsByItsLabelOrNotAtAll() async throws {
        let s = try await session("arc42-views")
        let tour = TourModel(session: s)
        let named = tour.stops.compactMap(\.projection)
        #expect(!named.isEmpty)
        for label in named {
            #expect(!label.isEmpty)
            #expect(!s.metamodel.projections.contains { $0.name == label })
        }
        #expect(s.metamodel.label(ofProjection: "story-map") == "story map")
        #expect(s.metamodel.label(ofProjection: "no-such-projection") == "")
    }

    @Test func aGoneSessionGivesAnEmptyTour() async throws {
        var s: WikiSession? = try await session("basic")
        let tour = TourModel(session: try #require(s))
        s = nil
        #expect(tour.steps.isEmpty)
        tour.start()
        #expect(!tour.isActive)
    }

    /// The rule: a step id, type name, projection name or text contains no section id (as a word) and
    /// no folder name with a hyphen, such as `functional-requirements`. A type or projection name must not
    /// equal a folder name, unless it is also a type name of the metamodel (`context` is both).
    /// Ordinary words in a sentence, such as "goals", are allowed.
    @Test func tourNamesNoSectionIds() async throws {
        for name in Fixture.names {
            let s = try await session(name)
            let sectionIDs = Set(s.metamodel.sections.map(\.id))
            let folders = Set(s.metamodel.types.compactMap { $0.folder.split(separator: "/").last.map(String.init) })
            let hyphenated = folders.filter { $0.contains("-") }
            let typeNames = Set(s.metamodel.types.map(\.name))
            func words(_ text: String) -> [String] { text.split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init) }
            for step in TourSteps.all {
                let names = [step.id, step.showsType, step.showsProjection].compactMap { $0 }
                for value in names + [step.text] {
                    for id in sectionIDs { #expect(!words(value).contains(id), "\(name) \(step.id) \(id)") }
                    for folder in hyphenated { #expect(!value.contains(folder), "\(name) \(step.id) \(folder)") }
                }
                for value in [step.showsType, step.showsProjection].compactMap({ $0 }) {
                    #expect(!folders.contains(value) || typeNames.contains(value), "\(name) \(value)")
                }
                for value in [step.id] + (step.title.map { [$0] } ?? []) {
                    #expect(!folders.contains(value), "\(name) \(value)")
                }
                #expect(!step.text.contains("wiki/"))
            }
        }
    }

    @Test func stepDataRoundTripsAsJSON() throws {
        let data = try JSONEncoder().encode(TourSteps.all)
        #expect(try JSONDecoder().decode([TourStep].self, from: data) == TourSteps.all)
        #expect(Set(TourSteps.all.map(\.id)).count == TourSteps.all.count)
    }

    @Test func methodTextNamesThreeLoops() {
        let page = renderPage(MethodText.markdown, resolve: { _ in .missing }, title: { _ in nil })
        #expect(page.problems.isEmpty)
        var headings: [Int: [String]] = [:]
        for case .heading(let level, let inlines) in page.blocks {
            headings[level, default: []].append(inlines.map { inline in
                if case .text(let t) = inline { return t }
                return ""
            }.joined())
        }
        #expect(headings[1] == ["Three loops"])
        let second = headings[2] ?? []
        #expect(Array(second.prefix(3)) == ["Capture", "Inspect", "Clarify"])
        #expect(second.count == 4)
    }
}
