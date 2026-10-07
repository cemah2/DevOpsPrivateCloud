# Récapitulatif : `plateforme/infra` à la livraison du module 05 (M05-E46)

> Arborescence de référence en fin de module, avec l'exercice qui produit chaque fichier et son corrigé. Les fichiers complets sont dans `corrige/fichiers/M05-EXX/` ; ce récapitulatif ne les recopie pas : il dit **où** les prendre et ce que la livraison exige **en plus**. Tes noms peuvent différer : ce qui compte, c'est que chaque ligne ait son équivalent.

```
infra/
├── .gitignore                         E02  (états, plans, surcharges, *.env : jamais dans Git)
├── .pre-commit-config.yaml            E02, E20  (tofu fmt, tofu validate, tflint, terraform-docs, gitleaks)
├── .tflint.hcl                        E20  (plugin terraform, règles de nommage)
├── .terraform-docs.yml                E20
├── .checkov.yaml, .trivyignore        E25  (exceptions justifiées, une par ligne, avec ticket)
├── .gitlab-ci.yml                     E14, E26  (qualité, sécurité, plan, apply protégé, dérive planifiée)
├── CONTRIBUTING.md                    E02  (section infra : copie propre, plan relu, pas d'apply « pour voir »)
├── outils/
│   ├── s3-tester-ecriture-conditionnelle.sh   E12
│   ├── restaurer-etat.sh                      E42  (base de RB-051)
│   └── verrou-etat.sh                         E36  (« pour aller plus loin », lecture seule)
├── socle/                             état socle/terraform.tfstate
│   ├── versions.tf                    E10, E11, E27  (required_version ~> 1.13.0, bpg/proxmox ~> 0.115.0,
│   │                                                  backend "s3" use_lockfile, bloc encryption)
│   ├── providers.tf                   E03, E10  (jeton par PROXMOX_VE_*, TLS vérifié ; bloc ssh seulement
│   │                                              si des snippets sont téléversés, E19)
│   ├── variables.tf, terraform.tfvars E10  (noeud, pool, stockages, DNS, clés publiques : rien de secret)
│   ├── images.tf                      E10  (source de données gold+debian13+current, postcondition = 1)
│   ├── s3-01.tf  → module "s3_01"     E10, E17  (module vm-debian ?ref=vX.Y.Z, bloc moved, disque de
│   │                                              données hdd-bulk, prevent_destroy, protection)
│   ├── importes.tf                    E16  (adm01, dns01, git01, runner01 : ressources importées,
│   │                                         prevent_destroy, ignore_changes commentés un par un)
│   ├── imports.tf                     E16  (blocs import {} ; inertes une fois les VMs dans l'état)
│   ├── outputs.tf                     E10, E23  (adresses, VMID : sources de l'inventaire Ansible)
│   └── .terraform.lock.hcl            versionné (zh: + h1: linux_amd64)
├── envs/lab-m05/                      état envs/lab-m05/terraform.tfstate (vide à la livraison)
│   ├── versions.tf, backend.tf, providers.tf, variables.tf, locals.tf, data.tf, main.tf,
│   │   modules.tf, outputs.tf, terraform.tfvars          E03 à E08, E11, E14, E15
│   └── .terraform.lock.hcl
└── terragrunt/                        E24  (live/root.hcl, live/commun.hcl, composants/ ; selon ADR)
```

## Ce que la livraison ajoute ou vérifie

| Point | Exigence | Contrôle |
|---|---|---|
| Plan du socle | « No changes » sur `main`, en CI (dérive) et sur `adm01` | `lab/bin/check 05 46` §4 |
| `ignore_changes` | chaque attribut ignoré a un commentaire : pourquoi, et ce qui le surveille | revue (grille du corrigé) |
| Destructions | job de plan en échec si une action `delete` vise un VMID 1000-1099 | revue du pipeline |
| Apply | applique `plan.bin` du même pipeline (`tofu apply plan.bin`), `resource_group`, `interruptible: false`, environnement protégé, `main` seulement | §1 du contrôle + revue |
| Trivy | image (ou binaire) épinglé par empreinte `sha256` | §2 du contrôle |
| Modules | `?ref=vX.Y.Z` partout, aucune branche | §2 du contrôle |
| Locks | versionnés, inchangés, `zh:` présents ; plateformes de tous les postes qui lancent `tofu` | §2 du contrôle |
| État | versionné, chiffré, sans verrou oublié ; restauration testée (RB-051) | §3 du contrôle + démonstration |
| Secrets | fichiers 600 dans `~/.config/workbook/`, variables CI protégées et masquées, registre à jour, rien dans l'historique Git | §6, §7 du contrôle |

## Extrait : contrôle des destructions dans le job de plan

À ajouter au script du job `plan:socle` (E26), après `tofu plan -out=plan.bin` :

```bash
# Échec si le plan détruit (ou remplace) une VM du socle : le plan reste disponible en artefact.
tofu show -json plan.bin > plan.json
if jq -e '[.resource_changes[]
          | select(.type == "proxmox_virtual_environment_vm")
          | select(.change.actions | index("delete"))
          | select((.change.before.vm_id // 0) >= 1000 and (.change.before.vm_id // 0) <= 1099)]
         | length > 0' plan.json >/dev/null; then
  echo "Le plan détruit ou remplace une VM du socle : arrêt. Voir plan.json (artefact) et RB-050/RB-051." >&2
  exit 1
fi
rm -f plan.json   # en clair : jamais en artefact
```

## Extrait : refuser un espace de travail autre que default (socle)

```hcl
# socle/garde-fous.tf — le socle ne vit que dans l'espace default (M05-E42).
check "espace_de_travail" {
  assert {
    condition     = terraform.workspace == "default"
    error_message = "Le socle ne se gère que dans l'espace « default » (espace courant : ${terraform.workspace}). Voir RB-051."
  }
}
```

Un bloc `check` n'arrête pas le plan (avertissement) ; pour l'arrêter, mets la même condition en `precondition` dans le `lifecycle` d'une ressource du socle (par exemple celle de `s3-01`).
