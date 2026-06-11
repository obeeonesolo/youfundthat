# Changelog — Méthodologie de Scoring YouFundThat

## Version 1.1 — Juin 2026

Conformément à notre engagement de transparence, toute modification de la
méthodologie est publiée avec sa justification. Cette version ne change
**aucun principe** de la V1.0 — elle corrige des incohérences internes
détectées lors de l'implémentation du moteur de calcul, et précise des
points ambigus. Chaque correction renforce la reproductibilité : un tiers
recalculant nos scores doit obtenir exactement les mêmes résultats.

---

### 1. Décote temporelle : la règle générale fait foi — CORRECTION

**Problème détecté.** La formule SQL publiée en section 2.1 de la V1.0
n'appliquait pas la décote temporelle définie en section 2.4 (faits de plus
de 5 ans pondérés ×0,5, faits de plus de 10 ans exclus du score). Trois des
six exemples de calcul du document reproduisaient cette erreur.

**Décision.** La règle de décote (section 2.4) s'applique **sans exception**
à tous les faits, qu'ils soient résolus ou non. C'est le choix le plus
mécanique et le moins sujet à interprétation : décider qu'un fait est
"résolu" serait une appréciation éditoriale, contraire au Principe 1
(binaire, zéro subjectivité). Un fait ancien qui perdure peut — et doit —
être re-documenté par une source récente, qui constitue alors un nouveau
fait à poids plein.

**Exemples recalculés** (date de référence : juin 2026) :

| Exemple | Score V1.0 (erroné) | Score V1.1 | Explication |
|---|---|---|---|
| Apple — axe fiscal | −5 | **−4** | Décision CE 2016 (10 ans) → poids ×0,5 |
| Meta — axe données | −8 | **−6,5** | Arrêt Schrems II 2020 (6 ans) → poids ×0,5 |
| Amazon.be — axe fiscal | −5 | **−2,5** | Faits CJUE et CE de 2017 (9 ans) → poids ×0,5 |
| Amazon.be — score global | −2,6 | **−2,1** | Conséquence du recalcul fiscal — label inchangé : 🟠 Problématique |

La formule SQL publiée intègre désormais le poids effectif
(`weight × décote`) dans le calcul de chaque axe.

### 2. Bornes des labels : inégalités explicites — PRÉCISION

**Problème détecté.** Les intervalles de la V1.0 ("Mitigé : −2,0 à +5,0",
"Problématique : −6,0 à −2,0") laissaient les scores frontières (−2,0 et
−6,0) appartenir à deux labels à la fois.

**Décision.** En cas d'ambiguïté, YouFundThat retient systématiquement
l'interprétation **la moins défavorable à l'entreprise notée**. Les bornes
sont désormais définies par inégalités strictes :

| Label | Condition |
|---|---|
| ✅ Aligné | score > +5,0 |
| 🟡 Mitigé | −2,0 ≤ score ≤ +5,0 |
| 🟠 Problématique | −6,0 ≤ score < −2,0 |
| 🔴 Critique | score < −6,0 |

### 3. Nouveau label "Données insuffisantes" — FORMALISATION

La section 11 de la V1.0 énonçait "Score absent ≠ score positif" sans
définir le mécanisme. C'est désormais formel : une entreprise sans **aucun
fait vérifié** reçoit le label **⚪ Données insuffisantes** au lieu d'un
score de 0 (qui serait classé 🟡 Mitigé à tort). Aucun seuil minimal de
faits n'est appliqué au-delà de zéro — tout seuil serait arbitraire ; le
niveau de couverture est indiqué par l'indice data_quality (1-5) affiché
sur chaque fiche.

### 4. Scores affichés à une décimale — PRÉCISION

La décote ×0,5 produit des scores d'axe fractionnaires (ex. : −6,5).
Ils sont affichés **sans arrondi à l'entier**, à une décimale. Arrondir
créerait un écart entre le score affiché et le score qu'un tiers obtient
en recalculant — incompatible avec le Principe 3.

### 5. Granularité de la décote : année civile — PRÉCISION

La décote est calculée sur l'**année civile** (année courante moins l'année
du fait), conformément au champ `year` de la base. Conséquence assumée et
documentée : les décotes évoluent chaque 1er janvier, de manière prévisible
et identique pour tous. Une granularité à la date exacte est à l'étude
pour une version ultérieure.

### 6. Corrections mineures

- **Exemple Apple, fait LuxLeaks** : poids corrigé de 3 à 2, conformément
  à la grille de critères ("structure offshore documentée" = poids 2).
  Sans impact sur le score (fait de plus de 10 ans, exclu du calcul).
- **Renumérotation des sections** : les axes 1 à 5 deviennent les sections
  3 à 7 ; les renvois internes (notamment la règle de neutralité politique,
  désormais section 7) sont corrigés.

### 7. Garanties techniques nouvelles (sans changement méthodologique)

Le moteur de calcul publié avec cette version impose désormais au niveau
de la base de données — et non plus seulement par le processus éditorial :

- la **double validation** : le validateur d'un fait doit être un éditeur
  différent de celui qui l'a proposé (workflow section 10.1, étape 5) ;
- l'**invisibilité publique** des faits non vérifiés ;
- un **journal d'audit public et immuable** : chaque ajout, modification,
  validation ou suppression de fait est horodaté, attribué à son auteur,
  et consultable par quiconque. Aucune entrée ne peut être modifiée ni
  supprimée, y compris par l'équipe éditoriale.

---

*Les scores affectés par la correction de la décote (point 1) ont été
recalculés automatiquement à la publication de cette version. La date de
recalcul (last_reviewed_at) figure sur chaque fiche.*

*Méthodologie complète : youfundthat.eu/boussole — Les désaccords se
résolvent par les sources, pas par l'autorité éditoriale.*

---

## Version 1.0 — Juin 2026

Publication initiale.
