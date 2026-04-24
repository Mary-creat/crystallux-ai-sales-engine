-- ══════════════════════════════════════════════════════════════════
-- Geographic Appointment Optimization (B.12b-1 / Component 4)
-- ══════════════════════════════════════════════════════════════════
-- For verticals where agents travel between appointments (insurance
-- brokers, real estate, construction), minimize drive time by
-- clustering same-region appointments and ordering them sensibly.
--
-- Scope: geocode each appointment once (cached in appointment_log),
-- compute daily route optimizations by haversine distance (no paid
-- map API required for MVP), expose via dashboard widget using
-- Leaflet (free OSM tiles).
--
-- Additive only. Claims no ownership of appointment_log — extends it.
-- ══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 1. appointment_log geo columns
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS address_line        text;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS city                 text;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS province             text;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS postal_code          text;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS country              text DEFAULT 'CA';
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS latitude             numeric(9,6);
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS longitude            numeric(9,6);
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS geocoded_at          timestamptz;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS geocoder             text;   -- 'nominatim' | 'google' | 'manual' | 'lead'
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS travel_time_prev_min integer;
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS drive_distance_km    numeric(6,2);
ALTER TABLE appointment_log ADD COLUMN IF NOT EXISTS route_batch_id       uuid;

CREATE INDEX IF NOT EXISTS idx_appointment_log_geocoded
  ON appointment_log(client_id, scheduled_start)
  WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────
-- 2. clients geo + agent base columns
-- ─────────────────────────────────────────────────────────────────
-- Where the agent starts and ends their day. Used for route
-- optimization anchors.

ALTER TABLE clients ADD COLUMN IF NOT EXISTS base_address         text;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS base_latitude        numeric(9,6);
ALTER TABLE clients ADD COLUMN IF NOT EXISTS base_longitude       numeric(9,6);
ALTER TABLE clients ADD COLUMN IF NOT EXISTS travel_optimization_enabled boolean DEFAULT false;
ALTER TABLE clients ADD COLUMN IF NOT EXISTS max_daily_km         integer;           -- optional cap used by suggester
ALTER TABLE clients ADD COLUMN IF NOT EXISTS preferred_drive_speed_kmh integer DEFAULT 40;

-- ─────────────────────────────────────────────────────────────────
-- 3. travel_optimization_log — one row per day's route
-- ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS travel_optimization_log (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id                uuid REFERENCES clients(id) ON DELETE CASCADE,
  agent_id                 uuid,
  optimized_for_date       date NOT NULL,
  generated_at             timestamptz DEFAULT now(),
  appointment_count        integer,
  total_km_before          numeric(7,2),
  total_km_after           numeric(7,2),
  total_minutes_before     integer,
  total_minutes_after      integer,
  saved_minutes            integer,
  ordered_appointment_ids  jsonb,              -- [uuid, uuid, ...] in suggested order
  route_geometry           jsonb,              -- optional: [[lat,lng], ...] for map rendering
  generator_source         text,               -- 'haversine' | 'google_directions' | 'manual'
  notes                    text,
  UNIQUE(client_id, agent_id, optimized_for_date)
);

CREATE INDEX IF NOT EXISTS idx_travel_opt_client_date
  ON travel_optimization_log(client_id, optimized_for_date DESC);

-- ─────────────────────────────────────────────────────────────────
-- 4. RLS
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE travel_optimization_log ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY travel_optimization_log_service_role_all ON travel_optimization_log
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────────────────────────────────────────────────
-- 5. RPCs
-- ─────────────────────────────────────────────────────────────────

