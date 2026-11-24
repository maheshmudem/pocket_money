# SQLite Schema — Core Design Baseline
- Document ID: DATA-002 · Status: Illustrative starter, NOT production migration.

This DDL demonstrates core relationships. Review, extend and convert to typed Drift tables/versioned migrations. Add triggers, further constraints, indexes, migrations and tests. Do not paste unchanged into production.

```sql
PRAGMA foreign_keys = ON;
CREATE TABLE profiles (
 id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL,
 profile_type TEXT NOT NULL CHECK(profile_type IN ('personal','family','business')),
 base_currency_code TEXT NOT NULL, created_at_utc TEXT NOT NULL,
 updated_at_utc TEXT NOT NULL, archived_at_utc TEXT,
 UNIQUE(id, base_currency_code)
);
CREATE TABLE profile_memberships (
 id TEXT PRIMARY KEY NOT NULL, profile_id TEXT NOT NULL REFERENCES profiles(id),
 user_id TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('owner','admin','editor','viewer')),
 membership_status TEXT NOT NULL CHECK(membership_status IN ('active','invited','revoked')),
 created_at_utc TEXT NOT NULL, UNIQUE(profile_id,user_id), UNIQUE(id,profile_id)
);
CREATE TABLE currencies (
 code TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL,
 minor_unit INTEGER NOT NULL CHECK(minor_unit BETWEEN 0 AND 4),
 symbol TEXT, is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1))
);
CREATE TABLE ledger_accounts (
 id TEXT PRIMARY KEY NOT NULL, profile_id TEXT NOT NULL REFERENCES profiles(id),
 name TEXT NOT NULL,
 account_type TEXT NOT NULL CHECK(account_type IN ('asset','liability','equity','income','expense')),
 normal_balance TEXT NOT NULL CHECK(normal_balance IN ('debit','credit')),
 is_system INTEGER NOT NULL DEFAULT 0 CHECK(is_system IN (0,1)),
 created_at_utc TEXT NOT NULL, UNIQUE(id,profile_id)
);
CREATE TABLE financial_accounts (
 id TEXT PRIMARY KEY NOT NULL, profile_id TEXT NOT NULL REFERENCES profiles(id),
 ledger_account_id TEXT NOT NULL, name TEXT NOT NULL,
 account_type TEXT NOT NULL CHECK(account_type IN ('cash','bank','wallet','credit_card','loan','investment','other')),
 currency_code TEXT NOT NULL REFERENCES currencies(code),
 is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
 created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL, UNIQUE(id,profile_id),
 FOREIGN KEY(ledger_account_id,profile_id) REFERENCES ledger_accounts(id,profile_id)
);
CREATE TABLE categories (
 id TEXT PRIMARY KEY NOT NULL, profile_id TEXT NOT NULL REFERENCES profiles(id),
 name TEXT NOT NULL, category_type TEXT NOT NULL CHECK(category_type IN ('income','expense','transfer','other')),
 parent_category_id TEXT, is_system INTEGER NOT NULL DEFAULT 0 CHECK(is_system IN (0,1)),
 is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)), UNIQUE(id,profile_id),
 FOREIGN KEY(parent_category_id,profile_id) REFERENCES categories(id,profile_id)
);
CREATE TABLE transactions (
 id TEXT PRIMARY KEY NOT NULL, profile_id TEXT NOT NULL REFERENCES profiles(id),
 transaction_type TEXT NOT NULL CHECK(transaction_type IN ('income','expense','transfer','adjustment','refund')),
 status TEXT NOT NULL CHECK(status IN ('draft','posted','voided')),
 transaction_date_utc TEXT NOT NULL, amount_minor INTEGER NOT NULL CHECK(amount_minor>0),
 currency_code TEXT NOT NULL REFERENCES currencies(code),
 base_currency_code TEXT NOT NULL REFERENCES currencies(code),
 base_amount_minor INTEGER NOT NULL CHECK(base_amount_minor>=0),
 fx_rate_scaled INTEGER NOT NULL CHECK(fx_rate_scaled>0), fx_rate_scale INTEGER NOT NULL CHECK(fx_rate_scale>0),
 source_account_id TEXT, destination_account_id TEXT, category_id TEXT, description TEXT,
 created_at_utc TEXT NOT NULL, updated_at_utc TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1,
 UNIQUE(id,profile_id),
 FOREIGN KEY(source_account_id,profile_id) REFERENCES financial_accounts(id,profile_id),
 FOREIGN KEY(destination_account_id,profile_id) REFERENCES financial_accounts(id,profile_id),
 FOREIGN KEY(category_id,profile_id) REFERENCES categories(id,profile_id),
 CHECK(source_account_id IS NULL OR destination_account_id IS NULL OR source_account_id<>destination_account_id)
);
CREATE TABLE transaction_splits (
 id TEXT PRIMARY KEY NOT NULL, profile_id TEXT NOT NULL REFERENCES profiles(id),
 transaction_id TEXT NOT NULL, category_id TEXT NOT NULL,
 amount_minor INTEGER NOT NULL CHECK(amount_minor>0), memo TEXT,
 FOREIGN KEY(transaction_id,profile_id) REFERENCES transactions(id,profile_id),
 FOREIGN KEY(category_id,profile_id) REFERENCES categories(id,profile_id), UNIQUE(id,profile_id)
);
CREATE TABLE journal_entries (
 id TEXT PRIMARY KEY NOT NULL, profile_id TEXT NOT NULL REFERENCES profiles(id),
 transaction_id TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('draft','posted','reversed')),
 effective_at_utc TEXT NOT NULL, created_at_utc TEXT NOT NULL, reverses_journal_entry_id TEXT,
 FOREIGN KEY(transaction_id,profile_id) REFERENCES transactions(id,profile_id),
 FOREIGN KEY(reverses_journal_entry_id,profile_id) REFERENCES journal_entries(id,profile_id),
 UNIQUE(id,profile_id)
);
CREATE TABLE ledger_postings (
 id TEXT PRIMARY KEY NOT NULL, profile_id TEXT NOT NULL REFERENCES profiles(id),
 journal_entry_id TEXT NOT NULL, ledger_account_id TEXT NOT NULL,
 side TEXT NOT NULL CHECK(side IN ('debit','credit')),
 base_amount_minor INTEGER NOT NULL CHECK(base_amount_minor>0),
 currency_code TEXT NOT NULL REFERENCES currencies(code),
 original_amount_minor INTEGER NOT NULL CHECK(original_amount_minor>0),
 FOREIGN KEY(journal_entry_id,profile_id) REFERENCES journal_entries(id,profile_id),
 FOREIGN KEY(ledger_account_id,profile_id) REFERENCES ledger_accounts(id,profile_id)
);
CREATE TABLE sync_outbox (
 operation_id TEXT PRIMARY KEY NOT NULL, profile_id TEXT NOT NULL REFERENCES profiles(id),
 entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
 operation_type TEXT NOT NULL CHECK(operation_type IN ('create','update','delete')),
 payload_json TEXT NOT NULL, created_at_utc TEXT NOT NULL, retry_count INTEGER NOT NULL DEFAULT 0,
 status TEXT NOT NULL CHECK(status IN ('pending','syncing','synced','retryable_error','permanent_error','conflict'))
);
CREATE INDEX idx_tx_profile_date ON transactions(profile_id,transaction_date_utc DESC);
CREATE INDEX idx_tx_profile_account_date ON transactions(profile_id,source_account_id,transaction_date_utc DESC);
CREATE INDEX idx_tx_profile_category_date ON transactions(profile_id,category_id,transaction_date_utc DESC);
CREATE INDEX idx_posting_profile_account ON ledger_postings(profile_id,ledger_account_id);
CREATE INDEX idx_outbox_profile_status ON sync_outbox(profile_id,status,created_at_utc);
```

## Additional invariants not fully expressed above
1. Posted journal has at least two postings.
2. Sum of debit base amounts equals sum of credit base amounts per posted journal.
3. Split sum equals parent amount under documented currency rule.
4. Income requires destination, expense requires source, transfer requires both.
5. All related profile IDs match.
6. Posted journals/postings immutable; corrections use reversals.
7. FX scale/rounding consistent and integer-based.
8. Cross-currency transfers explicitly account for base postings and FX effects.
9. Base currency changes never rewrite historical transactions silently.
10. Enforce with triggers/constraints and transactional domain validation tests, not UI alone.

Drift notes: typed tables/DAOs, explicit migrations, local transaction for multi-table financial writes, foreign keys enabled on every connection, migration tests for every released schema and native encrypted DB PoC on Android/iOS.
