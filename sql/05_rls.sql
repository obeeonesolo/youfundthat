-- ============================================================
-- YouFundThat — Row Level Security (Supabase)
-- Modèle de menace :
--   - anon (public)        : lit les faits VÉRIFIÉS, les scores,
--                            l'audit ; peut déposer une contestation.
--   - authenticated        : comme anon (sauf si éditeur).
--   - éditeur (table editors) : propose des faits (verified=false),
--                            valide les faits des AUTRES éditeurs.
--   - service_role/postgres: bypass RLS (migrations, cron).
-- Le principe "verified=false => jamais affiché" (section 2.2)
-- est imposé ICI, au niveau base — pas seulement dans le frontend.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Table des éditeurs (référence auth.users de Supabase)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS editors (
  user_id  uuid PRIMARY KEY,            -- = auth.users.id sur Supabase
  role     text NOT NULL DEFAULT 'editor' CHECK (role IN ('editor', 'admin')),
  added_at timestamptz NOT NULL DEFAULT now()
);

-- Helper : l'utilisateur courant est-il éditeur ?
-- SECURITY DEFINER : consultable depuis les policies sans exposer
-- la table editors en lecture publique.
CREATE OR REPLACE FUNCTION yft_is_editor() RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM editors WHERE user_id = auth.uid());
EXCEPTION WHEN undefined_function OR invalid_schema_name THEN
  RETURN false;  -- hors Supabase sans stub auth.uid()
END;
$$;

CREATE OR REPLACE FUNCTION yft_is_admin() RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM editors WHERE user_id = auth.uid() AND role = 'admin');
EXCEPTION WHEN undefined_function OR invalid_schema_name THEN
  RETURN false;
END;
$$;

-- ------------------------------------------------------------
-- 2. Les triggers de recalcul et d'audit doivent fonctionner
--    même quand l'appelant n'a pas de droits directs sur les
--    tables cibles (companies, audit_log).
-- ------------------------------------------------------------
ALTER FUNCTION yft_refresh_company_score() SECURITY DEFINER SET search_path = public;

-- ------------------------------------------------------------
-- 3. Double validation (workflow 10.1, étape 5) :
--    le validateur DOIT être différent du proposeur.
--    Imposé par trigger — aucune policy ne peut le contourner.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION yft_enforce_double_validation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.verified = true
     AND (TG_OP = 'INSERT' OR OLD.verified IS DISTINCT FROM true) THEN
    IF NEW.verified_by IS NOT DISTINCT FROM NEW.proposed_by THEN
      RAISE EXCEPTION 'Double validation requise : le validateur (verified_by) doit être différent du proposeur (proposed_by) — workflow 10.1 étape 5';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_facts_double_validation ON facts;
CREATE TRIGGER trg_facts_double_validation
  BEFORE INSERT OR UPDATE ON facts
  FOR EACH ROW EXECUTE FUNCTION yft_enforce_double_validation();

-- ------------------------------------------------------------
-- 4. Activation RLS
-- ------------------------------------------------------------
ALTER TABLE companies     ENABLE ROW LEVEL SECURITY;
ALTER TABLE facts         ENABLE ROW LEVEL SECURITY;
ALTER TABLE contestations ENABLE ROW LEVEL SECURITY;
ALTER TABLE editors       ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log     ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- 5. Policies — companies
-- ------------------------------------------------------------
DROP POLICY IF EXISTS companies_read_public ON companies;
CREATE POLICY companies_read_public ON companies
  FOR SELECT USING (true);                          -- fiches publiques

DROP POLICY IF EXISTS companies_write_editors ON companies;
CREATE POLICY companies_write_editors ON companies
  FOR ALL USING (yft_is_editor()) WITH CHECK (yft_is_editor());

