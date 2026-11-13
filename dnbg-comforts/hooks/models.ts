// Families cheapest first. A model in none of them ranks above them all, so a
// new family reads as pricier until it is added here.
const PRICE_ORDER = ['haiku', 'sonnet', 'opus', 'fable']

export function isModel(model: string, standard: string): boolean {
  return model.toLowerCase().includes(standard.toLowerCase())
}

export function priceRank(model: string): number {
  const rank = PRICE_ORDER.findIndex(family => model.toLowerCase().includes(family))
  return rank === -1 ? PRICE_ORDER.length : rank
}

/** `claude-fable-5-2` reads `FABLE 5.2`; an alias reads in capitals. */
export function displayName(model: string): string {
  return model
    .replace(/^claude-/, '')
    .replace(/-(\d+)-(\d+)$/, ' $1.$2')
    .replace(/-/g, ' ')
    .toUpperCase()
}
