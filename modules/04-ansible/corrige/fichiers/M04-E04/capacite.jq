# capacite.jq — une ligne CSV par hôte à partir des faits collectés par
#   ansible socle -m ansible.builtin.setup -a 'gather_subset=!all,!min,distribution,kernel,hardware' --tree ~/m04/e04/facts
# (M04-E04). Usage :
#   jq -r -f capacite.jq ~/m04/e04/facts/* > ~/m04/e04/capacite.csv   (puis ajouter l'en-tête)
# Dans le fichier produit par --tree, les noms de faits gardent le préfixe « ansible_ ».
.ansible_facts as $f
| [ (input_filename | sub(".*/"; "")),
    $f.ansible_distribution,
    $f.ansible_distribution_version,
    $f.ansible_kernel,
    $f.ansible_processor_vcpus,
    $f.ansible_memtotal_mb,
    ([$f.ansible_mounts[] | select(.mount == "/") | .size_available / 1073741824 | floor] | first // "?"),
    (($f.ansible_uptime_seconds // 0) / 86400 | floor)
  ]
| @csv
