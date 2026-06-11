-- ============================================================
-- YouFundThat — Tests RLS + Audit
-- Simule l'environnement Supabase en local :
--   - stub auth.uid() lisant request.jwt.claim.sub
--   - rôles anon / authenticated
-- Scénarios testés = scénarios d'ATTAQUE, pas seulement le happy path.
-- ============================================================

\set ON_ERROR_STOP on

-- Prérequis : tests/00_local_supabase_stub.sql exécuté AVANT sql/05_rls.sql

-- Rejouer les grants de 05_rls.sql au cas où les rôles ont été créés après
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON companies, facts, contestations, audit_log, v_company_scores TO anon, authenticated;
GRANT INSERT ON contestations TO anon, authenticated;
GRANT SELECT ON editors TO authenticated;
GRANT INSERT, UPDATE, DELETE ON facts TO authenticated;
GRANT INSERT, UPDATE, DELETE ON companies TO authenticated;
GRANT UPDATE ON contestations TO authenticated;
GRANT ALL ON editors TO authenticated;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;

-- ------------------------------------------------------------
-- Nettoyage des artefacts d'exécutions précédentes (idempotence)
-- ------------------------------------------------------------
DELETE FROM facts WHERE description IN (
  'Enquête optimisation fiscale (Le Monde 2025)',
  'FAIT NON VÉRIFIÉ — ne doit pas fuiter'
);
DELETE FROM contestations WHERE submitted_by = 'citoyen@example.be'
   OR argument LIKE '%frauduleuse%';

-- ------------------------------------------------------------
-- Données de test : 2 éditeurs + 1 fait non vérifié
-- ------------------------------------------------------------
DO $$
DECLARE
  ed1 CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  ed2 CONSTANT uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  INSERT INTO editors (user_id, role) VALUES (ed1, 'editor'), (ed2, 'admin')
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO facts (id, company_id, axis, fact_type, weight, year, verified, source_url, description, proposed_by)
  VALUES ('99999999-0000-0000-0000-000000000001',
          '00000000-0000-0000-0000-000000000001',
          'lobbying', 'negative', 1, 2025, false,
          'https://test.example/unverified', 'FAIT NON VÉRIFIÉ — ne doit pas fuiter', ed1::text)
  ON CONFLICT (id) DO NOTHING;
END $$;

-- ============================================================
-- SCÉNARIO 1 — Visiteur anonyme
-- ============================================================
SET ROLE anon;

DO $$
DECLARE v_count int; v_blocked boolean;
BEGIN
  -- 1a. Le public ne voit AUCUN fait non vérifié (Principe 1 imposé par RLS)
  SELECT count(*) INTO v_count FROM facts WHERE verified = false;
  ASSERT v_count = 0, format('FUITE: anon voit %s fait(s) non vérifié(s)', v_count);
  SELECT count(*) INTO v_count FROM facts;
  ASSERT v_count = 22, format('anon doit voir les 22 faits vérifiés du seed, vu: %s', v_count);
  RAISE NOTICE 'OK — anon: faits non vérifiés invisibles, faits vérifiés visibles';

  -- 1b. anon ne peut PAS insérer de fait
  v_blocked := false;
  BEGIN
    INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description)
    VALUES ('00000000-0000-0000-0000-000000000001', 'fiscal', 'negative', 3, 2025, false,
            'https://attaque.example', 'injection anon');
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAILLE: anon a pu insérer un fait';
  RAISE NOTICE 'OK — anon: insertion de fait bloquée';

  -- 1c. anon PEUT déposer une contestation (section 10.2)
  INSERT INTO contestations (company_id, source_url, argument, submitted_by)
  VALUES ('00000000-0000-0000-0000-000000000006',
          'https://source-alternative.example', 'Le taux effectif cité est contesté par ce rapport', 'citoyen@example.be');
  RAISE NOTICE 'OK — anon: dépôt de contestation autorisé';

  -- 1d. anon ne peut PAS déposer une contestation pré-résolue
  v_blocked := false;
  BEGIN
    INSERT INTO contestations (company_id, source_url, argument, status, resolution)
    VALUES ('00000000-0000-0000-0000-000000000006',
            'https://x.example', 'auto-résolution frauduleuse', 'accepted', 'fait supprimé');
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAILLE: anon a pu créer une contestation pré-résolue';
  RAISE NOTICE 'OK — anon: contestation pré-résolue bloquée';

  -- 1e. anon lit l'audit (transparence) mais ne peut pas le modifier
  PERFORM * FROM audit_log LIMIT 1;
  v_blocked := false;
  BEGIN
    DELETE FROM audit_log WHERE id = 1;
  EXCEPTION WHEN insufficient_privilege OR raise_exception THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAILLE: anon a pu supprimer une entrée d''audit';
  RAISE NOTICE 'OK — anon: audit lisible mais immuable';
