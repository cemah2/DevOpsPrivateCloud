# M05-E22 — plans à relire

Six sorties de `tofu plan` (ou de `tofu show -json`) collectées dans les MR et les pipelines de
`plateforme/infra` pendant une semaine. Elles sont **raccourcies** (attributs sans intérêt
retirés, signalés par `# (N unchanged attributes hidden)` comme le fait OpenTofu) mais leur
structure est exacte. Les questions sont dans l'énoncé de M05-E22. Ne lance rien : on lit.

| Fichier | Contexte |
|---|---|
| `plan-1.txt` | MR de Lucas « ajouter le vendor-data commun aux VMs du socle », pipeline sur `socle/` |
| `plan-2.txt` | MR de Karim « s3-01 passe dans le module vm-debian v1.1.0 », `socle/` |
| `plan-3.txt` | Plan planifié du lundi matin sur `envs/lab-m05`, aucune MR fusionnée depuis vendredi |
| `plan-4.txt` | Plan de Nadia sur `envs/lab-m05` après une intervention de nuit |
| `plan-5.txt` | MR de Julien « la recette dépend de la base » sur `envs/recette-m05` |
| `plan-6.json` | Extrait de `tofu show -json plan.tfplan \| jq '[.resource_changes[] \| {address, actions: .change.actions, reason: .action_reason, importing: .change.importing, previous_address}]'` sur `socle/` |
