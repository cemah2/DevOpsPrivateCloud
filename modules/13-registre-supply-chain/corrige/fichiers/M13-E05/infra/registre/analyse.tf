# registre/analyse.tf — analyse de vulnérabilités dans Harbor (M13-E05, SEC-1405).
# Analyseur par défaut : l'adaptateur Trivy installé par « install.sh --with-trivy » (nom « Trivy »).
# Analyse planifiée de TOUT le registre chaque nuit (les CVE apparaissent après la poussée : une
# image saine lundi peut être critique jeudi). Format cron à 6 champs (secondes) : 2 h 15 chaque nuit.
# L'analyse à la poussée est une propriété de chaque projet (vulnerability_scanning, projets.tf).
resource "harbor_interrogation_services" "analyse" {
  default_scanner           = "Trivy"
  vulnerability_scan_policy = "0 15 2 * * *"
}
