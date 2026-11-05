import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SessionActivityBundle: WidgetBundle {
    var body: some Widget { SessionActivityWidget() }
}

struct SessionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            ProLights(summary: context.state, stale: context.isStale)
                .padding(24)
                .activityBackgroundTint(.black)
                .widgetURL(URL(string: "sidepulse://sessions"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    ProLights(summary: context.state, stale: context.isStale).padding(16)
                }
            } compactLeading: {
                Circle().fill(context.state.color).frame(width: 8, height: 8)
            } compactTrailing: {
                Circle().fill(context.state.color).frame(width: 8, height: 8)
            } minimal: {
                Circle().fill(context.state.color).frame(width: 8, height: 8)
            }
            .widgetURL(URL(string: "sidepulse://sessions"))
        }
    }
}

/// SidePulse Pro's eight lights, without session names or messages on the Lock Screen.
/// ActivityKit animates updates for at most two seconds; it cannot run an LED loop.
private struct ProLights: View {
    let summary: SessionActivitySummary
    let stale: Bool
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<8) { index in
                Circle()
                    .fill(summary.color.gradient)
                    .frame(maxWidth: 22, maxHeight: 22)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: summary.color.opacity(0.7), radius: 7)
                    .opacity(stale ? 0.35 : (index.isMultiple(of: 2) ? 1 : 0.75))
                    .id("\(index):\(summary.updatedAt.timeIntervalSince1970)")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 1.2), value: summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SidePulse")
    }
}

private extension SessionActivitySummary {
    var color: Color {
        switch state {
        case "error", "blocked": return Color(red: 1, green: 0.23, blue: 0)
        case "working": return .cyan
        case "done": return .green
        default: return .clear
        }
    }
}
