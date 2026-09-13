CREATE TABLE IF NOT EXISTS audit_team_workspace (
  team_id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
  payload TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
INSERT OR IGNORE INTO audit_team_workspace (team_id,name,revision,payload,updated_at)
SELECT 'default','原稽核团队',revision,payload,updated_at FROM audit_workspace WHERE id=1;
