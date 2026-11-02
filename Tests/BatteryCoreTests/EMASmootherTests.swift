import Foundation
import Testing
@testable import BatteryCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Suite struct EMASmootherTests {
    @Test func firstSampleIsTheValue() {
        var s = EMASmoother(halfLife: 1800)
        #expect(s.value == nil)
        s.add(26.6, at: t0)
        #expect(s.value == 26.6)
    }

    @Test func constantInputStaysConstant() throws {
        var s = EMASmoother(halfLife: 30)
        for i in 0..<200 { s.add(7.5, at: t0.addingTimeInterval(TimeInterval(i * 10))) }
        #expect(abs(try #require(s.value) - 7.5) < 1e-9)
    }

    @Test func warmUpIsTheMeanSoFar() throws {
        var s = EMASmoother(halfLife: 1800)
        s.add(26.6, at: t0)
        for i in 1...60 { s.add(8.0, at: t0.addingTimeInterval(TimeInterval(i * 10))) }
        #expect(try #require(s.value) < 8.5)
    }

    @Test func halfLifeStep() throws {
        var s = EMASmoother(halfLife: 1800)
        for i in 0...900 { s.add(0.0, at: t0.addingTimeInterval(TimeInterval(i * 10))) }
        let base = 9_000
        for i in 1...180 { s.add(10.0, at: t0.addingTimeInterval(TimeInterval(base + i * 10))) }
        #expect(abs(try #require(s.value) - 5.0) < 0.15)
    }

    @Test func gapOverMaxGapReseeds() {
        var s = EMASmoother(halfLife: 1800)
        for i in 0..<10 { s.add(10.0, at: t0.addingTimeInterval(TimeInterval(i * 10))) }
        s.add(2.0, at: t0.addingTimeInterval(90 + 400))
        #expect(s.value == 2.0)
    }

    @Test func duplicateTimestampKeepsValue() {
        var s = EMASmoother(halfLife: 30)
        s.add(4.0, at: t0)
        s.add(6.0, at: t0.addingTimeInterval(10))
        let before = s.value
        s.add(100.0, at: t0.addingTimeInterval(10))
        #expect(s.value == before)
    }
}
