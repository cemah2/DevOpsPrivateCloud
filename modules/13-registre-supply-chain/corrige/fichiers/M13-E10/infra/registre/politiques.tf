# registre/politiques.tf — rétention, immuabilité, ramasse-miettes (M13-E10, PLAT-1410).

# --- Rétention de medisphere ----------------------------------------------------------------------
# Harbor GARDE un artefact dès qu'UNE règle le retient (OU logique) ; tout le reste est supprimé.
#   règle 1 : toutes les étiquettes v* (versions publiées), pour toujours ;
#   règle 2 : les 10 artefacts poussés le plus récemment de chaque dépôt (suivi main-<sha>).
# untagged_artifacts = true : les artefacts SANS étiquette entrent dans l'évaluation (et partent s'ils
# ne sont pas retenus). Les accessoires (signatures, attestations) suivent leur artefact : ils ne
# sont jamais évalués seuls, et disparaissent avec lui.
# Planification quotidienne (cron à 6 champs) : 1 h 30, avant l'analyse de 2 h 15 et loin du GC.
# ⚠️ Avant d'activer : simulation (« DRY RUN ») depuis l'IHM, journal relu (corrigé M13-E10).
resource "harbor_retention_policy" "medisphere" {
  scope    = harbor_project.projet["medisphere"].id
  schedule = "0 30 1 * * *"

  rule {
    always_retain      = true
    repo_matching      = "**"
    tag_matching       = "v*"
    untagged_artifacts = false
  }

  rule {
    most_recently_pushed = 10
    repo_matching        = "**"
    tag_matching         = "**"
    untagged_artifacts   = true
  }
}

# --- Immuabilité ------------------------------------------------------------------------------------
# Une étiquette v* ne peut plus être ni repoussée (autre contenu) ni supprimée. N'empêche pas
# d'ajouter des accessoires (signature, attestation) : ce sont des artefacts distincts, attachés à
# l'empreinte, pas des étiquettes.
resource "harbor_immutable_tag_rule" "versions" {
  for_each      = toset(["medisphere", "bibliotheque"])
  project_id    = harbor_project.projet[each.key].id
  repo_matching = "**"
  tag_matching  = "v*"
}

# --- Ramasse-miettes ---------------------------------------------------------------------------------
# Supprimer une étiquette ou un artefact ne fait que retirer des références : les BLOBS (couches)
# restent sur /data jusqu'au ramasse-miettes, qui supprime les blobs plus référencés.
# delete_untagged : les artefacts sans étiquette (anciennes cibles d'une étiquette déplacée,
# poussées par empreinte) sont supprimés aussi. Les accessoires d'un artefact étiqueté sont gardés.
# Dimanche 3 h (cron à 6 champs : s m h j mois jsem).
resource "harbor_garbage_collection" "hebdomadaire" {
  schedule        = "0 0 3 * * 0"
  delete_untagged = true
  workers         = 1
}
