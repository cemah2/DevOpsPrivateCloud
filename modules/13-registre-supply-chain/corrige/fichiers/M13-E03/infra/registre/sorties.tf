# registre/sorties.tf — M13-E03. Sorties SENSIBLES : jamais affichées par plan/apply ; lues par
# outils/publier-secrets-registre.sh sur adm01 (tofu output -json), qui écrit les fichiers 600 de
# ~/.config/workbook/ et les variables de CI. L'état est chiffré (chiffrement.tf).

output "robots" {
  description = "Nom complet et secret de chaque robot."
  sensitive   = true
  value = merge(
    { for p, r in harbor_robot_account.ci : "${p}-ci" => { utilisateur = r.full_name, secret = r.secret } },
    {
      "k8s-pull"  = { utilisateur = harbor_robot_account.k8s_pull.full_name, secret = harbor_robot_account.k8s_pull.secret }
      "wb-checks" = { utilisateur = harbor_robot_account.wb_checks.full_name, secret = harbor_robot_account.wb_checks.secret }
    },
  )
}

output "mots_de_passe_initiaux" {
  description = "Mots de passe initiaux des comptes humains (à transmettre, puis changés)."
  sensitive   = true
  value       = { for u, p in random_password.personne : u => p.result }
}

output "robots_noms" {
  description = "Noms complets des robots (non sensible)."
  value = concat(
    [for r in harbor_robot_account.ci : r.full_name],
    [harbor_robot_account.k8s_pull.full_name, harbor_robot_account.wb_checks.full_name],
  )
}
