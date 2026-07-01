import Foundation

/// Category registry backed by CLIP zero-shot categories.
/// Interface kept compatible with previous Vision-backed version so callers are unchanged.
enum VisionLabelCatalog {

    static func preloadTaxonomy() {}

    static var allIdentifiers: [String] { CLIPCategories.allIDs }
    static var curatedIdentifiers: [String] { CLIPCategories.allIDs }
    static var browseableIdentifiers: [String] { CLIPCategories.allIDs }

    static func isExcluded(_ identifier: String) -> Bool { false }

    static func isSupported(_ identifier: String) -> Bool {
        CLIPCategories.idSet.contains(normalize(identifier))
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    static func displayName(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func matches(stored: String, detected: String) -> Bool {
        normalize(stored) == normalize(detected)
    }

    static func canonicalIdentifier(for raw: String) -> String? {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return nil }
        if CLIPCategories.idSet.contains(normalized) { return normalized }
        return CLIPCategories.allIDs.first { $0.contains(normalized) || normalized.contains($0) }
    }

    static func normalizedAnchorList(_ labels: [String]) -> [String] {
        var seen = Set<String>()
        return labels.compactMap { label in
            guard let canonical = canonicalIdentifier(for: label) else { return nil }
            guard seen.insert(canonical).inserted else { return nil }
            return canonical
        }
    }
}

enum CLIPCategories {
    static let allIDs: [String] = clipLabelCategories.flatMap(\.labels).sorted()
    static let idSet: Set<String> = Set(allIDs)
}
