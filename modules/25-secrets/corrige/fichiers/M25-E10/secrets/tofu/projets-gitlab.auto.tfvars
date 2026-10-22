# tofu/projets-gitlab.auto.tfvars — plateforme/secrets (M25-E10)
# Identifiants numériques des projets (pas des secrets). Relevés par :
#   admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: …" https://git01.par1.medisphere.internal/api/v4/projects/mediagenda%2Fapi | jq .id
# Remplace chaque <ID> par TA valeur.
projets_gitlab = {
  "mediagenda/api"     = 0 # <ID-MEDIAGENDA-API>
  "medidoc/medidoc"    = 0 # <ID-MEDIDOC>
  "plateforme/secrets" = 0 # <ID-PLATEFORME-SECRETS>
  "plateforme/ansible" = 0 # <ID-PLATEFORME-ANSIBLE> (M25-E11)
  "formation/ci-labo"  = 0 # <ID-CI-LABO> (essai de M25-E10, retiré ensuite)
}
