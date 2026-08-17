import SwiftUI

/// Палитра INTR. — брутализм/гранж/минимализм.
enum INTR {
    static let background = Color(hex: 0xE8E5DC)     // тёплый dirty white
    static let text = Color(hex: 0x11110F)           // почти чёрный
    static let graphite = Color(hex: 0x242421)       // вторичный фон
    static let lime = Color(hex: 0xB7FF00)           // кислотный лайм
    static let red = Color(hex: 0xD83A32)            // грязный красный
    static let concrete = Color(hex: 0x85837B)       // бетонный серый

    static let border: Color = INTR.text.opacity(0.9)

    static let fontDisplay = Font.system(.largeTitle, design: .default).weight(.black)
    static let fontHeader = Font.system(.headline, design: .default).weight(.black)
    static let fontBody = Font.system(.body, design: .rounded)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Бруталистская кнопка: жёсткие границы, без скруглений, жирный текст.
struct INTRButtonStyle: ButtonStyle {
    var filled: Bool = false
    var accent: Color = INTR.lime

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .default).weight(.bold))
            .foregroundColor(filled ? INTR.text : INTR.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(filled ? accent : Color.clear)
            .overlay(
                Rectangle().stroke(INTR.border, lineWidth: 2)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Бруталистская карточка/поле: квадратные углы, толстая рамка, никакого теней.
struct INTRBox<Content: View>: View {
    let fill: Color
    @ViewBuilder let content: Content

    init(_ fill: Color = .clear, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        content
            .background(fill)
            .overlay(Rectangle().stroke(INTR.border, lineWidth: 2))
    }
}
