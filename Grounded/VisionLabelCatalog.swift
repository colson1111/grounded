import Foundation
import Vision

enum VisionLabelCatalog {
    private static var cachedAll: [String]?
    private static var cachedSet: Set<String>?

    /// Vision identifiers that are too broad or unsuitable for anchors — filtered everywhere.
    private static let excludedIdentifiers: Set<String> = {
        let raw: [String] = [
            // Taxonomy superclasses & generics
            "machine", "structure", "artifact", "device", "equipment", "instrumentality",
            "implement", "conveyance", "vehicle", "container", "covering", "whole",
            "object", "entity", "physical_entity", "abstraction", "matter", "substance",
            "living_thing", "organism", "natural_object", "psychological_feature",
            "furniture", "furnishing", "fixture", "commodity", "product", "creation",
            "construction", "building", "establishment", "workplace", "housing",
            "electronic_equipment", "electronic_device", "home_appliance",
            "appliance", "electrical_device", "mechanical_device", "sporting_goods",
            "sports_equipment", "outdoor_equipment", "hand_tool", "power_tool",
            "tool", "utensil", "tableware", "kitchenware", "cookware",
            "clothing", "apparel", "garment", "footwear", "accessory",
            "animal", "plant", "person", "human", "homo", "man", "woman",
            "food", "produce", "nutriment", "beverage", "drink",
            "wood", "wood_processed", "material", "textile", "fabric", "paper",
            "metal", "plastic", "glass", "ceramic", "rubber", "leather",
            // Scene / environment
            "outdoor", "land", "sky", "blue_sky",
            // Confirmed junk — too generic for anchors
            "consumer_electronics", "electronics", "interior_room", "interior_shop",
            "art", "decoration", "document", "portal", "door",
            "raw_glass", "frame", "adult",
            // Text / scene noise — often spurious on object photos
            "handwriting", "text", "letter", "word", "signature", "alphabet",
        ]
        return Set(raw.map { normalize($0) })
    }()

    static func isExcluded(_ identifier: String) -> Bool {
        excludedIdentifiers.contains(normalize(identifier))
    }

    private static var curatedSet: Set<String> {
        Set(filteredVisionLabelCategories.flatMap(\.labels).map { normalize($0) })
    }

    static var allIdentifiers: [String] {
        if let cachedAll { return cachedAll.filter { !isExcluded($0) } }
        return curatedIdentifiers
    }

    static var curatedIdentifiers: [String] {
        filteredVisionLabelCategories.flatMap(\.labels).sorted()
    }

    static var browseableIdentifiers: [String] {
        let source = cachedAll ?? curatedIdentifiers
        return source.filter { !isExcluded($0) }
    }

    static func preloadTaxonomy() {
        guard cachedAll == nil else { return }
        Task.detached(priority: .utility) {
            let request = VNClassifyImageRequest()
            guard let ids = try? request.supportedIdentifiers() else { return }
            await MainActor.run {
                cachedAll = ids.sorted()
                cachedSet = Set(ids)
            }
        }
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
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    static func matches(stored: String, detected: String) -> Bool {
        let storedID = normalize(stored)
        let detectedID = normalize(detected)
        guard !storedID.isEmpty, !detectedID.isEmpty else { return false }
        if isExcluded(detectedID) { return false }
        if storedID == detectedID { return true }
        return detectedID.contains(storedID) || storedID.contains(detectedID)
    }

    static func isSupported(_ identifier: String) -> Bool {
        guard !isExcluded(identifier) else { return false }
        let normalized = normalize(identifier)
        if curatedSet.contains(normalized) { return true }
        return cachedSet?.contains(normalized) ?? false
    }

    /// Returns the canonical Vision identifier for storage, if one exists.
    static func canonicalIdentifier(for raw: String) -> String? {
        let normalized = normalize(raw)
        guard !normalized.isEmpty, !isExcluded(normalized) else { return nil }

        if curatedSet.contains(normalized) { return normalized }
        if let cachedSet {
            if cachedSet.contains(normalized) { return normalized }
            if let match = cachedSet.first(where: { !isExcluded($0) && ($0.contains(normalized) || normalized.contains($0)) }) {
                return match
            }
        }

        if let curatedMatch = curatedSet.first(where: { $0.contains(normalized) || normalized.contains($0) }) {
            return curatedMatch
        }

        return normalized
    }

    static func normalizedAnchorList(_ labels: [String]) -> [String] {
        var seen = Set<String>()
        return labels.compactMap { label in
            guard let canonical = canonicalIdentifier(for: label) else { return nil }
            guard !seen.contains(canonical) else { return nil }
            seen.insert(canonical)
            return canonical
        }
    }
}
