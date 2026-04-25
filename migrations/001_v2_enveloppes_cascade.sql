-- =============================================================
-- WEC PILOTAGE V2 — Migration 001
-- À exécuter dans Supabase SQL Editor (projet AP2M)
-- Idempotent : peut être ré-exécuté sans casse.
-- =============================================================

-- 1) Enveloppes éditables au niveau projet --------------------
-- env_gars existe déjà. On ajoute env_wal / env_regul_urssaf / env_famille
-- + métadonnées de provision / base nette pour figer le snapshot.
ALTER TABLE wec_chantiers ADD COLUMN IF NOT EXISTS env_wal           NUMERIC DEFAULT 0;
ALTER TABLE wec_chantiers ADD COLUMN IF NOT EXISTS env_regul_urssaf  NUMERIC DEFAULT 0;
ALTER TABLE wec_chantiers ADD COLUMN IF NOT EXISTS env_famille       NUMERIC DEFAULT 0;
ALTER TABLE wec_chantiers ADD COLUMN IF NOT EXISTS duree_jours       INTEGER;
ALTER TABLE wec_chantiers ADD COLUMN IF NOT EXISTS nb_projets_actifs INTEGER DEFAULT 1;
ALTER TABLE wec_chantiers ADD COLUMN IF NOT EXISTS provision_charges NUMERIC;
ALTER TABLE wec_chantiers ADD COLUMN IF NOT EXISTS base_nette        NUMERIC;
ALTER TABLE wec_chantiers ADD COLUMN IF NOT EXISTS date_clot         TIMESTAMPTZ;

-- 2) Cycle de vie des factures + ventilation v2 ---------------
-- statut: brouillon | validee | payee | cloturee
ALTER TABLE wec_ventes ADD COLUMN IF NOT EXISTS statut               TEXT DEFAULT 'validee';
ALTER TABLE wec_ventes ADD COLUMN IF NOT EXISTS walid_validation_date TIMESTAMPTZ;
ALTER TABLE wec_ventes ADD COLUMN IF NOT EXISTS ventil_regul_urssaf  NUMERIC DEFAULT 0;
ALTER TABLE wec_ventes ADD COLUMN IF NOT EXISTS force_overflow       NUMERIC DEFAULT 0;
ALTER TABLE wec_ventes ADD COLUMN IF NOT EXISTS updated_at           TIMESTAMPTZ DEFAULT now();

-- 3) Audit log append-only ------------------------------------
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

-- 4) Backfill enveloppes depuis wec_budgets (1ère exécution) --
-- On hydrate env_wal / env_famille / env_regul_urssaf et provision/base_nette
-- depuis le budget validé associé, si pas déjà rempli.
UPDATE wec_chantiers c SET
  env_wal           = COALESCE(NULLIF(c.env_wal, 0),           b.wal_total),
  env_famille       = COALESCE(NULLIF(c.env_famille, 0),       b.famille_total),
  env_regul_urssaf  = COALESCE(NULLIF(c.env_regul_urssaf, 0),  b.urssaf_regul),
  base_nette        = COALESCE(c.base_nette,                   b.base_ht),
  provision_charges = COALESCE(c.provision_charges,            b.provision_charges,
                                CASE WHEN b.duree_mois IS NOT NULL AND b.nb_chantiers_actifs IS NOT NULL
                                     THEN 1828.0 * b.duree_mois / b.nb_chantiers_actifs END),
  duree_jours       = COALESCE(c.duree_jours,                  b.duree_mois * 30),
  nb_projets_actifs = COALESCE(c.nb_projets_actifs,            b.nb_chantiers_actifs)
FROM wec_budgets b
WHERE b.code_chantier = c.code;

-- Si une enveloppe est restée à NULL/0, on applique la règle 45/55.
UPDATE wec_chantiers SET
  env_gars = COALESCE(NULLIF(env_gars, 0), ROUND(COALESCE(base_nette, 0) * 0.45)),
  env_wal  = COALESCE(NULLIF(env_wal, 0),  ROUND(COALESCE(base_nette, 0) * 0.55))
WHERE base_nette IS NOT NULL;

-- 5) Statut par défaut sur les ventes existantes --------------
-- Si une vente est marquée payée, statut = payee, sinon validee.
UPDATE wec_ventes SET statut = CASE WHEN paye THEN 'payee' ELSE 'validee' END
WHERE statut IS NULL OR statut = 'validee';

-- =============================================================
-- FIN — vérifier dans la console Supabase qu'aucune erreur.
-- =============================================================
