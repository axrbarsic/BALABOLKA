import SwiftUI

struct ContentView: View {
    @Bindable var model: BalabolkaAppModel

    var body: some View {
        TabView {
            NavigationStack {
                ComposerScreen(model: model)
            }
            .tabItem {
                Label("Создать", systemImage: "wand.and.stars")
            }

            NavigationStack {
                LibraryScreen(model: model)
            }
            .tabItem {
                Label("История", systemImage: "rectangle.stack.fill")
            }
        }
        .tint(AppTheme.accent)
        .background(AppTheme.background)
    }
}

#Preview {
    ContentView(model: BalabolkaAppModel())
}
