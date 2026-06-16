import Foundation

public enum TodoDay: String, Codable, CaseIterable, Identifiable, Sendable {
    case today
    case tomorrow
    case dayAfterTomorrow

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today:
            "今天"
        case .tomorrow:
            "明天"
        case .dayAfterTomorrow:
            "后天"
        }
    }

    public var shortTitle: String {
        switch self {
        case .today:
            "今"
        case .tomorrow:
            "明"
        case .dayAfterTomorrow:
            "后"
        }
    }

    public func date(relativeTo baseDate: Date = Date(), calendar: Calendar = .current) -> Date {
        let offset: Int
        switch self {
        case .today:
            offset = 0
        case .tomorrow:
            offset = 1
        case .dayAfterTomorrow:
            offset = 2
        }
        return calendar.date(byAdding: .day, value: offset, to: baseDate) ?? baseDate
    }
}

public struct TodoItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var detail: String
    public var isCompleted: Bool
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String = "",
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case isCompleted
        case createdAt
        case completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

public struct TodoSettings: Codable, Equatable, Sendable {
    public var alwaysOnTop: Bool
    public var visibleOnAllSpaces: Bool
    public var opacity: Double
    public var appearance: TodoAppearance
    public var clickThrough: Bool
    public var autoClickThroughAtLowOpacity: Bool
    public var memoEnabled: Bool
    public var customBackgroundColor: WidgetBackgroundColor?

    public init(
        alwaysOnTop: Bool = true,
        visibleOnAllSpaces: Bool = true,
        opacity: Double = 0.72,
        appearance: TodoAppearance = .system,
        clickThrough: Bool = false,
        autoClickThroughAtLowOpacity: Bool = false,
        memoEnabled: Bool = false,
        customBackgroundColor: WidgetBackgroundColor? = nil
    ) {
        self.alwaysOnTop = alwaysOnTop
        self.visibleOnAllSpaces = visibleOnAllSpaces
        self.opacity = opacity
        self.appearance = appearance
        self.clickThrough = clickThrough
        self.autoClickThroughAtLowOpacity = autoClickThroughAtLowOpacity
        self.memoEnabled = memoEnabled
        self.customBackgroundColor = customBackgroundColor
    }

    private enum CodingKeys: String, CodingKey {
        case alwaysOnTop
        case visibleOnAllSpaces
        case opacity
        case appearance
        case clickThrough
        case autoClickThroughAtLowOpacity
        case memoEnabled
        case customBackgroundColor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? true
        visibleOnAllSpaces = try container.decodeIfPresent(Bool.self, forKey: .visibleOnAllSpaces) ?? true
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.72
        appearance = try container.decodeIfPresent(TodoAppearance.self, forKey: .appearance) ?? .system
        clickThrough = try container.decodeIfPresent(Bool.self, forKey: .clickThrough) ?? false
        autoClickThroughAtLowOpacity = try container.decodeIfPresent(Bool.self, forKey: .autoClickThroughAtLowOpacity) ?? false
        memoEnabled = try container.decodeIfPresent(Bool.self, forKey: .memoEnabled) ?? false
        customBackgroundColor = try container.decodeIfPresent(WidgetBackgroundColor.self, forKey: .customBackgroundColor)
    }

    public var effectiveOptionClickInsideWidget: Bool {
        clickThrough || (autoClickThroughAtLowOpacity && opacity <= 0.32)
    }

    public var effectiveClickThrough: Bool {
        effectiveOptionClickInsideWidget
    }
}

public struct WidgetBackgroundColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = WidgetBackgroundColor.clamped(red)
        self.green = WidgetBackgroundColor.clamped(green)
        self.blue = WidgetBackgroundColor.clamped(blue)
        self.opacity = WidgetBackgroundColor.clamped(opacity)
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public enum TodoAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system:
            "跟随系统"
        case .light:
            "浅色"
        case .dark:
            "深色"
        }
    }
}

public struct MemoState: Codable, Equatable, Sendable {
    public var text: String
    public var isExpanded: Bool

    public init(text: String = "", isExpanded: Bool = false) {
        self.text = text
        self.isExpanded = isExpanded
    }
}

public struct TodoSnapshot: Codable, Equatable, Sendable {
    public var selectedDay: TodoDay
    public var itemsByDay: [TodoDay: [TodoItem]]
    /// 常态化「每天」待办：固定显示在今天顶部，跨天不滚走、不被清除，每天自动重置为未完成。
    public var recurringItems: [TodoItem]
    public var settings: TodoSettings
    public var memo: MemoState
    /// 上次对齐「今天/明天/后天」三个分组时所基于的日期。用于在跨天后把待办向前滚动。
    public var lastActiveDate: Date

    public init(
        selectedDay: TodoDay = .today,
        itemsByDay: [TodoDay: [TodoItem]] = [:],
        recurringItems: [TodoItem] = [],
        settings: TodoSettings = TodoSettings(),
        memo: MemoState = MemoState(),
        lastActiveDate: Date = Date()
    ) {
        self.selectedDay = selectedDay
        self.itemsByDay = itemsByDay
        self.recurringItems = recurringItems
        self.settings = settings
        self.memo = memo
        self.lastActiveDate = lastActiveDate
    }

    private enum CodingKeys: String, CodingKey {
        case selectedDay
        case itemsByDay
        case recurringItems
        case settings
        case memo
        case lastActiveDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedDay = try container.decodeIfPresent(TodoDay.self, forKey: .selectedDay) ?? .today
        itemsByDay = try container.decodeIfPresent([TodoDay: [TodoItem]].self, forKey: .itemsByDay) ?? [:]
        recurringItems = try container.decodeIfPresent([TodoItem].self, forKey: .recurringItems) ?? []
        settings = try container.decodeIfPresent(TodoSettings.self, forKey: .settings) ?? TodoSettings()
        memo = try container.decodeIfPresent(MemoState.self, forKey: .memo) ?? MemoState()
        lastActiveDate = try container.decodeIfPresent(Date.self, forKey: .lastActiveDate) ?? Date()
    }

    public static var empty: TodoSnapshot {
        TodoSnapshot(
            itemsByDay: Dictionary(uniqueKeysWithValues: TodoDay.allCases.map { ($0, []) })
        )
    }
}
