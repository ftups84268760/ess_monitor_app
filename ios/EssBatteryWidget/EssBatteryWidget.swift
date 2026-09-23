import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        // 加入預設的 isCharging: false
        SimpleEntry(date: Date(), soc: 100, deviceName: "載入中...", isCharging: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(
            date: Date(),
            soc: getSocFromAppGroup(),
            deviceName: getDeviceNameFromAppGroup(),
            isCharging: getIsChargingFromAppGroup()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        // 取得當前的資料，包含充電狀態
        let entry = SimpleEntry(
            date: Date(),
            soc: getSocFromAppGroup(),
            deviceName: getDeviceNameFromAppGroup(),
            isCharging: getIsChargingFromAppGroup()
        )
        
        // 🎯 要求 iOS 系統每隔 15 分鐘自動刷新一次小工具
        let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
        completion(timeline)
    }
    
    // 從 App Group 讀取電量
    func getSocFromAppGroup() -> Int {
        let sharedDefaults = UserDefaults(suiteName: "group.com.flighttechnic.ftess")
        return sharedDefaults?.integer(forKey: "battery_soc") ?? 0
    }
    
    // 從 App Group 讀取設備名稱
    func getDeviceNameFromAppGroup() -> String {
        let sharedDefaults = UserDefaults(suiteName: "group.com.flighttechnic.ftess")
        return sharedDefaults?.string(forKey: "device_name") ?? "未知設備"
    }
    
    // 🎯 新增：從 App Group 讀取充電狀態
    func getIsChargingFromAppGroup() -> Bool {
        let sharedDefaults = UserDefaults(suiteName: "group.com.flighttechnic.ftess")
        return sharedDefaults?.bool(forKey: "is_charging") ?? false
    }
}

// 🎯 新增 isCharging 屬性
struct SimpleEntry: TimelineEntry {
    let date: Date
    let soc: Int
    let deviceName: String
    let isCharging: Bool
}

// 🎯 讀取外部圖檔作為遮罩的動態電池
struct GradientBatteryIcon: View {
    var soc: Int
    var isCharging: Bool // 接收充電狀態

    var body: some View {
        // 1. 用一張隱藏的原始圖片，負責撐開並鎖定真實的長寬比例
        Image("device_mask_icon")
            .resizable()
            .scaledToFit()
            .opacity(0) // 完全透明，僅作為排版骨架
            .overlay(
                // 2. 在撐開的骨架上疊加內容
                GeometryReader { geometry in
                    let height = geometry.size.height
                    // 確保極低電量時仍有微小高度顯示
                    let fillHeight = max(height * (CGFloat(soc) / 100.0), height * 0.05)
                    let gradientColors: [Color] = soc <= 20 ? [.red, .orange] : [.green, .cyan]

                    ZStack(alignment: .bottom) {
                        // 3. 填滿整個骨架的底槽色
                        Color.black.opacity(0.15)

                        // 4. 動態高度漸層液體
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .frame(height: fillHeight)
                    }
                    // 5. 將這個與骨架等大的 ZStack，套上同等尺寸的圖片遮罩
                    .mask(
                        Image("device_mask_icon")
                            .resizable()
                            .scaledToFit()
                    )
                    // 6. 🎯 新增疊加閃電圖示
                    .overlay(
                        Group {
                            if isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    // 加上微陰影，讓白色閃電在淺色漸層上依然清晰
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

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                // 1. 鎖定畫面的圓形進度條
                Gauge(value: Double(entry.soc), in: 0...100) {
                    // 若正在充電，可切換鎖定畫面圖示 (選用)
                    Image(systemName: entry.isCharging ? "bolt.fill" : "bolt.batteryblock.fill")
                } currentValueLabel: {
                    Text("\(entry.soc)%")
                }
                .gaugeStyle(.accessoryCircular)
                .tint(entry.soc <= 20 ? .red : .teal)
                
            case .systemMedium:
                // 2. 桌面中型尺寸 (橫向長方塊)
                HStack(spacing: 16) {
                    // 傳入 isCharging 參數
                    GradientBatteryIcon(soc: entry.soc, isCharging: entry.isCharging)
                        .frame(width: 44, height: 44)
                        .shadow(color: .white.opacity(0.8), radius: 2, x: 0, y: 1)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.deviceName)
                            .font(.headline)
                            .foregroundColor(.black.opacity(0.85)) // 強制深黑色
                            .lineLimit(1)
                        
                        HStack {
                            Text("目前電量")
                                .font(.subheadline)
                                .foregroundColor(.black.opacity(0.6)) // 深灰色
                            Spacer()
                            Text("\(entry.soc)%")
                                .font(.title3)
                                .bold()
                                .foregroundColor(.black) // 強制純黑色
                        }
                        
                        ProgressView(value: Double(entry.soc), total: 100)
                            .tint(entry.soc <= 20 ? .red : .teal)
                            // 為進度條底槽加上微透明的深色，避免在白底背景上看不見
                            .background(Color.black.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding()
                
            default:
                // 3. 桌面小型尺寸 (正方塊)
                VStack {
                    // 傳入 isCharging 參數
                    GradientBatteryIcon(soc: entry.soc, isCharging: entry.isCharging)
                        .frame(width: 50, height: 50)
                        .padding(.bottom, 2)
                        .shadow(color: .white.opacity(0.8), radius: 2, x: 0, y: 1)
                    
                    Text(entry.deviceName)
                        .font(.caption2)
                        .foregroundColor(.black.opacity(0.6)) // 深灰色
                        .lineLimit(1)
                        
                    Text("\(entry.soc)%")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.black) // 強制純黑色
                }
            }
        }
        // 滿足 iOS 17 的背景規範要求
        .containerBackground(for: .widget) {
            switch family {
            case .systemMedium:
                // 中型尺寸 (橫向)：讀取完整的機台渲染圖
                Image("device_render_full")
                    .resizable()
                    .scaledToFill()
                                
            case .systemSmall:
                // 小型尺寸 (正方)：讀取局部的機台特寫圖
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
    // 此處的 kind 必須與 Flutter 端 updateWidget 的 iOSName 一致
    let kind: String = "EssBatteryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            EssBatteryWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("FTESS 電量監控")
        .description("隨時查看您的IFS儲能設備當前電量")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}
