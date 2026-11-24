# Screen Wireframes — Low Fidelity
These textual layouts establish hierarchy, not final pixel-level designs. Recreate as Figma frames with matching IDs.

## SCR-DASH-001 — Dashboard
```text
┌──────────────────────────────────┐
│ Pocket CFO          [Profile ▾]  │
│ [Period: This month ▾]           │
├──────────────────────────────────┤
│ NET WORTH                         │
│ ₹••••••••••                [◉]  │
│ Change vs previous period        │
├──────────────────────────────────┤
│ INCOME             EXPENSE        │
│ [amount]           [amount]       │
│ [Cash-flow chart / period tabs]  │
├──────────────────────────────────┤
│ ACCOUNTS                   See all│
│ [Bank] [Cash] [Credit card]      │
├──────────────────────────────────┤
│ BUDGET PROGRESS                  │
│ [Category progress rows]         │
├──────────────────────────────────┤
│ RECENT TRANSACTIONS       See all│
│ [Icon] Groceries        -₹ 850   │
│ [Icon] Salary          +₹45,000  │
├──────────────────────────────────┤
│ Home   Accounts   Add   Insights  │
└──────────────────────────────────┘
```
The amounts are illustrative only; never seed them as real user data.

## SCR-TRAN-002 — Add transaction
```text
┌──────────────────────────────────┐
│ [Close]       New transaction    │
│ [Expense] [Income] [Transfer]    │
│                                  │
│              ₹ 0.00              │
│          [Currency ▾]            │
│ Source account [Select ▾]        │
│ Destination    [Select ▾] (xfer) │
│ Category       [Select ▾]        │
│ Date           [Today ▾]          │
│ Note           [Optional]         │
│ [Review]                         │
│               [Save]             │
└──────────────────────────────────┘
```

## SCR-IMP-002 — CSV mapping/preview
```text
┌──────────────────────────────────┐
│ Import preview · statement.csv   │
│ Date column      [Select ▾]      │
│ Description      [Select ▾]      │
│ Amount           [Select ▾]      │
│ Debit/Credit     [Select ▾]      │
│ Currency         [Select ▾]      │
│ [Preview rows]                   │
│ Valid 92 | Review 5 | Reject 3  │
│ [Possible duplicate warnings]    │
│ [Back]           [Confirm import]│
└──────────────────────────────────┘
```

## Figma variants
For every major screen: default, loading, empty, validation error, network/system error, offline, permission denied, disabled, success, dark theme, large text, keyboard-visible forms and reduced-motion state.
