"""Update credential IDs in all workflow JSON files."""
import json
from pathlib import Path

CRED_MAP = {
    "Supabase Crystallux": {"type": "httpCustomAuth", "id": "XdqdFpzSHzWHvQIU"},
    "Claude Anthropic":    {"type": "httpHeaderAuth", "id": "5GbgZmWqc8ruTO2H"},
}

workflows_dir = Path(__file__).parent.parent / "workflows"
total_changes = 0

for wf_file in sorted(workflows_dir.glob("*.json")):
    with open(wf_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    file_changes = 0
    for node in data.get("nodes", []):
        creds = node.get("credentials")
        if not isinstance(creds, dict):
            continue
        new_creds = {}
        for cred_type, cred_obj in creds.items():
            if not isinstance(cred_obj, dict):
                new_creds[cred_type] = cred_obj
                continue
            name = cred_obj.get("name")
            if name in CRED_MAP:
                target = CRED_MAP[name]
                expected_type = target["type"]
                expected_id = target["id"]
                if cred_type != expected_type or cred_obj.get("id") != expected_id:
                    file_changes += 1
                new_creds[expected_type] = {"id": expected_id, "name": name}
            else:
                new_creds[cred_type] = cred_obj
        node["credentials"] = new_creds

    if file_changes:
        with open(wf_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"{wf_file.name}: {file_changes} credential(s) updated")
        total_changes += file_changes
    else:
        print(f"{wf_file.name}: no changes")

print(f"\nTotal credential updates: {total_changes}")
