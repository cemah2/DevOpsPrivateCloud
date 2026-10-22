# observabilite-grafana/sorties.tf — M21-E17.

output "dossiers" {
  description = "UID et titre des dossiers (repris par les checks et les liens des runbooks)."
  value       = { for k, d in grafana_folder.equipe : k => d.title }
}

output "equipes" {
  description = "Identifiants des équipes Grafana."
  value       = { for k, t in grafana_team.equipe : k => t.team_id }
}
