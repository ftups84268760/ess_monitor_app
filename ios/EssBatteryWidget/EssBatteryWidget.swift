import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), soc: 100, deviceName: "載入中...", isCharging: false, lastUpdate: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(
            date: Date(),
            soc: getSocFromAppGroup(),
            deviceName: getDeviceNameFromAppGroup(),
            isCharging: getIsChargingFromAppGroup(),
            lastUpdate: getLastUpdateFromAppGroup()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = SimpleEntry(
            date: Date(),
            soc: getSocFromAppGroup(),
            deviceName: getDeviceNameFromAppGroup(),
            isCharging: getIsChargingFromAppGroup(),
            lastUpdate: getLastUpdateFromAppGroup()
        )
        
        // 保底機制：即使沒有推播，也要求 iOS 每 15 分鐘盡量更新一次
        let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
        completion(timeline)
    }
    
    func getSocFromAppGroup() -> Int {
        let sharedDefaults = UserDefaults(suiteName: "group.com.flighttechnic.ftess")
        return sharedDefaults?.integer(forKey: "battery_soc") ?? 0
    }
    
    func getDeviceNameFromAppGroup() -> String {
        let sharedDefaults = UserDefaults(suiteName: "group.com.flighttechnic.ftess")
        return sharedDefaults?.string(forKey: "device_name") ?? "未知設備"
    }
    
    func getIsChargingFromAppGroup() -> Bool {
        let sharedDefaults = UserDefaults(suiteName: "group.com.flighttechnic.ftess")
        return sharedDefaults?.bool(forKey: "is_charging") ?? false
    }
    
    func getLastUpdateFromAppGroup() -> Date {
        let sharedDefaults = UserDefaults(suiteName: "group.com.flighttechnic.ftess")
        let timestamp = sharedDefaults?.double(forKey: "last_update_timestamp") ?? Date().timeIntervalSince1970
        return Date(timeIntervalSince1970: timestamp)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let soc: Int
    let deviceName: String
    let isCharging: Bool
    let lastUpdate: Date
}

struct GradientBatteryIcon: View {
    var soc: Int
    var isCharging: Bool

    var body: some View {
        Image("device_mask_icon")
            .resizable()
            .scaledToFit()
            .opacity(0)
            .overlay(
                GeometryReader { geometry in
                    let height = geometry.size.height
                    let fillHeight = max(height * (CGFloat(soc) / 100.0), height * 0.05)
                    let gradientColors: [Color] = soc <= 20 ? [.red, .orange] : [.green, .cyan]

                    ZStack(alignment: .bottom) {
                        Color.black.opacity(0.15)
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .frame(height: fillHeight)
                    }
                    .mask(
                        Image("device_mask_icon")
                            .resizable()
                            .scaledToFit()
                    )
                    .overlay(
                        Group {
                            if isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            }
                        }
                    )
                }
            )
    }
}

struct EssBatteryWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    private var statusColor: Color {
        if entry.isCharging { return .green }
        if entry.soc <= 20 { return .red }
        return .black.opacity(0.85)
    }

    func timeAgoDisplay(from date: Date) -> String {
        let secondsAgo = Int(Date().timeIntervalSince(date))
        
        if secondsAgo < 60 {
            return "剛剛"
        }
        
        let minutes = secondsAgo / 60
        if minutes < 60 {
            return "\(minutes) 分鐘前"
        }
        
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) 小時前"
        }
        
        let days = hours / 24
        return "\(days) 天前"
    }

    var body: some View {
        Group {
            switch family {
            
            case .accessoryCircular:
                Gauge(value: Double(entry.soc), in: 0...100) {
                    Image(systemName: entry.isCharging ? "bolt.fill" : "bolt.batteryblock.fill")
                } currentValueLabel: {
                    Text("\(entry.soc)%")
                }
                .gaugeStyle(.accessoryCircular)
                .tint(entry.soc <= 20 ? .red : .teal)
                
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "minus.plus.batteryblock.fill")
                            .font(.system(size: 14))
                        if entry.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12))
                        }
                        Text("\(entry.soc)%")
                            .font(.system(size: 14, weight: .bold))
                    }
                                
                    // 🎯 核心修改：將 size 從 12 改為 15，並加上 weight: .medium
                    Text(entry.deviceName)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                                
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.3)) // 底層淺色軌道
                            Capsule()
                                .fill(Color.primary) // 上層實心電量
                                .frame(width: max(geometry.size.width * CGFloat(entry.soc) / 100.0, 0))
                        }
                    }
                    .frame(height: 7)
                    .padding(.top, 2)
                }
                
            case .systemMedium:
                HStack(spacing: 16) {
                    GradientBatteryIcon(soc: entry.soc, isCharging: entry.isCharging)
                        .frame(width: 50, height: 50)
                        .shadow(color: .white.opacity(0.8), radius: 2, x: 0, y: 1)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.deviceName)
                            .font(.headline)
                            .foregroundColor(.black.opacity(0.85))
                            .lineLimit(1)
                        
                        HStack(alignment: .bottom) {
                            Text(entry.isCharging ? "充電中" : "目前電量")
                                .font(.subheadline)
                                .foregroundColor(.black.opacity(0.6))
                            Spacer()
                            Text("\(entry.soc)%")
                                .font(.title2)
                                .bold()
                                .foregroundColor(statusColor)
                        }
                        
                        ProgressView(value: Double(entry.soc), total: 100)
                            .tint(entry.soc <= 20 ? .red : .teal)
                            .background(Color.black.opacity(0.1))
                            .clipShape(Capsule())
                            .padding(.bottom, 2)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 10))
                            Text(timeAgoDisplay(from: entry.lastUpdate))
                        }
                        .font(.caption2)
                        .foregroundColor(.black.opacity(0.5))
                    }
                }
                .padding()
                
            default:
                VStack(spacing: 2) {
                    GradientBatteryIcon(soc: entry.soc, isCharging: entry.isCharging)
                        .frame(width: 55, height: 55)
                        .shadow(color: .white.opacity(0.8), radius: 2, x: 0, y: 1)
                    
                    Text(entry.deviceName)
                        .font(.caption2)
                        .foregroundColor(.black.opacity(0.6))
                        .lineLimit(1)
                        
                    Text("\(entry.soc)%")
                        .font(.title2)
                        .bold()
                        .foregroundColor(statusColor)
                        
                    Text(timeAgoDisplay(from: entry.lastUpdate))
                        .font(.system(size: 9))
                        .foregroundColor(.black.opacity(0.4))
                }
                .padding(.top, 4)
            }
        }
        .containerBackground(for: .widget) {
            switch family {
            case .systemMedium:
                Image("device_render_full")
                    .resizable()
                    .scaledToFill()
                                
            case .systemSmall:
                Image("device_icon_close_up")
                    .resizable()
                    .scaledToFill()
                                
            default:
                Color.clear
            }
        }
    }
}

@main
struct EssBatteryWidget: Widget {
    let kind: String = "EssBatteryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            EssBatteryWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("FTESS 儲能狀態")
        .description("即時監控電池電量與狀態。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
