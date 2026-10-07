# .tflint.hcl — règles de qualité des modules de plateforme/tofu-modules (M05-E20).
# Lancement depuis la racine du dépôt :  tflint --init && tflint --recursive
# --recursive : chaque module (vm-debian/…) et chaque exemple est analysé à part.

config {
  # Analyser aussi les appels de modules (sources locales ET téléchargées par tofu init) :
  # une variable mal passée à vm-debian est vue ici, pas à l'apply.
  call_module_type = "all"
}

# Jeu de règles du langage, livré avec tflint. Préréglage « recommended », complété.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Conventions de l'équipe (CONTRIBUTING.md) ----------------------------------------------

# Noms en snake_case : ressources, variables, sorties, modules, locals.
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Toute variable et toute sortie a une description (reprise par terraform-docs).
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# Toute variable a un type.
rule "terraform_typed_variables" {
  enabled = true
}

# Versions toujours contraintes : OpenTofu et chaque provider.
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

# Sources de modules épinglées : jamais une branche, toujours une étiquette (?ref=vX.Y.Z).
rule "terraform_module_pinned_source" {
  enabled = true
  style   = "semver"
}

# Pas de variable, local ou source de données déclarés et jamais utilisés.
rule "terraform_unused_declarations" {
  enabled = true
}

# Une seule façon d'écrire les commentaires (#).
rule "terraform_comment_syntax" {
  enabled = true
}

# Un module réutilisable suit la structure standard : main.tf, variables.tf, outputs.tf,
# versions.tf, README.md. Les consommateurs savent où chercher.
rule "terraform_standard_module_structure" {
  enabled = true
}
