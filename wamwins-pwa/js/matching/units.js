// Same conversions as the reference UnitConverter (src/modules/catalog/domain/UnitConverter.ts), over the
// generated reference data. Returns undefined when no conversion exists.
export class UnitConverter {
  constructor(ref) {
    this.units = new Map(ref.units.map(([code, dimension, base, factor]) => [code, { dimension, base, factor }]));
    this.conv = new Map();
    for (const [item, from, to, factor] of ref.conversions) {
      if (!this.conv.has(item)) this.conv.set(item, []);
      this.conv.get(item).push({ from, to, factor });
    }
  }
  toBase(qty, code) {
    const u = this.units.get(code);
    if (!u) return undefined;
    return { qty: u.base ? qty * u.factor : qty, base: u.base ?? code };
  }
  convert(qty, from, to, itemId) {
    if (from === to) return qty;
    const a = this.toBase(qty, from), b = this.toBase(1, to);
    if (!a || !b) return undefined;
    if (a.base === b.base) return a.qty / b.qty;
    if (!itemId) return undefined;
    for (const c of this.conv.get(itemId) ?? []) {
      const viaFrom = this.toBase(1, c.from), viaTo = this.toBase(1, c.to);
      if (!viaFrom || !viaTo) continue;
      if (viaFrom.base === a.base && viaTo.base === b.base) return (a.qty / viaFrom.qty) * c.factor * viaTo.qty / b.qty;
      if (viaTo.base === a.base && viaFrom.base === b.base) return (a.qty / viaTo.qty) / c.factor * viaFrom.qty / b.qty;
    }
    return undefined;
  }
  toMassOrVolume(qty, unit, itemId) {
    const g = this.convert(qty, unit, 'G', itemId);
    if (g !== undefined) return { amount: g, basis: 'G' };
    const ml = this.convert(qty, unit, 'ML', itemId);
    return ml !== undefined ? { amount: ml, basis: 'ML' } : undefined;
  }
}
