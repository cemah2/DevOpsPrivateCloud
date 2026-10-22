# tofu/politiques.tf — politiques ACL (M25-E05 et E07, importées en E08).
# Une politique = un fichier politiques/<nom>.hcl, relu en MR comme du code ; le nom de la politique
# est celui du fichier. Ajouter une politique = ajouter un fichier ; la retirer = supprimer le
# fichier (le plan annonce la destruction).
resource "vault_policy" "acl" {
  for_each = fileset("${path.module}/../politiques", "*.hcl")

  name   = trimsuffix(each.value, ".hcl")
  policy = file("${path.module}/../politiques/${each.value}")
}
