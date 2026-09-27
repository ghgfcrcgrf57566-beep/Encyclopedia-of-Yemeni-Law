CREATE TABLE IF NOT EXISTS laws (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  short_name TEXT,
  category TEXT,
  order_num INTEGER,
  articles_count INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS abwab (
  id INTEGER PRIMARY KEY,
  law_id INTEGER NOT NULL,
  parent_bab_id INTEGER,
  level TEXT,
  label TEXT,
  title TEXT,
  order_num INTEGER
);

CREATE TABLE IF NOT EXISTS fusul (
  id INTEGER PRIMARY KEY,
  law_id INTEGER NOT NULL,
  bab_id INTEGER,
  label TEXT,
  title TEXT,
  order_num INTEGER
);

CREATE TABLE IF NOT EXISTS mawad (
  id INTEGER PRIMARY KEY,
  law_id INTEGER NOT NULL,
  fasl_id INTEGER,
  bab_id INTEGER,
  number TEXT,
  body TEXT NOT NULL,
  order_num INTEGER
);

CREATE INDEX IF NOT EXISTS idx_rag_mawad_law ON mawad(law_id);
CREATE INDEX IF NOT EXISTS idx_rag_mawad_number ON mawad(number);

CREATE VIRTUAL TABLE IF NOT EXISTS mawad_fts USING fts5(
  body,
  number,
  law_name,
  content='',
  tokenize='unicode61'
);

CREATE TRIGGER IF NOT EXISTS mawad_fts_ai AFTER INSERT ON mawad BEGIN
  INSERT INTO mawad_fts(rowid, body, number, law_name)
  SELECT new.id, new.body, new.number, (SELECT name FROM laws WHERE id = new.law_id);
END;

CREATE TRIGGER IF NOT EXISTS mawad_fts_au AFTER UPDATE ON mawad BEGIN
  DELETE FROM mawad_fts WHERE rowid = old.id;
  INSERT INTO mawad_fts(rowid, body, number, law_name)
  SELECT new.id, new.body, new.number, (SELECT name FROM laws WHERE id = new.law_id);
END;

CREATE TRIGGER IF NOT EXISTS mawad_fts_ad AFTER DELETE ON mawad BEGIN
  DELETE FROM mawad_fts WHERE rowid = old.id;
END;

CREATE TABLE IF NOT EXISTS ai_rate_limits (
  key TEXT NOT NULL,
  bucket INTEGER NOT NULL,
  count INTEGER NOT NULL,
  PRIMARY KEY(key,bucket)
);
