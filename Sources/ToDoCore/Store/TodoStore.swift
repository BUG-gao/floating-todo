import Foundation

@MainActor
public final class TodoStore: ObservableObject {
    @Published public private(set) var itemsByDay: [TodoDay: [TodoItem]]
    @Published public private(set) var recurringItems: [TodoItem]
    @Published public var selectedDay: TodoDay {
        didSet { persist() }
    }
    @Published public var settings: TodoSettings {
        didSet { persist() }
    }
    @Published public private(set) var memo: MemoState

    private let storage: UserDefaults
    private let storageKey: String
    private let calendar: Calendar
    private var lastActiveDate: Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        storage: UserDefaults = .standard,
        storageKey: String = "floating.todo.snapshot",
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.storage = storage
        self.storageKey = storageKey
        self.calendar = calendar

        let snapshot: TodoSnapshot
        let hasStoredSnapshot: Bool
        if
            let data = storage.data(forKey: storageKey),
            let decoded = try? decoder.decode(TodoSnapshot.self, from: data)
        {
            snapshot = decoded
            hasStoredSnapshot = true
        } else {
            snapshot = TodoSnapshot.empty
            hasStoredSnapshot = false
        }

        self.itemsByDay = TodoStore.normalizedItems(snapshot.itemsByDay)
        self.recurringItems = snapshot.recurringItems
        self.selectedDay = snapshot.selectedDay
        self.settings = snapshot.settings
        self.memo = snapshot.memo
        // 已有数据时按存储的基准日判断是否跨天；全新启动则把基准对齐到当前日期。
        self.lastActiveDate = hasStoredSnapshot
            ? calendar.startOfDay(for: snapshot.lastActiveDate)
            : calendar.startOfDay(for: now)

