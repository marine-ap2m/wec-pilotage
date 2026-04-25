-- =============================================================
-- WEC PILOTAGE — Schéma complet (création si absent)
-- À EXÉCUTER EN PREMIER si les tables wec_* n'existent pas encore.
-- Idempotent : CREATE TABLE IF NOT EXISTS, peut être ré-exécuté.
-- Inclut directement les colonnes v2 → si tu lances ce script,
-- tu peux SAUTER 001_v2_enveloppes_cascade.sql (sauf le backfill).
-- =============================================================

-- 1) Projets (chantiers) ---------------------------------------
CREATE TABLE IF NOT EXISTS wec_chantiers (
  id                TEXT PRIMARY KEY,
  code              TEXT UNIQUE,
  nom               TEXT NOT NULL,
  statut            TEXT DEFAULT 'en_cours',           -- en_cours | a_venir | termine
  marche_ht         NUMERIC DEFAULT 0,
  avenant_ht        NUMERIC DEFAULT 0,
  env_gars          NUMERIC DEFAULT 0,
  -- v2
  env_wal           NUMERIC DEFAULT 0,
  env_regul_urssaf  NUMERIC DEFAULT 0,
  env_famille       NUMERIC DEFAULT 0,
  base_nette        NUMERIC,
  provision_charges NUMERIC,
  duree_jours       INTEGER,
  nb_projets_actifs INTEGER DEFAULT 1,
  date_clot         TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_chantiers_code   ON wec_chantiers(code);
CREATE INDEX IF NOT EXISTS idx_chantiers_statut ON wec_chantiers(statut);

-- 2) Budgets (snapshot simulateur) -----------------------------
CREATE TABLE IF NOT EXISTS wec_budgets (
  id                  TEXT PRIMARY KEY,
  code_chantier       TEXT REFERENCES wec_chantiers(code) ON DELETE CASCADE,
  duree_mois          INTEGER,
  nb_chantiers_actifs INTEGER DEFAULT 1,
  base_ht             NUMERIC,
  env_gars_total      NUMERIC,
  mo_total            NUMERIC,
  fact_gars_total     NUMERIC,
  wal_total           NUMERIC,
  urssaf_total        NUMERIC,
  famille_total       NUMERIC,
  net_perso_total     NUMERIC,
  urssaf_regul        NUMERIC DEFAULT 0,
  provision_charges   NUMERIC,
  valide              BOOLEAN DEFAULT FALSE,
  date_validation     DATE,
  walid_ok            BOOLEAN DEFAULT FALSE,
  date_walid_ok       DATE,
  created_at          TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_budgets_code ON wec_budgets(code_chantier);

-- 3) Lignes prévisionnelles par facture (depuis simulateur) ---
CREATE TABLE IF NOT EXISTS wec_budgets_factures (
  id              TEXT PRIMARY KEY,
  budget_id       TEXT REFERENCES wec_budgets(id) ON DELETE CASCADE,
  code_chantier   TEXT,
  num_facture     INTEGER,
  montant_marche  NUMERIC,
  montant_wal     NUMERIC,
  mo              NUMERIC,
  urssaf          NUMERIC,
  famille         NUMERIC,
  net_perso       NUMERIC,
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_bf_code ON wec_budgets_factures(code_chantier);

-- 4) Ventes réelles (factures émises) --------------------------
CREATE TABLE IF NOT EXISTS wec_ventes (
  id                    TEXT PRIMARY KEY,
  code_chantier         TEXT,
  cid                   TEXT,                         -- legacy fallback
  date_facture          DATE,
  numero                TEXT UNIQUE,
  montant_ht            NUMERIC,
  paye                  BOOLEAN DEFAULT FALSE,
  date_paiement         DATE,
  categorie             TEXT DEFAULT 'facture_vente',
  ventil_gars           NUMERIC DEFAULT 0,
  ventil_fact_gars      NUMERIC DEFAULT 0,
  ventil_treso          NUMERIC DEFAULT 0,
  ventil_wal            NUMERIC DEFAULT 0,
  ventil_urssaf         NUMERIC DEFAULT 0,
  ventil_famille        NUMERIC DEFAULT 0,
  ventil_net            NUMERIC DEFAULT 0,
  -- v2
  statut                TEXT DEFAULT 'validee',       -- brouillon | validee | payee | cloturee
  walid_validation_date TIMESTAMPTZ,
  ventil_regul_urssaf   NUMERIC DEFAULT 0,
  force_overflow        NUMERIC DEFAULT 0,
  updated_at            TIMESTAMPTZ DEFAULT now(),
  created_at            TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ventes_code   ON wec_ventes(code_chantier);
CREATE INDEX IF NOT EXISTS idx_ventes_statut ON wec_ventes(statut);
CREATE INDEX IF NOT EXISTS idx_ventes_paye   ON wec_ventes(paye);

-- 5) Dépenses (gars, facture_gars, charge_fixe) ----------------
CREATE TABLE IF NOT EXISTS wec_depenses (
  id            TEXT PRIMARY KEY,
  code_chantier TEXT,
  cid           TEXT,                                 -- legacy fallback
  date_achat    DATE,
  fournisseur   TEXT,
  montant_ht    NUMERIC,
  paye          BOOLEAN DEFAULT TRUE,
  categorie     TEXT,                                 -- gars | facture_gars | charge_fixe
  created_at    TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_depenses_code ON wec_depenses(code_chantier);
CREATE INDEX IF NOT EXISTS idx_depenses_cat  ON wec_depenses(categorie);

-- 6) Virements Walid (famille / walid_net / urssaf) ------------
CREATE TABLE IF NOT EXISTS wec_walid_net (
  id            TEXT PRIMARY KEY,
  code_chantier TEXT,
  cid           TEXT,                                 -- legacy fallback
  date_virement DATE,
  montant       NUMERIC,
  categorie     TEXT,                                 -- famille | walid_net | urssaf
  created_at    TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_walid_code ON wec_walid_net(code_chantier);
CREATE INDEX IF NOT EXISTS idx_walid_cat  ON wec_walid_net(categorie);

-- 7) URSSAF (déclarations + paiements) -------------------------
CREATE TABLE IF NOT EXISTS wec_urssaf (
  id            TEXT PRIMARY KEY,
  type          TEXT,                                 -- declaration | paiement
  trimestre     TEXT,
  montant       NUMERIC,
  date          DATE,
  date_echeance DATE,
  libelle       TEXT,
  paye          BOOLEAN DEFAULT FALSE,
  created_at    TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_urssaf_type ON wec_urssaf(type);

-- 8) Audit log (append-only) -----------------------------------
CREATE TABLE IF NOT EXISTS wec_audit_logs (
  id            TEXT PRIMARY KEY,
  action        TEXT NOT NULL,
  user_role     TEXT,
  code_chantier TEXT,
  facture_id    TEXT,
  details       JSONB,
  created_at    TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_code    ON wec_audit_logs(code_chantier);
CREATE INDEX IF NOT EXISTS idx_audit_facture ON wec_audit_logs(facture_id);
CREATE INDEX IF NOT EXISTS idx_audit_action  ON wec_audit_logs(action);

-- =============================================================
-- POLITIQUES RLS — accès anon en lecture/écriture (PIN client-side)
-- Q9 : on désactive RLS pour la v1 (perf + simplicité).
-- Si tu veux durcir plus tard, basculer sur Supabase Auth + RLS.
-- =============================================================
ALTER TABLE wec_chantiers         DISABLE ROW LEVEL SECURITY;
ALTER TABLE wec_budgets           DISABLE ROW LEVEL SECURITY;
ALTER TABLE wec_budgets_factures  DISABLE ROW LEVEL SECURITY;
ALTER TABLE wec_ventes            DISABLE ROW LEVEL SECURITY;
ALTER TABLE wec_depenses          DISABLE ROW LEVEL SECURITY;
ALTER TABLE wec_walid_net         DISABLE ROW LEVEL SECURITY;
ALTER TABLE wec_urssaf            DISABLE ROW LEVEL SECURITY;
ALTER TABLE wec_audit_logs        DISABLE ROW LEVEL SECURITY;

-- =============================================================
-- VÉRIFICATION FINALE — exécute ces SELECTs dans la même session
-- pour confirmer que tout est OK :
-- =============================================================
-- SELECT table_name FROM information_schema.tables
--  WHERE table_schema='public' AND table_name LIKE 'wec_%';
-- → doit retourner les 8 tables ci-dessus.
