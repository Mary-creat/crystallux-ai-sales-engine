"""Standardize Supabase/Claude credential references in all workflow JSON files.

Removes hardcoded credential IDs so n8n resolves credentials by name on import.
Supabase nodes are forced to httpHeaderAuth (Header Auth).
"""
import json
from pathlib import Path

CRED_MAP = {
    "Supabase Crystallux": "httpHeaderAuth",
    "Claude Anthropic":    "httpHeaderAuth",
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
        uses_supabase = any(
            isinstance(v, dict) and v.get("name") == "Supabase Crystallux"
            for v in creds.values()
        )
        if uses_supabase:
            params = node.get("parameters")
            if isinstance(params, dict) and params.get("genericAuthType") != "httpHeaderAuth" \
                    and "genericAuthType" in params:
                params["genericAuthType"] = "httpHeaderAuth"
                file_changes += 1
        new_creds = {}
        for cred_type, cred_obj in creds.items():
            if not isinstance(cred_obj, dict):
                new_creds[cred_type] = cred_obj
                continue
            name = cred_obj.get("name")
            if name in CRED_MAP:
                expected_type = CRED_MAP[name]
                new_entry = {"name": name}
                if cred_type != expected_type or cred_obj != new_entry:
                    file_changes += 1
                new_creds[expected_type] = new_entry
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
