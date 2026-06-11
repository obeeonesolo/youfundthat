-- ============================================================
-- YouFundThat — Support des intégrations (section 10.3)
-- Alerte automatique si une source primaire devient inaccessible.
-- ============================================================

CREATE TABLE IF NOT EXISTS link_alerts (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fact_id     uuid NOT NULL REFERENCES facts(id) ON DELETE CASCADE,
  source_url  text NOT NULL,
  http_status integer,                 -- NULL = erreur réseau (timeout, DNS)
  detail      text,
  detected_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz              -- NULL = alerte ouverte
);

CREATE INDEX IF NOT EXISTS idx_link_alerts_open
  ON link_alerts (fact_id) WHERE resolved_at IS NULL;

ALTER TABLE link_alerts ENABLE ROW LEVEL SECURITY;

-- Lecture : éditeurs uniquement (liste de travail interne — les liens
-- morts non traités ne sont pas une information publique fiable).
DROP POLICY IF EXISTS link_alerts_read_editors ON link_alerts;
CREATE POLICY link_alerts_read_editors ON link_alerts
  FOR SELECT USING (yft_is_editor());

-- Écriture : aucune policy — seul service_role (bypass RLS) écrit,
-- c'est-à-dire les scripts d'intégration exécutés en cron.

-- Résolution par un éditeur
DROP POLICY IF EXISTS link_alerts_resolve_editors ON link_alerts;
CREATE POLICY link_alerts_resolve_editors ON link_alerts
  FOR UPDATE USING (yft_is_editor()) WITH CHECK (yft_is_editor());

DO $$ BEGIN
  GRANT SELECT, UPDATE ON link_alerts TO authenticated;
EXCEPTION WHEN undefined_object THEN
  RAISE NOTICE 'Rôle authenticated absent (hors Supabase) — grant ignoré';
END $$;
