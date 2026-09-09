# Packer, Explained (and a real debugging session)

Personal notes from building the first hardened image against the Proxmox
target, 2026-09-03/04. Written to actually understand *why* Packer behaves
the way it does, not just which commands to type.

## What Packer is

Packer does one job: **boot a temporary machine, run setup on it, capture
the result as a reusable image, then discard the temporary machine.**
That's the whole tool. It has no concept of ongoing infrastructure state —
unlike Terraform, which tracks and manages long-lived resources, Packer
builds once and hands you an artifact. Terraform then consumes that
artifact later, as a completely separate step run by a completely separate
tool. The two never talk to each other directly — see the main how-to
doc's "mental model" section for why that separation is deliberate.

If you've worked anywhere that talks about "baking golden AMIs" (AWS) or
using Azure VM Image Builder — this is the same pattern. Packer is just the
vendor-neutral tool HashiCorp built to do it against any cloud or
hypervisor with one config language, Proxmox included.

**Vs. Docker, since that's the other half of this project:** a `Dockerfile`
bakes a *container* image — layered, single-process, ephemeral. A
`.pkr.hcl` file bakes a *whole machine* image — a full OS disk meant to be
booted as a VM. Same underlying idea (repeatable, versioned artifact built
from declarative instructions), different layer of the stack. This
pipeline uses both for exactly that reason: Packer bakes the hardened OS
the Kubernetes node boots from; Docker later bakes the app that runs *on
top of* that node.

## The four building blocks

- **`packer { required_plugins {...} }`** — a manifest, not logic. Declares
  which plugins this build needs (e.g. `proxmox`, `ansible`).
  `packer init` reads this and downloads the actual plugin binaries into
  `~/.config/packer/plugins/`.
- **`source`** — how to obtain a machine to work on. Ours: clone an
  existing Proxmox template (`clone_vm_id`).
- **`provisioner`** — what to run on that machine once it's up. Ours: the
  `ansible` provisioner, which shells out to a real, separately-installed
  `ansible-playbook` binary.
- **`build`** — glues one `source` to one or more `provisioner`s (run in
  the order listed), plus a finalize step — here, converting the finished
  VM into a new template.

Packer's own core doesn't know how to talk to Proxmox or run Ansible —
that logic lives entirely in the plugins, which Packer core loads and
talks to over an internal RPC protocol (same architecture as Terraform
providers). Core just orchestrates: get a machine from the source plugin →
run each provisioner against it in order → let the source plugin finalize
it.

## Execution order of `packer build`

1. Parse every `*.pkr.hcl` file in the directory (not just the one you
   named — Packer loads the whole folder as one template), resolve
   `-var-file` values.
2. Hand the `source` block's config to its plugin. The plugin does the
   real work — for `proxmox-clone`, that means calling the Proxmox API to
   clone the base VM, boot it, and establish an SSH connection.
3. Once the source plugin reports a live, reachable machine, run each
   `provisioner` against it in order, over that connection.
4. Once provisioners finish successfully, the source plugin's finalize
   step runs — for us, converting the VM into a new template.
5. Any `post-processor` blocks run last (ours just echoes a confirmation
   line locally).

Nothing touches real infrastructure until `packer build` — `init` only
fetches plugins, `validate` only checks syntax.

## Tonight's build, as a case study

| Symptom | Real cause |
|---|---|
| `Unknown provisioner type "ansible"` | `required_plugins` never listed `ansible`, so `packer init` never fetched that plugin. Packer recognized the word in the config but had no plugin registered to execute it. **Fix:** add the `ansible` block to `required_plugins`, re-run `packer init`. |
| `Waiting for SSH...` → `Timeout waiting for SSH` after 10 minutes | The VM itself was completely healthy the whole time — cloud-init finished, sshd was listening. Packer simply had no way to *learn the VM's IP*. Without the QEMU Guest Agent, Proxmox can't report a DHCP-assigned address back through its API, so Packer polls forever with nothing to poll against. **Fix:** `qemu_agent = true` in the source block, plus actually getting the agent running in the guest (see below). |
| `qm agent 102 ping` → `QEMU guest agent is not running` | Direct confirmation of the above from the Proxmox side — the config-level flag (`--agent enabled=1`) just tells Proxmox to *expect* an agent; nothing was actually listening on the guest end because Ubuntu's cloud image doesn't ship it pre-installed. **Fix:** manually boot the base template once, install `qemu-guest-agent`, re-template. |
| `The device is not writable: Permission denied` on `base-9000-disk-0` | Not a Packer issue — this happened while manually trying to boot the *template* to fix the agent problem. `qm template` doesn't just set a config flag; on LVM storage it renames the disk (`vm-9000-disk-0` → `base-9000-disk-0`) and marks the logical volume **read-only**, so nothing can silently corrupt a golden image. **Fix:** `lvchange -prw` to explicitly unlock the LV before booting; `qm template` re-locks it automatically when re-run. |
| Final successful run: 1m20s | Fast because the base template already had current packages and the guest agent installed by that point — Ansible had comparatively little left to do. |

