# SHELF LIFE — Monetization Set (pinned rule 8, required before release gate)

## Revenue model
Primary: **rewarded video (portal SDK)** on two levers, both wired to `ShelfState`
hooks already shipped:
1. **Hint** — "Highlight one rule-breaking item" (`use_hint()`, 3 free/day,
   then watch-ad for +1). Placement is earned frustration relief — the classic
   arrange-game ad moment.
2. **Skip delivery** — "Send one box back" (`skip_delivery()`, 1/day free,
   then watch-ad). Removes a hard constraint conflict.

Interstitials: NONE at this stage. The game's core loop is 60-90s; an interstitial
per level would read as "second job simulator" hostility (pulse vibe risk).
Revisit only if D1 retention supports it.

Secondary (later, non-blocking): cosmetic shelf skins / badge frame themes as a
one-time purchase or portal storefront item. Zero gameplay impact, keeps the
"tidy satisfaction" fantasy clean.

## Genre benchmarks (constraint-sort / goods-arrangement class)
- Supermarket Sort (portal): 8.8 rating, top-decile sort-genre retention; sorts
  monetize on hint/boost rewarded video at $8-14 eCPM typical for the demo.
- Fill-the-fridge class: hot lane; rewarded-ad ARPDAU $0.02-0.05 for casual
  arrangement puzzles on web portals.
- Move-it: 2.15M plays arrange-tail evidence — arrangement games over-index on
  session length vs. match-3, which favors rewarded (opt-in) over interstitial.
- Mobile goods-sort F2P lane is saturated (30 apps) — our differentiation stays
  RULE-BADGE identity + composable rules; monetization follows portal norms.

## Gate statement
Rule 8 satisfied: revenue model (rewarded-first) + genre benchmarks above.
Ad SDK call sites are stubbed in-code (`hint_btn`/`skip_btn` handlers are the
integration points); actual SDK wiring lands with the first portal submission
card (separate scope, per distribution directive rule 6 portals-not-only).
