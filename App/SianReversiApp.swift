import SwiftUI
import AVFoundation
import ReplayKit

@main
struct SianReversiApp: App {
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

struct ContentView: View {
    @EnvironmentObject var model: GameModel
    private let gold = Color(red: 0.957, green: 0.776, blue: 0.310)
    private let panel = Color(red: 0.086, green: 0.125, blue: 0.098)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("เซียน ").font(.title2.bold()) + Text("Reversi").font(.title2.bold()).foregroundColor(gold)
                    Spacer()
                    Circle().fill(model.linked ? Color.green : Color.gray).frame(width: 10, height: 10)
                    Text(model.linked ? "กำลังอ่านจอ" : "ยังไม่อ่านจอ").font(.footnote).foregroundColor(.secondary)
                }

                PiPHost(model: model)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)

                Button { model.togglePiP() } label: {
                    Label(model.pipOn ? "ปิดหน้าต่างลอย" : "1. เปิดหน้าต่างลอย", systemImage: "pip")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .background(model.pipOn ? panel : gold).foregroundColor(model.pipOn ? .white : .black)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                BroadcastButton(title: model.linked ? "หยุด / เริ่มอ่านจอใหม่" : "2. เริ่มอ่านหน้าจอ", gold: gold, panel: panel, active: model.linked)

                Text(model.debug).font(.caption.monospaced()).foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("สีของคุณ").font(.subheadline).foregroundColor(.secondary)
                    Picker("สี", selection: Binding(get: { model.me }, set: { model.setMe($0) })) {
                        Text("อ่านอัตโนมัติ").tag(0); Text("ดำ ⚫").tag(1); Text("ขาว ⚪").tag(2)
                    }.pickerStyle(.segmented)
                    Text("เวลาคิดต่อตา").font(.subheadline).foregroundColor(.secondary)
                    Picker("เวลา", selection: $model.thinkMs) {
                        Text("0.5 วิ").tag(500); Text("1 วิ").tag(1000); Text("2 วิ").tag(2000)
                    }.pickerStyle(.segmented)
                }
                .padding(14).background(panel).clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    Text("วิธีใช้").font(.headline)
                    Text("1. กด เปิดหน้าต่างลอย (ถ้าไม่ขึ้น ปัดกลับหน้าโฮม หน้าต่างจะลอยเอง)")
                    Text("2. กด เริ่มอ่านหน้าจอ แล้วเลือก เซียน Reversi → เริ่มการถ่ายทอด")
                    Text("3. เปิด WePlay เข้าเกม หน้าต่างลอยจะบอกช่องที่ควรลงทุกตา")
                    Text("ช่วงท้ายเกม (ช่องว่าง ≤ 16) AI คำนวณจนจบเกมแบบแม่นยำ").foregroundColor(.secondary)
                }
                .font(.subheadline)
                .padding(14).background(panel).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(16)
        }
        .background(Color(red: 0.055, green: 0.078, blue: 0.067).ignoresSafeArea())
    }
}

struct PiPHost: UIViewRepresentable {
    let model: GameModel
    func makeUIView(context: Context) -> PiPHostView { PiPHostView(layer: model.pip.layer) }
    func updateUIView(_ uiView: PiPHostView, context: Context) {}
}

/// Styled button that opens the system screen-broadcast sheet with our extension preselected.
struct BroadcastButton: View {
    let title: String
    let gold: Color
    let panel: Color
    let active: Bool
    @State private var picker = BroadcastButton.makePicker()

    static func makePicker() -> RPSystemBroadcastPickerView {
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

    var body: some View {
        Button {
            for v in picker.subviews { if let b = v as? UIButton { b.sendActions(for: .allTouchEvents) } }
        } label: {
            Label(title, systemImage: "record.circle")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .background(active ? panel : gold).foregroundColor(active ? .white : .black)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .background(PickerHolder(picker: picker).frame(width: 1, height: 1).opacity(0.01))
    }
}

private struct PickerHolder: UIViewRepresentable {
    let picker: RPSystemBroadcastPickerView
    func makeUIView(context: Context) -> UIView { let v = UIView(); v.addSubview(picker); return v }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
