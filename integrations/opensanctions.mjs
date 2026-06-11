#!/usr/bin/env node
/* ============================================================
   YouFundThat — Connecteur OpenSanctions
   Critère méthodologie (axe démocratie, poids 2) :
   "Présence dans base OpenSanctions (PEP ou sanctions) —
    dirigeant principal" — source : OpenSanctions API.

   RÈGLE ABSOLUE : ce script ne crée JAMAIS de fait vérifié.
   Il propose des faits candidats (verified=false,
   proposed_by='bot:opensanctions') qui suivent le workflow
   éditorial standard — vérification humaine puis validation
   par un second éditeur (section 10.1).

   Usage :
     SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
     OPENSANCTIONS_API_KEY=... \
     node opensanctions.mjs --person "Prénom Nom" --company-qid Q478214 [--dry-run]

   API : https://api.opensanctions.org (endpoint /match/default)
   ============================================================ */
import { createClient } from "@supabase/supabase-js";

const args = Object.fromEntries(process.argv.slice(2)
  .map((a, i, arr) => a.startsWith("--") ? [a.slice(2), arr[i + 1] ?? true] : null)
  .filter(Boolean));
const DRY = "dry-run" in args;

const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, OPENSANCTIONS_API_KEY } = process.env;
if (!args.person || !args["company-qid"]) {
  console.error('Usage: node opensanctions.mjs --person "Nom" --company-qid Qxxx [--dry-run]');
  process.exit(1);
}

// Topics OpenSanctions retenus par la méthodologie
const RELEVANT_TOPICS = new Set(["sanction", "role.pep", "sanction.linked"]);

export async function matchPerson(name, apiKey) {
  const res = await fetch("https://api.opensanctions.org/match/default", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(apiKey ? { Authorization: `ApiKey ${apiKey}` } : {}),
    },
    body: JSON.stringify({
      queries: { q1: { schema: "Person", properties: { name: [name] } } },
    }),
  });
  if (!res.ok) throw new Error(`OpenSanctions API ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return (data.responses?.q1?.results || []).filter((r) =>
    r.match === true || r.score >= 0.85  // seuil de confiance élevé — limite les faux positifs
  );
}

export function toCandidateFact(result, companyId, personName) {
  const topics = (result.properties?.topics || []).filter((t) => RELEVANT_TOPICS.has(t));
  if (!topics.length) return null;
  return {
    company_id: companyId,
    axis: "democracy",
    fact_type: "negative",
    weight: 2,                            // grille axe démocratie
    year: new Date().getFullYear(),
    verified: false,                      // JAMAIS true — workflow éditorial obligatoire
    proposed_by: "bot:opensanctions",
    source_url: `https://www.opensanctions.org/entities/${result.id}/`,
    description: `[À VÉRIFIER] ${personName} — présence base OpenSanctions ` +
      `(${topics.join(", ")}) — score de correspondance ${(result.score * 100).toFixed(0)}%. ` +
      `Vérifier l'homonymie et la catégorie avant validation.`,
  };
}

async function main() {
  const matches = await matchPerson(args.person, OPENSANCTIONS_API_KEY);
  if (!matches.length) {
    console.log(`Aucune correspondance OpenSanctions fiable pour "${args.person}".`);
    console.log("Rappel : une absence peut justifier le critère positif " +
      "\u00AB Zéro contribution \u2026 \u00BB uniquement après recherche active documentée par un éditeur.");
    return;
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: company, error } = await sb.from("companies")
    .select("id, name").eq("wikidata_qid", args["company-qid"]).single();
  if (error) throw error;

  for (const m of matches) {
    const fact = toCandidateFact(m, company.id, args.person);
    if (!fact) { console.log(`Ignoré (topics non pertinents) : ${m.id}`); continue; }
    console.log(`Candidat : ${fact.description}`);
    if (!DRY) {
      const { error: e2 } = await sb.from("facts").insert(fact);
      if (e2) throw e2;
      console.log("→ inséré comme fait candidat (verified=false) — en attente de validation éditoriale.");
    }
  }
}

// Exécution directe uniquement (importable pour les tests)
if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
