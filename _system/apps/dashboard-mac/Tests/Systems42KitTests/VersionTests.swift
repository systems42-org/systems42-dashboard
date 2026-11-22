import Testing
@testable import Systems42Kit

@Test func versionIsSemantic() {
    #expect(Systems42Kit.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil)
}
