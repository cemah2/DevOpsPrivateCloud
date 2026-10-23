# tofu/eso-espaces.tf — plateforme/secrets : EXTRAIT à intégrer (F4-S12, CHG-3412).
# Deux entrées de plus dans local.espaces_eso (même politique eso-espace.hcl.tftpl : lecture de
# kv/<application>/<environnement>/* seulement). Application « legacy » : chemins kv/legacy/<env>/…
#
#    "legacy-rdv-recette" = { application = "legacy", environnement = "recette", chemins_creds = [] }
#    "legacy-rdv-prod"    = { application = "legacy", environnement = "prod", chemins_creds = [] }
#
# Valeurs (jamais dans Git ni dans l'état OpenTofu) : écrites par une personne de plateforme-admins
# avec la CLI bao (connexion OIDC), mots de passe aléatoires générés sur adm01 (openssl rand) :
#   bao kv put kv/legacy/recette/mariadb root=<GENERE> application=<GENERE> migrateur=<GENERE>
#   bao kv put kv/legacy/recette/s3 access_key_id=<CLE> secret_access_key=<SECRET>
# (voir le corrigé : génération sans que la valeur passe par la ligne de commande).