**The throughline:** every failure was Packer (or Proxmox) correctly
refusing to guess. No plugin declared → refuses to run an unknown
provisioner. No IP discoverable → refuses to assume one and just times
out rather than silently doing nothing. Template disk locked → refuses to
let anything overwrite a "finished" image without an explicit unlock.
That strictness is the actual point — it's what makes the resulting
template trustworthy enough for Terraform to clone from later without
either tool needing to double-check the other's work.

## State as of the first session (2026-09-03/04)

- Base template **VMID 9000** (`ubuntu-2404-cloudinit-base`) now has
  `qemu-guest-agent` installed and enabled — baked in permanently, so
  every future build inherits it.
- First hardened image successfully built: **VMID 102**,
  `homelab-hardened-ubuntu-24-04-2026-09-04T0309`.
- Next step: `terraform apply` in `infra/proxmox` (Phase 4) — not yet run.

## Round two (2026-09-07/08): rebuilding the image, and a long detour

Phase 4 ran successfully — Terraform found template 102, cloned it,
installed k3s, and produced a genuinely working cluster. But it surfaced
two real problems worth fixing at the source rather than patching around:
the node had no way to log in (fixed — see `infra/proxmox/main.tf`'s
`user_account` block) and its disk was far too small (template 9000's
disk was resized 2.4GB → ~23.5GB; see the LVM read-only-volume note
above for why that needs `lvchange -prw` first).

Rebuilding the image to pick up that bigger disk turned into the longest
single debugging thread of the project so far. In order, each one a real
bug, each one fixed before moving to the next:

1. **Wrong SSH user in Ansible's generated inventory.** The `ansible`
   provisioner's proxy-adapter mode generated an inventory with
   `ansible_user=<local WSL username>` instead of `ubuntu` — confirmed by
   intercepting the temp inventory file before Packer's cleanup deleted
   it. Every remote path Ansible tried to build was wrong as a result,
   surfacing as a confusing "No space left on device" on a tiny `mkdir`
   rather than a clear auth error. Fix: explicit `user = "ubuntu"` on the
   provisioner (packer-plugin-ansible doesn't reliably infer this from
   `ssh_username` alone).
2. **A real "no space" after that** — this one genuinely was disk space,
   from before the resize took effect on a given clone.
3. **A race between "SSH is up" and cloud-init actually finishing** —
   `growpart`/`resizefs` can still be running in the background at the
   exact moment Packer's communicator considers the VM "ready." Confirmed
   by watching a clone's `df -h` show the old, pre-resize size the moment
   Ansible's first task ran.
