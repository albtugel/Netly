import Foundation

/// Converts amounts of different periodicity into a monthly figure, rounded to cents.
enum MonthlyEquivalent {
    static func subscriptionCost(price: Decimal, cycle: BillingCycle) -> Decimal {
        let monthly: Decimal = switch cycle {
        case .weekly: price * 52 / 12
        case .monthly: price
        case .quarterly: price / 3
        case .yearly: price / 12
        }
        return monthly.rounded(scale: 2)
    }

    /// Spreads `amount` evenly over the months left until `deadline`; an overdue or current-month deadline counts as one month.
    static func installment(amount: Decimal, from today: CalendarDate, until deadline: CalendarDate) -> Decimal {
        let months = max(1, today.monthsUntil(deadline))
        return (amount / Decimal(months)).rounded(scale: 2, mode: .up)
    }
}
