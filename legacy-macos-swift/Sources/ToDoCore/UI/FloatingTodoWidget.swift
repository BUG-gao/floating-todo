import AppKit
import SwiftUI

public struct FloatingTodoWidget: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject private var store: TodoStore
    @FocusState private var inputIsFocused: Bool
    @State private var draftTitle = ""
    @State private var composerEditingItemID: TodoItem.ID?
    @State private var composerEditingDay: TodoDay?
    @State private var settingsAreVisible = false
    @State private var pendingScrollItemID: TodoItem.ID?
    @State private var activeActionMenu: RowActionMenuContext?
    @State private var detailEditor: TodoDetailEditorContext?
    @State private var recurringComposerIsActive = false
    @State private var recurringDraftTitle = ""
    @State private var recurringEditingItemID: TodoItem.ID?
    @FocusState private var recurringInputIsFocused: Bool
    private let onExpand: () -> Void

    public init(store: TodoStore, onExpand: @escaping () -> Void = {}) {
        self.store = store
        self.onExpand = onExpand
    }

    public var body: some View {
        let palette = WidgetPalette(colorScheme: effectiveColorScheme)
        let surfaceOpacity = self.surfaceOpacity

        GeometryReader { geometry in
            let isCompact = geometry.size.width < 295 || geometry.size.height < 270
            let displayDay: TodoDay = isCompact ? .today : store.selectedDay

            ZStack {
                VStack(spacing: isCompact ? 8 : 12) {
                    if !isCompact {
                        header(palette: palette)
                        dayPicker(palette: palette, surfaceOpacity: surfaceOpacity)
                    }

                    if displayDay == .today && (!store.recurringItems.isEmpty || recurringComposerIsActive) {
                        recurringSection(isCompact: isCompact, palette: palette, surfaceOpacity: surfaceOpacity)
                    }

                    taskList(day: displayDay, isCompact: isCompact, palette: palette, surfaceOpacity: surfaceOpacity)

                    if !isCompact {
                        if store.completedCount(for: displayDay) > 0 {
                            clearCompletedBar(day: displayDay, palette: palette)
                        }
                        composer(palette: palette, surfaceOpacity: surfaceOpacity)
                        memoDrawer(palette: palette, surfaceOpacity: surfaceOpacity)
                    }
                }
                .padding(isCompact ? 10 : 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isCompact {
                    compactExpandButton(palette: palette)
                }

                floatingActionMenu(in: geometry, palette: palette)
                detailEditorOverlay(palette: palette)
            }
            .coordinateSpace(name: WidgetCoordinateSpace.name)
            .onChange(of: isCompact) { _, compact in
                if compact {
                    closeFloatingMenu()
                    detailEditor = nil
                }
            }
        }
        .frame(minWidth: 220, idealWidth: 330, maxWidth: 440, minHeight: 180, idealHeight: 520, maxHeight: 700)
        .background(widgetMaterial(palette: palette))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .compositingGroup()
        .overlay(widgetBorder(palette: palette))
        .shadow(color: palette.shadow, radius: 24, x: 0, y: 16)
        .preferredColorScheme(store.settings.appearance.preferredColorScheme)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: store.selectedDay)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: store.items(for: store.selectedDay))
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: store.recurringItems)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: store.settings.memoEnabled)
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: store.memo.isExpanded)
        .onAppear {
            inputIsFocused = true
        }
    }

    private func header(palette: WidgetPalette) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("悬浮待办")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(headerSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            countPill

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    settingsAreVisible.toggle()
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(IconButtonStyle(isActive: settingsAreVisible, palette: palette))
            .help("设置")
            .popover(isPresented: $settingsAreVisible, arrowEdge: .top) {
                SettingsPopover(
                    settings: $store.settings,
                    onMemoEnabledChange: { isEnabled in
                        store.setMemoEnabled(isEnabled)
                    },
                    onBackgroundColorChange: { color in
                        store.updateCustomBackgroundColor(color)
                    },
                    onClearBackgroundColor: {
                        store.clearCustomBackgroundColor()
                    }
                )
                    .frame(width: 260)
                    .padding(14)
            }
        }
    }

    private func dayPicker(palette: WidgetPalette, surfaceOpacity: Double) -> some View {
        HStack(spacing: 6) {
            ForEach(TodoDay.allCases) { day in
                DayPickerButton(
                    day: day,
                    isSelected: store.selectedDay == day,
                    dateText: formattedDate(for: day),
                    palette: palette,
                    surfaceOpacity: surfaceOpacity
                ) {
                    store.selectedDay = day
                }
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.segmentBackground.opacity(surfaceOpacity))
        )
    }

    private func taskList(day: TodoDay, isCompact: Bool, palette: WidgetPalette, surfaceOpacity: Double) -> some View {
        let hasRecurringAbove = day == .today && !store.recurringItems.isEmpty
        return Group {
            if store.items(for: day).isEmpty {
                if isCompact {
                    compactEmptyState(palette: palette, hasRecurringAbove: hasRecurringAbove)
                } else {
                    emptyState(day: day, palette: palette, hasRecurringAbove: hasRecurringAbove)
                }
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(store.items(for: day)) { item in
                            TodoRow(
                                item: item,
                                day: day,
                                isCompact: isCompact,
                                isMenuActive: activeActionMenu?.item.id == item.id,
                                onToggle: {
                                    closeFloatingMenu()
                                    store.toggle(id: item.id, in: day)
                                },
                                onEditInComposer: {
                                    closeFloatingMenu()
                                    beginComposerEdit(item: item, day: day)
                                },
                                onShowMenu: { frame in
                                    toggleFloatingMenu(for: item, day: day, buttonFrame: frame)
                                },
                                onDelete: {
                                    closeFloatingMenu()
                                    store.delete(id: item.id, in: day)
                                },
                                palette: palette,
                                surfaceOpacity: surfaceOpacity
                            )
                            .id(item.id)
                            .listRowInsets(EdgeInsets(top: isCompact ? 3 : 4, leading: 0, bottom: isCompact ? 3 : 4, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onMove { source, destination in
                            closeFloatingMenu()
                            store.move(from: source, to: destination, in: day)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .onChange(of: pendingScrollItemID) { _, itemID in
                        guard let itemID else { return }
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                                proxy.scrollTo(itemID, anchor: .top)
                            }
                            pendingScrollItemID = nil
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func floatingActionMenu(in geometry: GeometryProxy, palette: WidgetPalette) -> some View {
        if let context = activeActionMenu {
            Button(action: closeFloatingMenu) {
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
                .zIndex(80)

            RowActionMenu(
                detailTitle: context.item.detail.isEmpty ? "添加描述" : "编辑描述",
                moveTargets: TodoDay.allCases.filter { $0 != context.day },
                onEdit: {
                    closeFloatingMenu()
                    beginComposerEdit(item: context.item, day: context.day)
                },
                onEditDetail: {
                    closeFloatingMenu()
                    cancelComposerEdit()
                    detailEditor = TodoDetailEditorContext(item: context.item, day: context.day)
                },
                onMove: { targetDay in
                    closeFloatingMenu()
                    store.moveItem(id: context.item.id, from: context.day, to: targetDay)
                },
                onPinRecurring: {
                    closeFloatingMenu()
                    store.pinAsRecurring(id: context.item.id, from: context.day)
                },
                onDelete: {
                    closeFloatingMenu()
                    store.delete(id: context.item.id, in: context.day)
                }
            )
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 18, x: 0, y: 10)
            .position(menuPosition(for: context.buttonFrame, in: geometry.size))
            .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            .zIndex(90)
        }
    }

    @ViewBuilder
    private func detailEditorOverlay(palette: WidgetPalette) -> some View {
        if detailEditor != nil {
            Button {
                detailEditor = nil
            } label: {
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
                .zIndex(100)

            TodoDetailEditor(
                title: Binding(
                    get: { detailEditor?.title ?? "" },
                    set: { detailEditor?.title = $0 }
                ),
                detail: Binding(
                    get: { detailEditor?.detail ?? "" },
                    set: { detailEditor?.detail = $0 }
                ),
                dayTitle: detailEditor?.day.title ?? store.selectedDay.title,
                onCancel: {
                    detailEditor = nil
                },
                onSave: {
                    guard let detailEditor else { return }
                    store.updateItem(
                        id: detailEditor.itemID,
                        title: detailEditor.title,
                        detail: detailEditor.detail,
                        in: detailEditor.day
                    )
                    self.detailEditor = nil
                }
            )
            .frame(width: 300)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.controlStroke.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 22, x: 0, y: 14)
            .padding(16)
            .transition(.scale(scale: 0.97).combined(with: .opacity))
            .zIndex(110)
        }
    }

    private func emptyState(day: TodoDay, palette: WidgetPalette, hasRecurringAbove: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(palette.accent.opacity(0.74))
                .symbolEffect(.pulse.byLayer, options: .nonRepeating)

            VStack(spacing: 4) {
                Text(hasRecurringAbove ? "\(day.title)没有临时待办" : "\(day.title)还没有待办")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(hasRecurringAbove ? "上方是每天常驻的事" : "写下一件真正要推进的事")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            inputIsFocused = true
        }
    }

    private func compactEmptyState(palette: WidgetPalette, hasRecurringAbove: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(palette.accent.opacity(0.7))
            Text(hasRecurringAbove ? "今天没有临时待办" : "今天暂无待办")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compactExpandButton(palette: WidgetPalette) -> some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(IconButtonStyle(isActive: false, palette: palette))
                .help("放大小组件")
            }
            Spacer()
        }
        .padding(8)
        .zIndex(70)
    }

    @ViewBuilder
    private func recurringSection(isCompact: Bool, palette: WidgetPalette, surfaceOpacity: Double) -> some View {
        VStack(spacing: isCompact ? 4 : 6) {
            if !isCompact {
                HStack(spacing: 6) {
                    Image(systemName: "repeat")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.accent)
                    Text("每天")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        recurringComposerIsActive = true
                        recurringInputIsFocused = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(IconButtonStyle(isActive: recurringComposerIsActive, palette: palette))
                    .help("添加每天常驻待办")
                }
            }

            ForEach(store.recurringItems) { item in
                RecurringTodoRow(
                    item: item,
                    isCompact: isCompact,
                    palette: palette,
                    surfaceOpacity: surfaceOpacity,
                    onToggle: { store.toggleRecurring(id: item.id) },
                    onEdit: { beginRecurringEdit(item: item) },
                    onUnpin: { store.unpinRecurring(id: item.id) },
                    onDelete: { store.deleteRecurring(id: item.id) }
                )
            }

            if recurringComposerIsActive && !isCompact {
                recurringComposer(palette: palette, surfaceOpacity: surfaceOpacity)
            }
        }
        .padding(isCompact ? 6 : 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.accent.opacity(isCompact ? 0.06 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func recurringComposer(palette: WidgetPalette, surfaceOpacity: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "repeat")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            TextField("添加每天常驻待办", text: $recurringDraftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .focused($recurringInputIsFocused)
                .onSubmit(commitRecurringComposer)

            Button(action: cancelRecurringComposer) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary.opacity(0.72))
            .help("收起")

            Button(action: commitRecurringComposer) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(recurringDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary.opacity(0.45) : palette.accent)
            .disabled(recurringDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("添加")
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.controlFill.opacity(surfaceOpacity))
        )
    }

    private func clearCompletedBar(day: TodoDay, palette: WidgetPalette) -> some View {
        HStack(spacing: 6) {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    closeFloatingMenu()
                    store.clearCompleted(in: day)
                }
            } label: {
                Label("清除已完成（\(store.completedCount(for: day))）", systemImage: "checkmark.circle.badge.xmark")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("清除「\(day.title)」里所有已完成待办")
        }
        .transition(.opacity)
    }

    private func composer(palette: WidgetPalette, surfaceOpacity: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)

            TextField(composerPlaceholder, text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .focused($inputIsFocused)
                .onSubmit(commitComposer)

            if composerEditingItemID != nil {
                Button(action: cancelComposerEdit) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary.opacity(0.72))
                .help("取消编辑")
            }

            Button(action: commitComposer) {
                Image(systemName: composerEditingItemID == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary.opacity(0.45) : palette.accent)
            .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(composerEditingItemID == nil ? "添加待办" : "确认修改")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.controlFill.opacity(surfaceOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.controlStroke.opacity(surfaceOpacity), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func memoDrawer(palette: WidgetPalette, surfaceOpacity: Double) -> some View {
        if store.settings.memoEnabled {
            MemoDrawer(
                text: Binding(
                    get: { store.memo.text },
                    set: { store.updateMemoText($0) }
                ),
                isExpanded: store.memo.isExpanded,
                onToggleExpanded: {
                    store.setMemoExpanded(!store.memo.isExpanded)
                },
                palette: palette,
                surfaceOpacity: surfaceOpacity
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var countPill: some View {
        let count = store.incompleteCount()
        return Text("\(count)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .monospacedDigit()
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(count == 0 ? Color.green.opacity(0.24) : WidgetPalette(colorScheme: effectiveColorScheme).accent.opacity(0.2))
            )
            .foregroundStyle(count == 0 ? Color.green : WidgetPalette(colorScheme: effectiveColorScheme).accent)
            .accessibilityLabel("\(count) 个未完成")
    }

    private func widgetMaterial(palette: WidgetPalette) -> some View {
        let customBackgroundColor = store.settings.customBackgroundColor
        return ZStack {
            LinearGradient(
                colors: [
                    panelTopColor(palette: palette, customBackgroundColor: customBackgroundColor),
                    panelBottomColor(palette: palette, customBackgroundColor: customBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(min(0.16, store.settings.opacity * 0.2))
        }
    }

    private func panelTopColor(palette: WidgetPalette, customBackgroundColor: WidgetBackgroundColor?) -> Color {
        guard let customBackgroundColor else {
            return palette.panelTop.opacity(store.settings.opacity)
        }
        return Color(widgetBackgroundColor: customBackgroundColor)
            .opacity(store.settings.opacity)
    }

    private func panelBottomColor(palette: WidgetPalette, customBackgroundColor: WidgetBackgroundColor?) -> Color {
        guard let customBackgroundColor else {
            return palette.panelBottom.opacity(max(0.08, store.settings.opacity * 0.72))
        }
        return Color(widgetBackgroundColor: customBackgroundColor)
            .blendedForPanelBottom(isDark: effectiveColorScheme == .dark)
            .opacity(max(0.08, store.settings.opacity * 0.72))
    }

    private func widgetBorder(palette: WidgetPalette) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [palette.borderTop, palette.borderBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var effectiveColorScheme: ColorScheme {
        store.settings.appearance.resolvedColorScheme(systemColorScheme)
    }

    private var surfaceOpacity: Double {
        min(1, max(0.18, store.settings.opacity + 0.24))
    }

    private var headerSubtitle: String {
        let count = store.incompleteCount()
        return count == 0 ? "这一页已经清空" : "\(store.selectedDay.title)还有 \(count) 件事"
    }

    private var emptyStateIcon: String {
        switch store.selectedDay {
        case .today:
            "sun.max.fill"
        case .tomorrow:
            "sparkles"
        case .dayAfterTomorrow:
            "calendar.badge.clock"
        }
    }

    private var composerPlaceholder: String {
        if composerEditingItemID != nil {
            "编辑待办标题"
        } else {
            "添加\(store.selectedDay.title)待办"
        }
    }

    private func beginComposerEdit(item: TodoItem, day: TodoDay) {
        store.selectedDay = day
        composerEditingItemID = item.id
        composerEditingDay = day
        draftTitle = item.title
        inputIsFocused = true
    }

    private func commitComposer() {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if let editingID = composerEditingItemID {
            store.updateTitle(id: editingID, title: trimmedTitle, in: composerEditingDay ?? store.selectedDay)
            composerEditingItemID = nil
            composerEditingDay = nil
        } else {
            pendingScrollItemID = store.add(trimmedTitle)?.id
        }
        draftTitle = ""
        inputIsFocused = true
    }

    private func cancelComposerEdit() {
        composerEditingItemID = nil
        composerEditingDay = nil
        draftTitle = ""
        inputIsFocused = true
    }

    private func beginRecurringEdit(item: TodoItem) {
        recurringComposerIsActive = true
        recurringEditingItemID = item.id
        recurringDraftTitle = item.title
        recurringInputIsFocused = true
    }

    private func commitRecurringComposer() {
        let trimmedTitle = recurringDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if let editingID = recurringEditingItemID {
            store.updateRecurringTitle(id: editingID, title: trimmedTitle)
        } else {
            store.addRecurring(trimmedTitle)
        }
        recurringDraftTitle = ""
        recurringEditingItemID = nil
        recurringInputIsFocused = true
    }

    private func cancelRecurringComposer() {
        recurringComposerIsActive = false
        recurringEditingItemID = nil
        recurringDraftTitle = ""
        recurringInputIsFocused = false
    }

    private func toggleFloatingMenu(for item: TodoItem, day: TodoDay, buttonFrame: CGRect) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            if activeActionMenu?.item.id == item.id {
                activeActionMenu = nil
            } else {
                activeActionMenu = RowActionMenuContext(item: item, day: day, buttonFrame: buttonFrame)
            }
        }
    }

    private func closeFloatingMenu() {
        guard activeActionMenu != nil else { return }
        withAnimation(.easeOut(duration: 0.14)) {
            activeActionMenu = nil
        }
    }

    private func menuPosition(for buttonFrame: CGRect, in size: CGSize) -> CGPoint {
        let menuSize = CGSize(width: 158, height: 230)
        let margin: CGFloat = 10
        let rawX = buttonFrame.maxX - menuSize.width / 2
        let x = min(max(rawX, margin + menuSize.width / 2), size.width - margin - menuSize.width / 2)
        let belowY = buttonFrame.maxY + 8 + menuSize.height / 2
        let aboveY = buttonFrame.minY - 8 - menuSize.height / 2
        let y = belowY + menuSize.height / 2 + margin <= size.height ? belowY : max(margin + menuSize.height / 2, aboveY)
        return CGPoint(x: x, y: y)
    }

    private func formattedDate(for day: TodoDay) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: day.date())
    }
}

private struct DayPickerButton: View {
    let day: TodoDay
    let isSelected: Bool
    let dateText: String
    let palette: WidgetPalette
    let surfaceOpacity: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(day.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(dateText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.72) : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? palette.selectedSegment.opacity(surfaceOpacity) : Color.clear)
            )
            .scaleEffect(isSelected ? 1 : 0.98)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .accessibilityLabel(day.title)
        .animation(.spring(response: 0.25, dampingFraction: 0.86), value: isSelected)
    }
}

private enum WidgetCoordinateSpace {
    static let name = "floating-todo-widget"
}

/// 把待办详情里的网址/邮箱识别成可点击链接，方便直接打开会议链接等。
private func linkifiedDetail(_ string: String, accent: Color) -> AttributedString {
    let mutable = NSMutableAttributedString(string: string)
    let types: NSTextCheckingResult.CheckingType = [.link]
    if let detector = try? NSDataDetector(types: types.rawValue) {
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        detector.enumerateMatches(in: string, range: fullRange) { match, _, _ in
            guard let match, let url = match.url else { return }
            mutable.addAttribute(.link, value: url, range: match.range)
        }
    }
    var attributed = AttributedString(mutable)
    for run in attributed.runs where run.link != nil {
        attributed[run.range].foregroundColor = accent
        attributed[run.range].underlineStyle = .single
    }
    return attributed
}

private struct MenuButtonFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct RowActionMenuContext: Equatable {
    let item: TodoItem
    let day: TodoDay
    let buttonFrame: CGRect
}

private struct TodoDetailEditorContext: Equatable {
    let itemID: TodoItem.ID
    let day: TodoDay
    var title: String
    var detail: String

    init(item: TodoItem, day: TodoDay) {
        itemID = item.id
        self.day = day
        title = item.title
        detail = item.detail
    }
}

private struct TodoRow: View {
    let item: TodoItem
    let day: TodoDay
    let isCompact: Bool
    let isMenuActive: Bool
    let onToggle: () -> Void
    let onEditInComposer: () -> Void
    let onShowMenu: (CGRect) -> Void
    let onDelete: () -> Void
    let palette: WidgetPalette
    let surfaceOpacity: Double

    @State private var isHovering = false
    @State private var menuButtonFrame: CGRect = .zero

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(item.isCompleted ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? "标记为未完成" : "完成")

            rowText

            if !isCompact {
                rowMenu
                    .opacity(isHovering || isMenuActive ? 1 : 0)
                    .allowsHitTesting(isHovering || isMenuActive)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(IconButtonStyle(isActive: false, palette: palette))
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .help("删除")
            }
        }
        .padding(.horizontal, isCompact ? 8 : 10)
        .padding(.vertical, isCompact ? 7 : 9)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill((item.isCompleted ? palette.completedRowFill : palette.rowFill(isHovering: isHovering)).opacity(surfaceOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.rowStroke(isHovering: isHovering).opacity(surfaceOpacity), lineWidth: 1)
        )
        .scaleEffect(isHovering ? 1.01 : 1)
        .opacity(item.isCompleted ? 0.72 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .scale(scale: 0.96).combined(with: .opacity)
        ))
    }

    @ViewBuilder
    private var rowText: some View {
        VStack(alignment: .leading, spacing: item.detail.isEmpty || isCompact ? 0 : 3) {
            Text(item.title)
                .font(.system(size: isCompact ? 13 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .strikethrough(item.isCompleted, color: .secondary)
                .lineLimit(isCompact ? 1 : 2)

            if !isCompact && !item.detail.isEmpty {
                Text(linkifiedDetail(item.detail, accent: palette.accent))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tint(palette.accent)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if isCompact {
                onToggle()
            } else {
                onEditInComposer()
            }
        }
    }

    private var rowMenu: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                onShowMenu(menuButtonFrame)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(IconButtonStyle(isActive: isMenuActive, palette: palette))
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: MenuButtonFramePreferenceKey.self,
                        value: proxy.frame(in: .named(WidgetCoordinateSpace.name))
                    )
            }
        )
        .onPreferenceChange(MenuButtonFramePreferenceKey.self) { frame in
            menuButtonFrame = frame
        }
        .help("更多操作")
    }
}

private struct RecurringTodoRow: View {
    let item: TodoItem
    let isCompact: Bool
    let palette: WidgetPalette
    let surfaceOpacity: Double
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onUnpin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: isCompact ? 17 : 19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(item.isCompleted ? Color.green : palette.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? "标记为今天未完成" : "完成")

            Text(item.title)
                .font(.system(size: isCompact ? 13 : 14, weight: .medium, design: .rounded))
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .strikethrough(item.isCompleted, color: .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if isCompact { onToggle() } else { onEdit() }
                }

            if isCompact {
                Image(systemName: "repeat")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.accent.opacity(0.7))
            } else {
                Button(action: onUnpin) {
                    Image(systemName: "pin.slash")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(IconButtonStyle(isActive: false, palette: palette))
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .help("取消每天，移回今天")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(IconButtonStyle(isActive: false, palette: palette))
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .help("删除")
            }
        }
        .padding(.horizontal, isCompact ? 8 : 10)
        .padding(.vertical, isCompact ? 6 : 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill((item.isCompleted ? palette.completedRowFill : palette.rowFill(isHovering: isHovering)).opacity(surfaceOpacity))
        )
        .opacity(item.isCompleted ? 0.72 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
    }
}

private struct RowActionMenu: View {
    let detailTitle: String
    let moveTargets: [TodoDay]
    let onEdit: () -> Void
    let onEditDetail: () -> Void
    let onMove: (TodoDay) -> Void
    let onPinRecurring: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            menuButton("编辑", systemImage: "pencil", action: onEdit)
            menuButton(detailTitle, systemImage: "note.text", action: onEditDetail)
            menuButton("设为每天", systemImage: "repeat", action: onPinRecurring)
            Divider()
            ForEach(moveTargets) { day in
                menuButton("移到\(day.title)", systemImage: "arrow.right", action: {
                    onMove(day)
                })
            }
            Divider()
            menuButton("删除", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .frame(width: 142)
    }

    private func menuButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.001))
        )
    }
}

