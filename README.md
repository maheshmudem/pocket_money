# Pocket CFO

**Pocket CFO** is a production-grade, local-first personal, household, and small-business financial management platform built with **Flutter (Clean Architecture + BLoC + Drift/SQLite3MultipleCiphers)** and **Django REST Framework + PostgreSQL**.

---

## Key Enterprise Capabilities

- **Double-Entry Financial Engine (`lib/core/financial_engine/`)**: 100% Pure Dart; zero floating-point money; 64-bit integer minor units (`INR` default, 0–4 decimal ISO currencies); `BigInt` fixed-point `10^8` FX with `HALF_EVEN` Banker's Rounding; immutable posted journals corrected exclusively via compensating reversals.
- **Encrypted Local Storage (`ADR-005`)**: Drift ORM backed by `sqlite3` v3 native build hook (`source: sqlite3mc` — SQLite3MultipleCiphers in SQLCipher v4 mode) with 256-bit CSPRNG DEK stored in hardware-backed Android Keystore / iOS Keychain (`flutter_secure_storage`), WAL encryption, `allowBackup=false`, and SQLite immutability/balance triggers.
- **Strict Four-Layer Profile Isolation & RBAC**: Isolated `Personal`, `Family`, and `Business` profiles enforced via epoch-guarded BLoC cancellation (`ProfileScopeController`), `ProfileId`-typed repositories, composite SQLite foreign keys `(id, profile_id)`, and Django RBAC (`Owner`, `Admin`, `Editor`, `Viewer`).
- **Offline-First Sync Engine (`lib/core/sync/`, `server/apps/sync/`)**: Atomic local commits + durable outbox + idempotent `/api/v1/sync/push/` replay + monotonic cursor `/api/v1/sync/pull/` + explicit conflict resolution UI (zero silent overwrites on posted financial history).
- **Complete Planning, Import & Export**: Budgets (refund-netted, transfer-excluded), Savings Goals (allocated & account-transfer modes), Idempotent Recurring Rules, Reducing-Balance EMI Loans (Principal/Interest/Fee splits), Duplicate-Detecting CSV Import, Formula-Sanitized CSV & PDF Reports, and AES-256-GCM `.pcfo` Backup with Isolated Staging-DB Restore Verification.
- **Security & Privacy Controls**: Argon2id server password hashing, short-lived in-memory JWT + rotating SHA-256 hashed refresh tokens with token-family reuse revocation, biometric + salted PBKDF2 PIN app lock, Android `FLAG_SECURE` privacy shield, and automated log redaction across mobile and server.

---

## Repository Structure

```text
pocket_money/
├── lib/                          # Flutter app (Feature-first Clean Architecture + BLoC)
│   ├── app/                      # EnvironmentConfig, GoRouter guards, Material 3 Fintech Theme, Adaptive Shell
│   ├── core/                     # Encrypted Drift DB (28 tables + triggers), Pure-Dart Financial Engine, Network, Security, Sync, Logging
│   ├── features/                 # 19 feature modules covering SCR-ONB-001 through SCR-NOT-001
│   └── shared/                   # Accessible tabular-numeral MoneyText, SyncStatusBadge, StateViews
├── test/                         # Architecture, Financial Vectors (TC-FIN-*), Encrypted DB, Triggers, BLoC, E2E, Performance & A11y tests
├── server/                       # Django + DRF + PostgreSQL modular monolith (/api/v1/)
├── infra/                        # Multi-stage Dockerfile, docker-compose.yml (Postgres 16 + Redis 7), Nginx TLS, backup/restore drill script
├── .github/workflows/            # Mobile CI (Android/iOS/Tests) and Backend CI (PostgreSQL 16 + pytest + OpenAPI check)
└── docs/pocket_cfo_documentation/# Governance, PRD, Architecture, ADRs, Traceability & OpenAPI v1 spec
```

---

## Quick Start — Mobile Client (Flutter)

### Prerequisites
- Flutter `3.44+` (Dart `3.12+`)
- Android SDK (run `flutter doctor --android-licenses` before Android APK builds) or Xcode on macOS for iOS.

### Setup & Verification Commands
```bash
flutter pub get
dart run build_runner build
flutter analyze
flutter test
```

### Run Against Local Backend
```bash
flutter run --dart-define=POCKET_CFO_ENV=dev --dart-define=POCKET_CFO_API_URL=http://10.0.2.2:8000/api/v1
```

---

## Quick Start — Enterprise Backend (Django + PostgreSQL)

### Option A: Docker Compose (Recommended for PostgreSQL 16 + Redis 7)
```bash
cp infra/.env.example infra/.env
docker compose -f infra/docker-compose.yml up --build
```

### Option B: Local Python Virtual Environment
```bash
cd server
python -m venv .venv
# Windows: .venv\Scripts\activate   |   macOS/Linux: source .venv/bin/activate
pip install -e ".[dev]"
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

### Backend Quality & Security Tests
```bash
cd server
ruff check .
python manage.py makemigrations --check --dry-run
pytest -v --cov=apps --cov=common
```

---

## Production Deployment & Backup Verification

1. Inject `DJANGO_SECRET_KEY`, `DATABASE_URL`, `DJANGO_ALLOWED_HOSTS`, and `CORS_ALLOWED_ORIGINS` strictly via managed secret store (never `.env` in Git).
2. Run `python manage.py migrate --noinput` as an atomic release step; verify `/api/v1/health/live/` and `/api/v1/health/ready/`.
3. Schedule encrypted PostgreSQL backups and automated ephemeral restore drills using `infra/scripts/backup_and_verify_postgres.sh`.
4. Build Flutter release binaries with `--dart-define=POCKET_CFO_ENV=prod --dart-define=POCKET_CFO_API_URL=https://api.pocketcfo.app/api/v1`. Release builds fail closed if SQLite3MultipleCiphers encryption cannot be verified.

---

## Troubleshooting

- **Android build fails with license error**: Run `flutter doctor --android-licenses` and accept SDK licenses.
- **Drift generated file out of date after table edits**: Run `dart run build_runner build`.
- **Database fails to open with wrong key**: Confirm hardware KeyStore/Keychain was not wiped independently of app data; restore from your encrypted `.pcfo` backup or cloud sync account.

<!-- 

now all things percet , now i need improve the more in the all cegments and feature or new function  ore any new things to useful to this app or purpose and better handles and also any new usefulll features to to do able the better . ok make perfcect plan to improve this applicaton better in all cegments UI fonction , animations etc.. ok do research and  any methiods ok , -->