# politiques/mediagenda-dev.hcl — groupe « mediagenda » (Julien Petit) (M25-E05, en code en E08).
# L'équipe gère elle-même les secrets de SON environnement de développement, et rien d'autre :
# ni la recette, ni la production (identités machines du palier 2), ni la plateforme.
path "kv/data/mediagenda/dev/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# Le « * » couvre aussi la chaîne vide : cette règle permet de lister kv/metadata/mediagenda/dev/.
# Pas de « delete » ici : supprimer les MÉTADONNÉES efface le secret et TOUTES ses versions, sans
# retour possible (c'est une destruction, comme kv/destroy).
path "kv/metadata/mediagenda/dev/*" {
  capabilities = ["read", "list"]
}

# Voir quels environnements existent (dev/, recette/, prod/), sans rien y lire. Une LISTE vise le
# chemin AVEC la barre finale : « kv/metadata/mediagenda » (sans barre) ne servirait à rien.
path "kv/metadata/mediagenda/" {
  capabilities = ["list"]
}

path "kv/delete/mediagenda/dev/*" {
  capabilities = ["update"]
}

path "kv/undelete/mediagenda/dev/*" {
  capabilities = ["update"]
}

# Pas de kv/destroy : une destruction (irréversible) passe par l'équipe Plateforme.
path "sys/capabilities-self" {
  capabilities = ["update"]
}
