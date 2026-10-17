import Foundation

/// Compact display data only. The session ledger remains the source of truth.
struct SessionActivitySummary: Codable, Hashable {
    let total: Int
    let working: Int
    let attention: Int
    let done: Int
    let state: String
    let title: String
    let statusLabel: String
    let appName: String
    let message: String?
    let progress: Int?
    let updatedAt: Date
}
