# Global Memo Drawer Design

## Goal

Add an optional global memo drawer to the floating todo widget.

## Requirements

- The memo feature is disabled by default.
- Settings can enable or disable the memo feature.
- When the user enables the memo feature, the memo drawer opens by default.
- The memo is a single global note. It does not change when the user switches between 今天, 明天, and 后天.
- The user can manually collapse or expand the memo drawer. That state persists.
- Memo text is edited inline in a multiline editor and persisted automatically.
- The memo uses the same visual language as the existing floating todo widget: shared panel, restrained color, same material style, same rounded component vocabulary.

## Architecture

- Store memo state in `TodoSnapshot` beside existing items and settings.
- Add `MemoState` for global memo content and expansion state.
- Add a `memoEnabled` setting to `TodoSettings`.
- Keep one `NSPanel`; render the memo drawer inside `FloatingTodoWidget` under the existing todo content.

## Testing

- Verify legacy snapshots decode with memo disabled and empty global memo.
- Verify enabling memo sets the drawer expanded.
- Verify memo text persists across `TodoStore` instances.
