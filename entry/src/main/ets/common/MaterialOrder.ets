export function materialOrder(defaultIds: string[], savedIds: string[]): string[] {
  const ordered: string[] = [];
  for (const id of savedIds.concat(defaultIds)) {
    if (id && defaultIds.includes(id) && !ordered.includes(id)) ordered.push(id);
  }
  return ordered;
}

export function moveVisibleMaterial(order: string[], visible: string[], from: number, to: number): string[] {
  if (!Number.isInteger(from) || !Number.isInteger(to) || from < 0 || to < 0 ||
    from >= visible.length || to >= visible.length || from === to) return order;
  const moved = visible.slice();
  const id = moved.splice(from, 1)[0];
  moved.splice(to, 0, id);
  let next = 0;
  return order.map((id: string) => visible.includes(id) ? moved[next++] : id);
}
