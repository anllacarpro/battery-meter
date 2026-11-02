import Testing
import Foundation
@testable import BatteryCore

@Suite struct HealthTrendCopyTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    static let locale = Locale(identifier: "en_US_POSIX")

    func sentence(_ trend: HealthTrend) -> String? {
        HealthTrendCopy.sentence(for: trend, calendar: Self.calendar, locale: Self.locale)
    }

    @Test func atOrBelow80SaysBelowThreshold() {
        #expect(sentence(.declining(currentPercent: 78, lossPerMonth: 0.6, reaches80: nil))
                == "Losing 0.6% a month. Below 80%, Apple's service threshold.")
        #expect(sentence(.declining(currentPercent: 80, lossPerMonth: 0.6, reaches80: nil))
                == "Losing 0.6% a month. Below 80%, Apple's service threshold.")
    }

    @Test func nilDateAbove80IsPastTenYears() {
        #expect(sentence(.declining(currentPercent: 98.5, lossPerMonth: 0.1, reaches80: nil))
                == "Losing 0.1% a month. Won't reach 80% in the next 10 years.")
    }

    @Test func datedProjection() {
        // 2027-04-15 00:00 UTC
        let date = Date(timeIntervalSince1970: 1_807_747_200)
        #expect(sentence(.declining(currentPercent: 97, lossPerMonth: 3.1, reaches80: date))
                == "Losing 3.1% a month. Reaches 80% around April 2027.")
    }

    @Test func steady() {
        #expect(sentence(.steady(currentPercent: 98.84)) == "Health is steady at 98.8%.")
    }

    @Test func tinyLossReadsUnderTenthOfPercent() {
        #expect(sentence(.declining(currentPercent: 99, lossPerMonth: 0.04, reaches80: nil))
                == "Losing under 0.1% a month. Won't reach 80% in the next 10 years.")
    }

    @Test func notEnoughDataHasNoSentence() {
        #expect(sentence(.notEnoughData(daysCollected: 3)) == nil)
    }
}
