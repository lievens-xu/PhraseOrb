import AppKit
import SwiftUI

struct Phrase: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
}

enum OrbLayout {
    static let orbSize: CGFloat = 64
    static func clamp(_ origin: NSPoint, to screen: NSRect) -> NSPoint {
        NSPoint(x: min(max(origin.x, screen.minX + 8), screen.maxX - orbSize - 8),
                y: min(max(origin.y, screen.minY + 8), screen.maxY - orbSize - 8))
    }
    static func menuFrame(orb: NSRect, screen: NSRect, height: CGFloat) -> NSRect {
        let width = min(CGFloat(360), screen.width - 24)
        let x = orb.minX - width - 8 >= screen.minX + 8
            ? orb.minX - width - 8 : orb.maxX + 8
        return NSRect(x: min(max(x, screen.minX + 8), screen.maxX - width - 8),
                      y: min(max(orb.maxY - height, screen.minY + 8), screen.maxY - height - 8),
                      width: width, height: height)
    }
}

final class PhraseStore: ObservableObject {
    @Published private(set) var phrases: [Phrase] = []
    @Published var errorMessage: String?
    let fileURL: URL
    var onChange: (() -> Void)?
    static let defaults = [
        Phrase(title: "收到，谢谢", text: "收到，谢谢！我会尽快处理。"),
        Phrase(title: "稍后回复", text: "您好，我现在暂时不方便回复，稍后联系您。"),
        Phrase(title: "跟进进度", text: "您好，想跟进一下这件事目前的进展，方便时请告知，谢谢！"),
        Phrase(title: "会议确认", text: "好的，时间已确认，我会准时参加。"),
        Phrase(title: "发送资料", text: "相关资料已整理好，请查收。如有问题，随时联系我。")
    ]
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhraseOrb/phrases.json")
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            do {
                phrases = try Self.decode(Data(contentsOf: self.fileURL))
            } catch {
                errorMessage = "读取语句失败，原文件已保留。请检查或导入备份。\n\(error.localizedDescription)"
            }
        } else {
            phrases = Self.defaults
            do { try write(phrases) } catch { errorMessage = "无法保存语句：\(error.localizedDescription)" }
        }
    }
    static func decode(_ data: Data) throws -> [Phrase] {
        let result = try JSONDecoder().decode([Phrase].self, from: data)
        guard result.count <= 2000, Set(result.map(\.id)).count == result.count,
              result.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw NSError(domain: "PhraseOrb", code: 1, userInfo: [NSLocalizedDescriptionKey: "语句数据无效：标题和内容不能为空，ID 不能重复，最多支持 2000 条。"])
        }
        return result
    }
    func write(_ next: [Phrase]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(next).write(to: fileURL, options: .atomic)
    }
    @discardableResult func commit(_ next: [Phrase]) -> Bool {
        do {
            _ = try Self.decode(JSONEncoder().encode(next))
            try write(next)
            phrases = next
            onChange?()
            return true
        } catch {
            errorMessage = "保存失败，修改尚未写入。\n\(error.localizedDescription)"
            return false
        }
    }
    @discardableResult func save(id: UUID?, title: String, text: String) -> UUID? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var next = phrases
        let phraseID = id ?? UUID()
        let item = Phrase(id: phraseID, title: title, text: text)
        if let index = next.firstIndex(where: { $0.id == phraseID }) { next[index] = item }
        else { next.append(item) }
        return commit(next) ? phraseID : nil
    }
    func remove(_ id: UUID) { _ = commit(phrases.filter { $0.id != id }) }
    func move(_ id: UUID, by offset: Int) {
        guard let i = phrases.firstIndex(where: { $0.id == id }), phrases.indices.contains(i + offset) else { return }
        var next = phrases
        next.swapAt(i, i + offset)
        _ = commit(next)
    }
    func importFile(_ url: URL) -> Bool {
        do {
            let imported = try Self.decode(Data(contentsOf: url))
            var next = phrases
            for item in imported {
                if let index = next.firstIndex(where: { $0.id == item.id }) { next[index] = item }
                else { next.append(item) }
            }
            return commit(next)
        } catch { errorMessage = "导入失败：\(error.localizedDescription)"; return false }
    }
}

