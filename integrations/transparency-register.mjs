#!/usr/bin/env node
/* ============================================================
   YouFundThat — Connecteur EU Transparency Register (lobbying)
   Critères méthodologie (axe lobbying) :
     > 5M€/an        → poids 3 (négatif)
     1M€ – 5M€/an    → poids 2 (négatif)
     100k€ – 1M€/an  → poids 1 (négatif)
     Zéro déclaration → poids 2 (positif) — UNIQUEMENT après
                        recherche active confirmée par un éditeur.

   Source de données : export open data du registre de transparence
   de l'UE (https://transparency-register.europa.eu — export XML/CSV),
   tel que repris par LobbyFacts.eu. Le script lit l'export CSV
   téléchargé localement — pas de scraping fragile.

   Comme tous les connecteurs : faits candidats UNIQUEMENT
   (verified=false, workflow éditorial obligatoire).

   Usage :
     SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
     node transparency-register.mjs --csv export.csv --org "TotalEnergies" \
       --company-qid Q154347 [--dry-run]
   ============================================================ */
import fs from "node:fs";
import { createClient } from "@supabase/supabase-js";

const args = Object.fromEntries(process.argv.slice(2)
  .map((a, i, arr) => a.startsWith("--") ? [a.slice(2), arr[i + 1] ?? true] : null)
  .filter(Boolean));
const DRY = "dry-run" in args;

/* Mapping seuils → critères de la grille (exporté pour les tests) */
export function spendToCriterion(annualSpendEUR) {
  if (annualSpendEUR == null || Number.isNaN(annualSpendEUR)) return null;
  if (annualSpendEUR > 5_000_000)  return { weight: 3, fact_type: "negative", band: "> 5M\u20AC/an" };
  if (annualSpendEUR >= 1_000_000) return { weight: 2, fact_type: "negative", band: "1M\u20AC\u20135M\u20AC/an" };
  if (annualSpendEUR >= 100_000)   return { weight: 1, fact_type: "negative", band: "100k\u20AC\u20131M\u20AC/an" };
  return null; // < 100k€ : pas de critère négatif ; le positif "zéro déclaration"
               // exige une recherche active humaine, jamais automatisée
}

/* Le registre publie des fourchettes ("1,000,000 - 1,249,999") ou des
   montants exacts. On retient la borne BASSE — interprétation la moins
   défavorable (cohérent avec la règle V1.1). */
export function parseSpend(raw) {
  if (!raw) return null;
  const nums = String(raw).replace(/[\u00A0\s]/g, "")
    .match(/\d[\d,.']*/g)?.map((n) => parseInt(n.replace(/[,.']/g, ""), 10))
    .filter((n) => !Number.isNaN(n));
  if (!nums?.length) return null;
  return Math.min(...nums);
}

function findOrgRow(csvText, orgName) {
  const lines = csvText.split(/\r?\n/);
  const header = lines[0].split(";").map((h) => h.replace(/^"|"$/g, "").trim());
  const nameIdx = header.findIndex((h) => /name/i.test(h));
  const costIdx = header.findIndex((h) => /cost|expenditure|spend/i.test(h));
  const yearIdx = header.findIndex((h) => /year|period/i.test(h));
  if (nameIdx < 0 || costIdx < 0) {
    throw new Error(`Colonnes introuvables. En-têtes détectés : ${header.join(" | ")}`);
  }
  const needle = orgName.toLowerCase();
  for (const line of lines.slice(1)) {
    const cols = line.split(";").map((c) => c.replace(/^"|"$/g, "").trim());
    if (cols[nameIdx]?.toLowerCase().includes(needle)) {
      return { name: cols[nameIdx], rawSpend: cols[costIdx],
               year: yearIdx >= 0 ? parseInt(cols[yearIdx], 10) : null };
    }
  }
  return null;
}

async function main() {
  if (!args.csv || !args.org || !args["company-qid"]) {
    console.error('Usage: node transparency-register.mjs --csv export.csv --org "Nom" --company-qid Qxxx [--dry-run]');
    process.exit(1);
  }
  const row = findOrgRow(fs.readFileSync(args.csv, "utf8"), args.org);
  if (!row) { console.log(`"${args.org}" introuvable dans l'export.`); return; }

  const spend = parseSpend(row.rawSpend);
  const crit = spendToCriterion(spend);
  console.log(`${row.name} — dépenses déclarées : ${row.rawSpend} (retenu : ${spend?.toLocaleString("fr-BE")} \u20AC)`);
  if (!crit) { console.log("Sous le seuil de 100k\u20AC — aucun critère négatif applicable."); return; }

  const year = row.year || new Date().getFullYear() - 1; // N-1 par défaut
  const fact = {
    axis: "lobbying", fact_type: crit.fact_type, weight: crit.weight, year,
    verified: false, proposed_by: "bot:transparency-register",
    source_url: "https://transparency-register.europa.eu/searchregister-or-update/search-register_en",
    description: `[À VÉRIFIER] Dépenses lobbying UE déclarées ${crit.band} ` +
      `(EU Transparency Register, ${year}) — montant retenu (borne basse) : ` +
      `${spend.toLocaleString("fr-BE")} \u20AC. Confirmer sur LobbyFacts.eu et lier la fiche datacard.`,
  };
  console.log(`Candidat : poids ${fact.weight}, ${fact.fact_type}, ${fact.year}`);

  if (DRY) return;
  const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
  const { data: company, error } = await sb.from("companies")
    .select("id").eq("wikidata_qid", args["company-qid"]).single();
  if (error) throw error;
  const { error: e2 } = await sb.from("facts").insert({ ...fact, company_id: company.id });
  if (e2) throw e2;
  console.log("→ inséré comme fait candidat (verified=false).");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
