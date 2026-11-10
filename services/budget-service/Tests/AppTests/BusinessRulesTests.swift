import Foundation
import Testing

@testable import App

@Suite struct BusinessRulesTests {
    let today = CalendarDate("2026-09-26")!

    func goal(target: Decimal = 1500, saved: Decimal = 300, date: String = "2027-09-26", priority: Int = 5, status: GoalStatus = .active) -> GoalFields {
        GoalFields(name: "Laptop", targetAmount: target, savedAmount: saved, targetDate: CalendarDate(date)!, priority: priority, status: status)
    }

    @Test(arguments: [
        ("0", false, "must_be_positive"),
        ("-1", true, "must_not_be_negative"),
        ("1000000.01", false, "too_large"),
        ("9.999", false, "too_precise"),
    ])
    func moneyRules(amount: String, allowsZero: Bool, code: String) {
        var validator = Validator()
        validator.money(Decimal(string: amount)!, field: "price", allowsZero: allowsZero, maximum: 1_000_000)
        #expect(validator.errors.map(\.code) == [code])
    }

    @Test func zeroIsAllowedOnlyWhereTheRuleSaysSo() {
        var validator = Validator()
        validator.money(0, field: "savedAmount", allowsZero: true, maximum: 100)
        validator.money(Decimal(string: "99.99")!, field: "price", maximum: 100)
        #expect(validator.errors.isEmpty)
    }

    @Test func textIsTrimmedBeforeTheLengthCheck() {
        var validator = Validator()
        validator.text("   ", field: "name")
        validator.text("  " + String(repeating: "a", count: 100) + "  ", field: "creditor")
        validator.text(String(repeating: "a", count: 101), field: "note")
        #expect(validator.errors.map(\.code) == ["blank", "too_long"])
        #expect(validator.errors.map(\.field) == ["name", "note"])
    }

    @Test func savedAmountMustNotExceedTheTarget() {
        var validator = Validator()
        goal(target: 1000, saved: 1000.01).validate(into: &validator, previous: nil, today: today)
        #expect(validator.errors == [FieldError(field: "savedAmount", code: "exceeds_target", message: "Must not exceed targetAmount")])
    }

    @Test func crossFieldRuleIsSkippedWhenAnAmountIsInvalidOnItsOwn() {
        var validator = Validator()
        goal(target: 0, saved: 50).validate(into: &validator, previous: nil, today: today)
        #expect(validator.errors.map(\.code) == ["must_be_positive"])
    }

    @Test func pastTargetDateIsCheckedOnlyWhenItChanges() {
        let overdue = goal(date: "2026-01-01")
        var created = Validator()
        overdue.validate(into: &created, previous: nil, today: today)
        #expect(created.errors.map(\.code) == ["must_be_in_future"])

        var renamed = Validator()
        var update = overdue
        update.name = "New laptop"
        update.validate(into: &renamed, previous: overdue, today: today)
        #expect(renamed.errors.isEmpty)
    }

    @Test(arguments: [0, 11])
    func priorityMustBeBetweenOneAndTen(priority: Int) {
        var validator = Validator()
        goal(priority: priority).validate(into: &validator, previous: nil, today: today)
        #expect(validator.errors.map(\.code) == ["out_of_range"])
    }

    @Test func requiredMonthlyContributionSpreadsTheRemainder() {
        #expect(goal(target: 1500, saved: 300, date: "2027-09-26").requiredMonthlyContribution(today: today) == 100)
        #expect(goal(target: 1500, saved: 1500).requiredMonthlyContribution(today: today) == 0)
        #expect(goal(status: .completed).requiredMonthlyContribution(today: today) == 0)
        #expect(goal(target: 1000, saved: 400, date: "2026-01-01").requiredMonthlyContribution(today: today) == 600)
    }

    @Test func partialUpdateKeepsUntouchedFields() throws {
        let debt = DebtFields(creditor: "Bank", amount: 500, dueDate: CalendarDate("2027-01-15")!)
        let update = try JSONDecoder().decode(DebtFields.UpdateRequest.self, from: Data(#"{"amount": 250}"#.utf8))
        let updated = debt.applying(update)
        #expect(updated.amount == 250)
        #expect(updated.creditor == "Bank")
        #expect(updated.dueDate == debt.dueDate)
    }
}
