# Tests des garde-fous (Lucas Martin, MR !214)
# « opa test rego/tofu » : tout est vert chez moi.
package main.infra

test_plan_correct {
	count(deny) == 0 with input as {"resource_changes": [{
		"type": "proxmox_virtual_environment_vm",
		"change": {"actions": ["create"], "after": {"vm_id": 2291, "pool_id": "lab", "tags": ["socle"]}},
	}]}
}
