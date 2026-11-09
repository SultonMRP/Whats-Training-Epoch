# What's Training? Epoch — agent notes

Folder: `D:\Warcrafts\SingleWoW\Interface\AddOns\Whats-Training-Epoch`

Client: 3.3.5a (`## Interface: 30300`). Version 1.0.6 (ZythDr). Cross-ref: `D:\Warcrafts\SingleWoW\Interface\AddOns\agent-global.md`

---

## What it is

Spellbook “what can I train next” UI. It does **not** ship a spell database. On first trainer visit it scans Blizzard’s trainer API and stores results in `WT_EpochAccountDB` / `WT_EpochCharDB`.

Scan lives in `Scanner.lua`. Spellbook frame is `UI.lua` (`WhatsTrainingFrame` on `SpellBookFrame`). Profession trainers are skipped (`IsTradeskillTrainer`).

---

## Session changes (2026-11-09)

### First-open client freeze

First scan turns on Available + Unavailable + **Already Known** (`SetTrainerServiceTypeFilter(..., "used", 1)`) so every rank is visible.

That fires `TRAINER_UPDATE`. The handler restored the player’s filters, which fired `TRAINER_UPDATE` again → infinite restore loop (UI thread lock). Class trainers hung; profession trainers were already skipped.

**Fix in `Scanner.lua`:**

- `applyingFilters` — ignore `TRAINER_UPDATE` caused by our own filter/UI restore (declare this `local` **before** any function that writes it).
- Do **not** call `RestoreSavedFilters` on every `TRAINER_UPDATE` while `scan.phase == "restore"`.
- After flipping filters, wait a tick (`AfterTrainerSettles`) so the list is complete, then scan once and restore once.
- One `SetTrainerService` per row for spell ID + description (`ResolveSpellIDAndDescription`).

### Scan tooltip stuck on screen

`WT_EpochTrainerTip` (`GameTooltipTemplate` + `SetTrainerService`) **shows** the tooltip in 3.3.5 even with `ANCHOR_NONE`. The scan never hid it.

**Fix:** park the tip off-screen (`TOPRIGHT` of `UIParent` is `TOPLEFT -128`), `Hide()` after each row and after the scan (including pcall failure).

---

## Do not

- Restore filters from `TRAINER_UPDATE` — that is the freeze.
- Assign `ReputationWatchBar_Update`-style Blizzard functions as raw `OnEvent` (different addon, same class of bug: widget args vs expected numbers).
- Leave `SetTrainerService` / `SetUnit` scrapers visible.
- Re-enable scanning profession trainers unless the user asks.
