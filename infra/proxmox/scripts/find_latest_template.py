#!/usr/bin/env python3
"""
Terraform `external` data source helper: finds the newest Proxmox VM
template matching a name prefix.

WHY THIS SCRIPT EXISTS:
Unlike AWS's `data "aws_ami"` (which has a native `most_recent = true` +
name-filter capability), the bpg/proxmox Terraform provider has no built-in
"give me the newest template matching this name pattern" data source. This
script replicates that lookup by calling the Proxmox API directly and
sorting matching templates by name (which works because our naming
convention embeds an ISO8601-like timestamp, so lexicographic sort ==
chronological sort).

Called via Terraform's `data "external"` block in main.tf. Must print a
flat JSON object of string values to stdout, per the external provider's
contract.

Requires: pip install requests
Environment variables expected: PROXMOX_API_URL, PROXMOX_API_TOKEN,
  PROXMOX_NODE, PROXMOX_TEMPLATE_PREFIX
"""
import json
import os
import sys

import requests


def main():
    api_url = os.environ["PROXMOX_API_URL"].rstrip("/")
    token = os.environ["PROXMOX_API_TOKEN"]  # format: "user@realm!tokenid=secret"
    node = os.environ["PROXMOX_NODE"]
    prefix = os.environ["PROXMOX_TEMPLATE_PREFIX"]

    headers = {"Authorization": f"PVEAPIToken={token}"}
    resp = requests.get(
        f"{api_url}/nodes/{node}/qemu",
        headers=headers,
        verify=False,  # homelab self-signed cert; use a real cert + verify=True beyond a lab
        timeout=15,
    )
    resp.raise_for_status()
    vms = resp.json()["data"]

    templates = [v for v in vms if v.get("template") == 1 and v.get("name", "").startswith(prefix)]
    if not templates:
        print(json.dumps({"error": f"no templates found matching prefix {prefix}"}), file=sys.stderr)
        sys.exit(1)

    newest = sorted(templates, key=lambda v: v["name"])[-1]

    print(json.dumps({"vmid": str(newest["vmid"]), "name": newest["name"]}))


if __name__ == "__main__":
    main()