4. **A red herring inside the fix for #3**: `cloud-init status --wait`
   reports exit code `2` ("degraded done"), not `0`, on this VM — caused
   by Proxmox's own built-in cloud-init integration using an old,
   deprecated single-`user` config syntax to inject Packer's ephemeral
   SSH key (nothing in this repo's own config). Confirmed via
   `qm guest exec <vmid> -- cloud-init status --long` showing a genuinely
   clean `status: done` alongside that one benign deprecation notice.
5. **The real, underlying bug**: even after all of the above, a
   standalone `shell` provisioner running a trivial `echo` / `sleep 3` /
   `echo` script — nothing to do with cloud-init at all — hung
   indefinitely and failed identically ("Error uploading script: Process
   exited with status 1", consistently around 5.5 minutes). That proved
   the problem was never cloud-init, exit codes, or wait logic — Packer's
   own native file-upload mechanism cannot reliably talk to this VM.
   Forcing `ssh_file_transfer_method = "sftp"` (vs. the default SCP) was
   tried and didn't resolve it either.

**The actual fix**: notice that the `ansible` provisioner — which
connects through its own proxy adapter, not Packer's native
communicator — worked reliably through all of this, including
successfully writing and executing a full playbook run in step 1's
investigation. So the cloud-init-readiness wait was moved **out of a
standalone Packer `shell` provisioner and into a `pre_tasks` entry inside
`hardening.yml` itself**, running through Ansible's own (proven-reliable)
connection instead of Packer's native one. The underlying cause of *why*
Packer's own file-upload mechanism specifically hangs against this VM is
still unconfirmed — worth a dedicated look at Packer's GitHub issues if
it resurfaces elsewhere — but routing around it entirely was the
pragmatic fix once the pattern (ansible-path reliable, native-path not)
was clear.

**Lesson worth keeping**: when a supposedly-fixed thing keeps failing in
new ways after several real, independently-verified fixes, it's worth
stepping back and asking "which of my two *tools*, not which of my
*configs*, might be the actual variable" — the breakthrough here came
from comparing two different connection mechanisms against each other,
not from another guess at what the failing one's config should be.

## Round three (2026-09-08/09): the disk was non-deterministic

Moving the wait into Ansible fixed the connection hang, but a *new*
symptom appeared: `gather_facts` (needing its own remote temp directory)
kept hitting "No space left on device" — even after confirming, via
direct `qm guest exec` checks, that the disk really had been resized to
~23.5G at the Proxmox/LVM level. Chased through several more layers:

6. **Ansible's automatic fact-gathering runs before `pre_tasks`** by
   default — it was racing growpart, same shape as bug #3 but one level
   earlier in the play. Fixed with `gather_facts: false` plus an explicit
   `ansible.builtin.setup` task placed *after* the wait.
7. **Normal Ansible modules stage into a remote temp dir before running**
   — which was itself failing with ENOSPC before growpart had freed any
   room, a chicken-and-egg the wait task was supposed to avoid. Fixed by
   using `ansible.builtin.raw` (no staging at all) for anything that runs
   before disk space is confirmed.
8. **cloud-init reporting done ≠ growpart actually finished.** Confirmed
   directly: a task requiring real free space still failed immediately
   after the wait task reported success. Stopped trusting cloud-init's
   status as a proxy entirely and polled real `df` output instead —
   which *also* never saw space appear within a generous bound.
9. **The actual disk was never being grown at all, on some runs.** A
   direct side-by-side comparison was the key move here: Proxmox's own
   native `qm clone --full 1` against template 9000 correctly produced a
   ~23.5G disk every time; Packer's `proxmox-clone` builder, cloning the
   *same* source with identical settings, sometimes produced ~23.5G and
   sometimes ~3.5G — same config, different result, run back to back.
   That ruled out every config-level explanation at once: it was a race
   condition in the clone operation itself (almost certainly the VM
   starting before the background clone/resize task had genuinely
   finished copying data), not anything `hardening.yml` or `.pkr.hcl`
   controlled directly.
10. A `disks {}` block was tried as a way to declare the target size
    explicitly rather than trust inheritance — it didn't fix the
    non-determinism and just left an unwanted, unformatted second disk
    on every template, so it was removed again once the real fix landed.

**The actual fix**: template 9000 itself had been unlocked and resized
*after the fact*, twice, by that point (once for the guest agent, once
for the original disk-size bump) — each time via unlock → `lvchange
-prw` → `qm resize` → re-lock. Rebuilt the base template completely from
scratch instead: destroy, recreate, resize **before** ever running `qm
template`, single clean pass, no unlock/re-lock history behind it at
all. The very next Packer build produced a correctly, consistently sized
clone. Whether the volume's resize *history* was the actual mechanism
(vs. coincidence) was never confirmed with certainty — but the fix
landed and held.

One more small bug surfaced during the same round: the cloud-init wait's
`until`/`retries` loop correctly recognized cloud-init was done (by
content), but the `raw` module still separately failed the *task* on
cloud-init's own "degraded" exit code (2) — `until` only controls when
to stop retrying, it doesn't override the module's own pass/fail check.
Needed an explicit `failed_when: false` alongside it.

**Lesson worth keeping, again**: after enough config-level fixes that
each turn out to be real but insufficient, it's worth testing the *same
operation two different ways* (here: Packer's clone vs. Proxmox's own
native clone, against the identical source) rather than continuing to
adjust the failing path's settings. That comparison is what turned "this
config must be subtly wrong" into "this specific operation is racy," and
it also caught the disks{} block having zero real effect — evidence a
plain pass/fail status would never have shown.

## Final state (2026-09-09)

Base template **VMID 9000** rebuilt clean (no resize-after-templating
history), guest agent installed, disk correctly sized at ~25.5G from a
single pass. First fully clean build against it: **VMID 104**,
`homelab-hardened-ubuntu-24-04-2026-09-09T0029` — full Ansible run,
`ok=23 changed=13 failed=0`, disk healthy with 22G free throughout. This
closes out Phase 2 for real. Next: `terraform apply -replace` in
`infra/proxmox` to move the k3s node onto this image.
