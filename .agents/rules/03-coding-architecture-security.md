# Coding, Architecture, Concurrency & Security Standards

Apply these engineering rules to every source file across backend, mobile, desktop, and web projects to keep the codebase maintainable, deterministic, fast, and secure.

---

## 1. Clean Architecture & Layer Boundaries

- **Strict Layer Isolation**:
  - `domain/` and pure core engines (e.g., `financial_engine/`, pricing, scheduling, domain rules) MUST remain **100% pure language code** — zero UI toolkit, database driver, HTTP client, or platform SDK imports.
  - `presentation/` (UI, screens, controllers/BLoCs) talks to `domain/` repositories or use-cases, never directly executing raw SQL or reaching into low-level storage internals.
  - `data/` implements `domain/` contracts, maps persistence/network DTOs cleanly, and enforces schema/transaction integrity.
- **Immutability & Explicit Errors**:
  - Prefer immutable value objects and entities (`final class`, `@immutable`, `Equatable`, `copyWith`).
  - Return explicit typed results (`Result<T, AppFailure>` / sealed error types) for domain and I/O failures instead of silently swallowing exceptions or returning ambiguous `null`s.
- **Small, Modular, Reusable Units**:
  - Extract repeated UI surfaces, formatters, validators, and business helpers into shared modules (`lib/shared/` or `src/shared/`).
  - Keep functions single-purpose and readable; eliminate dead code, commented-out blocks, and unused imports immediately.

---

## 2. Precision, Data Integrity & Persistence

- **Exact Numeric Math (Zero Float Money)**:
  - Never store or calculate currency, balances, taxes, interest, or percentages that sum to 100% using IEEE-754 floating-point (`double` / `float`). Use integer minor units (paise/cents) or arbitrary-precision decimal types.
- **Atomic Transactions & Auditability**:
  - Multi-step writes (e.g., double-entry debits & credits, transfers, balance updates, loan EMI principal/interest splits) MUST execute inside a single atomic database transaction.
  - Enforce invariants at **both** domain and database layers (composite foreign keys, `CHECK` constraints, immutability triggers, idempotency keys).
- **Deterministic Time & IDs**:
  - Store and compare timestamps in **UTC** (ISO-8601); format into local time only at the presentation layer.
  - Inject clocks (`UtcClock`) and ID generators (`IdGenerator`) so all logic is 100% deterministic and unit-testable.

---

## 3. Concurrency, Lifecycle & Resource Safety

- **Zero Resource Leaks**:
  - Always dispose every `TextEditingController`, `FocusNode`, `ScrollController`, `AnimationController`, `StreamSubscription`, `Timer`, and `ChangeNotifier` in `dispose()` / cleanup hooks.
- **Async Mount & Race Guards**:
  - Always check `if (!mounted) return;` (or `if (!context.mounted) return;`) after every `await` before touching `BuildContext`, `Navigator`, `ScaffoldMessenger`, or `setState`.
  - Guard against stale in-flight responses during rapid user actions (e.g., rapid profile/tab switches, fast search typing) using request sequencing, switch-map cancellation, or active-ID verification.
- **Zero Deprecated APIs**:
  - Treat analyzer `info` and deprecation notices as build blockers (`--fatal-infos` / `-D warnings`), upgrading immediately to current framework APIs.

---

## 4. Security & Privacy Hygiene

- **Zero Hardcoded Secrets**: Never commit API keys, private keys, encryption passphrases, signing passwords, or OAuth secrets to code, tests, or config files.
- **Encryption & Key Management**: Protect sensitive local databases/backups with authenticated encryption (e.g., SQLCipher / AES-256-GCM) and platform secure keystores (Keychain / Android Keystore), with salted KDF hashing (PBKDF2/Argon2) for user PINs/passphrases.
- **Redacted Diagnostics**: Never print passwords, PINs, auth tokens, account numbers, or raw PII into `print`, `debugPrint`, `logcat`, or crash telemetry; pass all logs through a redacting logger.
- **Validate Every Boundary**: Sanitize and validate all user inputs, imported files (CSV/JSON/backups), and external API payloads before mutating state — prefer staging validation before destructive restores.
