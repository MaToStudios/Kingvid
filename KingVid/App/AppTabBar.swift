import SwiftUI

/// KingVid's bottom navigation: Home, YouTube, Browser, Library, Settings.
struct AppTabBar: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppSection.allCases) { section in
                let selected = app.section == section
                Button {
                    if !selected {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        app.section = section
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 21, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(selected ? AnyShapeStyle(Theme.goldGradientVertical) : AnyShapeStyle(Theme.textTertiary))
                            .scaleEffect(selected ? 1.08 : 1)
                        Text(section.title)
                            .font(Theme.ui(10, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Theme.textTertiary))
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .background(
            Theme.surface
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(LinearGradient(colors: [Theme.gold.opacity(0), Theme.gold.opacity(0.5), Theme.gold.opacity(0)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
