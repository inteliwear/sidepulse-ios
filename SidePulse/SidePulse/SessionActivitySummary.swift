import Foundation

/// Only visual state crosses into the Lock Screen extension. Session text stays in the app.
struct SessionActivitySummary: Codable, Hashable {
    let state: String
    let updatedAt: Date
}
