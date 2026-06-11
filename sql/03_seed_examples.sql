-- ============================================================
-- YouFundThat — Seed de test
-- Les 6 exemples de calcul du document Méthodologie V1.0
-- (sections 3 à 7 et 9). Faits réels et vérifiables.
-- ============================================================

-- IDs fixes pour les tests
INSERT INTO companies (id, name, wikidata_qid, country, data_quality) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Apple Inc.',        'Q312',     'US', 5),
  ('00000000-0000-0000-0000-000000000002', 'TotalEnergies',     'Q154347',  'FR', 4),
  ('00000000-0000-0000-0000-000000000003', 'Meta Platforms',    'Q380',     'US', 5),
  ('00000000-0000-0000-0000-000000000004', 'Triodos Bank',      'Q1068740', 'NL', 3),
  ('00000000-0000-0000-0000-000000000005', 'Tesla / SpaceX',    'Q478214',  'US', 4),
  ('00000000-0000-0000-0000-000000000006', 'Amazon.be',         'Q3884',    'US', 5)
ON CONFLICT (id) DO NOTHING;

-- ------------------------------------------------------------
-- Apple — axe fiscal (exemple section 3)
-- NB : le doc V1.0 attribue weight=3 au fait LuxLeaks dans son
-- exemple, mais la grille de critères (structure offshore) le
-- définit à weight=2. La grille fait foi. Sans impact : décote x0.
-- ------------------------------------------------------------
INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description, verified_by, verified_at) VALUES
('00000000-0000-0000-0000-000000000001', 'fiscal', 'negative', 3, 2024, true,
 'https://curia.europa.eu/juris/document/C-465-20', 'Arrêt CJUE C-465/20 — avantages fiscaux illégaux Irlande (définitif)', 'editor2', now()),
('00000000-0000-0000-0000-000000000001', 'fiscal', 'negative', 2, 2014, true,
 'https://offshoreleaks.icij.org/luxleaks/apple', 'ICIJ LuxLeaks — structure Luxembourg documentée', 'editor2', now()),
('00000000-0000-0000-0000-000000000001', 'fiscal', 'negative', 2, 2016, true,
 'https://ec.europa.eu/competition/state_aid/apple-2016', 'Taux effectif ~1%% sur profits UE — décision CE 2016', 'editor2', now());

-- ------------------------------------------------------------
-- TotalEnergies — axe lobbying (exemple section 4)
-- ------------------------------------------------------------
INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description, verified_by, verified_at) VALUES
('00000000-0000-0000-0000-000000000002', 'lobbying', 'negative', 2, 2024, true,
 'https://lobbyfacts.eu/datacard/totalenergies', 'Dépenses lobbying UE 2,8M€/an (LobbyFacts 2024)', 'editor2', now()),
('00000000-0000-0000-0000-000000000002', 'lobbying', 'negative', 2, 2025, true,
 'https://lobbymap.org/company/TotalEnergies', 'Score InfluenceMap E (2025)', 'editor2', now()),
('00000000-0000-0000-0000-000000000002', 'lobbying', 'negative', 1, 2023, true,
 'https://corporateeurope.org/totalenergies-revolving-door', 'Enquête CEO revolving door Commission (Corporate Europe Obs.)', 'editor2', now());

-- ------------------------------------------------------------
-- Meta — axe données (exemple section 5)
-- ------------------------------------------------------------
INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description, verified_by, verified_at) VALUES
('00000000-0000-0000-0000-000000000003', 'data', 'negative', 3, 2023, true,
 'https://www.dataprotection.ie/meta-decision-2023', 'Amende RGPD 1,2Mrd€ DPC Irlande (2023, définitif)', 'editor2', now()),
('00000000-0000-0000-0000-000000000003', 'data', 'negative', 3, 2020, true,
 'https://curia.europa.eu/juris/document/C-311-18', 'Transferts UE→US sans garanties — arrêt Schrems II (2020)', 'editor2', now()),
('00000000-0000-0000-0000-000000000003', 'data', 'negative', 2, 2025, true,
 'https://www.facebook.com/privacy/policy', 'Infrastructure principale hors UE (US data centers)', 'editor2', now());

