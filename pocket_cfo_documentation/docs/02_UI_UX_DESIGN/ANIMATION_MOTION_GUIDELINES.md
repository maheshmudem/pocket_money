# Animation and Motion Guidelines

## Principles
Motion explains a change, guides attention or provides feedback. It must not obscure amounts, delay saving, block navigation or disguise failure. Respect OS reduced-motion settings. Keep dashboards calm; avoid continuous decorative loops. Use haptics sparingly.

## Suggested tokens
| Token | Duration | Use |
|---|---:|---|
| `motion.fast` | 100–160 ms | button/chip feedback |
| `motion.standard` | 180–260 ms | card expansion, navigation, chart reveal |
| `motion.emphasis` | 260–400 ms | one-time goal milestone |
| `motion.long` | Avoid by default | optional onboarding storytelling only |

Use consistent ease-out entering and ease-in leaving. Validate on real devices.

## Motion catalogue
| ID | Interaction | Behaviour | Reduced-motion fallback |
|---|---|---|---|
| MOT-001 | Balance update | Short value interpolation after confirmed update | Instant value |
| MOT-002 | Chart reveal | Bar/line/donut reveals current data | Static chart |
| MOT-003 | Save | Press feedback + clear saved confirmation | Static state/message |
| MOT-004 | Card expand | Short height/opacity transition | Immediate expansion |
| MOT-005 | Budget progress | Progress animation after calculation | Static bar |
| MOT-006 | Goal milestone | Optional, one-time celebration | Static success state |
| MOT-007 | Skeleton | Subtle shimmer while waiting | Static placeholder |
| MOT-008 | Page transition | Short route transition | Platform/default transition |

## Financial trust safeguards
Never animate a predicted balance as confirmed. Accessibility services receive final value immediately. Avoid bounce/elastic motion for debt/loss/warning. Separate local save confirmation from cloud sync. Do not celebrate every routine expense.

## Flutter implementation
Use Flutter animation primitives for simple transitions; evaluate `flutter_animate` or Lottie only for specific needs. Keep animations bounded and disposed correctly. Avoid large animations in scrolling lists. Profile low/mid-range devices and test reduced-motion.
