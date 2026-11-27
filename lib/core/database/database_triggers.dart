/// Database-level indexes, double-entry immutability & balance triggers,
/// and ISO currency seeds (`DATA-002`, `DATA-003`).
abstract final class DatabaseIntegritySql {
  static const List<String> indexStatements = [
    'CREATE INDEX IF NOT EXISTS idx_tx_profile_date ON transactions(profile_id, transaction_date_utc DESC);',
    'CREATE INDEX IF NOT EXISTS idx_tx_profile_source_date ON transactions(profile_id, source_account_id, transaction_date_utc DESC);',
    'CREATE INDEX IF NOT EXISTS idx_tx_profile_dest_date ON transactions(profile_id, destination_account_id, transaction_date_utc DESC);',
    'CREATE INDEX IF NOT EXISTS idx_tx_profile_category_date ON transactions(profile_id, category_id, transaction_date_utc DESC);',
    'CREATE INDEX IF NOT EXISTS idx_tx_profile_ext_ref ON transactions(profile_id, external_ref);',
    'CREATE INDEX IF NOT EXISTS idx_posting_profile_account ON ledger_postings(profile_id, ledger_account_id);',
    'CREATE INDEX IF NOT EXISTS idx_posting_profile_journal ON ledger_postings(profile_id, journal_entry_id);',
    'CREATE INDEX IF NOT EXISTS idx_journal_profile_tx ON journal_entries(profile_id, transaction_id);',
    'CREATE INDEX IF NOT EXISTS idx_outbox_profile_status ON sync_outbox(profile_id, status, created_at_utc);',
    'CREATE INDEX IF NOT EXISTS idx_import_fingerprint ON imported_transactions(profile_id, fingerprint);',
    'CREATE INDEX IF NOT EXISTS idx_audit_profile_date ON audit_logs(profile_id, created_at_utc DESC);',
    'CREATE INDEX IF NOT EXISTS idx_notif_profile_unread ON local_notifications(profile_id, is_read, created_at_utc DESC);',
    'CREATE INDEX IF NOT EXISTS idx_bucket_profile_month ON bucket_list_items(profile_id, target_year_month, status);',
  ];

