/* ============================================================
   YouFundThat — Application frontend (vanilla JS, sans build)
   - Couche données : Supabase (vue v_company_scores + facts) ou
     mode démo local (demo-data.js)
   - Moteur de score : miroir EXACT de sql/02_scoring.sql
     (décote temporelle, plafonnement, labels V1.1)
   ============================================================ */
(function () {
  "use strict";

  const CFG = window.YFT_CONFIG || {};
  const DEMO = !CFG.SUPABASE_URL || !CFG.SUPABASE_ANON_KEY;
  const sb = DEMO ? null : window.supabase.createClient(CFG.SUPABASE_URL, CFG.SUPABASE_ANON_KEY);
  const app = document.getElementById("app");

  const AXES = [
    { key: "fiscal",    name: "Transparence fiscale" },
    { key: "lobbying",  name: "Lobbying UE" },
    { key: "data",      name: "Souveraineté données" },
    { key: "labor",     name: "Droits fondamentaux" },
    { key: "democracy", name: "Empreinte démocratique" },
  ];

  const LABELS = {
    aligne:                 { txt: "Aligné" },
    mitige:                 { txt: "Mitigé" },
    problematique:          { txt: "Problématique" },
    critique:               { txt: "Critique" },
    donnees_insuffisantes:  { txt: "Données insuffisantes" },
  };

  /* ---------- Moteur de score — miroir de sql/02_scoring.sql ---------- */
  const refYear = new Date().getFullYear();

  function effectiveWeight(weight, year) {
    const age = refYear - year;
    if (age <= 5) return weight;
    if (age <= 10) return weight * 0.5;
    return 0;
  }
  function axisScore(facts, axis) {
    const sum = facts
      .filter((f) => f.axis === axis)
      .reduce((s, f) => s + (f.fact_type === "negative" ? -1 : 1) * effectiveWeight(f.weight, f.year), 0);
    return Math.max(-10, Math.min(10, sum));
  }
  function globalScore(facts) {
    const avg = AXES.reduce((s, a) => s + axisScore(facts, a.key), 0) / 5;
    return Math.round(avg * 10) / 10;
  }
  function labelOf(facts) {
    if (!facts.length) return "donnees_insuffisantes";
    const s = globalScore(facts);
    if (s > 5) return "aligne";
    if (s >= -2) return "mitige";
    if (s >= -6) return "problematique";
    return "critique";
  }

  /* ---------- Couche données ---------- */
  async function fetchCompanies(query) {
    if (DEMO) {
      const q = (query || "").toLowerCase();
      const list = window.YFT_DEMO.companies
        .filter((c) => !q || c.name.toLowerCase().includes(q))
        .map((c) => {
          const facts = window.YFT_DEMO.facts.filter((f) => f.company_id === c.id);
          return { ...c, facts, score_global: globalScore(facts), label: labelOf(facts) };
        });
      return list;
    }
    let req = sb.from("companies")
      .select("id, name, wikidata_qid, country, data_quality, score_global, label, last_reviewed_at")
      .order("name").limit(60);
    if (query) req = req.ilike("name", `%${query}%`);
    const { data, error } = await req;
    if (error) throw error;
    return data;
  }

  async function fetchCompany(idOrQid) {
    if (DEMO) {
      const c = window.YFT_DEMO.companies.find((x) => x.id === idOrQid || x.wikidata_qid === idOrQid);
      if (!c) return null;
      const facts = window.YFT_DEMO.facts.filter((f) => f.company_id === c.id);
      return { company: { ...c, score_global: globalScore(facts), label: labelOf(facts),
                          last_reviewed_at: new Date().toISOString() }, facts };
    }
    const byQid = /^Q\d+$/.test(idOrQid);
    const { data: company, error: e1 } = await sb.from("companies").select("*")
      .eq(byQid ? "wikidata_qid" : "id", idOrQid).maybeSingle();
    if (e1) throw e1;
    if (!company) return null;
    // RLS : seuls les faits verified=true sont visibles — pas besoin de filtrer
    const { data: facts, error: e2 } = await sb.from("facts")
      .select("axis, fact_type, weight, year, description, source_url")
      .eq("company_id", company.id)
      .order("weight", { ascending: false });
    if (e2) throw e2;
    return { company, facts: facts || [] };
  }

  /* ---------- Boussole pentagonale (signature) ---------- */
  // Score -10..+10 -> rayon 0..R ; 0 = anneau médian
  function compassSVG(facts, size, opts) {
    const o = opts || {};
    const R = size / 2 - (o.labels ? 34 : 6);
    const cx = size / 2, cy = size / 2 + (o.labels ? 4 : 0);
    const pt = (i, r) => {
      const ang = -Math.PI / 2 + (i * 2 * Math.PI) / 5;
      return [cx + r * Math.cos(ang), cy + r * Math.sin(ang)];
    };
    const ring = (r) => AXES.map((_, i) => pt(i, r).map((v) => v.toFixed(1)).join(",")).join(" ");
    const scores = AXES.map((a) => axisScore(facts, a.key));
    const dataPoly = scores
      .map((s, i) => pt(i, ((s + 10) / 20) * R).map((v) => v.toFixed(1)).join(","))
      .join(" ");
    const axesLines = AXES.map((_, i) => {
      const [x, y] = pt(i, R);
      return `<line x1="${cx}" y1="${cy}" x2="${x.toFixed(1)}" y2="${y.toFixed(1)}" stroke="#dcdfe6" stroke-width="1"/>`;
    }).join("");
    const labels = o.labels ? AXES.map((a, i) => {
      const [x, y] = pt(i, R + 20);
      const anchor = Math.abs(x - cx) < 8 ? "middle" : x > cx ? "start" : "end";
      return `<text x="${x.toFixed(1)}" y="${y.toFixed(1)}" text-anchor="${anchor}"
        font-family="IBM Plex Mono, monospace" font-size="11" fill="#44516a">${a.name}</text>
        <text x="${x.toFixed(1)}" y="${(y + 13).toFixed(1)}" text-anchor="${anchor}"
        font-family="IBM Plex Mono, monospace" font-size="11" font-weight="600"
        fill="${scores[i] < 0 ? "#c0392b" : scores[i] > 0 ? "#1e8a4c" : "#8a8f98"}">${fmt(scores[i])}</text>`;
    }).join("") : "";
    return `<svg viewBox="0 0 ${size} ${size}" role="img"
      aria-label="Boussole des 5 axes : ${AXES.map((a, i) => `${a.name} ${fmt(scores[i])}`).join(", ")}">
      <polygon points="${ring(R)}" fill="none" stroke="#dcdfe6" stroke-width="1.2"/>
      <polygon points="${ring(R * 0.5)}" fill="none" stroke="#dcdfe6" stroke-width="1" stroke-dasharray="3 3"/>
      ${axesLines}
      <polygon points="${dataPoly}" fill="rgba(36,86,230,.13)" stroke="#2456e6" stroke-width="2" stroke-linejoin="round"/>
      ${scores.map((s, i) => {
        const [x, y] = pt(i, ((s + 10) / 20) * R);
        return `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="3.2" fill="#2456e6"/>`;
      }).join("")}
      ${labels}
    </svg>`;
  }

  /* ---------- Utilitaires ---------- */
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const fmt = (n) => {
    const v = Math.round(n * 10) / 10;
    return (v > 0 ? "+" : "") + String(v).replace(".", ",");
  };
  const demoBanner = () => DEMO
    ? `<div class="demo-banner">Mode démonstration — données d'exemple locales.
       Renseignez votre projet Supabase dans <span class="mono">config.js</span> pour les données réelles.</div>`
    : "";

  /* ---------- Vues ---------- */
  async function viewHome(query) {
    app.innerHTML = `${demoBanner()}
      <section class="hero">
        <h1>Où va l'argent que vous <em>donnez</em> aux entreprises ?</h1>
        <p class="lede">Chaque entreprise est notée de −10 à +10 sur 5 axes — fiscalité, lobbying,
        données, droits fondamentaux, empreinte démocratique — sur base exclusive de faits publics,
        sourcés et vérifiables. Pas d'opinion : des preuves.</p>
        <form class="search" id="searchForm" role="search">
          <input id="searchInput" type="search" placeholder="Chercher une entreprise…"
                 aria-label="Chercher une entreprise" value="${esc(query || "")}">
          <button type="submit">Chercher</button>
        </form>
      </section>
      <div class="company-grid" id="grid"><p class="state">Chargement…</p></div>`;

    document.getElementById("searchForm").addEventListener("submit", (e) => {
      e.preventDefault();
      const q = document.getElementById("searchInput").value.trim();
      location.hash = q ? `#/?q=${encodeURIComponent(q)}` : "#/";
    });

    try {
      const companies = await fetchCompanies(query);
      const grid = document.getElementById("grid");
      if (!companies.length) {
        grid.innerHTML = `<p class="state">Aucune entreprise trouvée pour « ${esc(query)} ».
          <span class="hint">Vous pouvez proposer son ajout à l'équipe éditoriale.</span></p>`;
        return;
      }
      grid.innerHTML = companies.map((c) => `
        <a class="company-card" href="#/c/${esc(c.wikidata_qid || c.id)}">
          <div class="mini-compass">${DEMO ? compassSVG(c.facts, 64) :
            `<svg viewBox="0 0 24 24" width="64" height="64"><polygon points="12,2 21.5,9 17.9,21 6.1,21 2.5,9" fill="none" stroke="#dcdfe6" stroke-width="1.4"/></svg>`}</div>
          <div>
            <h3>${esc(c.name)}</h3>
            <div class="meta">${esc(c.wikidata_qid || "")} · global ${c.score_global == null ? "—" : fmt(c.score_global)}</div>
            <span class="badge" data-label="${esc(c.label || "donnees_insuffisantes")}">${LABELS[c.label]?.txt || "Données insuffisantes"}</span>
          </div>
        </a>`).join("");
    } catch (err) {
      document.getElementById("grid").innerHTML =
        `<p class="state">Impossible de charger les entreprises.<br>
         <span class="hint mono">${esc(err.message)}</span></p>`;
    }
  }

  async function viewCompany(idOrQid) {
    app.innerHTML = `<p class="state">Chargement de la fiche…</p>`;
    let res;
    try { res = await fetchCompany(idOrQid); }
    catch (err) {
      app.innerHTML = `<p class="state">Erreur de chargement.<br><span class="hint mono">${esc(err.message)}</span></p>`;
      return;
    }
    if (!res) {
      app.innerHTML = `<p class="state">Entreprise introuvable. <a href="#/">Retour à la recherche</a></p>`;
      return;
    }
    const { company: c, facts } = res;
    const label = c.label || labelOf(facts);
    const global = c.score_global ?? globalScore(facts);
    const counts = Object.fromEntries(AXES.map((a) => [a.key, {
      pos: facts.filter((f) => f.axis === a.key && f.fact_type === "positive").length,
      neg: facts.filter((f) => f.axis === a.key && f.fact_type === "negative").length,
    }]));
    const lastReviewed = c.last_reviewed_at
      ? new Date(c.last_reviewed_at).toLocaleDateString("fr-BE", { year: "numeric", month: "long", day: "numeric" })
      : "—";

    const axisRows = AXES.map((a) => {
      const s = axisScore(facts, a.key);
      const pct = Math.abs(s) * 5; // 10 -> 50%
      const cls = s < 0 ? "neg" : "pos";
      return `<div class="axe-row">
        <span class="axe-name">${a.name}</span>
        <span class="axe-track"><span class="axe-fill ${cls}" style="width:${pct}%"></span></span>
        <span class="axe-score ${s < 0 ? "neg" : s > 0 ? "pos" : ""}">${fmt(s)}</span>
        <span class="axe-counts">${counts[a.key].pos}\u00A0+ / ${counts[a.key].neg}\u00A0−</span>
      </div>`;
    }).join("");

    const factRows = facts.length ? AXES.map((a) => {
      const fs = facts.filter((f) => f.axis === a.key);
      if (!fs.length) return "";
      return fs.map((f) => {
        const w = effectiveWeight(f.weight, f.year);
        const sign = f.fact_type === "negative" ? -1 : 1;
        const decay = w === 0 ? "exclu (>10 ans)" : w !== f.weight ? `×0,5 (>5 ans)` : "";
        return `<article class="fact ${f.fact_type}">
          <div class="fact-weight">
            <span class="pts">${w === 0 ? "0" : fmt(sign * w)} pt${Math.abs(w) > 1 ? "s" : ""}</span>
            <span class="decay">poids ${f.weight}${decay ? " · " + decay : ""} · ${f.year}</span>
          </div>
          <div class="fact-body">
            <p>${esc(f.description)}</p>
            <p class="fact-meta">${a.name} ·
              <a href="${esc(f.source_url)}" target="_blank" rel="noopener">source primaire ↗</a></p>
          </div>
        </article>`;
      }).join("");
    }).join("") : `<p class="state">Aucun fait vérifié pour cette entreprise —
       <span class="hint">un score absent n'est pas un score positif.</span></p>`;

    const mailto = `mailto:${esc(CFG.CONTEST_EMAIL || "contester@youfundthat.eu")}` +
      `?subject=${encodeURIComponent("Contestation de score — " + c.name)}` +
      `&body=${encodeURIComponent("Entreprise : " + c.name + "\nFait contesté : \nSource primaire alternative (URL obligatoire) : \nArgument : ")}`;

    app.innerHTML = `${demoBanner()}
      <a class="back" href="#/">← Toutes les entreprises</a>
      <header class="fiche-head">
        <div class="fiche-id">
          <div class="qid">${esc(c.wikidata_qid || "")} · ${esc(c.country || "")} ·
            <span class="data-quality">couverture des données : ${c.data_quality ?? "?"}/5</span></div>
          <h1>${esc(c.name)}</h1>
          <div class="score-line">
            <span class="score-global">${facts.length ? fmt(global) : "—"}<small> / ±10</small></span>
            <span class="badge" data-label="${esc(label)}">${LABELS[label]?.txt || label}</span>
          </div>
        </div>
        <div class="compass-wrap">${compassSVG(facts, 360, { labels: true })}</div>
      </header>

      <h2 class="axes-title">Les 5 axes</h2>
      <div class="axes">${axisRows}</div>

      <section class="facts">
        <h2>Registre des faits</h2>
        <p class="registre-note">Chaque fait est vérifié par deux éditeurs distincts et lié à sa source
        primaire. Les faits de plus de 5 ans comptent pour moitié ; au-delà de 10 ans ils sont exclus du score.</p>
        ${factRows}
      </section>

      <aside class="transparence" aria-label="Transparence du score">
        <h2>Transparence du score</h2>
        <ul>
          <li>${facts.filter((f) => f.fact_type === "positive").length} fait(s) positif(s) et
              ${facts.filter((f) => f.fact_type === "negative").length} fait(s) négatif(s) comptabilisés —
              détail par axe ci-dessus.</li>
          <li>Chaque fait du registre est lié à sa source primaire.</li>
          <li>Dernier recalcul : ${esc(lastReviewed)}.</li>
        </ul>
        <a class="btn-contester" href="${mailto}">Contester ce score</a>
        <p class="mention">Score calculé sur base de faits publics vérifiables —
           méthodologie complète sur <a href="#/methodologie">/boussole</a>.</p>
      </aside>`;
  }

  function viewMethodologie() {
    app.innerHTML = `<div class="prose">
      <a class="back" href="#/">← Retour</a>
      <h1>Méthodologie — l'essentiel</h1>
      <p>Le score de chaque entreprise est <strong>binaire</strong> (un fait prouvé et sourcé donne ses
      points, tout le reste vaut zéro), <strong>automatique</strong> (recalculé par la base de données à
      chaque modification — jamais saisi à la main) et <strong>public</strong> (reproductible par
      n'importe qui à partir des sources primaires).</p>
      <table>
        <tr><th>Label</th><th>Score global</th></tr>
        <tr><td>✅ Aligné</td><td>score &gt; +5,0</td></tr>
        <tr><td>🟡 Mitigé</td><td>−2,0 ≤ score ≤ +5,0</td></tr>
        <tr><td>🟠 Problématique</td><td>−6,0 ≤ score &lt; −2,0</td></tr>
        <tr><td>🔴 Critique</td><td>score &lt; −6,0</td></tr>
        <tr><td>⚪ Données insuffisantes</td><td>aucun fait vérifié</td></tr>
      </table>
      <p>Les faits de plus de 5 ans comptent pour moitié ; ceux de plus de 10 ans sont exclus du score
      mais restent visibles. Le journal de toutes les modifications est public et immuable.
      La méthodologie complète (V1.1) et son changelog sont publiés sur
      <a href="https://github.com/obeeonesolo/youfundthat" target="_blank" rel="noopener">github.com/obeeonesolo/youfundthat</a>.</p>
    </div>`;
  }

  /* ---------- Routeur ---------- */
  function route() {
    const h = location.hash || "#/";
    const mCompany = h.match(/^#\/c\/([^/?]+)/);
    const mQuery = h.match(/[?&]q=([^&]*)/);
    if (mCompany) return viewCompany(decodeURIComponent(mCompany[1]));
    if (h.startsWith("#/methodologie")) return viewMethodologie();
    return viewHome(mQuery ? decodeURIComponent(mQuery[1]) : "");
  }
  window.addEventListener("hashchange", route);
  route();
})();
