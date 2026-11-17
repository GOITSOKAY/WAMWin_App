-- WAMWins LOCAL (on-device) database | Module: PRIVACY (additive; mirrors privacy.* in PG V028)
-- Consent ledger with document code/version/text hash, person-level health access grants with expiry,
-- an access log (accounting of disclosures) and privacy requests. Every tier; never a paid feature.

-- consent_record: widen the consent types and add provenance columns. SQLite cannot change a CHECK in place,
-- so the table is rebuilt and every existing row is copied (no data is lost).
CREATE TABLE consent_record_new (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES user_account(id) ON DELETE CASCADE,
    consent_type TEXT NOT NULL CHECK (consent_type IN ('TERMS','PRIVACY_POLICY','AGE_18_PLUS','HEALTH_DATA_PROCESSING','HEALTH_DATA_SHARING',
        'CHILD_PROFILE','ADULT_ON_BEHALF','MEDIA_PROCESSING','VOICE_COMMANDS','THIRD_PARTY_SHARING','MARKETING')),
    document_code TEXT,
    document_version TEXT NOT NULL,
    text_hash TEXT,
    method TEXT CHECK (method IN ('REGISTRATION','POPUP','SETTINGS','IMPORT','API')),
    subject_ref TEXT,
    user_agent TEXT,
    granted INTEGER NOT NULL CHECK (granted IN (0,1)),
    recorded_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    source_device_id TEXT
) STRICT;
INSERT INTO consent_record_new (id, user_id, consent_type, document_version, granted, recorded_at, source_device_id)
SELECT id, user_id, consent_type, document_version, granted, recorded_at, source_device_id FROM consent_record;
DROP TABLE consent_record;
ALTER TABLE consent_record_new RENAME TO consent_record;
CREATE INDEX ix_consent_latest ON consent_record(user_id, consent_type, subject_ref, recorded_at);
-- append-only: withdrawing consent is a new row
CREATE TRIGGER trg_consent_no_update BEFORE UPDATE ON consent_record BEGIN SELECT RAISE(ABORT, 'consent records are append-only'); END;

CREATE TABLE consent_document (
    code TEXT NOT NULL CHECK (code IN ('PRIVACY_NOTICE','CONSUMER_HEALTH_DATA_POLICY','TERMS')),
    version TEXT NOT NULL,
    title TEXT NOT NULL,
    effective_from TEXT NOT NULL,
    text_hash TEXT,
    public_url TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    PRIMARY KEY (code, version)
) STRICT;

CREATE TABLE access_grant (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    subject_member_id TEXT NOT NULL REFERENCES family_member(id) ON DELETE CASCADE,
    grantee_user_id TEXT,
    grantee_email TEXT,
    grantee_name TEXT NOT NULL,
    categories TEXT NOT NULL CHECK (json_valid(categories) AND json_array_length(categories) >= 1),   -- JSON array of category codes
    access_level TEXT NOT NULL DEFAULT 'VIEW' CHECK (access_level IN ('VIEW','VIEW_EDIT')),
    starts_at TEXT NOT NULL,
    expires_at TEXT,
    purpose TEXT,
    consent_record_id TEXT,
    granted_by_user_id TEXT NOT NULL,
    granted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    revoked_at TEXT,
    revoked_by_user_id TEXT,
    server_sync_version INTEGER,
    CHECK (grantee_user_id IS NOT NULL OR grantee_email IS NOT NULL),
    CHECK (expires_at IS NULL OR expires_at > starts_at)
) STRICT;
CREATE INDEX ix_grant_household ON access_grant(household_id);
CREATE INDEX ix_grant_grantee ON access_grant(grantee_user_id);
CREATE INDEX ix_grant_subject ON access_grant(subject_member_id);

CREATE TABLE access_log (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    actor_user_id TEXT,
    subject_member_id TEXT,
    action TEXT NOT NULL CHECK (action IN ('VIEWED','EDITED','GRANT_CREATED','GRANT_REVOKED','GRANT_EXPIRED','HEALTH_DELETED','EXPORTED')),
    categories TEXT NOT NULL DEFAULT '[]',
    grant_id TEXT,
    at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
) STRICT;
CREATE INDEX ix_access_log_household ON access_log(household_id, at);
CREATE TRIGGER trg_access_log_no_update BEFORE UPDATE ON access_log BEGIN SELECT RAISE(ABORT, 'the access log is append-only'); END;

CREATE TABLE privacy_request (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES user_account(id) ON DELETE CASCADE,
    household_id TEXT,
    request_type TEXT NOT NULL CHECK (request_type IN ('ACCESS','EXPORT','DELETION','RECTIFICATION','CORRECTION','RESTRICTION','OBJECTION','RECIPIENTS','APPEAL','OTHER')),
    details TEXT,
    status TEXT NOT NULL DEFAULT 'RECEIVED' CHECK (status IN ('RECEIVED','IN_PROGRESS','COMPLETED','REJECTED')),
    requested_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    due_at TEXT NOT NULL,
    completed_at TEXT,
    server_sync_version INTEGER
) STRICT;
CREATE INDEX ix_privacy_request_user ON privacy_request(user_id);
