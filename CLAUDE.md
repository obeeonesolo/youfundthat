# YouFundThat — Contexte projet pour Claude Code

## Ce qu'est ce projet

Initiative citoyenne belge sans but lucratif (youfundthat.eu) qui note les
entreprises de **−10 à +10 sur 5 axes** : `fiscal`, `lobbying`, `data`,
`labor`, `democracy`. Le score repose exclusivement sur des **faits binaires,
sourcés et vérifiés** — jamais d'opinion. Méthodologie publique **V1.1**
(`YouFundThat-Methodologie-Scoring-V1.1.docx`, changelog dans
`CHANGELOG-V1.1.md`). Stack : Supabase/PostgreSQL + frontend statique vanilla JS.

## Règles métier NON-NÉGOCIABLES (à respecter dans tout code)

1. **Binaire** : un fait vaut ses points si prouvé et vérifié, sinon 0.
   Jamais de demi-points subjectifs, jamais d'appréciation éditoriale dans le code.
2. **Automatique** : le score est TOUJOURS calculé par la base
   (`yft_axis_score`, `yft_global_score`), jamais saisi ni patché à la main.
3. **Public/reproductible** : tout changement de calcul doit rester
   reproductible par un tiers. Le moteur JS du frontend (`frontend/app.js`)
   est un MIROIR EXACT du moteur SQL — toute modification de l'un impose la
   modification de l'autre ET de leurs tests respectifs.
4. **Décote temporelle** (V1.1, s'applique sans exception) : âge en années
   civiles ; ≤5 ans ×1.0 ; ≤10 ans ×0.5 ; >10 ans ×0 (exclu du score,
   visible en timeline).
5. **Labels V1.1** (bornes strictes, interprétation la moins défavorable) :
   aligné `>+5.0` ; mitigé `−2.0 ≤ s ≤ +5.0` ; problématique `−6.0 ≤ s < −2.0` ;
   critique `< −6.0` ; `donnees_insuffisantes` si 0 fait vérifié.
   Scores affichés à 1 décimale.
6. **Double validation** : `verified=true` exige `verified_by ≠ proposed_by`
   (trigger `yft_enforce_double_validation`). Ne jamais contourner.
7. **Connecteurs/bots** : ne créent QUE des faits candidats
   (`verified=false`, `proposed_by='bot:…'`, description préfixée `[À VÉRIFIER]`).
8. **Journal d'audit immuable** : `audit_log` n'accepte ni UPDATE ni DELETE,
   même par admin. Ne jamais affaiblir.
9. **Sécurité des clés** : la clé `service_role` ne va JAMAIS dans
   `frontend/`, dans Git, ni dans un exemple de code client. Le frontend
   n'utilise que la clé `anon` (la sécurité repose sur les RLS de
   `sql/05_rls.sql`).

## Structure du dépôt

- `sql/01_schema.sql` → tables `companies`, `facts`, `contestations`
- `sql/02_scoring.sql` → moteur de score + vue `v_company_scores` + trigger de recalcul
- `sql/03_seed_examples.sql` → 6 entreprises d'exemple (22 faits)
- `sql/04_audit.sql` → journal d'audit immuable
- `sql/05_rls.sql` → RLS + table `editors` + double validation
- `sql/06_integrations.sql` → table `link_alerts`
- `tests/00_local_supabase_stub.sql` → stub `auth.uid()` LOCAL UNIQUEMENT (avant 05 en local)
- `tests/test_scoring.sql` → 22 assertions (date de référence FIXE '2026-06-10')
- `tests/test_rls_audit.sql` → 11 scénarios d'attaque (idempotent)
- `frontend/` → statique sans build ; `config.js` vide = mode démo (`demo-data.js`)
- `integrations/` → `linkrot.mjs`, `opensanctions.mjs`, `transparency-register.mjs`

## Ordre de déploiement SQL

`01 → 02 → 04 → 05 → 06` (+ `03` optionnel pour les exemples).
En local sans Supabase : exécuter `tests/00_local_supabase_stub.sql` AVANT `05`.
Bootstrap du premier admin : `INSERT INTO editors` via service_role (voir README).

## Commandes de test (doivent TOUTES passer avant tout commit)

```bash
# SQL (PostgreSQL local ou supabase db)
psql -d youfundthat -v ON_ERROR_STOP=1 -f tests/test_scoring.sql      # attend "TOUS LES TESTS PASSENT"
psql -d youfundthat -f tests/test_rls_audit.sql                        # attend "TOUS LES TESTS RLS + AUDIT PASSENT"

# Frontend
node --check frontend/app.js

# Intégrations
cd integrations && npm install && node --check linkrot.mjs opensanctions.mjs transparency-register.mjs
```

Résultats de référence du seed (recalculés V1.1, réf. 2026) : Apple fiscal −4 ;
TotalEnergies lobbying −5 ; Meta data −6,5 ; Triodos labor +3 ; Tesla
democracy −5 ; Amazon.be global −2,1 (problématique).

## État au moment du transfert (juin 2026)

FAIT : moteur SQL testé (33 assertions), RLS+audit, frontend (mode démo testé,
moteur JS = moteur SQL), connecteurs (logique testée, 11 assertions), docx
V1.1, changelog public.

À FAIRE (prochaines étapes priorisées) :
1. Créer le projet Supabase réel, déployer le SQL, bootstrap admin,
   configurer `frontend/config.js`, déployer le statique.
2. Premier run `--dry-run` des 3 connecteurs en conditions réseau réelles
   (jamais testés en live — environnement de dev sans accès réseau).
3. Cron : `pg_cron` trimestriel pour `yft_refresh_all_scores()` ; copier
   `integrations/.github-workflows-integrations.yml` vers `.github/workflows/`.
4. V2 : formulaire de contestation (remplace mailto), bouton "Proposer un
   fait", page publique du journal d'audit.

Limite connue assumée : `verified_by` n'est pas lié cryptographiquement à
`auth.uid()`, mais l'audit capture le vrai uid — fraude détectable a posteriori.

## Conventions

- Langue du code, des commentaires et des messages de commit : **français**.
- Tout choix d'interprétation ambigu se tranche par "l'interprétation la
  moins défavorable à l'entreprise notée" (règle V1.1, protection juridique).
- L'utilisateur est expert en sécurité de l'information : être direct,
  critique, sourcé ; signaler les risques sans édulcorer.