        // 跨天后把待办向前滚动，使「今天/明天/后天」始终对齐真实日期。
        rollOverIfNeeded(now: now)
    }

    public func items(for day: TodoDay? = nil) -> [TodoItem] {
        itemsByDay[day ?? selectedDay] ?? []
    }

    public func incompleteCount(for day: TodoDay? = nil) -> Int {
        items(for: day).filter { !$0.isCompleted }.count
    }

    public func completedCount(for day: TodoDay? = nil) -> Int {
        items(for: day).filter { $0.isCompleted }.count
    }

    /// 如果当前日期已经跨过上次对齐的日期，则把三个分组整体向前滚动。
    /// 过期分组里未完成的待办顺延到「今天」底部，已完成的丢弃。
    public func rollOverIfNeeded(now: Date = Date()) {
        let startOfToday = calendar.startOfDay(for: now)
        let dayDelta = calendar.dateComponents([.day], from: lastActiveDate, to: startOfToday).day ?? 0
        guard dayDelta > 0 else { return }

        itemsByDay = TodoStore.normalizedItems(TodoStore.rolledOver(items: itemsByDay, dayDelta: dayDelta))
        // 常态化待办每天重置为未完成，但内容保留。
        recurringItems = recurringItems.map { item in
            var reset = item
            reset.isCompleted = false
            reset.completedAt = nil
            return reset
        }
        lastActiveDate = startOfToday
        persist()
    }

    @discardableResult
    public func add(_ title: String, to day: TodoDay? = nil) -> TodoItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        let targetDay = day ?? selectedDay
        let item = TodoItem(title: trimmedTitle)
        itemsByDay[targetDay, default: []].insert(item, at: 0)
        persist()
        return item
    }

    public func updateTitle(id: TodoItem.ID, title: String, in day: TodoDay? = nil) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        mutateItem(id: id, in: day) { item in
            item.title = trimmedTitle
        }
    }

    public func updateDetail(id: TodoItem.ID, detail: String, in day: TodoDay? = nil) {
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateItem(id: id, in: day) { item in
            item.detail = trimmedDetail
        }
    }

    public func updateItem(id: TodoItem.ID, title: String, detail: String, in day: TodoDay? = nil) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateItem(id: id, in: day) { item in
            item.title = trimmedTitle
            item.detail = trimmedDetail
        }
    }

    public func toggle(id: TodoItem.ID, in day: TodoDay? = nil) {
        mutateItem(id: id, in: day) { item in
            item.isCompleted.toggle()
            item.completedAt = item.isCompleted ? Date() : nil
        }
        sortCompletedToBottom(in: day ?? selectedDay)
    }

    public func delete(id: TodoItem.ID, in day: TodoDay? = nil) {
        let targetDay = day ?? selectedDay
        itemsByDay[targetDay]?.removeAll { $0.id == id }
        persist()
    }

    public func move(from source: IndexSet, to destination: Int, in day: TodoDay? = nil) {
        let targetDay = day ?? selectedDay
        itemsByDay[targetDay, default: []].move(fromOffsets: source, toOffset: destination)
        persist()
    }

    public func moveItem(id: TodoItem.ID, from sourceDay: TodoDay, to targetDay: TodoDay) {
        guard sourceDay != targetDay, var sourceItems = itemsByDay[sourceDay] else { return }
        guard let index = sourceItems.firstIndex(where: { $0.id == id }) else { return }
        let item = sourceItems.remove(at: index)
        itemsByDay[sourceDay] = sourceItems
        itemsByDay[targetDay, default: []].insert(item, at: 0)
        persist()
    }

    public func clearCompleted(in day: TodoDay? = nil) {
        let targetDay = day ?? selectedDay
        itemsByDay[targetDay]?.removeAll { $0.isCompleted }
        persist()
    }

    // MARK: - 常态化「每天」待办

    public func recurringIncompleteCount() -> Int {
        recurringItems.filter { !$0.isCompleted }.count
    }

    @discardableResult
    public func addRecurring(_ title: String) -> TodoItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        let item = TodoItem(title: trimmedTitle)
        recurringItems.insert(item, at: 0)
        persist()
        return item
    }

    public func toggleRecurring(id: TodoItem.ID) {
        guard let index = recurringItems.firstIndex(where: { $0.id == id }) else { return }
        recurringItems[index].isCompleted.toggle()
        recurringItems[index].completedAt = recurringItems[index].isCompleted ? Date() : nil
        // 稳定分区：未完成在前、已完成在后。
        recurringItems = recurringItems.filter { !$0.isCompleted } + recurringItems.filter { $0.isCompleted }
        persist()
    }

    public func updateRecurringItem(id: TodoItem.ID, title: String, detail: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let index = recurringItems.firstIndex(where: { $0.id == id }) else { return }
        recurringItems[index].title = trimmedTitle
        recurringItems[index].detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    public func updateRecurringTitle(id: TodoItem.ID, title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let index = recurringItems.firstIndex(where: { $0.id == id }) else { return }
        recurringItems[index].title = trimmedTitle
        persist()
    }

    public func deleteRecurring(id: TodoItem.ID) {
        recurringItems.removeAll { $0.id == id }
        persist()
    }

    /// 把某条普通待办设为「每天」常驻，从原日期分组移入常态化列表。
    public func pinAsRecurring(id: TodoItem.ID, from day: TodoDay? = nil) {
        let sourceDay = day ?? selectedDay
        guard var dayItems = itemsByDay[sourceDay],
              let index = dayItems.firstIndex(where: { $0.id == id }) else { return }
        var item = dayItems.remove(at: index)
        item.isCompleted = false
        item.completedAt = nil
        itemsByDay[sourceDay] = dayItems
        recurringItems.insert(item, at: 0)
        persist()
    }

    /// 取消「每天」常驻，移回「今天」普通列表。
    public func unpinRecurring(id: TodoItem.ID) {
        guard let index = recurringItems.firstIndex(where: { $0.id == id }) else { return }
        let item = recurringItems.remove(at: index)
        itemsByDay[.today, default: []].insert(item, at: 0)
        persist()
    }

    public func setMemoEnabled(_ isEnabled: Bool) {
        settings.memoEnabled = isEnabled
        if isEnabled {
            memo.isExpanded = true
        }
        persist()
    }

    public func setMemoExpanded(_ isExpanded: Bool) {
        memo.isExpanded = isExpanded
        persist()
    }

    public func updateMemoText(_ text: String) {
        memo.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    public func updateCustomBackgroundColor(_ color: WidgetBackgroundColor) {
        settings.customBackgroundColor = color
    }

    public func clearCustomBackgroundColor() {
        settings.customBackgroundColor = nil
    }

    public func reset(snapshot: TodoSnapshot = .empty) {
        selectedDay = snapshot.selectedDay
        itemsByDay = TodoStore.normalizedItems(snapshot.itemsByDay)
        recurringItems = snapshot.recurringItems
        settings = snapshot.settings
        memo = snapshot.memo
        persist()
    }

    private func mutateItem(id: TodoItem.ID, in day: TodoDay?, mutation: (inout TodoItem) -> Void) {
        let targetDay = day ?? selectedDay
        guard var items = itemsByDay[targetDay] else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutation(&items[index])
        itemsByDay[targetDay] = items
        persist()
    }

    private func sortCompletedToBottom(in day: TodoDay) {
        guard let items = itemsByDay[day] else { return }
        // 稳定分区：未完成在前、已完成在后，两组内部都保留用户的手动顺序。
        itemsByDay[day] = items.filter { !$0.isCompleted } + items.filter { $0.isCompleted }
        persist()
    }

    private func persist() {
        let snapshot = TodoSnapshot(
            selectedDay: selectedDay,
            itemsByDay: itemsByDay,
            recurringItems: recurringItems,
            settings: settings,
            memo: memo,
            lastActiveDate: lastActiveDate
        )
        guard let data = try? encoder.encode(snapshot) else { return }
        storage.set(data, forKey: storageKey)
    }

    /// 把三个分组整体向前滚动 `dayDelta` 天的纯函数实现，便于单元测试。
    static func rolledOver(items: [TodoDay: [TodoItem]], dayDelta: Int) -> [TodoDay: [TodoItem]] {
        guard dayDelta > 0 else { return items }
        let offsets: [TodoDay: Int] = [.today: 0, .tomorrow: 1, .dayAfterTomorrow: 2]
        var result: [TodoDay: [TodoItem]] = Dictionary(uniqueKeysWithValues: TodoDay.allCases.map { ($0, []) })
        var carriedOverdue: [TodoItem] = []

        for day in TodoDay.allCases {
            let dayItems = items[day] ?? []
            let newOffset = (offsets[day] ?? 0) - dayDelta
            if newOffset >= 0, let targetDay = offsets.first(where: { $0.value == newOffset })?.key {
                result[targetDay, default: []].append(contentsOf: dayItems)
            } else {
                // 过期分组：未完成顺延，已完成丢弃。
                carriedOverdue.append(contentsOf: dayItems.filter { !$0.isCompleted })
            }
        }

        // 过期未完成的待办排在「今天」新内容的下方。
        result[.today] = (result[.today] ?? []) + carriedOverdue
        return result
    }

    private static func normalizedItems(_ items: [TodoDay: [TodoItem]]) -> [TodoDay: [TodoItem]] {
        var result = items
        TodoDay.allCases.forEach { day in
            result[day] = result[day] ?? []
        }
        return result
    }
}

private extension Array {
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { self[$0] }
        remove(atOffsets: source)
        insert(contentsOf: moving, at: Swift.min(destination, count))
    }

    mutating func remove(atOffsets offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            remove(at: offset)
        }
    }
}
