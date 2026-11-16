import SwiftUI
import CairnChatDomain

/// Cairn's visual identity: a slate trail-marker palette and a mark drawn in code.
/// The mark is three stacked stones — it is the app's logo, drawn here rather than
/// shipped as a bitmap, so there is no third-party asset involved at any point.
public enum CairnTheme {
    public static let slate = Color(red: 0.10, green: 0.12, blue: 0.15)
    public static let slateDeep = Color(red: 0.07, green: 0.08, blue: 0.10)
    public static let stone = Color(red: 0.24, green: 0.27, blue: 0.31)
    public static let stoneLight = Color(red: 0.62, green: 0.66, blue: 0.70)
    public static let amber = Color(red: 0.95, green: 0.69, blue: 0.28)
    public static let moss = Color(red: 0.49, green: 0.68, blue: 0.55)
    public static let rust = Color(red: 0.85, green: 0.42, blue: 0.35)
}

public struct CairnMark: View {
    private var tint: Color

    public init(tint: Color = CairnTheme.amber) {
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                stone(width: w * 0.92, height: h * 0.24, yOffset: h * 0.34, tilt: -4)
                stone(width: w * 0.70, height: h * 0.22, yOffset: h * 0.08, tilt: 3)
                stone(width: w * 0.46, height: h * 0.20, yOffset: -h * 0.16, tilt: -2)
                stone(width: w * 0.24, height: h * 0.16, yOffset: -h * 0.36, tilt: 6)
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func stone(width: CGFloat, height: CGFloat, yOffset: CGFloat, tilt: Double) -> some View {
        Capsule()
            .fill(tint.gradient)
            .frame(width: width, height: height)
            .rotationEffect(.degrees(tilt))
            .offset(y: yOffset)
    }
}

/// Where a turn actually went. Always visible: the user should never have to guess
/// whether their words left the device.
public struct NetworkBadge: View {
    private var networkClass: NetworkClass

    public init(networkClass: NetworkClass) {
        self.networkClass = networkClass
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(label)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.18)))
        .foregroundStyle(color)
    }

    private var symbol: String {
        switch networkClass {
        case .onDevice: return "lock.shield.fill"
        case .privateLan: return "localNetwork"
        case .privateVPN: return "point.3.connected.trianglepath.dotted"
        case .publicInternet: return "globe"
        }
    }

    private var label: String {
        switch networkClass {
        case .onDevice: return "On device"
        case .privateLan: return "LAN"
        case .privateVPN: return "VPN"
        case .publicInternet: return "Internet"
        }
    }

    private var color: Color {
        switch networkClass {
        case .onDevice: return CairnTheme.moss
        case .privateLan: return CairnTheme.amber
        case .privateVPN: return CairnTheme.stoneLight
        case .publicInternet: return CairnTheme.rust
        }
    }
}

/// A profile whose traffic reaches the server unencrypted. Plaintext is permitted on a
/// private network, so this is a warning rather than an error — but it is never hidden,
/// so the user can always see whether a prompt leaves the device in the clear.
public struct PlaintextBadge: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.open.fill")
            Text("Plaintext")
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(CairnTheme.amber.opacity(0.18)))
        .foregroundStyle(CairnTheme.amber)
        .accessibilityLabel("Unencrypted connection")
    }
}

/// Phase pill + live tok/s, shown only while a turn is in flight.
public struct StreamingStatusView: View {
    private var phase: GenerationPhase
    private var tokensPerSecond: Double?

    public init(phase: GenerationPhase, tokensPerSecond: Double?) {
        self.phase = phase
        self.tokensPerSecond = tokensPerSecond
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(CairnTheme.amber).frame(width: 6, height: 6)
            Text(title)
            if let rate = tokensPerSecond {
                Text(String(format: "%.1f tok/s", rate))
                    .monospacedDigit()
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(CairnTheme.stoneLight)
    }

    private var title: String {
        switch phase {
        case .idle: return "idle"
        case .preparing: return "preparing"
        case .thinking: return "reasoning"
        case .streaming: return "streaming"
        case .cancelling: return "stopping"
        case .completed: return "done"
        case .cancelled: return "stopped"
        case .failed: return "failed"
        }
    }
}
