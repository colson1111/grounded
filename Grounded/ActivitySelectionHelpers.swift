import Foundation
import FamilyControls
import ManagedSettings

enum ActivitySelectionHelpers {
    private static let plistEncoder = PropertyListEncoder()
    private static let plistDecoder = PropertyListDecoder()

    /// Max exceptions Apple allows in `except:` for category shields.
    private static let maxShieldExceptions = 50

    static func applyShield(
        selection: FamilyActivitySelection,
        allowedExceptions: Set<ApplicationToken> = [],
        to store: ManagedSettingsStore
    ) {
        let exceptions = resolvedExceptions(for: selection, allowedExceptions: allowedExceptions)

        if selection.includeEntireCategory && !selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = .all(except: exceptions)
            store.shield.applications = nil
        } else if !selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = .specific(
                selection.categoryTokens,
                except: exceptions
            )
            store.shield.applications = nil
        } else if !selection.applicationTokens.isEmpty {
            store.shield.applications = selection.applicationTokens
            store.shield.applicationCategories = nil
        } else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
        }

        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
    }

    /// With "All Apps" + `includeEntireCategory`, `applicationTokens` lists apps still
    /// checked for blocking — not the few you unchecked. Persisted `allowedExceptions`
    /// holds tokens removed in the picker (up to 50).
    private static func resolvedExceptions(
        for selection: FamilyActivitySelection,
        allowedExceptions: Set<ApplicationToken>
    ) -> Set<ApplicationToken> {
        if !allowedExceptions.isEmpty {
            return allowedExceptions
        }
        guard selection.includeEntireCategory,
              !selection.categoryTokens.isEmpty,
              selection.applicationTokens.count <= maxShieldExceptions else {
            return []
        }
        return selection.applicationTokens
    }

    static func encodeSelection(_ selection: FamilyActivitySelection) -> Data? {
        try? plistEncoder.encode(selection)
    }

    static func decodeSelectionData(_ data: Data?) -> FamilyActivitySelection? {
        guard let data else { return nil }
        if let decoded = try? plistDecoder.decode(FamilyActivitySelection.self, from: data) {
            return decoded
        }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    static func encodeAllowedTokens(_ tokens: Set<ApplicationToken>) -> Data? {
        guard !tokens.isEmpty else { return nil }
        var selection = FamilyActivitySelection()
        selection.applicationTokens = tokens
        return encodeSelection(selection)
    }

    static func decodeAllowedTokens(from data: Data?) -> Set<ApplicationToken> {
        decodeSelectionData(data)?.applicationTokens ?? []
    }

    /// `includeEntireCategory` is set only at init and is not preserved by encoding.
    static func selectionWithTokens(
        from snapshot: FamilyActivitySelection,
        includeEntireCategory storedFlag: Bool
    ) -> FamilyActivitySelection {
        let include = storedFlag
            || !snapshot.categoryTokens.isEmpty
            || !snapshot.applicationTokens.isEmpty
        var selection = FamilyActivitySelection(includeEntireCategory: include)
        selection.applicationTokens = snapshot.applicationTokens
        selection.categoryTokens = snapshot.categoryTokens
        selection.webDomainTokens = snapshot.webDomainTokens
        return selection
    }

    /// Always use `includeEntireCategory: true` so "All Apps" exposes per-app tokens.
    static func selectionForPicker(from snapshot: FamilyActivitySelection) -> FamilyActivitySelection {
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        selection.applicationTokens = snapshot.applicationTokens
        selection.categoryTokens = snapshot.categoryTokens
        selection.webDomainTokens = snapshot.webDomainTokens
        return selection
    }

    static func decodedSelection(
        from data: Data?,
        includeEntireCategory: Bool
    ) -> FamilyActivitySelection? {
        guard let data, let snapshot = decodeSelectionData(data) else {
            return nil
        }
        return selectionWithTokens(from: snapshot, includeEntireCategory: includeEntireCategory)
    }

    static func mergeAllowedExceptions(
        existing data: Data?,
        sessionRemovals: Set<ApplicationToken>,
        sessionReblocked: Set<ApplicationToken>
    ) -> Data? {
        guard !sessionRemovals.isEmpty || !sessionReblocked.isEmpty else { return data }
        var allowed = decodeAllowedTokens(from: data)
        allowed.formUnion(sessionRemovals)
        allowed.subtract(sessionReblocked)
        return encodeAllowedTokens(allowed)
    }
}
