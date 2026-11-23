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
                #expect(step.showsType == nil ? step.id == "tour-method" : !pages(of: step, in: s).isEmpty, "\(name) \(step.id)")
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

    @Test func theVisionPageComesFirstInItsStep() async throws {
        let s = try await session("basic")
        let tour = TourModel(session: s)
        tour.start()
        let ref = try #require(s.selectedPage)
        #expect(s.store.page(ref)?.title == s.orientation?.title)
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
        tour.next()
        tour.next()
        let id = tour.steps[tour.current].id
        s.replace(with: LoadedWiki(root: try Preflight.open(copy)))
        tour.followWiki()
        #expect(tour.steps[tour.current].id == id)
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
        #expect(!tour.steps.map(\.id).contains("tour-decisions"))
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

    @Test func projectionIsNamedOnlyWhenTheMetamodelHasIt() async throws {
        let s = try await session("arc42-views")
        let tour = TourModel(session: s)
        tour.start()
        let named = tour.stops.compactMap(\.projection)
        #expect(!named.isEmpty)
        for name in named { #expect(s.metamodel.projections.contains { $0.name == name }) }
    }

    @Test func aGoneSessionGivesAnEmptyTour() async throws {
        var s: WikiSession? = try await session("basic")
        let tour = TourModel(session: try #require(s))
        s = nil
        #expect(tour.steps.isEmpty)
        tour.start()
        #expect(!tour.isActive)
    }

    @Test func tourNamesNoSectionIds() async throws {
        for name in Fixture.names {
            let s = try await session(name)
            let sectionIDs = Set(s.metamodel.sections.map(\.id))
            let folders = Set(s.metamodel.types.compactMap { $0.folder.split(separator: "/").last.map(String.init) })
            let typeNames = Set(s.metamodel.types.map(\.name))
            for step in TourSteps.all {
                for value in [step.id, step.showsType, step.showsProjection].compactMap({ $0 }) {
                    #expect(!sectionIDs.contains(value), "\(name) \(step.id)")
                }
                for value in [step.showsType, step.showsProjection].compactMap({ $0 }) {
                    #expect(!folders.contains(value) || typeNames.contains(value), "\(name) \(value)")
                }
                let words = (step.title + " " + step.text).split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init)
                for word in words { #expect(!sectionIDs.contains(word), "\(name) \(step.id) \(word)") }
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
