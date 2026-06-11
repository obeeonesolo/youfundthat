#!/usr/bin/env node
/* ============================================================
   YouFundThat — Vérification des sources primaires (liens morts)
   Méthodologie section 10.3 : "Alerte automatique si une source
   primaire devient inaccessible — mensuelle".

   Usage (cron mensuel, ex. GitHub Actions) :
     SUPABASE_URL=https://xxx.supabase.co \
     SUPABASE_SERVICE_ROLE_KEY=... \
     node linkrot.mjs [--dry-run]

   ⚠ Utilise la clé service_role (bypass RLS) — à exécuter
   uniquement côté serveur/CI, jamais dans le navigateur.
   ============================================================ */
import { createClient } from "@supabase/supabase-js";

const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY } = process.env;
const DRY = process.argv.includes("--dry-run");
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY requis.");
  process.exit(1);
}
const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const TIMEOUT_MS = 15000;
const UA = "YouFundThat-LinkCheck/1.0 (+https://youfundthat.eu/boussole)";

async function checkUrl(url) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    // HEAD d'abord (léger), GET en repli (certains serveurs refusent HEAD)
    let res = await fetch(url, { method: "HEAD", redirect: "follow",
      signal: ctrl.signal, headers: { "User-Agent": UA } });
    if (res.status === 405 || res.status === 403) {
      res = await fetch(url, { method: "GET", redirect: "follow",
        signal: ctrl.signal, headers: { "User-Agent": UA } });
    }
    return { ok: res.status < 400, status: res.status, detail: res.statusText };
  } catch (err) {
    return { ok: false, status: null, detail: String(err.cause?.code || err.name || err.message) };
  } finally {
    clearTimeout(timer);
  }
}

async function main() {
  const { data: facts, error } = await sb.from("facts")
    .select("id, source_url").eq("verified", true);
  if (error) throw error;

  console.log(`${facts.length} sources à vérifier${DRY ? " (dry-run)" : ""}…`);
  let dead = 0;

  for (const f of facts) {
    const r = await checkUrl(f.source_url);
    if (r.ok) {
      // Lien revenu en vie : résoudre les alertes ouvertes
      if (!DRY) await sb.from("link_alerts")
        .update({ resolved_at: new Date().toISOString() })
        .eq("fact_id", f.id).is("resolved_at", null);
      continue;
    }
    dead++;
    console.warn(`MORT  [${r.status ?? "ERR"}] ${f.source_url} — ${r.detail}`);
    if (DRY) continue;
    // Une seule alerte ouverte par fait
    const { data: open } = await sb.from("link_alerts")
      .select("id").eq("fact_id", f.id).is("resolved_at", null).limit(1);
    if (!open?.length) {
      await sb.from("link_alerts").insert({
        fact_id: f.id, source_url: f.source_url,
        http_status: r.status, detail: r.detail,
      });
    }
    await new Promise((r2) => setTimeout(r2, 400)); // politesse
  }

  console.log(`Terminé : ${dead} lien(s) mort(s) sur ${facts.length}.`);
  if (dead > 0) process.exitCode = 2; // signal pour la CI
}

main().catch((e) => { console.error(e); process.exit(1); });
