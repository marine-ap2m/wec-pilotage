# Handoff — Enveloppes projet + ventilation cascade

**Date :** 24 avril 2026
**Branche :** `claude/wec-financial-envelopes-GDqwf`
**Scope :** Fiabilisation des joins, ventilation cascade entre factures, édition post-validation, vue Walid enrichie.

---

## 1. Rappel modèle financier (verrouillé, NE PAS TOUCHER)

```js
// index.html:351-362
const FRAIS_MENSUELS = 1828;                               // Qonto(12)+Dougs(119)+Assurance(497)+AP2M(1200)
provisionCF = 1828 * duree_mois / nb_chantiers_actifs;
baseNette   = (marche + avenant) - provisionCF;
envGars     = baseNette * 0.45;
MO          = envGars / 1.20;
factGars    = MO * 0.20;
factWal     = baseNette - envGars;                         // ⇔ baseNette * 0.55
urssaf      = factWal * 0.212;
netTotal    = factWal * 0.75;
netPerso    = netTotal - famille - regulURSSAF;
```

**Invariant :** `factGars + factWal = baseNette` et la somme des 7 ventil_* = montant facture HT.

---

## 2. Schéma Supabase (tables existantes)

Les noms réels diffèrent du brief initial. Les tables sont préfixées `wec_*`.

```
wec_chantiers       id, code, nom, marche_ht, avenant_ht, statut, created_at
wec_budgets         id, code_chantier, duree_mois, nb_chantiers_actifs,
                    base_ht, env_gars_total, mo_total, fact_gars_total,
                    wal_total, urssaf_total, famille_total, net_perso_total,
                    urssaf_regul, provision_charges, valide, walid_ok,
                    date_validation, date_walid_ok
wec_budgets_factures id, budget_id, code_chantier, num_facture,
                    montant_marche, montant_wal, mo, urssaf, famille, net_perso
wec_ventes          id, code_chantier, date_facture, numero, montant_ht,
                    paye, date_paiement, categorie,
                    ventil_gars, ventil_fact_gars, ventil_treso,
                    ventil_wal, ventil_urssaf, ventil_famille, ventil_net
wec_depenses        id, code_chantier, date_achat, fournisseur,
                    montant_ht, paye, categorie
wec_walid_net       id, code_chantier, date_virement, montant, categorie
wec_urssaf          id, date_echeance, montant, statut, ...
```

**Règle d'or :** toutes les joins entre tables passent par `code_chantier`.
Il n'y a **plus** de fallback sur `cid` depuis cette release (cf. régression historique).

---

## 3. Modifications apportées dans `index.html`

### A. Helpers (nouvelles fonctions)

```js
matchCh(row, c)        // remplace toutes les chaînes `code_chantier===c.id||c.code||cid...`
envBud(bud)            // extrait les enveloppes d'une ligne wec_budgets en objet typé
consomme(code, excludeId) // somme les 7 ventils des factures du chantier (hors facture en édition)
_chSel() / _budSel()   // chantier et budget sélectionnés dans le modal facture
_hint(id, reste, budget) // affiche un badge "Reste enveloppe" vert/orange/rouge
```

### B. Ventilation cascade dans le modal facture

1. Quand Marine ouvre "Encaissement / Facture" et sélectionne un chantier + montant :
   - `ventilAuto()` pré-remplit `v-gars`, `v-treso`, `v-fam` au **pro-rata de l'enveloppe restante** (pas du budget initial).
   - Formule : `suggestion = max(0, env - consommé_autres_factures) * (montant / base_restante)`.

2. Marine peut éditer cell-by-cell. À chaque frappe, `ventilCalc()` recalcule :
   - Les dérivés (`v-fg` = 20 % MO, `v-wal` = résidu, `v-urs`, `v-net`).
   - Un **bloc "Enveloppes restantes après cette facture"** qui affiche en temps réel le reste de chaque poste (GARS, Tréso, WAL, URSSAF, Famille, Net perso), coloré en vert/orange/rouge.
   - Un hint sous chaque input éditable ("Reste enveloppe : X / Y").

