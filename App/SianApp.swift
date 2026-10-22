import SwiftUI
import AVFoundation
import ReplayKit

@main
struct SianApp: App {
    @StateObject private var model = GameModel()
    init() {
        // PiP needs an active playback audio session; mix so the game's sound keeps playing.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model).preferredColorScheme(.dark) }
    }
}

enum Theme {
    static let bg = Color(red: 0.055, green: 0.078, blue: 0.141)       // deep navy
    static let panel = Color(red: 0.090, green: 0.125, blue: 0.212)
    static let panel2 = Color(red: 0.125, green: 0.165, blue: 0.267)
    static let gold = Color(red: 0.949, green: 0.757, blue: 0.306)
    static let ink = Color(red: 0.925, green: 0.937, blue: 0.965)
    static let muted = Color(red: 0.588, green: 0.627, blue: 0.722)
    static let live = Color(red: 0.302, green: 0.851, blue: 0.561)
}

struct GameInfo: Identifiable {
    let kind: GameKind
    let name: String
    let place: String
    let icon: String
    var id: Int { kind.rawValue }
}

struct ContentView: View {
    @EnvironmentObject var model: GameModel
    @State private var picker = BroadcastPicker.make()
    @State private var showSettings = false

    private let games = [
        GameInfo(kind: .reversi, name: "Reversi", place: "WePlay", icon: "circle.lefthalf.filled"),
        GameInfo(kind: .checkers, name: "หมากฮอส", place: "WePlay", icon: "crown.fill"),
        GameInfo(kind: .connect4, name: "เรียง 4", place: "Plato", icon: "circle.grid.3x3.fill"),
        GameInfo(kind: .connect5, name: "เรียง 5", place: "Plato", icon: "circle.grid.3x3.circle.fill"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                PiPHost(model: model)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(model.linked ? Theme.gold.opacity(0.6) : Color.clear, lineWidth: 1.5))
                startButton
                gameGrid
                tips
                settings
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
        .background(PickerHolder(picker: picker).frame(width: 1, height: 1).opacity(0.01))
        .foregroundColor(Theme.ink)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "crown.fill").font(.title2).foregroundColor(Theme.gold)
            Text("เซียน").font(.system(size: 30, weight: .heavy))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(model.linked ? Theme.live : Theme.muted.opacity(0.5)).frame(width: 9, height: 9)
                Text(model.linked ? "กำลังอ่านจอ" : "ยังไม่เริ่ม").font(.footnote.weight(.semibold))
                    .foregroundColor(model.linked ? Theme.live : Theme.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.panel).clipShape(Capsule())
        }
    }

    private var startButton: some View {
        Button {
            if !model.pipOn { model.togglePiP() }
            for v in picker.subviews { if let b = v as? UIButton { b.sendActions(for: .allTouchEvents) } }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: model.linked ? "stop.circle.fill" : "play.circle.fill").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.linked ? "หยุดอ่านจอ" : "เริ่มใช้งาน").font(.headline)
                    Text(model.linked ? "แตะแล้วกด Stop Broadcast" : "เปิดหน้าต่างลอย แล้วกด Start Broadcast")
                        .font(.caption).opacity(0.75)
                }
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(model.linked ? Theme.panel2 : Theme.gold)
            .foregroundColor(model.linked ? Theme.ink : Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var gameGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("เกมที่รองรับ").font(.subheadline.weight(.semibold)).foregroundColor(Theme.muted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(games) { g in
                    let on = model.linked && model.activeGame == g.kind
                    HStack(spacing: 10) {
                        Image(systemName: g.icon).font(.title3)
                            .foregroundColor(on ? Color.black : Theme.gold)
                            .frame(width: 36, height: 36)
                            .background(on ? Theme.gold : Theme.panel2).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(g.name).font(.subheadline.weight(.bold))
                            Text(on ? "กำลังเล่น" : g.place).font(.caption).foregroundColor(on ? Theme.gold : Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Theme.gold : Color.clear, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("วิธีใช้").font(.subheadline.weight(.semibold)).foregroundColor(Theme.muted)
            Group {
                Label("กด เริ่มใช้งาน → Start Broadcast แล้วเข้าเกม แอปรู้เองว่าเล่นเกมไหน", systemImage: "1.circle")
                Label("บีบหน้าต่างลอยให้เล็ก แล้ววางใต้กระดาน อย่าบังกระดานหรือรูปโปรไฟล์", systemImage: "2.circle")
                Label("ฮอส: เส้นเขียวคือทางเดิน กากบาทคือตัวที่กิน · เรียง 4/5: ลูกศรทองชี้ช่องที่หยอด", systemImage: "3.circle")
            }
            .font(.footnote)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation { showSettings.toggle() } } label: {
                HStack {
                    Text("ตั้งค่า").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: showSettings ? "chevron.up" : "chevron.down")
                }.foregroundColor(Theme.muted)
            }
            if showSettings {
                Text("เวลาคิดต่อตา").font(.footnote).foregroundColor(Theme.muted)
                Picker("เวลา", selection: $model.thinkMs) {
                    Text("0.5 วิ").tag(500); Text("1 วิ").tag(1000); Text("2 วิ").tag(2000)
                }.pickerStyle(.segmented)
                Text("สีของคุณใน Reversi").font(.footnote).foregroundColor(Theme.muted)
                Picker("สี", selection: Binding(get: { model.me }, set: { model.setMe($0) })) {
                    Text("อ่านเอง").tag(0); Text("ดำ").tag(1); Text("ขาว").tag(2)
                }.pickerStyle(.segmented)
                Button { model.togglePiP() } label: {
                    Label(model.pipOn ? "ปิดหน้าต่างลอย" : "เปิดหน้าต่างลอย", systemImage: "pip")
                        .font(.footnote.weight(.semibold))
                }
                Text(model.debug).font(.caption2.monospaced()).foregroundColor(Theme.muted)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct PiPHost: UIViewRepresentable {
    let model: GameModel
    func makeUIView(context: Context) -> PiPHostView { PiPHostView(layer: model.pip.layer) }
    func updateUIView(_ uiView: PiPHostView, context: Context) {}
}

/// The system screen-broadcast sheet, with our extension preselected.
enum BroadcastPicker {
    static func make() -> RPSystemBroadcastPickerView {
        let p = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        p.showsMicrophoneButton = false
        if let url = Bundle.main.builtInPlugInsURL,
           let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
           let ext = items.first(where: { $0.pathExtension == "appex" }),
           let id = Bundle(url: ext)?.bundleIdentifier {
            p.preferredExtension = id
        }
        return p
    }
}

private struct PickerHolder: UIViewRepresentable {
    let picker: RPSystemBroadcastPickerView
    func makeUIView(context: Context) -> UIView { let v = UIView(); v.addSubview(picker); return v }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
