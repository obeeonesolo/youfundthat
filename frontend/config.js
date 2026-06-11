// ============================================================
// YouFundThat — Configuration frontend
// Renseigner l'URL du projet Supabase et la clé ANON (publique).
// La clé anon est faite pour être exposée — la sécurité repose
// sur les RLS policies (sql/05_rls.sql), pas sur le secret.
// NE JAMAIS mettre la clé service_role ici.
// Laisser vide pour utiliser le mode démonstration (demo-data.js).
// ============================================================
window.YFT_CONFIG = {
  SUPABASE_URL: "https://nralpuhptljtjmgdqpxt.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_GJbg1PUxmMOdqTzHwlHUQQ_oYGcYS2Z",
  CONTEST_EMAIL: "contester@youfundthat.eu",
};
