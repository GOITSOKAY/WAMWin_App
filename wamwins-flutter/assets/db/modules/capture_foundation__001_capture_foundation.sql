-- LAZY MODULE MIGRATION (device): applied ONLY the first time an entitled capture module
-- (IMAGE_RECOGNITION, VIDEO_RECOGNITION, RECEIPT_SCANNING, TEST_ADVANCED_CAPTURE, ...) loads.
-- Additive only: creates new tables, never alters or rebuilds existing ones.
-- Mirrors ext.* in database/postgres/migrations/future-ai/V022.
CREATE TABLE IF NOT EXISTS media_asset (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    media_type TEXT NOT NULL CHECK (media_type IN ('IMAGE','VIDEO','AUDIO','DOCUMENT')),
    local_uri TEXT NOT NULL, mime_type TEXT NOT NULL, byte_size INTEGER,
    status TEXT NOT NULL DEFAULT 'PENDING_UPLOAD' CHECK (status IN ('PENDING_UPLOAD','UPLOADED','PROCESSED','PURGED')),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE (id, household_id)
) STRICT;
CREATE TABLE IF NOT EXISTS capture_session (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    capture_kind TEXT NOT NULL CHECK (capture_kind IN ('IMAGE','VIDEO','BARCODE','RECEIPT','VOICE','TEST')),
    target_kitchen_id TEXT, target_storage_instance_id TEXT,
    status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','PROCESSING','REVIEW','COMPLETED','CANCELLED','FAILED')),
    started_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')), completed_at TEXT,
    UNIQUE (id, household_id)
) STRICT;
CREATE TABLE IF NOT EXISTS recognition_session (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    capture_session_id TEXT, media_asset_id TEXT,
    engine_code TEXT NOT NULL, engine_version TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','RUNNING','COMPLETED','FAILED')),
    UNIQUE (id, household_id),
    FOREIGN KEY (capture_session_id, household_id) REFERENCES capture_session(id, household_id) ON DELETE CASCADE
) STRICT;
CREATE TABLE IF NOT EXISTS recognition_result (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    recognition_session_id TEXT NOT NULL,
    result_kind TEXT NOT NULL CHECK (result_kind IN ('ITEM','STORAGE_UNIT','SECTION','APPLIANCE','EQUIPMENT')),
    proposed_item_master_id TEXT REFERENCES item_master(id),
    proposed_storage_type_code TEXT REFERENCES storage_type(code),
    proposed_label TEXT, quantity_estimate REAL, unit_code TEXT REFERENCES unit_of_measure(code),
    confidence REAL NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    review_status TEXT NOT NULL DEFAULT 'PENDING' CHECK (review_status IN ('PENDING','CONFIRMED','EDITED','REJECTED')),
    reviewed_at TEXT, resulting_inventory_item_id TEXT, resulting_storage_instance_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    FOREIGN KEY (recognition_session_id, household_id) REFERENCES recognition_session(id, household_id) ON DELETE CASCADE
) STRICT;
