# YouFundThat — Moteur de scoring (V1)

Implémentation PostgreSQL/Supabase de la Méthodologie de Scoring V1.0.
Testée sur PostgreSQL 16. **Lire RAPPORT.md** : l'implémentation corrige des
incohérences du document (décote temporelle, bornes de labels).

## Contenu

```
sql/01_schema.sql                 Tables companies, facts, contestations + contraintes
sql/02_scoring.sql                Fonctions de calcul, vue publique, triggers de recalcul
sql/03_seed_examples.sql          Les 6 exemples du document (22 faits)
sql/04_audit.sql                  Journal d'audit immuable (triggers sur facts/contestations)
sql/05_rls.sql                    Row Level Security + double validation + table editors
tests/00_local_supabase_stub.sql  Stub auth.uid() + rôles (LOCAL UNIQUEMENT, jamais sur Supabase)
tests/test_scoring.sql            22 assertions moteur de scoring — réf. fixe 2026-06-10
tests/test_rls_audit.sql         11 scénarios d'attaque RLS + piste d'audit (idempotent)
sql/06_integrations.sql           Table link_alerts (alertes liens morts, section 10.3)
frontend/                         Fiches entreprises (statique, sans build) — voir frontend/index.html
integrations/                     Connecteurs OpenSanctions, EU Transparency Register, liens morts
RAPPORT.md                        Écarts vs document V1.0 — arbitrages validés le 2026-06-10
```

## Frontend

Statique, sans étape de build : `frontend/index.html` + supabase-js en CDN.
Renseigner `frontend/config.js` (URL du projet + clé **anon** — jamais la
service_role) puis déployer sur n'importe quel hébergeur statique (Netlify,
Cloudflare Pages, GitHub Pages). Sans configuration, le site démarre en
**mode démonstration** avec les 6 entreprises d'exemple — le moteur de score
JavaScript embarqué est un miroir testé du moteur SQL (mêmes résultats sur
les 6 cas). La fiche entreprise respecte intégralement la règle de
transparence 8.3 : compteurs de faits ± par axe, sources primaires liées,
date de dernier recalcul, bouton "Contester ce score" (mailto), mention
méthodologie.

## Déploiement sur Supabase

Dans l'ordre, via le SQL Editor ou `supabase db push` :

```bash
psql $DATABASE_URL -f sql/01_schema.sql
psql $DATABASE_URL -f sql/02_scoring.sql
psql $DATABASE_URL -f sql/04_audit.sql
psql $DATABASE_URL -f sql/05_rls.sql
# Seed optionnel (données d'exemple) :
psql $DATABASE_URL -f sql/03_seed_examples.sql
```

**Bootstrap obligatoire** — avec RLS actif, personne ne peut écrire tant que la
table `editors` est vide. Insérer le premier admin via le SQL Editor Supabase
(rôle `postgres`/`service_role`, qui bypass RLS) :

```sql
INSERT INTO editors (user_id, role)
VALUES ('<uuid-auth.users-du-fondateur>', 'admin');
```

En local (dev/CI), exécuter `tests/00_local_supabase_stub.sql` **avant**
`sql/05_rls.sql`.

Cron trimestriel de mise à jour des décotes (section 10.3) — via pg_cron Supabase :

```sql
SELECT cron.schedule('yft-decay-refresh', '0 3 1 1,4,7,10 *',
                     $$SELECT yft_refresh_all_scores()$$);
```

## Tests

```bash
psql $DATABASE_URL -f tests/test_scoring.sql
```

Sortie attendue : `=== TOUS LES TESTS PASSENT ===` puis le tableau des scores.

## API de scoring (fonctions exposées)

| Fonction | Rôle |
|---|---|
| `yft_axis_score(company_id, axis [, ref_date])` | Score d'un axe, plafonné ±10 |
| `yft_global_score(company_id [, ref_date])` | Moyenne des 5 axes, 1 décimale |
| `yft_label(company_id [, ref_date])` | aligne / mitige / problematique / critique / donnees_insuffisantes |
| `yft_effective_weight(weight, year [, ref_date])` | Poids avec décote temporelle |
| `yft_refresh_all_scores()` | Recalcul de toutes les entreprises (cron) |
| Vue `v_company_scores` | Scores + nb faits ± par axe (transparence 8.3) |

Le paramètre `ref_date` (défaut : aujourd'hui) rend tout calcul **reproductible
à date fixe** — essentiel pour l'auditabilité revendiquée par la méthodologie.

## Garanties imposées par la base (pas seulement par le code applicatif)

- `weight` ∈ {1, 2, 3} uniquement
- `source_url` obligatoire et au format http(s)
- `verified = true` impossible sans `verified_by` + `verified_at` (contrainte CHECK)
- **Double validation** : le validateur doit être différent du proposeur (trigger — workflow 10.1 étape 5)
- Le score n'est jamais saisi : trigger de recalcul sur tout INSERT/UPDATE/DELETE de facts
- Faits non vérifiés : **invisibles du public au niveau RLS** (pas seulement filtrés par le frontend)
- Journal d'audit **immuable** : trigger interdisant UPDATE/DELETE, écriture par trigger SECURITY DEFINER uniquement

## Modèle de sécurité RLS

| Acteur | companies | facts | contestations | audit_log |
|---|---|---|---|---|
| anon (public) | lecture | lecture (vérifiés seuls) | lecture + dépôt | lecture |
| authenticated | lecture | lecture (vérifiés seuls) | lecture + dépôt | lecture |
| éditeur | écriture | proposer (verified=false), valider les faits d'autrui | résoudre | lecture |
| admin | écriture | + suppression | résoudre | lecture |
| service_role | bypass RLS (migrations, cron `yft_refresh_all_scores`) | | | |

## Intégrations

Connecteurs dans `integrations/` (voir `integrations/README.md`) :
`linkrot.mjs` (alertes liens morts mensuelles — section 10.3, table
`link_alerts` via `sql/06_integrations.sql`), `opensanctions.mjs`
(PEP/sanctions des dirigeants — axe démocratie) et
`transparency-register.mjs` (seuils de dépenses lobbying — axe lobbying).
Règle commune : les connecteurs ne créent **que des faits candidats**
(`verified=false`, `proposed_by='bot:…'`) — le score n'est jamais touché
sans double validation humaine. La logique métier est testée unitairement ;
les appels réseau réels restent à valider par un premier run `--dry-run`.
Cron : copier `.github-workflows-integrations.yml` dans
`.github/workflows/` du dépôt.

## Prochaines étapes suggérées

1. ~~Trancher les points du RAPPORT.md~~ — fait (Q1-Q5 validés, implémentation conforme)
2. ~~RLS Supabase + table d'audit~~ — fait
3. ~~Changelog public V1.0 → V1.1~~ — fait (`CHANGELOG-V1.1.md`)
4. ~~Document méthodologie V1.1 (docx)~~ — fait
5. ~~Frontend : fiche entreprise~~ — fait (`frontend/`, mode démo inclus)
6. ~~Intégrations : OpenSanctions, registre UE, liens morts~~ — fait (`integrations/`)
7. Déployer : projet Supabase réel (01→02→04→05→06, bootstrap admin), hébergeur statique, premier run `--dry-run` des connecteurs
8. V2 : formulaire de contestation (remplace le mailto), bouton "Proposer un fait", page publique du journal d'audit
