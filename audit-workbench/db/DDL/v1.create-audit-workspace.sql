CREATE TABLE IF NOT EXISTS audit_workspace (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
  payload TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
