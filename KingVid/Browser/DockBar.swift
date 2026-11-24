import SwiftUI

/// Bottom navigation dock: back, forward, tabs, library, settings.
struct DockBar: View {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject var browser: BrowserStore
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(spacing: 0) {
            dockButton("chevron.left", enabled: tab.canGoBackEffective) { tab.goBack() }
            dockButton("chevron.right", enabled: tab.canGoForward) { tab.goForward() }

            Button {
                tab.captureSnapshot()
                app.sheet = .tabs
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.goldGradient, lineWidth: 2)
                        .frame(width: 25, height: 25)
                    Text("\(browser.tabs.count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.goldGradient)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle())

            dockButton("books.vertical.fill") { app.sheet = .library }
            dockButton("gearshape.fill") { app.sheet = .settings }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(
            Theme.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(LinearGradient(colors: [Theme.gold.opacity(0.0), Theme.gold.opacity(0.45), Theme.gold.opacity(0.0)],
                                                    startPoint: .leading, endPoint: .trailing))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func dockButton(_ symbol: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(enabled ? AnyShapeStyle(Theme.goldGradientVertical) : AnyShapeStyle(Theme.textTertiary))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconPressStyle())
        .disabled(!enabled)
    }
}