-- ------------------------------------------------------------
-- Triodos Bank — axe droits fondamentaux (exemple section 6)
-- ------------------------------------------------------------
INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description, verified_by, verified_at) VALUES
('00000000-0000-0000-0000-000000000004', 'labor', 'positive', 2, 2024, true,
 'https://www.triodos.com/minimum-standards', 'Aucun financement armement/fossile/tabac — politique publiée', 'editor2', now()),
('00000000-0000-0000-0000-000000000004', 'labor', 'positive', 1, 2024, true,
 'https://www.triodos.com/know-where-your-money-goes', 'Rapport annuel 100%% des prêts publiés en ligne (2024)', 'editor2', now());

-- ------------------------------------------------------------
-- Tesla / SpaceX — axe démocratie (exemple section 7)
-- ------------------------------------------------------------
INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description, verified_by, verified_at) VALUES
('00000000-0000-0000-0000-000000000005', 'democracy', 'negative', 2, 2024, true,
 'https://www.fec.gov/data/committee/america-pac', 'America PAC — 270M$ pour Trump 2024 (FEC)', 'editor2', now()),
('00000000-0000-0000-0000-000000000005', 'democracy', 'negative', 1, 2025, true,
 'https://archive.org/musk-afd-statements', 'Soutien public AfD/Vox/Reform UK (déclarations publiques)', 'editor2', now()),
('00000000-0000-0000-0000-000000000005', 'democracy', 'negative', 2, 2022, true,
 'https://www.theverge.com/twitter-moderation-layoffs', 'Rachat Twitter/X — licenciement 80%% des modérateurs (The Verge)', 'editor2', now());

-- ------------------------------------------------------------
-- Amazon.be — scoring complet 5 axes (exemple section 9)
-- ------------------------------------------------------------
INSERT INTO facts (company_id, axis, fact_type, weight, year, verified, source_url, description, verified_by, verified_at) VALUES
('00000000-0000-0000-0000-000000000006', 'fiscal',    'negative', 3, 2017, true,
 'https://ec.europa.eu/competition/amazon-luxembourg-2017', 'CJUE : 250M€ avantages fiscaux illégaux Luxembourg (2017, définitif)', 'editor2', now()),
('00000000-0000-0000-0000-000000000006', 'fiscal',    'negative', 2, 2017, true,
 'https://ec.europa.eu/competition/amazon-tax-2017', 'Taux effectif ~1%% sur profits UE (décision CE 2017)', 'editor2', now()),
('00000000-0000-0000-0000-000000000006', 'lobbying',  'negative', 2, 2024, true,
 'https://lobbyfacts.eu/datacard/amazon', 'Dépenses lobbying UE 4,2M€/an (LobbyFacts 2024)', 'editor2', now()),
('00000000-0000-0000-0000-000000000006', 'lobbying',  'negative', 1, 2025, true,
 'https://lobbymap.org/company/Amazon', 'Score InfluenceMap D (lobbymap.org 2025)', 'editor2', now()),
('00000000-0000-0000-0000-000000000006', 'data',      'negative', 2, 2025, true,
 'https://aws.amazon.com/privacy', 'Infrastructure principale hors UE (US) — données citoyens européens', 'editor2', now()),
('00000000-0000-0000-0000-000000000006', 'data',      'negative', 1, 2024, true,
 'https://www.autoriteprotectiondonnees.be/amazon-enquete-2024', 'Enquête RGPD APD belge en cours (2024)', 'editor2', now()),
('00000000-0000-0000-0000-000000000006', 'labor',     'negative', 1, 2023, true,
 'https://www.reuters.com/amazon-warehouse-2023', 'Rapport conditions entrepôts (Reuters 2023)', 'editor2', now()),
('00000000-0000-0000-0000-000000000006', 'democracy', 'negative', 1, 2024, true,
 'https://www.fec.gov/data/amazon-pac', 'Dons PAC mixtes US (FEC) — sans engagement anti-démocratique direct', 'editor2', now());
