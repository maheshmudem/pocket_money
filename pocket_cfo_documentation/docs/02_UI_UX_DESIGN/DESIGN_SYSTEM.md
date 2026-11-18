# Design System
- Document ID: UX-001 · Status: Draft visual direction; final tokens require Figma approval.

## Visual direction
Premium, calm, trustworthy fintech. Use contemporary editorial hierarchy, generous whitespace, high-clarity financial numbers, restrained gradients and subtle surface depth. Avoid excessive glassmorphism, neon overload, tiny low-contrast labels and decorative motion that competes with money information.

## Principles
1. Financial clarity first: amount, currency, period and context are clear.
2. Calm confidence: clean layouts, alignment and restrained colour.
3. Progressive disclosure: advanced detail without overwhelming defaults.
4. Consistency: shared components behave consistently.
5. Honest feedback: saved, pending sync, failed and estimated are distinct.
6. Accessibility: never use colour as the only status signal.

## Proposed semantic palette
| Token | Purpose | Direction |
|---|---|---|
| primary | Brand/actions | Deep blue / indigo |
| primaryContainer | Selected surfaces | Soft blue tint |
| background | Page | Warm near-white / deep charcoal-navy |
| surface | Cards/sheets | Neutral elevated surface |
| income | Cash inflow | Teal/green + icon/label |
| expense | Outflow | Coral/red + icon/label |
| warning | Attention | Amber |
| error | Invalid/failed | Red + text/icon |
| success | Completed | Green/teal + text/icon |
| outline | Dividers | Contrast-aware neutral |

Finalize exact colour values in design tooling and validate WCAG contrast. Never rely only on green/red.

## Typography and numbers
Use a legible sans-serif with clear numeral shapes. Define display, page title, section title, body, label, caption and table styles. Use tabular numerals for financial values where supported. Avoid overusing uppercase and microcopy.

## Spacing and shape
Use a 4-point scale: 4, 8, 12, 16, 20, 24, 32, 40. Define a small radius scale for controls, cards and sheets. Prefer consistent card geometry.

## Component library
App bars/profile selector; primary/secondary/text/destructive buttons; amount field/currency selector; account/category picker; period picker; transaction row/date group; summary card; budget progress; savings goal; chart container with legend/text summary; empty/loading/error/offline/permission states; confirmation sheet; filter chips; search; sync indicator.

Every component must define variants, sizes, states, semantics, content rules and responsive behaviour.

## Charts
Label period and currency; provide textual summaries; avoid misleading axes; mark incomplete periods; explain inclusions/exclusions for net worth and spend; show honest empty states. Do not imply precision beyond data coverage.

## Themes and responsive layout
Support light, dark and system modes. Design compact phones first, then larger phones/tablets. At wider breakpoints use adaptive columns/navigation rail where suitable. Forms must work with keyboard visible and text scaling.

## Handoff
Figma page/frame names include screen IDs; use design tokens; supply default/loading/empty/error/offline/disabled/success states, dark mode, large text and motion notes.
