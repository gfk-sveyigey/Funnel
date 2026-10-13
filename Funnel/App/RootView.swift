import SwiftUI

struct RootView: View {

    var body: some View {
        TabView {
            Tab("浏览", systemImage: "link") {
                NavigationStack { BrowserView() }
            }
            Tab("任务", systemImage: "arrow.down.circle") {
                NavigationStack { TaskListView() }
            }
            Tab("设置", systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
            Tab("日志", systemImage: "doc.text.magnifyingglass") {
                NavigationStack { LogsView() }
            }
        }
    }
}