3. Alerte dépassement : **visuelle uniquement**, pas de blocage. Au save, toast d'avertissement "⚠ Dépassement GARS, Famille" si applicable. Marine peut toujours enregistrer.

### C. Édition post-validation

Dans la fiche chantier Marine, onglet **Réel**, chaque facture émise affiche un bouton **✏️ Modifier**.
- `editVente(id)` → `openModal('enc', id)` qui pré-remplit le modal avec les valeurs de la facture.
- Bannière d'avertissement : "Édition d'une facture déjà enregistrée. La modification recalcule les enveloppes restantes pour les factures suivantes."
- Save → `sbPatch('wec_ventes', id, patch)` (pas de POST).
- La cascade recalcule automatiquement : la facture éditée est **exclue** de `consomme()` via le paramètre `excludeId`, donc son nouveau montant libère/consomme correctement les enveloppes pour les factures suivantes.

### D. Vue Walid détail enrichie

Barres de progression **Famille** et **Net perso** :
- Portion pleine = réalisé encaissé.
- Portion transparente = en attente de règlement.
- Label "X / Y" et texte complémentaire "en attente de règlement".

---

## 4. Checklist de tests fonctionnels

### Scénario 1 — Nouvelle facture avec cascade
- [ ] Créer un chantier via Simulateur (marché 100 000 €, 3 factures, 1 chantier actif).
- [ ] Valider le budget → vérifier que `wec_budgets.env_gars_total` et `famille_total` sont bien renseignés.
- [ ] Ouvrir "Encaissement / Facture", sélectionner le chantier, saisir montant 33 000 €.
- [ ] Vérifier que les champs MO / Tréso / Famille se pré-remplissent ≈ 1/3 des enveloppes.
- [ ] Vérifier que le bloc "Enveloppes restantes" affiche ≈ 2/3 de chaque enveloppe en vert.
- [ ] Enregistrer.

### Scénario 2 — Cascade sur facture suivante
- [ ] Créer une 2ᵉ facture même chantier, même montant.
- [ ] Le pré-remplissage doit proposer 1/2 de ce qui reste (pas 1/3 du budget initial).
- [ ] Le bloc "Enveloppes restantes" doit tomber à ≈ 1/3 après saisie.

### Scénario 3 — Dépassement
- [ ] Sur la 3ᵉ facture, forcer un `v-gars` > enveloppe GARS restante.
- [ ] Le hint sous MO doit passer en rouge "⚠️ Dépassement : X au-dessus de l'enveloppe".
- [ ] Le bloc "Enveloppes restantes" affiche GARS en rouge avec `-X€`.
- [ ] Enregistrer → toast warn "⚠ Dépassement GARS" mais la ligne est bien créée.

### Scénario 4 — Édition post-validation
- [ ] Aller sur la fiche chantier, onglet Réel → cliquer ✏️ Modifier sur la facture 1.
- [ ] Le modal s'ouvre pré-rempli, bannière édition visible, chantier verrouillé.
- [ ] Modifier `v-fam` → vérifier recalc du net perso + reste enveloppe.
- [ ] Enregistrer → toast "Ventilation mise à jour".
- [ ] Ouvrir la facture 2 en édition → son bloc "Enveloppes restantes" reflète le nouveau total.

### Scénario 5 — Vue Walid
- [ ] Login Walid → ouvrir le chantier.
- [ ] Vérifier les deux barres "Famille" et "Net perso" (plein = encaissé, clair = attente).
- [ ] Déplier une facture → 3 lignes : Famille, Net perso, Marché facturé.

### Scénario 6 — Régression `cid`
- [ ] Marine → fiche chantier → onglet Réel → les 4 blocs enveloppes doivent afficher des chiffres non-nuls.
- [ ] Mouvements → les lignes doivent bien référencer le bon chantier (colonne "Chantier" à droite).

---

## 5. Cascade automatique (lot 2)