  /// Enforces accounting invariants directly inside SQLite so neither UI nor
  /// repository bugs can post an unbalanced journal or mutate posted history.
  static const List<String> triggerStatements = [
    // 1. Disallow inserting journal_entries directly as posted/reversed.
    // Journals must start as 'draft', attach >=2 balanced postings, then transition to 'posted'.
    '''
    CREATE TRIGGER IF NOT EXISTS trg_journal_no_direct_posted_insert
    BEFORE INSERT ON journal_entries
    WHEN NEW.status <> 'draft'
    BEGIN
      SELECT RAISE(ABORT, 'LEDGER_INVARIANT: journal_entries must be inserted as draft before posting');
    END;
    ''',

    // 2. Verify >=2 postings and SUM(debit) == SUM(credit) > 0 when posting a journal.
    '''
    CREATE TRIGGER IF NOT EXISTS trg_journal_verify_balanced_before_post
    BEFORE UPDATE OF status ON journal_entries
    WHEN OLD.status = 'draft' AND NEW.status = 'posted'
    BEGIN
      SELECT CASE
        WHEN (SELECT COUNT(*) FROM ledger_postings WHERE journal_entry_id = NEW.id AND profile_id = NEW.profile_id) < 2
        THEN RAISE(ABORT, 'LEDGER_INVARIANT: posted journal requires at least two postings')
      END;
      SELECT CASE
        WHEN COALESCE((SELECT SUM(base_amount_minor) FROM ledger_postings WHERE journal_entry_id = NEW.id AND profile_id = NEW.profile_id AND side = 'debit'), 0) <= 0
        THEN RAISE(ABORT, 'LEDGER_INVARIANT: posted journal debit total must be positive')
      END;
      SELECT CASE
        WHEN COALESCE((SELECT SUM(base_amount_minor) FROM ledger_postings WHERE journal_entry_id = NEW.id AND profile_id = NEW.profile_id AND side = 'debit'), 0)
          <> COALESCE((SELECT SUM(base_amount_minor) FROM ledger_postings WHERE journal_entry_id = NEW.id AND profile_id = NEW.profile_id AND side = 'credit'), 0)
        THEN RAISE(ABORT, 'LEDGER_INVARIANT: posted journal debits must equal credits in base currency')
      END;
    END;
    ''',

    // 3. Posted journals are immutable except marking status = 'reversed' while keeping all other columns unchanged.
    '''
    CREATE TRIGGER IF NOT EXISTS trg_journal_immutable_update
    BEFORE UPDATE ON journal_entries
    WHEN OLD.status IN ('posted', 'reversed')
    BEGIN
      SELECT CASE
        WHEN OLD.status = 'reversed'
        THEN RAISE(ABORT, 'LEDGER_INVARIANT: reversed journal_entry is strictly immutable')
        WHEN NOT (
          NEW.status = 'reversed'
          AND NEW.id = OLD.id
          AND NEW.profile_id = OLD.profile_id
          AND NEW.transaction_id = OLD.transaction_id
          AND NEW.effective_at_utc = OLD.effective_at_utc
          AND NEW.created_at_utc = OLD.created_at_utc
          AND COALESCE(NEW.reverses_journal_entry_id, '') = COALESCE(OLD.reverses_journal_entry_id, '')
        )
        THEN RAISE(ABORT, 'LEDGER_INVARIANT: posted journal_entry cannot be mutated')
      END;
    END;
    ''',

    // 4. Posted or reversed journals can never be deleted.
    '''
    CREATE TRIGGER IF NOT EXISTS trg_journal_immutable_delete
    BEFORE DELETE ON journal_entries
    WHEN OLD.status IN ('posted', 'reversed')
    BEGIN
      SELECT RAISE(ABORT, 'LEDGER_INVARIANT: posted or reversed journal_entry cannot be deleted');
    END;
    ''',

    // 5. Postings cannot be added, modified, or deleted once parent journal is posted/reversed.
    '''
    CREATE TRIGGER IF NOT EXISTS trg_posting_no_insert_after_post
    BEFORE INSERT ON ledger_postings
    WHEN (SELECT status FROM journal_entries WHERE id = NEW.journal_entry_id AND profile_id = NEW.profile_id) IN ('posted', 'reversed')
    BEGIN
      SELECT RAISE(ABORT, 'LEDGER_INVARIANT: cannot add posting to posted or reversed journal');
    END;
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_posting_immutable_update
    BEFORE UPDATE ON ledger_postings
    WHEN (SELECT status FROM journal_entries WHERE id = OLD.journal_entry_id AND profile_id = OLD.profile_id) IN ('posted', 'reversed')
    BEGIN
      SELECT RAISE(ABORT, 'LEDGER_INVARIANT: cannot modify posting of posted or reversed journal');
    END;
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_posting_immutable_delete
    BEFORE DELETE ON ledger_postings
    WHEN (SELECT status FROM journal_entries WHERE id = OLD.journal_entry_id AND profile_id = OLD.profile_id) IN ('posted', 'reversed')
    BEGIN
      SELECT RAISE(ABORT, 'LEDGER_INVARIANT: cannot delete posting of posted or reversed journal');
    END;
    ''',

    // 6. Transaction type account requirements when posted.
    '''
    CREATE TRIGGER IF NOT EXISTS trg_tx_validate_accounts_insert
    BEFORE INSERT ON transactions
    WHEN NEW.status = 'posted'
    BEGIN
      SELECT CASE
        WHEN NEW.transaction_type = 'income' AND NEW.destination_account_id IS NULL
        THEN RAISE(ABORT, 'TX_INVARIANT: posted income requires destination_account_id')
        WHEN NEW.transaction_type = 'expense' AND NEW.source_account_id IS NULL
        THEN RAISE(ABORT, 'TX_INVARIANT: posted expense requires source_account_id')
        WHEN NEW.transaction_type = 'transfer' AND (NEW.source_account_id IS NULL OR NEW.destination_account_id IS NULL)
        THEN RAISE(ABORT, 'TX_INVARIANT: posted transfer requires both source and destination accounts')
        WHEN NEW.base_amount_minor <= 0
        THEN RAISE(ABORT, 'TX_INVARIANT: posted transaction base_amount_minor must be > 0')
      END;
    END;
    ''',
  ];

  /// Seeded ISO-4217 currency catalog (`INR` default, covering 0, 2, 3, and 4 decimal precision).
  static const List<({String code, String name, int minorUnit, String symbol})>
  defaultCurrencies = [
    (code: 'INR', name: 'Indian Rupee', minorUnit: 2, symbol: '₹'),
    (code: 'USD', name: 'US Dollar', minorUnit: 2, symbol: '\$'),
    (code: 'EUR', name: 'Euro', minorUnit: 2, symbol: '€'),
    (code: 'GBP', name: 'British Pound', minorUnit: 2, symbol: '£'),
    (code: 'AED', name: 'UAE Dirham', minorUnit: 2, symbol: 'د.إ'),
    (code: 'SGD', name: 'Singapore Dollar', minorUnit: 2, symbol: 'S\$'),
    (code: 'AUD', name: 'Australian Dollar', minorUnit: 2, symbol: 'A\$'),
    (code: 'CAD', name: 'Canadian Dollar', minorUnit: 2, symbol: 'C\$'),
    (code: 'CHF', name: 'Swiss Franc', minorUnit: 2, symbol: 'CHF'),
    (code: 'JPY', name: 'Japanese Yen', minorUnit: 0, symbol: '¥'),
    (code: 'KRW', name: 'South Korean Won', minorUnit: 0, symbol: '₩'),
    (code: 'KWD', name: 'Kuwaiti Dinar', minorUnit: 3, symbol: 'KD'),
    (code: 'BHD', name: 'Bahraini Dinar', minorUnit: 3, symbol: 'BD'),
    (code: 'OMR', name: 'Omani Rial', minorUnit: 3, symbol: 'OMR'),
    (
      code: 'CLF',
      name: 'Chilean Unit of Account (UF)',
      minorUnit: 4,
      symbol: 'UF',
    ),
  ];
}