-- ------------------------------------------------------------
-- 6. Policies — facts
--    Le public ne voit JAMAIS un fait non vérifié (Principe 1).
-- ------------------------------------------------------------
DROP POLICY IF EXISTS facts_read_verified_public ON facts;
CREATE POLICY facts_read_verified_public ON facts
  FOR SELECT USING (verified = true OR yft_is_editor());

-- Un éditeur propose un fait : toujours verified=false à l'entrée
-- (workflow 10.1 étape 4 — la validation est un second temps).
DROP POLICY IF EXISTS facts_insert_editors ON facts;
CREATE POLICY facts_insert_editors ON facts
  FOR INSERT WITH CHECK (yft_is_editor() AND verified = false);

DROP POLICY IF EXISTS facts_update_editors ON facts;
CREATE POLICY facts_update_editors ON facts
  FOR UPDATE USING (yft_is_editor()) WITH CHECK (yft_is_editor());

-- Suppression : admin uniquement (un fait erroné se supprime après
-- contestation fondée — décision qui engage la responsabilité).
DROP POLICY IF EXISTS facts_delete_admin ON facts;
CREATE POLICY facts_delete_admin ON facts
  FOR DELETE USING (yft_is_admin());

-- ------------------------------------------------------------
-- 7. Policies — contestations (section 10.2)
--    "Tout utilisateur peut contester" : INSERT ouvert, y compris anon.
--    "Archivées et publiques" : SELECT ouvert.
--    Résolution : éditeurs uniquement.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS contestations_read_public ON contestations;
CREATE POLICY contestations_read_public ON contestations
  FOR SELECT USING (true);

DROP POLICY IF EXISTS contestations_insert_public ON contestations;
CREATE POLICY contestations_insert_public ON contestations
  FOR INSERT WITH CHECK (
    status = 'open' AND resolution IS NULL AND resolved_at IS NULL
  );

DROP POLICY IF EXISTS contestations_resolve_editors ON contestations;
CREATE POLICY contestations_resolve_editors ON contestations
  FOR UPDATE USING (yft_is_editor()) WITH CHECK (yft_is_editor());

-- Pas de policy DELETE : une contestation ne se supprime jamais
-- (archivage public obligatoire).

-- ------------------------------------------------------------
-- 8. Policies — editors (gestion par admin uniquement)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS editors_read_self ON editors;
CREATE POLICY editors_read_self ON editors
  FOR SELECT USING (user_id = auth.uid() OR yft_is_admin());

DROP POLICY IF EXISTS editors_manage_admin ON editors;
CREATE POLICY editors_manage_admin ON editors
  FOR ALL USING (yft_is_admin()) WITH CHECK (yft_is_admin());

-- ------------------------------------------------------------
-- 9. Policies — audit_log
--    Lecture publique (transparence totale) ; AUCUNE policy
--    d'écriture : seul le trigger SECURITY DEFINER écrit.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS audit_read_public ON audit_log;
CREATE POLICY audit_read_public ON audit_log
  FOR SELECT USING (true);

-- ------------------------------------------------------------
-- 10. Grants (Supabase crée anon/authenticated ; idempotent)
-- ------------------------------------------------------------
DO $$ BEGIN
  GRANT USAGE ON SCHEMA public TO anon, authenticated;
  GRANT SELECT ON companies, facts, contestations, audit_log, v_company_scores
    TO anon, authenticated;
  GRANT INSERT ON contestations TO anon, authenticated;
  GRANT SELECT ON editors TO authenticated;
  GRANT INSERT, UPDATE ON facts TO authenticated;
  GRANT INSERT, UPDATE, DELETE ON companies TO authenticated;
  GRANT DELETE ON facts TO authenticated;        -- filtré par policy admin
  GRANT UPDATE ON contestations TO authenticated;
  GRANT ALL ON editors TO authenticated;          -- filtré par policy admin
EXCEPTION WHEN undefined_object THEN
  RAISE NOTICE 'Rôles anon/authenticated absents (hors Supabase) — grants ignorés';
END $$;
