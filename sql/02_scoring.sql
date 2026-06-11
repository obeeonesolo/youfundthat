-- ============================================================
-- YouFundThat — Logique de scoring
-- Méthodologie de Scoring V1.0 — sections 2.1, 2.4, 8.1, 8.2
-- ============================================================
-- NOTE D'IMPLÉMENTATION (écart corrigé vs document V1.0) :
-- La formule SQL publiée en section 2.1 du document n'applique pas
-- la décote temporelle définie en section 2.4. Cette implémentation
-- unifie les deux : le poids effectif (avec décote) est utilisé
-- partout. C'est la section 2.4 qui fait foi.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Poids effectif avec décote temporelle (section 2.4)
--    <= 5 ans : x1.0 │ <= 10 ans : x0.5 │ > 10 ans : x0.0
--    p_ref permet un calcul reproductible à date fixe (tests, audit)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION yft_effective_weight(
  p_weight integer,
  p_year   integer,
  p_ref    date DEFAULT CURRENT_DATE
) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
  SELECT p_weight * CASE
    WHEN (EXTRACT(YEAR FROM p_ref)::int - p_year) <= 5  THEN 1.0
    WHEN (EXTRACT(YEAR FROM p_ref)::int - p_year) <= 10 THEN 0.5
    ELSE 0.0
  END;
$$;

-- ------------------------------------------------------------
-- 2. Score d'un axe (section 2.1)
--    Somme algébrique des poids effectifs, plafonnée à [-10, +10].
--    Seuls les faits verified=true comptent (Principe 1 et 2).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION yft_axis_score(
  p_company uuid,
  p_axis    axis_type,
  p_ref     date DEFAULT CURRENT_DATE
) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT GREATEST(-10, LEAST(10,
    COALESCE(SUM(
      CASE f.fact_type WHEN 'negative' THEN -1 ELSE 1 END
      * yft_effective_weight(f.weight, f.year, p_ref)
    ), 0)
  ))
  FROM facts f
  WHERE f.company_id = p_company
    AND f.axis       = p_axis
    AND f.verified   = true;
$$;

-- ------------------------------------------------------------
-- 3. Score global (section 8.1)
--    Moyenne arithmétique NON pondérée des 5 axes (un axe sans
--    fait vaut 0), arrondie à 1 décimale.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION yft_global_score(
  p_company uuid,
  p_ref     date DEFAULT CURRENT_DATE
) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT ROUND(AVG(yft_axis_score(p_company, a, p_ref)), 1)
  FROM unnest(enum_range(NULL::axis_type)) AS a;
$$;

-- ------------------------------------------------------------
-- 4. Label (section 8.2)
--    Convention retenue pour les bornes (ambiguës dans le doc V1.0,
--    voir RAPPORT) :  aligné  : score >  +5.0
--                     mitigé  : -2.0 <= score <= +5.0
--                     problém.: -6.0 <= score <  -2.0
--                     critique: score <  -6.0
--    Une entreprise sans AUCUN fait vérifié => 'donnees_insuffisantes'
--    (section 11 : "Score absent ≠ score positif").
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION yft_label(
  p_company uuid,
  p_ref     date DEFAULT CURRENT_DATE
) RETURNS score_label
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_score numeric;
  v_facts integer;
BEGIN
  SELECT count(*) INTO v_facts
  FROM facts WHERE company_id = p_company AND verified = true;

  IF v_facts = 0 THEN
    RETURN 'donnees_insuffisantes';
  END IF;

  v_score := yft_global_score(p_company, p_ref);

  RETURN CASE
    WHEN v_score >  5.0 THEN 'aligne'::score_label
    WHEN v_score >= -2.0 THEN 'mitige'::score_label
    WHEN v_score >= -6.0 THEN 'problematique'::score_label
    ELSE 'critique'::score_label
  END;
END;
$$;

-- ------------------------------------------------------------
-- 5. Vue publique des scores détaillés (section 8.3 —
--    transparence : nb de faits +/- par axe)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_company_scores AS
SELECT
  c.id                                           AS company_id,
  c.name,
  c.wikidata_qid,
  c.data_quality,
  a.axis,
  yft_axis_score(c.id, a.axis)                   AS axis_score,
  count(f.id) FILTER (WHERE f.fact_type = 'positive') AS positive_facts,
  count(f.id) FILTER (WHERE f.fact_type = 'negative') AS negative_facts,
  c.score_global,
  c.label,
  c.last_reviewed_at
FROM companies c
CROSS JOIN unnest(enum_range(NULL::axis_type)) AS a(axis)
LEFT JOIN facts f
       ON f.company_id = c.id AND f.axis = a.axis AND f.verified = true
GROUP BY c.id, c.name, c.wikidata_qid, c.data_quality, a.axis,
         c.score_global, c.label, c.last_reviewed_at;

-- ------------------------------------------------------------
-- 6. Recalcul automatique (Principe 2 — section 1)
--    Trigger sur facts : tout INSERT/UPDATE/DELETE rafraîchit le
--    cache score_global + label + last_reviewed_at de l'entreprise.
--    Le score n'est JAMAIS saisi manuellement.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION yft_refresh_company_score() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_company uuid;
BEGIN
  v_company := COALESCE(NEW.company_id, OLD.company_id);

  UPDATE companies SET
    score_global     = yft_global_score(v_company),
    label            = yft_label(v_company),
    last_reviewed_at = now()
  WHERE id = v_company;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_facts_refresh_score ON facts;
CREATE TRIGGER trg_facts_refresh_score
  AFTER INSERT OR UPDATE OR DELETE ON facts
  FOR EACH ROW EXECUTE FUNCTION yft_refresh_company_score();

-- ------------------------------------------------------------
-- 7. Recalcul périodique des décotes (section 10.3 —
--    cron trimestriel Supabase : SELECT yft_refresh_all_scores();)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION yft_refresh_all_scores() RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_count integer := 0;
  r record;
BEGIN
  FOR r IN SELECT id FROM companies LOOP
    UPDATE companies SET
      score_global     = yft_global_score(r.id),
      label            = yft_label(r.id),
      last_reviewed_at = now()
    WHERE id = r.id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
