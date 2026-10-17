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
            SessionActivityView(summary: context.state, stale: context.isStale)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(URL(string: "sidepulse://sessions"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("SidePulse", systemImage: "circle.hexagongrid.fill").font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.total) sessions").font(.caption) }
                DynamicIslandExpandedRegion(.bottom) {
                    SessionActivityView(summary: context.state, stale: context.isStale, compact: true)
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(context.state.color)
            } compactTrailing: {
                Text("\(context.state.total)").monospacedDigit()
            } minimal: {
                Image(systemName: context.state.symbol).foregroundStyle(context.state.color)
            }
            .widgetURL(URL(string: "sidepulse://sessions"))
        }
    }
}

private struct SessionActivityView: View {
    let summary: SessionActivitySummary
    let stale: Bool
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !compact {
                HStack {
                    Label("SidePulse", systemImage: "circle.hexagongrid.fill").font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(summary.total) sessions").font(.caption)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: summary.symbol).foregroundStyle(summary.color)
                Text(summary.title).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                if let progress = summary.progress { Text("\(progress)%").monospacedDigit().font(.caption) }
            }
            Text(summary.statusLabel + " · " + summary.appName).font(.subheadline).foregroundStyle(summary.color)
            if !compact, let message = summary.message, !message.isEmpty { Text(message).font(.caption).lineLimit(2) }
            HStack {
                Text("\(summary.working) working · \(summary.attention) need attention · \(summary.done) done")
                Spacer(minLength: 0)
            }.font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(stale ? "Last reported" : "Updated")
                Text(summary.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }.font(.caption2).foregroundStyle(.secondary)
        }.padding(compact ? 4 : 16)
    }
}

private extension SessionActivitySummary {
    var symbol: String {
        switch state {
        case "error": return "exclamationmark.triangle.fill"
        case "blocked": return "hand.raised.fill"
        case "working": return "gearshape.2.fill"
        case "done": return "checkmark.circle.fill"
        default: return "pause.circle"
        }
    }
    var color: Color {
        switch state {
        case "error": return .red
        case "blocked": return .orange
        case "working": return .cyan
        case "done": return .green
        default: return .secondary
        }
    }
}