let ink = NSColor(calibratedRed: 0.10, green: 0.17, blue: 0.22, alpha: 1)
let teal = NSColor(calibratedRed: 0.02, green: 0.53, blue: 0.48, alpha: 1)
let muted = NSColor(calibratedRed: 0.43, green: 0.49, blue: 0.51, alpha: 1)

func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, lines: NSLineBreakMode = .byTruncatingTail) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = lines
    (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
}

class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class HoverView: NSView {
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { entered?() }
    override func mouseExited(with event: NSEvent) { exited?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class OrbView: HoverView {
    weak var controller: OrbController?
    var copied = false { didSet { needsDisplay = true } }
    var hovering = false { didSet { needsDisplay = true } }
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var dragging = false
    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: hovering ? 4 : 6, dy: hovering ? 4 : 6)
        let path = NSBezierPath(ovalIn: circle)
        NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.72, blue: 0.64, alpha: 1), ending: teal)!.draw(in: path, angle: -60)
        NSColor.white.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 1
        path.stroke()
        let symbol = NSImage(systemSymbolName: copied ? "checkmark" : "text.bubble.fill", accessibilityDescription: "快捷语句")!
            .withSymbolConfiguration(.init(paletteColors: [.white]))!
        let symbolRect = NSRect(x: 20, y: 20, width: 24, height: 24)
        symbol.draw(in: symbolRect)
    }
    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        dragging = false
        controller?.cancelCollapse()
    }
    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let dx = current.x - startMouse.x, dy = current.y - startMouse.y
        if hypot(dx, dy) > 4 { dragging = true }
        if dragging {
            controller?.isDragging = true
            controller?.collapse()
            window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        }
    }
    override func mouseUp(with event: NSEvent) {
        controller?.isDragging = false
        if dragging { controller?.finishDrag() } else { controller?.expand() }
    }
    override func rightMouseDown(with event: NSEvent) {
        controller?.collapse()
        if let menu = controller?.contextMenu { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

final class PhraseRow: HoverView {
    let phrase: Phrase
    var action: (() -> Void)?
    var selected = false { didSet { needsDisplay = true } }
    var copied = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    init(phrase: Phrase, frame: NSRect) {
        self.phrase = phrase
        super.init(frame: frame)
        entered = { [weak self] in self?.selected = true }
        exited = { [weak self] in self?.selected = false }
        toolTip = phrase.text
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        if selected || copied {
            NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.94, alpha: 1).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 3), xRadius: 10, yRadius: 10).fill()
        }
        drawText(copied ? "已复制 ✓" : phrase.title, in: NSRect(x: 18, y: 12, width: bounds.width - 60, height: 21),
                 font: .systemFont(ofSize: 13, weight: .semibold), color: copied ? teal : ink)
        drawText(phrase.text.replacingOccurrences(of: "\n", with: " "), in: NSRect(x: 18, y: 36, width: bounds.width - 60, height: 18),
                 font: .systemFont(ofSize: 11), color: muted)
        if let icon = NSImage(systemSymbolName: copied ? "checkmark.circle.fill" : "doc.on.doc", accessibilityDescription: "复制") {
            icon.draw(in: NSRect(x: bounds.width - 36, y: 24, width: 16, height: 16))
        }
    }
    override func mouseDown(with event: NSEvent) { action?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

final class MenuView: HoverView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.985, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()
        drawText("快捷语句", in: NSRect(x: 20, y: 18, width: bounds.width - 40, height: 24),
                 font: .systemFont(ofSize: 17, weight: .bold), color: ink)
        drawText("点击复制 · 回到输入框按 ⌘V 粘贴", in: NSRect(x: 20, y: 46, width: bounds.width - 40, height: 18),
                 font: .systemFont(ofSize: 11), color: muted)
        NSColor.separatorColor.setFill()
        NSRect(x: 16, y: bounds.height - 49, width: bounds.width - 32, height: 1).fill()
    }
}

