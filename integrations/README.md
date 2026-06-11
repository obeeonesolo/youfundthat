# Intégrations YouFundThat

Connecteurs vers les sources de données externes prévues par la méthodologie.
**Règle commune non-négociable** : aucun connecteur ne crée jamais un fait
vérifié. Ils proposent des **faits candidats** (`verified=false`,
`proposed_by='bot:…'`) qui entrent dans le workflow éditorial standard
(section 10.1) — vérification humaine puis validation par un second éditeur.
Le score n'est donc jamais influencé par un robot sans double contrôle humain.

## Scripts

| Script | Source | Critère méthodologie | Fréquence suggérée |
|---|---|---|---|
| `linkrot.mjs` | HTTP HEAD/GET sur chaque source_url | Section 10.3 — alerte liens morts | Mensuelle (cron) |
| `opensanctions.mjs` | api.opensanctions.org (endpoint match) | Axe démocratie, poids 2 — PEP/sanctions dirigeant | À la demande / lors de l'ajout d'une entreprise |
| `transparency-register.mjs` | Export open data EU Transparency Register | Axe lobbying, poids 1-3 selon seuils | Annuelle (publication N-1) |

## Configuration

```bash
cd integrations && npm install

export SUPABASE_URL="https://xxxx.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="…"        # JAMAIS dans le frontend ni dans Git
export OPENSANCTIONS_API_KEY="…"            # gratuit pour usage non-commercial — s'enregistrer

# Tester sans rien écrire :
node linkrot.mjs --dry-run
node opensanctions.mjs --person "Elon Musk" --company-qid Q478214 --dry-run
node transparency-register.mjs --csv export.csv --org "TotalEnergies" --company-qid Q154347 --dry-run
```

## Choix d'implémentation (et leurs raisons)

- **Borne basse des fourchettes** : le registre UE publie des fourchettes de
  dépenses ("1 000 000 – 1 249 999 €"). Le montant retenu est la borne basse —
  interprétation la moins défavorable, cohérente avec la règle V1.1.
- **Seuil de correspondance OpenSanctions à 85%** : limite les faux positifs
  d'homonymie. Chaque candidat porte la mention `[À VÉRIFIER]` et le score de
  correspondance ; l'éditeur tranche.
- **Le critère positif "zéro déclaration / zéro contribution" n'est jamais
  automatisé** : la méthodologie exige une *recherche active confirmée* —
  c'est un jugement humain, pas une absence dans un export.
- **Export CSV plutôt que scraping** : LobbyFacts/le registre changent de
  mise en page ; l'open data officiel est stable et citable.

## Cron via GitHub Actions

Voir `.github-workflows-integrations.yml` (à copier dans
`.github/workflows/integrations.yml` du repo). Les secrets se configurent
dans Settings → Secrets and variables → Actions.

## ⚠ Statut de test

La logique métier (mapping des seuils, parsing des fourchettes, conversion en
faits candidats) est **testée unitairement** (11 assertions). Les appels
réseau réels (OpenSanctions, registre UE, Supabase) n'ont **pas** pu être
testés depuis l'environnement de développement — à valider lors du premier
run `--dry-run` en conditions réelles.
