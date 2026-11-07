-- WAMWins LOCAL (on-device) database | Module: IDENTITY (device-local sign-in) + device settings
-- DEVICE-ONLY tables (not synced). Used by native clients (Flutter) for offline-first local accounts until
-- WAM Digital cloud sign-in is connected; the cloud equivalent is identity.auth_identity (PostgreSQL).
-- Passwords: PBKDF2-SHA-256 (310,000 iterations, per-user salt) - never stored readable.
CREATE TABLE local_auth_identity (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES user_account(id) ON DELETE CASCADE,
    provider_subject TEXT NOT NULL UNIQUE COLLATE NOCASE,      -- normalised email
    secret_hash TEXT NOT NULL,                                -- base64 PBKDF2 output
    salt TEXT NOT NULL,                                       -- base64
    kdf TEXT NOT NULL DEFAULT 'PBKDF2-SHA256' CHECK (kdf = 'PBKDF2-SHA256'),
    iterations INTEGER NOT NULL CHECK (iterations >= 310000),
    failed_attempts INTEGER NOT NULL DEFAULT 0,
    locked_until TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    last_used_at TEXT
) STRICT;
-- Only the SHA-256 of the session token is stored; the token itself lives in the OS keystore.
CREATE TABLE local_session (
    token_hash TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES user_account(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    expires_at TEXT NOT NULL
) STRICT;
CREATE TABLE local_setting (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
) STRICT;
