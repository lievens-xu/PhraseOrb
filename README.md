# 语句球 · PhraseOrb

适用于 macOS 13 及以上，支持 Apple 芯片和 Intel Mac。原生 AppKit + SwiftUI，无第三方依赖。

## 功能

- 悬浮球置顶显示，鼠标移入展开快捷语句，点击复制。
- 拖动移动位置，自动记住上次位置，支持隐藏和重置。
- 管理窗口支持新增、编辑、删除、搜索、排序和多行内容。
- JSON 导入／导出备份，语句存储在本机。
- 菜单栏和右键菜单提供管理、显示／隐藏及退出入口。

## 界面

<img src="docs/screenshots/menu.png" alt="悬浮菜单" width="360">

<img src="docs/screenshots/editor.png" alt="语句管理窗口" width="830">

## 下载

在[Releases 页面](https://github.com/lievens-xu/PhraseOrb/releases/latest)下载 macOS 应用压缩包，解压后将「语句球.app」拖入「应用程序」。

## 使用

1. 将「语句球.app」拖入「应用程序」，双击启动。
2. 鼠标移入悬浮球，展开快捷语句。点击任意语句，看到「已复制」后，在目标输入框按 ⌘V 粘贴。
3. 按住悬浮球拖动即可移动位置，位置会自动保存。
4. 点击展开菜单的「管理语句…」，或右键悬浮球，新增、编辑、删除、搜索、调整顺序或导入／导出语句。
5. 编辑后点击「保存」或按 ⌘S。关闭窗口后悬浮球继续运行；从菜单栏图标或右键菜单选择「退出」才会退出软件。

悬浮球启动后默认出现在主屏右侧中间，软件不在 Dock 中显示。可以通过菜单栏图标隐藏／显示悬浮球，或重置其位置。

本版本仅把内容复制到剪贴板，不自动发送消息或自动粘贴。应用不需要辅助功能、屏幕录制或网络权限。复制后会替换当前剪贴板内容。

## 语句与备份

语句存储在 `~/Library/Application Support/PhraseOrb/phrases.json`，标题、全文、顺序均保存在本机。多行文字和前后空格按原样复制。首次运行提供 5 条示例语句。

管理窗口的「导出」保存全部已保存语句为 JSON；「导入」合并备份：相同 ID 更新，新的 ID 追加。导入不会因为文件缺少某条语句而删除现有语句。最多支持 2000 条语句。删除需要确认，建议定期导出备份。

若希望开机启动，可在 macOS「系统设置 → 通用 → 登录项」中自行添加应用。

## 本地安装说明

这是本地编译并做临时签名的应用，没有 Apple Developer ID 公证。当前电脑可直接启动；转移到其他 Mac 后，系统可能要求在「系统设置 → 隐私与安全性」中允许打开。

悬浮面板使用系统置顶层级，并支持跨桌面及全屏辅助显示；系统安全界面等特殊窗口仍可能覆盖它。

## 从源码构建

需要 Apple Command Line Tools（`xcode-select --install`）。在源码目录运行：

```sh
./build.sh
```

输出为 `dist/语句球.app`，包含 arm64 和 x86_64 两种架构。重新生成图标可运行：

```sh
xcrun swift make-icon.swift AppIcon.iconset
iconutil -c icns AppIcon.iconset -o AppIcon.icns
./build.sh
```

## 验证

```sh
dist/语句球.app/Contents/MacOS/PhraseOrb --self-test
mkdir -p /tmp/phraseorb-ui-test
dist/语句球.app/Contents/MacOS/PhraseOrb --ui-test --test-dir /tmp/phraseorb-ui-test
```

`--self-test` 使用临时目录测试持久化、增删改、排序、备份校验及屏幕边缘布局。`--ui-test` 启动真实 AppKit 窗口，通过调用界面的事件处理回调验证展开、复制反馈、延迟收起、隐藏与管理窗口，并输出界面 PNG。界面测试使用独立测试剪贴板和数据文件，不覆盖日常语句或系统剪贴板。

界面回调测试不等于真实鼠标操作或所有多显示器／全屏应用场景的验收。1.0 版本已在 Apple 芯片 Mac 上完成 13 项数据与布局测试、9 项界面回调测试，并检查了渲染后的界面。Intel 架构完成交叉编译，未在 Intel 硬件运行。

性能测试与范围说明见 [性能测试记录](docs/performance.md)。

实现参考 Apple 官方说明：[跨应用全屏的窗口行为](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)、[剪贴板写入接口](https://developer.apple.com/documentation/appkit/nspasteboard/setstring(_:fortype:))。
