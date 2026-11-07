-- WAMWins LOCAL database | Module: QUESTIONNAIRE (household profile provisioning trace)
-- Mirrors questionnaire.profile_provisioning_record (PostgreSQL V026). Every record created from the
-- HOUSEHOLD_PROFILE answers is traced by a stable draft key, so re-running provisioning
-- ("Update my answers") adds what is new and never duplicates.
CREATE TABLE profile_provisioning_record (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL REFERENCES household(id) ON DELETE CASCADE,
    session_id TEXT,
    draft_key TEXT NOT NULL,
    created_entity_table TEXT NOT NULL,
    created_entity_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE (household_id, draft_key)
) STRICT;
