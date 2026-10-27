#if canImport(SwiftUI)
import AppKit
import SpiderBoard
import SpiderCore
import SwiftUI

/// Spider Solitaire ▸ Settings… (⌘,): a toolbar-style tabbed window like System Settings panes
/// in other Mac apps. As usual on the Mac, every change applies at once (no OK / Cancel).
enum SettingsTab: String, CaseIterable {
    case general, gameplay, appearance, credits

    var title: String {
        switch self {
        case .general: return "General"
        case .gameplay: return "Gameplay"
        case .appearance: return "Appearance"
        case .credits: return "Credits"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .gameplay: return "suit.heart.fill"
        case .appearance: return "paintpalette"
        case .credits: return "rosette"
        }
    }
}

/// Hosts one SwiftUI view per tab and resizes the window to each tab's content, keeping the
/// top edge in place, as Mac settings windows do.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    init(model: GameModel, updates: UpdateController) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = NSTabViewController.TabStyle.toolbar
        transitionOptions = [NSViewController.TransitionOptions.crossfade, NSViewController.TransitionOptions.allowUserInteraction]
        for tab in SettingsTab.allCases {
            let root: AnyView
            switch tab {
            case .general: root = AnyView(GeneralSettingsView(model: model, updates: updates))
            case .gameplay: root = AnyView(GameplaySettingsView(model: model))
            case .appearance: root = AnyView(AppearanceSettingsView(model: model))
            case .credits: root = AnyView(CreditsSettingsView())
            }
            let controller: NSHostingController<AnyView> = NSHostingController<AnyView>(rootView: root)
            controller.sizingOptions = [NSHostingSizingOptions.preferredContentSize]
            controller.title = tab.title
            let item: NSTabViewItem = NSTabViewItem(viewController: controller)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.identifier = tab.rawValue
            addTabViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let view: NSView = tabViewItem?.viewController?.view, let window: NSWindow = view.window else { return }
        let content: NSSize = view.fittingSize
        let frame: NSRect = window.frameRect(forContentRect: NSRect(origin: NSPoint.zero, size: content))
        var target: NSRect = window.frame
        target.origin.y += target.height - frame.height
        target.size = frame.size
        let animate: Bool = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(target, display: true, animate: animate)
    }
}

/// Shared pieces: the felt colour accent, binding helper, and a toggle with a short description.
enum SettingsStyle {
    static let width: CGFloat = 520
    static let accent: Color = BoardView.felt
}

@MainActor
func optionBinding<Value>(_ model: GameModel, _ keyPath: WritableKeyPath<Options, Value>) -> Binding<Value> {
    Binding<Value>(
        get: { model.options[keyPath: keyPath] },
        set: { (value: Value) in
            var options: Options = model.options
            options[keyPath: keyPath] = value
            model.applyOptions(options)
        }
    )
}

struct DescribedToggle: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: HorizontalAlignment.leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(Font.callout)
                        .foregroundColor(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundColor(SettingsStyle.accent)
            }
        }
        .toggleStyle(SwitchToggleStyle())
        .tint(SettingsStyle.accent)
    }
}

struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form {
            content()
        }
        .formStyle(GroupedFormStyle())
        .tint(SettingsStyle.accent)
        .frame(width: SettingsStyle.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var model: GameModel
    @ObservedObject var updates: UpdateController

    var body: some View {
        SettingsPane {
            Section("When you quit with a game in progress") {
                Picker("When you quit", selection: optionBinding(model, \Options.saveOnExit)) {
                    Text("Save it and pick up where you left off").tag(ExitSavePolicy.always)
                    Text("Don't save it (it counts as a loss)").tag(ExitSavePolicy.never)
                    Text("Ask me each time").tag(ExitSavePolicy.prompt)
                }
                .pickerStyle(RadioGroupPickerStyle())
                .labelsHidden()
            }
            Section("When the app opens") {
                Picker("When the app opens", selection: optionBinding(model, \Options.openOnStart)) {
                    Text("Open the saved game").tag(StartOpenPolicy.always)
                    Text("Start a new game").tag(StartOpenPolicy.never)
                    Text("Ask me each time").tag(StartOpenPolicy.prompt)
                }
                .pickerStyle(RadioGroupPickerStyle())
                .labelsHidden()
            }
            Section {
                DescribedToggle(title: "Play sounds",
                                detail: "Soft macOS sounds when you deal, drop a card, finish a suit or win.",
                                symbol: "speaker.wave.2.fill",
                                isOn: optionBinding(model, \Options.soundsEnabled))
            }
            Section {
                DescribedToggle(title: "Check for updates automatically",
                                detail: "Once a day at launch. You only hear about it when a new version is out.",
                                symbol: "arrow.triangle.2.circlepath",
                                isOn: optionBinding(model, \Options.checkForUpdatesAutomatically))
                HStack {
                    Text("Version \(UpdateController.currentVersion ?? "development build")")
                        .foregroundColor(Color.secondary)
                    Spacer()
                    Button("Check Now") { updates.check(userInitiated: true) }
                }
            }
        }
    }
}

// MARK: - Gameplay

