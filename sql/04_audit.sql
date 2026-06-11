-- ============================================================
-- YouFundThat — Journal d'audit (section 10.2)
-- "Toutes les contestations et leurs résolutions sont archivées
--  et publiques" — étendu à toute modification de faits.
-- Le journal est IMMUABLE : insertion par trigger uniquement,
-- aucun UPDATE/DELETE possible, même pour les éditeurs.
-- ============================================================

CREATE TABLE IF NOT EXISTS audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  table_name  text NOT NULL,
  record_id   uuid,
  action      text NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
  old_data    jsonb,                       -- état avant (UPDATE/DELETE)
  new_data    jsonb,                       -- état après (INSERT/UPDATE)
  changed_by  text NOT NULL,               -- auth.uid() Supabase ou rôle SQL
  changed_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_record ON audit_log (table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_audit_time   ON audit_log (changed_at DESC);

-- ------------------------------------------------------------
-- Fonction de capture générique
-- SECURITY DEFINER : les éditeurs n'ont pas besoin (et n'ont pas)
-- de droit INSERT direct sur audit_log — seul le trigger écrit.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION yft_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_who text;
BEGIN
  -- Sur Supabase : identifiant de l'utilisateur authentifié.
  -- Hors Supabase (tests, migration) : rôle SQL courant.
  BEGIN
    v_who := COALESCE(auth.uid()::text, current_user);
  EXCEPTION WHEN undefined_function OR invalid_schema_name THEN
    v_who := current_user;
  END;

  INSERT INTO audit_log (table_name, record_id, action, old_data, new_data, changed_by)
  VALUES (
    TG_TABLE_NAME,
    COALESCE(NEW.id, OLD.id),
    TG_OP,
    CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END,
    CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END,
    v_who
  );
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Audit sur facts : la source de vérité du score.
-- (companies n'est pas auditée : score_global/label sont des caches
--  dérivés des facts — les auditer dupliquerait chaque événement.)
DROP TRIGGER IF EXISTS trg_facts_audit ON facts;
CREATE TRIGGER trg_facts_audit
  AFTER INSERT OR UPDATE OR DELETE ON facts
  FOR EACH ROW EXECUTE FUNCTION yft_audit();

DROP TRIGGER IF EXISTS trg_contestations_audit ON contestations;
CREATE TRIGGER trg_contestations_audit
  AFTER INSERT OR UPDATE OR DELETE ON contestations
  FOR EACH ROW EXECUTE FUNCTION yft_audit();

-- ------------------------------------------------------------
-- Immuabilité : interdire UPDATE et DELETE sur le journal,
-- y compris pour les éditeurs (défense en profondeur, en plus
-- de l'absence de policy RLS d'écriture).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION yft_audit_immutable() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_log est immuable — aucune modification ni suppression autorisée';
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_immutable ON audit_log;
CREATE TRIGGER trg_audit_immutable
  BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION yft_audit_immutable();
