// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import Foundation

/// The ids inside a container — items, sequences, alternatives, features — are slugs: lowercase
/// letters, digits and hyphens, as the sidecar proposal writes them. They are local to the
/// container and chosen by whoever authors it; this makes a first one from a title.
public enum Slug {
    /// "The Talons of Weng-Chiang" becomes "the-talons-of-weng-chiang". Accents are stripped, runs
    /// of anything else collapse to one hyphen, and an empty result becomes "item" so the caller
    /// always gets a usable id.
    public static func make(from title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var slug = ""
        var pendingHyphen = false
        for scalar in folded.unicodeScalars {
            if (scalar.value >= 0x61 && scalar.value <= 0x7A) || (scalar.value >= 0x30 && scalar.value <= 0x39) {
                if pendingHyphen && !slug.isEmpty { slug.append("-") }
                pendingHyphen = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingHyphen = true
            }
        }
        return slug.isEmpty ? "item" : slug
    }

    /// The slug, or the first of "slug-2", "slug-3", … not in `taken`.
    public static func unique(from title: String, avoiding taken: Set<String>) -> String {
        let base = make(from: title)
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    public static func isValid(_ slug: String) -> Bool {
        !slug.isEmpty && !slug.hasPrefix("-") && !slug.hasSuffix("-") && slug.unicodeScalars.allSatisfy {
            ($0.value >= 0x61 && $0.value <= 0x7A) || ($0.value >= 0x30 && $0.value <= 0x39) || $0 == "-"
        }
    }
}
