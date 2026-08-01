import WidgetKit
import SwiftUI

private let widgetGroupId = "group.com.mrplay.shared"

struct RecentEntry: TimelineEntry {
  let date: Date
  let videos: [[String: String]]
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> RecentEntry {
    RecentEntry(date: Date(), videos: [])
  }

  func getSnapshot(in context: Context, completion: @escaping (RecentEntry) -> Void) {
    completion(makeEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    completion(Timeline(entries: [makeEntry()], policy: .atEnd))
  }

  private func makeEntry() -> RecentEntry {
    var videos: [[String: String]] = []
    if let raw = UserDefaults(suiteName: widgetGroupId)?.string(forKey: "recent"),
       let data = raw.data(using: .utf8),
       let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
      videos = Array(decoded.prefix(3))
    }
    return RecentEntry(date: Date(), videos: videos)
  }
}

struct MrPlayRecentWidgetView: View {
  let entry: Provider.Entry

  var body: some View {
    content
      .widgetURL(fallbackUrl)
      .widgetBackground()
  }

  @ViewBuilder
  private var content: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Image(systemName: "play.rectangle.fill")
          .font(.caption)
        Text("MrPlay")
          .font(.caption)
          .bold()
      }
      .foregroundColor(.secondary)

      if entry.videos.isEmpty {
        Spacer()
        Text("Watch a video to see it here")
          .font(.caption2)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
        Spacer()
      } else {
        ForEach(Array(entry.videos.enumerated()), id: \.offset) { _, video in
          HStack(spacing: 6) {
            Image(systemName: "play.circle.fill")
              .font(.system(size: 12))
              .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 1) {
              Text(video["title"] ?? "")
                .font(.caption)
                .lineLimit(1)
              Text(video["platform"] ?? "")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
          }
          .foregroundColor(.primary)
          .widgetURL(url(for: video))
        }
        Spacer(minLength: 0)
      }
    }
    .padding(8)
  }

  private var fallbackUrl: URL? {
    guard let first = entry.videos.first else { return nil }
    return url(for: first)
  }

  private func url(for video: [String: String]) -> URL? {
    guard let urlString = video["url"]?
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
    return URL(string: "mrplay://open?url=\(urlString)&homeWidget")
  }
}

@main
struct MrPlayRecentWidget: Widget {
  let kind: String = "MrPlayRecentWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      MrPlayRecentWidgetView(entry: entry)
    }
    .configurationDisplayName("MrPlay Recent")
    .description("Your recently watched videos, one tap away.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

private extension View {
  @ViewBuilder
  func widgetBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) {
        Color.black
      }
    } else {
      background(Color.black)
    }
  }
}
