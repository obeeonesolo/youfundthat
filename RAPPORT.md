# RAPPORT — Écarts détectés entre la Méthodologie V1.0 et son implémentation

Implémenter la méthodologie en code exécutable a révélé des incohérences internes
au document V1.0. Pour un outil qui revendique l'**auditabilité totale** et la
**reproductibilité par tout tiers**, ces écarts doivent être tranchés et publiés
(changelog V1.1) — sinon le premier journaliste qui recalcule un score trouvera
un résultat différent de celui affiché.

## 1. La décote temporelle n'est pas appliquée dans les exemples du document — CRITIQUE

La section 2.4 définit : faits ≤ 5 ans → ×1.0, ≤ 10 ans → ×0.5, > 10 ans → ×0.0.
Mais la formule SQL de la section 2.1 ne l'applique pas, et **3 exemples sur 6 la
contredisent** (calcul à date de référence juin 2026) :

| Exemple | Fait concerné | Âge | Score doc | Score selon règle 2.4 |
|---|---|---|---|---|
| Apple — fiscal | Décision CE 2016 (taux ~1%) | 10 ans → ×0.5 | **-5** | **-4** |
| Meta — données | Arrêt Schrems II 2020 | 6 ans → ×0.5 | **-8** | **-6.5** |
| Amazon — fiscal | CJUE + CE 2017 | 9 ans → ×0.5 | **-5** | **-2.5** |
| Amazon — global | (conséquence) | — | **-2.6** | **-2.1** |

**Décision d'implémentation : la règle 2.4 fait foi** (c'est la règle générale ;
les exemples sont des illustrations). Les exemples du document doivent être
recalculés dans la V1.1. Le label final d'Amazon reste 🟠 Problématique (-2.1),
mais de justesse — voir point 3.

**Alternative à considérer** : si l'intention était que les exemples soient
corrects, alors la décote ne s'appliquerait qu'aux faits *résolus* (l'exemple
Apple LuxLeaks dit "résolue depuis"). Cela demanderait un champ `resolved`
dans la table facts. À trancher par l'éditeur de la méthodologie.

## 2. Poids du fait LuxLeaks dans l'exemple Apple — MINEUR

L'exemple section 3 attribue `weight=3` au fait LuxLeaks, mais la grille de
critères définit "Structure offshore documentée (LuxLeaks…)" à `weight=2`.
Sans impact sur le score (décote ×0 dans les deux cas), mais l'exemple
contredit la grille. À corriger en V1.1.

## 3. Bornes des labels ambiguës — MOYEN

Section 8.2 : Mitigé = "-2,0 à +5,0" et Problématique = "-6,0 à -2,0".
Le score **-2,0 exactement** appartient aux deux intervalles. Idem pour la
borne -6,0. Convention retenue dans l'implémentation :

- ✅ Aligné : score > +5.0
- 🟡 Mitigé : -2.0 ≤ score ≤ +5.0
- 🟠 Problématique : -6.0 ≤ score < -2.0
- 🔴 Critique : score < -6.0

Conséquence concrète : Amazon à -2.1 est Problématique, mais à -2.0 il serait
Mitigé. Avec la décote, beaucoup d'entreprises graviteront autour de cette
frontière. La V1.1 doit fixer les bornes avec des inégalités explicites.

## 4. Numérotation des sections — COSMÉTIQUE

Le document saute de la section 2 aux axes numérotés 1-5, puis reprend à la
section 8. La règle de neutralité politique est référencée "section 7" mais
apparaît dans l'axe 5. À renuméroter en V1.1.

## 5. Choix d'implémentation à valider

1. **Label "Données insuffisantes"** : une entreprise sans aucun fait vérifié
   reçoit ce label au lieu de 🟡 Mitigé (score 0) — conforme à l'esprit de la
   section 11 ("Score absent ≠ score positif"), mais non spécifié formellement.
2. **Scores d'axe fractionnaires** : avec la décote ×0.5, un axe peut valoir
   -6.5. Le document n'envisage que des entiers. Affichage : 1 décimale.
3. **Contrainte de double validation** : `verified=true` exige `verified_by`
   et `verified_at` non nuls (étape 5 du workflow 10.1), imposé au niveau
   base de données — un éditeur ne peut pas court-circuiter le processus.
4. **Décote relative à l'année civile** : `EXTRACT(YEAR FROM now()) - year`,
   comme dans le document. Un fait de décembre 2021 et un de janvier 2021
   décotent au même moment (1er janvier 2027). Alternative plus fine : décote
   par date exacte du fait (demanderait un champ `fact_date` au lieu de `year`).
