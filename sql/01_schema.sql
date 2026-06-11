-- ============================================================
-- YouFundThat — Schéma de base de données
-- Méthodologie de Scoring V1.0 — youfundthat.eu/boussole
-- Cible : Supabase (PostgreSQL >= 15)
-- ============================================================

-- Extension UUID (déjà active sur Supabase, idempotent ailleurs)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ------------------------------------------------------------
-- Types énumérés (section 2.2)
-- ------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE axis_type AS ENUM ('fiscal', 'lobbying', 'data', 'labor', 'democracy');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE fact_direction AS ENUM ('positive', 'negative');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE score_label AS ENUM ('aligne', 'mitige', 'problematique', 'critique', 'donnees_insuffisantes');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ------------------------------------------------------------
-- Table companies
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS companies (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name             text NOT NULL,
  wikidata_qid     text UNIQUE,                       -- ex: 'Q312' (Apple)
  country          text,                              -- ISO 3166-1 alpha-2, ex: 'BE'
  -- Niveau de couverture des données (section 11 — biais de disponibilité)
  data_quality     smallint NOT NULL DEFAULT 1
                   CHECK (data_quality BETWEEN 1 AND 5),
  -- Cache du score global, recalculé par trigger (section 8.1)
  score_global     numeric(3,1),
  label            score_label,
  last_reviewed_at timestamptz,                       -- section 8.3
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- Table facts (section 2.2)
-- Un fait = un critère binaire prouvé, sourcé, vérifié.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS facts (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id   uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  axis         axis_type NOT NULL,
  fact_type    fact_direction NOT NULL,
  -- Gravité définie par le type de source (section 2.3)
  weight       smallint NOT NULL CHECK (weight IN (1, 2, 3)),
  -- Année du fait — base de la décote temporelle (section 2.4)
  year         integer NOT NULL CHECK (year BETWEEN 1950 AND 2100),
  -- Principe 1 : verified=false => jamais affiché ni comptabilisé
  verified     boolean NOT NULL DEFAULT false,
  -- Source primaire — condition sine qua non (section 2.2)
  source_url   text NOT NULL CHECK (source_url ~* '^https?://'),
  description  text NOT NULL,                         -- libellé du fait affiché
  -- Traçabilité éditoriale (section 10.1)
  proposed_by  text,                                  -- étape 1-4
  verified_by  text,                                  -- étape 5 (second éditeur)
  verified_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- Garde-fou : un fait ne peut être verified=true sans validateur identifié
ALTER TABLE facts DROP CONSTRAINT IF EXISTS facts_verified_requires_validator;
ALTER TABLE facts ADD CONSTRAINT facts_verified_requires_validator
  CHECK (verified = false OR (verified_by IS NOT NULL AND verified_at IS NOT NULL));

-- Index de performance pour le calcul de score (requête la plus fréquente)
CREATE INDEX IF NOT EXISTS idx_facts_scoring
  ON facts (company_id, axis) WHERE verified = true;

-- ------------------------------------------------------------
-- Table contestations (section 10.2) — archivées et publiques
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS contestations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fact_id       uuid REFERENCES facts(id) ON DELETE SET NULL,
  company_id    uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  -- La contestation doit fournir une source primaire alternative
  source_url    text NOT NULL CHECK (source_url ~* '^https?://'),
  argument      text NOT NULL,
  submitted_by  text,                                 -- email ou identifiant
  submitted_at  timestamptz NOT NULL DEFAULT now(),
  -- Résolution sous 10 jours ouvrables
  status        text NOT NULL DEFAULT 'open'
                CHECK (status IN ('open', 'accepted', 'rejected')),
  resolution    text,                                 -- réponse motivée publiée
  resolved_at   timestamptz
);

-- Trigger updated_at générique
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_companies_updated ON companies;
CREATE TRIGGER trg_companies_updated BEFORE UPDATE ON companies
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_facts_updated ON facts;
CREATE TRIGGER trg_facts_updated BEFORE UPDATE ON facts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
