import json, sqlite3, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class DatabaseTests(unittest.TestCase):
 def setUp(self):
  self.db=sqlite3.connect(':memory:')
  for path in sorted((ROOT/'db/DDL').glob('v[12].*.sql')): self.db.executescript(path.read_text())
  self.db.execute("UPDATE audit_workspace SET revision=6,payload=? WHERE id=1", ('{"schemaVersion":2,"records":[],"snapshots":[]}',))
  self.migration=next((ROOT/'db/DDL').glob('v3.*.sql')).read_text()
  self.db.executescript(self.migration)
  self.sql=json.loads((ROOT/'db/sql/team-workspace.sql.json').read_text())
 def test_preserve(self):
  self.assertEqual(self.db.execute(self.sql['getWorkspace'],('default',)).fetchone()[0],6)
  self.assertEqual(self.db.execute('SELECT revision FROM audit_workspace').fetchone()[0],6)
 def test_idempotency(self):
  self.db.execute(self.sql['saveWorkspace'],('{}','now','default',6))
  self.db.executescript(self.migration)
  self.assertEqual(self.db.execute(self.sql['getWorkspace'],('default',)).fetchone(),(7,'{}'))
 def test_cas_isolation(self):
  self.db.execute(self.sql['createTeam'],('b','团队乙','{}','now'))
  self.assertEqual(self.db.execute(self.sql['saveWorkspace'],('{}','now','default',6)).rowcount,1)
  self.assertEqual(self.db.execute(self.sql['saveWorkspace'],('{}','now','b',0)).rowcount,1)
  self.assertEqual(self.db.execute(self.sql['saveWorkspace'],('{"bad":1}','now','b',0)).rowcount,0)
  self.assertEqual(self.db.execute(self.sql['getWorkspace'],('b',)).fetchone(),(1,'{}'))
 def test_unique_team(self):
  with self.assertRaises(sqlite3.IntegrityError):self.db.execute(self.sql['createTeam'],('c','原稽核团队','{}','now'))
if __name__=='__main__': unittest.main()
