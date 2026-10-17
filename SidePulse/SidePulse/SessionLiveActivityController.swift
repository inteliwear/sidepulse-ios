import ActivityKit
import UIKit

@MainActor
final class SessionLiveActivityController {
    static let shared = SessionLiveActivityController()
    private var pending: Task<Void, Never>?

    func refresh(_ summary: SessionActivitySummary?, enabled: Bool, allowStart: Bool) {
        let previous = pending
        pending = Task {
            // Serialize updates so a slow older update cannot overwrite the newest state.
            await previous?.value
            let activities = Activity<SessionActivityAttributes>.activities
            guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled, let summary else {
                for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
                return
            }
            let content = ActivityContent(state: summary, staleDate: min(summary.updatedAt.addingTimeInterval(300), Date().addingTimeInterval(300)))
            if let activity = activities.first {
                if activity.content.state != summary { await activity.update(content) }
                for extra in activities.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            } else if allowStart && UIApplication.shared.applicationState == .active {
                do { _ = try Activity.request(attributes: SessionActivityAttributes(), content: content, pushType: nil) }
                catch { EventLog.append("Session Live Activity could not start: \(error.localizedDescription)") }
            }
        }
    }
}
