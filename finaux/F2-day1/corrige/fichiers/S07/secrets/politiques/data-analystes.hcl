# politiques/data-analystes.hcl — groupe « data » (Hugo Bernard, Sarah Colin) (F2-S07, DEV-3207).
# Politique AJOUTÉE à celle que rend l'équipe en code (data-equipe : kv/data/traitements/*) par
# var.politiques_equipes_en_plus (tofu/equipes.extrait-F2-S07.tf).
# Lecture de la base de statistiques par comptes dynamiques personnels : chaque compte est créé pour
# UNE connexion OIDC (le journal d'audit d'OpenBao relie le compte PostgreSQL à la personne ; le nom du
# compte commence par le nom d'affichage du jeton, tronqué). La gestion des secrets de l'espace reste
# dans data-equipe. RIEN sous kv/mediagenda, db-mediagenda ni ailleurs.
path "db-data/creds/data-analyste" {
  capabilities = ["read"]
}

path "sys/capabilities-self" {
  capabilities = ["update"]
}
