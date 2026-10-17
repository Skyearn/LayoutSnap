import SwiftUI

/// 设置里的「快捷键」标签页：所有快捷键都在这里集中设置
struct ShortcutsSettingsView: View {

    @ObservedObject var store: LayoutStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AppController

    var body: some View {
        Form {
            Section("功能快捷键") {
                ForEach(AppAction.allCases) { action in
                    HotKeyRow(title: action.title,
                              detail: action.detail,
                              symbol: action.symbol,
                              spec: settings.hotKey(for: action),
                              onChange: { controller.setHotKey($0, for: action) })
                }
                Text("点右边的按钮，然后按下想用的组合键（必须带 ⌘ / ⌃ / ⌥ / ⇧ 至少一个）。Esc 取消录制，Delete 清除。同一个组合键只能绑一个功能。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("布局快捷键") {
                if store.layouts.isEmpty {
                    Text("还没有保存过布局")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.layouts) { layout in
                        HotKeyRow(title: layout.displayName,
                                  detail: "\(layout.windows.count) 个窗口 · \(layout.appSummary)",
                                  symbol: "rectangle.3.group",
                                  spec: layout.hotKey,
                                  onChange: { controller.setHotKey($0, for: layout) })
                    }
                }
                Text("每个布局可以单独绑一个快捷键，方便直接恢复那一个。默认不设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