`recalcCascade(code)` rebalance automatiquement après chaque save (création ou édition de virement).

Algorithme :
1. Récupère tous les virements du chantier.
2. Sépare `locked` (paye=true, intouchables) et `pending` (paye=false).
3. Reste à ventiler par poste = enveloppe - somme ventil des `locked`.
4. Pour chaque virement pending : pro-rata sur son montant relatif au total pending.
5. PATCH chaque pending modifié en parallèle.

Trigger : après chaque `sbPost`/`sbPatch` sur `wec_ventes`. Toast "cascade rééquilibrée sur N virement(s)" si N>0.

Conséquence : à la fin du chantier (tous les virements encaissés), la somme des ventil_* tombe pile sur les enveloppes prévues.

## 6. URSSAF auto-agrégation par mois (lot 2)

Plus besoin de "Déclaration CA" manuelle. L'URSSAF lit directement `ventil_wal` des virements `paye=true` :
- Agrégation par mois (`date_paiement` ou fallback `date_facture`).
- Affichage : 1 carte par mois avec CA WAL + URSSAF due.
- Déclaration mensuelle, paiement trimestriel (avec demande mensuel en cours côté Marine).
- Le bouton "+ Régul antériorité" reste pour saisir les périodes pré-app.

## 7. Vue Walid refondue "scolaire maternelle" (lot 2)

3 blocs séquentiels lecture seule :
- **🎯 Le plan validé** — 6 enveloppes (gars, fact GARS, tréso société, URSSAF, famille, net) avec icônes, montants, et notes pédagogiques. Cadenas vert si `walid_ok=true`.
- **✅ Règlements déjà reçus** — pour chaque virement encaissé : "Le DD/MM, virement de X € → versé aux gars / fact GARS / tréso / URSSAF / famille / pour toi".
- **⏳ Reste à recevoir** — agrégation des virements en attente, même décomposition pédagogique, gros chiffre vert "💰 Pour toi (net à venir) : X €".

Plus de toggle/accordéon. Tout est déplié, lisible, verrouillé.

## 8. Points à clarifier / Dette technique

| Sujet | Action |
|---|---|
| Historique audit ventilation | Pas implémenté — la PATCH écrase. À prévoir : table `wec_ventes_historique` avec trigger ou snapshot manuel. |
| Seuil d'alerte personnalisable | Actuellement 20 % du budget initial déclenche l'orange. Constante à externaliser dans settings. |
| Export CSV Dougs | Non implémenté dans ce lot. |
| Suppression facture | Non modifiée — la cascade se recalcule au rechargement après suppression. |
| Pagination factures 100+ | Pas nécessaire aujourd'hui. |
| Bascule mensuel/trimestriel URSSAF | Marine a fait la demande URSSAF. Quand validé, ajouter un toggle dans les settings pour générer les échéances en mode mensuel. |

---

## 6. Recommandations workflow Marine/Walid

### Marine
- **Discipline budget** : saisir `env_gars_total` et `famille_total` précis à la validation projet — toute la cascade en dépend.
- **Édition** : corriger une facture déjà réglée est désormais sûr. Toujours vérifier la facture N+1 après édition (ouvrir en édition pour lire les nouvelles enveloppes restantes).
- **Dépassement** : la toast warn et les pills rouges sont volontairement non-bloquants. Quand tu valides malgré tout, note la raison dans le numéro de facture ou un champ dédié (à prévoir).

### Walid
- Les barres de progression répondent à sa question principale : "je suis dans les clous ou pas ?".
- Le bouton "Je suis OK" reste le seul acte de validation côté Walid — il n'intervient pas sur les ventilations.
- Si tu veux aussi lui montrer les enveloppes GARS/Tréso (transparence totale), ajouter une section "Comptes du chantier" désactivée par défaut, toggle côté Marine.

---

## 7. Fichiers touchés

- `index.html` — 1 seul fichier modifié. Pas de migration SQL nécessaire.
- `_HANDOFFS/2026-04-24_enveloppes_cascade.md` — ce document.
