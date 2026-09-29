import Foundation
import Testing

@testable import App

@Suite struct MonthlyEquivalentTests {
    @Test(arguments: [
        (BillingCycle.weekly, "10", "43.33"),
        (.monthly, "10", "10"),
        (.quarterly, "10", "3.33"),
        (.yearly, "119.88", "9.99"),
    ])
    func subscriptionCost(cycle: BillingCycle, price: String, expected: String) {
        #expect(MonthlyEquivalent.subscriptionCost(price: Decimal(string: price)!, cycle: cycle) == Decimal(string: expected))
    }

    @Test func installmentRoundsUpAndNeverDividesByZero() {
        let today = CalendarDate("2026-09-26")!
        #expect(MonthlyEquivalent.installment(amount: 100, from: today, until: CalendarDate("2026-12-26")!) == Decimal(string: "33.34"))
        #expect(MonthlyEquivalent.installment(amount: 100, from: today, until: CalendarDate("2026-09-01")!) == 100)
    }
}