final class OrbController: NSObject {
    let store: PhraseStore
    let orb: PassivePanel
    let menuPanel: PassivePanel
    let orbView: OrbView
    let pasteboard: NSPasteboard
    let positionDefaults: UserDefaults
    var isDragging = false
    var isShown = true
    var openEditor: (() -> Void)?
    var contextMenu: NSMenu?
    var collapseTask: DispatchWorkItem?
    var feedbackTask: DispatchWorkItem?
    var rows: [PhraseRow] = []
    init(store: PhraseStore, pasteboard: NSPasteboard = .general, defaults: UserDefaults = .standard) {
        self.store = store
        self.pasteboard = pasteboard
        self.positionDefaults = defaults
        orb = PassivePanel(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        menuPanel = PassivePanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        orbView = OrbView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        super.init()
        for panel in [orb, menuPanel] {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            if #available(macOS 13.0, *) { panel.collectionBehavior.insert(.canJoinAllApplications) }
            panel.acceptsMouseMovedEvents = true
        }
        orb.contentView = orbView
        orbView.controller = self
        orbView.toolTip = "移入展开 · 拖动移动 · 右键管理"
        orbView.entered = { [weak self] in
            self?.orbView.hovering = true
            self?.expand()
        }
        orbView.exited = { [weak self] in
            self?.orbView.hovering = false
            self?.scheduleCollapse()
        }
        resetPosition(useSaved: true)
        store.onChange = { [weak self] in
            guard let self, self.menuPanel.isVisible else { return }
            self.rebuildMenu()
        }
    }
    var screen: NSScreen { orb.screen ?? NSScreen.main ?? NSScreen.screens[0] }
    func show() { isShown = true; orb.orderFrontRegardless() }
    func hide() { isShown = false; collapse(); orb.orderOut(nil) }
    func resetPosition(useSaved: Bool = false) {
        let main = NSScreen.main ?? NSScreen.screens[0]
        let visible = main.visibleFrame
        var origin = NSPoint(x: visible.maxX - 88, y: visible.midY)
        if useSaved, positionDefaults.object(forKey: "orbX") != nil {
            let saved = NSPoint(x: positionDefaults.double(forKey: "orbX"), y: positionDefaults.double(forKey: "orbY"))
            if let target = NSScreen.screens.first(where: { $0.visibleFrame.contains(NSPoint(x: saved.x + 32, y: saved.y + 32)) }) {
                origin = OrbLayout.clamp(saved, to: target.visibleFrame)
            }
        }
        orb.setFrameOrigin(origin)
        if !useSaved { savePosition() }
    }
    func savePosition() {
        positionDefaults.set(orb.frame.minX, forKey: "orbX")
        positionDefaults.set(orb.frame.minY, forKey: "orbY")
    }
    func finishDrag() {
        let center = NSPoint(x: orb.frame.midX, y: orb.frame.midY)
        let target = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? screen
        orb.setFrameOrigin(OrbLayout.clamp(orb.frame.origin, to: target.visibleFrame))
        savePosition()
    }
    func cancelCollapse() { collapseTask?.cancel(); collapseTask = nil }
    func expand() {
        guard !isDragging, isShown else { return }
        cancelCollapse()
        if !menuPanel.isVisible { rebuildMenu(); menuPanel.orderFrontRegardless() }
    }
    func collapse() { cancelCollapse(); menuPanel.orderOut(nil) }
    func scheduleCollapse() {
        cancelCollapse()
        let task = DispatchWorkItem { [weak self] in self?.collapse() }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30, execute: task)
    }
    @discardableResult func copy(_ phrase: Phrase) -> Bool {
        pasteboard.clearContents()
        guard pasteboard.setString(phrase.text, forType: .string) else {
            NSSound.beep(); return false
        }
        for row in rows { row.copied = row.phrase.id == phrase.id }
        orbView.copied = true
        feedbackTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.orbView.copied = false
            self?.rows.forEach { $0.copied = false }
        }
        feedbackTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
        return true
    }
    func rebuildMenu() {
        let rowHeight: CGFloat = 68
        let available = max(80, screen.visibleFrame.height - 148)
        let listHeight = min(CGFloat(max(1, store.phrases.count)) * rowHeight, min(408, available))
        let height = 80 + listHeight + 49
        let frame = OrbLayout.menuFrame(orb: orb.frame, screen: screen.visibleFrame, height: height)
        menuPanel.setFrame(frame, display: false)
        let root = MenuView(frame: NSRect(origin: .zero, size: frame.size))
        root.appearance = NSAppearance(named: .aqua)
        root.entered = { [weak self] in self?.cancelCollapse() }
        root.exited = { [weak self] in self?.scheduleCollapse() }
        let scroll = NSScrollView(frame: NSRect(x: 6, y: 80, width: frame.width - 12, height: listHeight))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width,
                                               height: max(listHeight, CGFloat(store.phrases.count) * rowHeight)))
        rows = []
        for (i, phrase) in store.phrases.enumerated() {
            let row = PhraseRow(phrase: phrase, frame: NSRect(x: 0, y: CGFloat(i) * rowHeight, width: document.frame.width, height: rowHeight))
            row.action = { [weak self] in _ = self?.copy(phrase) }
            document.addSubview(row)
            rows.append(row)
        }
        if store.phrases.isEmpty {
            let label = NSTextField(labelWithString: "还没有语句，点击下方「管理语句」添加")
            label.font = .systemFont(ofSize: 12)
            label.textColor = muted
            label.frame = NSRect(x: 16, y: 24, width: document.frame.width - 32, height: 22)
            document.addSubview(label)
        }
        scroll.documentView = document
        root.addSubview(scroll)
        let button = NSButton(title: "管理语句…", target: self, action: #selector(manage))
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.contentTintColor = teal
        button.frame = NSRect(x: 16, y: height - 39, width: 108, height: 28)
        root.addSubview(button)
        let count = NSTextField(labelWithString: "\(store.phrases.count) 条语句")
        count.font = .systemFont(ofSize: 11)
        count.textColor = muted
        count.alignment = .right
        count.frame = NSRect(x: frame.width - 110, y: height - 32, width: 86, height: 18)
        root.addSubview(count)
        menuPanel.contentView = root
    }
    @objc func manage() { collapse(); openEditor?() }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