struct GameplaySettingsView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        SettingsPane {
            Section {
                DescribedToggle(title: "Only deal winnable games",
                                detail: "Every new game is one a built-in solver has already won. Four suits can take a few seconds to deal.",
                                symbol: "checkmark.seal.fill",
                                isOn: optionBinding(model, \Options.winnableDealsOnly))
            }
            Section("Undo") {
                Picker("Undo", selection: optionBinding(model, \Options.undoPolicy)) {
                    VStack(alignment: HorizontalAlignment.leading, spacing: 2) {
                        Text("Unlimited")
                        Text("Go all the way back to the start of the game.")
                            .font(Font.callout).foregroundColor(Color.secondary)
                    }
                    .tag(UndoPolicy.unlimited)
                    VStack(alignment: HorizontalAlignment.leading, spacing: 2) {
                        Text("Classic XP")
                        Text("Undo stops at each deal and each completed suit, like the original.")
                            .font(Font.callout).foregroundColor(Color.secondary)
                    }
                    .tag(UndoPolicy.xpClassic)
                }
                .pickerStyle(RadioGroupPickerStyle())
                .labelsHidden()
            }
            Section {
                Label {
                    Text("Change the number of suits from Game ▸ Difficulty: one suit is gentle, four is a real challenge.")
                        .font(Font.callout)
                        .foregroundColor(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb.fill").foregroundColor(CardStyle.gold)
                }
            }
        }
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        SettingsPane {
            Section("Card faces") {
                HStack(spacing: 14) {
                    FaceStyleTile(style: CardFaceStyle.classic, title: "Classic",
                                  detail: "Traditional English pattern art",
                                  selection: optionBinding(model, \Options.cardFaces))
                    FaceStyleTile(style: CardFaceStyle.simple, title: "Simple",
                                  detail: "Clean, drawn by the app",
                                  selection: optionBinding(model, \Options.cardFaces))
                }
                .padding(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            Section("Card back") {
                HStack(spacing: 16) {
                    CardBackPreview()
                    VStack(alignment: HorizontalAlignment.leading, spacing: 4) {
                        Text("Gold rosette")
                        Text("A gold rosette on deep blue, drawn at any size so it stays sharp.")
                            .font(Font.callout)
                            .foregroundColor(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Section {
                DescribedToggle(title: "Show animations",
                                detail: "Cards glide into place and the XP style celebration plays when you win.",
                                symbol: "sparkles",
                                isOn: optionBinding(model, \Options.animationsEnabled))
            }
        }
    }
}

/// A selectable tile with three small cards fanned out, drawn with that face style.
struct FaceStyleTile: View {
    let style: CardFaceStyle
    let title: String
    let detail: String
    @Binding var selection: CardFaceStyle
    @State private var hovering: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    private var isSelected: Bool { selection == style }

    private static let cards: [Card] = [
        Card(id: 0, suit: Suit.spades, rank: Rank.king, isFaceUp: true),
        Card(id: 1, suit: Suit.hearts, rank: Rank.queen, isFaceUp: true),
        Card(id: 2, suit: Suit.spades, rank: Rank.ace, isFaceUp: true),
    ]

    var body: some View {
        Button {
            selection = style
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(BoardView.felt)
                    ForEach(Array(FaceStyleTile.cards.enumerated()), id: \.offset) { (item: (offset: Int, element: Card)) in
                        CardView(card: item.element, size: CGSize(width: 54, height: 73))
                            .shadow(color: Color.black.opacity(0.3), radius: 2, x: 1, y: 2)
                            .rotationEffect(Angle.degrees(fanAngle(item.offset)), anchor: UnitPoint.bottom)
                            .offset(x: CGFloat(item.offset - 1) * (spread ? 26 : 18), y: 0)
                    }
                }
                .frame(width: 200, height: 112)
                .environment(\.cardFaceStyle, style)
                VStack(spacing: 2) {
                    Text(title).font(Font.headline)
                    Text(detail).font(Font.caption).foregroundColor(Color.secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? SettingsStyle.accent : Color.primary.opacity(0.1), lineWidth: isSelected ? 3 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { (inside: Bool) in hovering = inside }
        .animation(reduceMotion ? nil : Animation.spring(response: 0.35, dampingFraction: 0.7), value: spread)
        .animation(Animation.easeOut(duration: 0.2), value: isSelected)
        .accessibilityLabel(Text(title + " card faces"))
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : [])
    }

    private var spread: Bool { isSelected || hovering }

    private func fanAngle(_ index: Int) -> Double {
        Double(index - 1) * (spread ? 12 : 7)
    }
}

struct CardBackPreview: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(BoardView.felt)
            CardBackView(size: CGSize(width: 54, height: 73))
                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 1, y: 2)
        }
        .frame(width: 84, height: 96)
        .accessibilityHidden(true)
    }
}

// MARK: - Credits

struct CreditsSettingsView: View {
    var body: some View {
        SettingsPane {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: HorizontalAlignment.leading, spacing: 2) {
                        Text("Spider Solitaire").font(Font.title3.weight(Font.Weight.semibold))
                        Text("Version \(UpdateController.currentVersion ?? "development build")")
                            .foregroundColor(Color.secondary)
                    }
                }
            }
            ForEach(Credits.all, id: \.title) { (credit: Credit) in
                Section(credit.title) {
                    Text(credit.detail)
                        .fixedSize(horizontal: false, vertical: true)
                    if !credit.links.isEmpty {
                        HStack(spacing: 14) {
                            ForEach(credit.links, id: \.url) { (link: Credit.Link) in
                                if let url: URL = URL(string: link.url) {
                                    Link(link.title, destination: url)
                                        .font(Font.callout)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
