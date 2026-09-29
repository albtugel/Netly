/// String enum whose decoding error lists the allowed values instead of Swift type names.
protocol APIEnum: RawRepresentable, CaseIterable, Codable, Sendable where RawValue == String {}

extension APIEnum {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = Self(rawValue: raw) else {
            let allowed = Self.allCases.map(\.rawValue).joined(separator: ", ")
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Must be one of: \(allowed)")
        }
        self = value
    }
}
