-- WAMWins LOCAL (on-device) database | Module: BACKUP (additive; mirrors backup.* in PG V024)
-- The encrypted backup payload is a file in app-private storage (or a user-chosen file);
-- only metadata is stored here. No keys are ever stored in the database.
CREATE TABLE backup_settings (
    household_id TEXT PRIMARY KEY REFERENCES household(id) ON DELETE CASCADE,
    auto_backup_enabled INTEGER NOT NULL DEFAULT 1 CHECK (auto_backup_enabled IN (0,1)),
    frequency TEXT NOT NULL DEFAULT 'WEEKLY' CHECK (frequency IN ('DAILY','WEEKLY','MONTHLY')),
    preferred_hour INTEGER NOT NULL DEFAULT 2 CHECK (preferred_hour BETWEEN 0 AND 23),
    retention_count INTEGER NOT NULL DEFAULT 5 CHECK (retention_count BETWEEN 1 AND 50),
    destination TEXT NOT NULL DEFAULT 'DEVICE' CHECK (destination IN ('DEVICE','CLOUD')),
    include_health_data INTEGER NOT NULL DEFAULT 1 CHECK (include_health_data IN (0,1)),
    last_success_at TEXT, last_failure_at TEXT, last_failure_code TEXT, next_due_at TEXT,
    updated_by_user_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    row_version INTEGER NOT NULL DEFAULT 1,
    server_sync_version INTEGER
) STRICT;

CREATE TABLE backup_record (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    trigger_type TEXT NOT NULL CHECK (trigger_type IN ('MANUAL','AUTOMATIC','PRE_RESTORE','PRE_MIGRATION')),
    status TEXT NOT NULL DEFAULT 'RUNNING' CHECK (status IN ('RUNNING','COMPLETED','FAILED','DELETED')),
    destination TEXT NOT NULL CHECK (destination IN ('DEVICE','USER_FILE','CLOUD')),
    format_version INTEGER NOT NULL,
    storage_uri TEXT, byte_size INTEGER, sha256 TEXT,
    encryption_algorithm TEXT NOT NULL DEFAULT 'AES-256-GCM' CHECK (encryption_algorithm = 'AES-256-GCM'),
    key_kind TEXT NOT NULL CHECK (key_kind IN ('DEVICE_KEY','PASSPHRASE','CLOUD_KMS')),
    include_health_data INTEGER NOT NULL CHECK (include_health_data IN (0,1)),
    table_count INTEGER, row_count INTEGER, schema_fingerprint TEXT,
    created_by_user_id TEXT, source_device_id TEXT,
    started_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    completed_at TEXT, deleted_at TEXT, error_code TEXT,
    server_sync_version INTEGER
) STRICT;
CREATE INDEX ix_backup_household ON backup_record(household_id, started_at);

CREATE TABLE restore_record (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    backup_id TEXT,
    source_sha256 TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('COMPLETED','FAILED')),
    safety_backup_id TEXT REFERENCES backup_record(id) ON DELETE SET NULL,
    restored_row_count INTEGER,
    remapped_from_household_id TEXT,
    restored_by_user_id TEXT,
    started_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    completed_at TEXT
) STRICT;
