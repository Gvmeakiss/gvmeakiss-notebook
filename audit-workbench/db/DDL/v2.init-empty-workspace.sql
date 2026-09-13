INSERT INTO audit_workspace (id, revision, payload, updated_at)
SELECT 1, 0, '{"schemaVersion":2,"records":[],"snapshots":[]}', strftime('%Y-%m-%dT%H:%M:%fZ','now')
WHERE NOT EXISTS (SELECT 1 FROM audit_workspace WHERE id = 1);
