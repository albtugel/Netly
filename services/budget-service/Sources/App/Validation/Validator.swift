import Foundation

/// Collects every rule violation of a request instead of stopping at the first one.
struct Validator {
    private(set) var errors: [FieldError] = []

    /// Whether `field` already has a violation; cross-field rules skip fields that are invalid on their own.
    func hasError(for field: String) -> Bool {
        errors.contains { $0.field == field }
    }

    mutating func add(field: String, code: String, message: String) {
        errors.append(FieldError(field: field, code: code, message: message))
    }

    mutating func check(_ condition: Bool, field: String, code: String, message: String) {
        if !condition {
            add(field: field, code: code, message: message)
        }
    }

    /// Non-blank text, at most `maxLength` characters after trimming.
    mutating func text(_ value: String, field: String, maxLength: Int = 100) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            add(field: field, code: "blank", message: "Must not be blank")
        } else if trimmed.count > maxLength {
            add(field: field, code: "too_long", message: "Must be at most \(maxLength) characters")
        }
    }

    /// Money amount with at most two fractional digits.
    mutating func money(_ value: Decimal, field: String, allowsZero: Bool = false, maximum: Decimal) {
        if allowsZero ? value < 0 : value <= 0 {
            let message = allowsZero ? "Must be greater than or equal to 0" : "Must be greater than 0"
            add(field: field, code: allowsZero ? "must_not_be_negative" : "must_be_positive", message: message)
        } else if value > maximum {
            add(field: field, code: "too_large", message: "Must be at most \(maximum)")
        } else if value.rounded(scale: 2) != value {
            add(field: field, code: "too_precise", message: "Must have at most 2 decimal places")
        }
    }

    mutating func range(_ value: Int, field: String, _ bounds: ClosedRange<Int>) {
        check(
            bounds.contains(value),
            field: field,
            code: "out_of_range",
            message: "Must be between \(bounds.lowerBound) and \(bounds.upperBound)"
        )
    }

    mutating func future(_ date: CalendarDate, field: String, today: CalendarDate) {
        check(date > today, field: field, code: "must_be_in_future", message: "Must be after \(today)")
    }

    func throwIfInvalid() throws {
        if !errors.isEmpty {
            throw APIError.validationFailed(errors)
        }
    }
}

extension Decimal {
    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }
}
