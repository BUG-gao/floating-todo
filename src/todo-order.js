// Keep completed todos at the bottom, preserving manual order in both groups.
export function reorderItems(items, orderedIds) {
  const byId = new Map(items.map((item) => [item.id, item]));
  if (orderedIds.length !== items.length || new Set(orderedIds).size !== items.length ||
      orderedIds.some((id) => !byId.has(id))) return items;
  const ordered = orderedIds.map((id) => byId.get(id));
  return [...ordered.filter((item) => !item.completed), ...ordered.filter((item) => item.completed)];
}