-- 5.1 Return appointments that still need geocoding (within last 30 days
-- of scheduled_start or upcoming).
CREATE OR REPLACE FUNCTION get_ungeocoded_appointments(p_limit integer DEFAULT 50)
RETURNS TABLE(
  id              uuid,
  client_id       uuid,
  address_line    text,
  city            text,
  province        text,
  postal_code     text,
  country         text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT a.id, a.client_id,
           a.address_line, a.city, a.province, a.postal_code,
           COALESCE(a.country,'CA')::text
      FROM appointment_log a
     WHERE a.latitude IS NULL
       AND (a.address_line IS NOT NULL OR a.city IS NOT NULL OR a.postal_code IS NOT NULL)
       AND a.scheduled_start > now() - interval '30 days'
     ORDER BY a.scheduled_start ASC
     LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION get_ungeocoded_appointments(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_ungeocoded_appointments(integer) TO service_role;

-- 5.2 Persist geocoded coordinates on an appointment.
CREATE OR REPLACE FUNCTION update_appointment_geocode(
  p_appointment_id uuid,
  p_latitude       numeric,
  p_longitude      numeric,
  p_geocoder       text
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE appointment_log
     SET latitude    = p_latitude,
         longitude   = p_longitude,
         geocoded_at = now(),
         geocoder    = COALESCE(p_geocoder,'unknown'),
         updated_at  = now()
   WHERE id = p_appointment_id;
END;
$$;

REVOKE ALL ON FUNCTION update_appointment_geocode(uuid, numeric, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_appointment_geocode(uuid, numeric, numeric, text) TO service_role;

-- 5.3 Fetch a day's appointments with geo + drive data for the map.
CREATE OR REPLACE FUNCTION get_daily_geo_appointments(
  p_client_id uuid,
  p_date      date DEFAULT CURRENT_DATE
)
RETURNS TABLE(
  appointment_id       uuid,
  scheduled_start      timestamptz,
  scheduled_end        timestamptz,
  appointment_type     text,
  outcome              text,
  lead_id              uuid,
  lead_name            text,
  address_line         text,
  city                 text,
  province             text,
  latitude             numeric,
  longitude            numeric,
  travel_time_prev_min integer,
  drive_distance_km    numeric,
  route_batch_id       uuid
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT  a.id, a.scheduled_start, a.scheduled_end, a.appointment_type,
            a.outcome, a.lead_id,
            (COALESCE(l.first_name,'') || ' ' || COALESCE(l.last_name,''))::text,
            a.address_line, a.city, a.province,
            a.latitude, a.longitude, a.travel_time_prev_min, a.drive_distance_km,
            a.route_batch_id
      FROM  appointment_log a
      LEFT JOIN leads l ON l.id = a.lead_id
     WHERE  a.client_id = p_client_id
       AND  a.scheduled_start::date = p_date
     ORDER BY a.scheduled_start ASC;
END;
$$;

REVOKE ALL ON FUNCTION get_daily_geo_appointments(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_daily_geo_appointments(uuid, date) TO service_role;

-- 5.4 Persist an optimized route (called by clx-route-optimizer-v1).
CREATE OR REPLACE FUNCTION record_route_optimization(
  p_client_id              uuid,
  p_agent_id               uuid,
  p_date                   date,
  p_ordered_appointment_ids jsonb,
  p_km_before              numeric,
  p_km_after               numeric,
  p_minutes_before         integer,
  p_minutes_after          integer,
  p_generator_source       text DEFAULT 'haversine',
  p_route_geometry         jsonb DEFAULT NULL,
  p_notes                  text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id      uuid;
  v_batch   uuid := gen_random_uuid();
  v_count   integer;
  v_elem    text;
  v_rank    integer := 0;
  v_prev_id uuid;
  v_prev_start timestamptz;
BEGIN
  v_count := COALESCE(jsonb_array_length(p_ordered_appointment_ids), 0);

  INSERT INTO travel_optimization_log (
    client_id, agent_id, optimized_for_date, appointment_count,
    total_km_before, total_km_after, total_minutes_before, total_minutes_after,
    saved_minutes, ordered_appointment_ids, generator_source,
    route_geometry, notes
  )
  VALUES (
    p_client_id, p_agent_id, p_date, v_count,
    p_km_before, p_km_after, p_minutes_before, p_minutes_after,
    GREATEST(COALESCE(p_minutes_before,0) - COALESCE(p_minutes_after,0), 0),
    COALESCE(p_ordered_appointment_ids,'[]'::jsonb),
    COALESCE(p_generator_source,'haversine'),
    p_route_geometry, p_notes
  )
  ON CONFLICT (client_id, agent_id, optimized_for_date) DO UPDATE SET
    appointment_count       = EXCLUDED.appointment_count,
    total_km_before         = EXCLUDED.total_km_before,
    total_km_after          = EXCLUDED.total_km_after,
    total_minutes_before    = EXCLUDED.total_minutes_before,
    total_minutes_after     = EXCLUDED.total_minutes_after,
    saved_minutes           = EXCLUDED.saved_minutes,
    ordered_appointment_ids = EXCLUDED.ordered_appointment_ids,
    generator_source        = EXCLUDED.generator_source,
    route_geometry          = EXCLUDED.route_geometry,
    notes                   = EXCLUDED.notes,
    generated_at            = now()
  RETURNING id INTO v_id;

  -- Attach the route_batch_id to each appointment so the dashboard
  -- map can filter by it.
  UPDATE appointment_log a
     SET route_batch_id = v_batch,
         updated_at     = now()
    FROM (
      SELECT (elem #>> '{}')::uuid AS appt_id, ordinality
        FROM jsonb_array_elements(p_ordered_appointment_ids) WITH ORDINALITY AS t(elem, ordinality)
    ) orderedAppts
   WHERE a.id = orderedAppts.appt_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION record_route_optimization(uuid, uuid, date, jsonb, numeric, numeric, integer, integer, text, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION record_route_optimization(uuid, uuid, date, jsonb, numeric, numeric, integer, integer, text, jsonb, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- 6. Monitoring seeds
-- ─────────────────────────────────────────────────────────────────

INSERT INTO scan_errors (error_code, severity, category, description, suggested_action, created_at)
SELECT 'GEOCODE_FAILED', 'warning', 'geo',
       'Geocoder returned no result for an appointment address.',
       'Confirm address is parseable; fall back to postal_code geocoding.', now()
WHERE NOT EXISTS (SELECT 1 FROM scan_errors WHERE error_code='GEOCODE_FAILED');

INSERT INTO scan_errors (error_code, severity, category, description, suggested_action, created_at)
SELECT 'ROUTE_OPT_SKIPPED', 'info', 'geo',
       'Route optimizer skipped — fewer than 2 geocoded appointments for the day.',
       'No action needed; optimizer only runs when 2+ on-site visits exist.', now()
WHERE NOT EXISTS (SELECT 1 FROM scan_errors WHERE error_code='ROUTE_OPT_SKIPPED');

-- ─────────────────────────────────────────────────────────────────
-- 7. Verification queries
-- ─────────────────────────────────────────────────────────────────
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='appointment_log' AND column_name IN ('latitude','longitude','route_batch_id');
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name='clients' AND column_name IN ('base_latitude','travel_optimization_enabled');
-- SELECT count(*) FROM travel_optimization_log;  -- 0 expected
-- SELECT proname FROM pg_proc WHERE proname IN (
--   'get_ungeocoded_appointments','update_appointment_geocode',
--   'get_daily_geo_appointments','record_route_optimization'
-- );

-- ─────────────────────────────────────────────────────────────────
-- 8. ROLLBACK
-- ─────────────────────────────────────────────────────────────────
-- DROP FUNCTION IF EXISTS record_route_optimization(uuid, uuid, date, jsonb, numeric, numeric, integer, integer, text, jsonb, text);
-- DROP FUNCTION IF EXISTS get_daily_geo_appointments(uuid, date);
-- DROP FUNCTION IF EXISTS update_appointment_geocode(uuid, numeric, numeric, text);
-- DROP FUNCTION IF EXISTS get_ungeocoded_appointments(integer);
-- DROP TABLE IF EXISTS travel_optimization_log;
-- ALTER TABLE clients
--   DROP COLUMN IF EXISTS base_address,
--   DROP COLUMN IF EXISTS base_latitude,
--   DROP COLUMN IF EXISTS base_longitude,
--   DROP COLUMN IF EXISTS travel_optimization_enabled,
--   DROP COLUMN IF EXISTS max_daily_km,
--   DROP COLUMN IF EXISTS preferred_drive_speed_kmh;
-- ALTER TABLE appointment_log
--   DROP COLUMN IF EXISTS address_line,
--   DROP COLUMN IF EXISTS city,
--   DROP COLUMN IF EXISTS province,
--   DROP COLUMN IF EXISTS postal_code,
--   DROP COLUMN IF EXISTS country,
--   DROP COLUMN IF EXISTS latitude,
--   DROP COLUMN IF EXISTS longitude,
--   DROP COLUMN IF EXISTS geocoded_at,
--   DROP COLUMN IF EXISTS geocoder,
--   DROP COLUMN IF EXISTS travel_time_prev_min,
--   DROP COLUMN IF EXISTS drive_distance_km,
--   DROP COLUMN IF EXISTS route_batch_id;
