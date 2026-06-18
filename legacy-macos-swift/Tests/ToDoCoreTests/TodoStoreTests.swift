import XCTest
@testable import ToDoCore

final class TodoStoreTests: XCTestCase {
    private let storageKey = "test.todo.snapshot"

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "TodoStoreTests.\(UUID().uuidString)")!
        defaults.removeObject(forKey: storageKey)
        return defaults
    }

    @MainActor
    func testAddTrimsWhitespaceAndIgnoresEmptyTitles() {
        let defaults = makeDefaults()
        let store = TodoStore(storage: defaults, storageKey: storageKey)

        let item = store.add("  归档笔记  ")
        let emptyItem = store.add("   ")

        XCTAssertEqual(store.items().map(\.title), ["归档笔记"])
        XCTAssertEqual(store.incompleteCount(), 1)
        XCTAssertEqual(item?.id, store.items().first?.id)
        XCTAssertNil(emptyItem)
    }

    @MainActor
    func testTasksAreSeparatedByDay() {
        let defaults = makeDefaults()
        let store = TodoStore(storage: defaults, storageKey: storageKey)

        store.add("今天任务", to: .today)
        store.add("明天任务", to: .tomorrow)
        store.add("后天任务", to: .dayAfterTomorrow)

        XCTAssertEqual(store.items(for: .today).map(\.title), ["今天任务"])
        XCTAssertEqual(store.items(for: .tomorrow).map(\.title), ["明天任务"])
        XCTAssertEqual(store.items(for: .dayAfterTomorrow).map(\.title), ["后天任务"])
    }

    @MainActor
    func testToggleCompletesTaskAndMovesItBelowOpenTasks() {
        let defaults = makeDefaults()
        let store = TodoStore(storage: defaults, storageKey: storageKey)
        store.add("先完成", to: .today)
        store.add("还没完成", to: .today)

        let firstCreatedTask = store.items(for: .today).last!
        store.toggle(id: firstCreatedTask.id, in: .today)

        let items = store.items(for: .today)
        XCTAssertEqual(items.first?.title, "还没完成")
        XCTAssertEqual(items.last?.title, "先完成")
        XCTAssertTrue(items.last?.isCompleted == true)
        XCTAssertNotNil(items.last?.completedAt)
    }

    @MainActor
    func testUpdateTitleAndDelete() {
        let defaults = makeDefaults()
        let store = TodoStore(storage: defaults, storageKey: storageKey)
        store.add("旧标题")

        let id = store.items().first!.id
        store.updateTitle(id: id, title: " 新标题 ")
        XCTAssertEqual(store.items().first?.title, "新标题")

        store.delete(id: id)
        XCTAssertTrue(store.items().isEmpty)
    }

    @MainActor
    func testUpdateItemDetail() {
        let defaults = makeDefaults()
        let store = TodoStore(storage: defaults, storageKey: storageKey)
        store.add("10:00 日程确认")

        let id = store.items().first!.id
        store.updateItem(id: id, title: "10:00 日程确认", detail: "确认今日安排")

        XCTAssertEqual(store.items().first?.title, "10:00 日程确认")
        XCTAssertEqual(store.items().first?.detail, "确认今日安排")

        store.updateDetail(id: id, detail: "   ")
        XCTAssertEqual(store.items().first?.detail, "")
    }

    @MainActor
    func testMoveItemBetweenDays() {
        let defaults = makeDefaults()
        let store = TodoStore(storage: defaults, storageKey: storageKey)
        store.add("移动我", to: .today)

        let id = store.items(for: .today).first!.id
        store.moveItem(id: id, from: .today, to: .tomorrow)

        XCTAssertTrue(store.items(for: .today).isEmpty)
        XCTAssertEqual(store.items(for: .tomorrow).map(\.title), ["移动我"])
    }

    @MainActor
    func testPersistsSnapshotAcrossStoreInstances() {
        let defaults = makeDefaults()
        let firstStore = TodoStore(storage: defaults, storageKey: storageKey)
        firstStore.selectedDay = .tomorrow
        firstStore.add("明天写方案")
        firstStore.settings = TodoSettings(
            alwaysOnTop: false,
            visibleOnAllSpaces: false,
            opacity: 0.28,
            appearance: .dark
        )

        let secondStore = TodoStore(storage: defaults, storageKey: storageKey)

        XCTAssertEqual(secondStore.selectedDay, .tomorrow)
        XCTAssertEqual(secondStore.items().map(\.title), ["明天写方案"])
        XCTAssertEqual(
            secondStore.settings,
            TodoSettings(alwaysOnTop: false, visibleOnAllSpaces: false, opacity: 0.28, appearance: .dark)
        )
    }

    func testSettingsDecodeLegacyPayloadWithoutAppearance() throws {
        let json = """
        {
          "alwaysOnTop": false,
          "visibleOnAllSpaces": true,
          "opacity": 0.24
        }
        """

        let settings = try JSONDecoder().decode(TodoSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.alwaysOnTop, false)
        XCTAssertEqual(settings.visibleOnAllSpaces, true)
        XCTAssertEqual(settings.opacity, 0.24)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.clickThrough, false)
        XCTAssertEqual(settings.autoClickThroughAtLowOpacity, false)
        XCTAssertEqual(settings.memoEnabled, false)
        XCTAssertNil(settings.customBackgroundColor)
    }

    func testSettingsDecodeCustomBackgroundColor() throws {
        let json = """
        {
          "customBackgroundColor": {
            "red": 0.2,
            "green": 0.4,
            "blue": 0.6,
            "opacity": 1.0
          }
        }
        """

        let settings = try JSONDecoder().decode(TodoSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.customBackgroundColor, WidgetBackgroundColor(red: 0.2, green: 0.4, blue: 0.6, opacity: 1.0))
    }

    @MainActor
    func testCustomBackgroundColorPersistsAcrossStoreInstances() {
        let defaults = makeDefaults()
        let firstStore = TodoStore(storage: defaults, storageKey: storageKey)
        let color = WidgetBackgroundColor(red: 0.15, green: 0.34, blue: 0.72, opacity: 1.0)

        firstStore.updateCustomBackgroundColor(color)

        let secondStore = TodoStore(storage: defaults, storageKey: storageKey)

        XCTAssertEqual(secondStore.settings.customBackgroundColor, color)
    }

    @MainActor
    func testClearingCustomBackgroundColorRestoresDefault() {
        let defaults = makeDefaults()
        let store = TodoStore(storage: defaults, storageKey: storageKey)

        store.updateCustomBackgroundColor(WidgetBackgroundColor(red: 0.15, green: 0.34, blue: 0.72))
        store.clearCustomBackgroundColor()

        XCTAssertNil(store.settings.customBackgroundColor)
    }

    func testSnapshotDecodeLegacyPayloadWithoutMemo() throws {
        let json = """
        {}
        """

        let snapshot = try JSONDecoder().decode(TodoSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.memo, MemoState())
        XCTAssertFalse(snapshot.settings.memoEnabled)
    }

    @MainActor
    func testEnablingMemoExpandsDrawerByDefault() {
        let defaults = makeDefaults()
        let store = TodoStore(storage: defaults, storageKey: storageKey)

        XCTAssertFalse(store.settings.memoEnabled)
        XCTAssertFalse(store.memo.isExpanded)

        store.setMemoEnabled(true)

        XCTAssertTrue(store.settings.memoEnabled)
        XCTAssertTrue(store.memo.isExpanded)
    }

    @MainActor
    func testMemoTextPersistsAcrossStoreInstances() {
        let defaults = makeDefaults()
        let firstStore = TodoStore(storage: defaults, storageKey: storageKey)

        firstStore.setMemoEnabled(true)
        firstStore.updateMemoText("  参考编号 0000\n临时参考链接  ")
        firstStore.setMemoExpanded(false)

        let secondStore = TodoStore(storage: defaults, storageKey: storageKey)

        XCTAssertTrue(secondStore.settings.memoEnabled)
        XCTAssertEqual(secondStore.memo.text, "参考编号 0000\n临时参考链接")
        XCTAssertFalse(secondStore.memo.isExpanded)
    }

    func testOptionClickInsideWidgetSettingsResolution() {
        XCTAssertFalse(TodoSettings(opacity: 0.72).effectiveOptionClickInsideWidget)
        XCTAssertTrue(TodoSettings(opacity: 0.72, clickThrough: true).effectiveOptionClickInsideWidget)
        XCTAssertFalse(TodoSettings(opacity: 0.33, autoClickThroughAtLowOpacity: true).effectiveOptionClickInsideWidget)
        XCTAssertTrue(TodoSettings(opacity: 0.32, autoClickThroughAtLowOpacity: true).effectiveOptionClickInsideWidget)
    }

    func testTodoItemDecodeLegacyPayloadWithoutDetail() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "title": "旧任务",
          "isCompleted": false,
          "createdAt": 802000000
        }
        """

        let item = try JSONDecoder().decode(TodoItem.self, from: Data(json.utf8))

        XCTAssertEqual(item.title, "旧任务")
        XCTAssertEqual(item.detail, "")
        XCTAssertEqual(item.isCompleted, false)
    }

    @MainActor
    func testClearCompletedRemovesOnlyCompletedItems() {
        let defaults = makeDefaults()
        let store = TodoStore(storage: defaults, storageKey: storageKey)
        store.add("已完成的事", to: .today)
        store.add("还没做的事", to: .today)

        let doneID = store.items(for: .today).first { $0.title == "已完成的事" }!.id
        store.toggle(id: doneID, in: .today)
        XCTAssertEqual(store.completedCount(for: .today), 1)

        store.clearCompleted(in: .today)

        XCTAssertEqual(store.completedCount(for: .today), 0)
        XCTAssertEqual(store.items(for: .today).map(\.title), ["还没做的事"])
    }

    @MainActor
    func testToggleKeepsManualOrderWithinGroups() {
        let defaults = makeDefaults()
        let store = TodoStore(storage: defaults, storageKey: storageKey)
        // 顶部插入，最终顺序为 [C, B, A]
        store.add("A", to: .today)
        store.add("B", to: .today)
        store.add("C", to: .today)

        let itemB = store.items(for: .today).first { $0.title == "B" }!
        store.toggle(id: itemB.id, in: .today)

        // B 沉到底部，未完成组保留手动顺序 [C, A]
        XCTAssertEqual(store.items(for: .today).map(\.title), ["C", "A", "B"])
    }

    @MainActor
    func testRollOverShiftsDaysAndCarriesOverdueToTodayBottom() {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = Date(timeIntervalSince1970: 1_700_000_000) // 基准日
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!

        let defaults = makeDefaults()
        let firstStore = TodoStore(storage: defaults, storageKey: storageKey, now: day1, calendar: calendar)
        firstStore.add("今天-未完成", to: .today)
        firstStore.add("今天-已完成", to: .today)
        firstStore.add("明天的事", to: .tomorrow)
        firstStore.add("后天的事", to: .dayAfterTomorrow)

        let doneID = firstStore.items(for: .today).first { $0.title == "今天-已完成" }!.id
        firstStore.toggle(id: doneID, in: .today)

        // 第二天重新打开，应整体向前滚动一天
        let secondStore = TodoStore(storage: defaults, storageKey: storageKey, now: day2, calendar: calendar)

        // 明天的事 → 今天（顶部），过期未完成顺延到今天底部，已完成丢弃
        XCTAssertEqual(secondStore.items(for: .today).map(\.title), ["明天的事", "今天-未完成"])
        XCTAssertEqual(secondStore.items(for: .tomorrow).map(\.title), ["后天的事"])
        XCTAssertTrue(secondStore.items(for: .dayAfterTomorrow).isEmpty)
    }

    @MainActor
    func testRollOverThreeOrMoreDaysCollapsesAllIncompleteToToday() {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day4 = calendar.date(byAdding: .day, value: 4, to: day1)!

        let defaults = makeDefaults()
        let firstStore = TodoStore(storage: defaults, storageKey: storageKey, now: day1, calendar: calendar)
        firstStore.add("今天事", to: .today)
        firstStore.add("明天事", to: .tomorrow)
        firstStore.add("后天事", to: .dayAfterTomorrow)

        let secondStore = TodoStore(storage: defaults, storageKey: storageKey, now: day4, calendar: calendar)

        XCTAssertEqual(Set(secondStore.items(for: .today).map(\.title)), ["今天事", "明天事", "后天事"])
        XCTAssertTrue(secondStore.items(for: .tomorrow).isEmpty)
        XCTAssertTrue(secondStore.items(for: .dayAfterTomorrow).isEmpty)
    }

    @MainActor
    func testNoRollOverWithinSameDay() {
        let calendar = Calendar(identifier: .gregorian)
        let morning = Date(timeIntervalSince1970: 1_700_000_000)
        let evening = morning.addingTimeInterval(8 * 3600)

        let defaults = makeDefaults()
        let firstStore = TodoStore(storage: defaults, storageKey: storageKey, now: morning, calendar: calendar)
        firstStore.add("今天事", to: .today)
        firstStore.add("明天事", to: .tomorrow)

        let secondStore = TodoStore(storage: defaults, storageKey: storageKey, now: evening, calendar: calendar)

        XCTAssertEqual(secondStore.items(for: .today).map(\.title), ["今天事"])
        XCTAssertEqual(secondStore.items(for: .tomorrow).map(\.title), ["明天事"])
    }

    @MainActor
    func testPinAndUnpinRecurring() {
        let defaults = makeDefaults()
        let store = TodoStore(storage: defaults, storageKey: storageKey)
        store.add("每天整理资料", to: .today)

        let id = store.items(for: .today).first!.id
        store.pinAsRecurring(id: id, from: .today)

        XCTAssertTrue(store.items(for: .today).isEmpty)
        XCTAssertEqual(store.recurringItems.map(\.title), ["每天整理资料"])

        store.unpinRecurring(id: id)
        XCTAssertEqual(store.items(for: .today).map(\.title), ["每天整理资料"])
        XCTAssertTrue(store.recurringItems.isEmpty)
    }

    @MainActor
    func testRecurringResetsCompletionOnNewDayButKeepsContent() {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!

        let defaults = makeDefaults()
        let firstStore = TodoStore(storage: defaults, storageKey: storageKey, now: day1, calendar: calendar)
        firstStore.addRecurring("喝水")
        let id = firstStore.recurringItems.first!.id
        firstStore.toggleRecurring(id: id)
        XCTAssertTrue(firstStore.recurringItems.first!.isCompleted)

        let secondStore = TodoStore(storage: defaults, storageKey: storageKey, now: day2, calendar: calendar)

        XCTAssertEqual(secondStore.recurringItems.map(\.title), ["喝水"])
        XCTAssertFalse(secondStore.recurringItems.first!.isCompleted)
    }

    @MainActor
    func testRecurringNotAffectedByDayRollOver() {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!

        let defaults = makeDefaults()
        let firstStore = TodoStore(storage: defaults, storageKey: storageKey, now: day1, calendar: calendar)
        firstStore.addRecurring("每天复盘")
        firstStore.add("明天的事", to: .tomorrow)

        let secondStore = TodoStore(storage: defaults, storageKey: storageKey, now: day2, calendar: calendar)

        // 常驻待办留在常驻列表，不会被滚进某一天
        XCTAssertEqual(secondStore.recurringItems.map(\.title), ["每天复盘"])
        XCTAssertEqual(secondStore.items(for: .today).map(\.title), ["明天的事"])
    }

    @MainActor
    func testRecurringPersistsAndTrimsEmpty() {
        let defaults = makeDefaults()
        let firstStore = TodoStore(storage: defaults, storageKey: storageKey)
        firstStore.addRecurring("  检查待办清单  ")
        XCTAssertNil(firstStore.addRecurring("   "))

        let secondStore = TodoStore(storage: defaults, storageKey: storageKey)
        XCTAssertEqual(secondStore.recurringItems.map(\.title), ["检查待办清单"])
    }

    func testSnapshotDecodeLegacyPayloadWithoutRecurring() throws {
        let snapshot = try JSONDecoder().decode(TodoSnapshot.self, from: Data("{}".utf8))
        XCTAssertTrue(snapshot.recurringItems.isEmpty)
    }

    @MainActor
    func testSimulatedUserFlow() {
        let defaults = makeDefaults()
        let store = TodoStore(storage: defaults, storageKey: storageKey)

        store.add("整理收件箱")
        store.add("整理需求清单")
        store.selectedDay = .tomorrow
        store.add("设计悬浮窗视觉")
        store.selectedDay = .today

        let doneTask = store.items().first { $0.title == "整理收件箱" }!
        store.toggle(id: doneTask.id)

        let movedTask = store.items().first { $0.title == "整理需求清单" }!
        store.moveItem(id: movedTask.id, from: .today, to: .dayAfterTomorrow)

        XCTAssertEqual(store.incompleteCount(for: .today), 0)
        XCTAssertEqual(store.items(for: .today).filter(\.isCompleted).map(\.title), ["整理收件箱"])
        XCTAssertEqual(store.items(for: .tomorrow).map(\.title), ["设计悬浮窗视觉"])
        XCTAssertEqual(store.items(for: .dayAfterTomorrow).map(\.title), ["整理需求清单"])
    }
}
