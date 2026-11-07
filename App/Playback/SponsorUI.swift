// SPDX-License-Identifier: GPL-3.0-only
import FlowCore
import SwiftUI

/// SponsorBlock category names and the colors the SponsorBlock project uses for them.
enum SponsorCategory {
    static let all = ["sponsor", "selfpromo", "interaction", "intro", "outro", "preview", "filler", "music_offtopic"]

    static func name(_ category: String) -> String {
        switch category {
        case "sponsor": return "Sponsor"
        case "selfpromo": return "Self-promotion"
        case "interaction": return "Interaction reminder"
        case "intro": return "Intro"
        case "outro": return "Outro"
        case "preview": return "Preview"
        case "filler": return "Filler"
        case "music_offtopic": return "Non-music"
        default: return category.capitalized
        }
    }

    static func color(_ category: String) -> Color {
        switch category {
        case "sponsor": return Color(red: 0, green: 0.83, blue: 0)
        case "selfpromo": return Color(red: 1, green: 0.85, blue: 0)
        case "interaction": return Color(red: 0.8, green: 0, blue: 1)
        case "intro": return Color(red: 0, green: 0.9, blue: 0.9)
        case "outro": return Color(red: 0.01, green: 0.01, blue: 0.93)
        case "preview": return Color(red: 0, green: 0.56, blue: 0.84)
        case "filler": return Color(red: 0.45, green: 0, blue: 1)
        case "music_offtopic": return Color(red: 1, green: 0.6, blue: 0)
        default: return .gray
        }
    }
}

/// Thin timeline under the video showing where segments are and where playback is.
struct SegmentStrip: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        if !player.segments.isEmpty, player.duration > 0 {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.18))
                    ForEach(player.segments) { segment in
                        Rectangle()
                            .fill(SponsorCategory.color(segment.category))
                            .frame(width: max(2, width * (segment.end - segment.start) / player.duration))
                            .offset(x: width * segment.start / player.duration)
                    }
                    Rectangle().fill(.white)
                        .frame(width: 2)
                        .offset(x: min(width - 2, width * player.position / player.duration))
                }
            }
            .frame(height: 4)
            .accessibilityLabel("\(player.segments.count) SponsorBlock segments")
        }
    }
}

/// Pills over the bottom of the video: undo after an automatic skip, or skip for a manual category.
struct SkipOverlay: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        Group {
            if let skipped = player.lastSkipped {
                pill(color: SponsorCategory.color(skipped.category)) {
                    Text("Skipped \(SponsorCategory.name(skipped.category).lowercased())")
                    Divider().frame(height: 14).overlay(.white.opacity(0.5))
                    Button("Undo") { player.undoSkip() }.fontWeight(.bold)
                }
            } else if let segment = player.manualSegment {
                Button { player.skipManual() } label: {
                    pill(color: SponsorCategory.color(segment.category)) {
                        Text("Skip \(SponsorCategory.name(segment.category).lowercased())")
                        Image(systemName: "forward.end.fill")
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(10)
        .padding(.bottom, 44)
        .animation(.snappy, value: player.lastSkipped?.id)
        .animation(.snappy, value: player.manualSegment?.id)
    }

    private func pill<Content: View>(color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            content()
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.7), in: Capsule())
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}

struct SponsorBlockSettings: View {
    @AppStorage(Settings.sponsorBlockKey) private var enabled = true
    @State private var autoSkip = Settings.autoSkipCategories

    var body: some View {
        Form {
            Toggle("SponsorBlock", isOn: $enabled)
            Section("Skip automatically") {
                ForEach(SponsorCategory.all, id: \.self) { category in
                    Toggle(isOn: Binding(
                        get: { autoSkip.contains(category) },
                        set: { on in
                            if on { autoSkip.insert(category) } else { autoSkip.remove(category) }
                            UserDefaults.standard.set(Array(autoSkip), forKey: Settings.sponsorAutoSkipKey)
                        })) {
                        HStack(spacing: 10) {
                            Circle().fill(SponsorCategory.color(category)).frame(width: 10, height: 10)
                            Text(SponsorCategory.name(category))
                        }
                    }
                }
            }
            .disabled(!enabled)
        }
        .navigationTitle("SponsorBlock")
    }
}