struct EditorView: View {
    @ObservedObject var store: PhraseStore
    @State private var search = ""
    @State private var selection: UUID?
    @State private var title = ""
    @State private var text = ""
    @State private var editingNew = false
    @State private var confirmDelete = false
    @State private var discardAction: (() -> Void)?
    @State private var confirmDiscard = false
    @State private var copied = false
    let copyAction: (Phrase) -> Bool
    let onDraftChanged: (Bool) -> Void
    var filtered: [Phrase] {
        store.phrases.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }
    }
    var original: Phrase? { store.phrases.first { $0.id == selection } }
    var dirty: Bool { editingNew ? (!title.isEmpty || !text.isEmpty) : original.map { $0.title != title || $0.text != text } ?? false }
    var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func load(_ id: UUID?) {
        selection = id
        editingNew = false
        title = store.phrases.first { $0.id == id }?.title ?? ""
        text = store.phrases.first { $0.id == id }?.text ?? ""
        copied = false
    }
    func guarded(_ action: @escaping () -> Void) {
        if dirty { discardAction = action; confirmDiscard = true } else { action() }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("我的快捷语句").font(.title3.bold())
                TextField("搜索标题或内容", text: $search).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(filtered) { phrase in
                            Button { if selection != phrase.id || editingNew { guarded { load(phrase.id) } } } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(phrase.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(phrase.text.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(selection == phrase.id && !editingNew ? Color(nsColor: teal).opacity(0.12) : Color.clear)
                                .cornerRadius(8)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if filtered.isEmpty { Text(search.isEmpty ? "点击下方新增语句" : "没有匹配的语句").font(.footnote).foregroundStyle(.secondary).padding(.top, 24) }
                    }
                }
                HStack {
                    Button { guarded { selection = nil; title = ""; text = ""; editingNew = true } } label: { Label("新增", systemImage: "plus") }
                    Spacer()
                    Text("\(store.phrases.count) 条").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("导入", action: importPhrases)
                    Button("导出", action: exportPhrases)
                }.controlSize(.small)
            }.padding(20).frame(width: 250)
            Divider()
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(editingNew ? "新增语句" : "编辑语句").font(.title2.bold())
                    Spacer()
                    if dirty { Text("未保存").font(.caption).foregroundStyle(.orange) }
                }
                Text("标题").font(.headline)
                TextField("例如：收到，谢谢", text: $title).textFieldStyle(.roundedBorder)
                Text("复制内容").font(.headline)
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                    .frame(minHeight: 180)
                Text("支持多行文字，点击悬浮菜单时会完整复制。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("删除", role: .destructive) { confirmDelete = true }.disabled(selection == nil || editingNew)
                    Button { if let selection { store.move(selection, by: -1) } } label: { Image(systemName: "arrow.up") }
                        .help("在悬浮菜单中上移").disabled(selection == nil || editingNew || store.phrases.first?.id == selection)
                    Button { if let selection { store.move(selection, by: 1) } } label: { Image(systemName: "arrow.down") }
                        .help("在悬浮菜单中下移").disabled(selection == nil || editingNew || store.phrases.last?.id == selection)
                    Spacer()
                    Button(copied ? "已复制 ✓" : "复制") {
                        copied = copyAction(Phrase(title: title, text: text))
                    }.disabled(!valid)
                    Button("保存") {
                        if let id = store.save(id: editingNew ? nil : selection, title: title, text: text) { load(id) }
                    }.keyboardShortcut("s", modifiers: .command).disabled(!valid || (!dirty && !editingNew))
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(selection == nil && !editingNew)
        }
        .frame(minWidth: 780, minHeight: 510)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color(nsColor: teal))
        .onAppear { if selection == nil { load(store.phrases.first?.id); if store.phrases.isEmpty { editingNew = true } } }
        .onChange(of: dirty) { onDraftChanged($0) }
        .onChange(of: title) { _ in copied = false }
        .onChange(of: text) { _ in copied = false }
        .alert("删除这条语句？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let selection { store.remove(selection); if !store.phrases.contains(where: { $0.id == selection }) { load(store.phrases.first?.id) } }
                if store.phrases.isEmpty { editingNew = true }
            }
        } message: { Text("删除后可通过之前导出的备份恢复。") }
        .alert("放弃未保存的修改？", isPresented: $confirmDiscard) {
            Button("继续编辑", role: .cancel) { discardAction = nil }
            Button("放弃修改", role: .destructive) { discardAction?(); discardAction = nil }
        }
        .alert("操作未完成", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
    func importPhrases() {
        guarded {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.message = "导入 JSON 备份：相同 ID 更新，其余语句追加。"
            if panel.runModal() == .OK, let url = panel.url, store.importFile(url) {
                load(selection ?? store.phrases.first?.id)
                if store.phrases.isEmpty { editingNew = true }
            }
        }
    }
    func exportPhrases() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "快捷语句备份.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(store.phrases).write(to: url, options: .atomic)
            } catch { store.errorMessage = "导出失败：\(error.localizedDescription)" }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var store: PhraseStore!
    var controller: OrbController!
    var statusItem: NSStatusItem!
    var editor: NSWindow?
    var editorDirty = false
    var smoke = CommandLine.arguments.contains("--ui-test")
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !smoke, let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        let uiDirectory = argumentValue("--test-dir").map { URL(fileURLWithPath: $0) }
        store = PhraseStore(fileURL: smoke ? uiDirectory!.appendingPathComponent("ui-phrases.json") : nil)
        let defaults = smoke ? UserDefaults(suiteName: "PhraseOrb.UITests")! : .standard
        if smoke { defaults.removePersistentDomain(forName: "PhraseOrb.UITests") }
        controller = OrbController(store: store, pasteboard: smoke ? NSPasteboard(name: .init("PhraseOrb.UITests")) : .general, defaults: defaults)
        controller.openEditor = { [weak self] in self?.showEditor() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "语句球")
        statusItem.button?.toolTip = "语句球 — 快捷复制"
        let menu = NSMenu()
        let manage = menu.addItem(withTitle: "管理快捷语句…", action: #selector(showEditor), keyEquivalent: ",")
        manage.target = self
        let toggle = menu.addItem(withTitle: "显示／隐藏悬浮球", action: #selector(toggleOrb), keyEquivalent: "")
        toggle.target = self
        let reset = menu.addItem(withTitle: "重置悬浮球位置", action: #selector(resetOrb), keyEquivalent: "")
        reset.target = self
        menu.addItem(.separator())
        let about = menu.addItem(withTitle: "关于语句球", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        let quit = menu.addItem(withTitle: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        statusItem.menu = menu
        controller.contextMenu = menu
        let main = NSMenu()
        let appItem = NSMenuItem(); appItem.submenu = menu.copy() as? NSMenu; main.addItem(appItem)
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        controller.show()
        if smoke { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.runUISmoke(uiDirectory!) } }
        else if store.errorMessage != nil { showEditor() }
    }
    @objc func showEditor() {
        controller.collapse()
        if editor == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 830, height: 550),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "语句球 · 管理快捷语句"
            window.minSize = NSSize(width: 800, height: 550)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: EditorView(store: store, copyAction: { [weak self] in self?.controller.copy($0) ?? false },
                                                                  onDraftChanged: { [weak self] in self?.editorDirty = $0 }))
            window.center()
            editor = window
        }
        NSApp.activate(ignoringOtherApps: true)
        editor?.makeKeyAndOrderFront(nil)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard editorDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "关闭前还有未保存的修改"
        alert.informativeText = "关闭会放弃修改。也可以继续编辑并点击「保存」。"
        alert.addButton(withTitle: "继续编辑")
        alert.addButton(withTitle: "放弃修改并关闭")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func windowWillClose(_ notification: Notification) { editor = nil; editorDirty = false }
    @objc func toggleOrb() { if controller.isShown { controller.hide() } else { controller.show() } }
    @objc func resetOrb() { controller.collapse(); controller.resetPosition(); controller.show() }
    @objc func screenChanged() { controller.collapse(); controller.finishDrag() }
    @objc func quitApp() {
        if let editor, !windowShouldClose(editor) { return }
        editorDirty = false
        NSApp.terminate(nil)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let editor, editorDirty, !windowShouldClose(editor) { return .terminateCancel }
        return .terminateNow
    }
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "语句球 1.0"
        alert.informativeText = "移入展开，点击复制，⌘V 粘贴。\n拖动悬浮球可移动，右键或菜单栏图标可管理与退出。\n所有语句只保存在本机，无需网络或辅助功能权限。"
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    func runUISmoke(_ directory: URL) {
        var report: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            report.append("PASS: \(name)")
        }
        check(controller.orb.isVisible, "悬浮球启动显示")
        check(controller.orb.level == .statusBar && !controller.orb.canBecomeKey, "置顶且复制面板不抢输入焦点")
        controller.orbView.entered?()
        check(controller.menuPanel.isVisible && controller.rows.count == store.phrases.count, "移入事件展开全部语句")
        let phrase = store.phrases[0]
        controller.rows[0].action?()
        check(controller.pasteboard.string(forType: .string) == phrase.text, "点击语句写入独立测试剪贴板")
        check(controller.rows[0].copied && controller.orbView.copied, "复制成功反馈")
        controller.orbView.copied = false
        controller.rows[0].copied = false
        capture(controller.menuPanel.contentView!, to: directory.appendingPathComponent("menu-preview.png"))
        capture(controller.orbView, to: directory.appendingPathComponent("orb-preview.png"))
        controller.scheduleCollapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            check(!self.controller.menuPanel.isVisible, "离开后延迟收起")
            self.controller.expand()
            self.controller.scheduleCollapse()
            (self.controller.menuPanel.contentView as? HoverView)?.entered?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                check(self.controller.menuPanel.isVisible, "进入菜单取消收起，跨越间隙可点击")
                self.controller.hide()
                check(!self.controller.orb.isVisible && !self.controller.menuPanel.isVisible, "隐藏悬浮球与菜单")
                self.controller.show()
                self.showEditor()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    check(self.editor?.isVisible == true, "管理窗口打开")
                    capture(self.editor!.contentView!, to: directory.appendingPathComponent("editor-preview.png"))
                    try! report.joined(separator: "\n").write(to: directory.appendingPathComponent("ui-test-results.txt"), atomically: true, encoding: .utf8)
                    print(report.joined(separator: "\n"))
                    self.editorDirty = false
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

func capture(_ view: NSView, to url: URL) {
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
}

func argumentValue(_ flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag), CommandLine.arguments.indices.contains(index + 1) else { return nil }
    return CommandLine.arguments[index + 1]
}

