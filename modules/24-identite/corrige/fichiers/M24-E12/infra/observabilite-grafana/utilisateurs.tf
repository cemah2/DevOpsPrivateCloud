# plateforme/infra/observabilite-grafana/utilisateurs.tf — M24-E12 (DEV-2512).
#
# Depuis le SSO, un compte Grafana n'existe qu'APRÈS la première connexion de la personne (allow_sign_up
# de generic_oauth) : les comptes locaux du M21 sont supprimés. Or grafana_team refuse un membre qui
# n'existe pas (l'apply échoue). On ne garde donc, dans chaque équipe, que les membres DÉCLARÉS qui
# EXISTENT déjà ; une personne qui se connecte pour la première fois entre dans son équipe au plan
# suivant (contrôle de dérive nocturne, ou prochaine MR). Le plan affiche alors un ajout : normal.
#
# grafana_users lit les API d'administration du SERVEUR : jetons de compte de service refusés, d'où le
# fournisseur admin_serveur (authentification basique d'« admin », M22-E16).
data "grafana_users" "tous" {
  provider = grafana.admin_serveur
}

locals {
  # Adresses de courriel des comptes existants, en minuscules (Grafana compare sans casse).
  adresses_existantes = toset([for u in data.grafana_users.tous.users : lower(u.email)])

  equipes_effectives = {
    for nom, e in var.equipes : nom => {
      titre_dossier = e.titre_dossier
      membres       = [for m in e.membres : m if contains(local.adresses_existantes, lower(m))]
      admins        = [for m in e.admins : m if contains(local.adresses_existantes, lower(m))]
      absents       = [for m in concat(e.membres, e.admins) : m if !contains(local.adresses_existantes, lower(m))]
    }
  }
}

# Lu en revue de plan : qui n'est pas encore dans son équipe faute de s'être connecté.
output "membres_pas_encore_connectes" {
  value = { for nom, e in local.equipes_effectives : nom => e.absents if length(e.absents) > 0 }
}
