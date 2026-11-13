// Families cheapest first. A model in none of them ranks above them all, so a
// new family reads as pricier until it is added here.
const PRICE_ORDER = ['haiku', 'sonnet', 'opus', 'fable']

/** Whether `model` is `standard`, either one an alias or part of the other's id. */
export function isModel(model: string, standard: string): boolean {
  const [a, b] = [model.toLowerCase(), standard.toLowerCase()]
  return a.includes(b) || b.includes(a)
}

function priceRank(model: string): number {
  const rank = PRICE_ORDER.findIndex(family => model.toLowerCase().includes(family))
  return rank === -1 ? PRICE_ORDER.length : rank
}

/** `claude-fable-5-2` reads `FABLE 5.2`; an alias reads in capitals. */
export function displayName(model: string): string {
  return model
    .replace(/\[[^\]]*\]$/, '')
    .replace(/-\d{8}$/, '')
    .replace(/^claude-/, '')
    .replace(/-(\d+)-(\d+)$/, ' $1.$2')
    .replace(/-/g, ' ')
    .toUpperCase()
}

export function costAgainst(model: string, standard: string): 'more' | 'same' | 'less' {
  const [rank, standardRank] = [priceRank(model), priceRank(standard)]
  return rank > standardRank ? 'more' : rank < standardRank ? 'less' : 'same'
}
