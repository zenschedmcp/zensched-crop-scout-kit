-- ZenSched Crop-Scout Local Database Schema
-- SQLite database for growers, fields (places with a GPS corner), scout
-- visit summaries, and billing.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my crop-scout database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 crop-scout.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- NOT A RECOMMENDATION AND NOT A SPRAY LOG. scout_log is the owner's local
-- extract of growth stage, pest count, and pest type from the Scout Record.
-- It is not a CCA / PCA written recommendation, not a FIFRA or state
-- pesticide-use report, and not a yield or NDVI model. Licensed agronomists
-- still write recommendations on their own forms.
--
-- PRIVACY: fields.access_notes (gate, muddy approach, dog, "park at the
-- south corner") and scouts.license_no (CCA / PCA number) live ONLY in this
-- file on your computer. They are never sent to ZenSched. The GPS corner
-- DOES go to ZenSched — that is the check-in pin. SKILL.md forbids the
-- agent from putting access notes or license numbers in any ZenSched field.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, default scout, business name, form id).
-- default_checkin_radius_m is informational: the radius ZenSched enforces
-- is the account POLICY's, set with policy_update(0, {"checkin_radius_m": N}).
-- Fields are large; 200 m is a starting point for a corner pin.
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Crop Scout');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-05:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_worker_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_start', '07:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_minutes', '45');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '14');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('scout_record_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('event_window_days', '60');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_checkin_radius_m', '200');

-- Services: your price list. Seeded with common scout products; edit prices.
-- visits.service_id is what was actually done (a weekly field-scout grower
-- can still get a one-off disease_scout visit).
CREATE TABLE IF NOT EXISTS services (
  service_id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL UNIQUE,                        -- short handle: 'field_scout'
  service_name TEXT NOT NULL,                       -- shown on invoices
  default_minutes INTEGER NOT NULL,                 -- shift length on ZenSched
  price REAL NOT NULL,                              -- default per-visit dollars
  is_active INTEGER DEFAULT 1,
  notes TEXT
);

INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('field_scout', 'Field scout', 45, 125.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('disease_scout', 'Disease scout', 60, 180.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('tissue_sample', 'Tissue sample', 30, 85.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('soil_sample', 'Soil sample', 45, 95.00);
INSERT OR IGNORE INTO services (code, service_name, default_minutes, price) VALUES ('stand_count', 'Stand count', 30, 75.00);

-- Growers: who pays. Contact and billing live here. Cadence lives on the
-- field — one farm often has a weekly corn field and an on-demand soy field.
CREATE TABLE IF NOT EXISTS growers (
  grower_id INTEGER PRIMARY KEY AUTOINCREMENT,
  grower_name TEXT NOT NULL,                        -- 'Tom Rivera' or 'Rivera Farms'
  farm_name TEXT,                                   -- 'Rivera Farms' if grower_name is a person
  contact_email TEXT,
  contact_phone TEXT,
  billing_notes TEXT,                               -- 'invoice monthly', 'pays after harvest'
  is_active INTEGER DEFAULT 1,                      -- 0 = paused / sold the farm
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Fields: the places. One ZenSched LOCATION per field, pinned at a GPS
-- corner (SW corner or the field entrance — pick one and stay consistent).
-- Agricultural fields often have no street address; location_create takes
-- lat+lng of the corner and leaves street_address empty. A farm 911 /
-- nearest-road string can live in nearest_road for humans; do not pass it
-- as street_address if you also have the corner (geocoding would move the
-- pin to the mailbox).
-- One ZenSched EVENT per field per rolling window of at most 60 days.
-- zensched_event_id is the CURRENT event; event_valid_until is its last
-- valid date. Cadence (frequency, next date, rate) is PER FIELD.
CREATE TABLE IF NOT EXISTS fields (
  field_id INTEGER PRIMARY KEY AUTOINCREMENT,
  grower_id INTEGER NOT NULL,
  field_name TEXT NOT NULL,                         -- 'North 80', 'Block 12'
  field_label TEXT,                                 -- sent to ZenSched: 'Rivera - North 80' (keep ≤50)
  crop TEXT,                                        -- 'corn', 'soy', 'wheat', 'cotton', 'cane'
  acres REAL,
  county TEXT,
  township TEXT,
  nearest_road TEXT,                                -- human hint only; not the pin
  corner_lat REAL,                                  -- GPS corner (decimal degrees)
  corner_lng REAL,
  access_notes TEXT,                                -- LOCAL ONLY: gate, muddy approach, dog
  service_id INTEGER,                               -- default recurring service for this field
  service_rate REAL NOT NULL,                       -- price per visit (may differ from the list)
  service_frequency TEXT NOT NULL
    CHECK (service_frequency IN ('weekly', 'biweekly', 'monthly', 'seasonal', 'on-demand')),
  next_service_date TEXT,                           -- ISO date: '2026-09-07'
  last_service_date TEXT,                           -- set automatically when a visit is recorded
  preferred_start TEXT                              -- 'HH:MM' 24-hour local; NULL = settings.default_shift_start
    CHECK (preferred_start IS NULL OR preferred_start GLOB '[0-2][0-9]:[0-5][0-9]'),
  zensched_worker_id INTEGER,                       -- preferred scout; NULL = settings.default_worker_id
  zensched_location_id INTEGER,                     -- from location_create (permanent)
  zensched_event_id INTEGER,                        -- from event_create (current <=60-day window)
  event_valid_until TEXT,                           -- ISO date: last day the current event covers
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (grower_id) REFERENCES growers(grower_id) ON DELETE CASCADE,
  FOREIGN KEY (service_id) REFERENCES services(service_id)
);

-- Scouts: your roster. zensched_worker_id comes from worker_invite.
-- license_no is LOCAL ONLY (CCA / PCA / state agronomist number).
CREATE TABLE IF NOT EXISTS scouts (
  scout_id INTEGER PRIMARY KEY AUTOINCREMENT,
  scout_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite
  license_no TEXT,                                  -- LOCAL ONLY
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Visits: one row per COMPLETED scout visit, linked to the ZenSched shift
-- and the Scout Record form submission. growth_stage / pest_type are
-- CHECK-constrained to the form's option labels. pest_count is the number
-- the scout typed (per plant, per 20 plants, per sweep — whatever they use).
CREATE TABLE IF NOT EXISTS visits (
  visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  grower_id INTEGER NOT NULL,
  field_id INTEGER NOT NULL,
  service_id INTEGER NOT NULL,
  scout_id INTEGER,                                 -- local roster row (trigger fills from worker id)
  completed_date TEXT NOT NULL,                     -- ISO date: '2026-09-07'
  amount REAL NOT NULL,
  zensched_shift_id INTEGER UNIQUE,                 -- prevents recording the same shift twice
  zensched_event_id INTEGER,
  zensched_worker_id INTEGER,
  actual_in TEXT,                                   -- from shift_status / timesheet_export
  actual_out TEXT,
  duration_minutes INTEGER,
  gps_verified INTEGER,                             -- 1 if the check-in punch was on site
  report_dc_id INTEGER,                             -- Scout Record submission_id
  growth_stage TEXT
    CHECK (growth_stage IS NULL OR growth_stage IN ('Emergence', 'Vegetative', 'Flowering', 'Grain fill', 'Mature', 'Post-harvest')),
  pest_count REAL,                                  -- as typed on the form (number)
  pest_type TEXT
    CHECK (pest_type IS NULL OR pest_type IN ('None', 'Aphids', 'Armyworm', 'Corn rootworm', 'Spider mites', 'Whitefly', 'Weeds', 'Disease', 'Other')),
  notes TEXT,
  photo_urls TEXT,                                  -- JSON array of canopy media URLs
  invoiced INTEGER DEFAULT 0,                       -- 1 = included in an invoice
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (grower_id) REFERENCES growers(grower_id) ON DELETE CASCADE,
  FOREIGN KEY (field_id) REFERENCES fields(field_id) ON DELETE CASCADE,
  FOREIGN KEY (service_id) REFERENCES services(service_id),
  FOREIGN KEY (scout_id) REFERENCES scouts(scout_id) ON DELETE SET NULL
);

-- Invoices: billing records, one per grower per draft.
-- invoice_number is filled in automatically by a trigger if left NULL.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  grower_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,                       -- human-readable: 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,                           -- 1 = paid, 0 = unpaid
  paid_date TEXT,
  sent_date TEXT,                                   -- when you actually emailed/texted it
  line_items TEXT,                                  -- JSON array of visit references
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (grower_id) REFERENCES growers(grower_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_fields_grower ON fields(grower_id);
CREATE INDEX IF NOT EXISTS idx_fields_next_service ON fields(next_service_date, is_active);
CREATE INDEX IF NOT EXISTS idx_fields_service ON fields(service_id);
CREATE INDEX IF NOT EXISTS idx_fields_zensched_location ON fields(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_fields_zensched_event ON fields(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_scouts_worker ON scouts(zensched_worker_id);
CREATE INDEX IF NOT EXISTS idx_visits_grower ON visits(grower_id, completed_date);
CREATE INDEX IF NOT EXISTS idx_visits_field ON visits(field_id, completed_date);
CREATE INDEX IF NOT EXISTS idx_visits_invoiced ON visits(invoiced);
CREATE INDEX IF NOT EXISTS idx_invoices_grower ON invoices(grower_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_grower_timestamp
AFTER UPDATE ON growers
BEGIN
  UPDATE growers SET updated_at = datetime('now') WHERE grower_id = NEW.grower_id;
END;

CREATE TRIGGER IF NOT EXISTS update_field_timestamp
AFTER UPDATE ON fields
BEGIN
  UPDATE fields SET updated_at = datetime('now') WHERE field_id = NEW.field_id;
END;

CREATE TRIGGER IF NOT EXISTS update_scout_timestamp
AFTER UPDATE ON scouts
BEGIN
  UPDATE scouts SET updated_at = datetime('now') WHERE scout_id = NEW.scout_id;
END;

-- Fill scout_id from the roster when the agent only has the ZenSched worker id.
CREATE TRIGGER IF NOT EXISTS fill_visit_scout
AFTER INSERT ON visits
WHEN NEW.scout_id IS NULL AND NEW.zensched_worker_id IS NOT NULL
BEGIN
  UPDATE visits
  SET scout_id = (SELECT scout_id FROM scouts WHERE zensched_worker_id = NEW.zensched_worker_id)
  WHERE visit_id = NEW.visit_id;
END;

-- Recording a completed visit automatically advances the FIELD's cadence.
-- seasonal is +90 days (not +3 months). on-demand clears the next date.
-- The agent should NOT hand-maintain next_service_date after this.
-- A one-off recorded on a recurring field also moves the cadence; if the
-- owner wants the regular walk kept, set next_service_date back explicitly.
CREATE TRIGGER IF NOT EXISTS advance_service_date_on_visit
AFTER INSERT ON visits
BEGIN
  UPDATE fields
  SET last_service_date = NEW.completed_date,
      next_service_date = CASE service_frequency
        WHEN 'weekly'    THEN date(NEW.completed_date, '+7 days')
        WHEN 'biweekly'  THEN date(NEW.completed_date, '+14 days')
        WHEN 'monthly'   THEN date(NEW.completed_date, '+1 month')
        WHEN 'seasonal'  THEN date(NEW.completed_date, '+90 days')
        ELSE NULL                                    -- on-demand: no automatic next visit
      END
  WHERE field_id = NEW.field_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Who is due in the next 7 days (today + 6). The agent's weekly scheduling
-- query. One row = one shift_create call. Columns ending in _iso are ready
-- to pass as shift_create start/end; idempotency_key is ready too.
-- event_needs_roll = 1 means create a new ZenSched event first (see SKILL.md).
-- access_notes is included so the agent can tell the owner to pass it to the
-- scout; it must never go into a ZenSched field.
CREATE VIEW IF NOT EXISTS fields_due AS
SELECT
  g.grower_id,
  g.grower_name,
  g.farm_name,
  g.contact_email,
  g.contact_phone,
  f.field_id,
  f.field_name,
  f.field_label,
  f.crop,
  f.acres,
  f.county,
  f.township,
  f.nearest_road,
  f.corner_lat,
  f.corner_lng,
  f.access_notes,
  f.service_rate,
  f.service_frequency,
  f.next_service_date,
  COALESCE(f.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start')) AS start_time,
  sv.service_id,
  sv.code                                    AS service_code,
  sv.service_name,
  COALESCE(sv.default_minutes, CAST((SELECT value FROM settings WHERE key = 'default_shift_minutes') AS INTEGER)) AS default_minutes,
  f.zensched_location_id,
  f.zensched_event_id,
  f.event_valid_until,
  CASE WHEN f.event_valid_until IS NULL OR f.event_valid_until < f.next_service_date THEN 1 ELSE 0 END AS event_needs_roll,
  COALESCE(f.zensched_worker_id, (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id')) AS worker_id,
  (SELECT s.scout_name FROM scouts s
    WHERE s.zensched_worker_id = COALESCE(f.zensched_worker_id,
           (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_worker_id'))) AS scout_name,
  f.next_service_date || 'T'
    || COALESCE(f.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
    || ':00' || (SELECT value FROM settings WHERE key = 'timezone_offset') AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(
      f.next_service_date || ' '
      || COALESCE(f.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start'))
      || ':00',
      '+' || COALESCE(sv.default_minutes, CAST((SELECT value FROM settings WHERE key = 'default_shift_minutes') AS INTEGER)) || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset') AS end_iso,
  'shift-field-' || f.field_id || '-' || strftime('%Y%m%d', f.next_service_date) AS idempotency_key
FROM fields f
JOIN growers g ON g.grower_id = f.grower_id AND g.is_active = 1
LEFT JOIN services sv ON sv.service_id = f.service_id
WHERE f.is_active = 1
  AND f.next_service_date IS NOT NULL
  AND f.next_service_date <= date('now', '+7 days')
ORDER BY f.next_service_date, COALESCE(f.preferred_start, (SELECT value FROM settings WHERE key = 'default_shift_start')), g.grower_name, f.field_name;

-- Fields whose current ZenSched event expires within 14 days (or has none)
-- and that belong to an active grower. Roll these proactively.
CREATE VIEW IF NOT EXISTS events_expiring AS
SELECT
  f.field_id,
  g.grower_name,
  f.field_name,
  f.field_label,
  f.zensched_location_id,
  f.zensched_event_id,
  f.event_valid_until
FROM fields f
JOIN growers g ON g.grower_id = f.grower_id AND g.is_active = 1
WHERE f.is_active = 1
  AND (f.event_valid_until IS NULL OR f.event_valid_until <= date('now', '+14 days'))
ORDER BY f.event_valid_until;

-- Completed work that has not been invoiced yet, grouped by grower.
CREATE VIEW IF NOT EXISTS visits_to_invoice AS
SELECT
  g.grower_id,
  g.grower_name,
  g.farm_name,
  g.contact_email,
  g.billing_notes,
  COUNT(v.visit_id)       AS visit_count,
  SUM(v.amount)           AS total_amount,
  MIN(v.completed_date)   AS first_visit_date,
  MAX(v.completed_date)   AS last_visit_date
FROM visits v
JOIN growers g ON g.grower_id = v.grower_id
WHERE v.invoiced = 0
GROUP BY g.grower_id
ORDER BY g.grower_name;

-- Unpaid invoices, oldest first.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  g.grower_name,
  g.farm_name,
  g.contact_email,
  i.invoice_date,
  i.due_date,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue
FROM invoices i
JOIN growers g ON g.grower_id = i.grower_id
WHERE i.paid = 0
ORDER BY i.due_date;

-- Owner's local scout-log extract: one row per recorded visit. This is the
-- owner's copy of growth stage / pest count / pest type, not a CCA
-- recommendation and not a spray log. Visits with pest_type None are kept
-- (a zero-pressure walk is still a billed scout).
CREATE VIEW IF NOT EXISTS scout_log AS
SELECT
  v.visit_id,
  v.completed_date                               AS scout_date,
  f.field_name,
  f.field_label,
  f.crop,
  f.acres,
  f.county,
  g.grower_name,
  g.farm_name,
  v.growth_stage,
  v.pest_type,
  v.pest_count,
  COALESCE(s.scout_name, 'scout ' || v.zensched_worker_id) AS scout,
  v.notes,
  v.zensched_shift_id,
  v.report_dc_id,
  v.gps_verified
FROM visits v
JOIN fields f ON f.field_id = v.field_id
JOIN growers g ON g.grower_id = v.grower_id
LEFT JOIN scouts s ON s.scout_id = v.scout_id
ORDER BY v.completed_date DESC, g.grower_name, f.field_name;
