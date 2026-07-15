import SwiftUI

// MARK: - Preflight Media Check Views

extension PreflightClipStatus {
  var color: Color {
    switch self {
    case .newMedia: return .green
    case .alreadyInDestination, .alreadyInAnotherProject, .alreadyOnBackup:
      return .blue
    case .possibleDuplicate: return .orange
    case .sameNameDifferentSize: return .red
    }
  }

  var systemImage: String {
    switch self {
    case .newMedia: return "sparkles"
    case .alreadyInDestination: return "externaldrive.fill.badge.checkmark"
    case .alreadyInAnotherProject: return "rectangle.stack.badge.checkmark"
    case .alreadyOnBackup: return "archivebox.fill"
    case .possibleDuplicate: return "questionmark.diamond.fill"
    case .sameNameDifferentSize: return "exclamationmark.triangle.fill"
    }
  }
}

struct PreflightSummaryCard: View {
  @ObservedObject var preflight: PreflightMediaCheckViewModel
  let canRun: Bool
  let onRun: () -> Void

  var body: some View {
    CardContainer {
      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 8) {
            Label("Preflight Media Check", systemImage: "checklist.checked")
              .font(.headline)
            if preflight.isRunning {
              ProgressView()
                .controlSize(.small)
            }
          }

          Text(preflight.message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

          HStack(spacing: 8) {
            summaryPill("New", count: preflight.summary.newCount, color: .green)
            summaryPill(
              "Imported",
              count: preflight.summary.alreadyImportedCount,
              color: .blue
            )
            summaryPill(
              "Review",
              count: preflight.summary.reviewCount,
              color: .orange
            )
          }
          .opacity(preflight.hasResults ? 1 : 0.45)
        }

        Spacer(minLength: 12)

        Button(preflight.hasResults ? "Refresh Preflight" : "Run Preflight") {
          onRun()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canRun || preflight.isRunning)
      }
      .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
    }
  }

  private func summaryPill(
    _ label: String,
    count: Int,
    color: Color
  ) -> some View {
    Text("\(label) \(count)")
      .font(.caption.bold())
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(color.opacity(0.13), in: Capsule())
      .foregroundStyle(color)
  }
}

struct PreflightStatusBadge: View {
  let result: PreflightClipResult
  var compact = false

  var body: some View {
    Label(result.status.label, systemImage: result.status.systemImage)
      .font(compact ? .caption2.bold() : .caption.bold())
      .lineLimit(1)
      .padding(.horizontal, compact ? 6 : 8)
      .padding(.vertical, compact ? 3 : 4)
      .background(result.status.color.opacity(0.14), in: Capsule())
      .foregroundStyle(result.status.color)
      .help(helpText)
  }

  private var helpText: String {
    var parts = [result.reason]
    if let location = result.matchedLocationLabel, !location.isEmpty {
      parts.append("Location: \(location)")
    }
    if let path = result.matchedPath, !path.isEmpty {
      parts.append(path)
    }
    return parts.joined(separator: "\n")
  }
}