private struct TodoDetailEditor: View {
    @Binding var title: String
    @Binding var detail: String
    let dayTitle: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(dayTitle)待办详情")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            VStack(alignment: .leading, spacing: 6) {
                Text("标题")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("待办标题", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("描述")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextEditor(text: $detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(height: 84)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }

            HStack {
                Button("取消", action: onCancel)
                Spacer()
                Button("保存详情", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct SettingsPopover: View {
    @Binding var settings: TodoSettings
    let onMemoEnabledChange: (Bool) -> Void
    let onBackgroundColorChange: (WidgetBackgroundColor) -> Void
    let onClearBackgroundColor: () -> Void
    @State private var helpTopic: SettingsHelpTopic?
    @State private var selectedBackgroundColor = Color(red: 0.86, green: 0.92, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("小组件设置")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            settingToggle("始终置顶", isOn: $settings.alwaysOnTop)
            settingToggle("显示在所有桌面", isOn: $settings.visibleOnAllSpaces)
            settingToggle("开启备忘录", isOn: Binding(
                get: { settings.memoEnabled },
                set: { isEnabled in
                    onMemoEnabledChange(isEnabled)
                }
            ))
            settingToggle("允许 Option 操作小组件", isOn: $settings.clickThrough, topic: .optionClickThrough)
            settingToggle("低透明度时允许 Option 操作", isOn: $settings.autoClickThroughAtLowOpacity, topic: .lowOpacityClickThrough)

            Picker("外观", selection: $settings.appearance) {
                ForEach(TodoAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.segmented)

            backgroundColorSection

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("透明度")
                    Spacer()
                    Text("\(Int(settings.opacity * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))

                Slider(value: $settings.opacity, in: 0.2...0.95)
            }
        }
        .onAppear {
            selectedBackgroundColor = settings.customBackgroundColor.map(Color.init(widgetBackgroundColor:)) ?? Color(red: 0.86, green: 0.92, blue: 1.0)
        }
        .onChange(of: settings.customBackgroundColor) { _, customBackgroundColor in
            if let customBackgroundColor {
                selectedBackgroundColor = Color(widgetBackgroundColor: customBackgroundColor)
            }
        }
    }

    private var backgroundColorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ColorPicker(
                    "背景色",
                    selection: Binding(
                        get: { selectedBackgroundColor },
                        set: { color in
                            selectedBackgroundColor = color
                            onBackgroundColorChange(WidgetBackgroundColor(color: color))
                        }
                    ),
                    supportsOpacity: false
                )
                .font(.system(size: 13, weight: .medium, design: .rounded))

                Spacer()

                Button("恢复默认") {
                    onClearBackgroundColor()
                    selectedBackgroundColor = Color(red: 0.86, green: 0.92, blue: 1.0)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(settings.customBackgroundColor == nil ? Color.secondary.opacity(0.55) : Color.secondary)
                .disabled(settings.customBackgroundColor == nil)
            }

            if settings.customBackgroundColor != nil {
                Text("内部控件会跟随当前透明度保留统一材质。")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>, topic: SettingsHelpTopic? = nil) -> some View {
        HStack(spacing: 0) {
            Text(title)
            if let topic {
                helpButton(topic)
                    .padding(.leading, 2)
            }
            Spacer(minLength: 14)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
    }

    private func helpButton(_ topic: SettingsHelpTopic) -> some View {
        Button {
            helpTopic = topic
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(topic.title)说明")
        .help(topic.title)
        .popover(isPresented: Binding(
            get: { helpTopic == topic },
            set: { isPresented in
                if !isPresented {
                    helpTopic = nil
                }
            }
        ), arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(topic.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(topic.message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 230, alignment: .leading)
            .padding(10)
        }
    }
}

private struct MemoDrawer: View {
    @Binding var text: String
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let palette: WidgetPalette
    let surfaceOpacity: Double

    @FocusState private var editorIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggleExpanded) {
                HStack(spacing: 9) {
                    Image(systemName: "note.text")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(palette.accent)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(palette.accent.opacity(0.12))
                        )

                    Text("全局备忘录")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .frame(height: 48)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "收起备忘录" : "展开备忘录")

            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .opacity(0.35)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .scrollContentBackground(.hidden)
                            .focused($editorIsFocused)
                            .frame(minHeight: 88, maxHeight: 128)
                            .padding(8)

                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !editorIsFocused {
                            Text("记录临时想法、链接、会议号")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(palette.controlFill.opacity(max(0.16, surfaceOpacity - 0.12)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(palette.controlStroke.opacity(surfaceOpacity), lineWidth: 1)
                    )
                    .padding(10)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.controlFill.opacity(max(0.18, surfaceOpacity - 0.08)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.controlStroke.opacity(surfaceOpacity), lineWidth: 1)
        )
    }
}

private enum SettingsHelpTopic {
    case optionClickThrough
    case lowOpacityClickThrough

    var title: String {
        switch self {
        case .optionClickThrough:
            "Option 操作小组件"
        case .lowOpacityClickThrough:
            "低透明度自动允许 Option 操作"
        }
    }

    var message: String {
        switch self {
        case .optionClickThrough:
            "开启后，按住 Option 点击浮窗覆盖区域时仍操作小组件；关闭时，Option 点击会落到下层窗口。"
        case .lowOpacityClickThrough:
            "当透明度小于等于 32% 时，自动允许 Option 点击继续操作小组件。普通点击不受影响。"
        }
    }
}

private struct IconButtonStyle: ButtonStyle {
    let isActive: Bool
    let palette: WidgetPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? palette.accent : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isActive ? palette.accent.opacity(0.18) : palette.iconButtonFill(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct WidgetPalette: Equatable {
    let colorScheme: ColorScheme

    var isDark: Bool { colorScheme == .dark }
    var accent: Color { isDark ? Color(red: 0.55, green: 0.72, blue: 1.0) : Color(red: 0.05, green: 0.45, blue: 1.0) }
    var panelTop: Color { isDark ? Color(red: 0.12, green: 0.14, blue: 0.18) : Color(red: 0.86, green: 0.92, blue: 1.0) }
    var panelBottom: Color { isDark ? Color(red: 0.07, green: 0.09, blue: 0.12) : Color(red: 0.93, green: 0.97, blue: 1.0) }
    var segmentBackground: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.055) }
    var selectedSegment: Color { isDark ? Color.white.opacity(0.16) : Color.white.opacity(0.58) }
    var controlFill: Color { isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.42) }
    var controlStroke: Color { isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.42) }
    var completedRowFill: Color { isDark ? Color.white.opacity(0.04) : Color.white.opacity(0.18) }
    var borderTop: Color { isDark ? Color.white.opacity(0.22) : Color.white.opacity(0.58) }
    var borderBottom: Color { isDark ? Color.black.opacity(0.34) : Color.black.opacity(0.06) }
    var shadow: Color { Color.black.opacity(isDark ? 0.36 : 0.13) }

    func rowFill(isHovering: Bool) -> Color {
        isDark ? Color.white.opacity(isHovering ? 0.13 : 0.08) : Color.white.opacity(isHovering ? 0.56 : 0.36)
    }

    func rowStroke(isHovering: Bool) -> Color {
        isDark ? Color.white.opacity(isHovering ? 0.2 : 0.1) : Color.white.opacity(isHovering ? 0.56 : 0.28)
    }

    func iconButtonFill(isPressed: Bool) -> Color {
        isDark ? Color.white.opacity(isPressed ? 0.15 : 0.09) : Color.white.opacity(isPressed ? 0.56 : 0.32)
    }
}

private extension TodoAppearance {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    func resolvedColorScheme(_ systemColorScheme: ColorScheme) -> ColorScheme {
        preferredColorScheme ?? systemColorScheme
    }
}

private extension Color {
    init(widgetBackgroundColor: WidgetBackgroundColor) {
        self.init(
            red: widgetBackgroundColor.red,
            green: widgetBackgroundColor.green,
            blue: widgetBackgroundColor.blue,
            opacity: widgetBackgroundColor.opacity
        )
    }

    func blendedForPanelBottom(isDark: Bool) -> Color {
        let color = WidgetBackgroundColor(color: self)
        let target = isDark
            ? WidgetBackgroundColor(red: 0, green: 0, blue: 0)
            : WidgetBackgroundColor(red: 1, green: 1, blue: 1)
        return Color(widgetBackgroundColor: color.blended(with: target, amount: 0.18))
    }
}

private extension WidgetBackgroundColor {
    init(color: Color) {
        let nsColor = NSColor(color)
        let rgbColor = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(
            red: Double(rgbColor.redComponent),
            green: Double(rgbColor.greenComponent),
            blue: Double(rgbColor.blueComponent),
            opacity: Double(rgbColor.alphaComponent)
        )
    }

    func blended(with target: WidgetBackgroundColor, amount: Double) -> WidgetBackgroundColor {
        let ratio = min(1, max(0, amount))
        return WidgetBackgroundColor(
            red: red + (target.red - red) * ratio,
            green: green + (target.green - green) * ratio,
            blue: blue + (target.blue - blue) * ratio,
            opacity: opacity + (target.opacity - opacity) * ratio
        )
    }
}
