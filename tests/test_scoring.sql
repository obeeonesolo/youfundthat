-- ============================================================
-- YouFundThat — Suite de tests du moteur de scoring
-- Date de référence fixe : 2026-06-10 (reproductibilité)
--
-- ATTENTION : les scores attendus ci-dessous appliquent la
-- décote temporelle (section 2.4), ce que les exemples du
-- document V1.0 ne font PAS tous. Les écarts sont documentés
-- dans RAPPORT.md. C'est la règle 2.4 qui fait foi.
-- ============================================================

\set ON_ERROR_STOP on
\set ref '''2026-06-10''::date'

DO $$
DECLARE
  v numeric;
  v_label score_label;
  ref CONSTANT date := '2026-06-10';

  c_apple   CONSTANT uuid := '00000000-0000-0000-0000-000000000001';
  c_total   CONSTANT uuid := '00000000-0000-0000-0000-000000000002';
  c_meta    CONSTANT uuid := '00000000-0000-0000-0000-000000000003';
  c_triodos CONSTANT uuid := '00000000-0000-0000-0000-000000000004';
  c_tesla   CONSTANT uuid := '00000000-0000-0000-0000-000000000005';
  c_amazon  CONSTANT uuid := '00000000-0000-0000-0000-000000000006';
BEGIN
  -- ====== Tests unitaires : décote temporelle (section 2.4) ======
  ASSERT yft_effective_weight(3, 2024, ref) = 3.0,  'décote: fait <=5 ans = poids plein';
  ASSERT yft_effective_weight(3, 2021, ref) = 3.0,  'décote: limite 5 ans incluse (2021 -> age 5)';
  ASSERT yft_effective_weight(3, 2020, ref) = 1.5,  'décote: fait 6 ans = x0.5';
  ASSERT yft_effective_weight(2, 2016, ref) = 1.0,  'décote: limite 10 ans incluse (2016 -> age 10) = x0.5';
  ASSERT yft_effective_weight(2, 2014, ref) = 0.0,  'décote: fait >10 ans = exclu du score';
  RAISE NOTICE 'OK — décote temporelle (5 assertions)';

  -- ====== Apple — axe fiscal ======
  -- CJUE 2024 (w3, plein) + LuxLeaks 2014 (x0) + CE 2016 (w2 x0.5)
  -- = -3 + 0 + -1 = -4   [doc V1.0 : -5, sans décote sur 2016]
  v := yft_axis_score(c_apple, 'fiscal', ref);
  ASSERT v = -4, format('Apple fiscal: attendu -4 (avec décote 2.4), obtenu %s', v);
  RAISE NOTICE 'OK — Apple fiscal = -4 (doc: -5, écart décote documenté)';

  -- ====== TotalEnergies — axe lobbying ======
  -- 2024 (w2) + 2025 (w2) + 2023 (w1) = -5  [conforme doc]
  v := yft_axis_score(c_total, 'lobbying', ref);
  ASSERT v = -5, format('TotalEnergies lobbying: attendu -5, obtenu %s', v);
  RAISE NOTICE 'OK — TotalEnergies lobbying = -5 (conforme doc)';

  -- ====== Meta — axe données ======
  -- 2023 (w3) + Schrems II 2020 (w3 x0.5 = 1.5) + infra 2025 (w2)
  -- = -3 -1.5 -2 = -6.5   [doc V1.0 : -8, sans décote sur Schrems II]
  v := yft_axis_score(c_meta, 'data', ref);
  ASSERT v = -6.5, format('Meta data: attendu -6.5 (avec décote 2.4), obtenu %s', v);
  RAISE NOTICE 'OK — Meta données = -6.5 (doc: -8, écart décote documenté)';

  -- ====== Triodos — axe droits fondamentaux ======
  -- +2 +1 = +3  [conforme doc]
  v := yft_axis_score(c_triodos, 'labor', ref);
  ASSERT v = 3, format('Triodos labor: attendu +3, obtenu %s', v);
  RAISE NOTICE 'OK — Triodos droits = +3 (conforme doc)';

  -- ====== Tesla — axe démocratie ======
  -- 2024 (w2) + 2025 (w1) + 2022 (w2, age 4, plein) = -5  [conforme doc]
  v := yft_axis_score(c_tesla, 'democracy', ref);
  ASSERT v = -5, format('Tesla democracy: attendu -5, obtenu %s', v);
  RAISE NOTICE 'OK — Tesla démocratie = -5 (conforme doc)';

  -- ====== Amazon.be — scoring complet ======
  -- fiscal:   2017 (age 9) -> (-3 -2) x0.5 = -2.5  [doc: -5]
  -- lobbying: -2 -1 = -3                            [conforme]
  -- data:     -2 -1 = -3                            [conforme]
  -- labor:    -1                                    [conforme]
  -- democracy:-1                                    [conforme]
  ASSERT yft_axis_score(c_amazon, 'fiscal',    ref) = -2.5, 'Amazon fiscal';
  ASSERT yft_axis_score(c_amazon, 'lobbying',  ref) = -3,   'Amazon lobbying';
  ASSERT yft_axis_score(c_amazon, 'data',      ref) = -3,   'Amazon data';
  ASSERT yft_axis_score(c_amazon, 'labor',     ref) = -1,   'Amazon labor';
  ASSERT yft_axis_score(c_amazon, 'democracy', ref) = -1,   'Amazon democracy';

  -- Global = (-2.5 -3 -3 -1 -1)/5 = -10.5/5 = -2.1  [doc: -2.6]
  v := yft_global_score(c_amazon, ref);
  ASSERT v = -2.1, format('Amazon global: attendu -2.1, obtenu %s', v);

  -- Label : -2.1 < -2.0 => problématique  [conforme au label du doc]
  v_label := yft_label(c_amazon, ref);
  ASSERT v_label = 'problematique', format('Amazon label: attendu problematique, obtenu %s', v_label);
  RAISE NOTICE 'OK — Amazon.be global = -2.1, label problématique (doc: -2.6, même label)';

  -- ====== Plafonnement à ±10 (section 2.1) ======
  -- Vérifié par construction : ajout temporaire de faits extrêmes
  DECLARE c_clamp uuid;
  BEGIN
    INSERT INTO companies (name) VALUES ('_test_clamp') RETURNING id INTO c_clamp;
    INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description, verified_by, verified_at)
    SELECT c_clamp, 'fiscal', 'negative', 3, 2025, true, 'https://test.example/c', 'clamp test', 'editor2', now()
    FROM generate_series(1, 5);
    -- 5 x (-3) = -15 -> plafonné à -10
    ASSERT yft_axis_score(c_clamp, 'fiscal', ref) = -10, 'plafonnement -10';
    DELETE FROM companies WHERE id = c_clamp;
  END;
  RAISE NOTICE 'OK — plafonnement à -10';

  -- ====== Principe 1 : verified=false jamais comptabilisé ======
  DECLARE c_unv uuid;
  BEGIN
    INSERT INTO companies (name) VALUES ('_test_unverified') RETURNING id INTO c_unv;
    INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description)
    VALUES (c_unv, 'fiscal', 'negative', 3, 2025, false, 'https://test.example/u', 'fait non vérifié');
    ASSERT yft_axis_score(c_unv, 'fiscal', ref) = 0, 'fait non vérifié exclu';
    ASSERT yft_label(c_unv, ref) = 'donnees_insuffisantes', 'aucun fait vérifié => données insuffisantes';
    DELETE FROM companies WHERE id = c_unv;
  END;
  RAISE NOTICE 'OK — verified=false exclu + label données insuffisantes';

  -- ====== Recalcul automatique par trigger (Principe 2) ======
  DECLARE c_trig uuid; v_cached numeric;
  BEGIN
    INSERT INTO companies (name) VALUES ('_test_trigger') RETURNING id INTO c_trig;
    INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description, verified_by, verified_at)
    VALUES (c_trig, 'data', 'positive', 3, 2025, true, 'https://test.example/t', 'infra 100%% UE certifiée', 'editor2', now());
    SELECT score_global INTO v_cached FROM companies WHERE id = c_trig;
    -- +3 sur 1 axe / 5 = 0.6
    ASSERT v_cached = 0.6, format('trigger: cache attendu 0.6, obtenu %s', v_cached);
    DELETE FROM companies WHERE id = c_trig;
  END;
  RAISE NOTICE 'OK — recalcul automatique du cache par trigger';

  -- ====== Garde-fou : verified=true sans validateur => rejet ======
  DECLARE c_guard uuid; v_failed boolean := false;
  BEGIN
    INSERT INTO companies (name) VALUES ('_test_guard') RETURNING id INTO c_guard;
    BEGIN
      INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description)
      VALUES (c_guard, 'fiscal', 'negative', 1, 2025, true, 'https://test.example/g', 'sans validateur');
    EXCEPTION WHEN check_violation OR raise_exception THEN
      -- rejeté soit par la contrainte CHECK (01_schema), soit par le
      -- trigger de double validation (05_rls) — les deux sont valides
      v_failed := true;
    END;
    ASSERT v_failed, 'verified=true sans verified_by doit être rejeté';
    DELETE FROM companies WHERE id = c_guard;
  END;
  RAISE NOTICE 'OK — double validation imposée par contrainte';

  RAISE NOTICE '';
  RAISE NOTICE '=== TOUS LES TESTS PASSENT ===';
END $$;

-- Affichage récapitulatif des scores calculés
SELECT name,
       yft_axis_score(id, 'fiscal',    '2026-06-10') AS fiscal,
       yft_axis_score(id, 'lobbying',  '2026-06-10') AS lobbying,
       yft_axis_score(id, 'data',      '2026-06-10') AS data,
       yft_axis_score(id, 'labor',     '2026-06-10') AS labor,
       yft_axis_score(id, 'democracy', '2026-06-10') AS democracy,
       yft_global_score(id, '2026-06-10')            AS global,
       yft_label(id, '2026-06-10')                   AS label
FROM companies
ORDER BY name;
