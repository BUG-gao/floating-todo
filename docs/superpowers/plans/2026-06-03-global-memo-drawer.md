# Global Memo Drawer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, global memo drawer below the existing floating todo widget.

**Architecture:** Persist memo enablement in `TodoSettings` and memo content/expanded state in `TodoSnapshot`. Keep the existing single `NSPanel` and render the drawer inside `FloatingTodoWidget` so window movement, Space behavior, opacity, and Option-click behavior remain consistent.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, XCTest, UserDefaults JSON persistence.

---

### Task 1: Store Model And Persistence

**Files:**
- Modify: `Sources/ToDoCore/Models/TodoModels.swift`
- Modify: `Sources/ToDoCore/Store/TodoStore.swift`
- Test: `Tests/ToDoCoreTests/TodoStoreTests.swift`

- [ ] Add tests for legacy decode, enabling default expansion, and memo text persistence.
- [ ] Run `swift test --filter TodoStoreTests` and verify the new tests fail because memo APIs do not exist yet.
- [ ] Add `MemoState`, `TodoSettings.memoEnabled`, and `TodoSnapshot.memo`.
- [ ] Add `TodoStore.updateMemoText(_:)`, `setMemoEnabled(_:)`, and `setMemoExpanded(_:)`.
- [ ] Run `swift test --filter TodoStoreTests` and verify the store tests pass.

### Task 2: Memo Drawer UI

**Files:**
- Modify: `Sources/ToDoCore/UI/FloatingTodoWidget.swift`

- [ ] Render a unified memo drawer below the existing todo area only when `store.settings.memoEnabled` is true.
- [ ] Use the same palette, material opacity, rounded controls, and icon vocabulary as the current widget.
- [ ] Use multiline inline editing with automatic persistence through `store.updateMemoText(_:)`.
- [ ] Add expand/collapse control that calls `store.setMemoExpanded(_:)`.

### Task 3: Settings And Window Sizing

**Files:**
- Modify: `Sources/ToDoCore/UI/FloatingTodoWidget.swift`
- Modify: `Sources/ToDoCore/App/FloatingPanelController.swift`

- [ ] Add a settings toggle labeled `开启备忘录`.
- [ ] Increase default and maximum panel height enough to show the memo drawer without cramped content.
- [ ] Keep compact behavior focused on today-only todo content.

### Task 4: Verification

**Files:**
- All changed Swift files.

- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Inspect the diff for unrelated changes.