END $$;

RESET ROLE;

-- ============================================================
-- SCÉNARIO 2 — Éditeur 1 : propose un fait, tente de s'auto-valider
-- ============================================================
SET ROLE authenticated;
SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

DO $$
DECLARE v_blocked boolean; v_id uuid;
BEGIN
  -- 2a. L'éditeur propose un fait (verified=false) — autorisé
  INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description, proposed_by)
  VALUES ('00000000-0000-0000-0000-000000000002', 'fiscal', 'negative', 1, 2025, false,
          'https://lemonde.fr/enquete-2025', 'Enquête optimisation fiscale (Le Monde 2025)',
          auth.uid()::text)
  RETURNING id INTO v_id;
  RAISE NOTICE 'OK — éditeur: proposition de fait (verified=false) acceptée';

  -- 2b. L'éditeur ne peut PAS insérer directement verified=true
  v_blocked := false;
  BEGIN
    INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description, proposed_by, verified_by, verified_at)
    VALUES ('00000000-0000-0000-0000-000000000002', 'fiscal', 'negative', 3, 2025, true,
            'https://x.example', 'court-circuit du workflow', auth.uid()::text, 'autre', now());
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAILLE: insertion directe verified=true possible';
  RAISE NOTICE 'OK — éditeur: insertion directe verified=true bloquée (policy)';

  -- 2c. L'éditeur ne peut PAS s'auto-valider (double validation, 10.1 étape 5)
  v_blocked := false;
  BEGIN
    UPDATE facts SET verified = true, verified_by = auth.uid()::text, verified_at = now()
    WHERE id = v_id;
  EXCEPTION WHEN raise_exception THEN v_blocked := true;
  END;
  ASSERT v_blocked, 'FAILLE: auto-validation possible';
  RAISE NOTICE 'OK — éditeur: auto-validation bloquée (trigger double validation)';
END $$;

-- ============================================================
-- SCÉNARIO 3 — Éditeur 2 (second éditeur) : valide le fait
-- ============================================================
SET request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

DO $$
DECLARE v_id uuid; v_score numeric;
BEGIN
  SELECT id INTO v_id FROM facts
  WHERE description = 'Enquête optimisation fiscale (Le Monde 2025)';

  -- 3a. Validation par un éditeur DIFFÉRENT — autorisée
  UPDATE facts SET verified = true, verified_by = auth.uid()::text, verified_at = now()
  WHERE id = v_id;
  RAISE NOTICE 'OK — second éditeur: validation acceptée';

  -- 3b. Le recalcul automatique a fonctionné malgré RLS
  --     (trigger SECURITY DEFINER) : Total lobbying -5, fiscal -1
  --     => global passe de -1.0 à -1.2
  SELECT score_global INTO v_score FROM companies
  WHERE id = '00000000-0000-0000-0000-000000000002';
  ASSERT v_score = -1.2, format('recalcul auto attendu -1.2, obtenu %s', v_score);
  RAISE NOTICE 'OK — recalcul automatique du score à travers RLS (SECURITY DEFINER)';
END $$;

RESET ROLE;
RESET request.jwt.claim.sub;

-- ============================================================
-- SCÉNARIO 4 — Piste d'audit complète
-- ============================================================
DO $$
DECLARE v_count int;
BEGIN
  -- Chaque étape du cycle de vie du fait Le Monde est tracée :
  -- INSERT (proposition) + UPDATE (validation) = 2 entrées minimum
  SELECT count(*) INTO v_count FROM audit_log a
  JOIN facts f ON f.id = a.record_id
  WHERE f.description = 'Enquête optimisation fiscale (Le Monde 2025)';
  ASSERT v_count >= 2, format('audit incomplet: %s entrée(s)', v_count);

  -- L'identité du modificateur est capturée
  SELECT count(*) INTO v_count FROM audit_log
  WHERE changed_by = '22222222-2222-2222-2222-222222222222';
  ASSERT v_count >= 1, 'audit: auth.uid() du validateur non capturé';
  RAISE NOTICE 'OK — audit: cycle proposition->validation tracé avec identités';
END $$;

SELECT '=== TOUS LES TESTS RLS + AUDIT PASSENT ===' AS resultat;