func runSelfTests() {
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
        count += 1; print("PASS: \(name)")
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PhraseOrb-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("phrases.json")
    let store = PhraseStore(fileURL: url)
    check(store.phrases.count == 5 && FileManager.default.fileExists(atPath: url.path), "首次启动初始化并保存默认语句")
    let multiline = "第一行\n第二行\n  保留空格 🐱"
    let id = store.save(id: nil, title: "  多行测试  ", text: multiline)!
    check(store.phrases.last?.title == "多行测试" && store.phrases.last?.text == multiline, "新增语句保留多行、空格和 Unicode")
    let reopened = PhraseStore(fileURL: url)
    check(reopened.phrases == store.phrases, "重新加载还原语句与排序")
    check(store.save(id: id, title: "编辑后", text: "新内容") == id && store.phrases.count == 6, "编辑保留 ID 且不重复添加")
    store.move(id, by: -1)
    check(store.phrases[4].id == id, "语句排序持久化")
    check(store.save(id: nil, title: " ", text: "abc") == nil && store.save(id: nil, title: "abc", text: "\n ") == nil, "拒绝空标题与空内容")
    let backup = folder.appendingPathComponent("import.json")
    let added = Phrase(title: "导入", text: "从备份恢复")
    try! JSONEncoder().encode([Phrase(id: id, title: "合并", text: "更新"), added]).write(to: backup)
    check(store.importFile(backup) && store.phrases.count == 7 && store.phrases.first(where: { $0.id == id })?.text == "更新", "导入合并同 ID 与追加新语句")
    try! JSONEncoder().encode([added, added]).write(to: backup)
    check(!store.importFile(backup) && store.phrases.count == 7, "无效备份不覆盖现有数据")
    store.remove(id)
    check(!PhraseStore(fileURL: url).phrases.contains(where: { $0.id == id }), "删除写入磁盘")
    let corrupt = folder.appendingPathComponent("corrupt.json")
    let broken = Data("not json".utf8)
    try! broken.write(to: corrupt)
    let corruptStore = PhraseStore(fileURL: corrupt)
    check(corruptStore.errorMessage != nil && (try! Data(contentsOf: corrupt)) == broken, "损坏文件保留且报告错误")
    let screen = NSRect(x: -1920, y: 40, width: 1920, height: 1040)
    let clipped = OrbLayout.clamp(NSPoint(x: 100, y: -200), to: screen)
    check(clipped.x == -72 && clipped.y == 48, "副屏负坐标和拖动边界")
    for point in [NSPoint(x: -1900, y: 50), NSPoint(x: -80, y: 1000)] {
        let menu = OrbLayout.menuFrame(orb: NSRect(origin: point, size: NSSize(width: 64, height: 64)), screen: screen, height: 469)
        check(screen.contains(menu), "菜单在屏幕边缘自动换侧并保持可见")
    }
    print("ALL \(count) TESTS PASSED")
}

if CommandLine.arguments.contains("--self-test") { runSelfTests(); exit(0) }
if CommandLine.arguments.contains("--ui-test") && argumentValue("--test-dir") == nil {
    fputs("--ui-test requires --test-dir\n", stderr); exit(2)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
