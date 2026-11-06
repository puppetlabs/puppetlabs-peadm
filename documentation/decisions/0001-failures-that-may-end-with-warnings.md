# 0001: Which failures may end a run with warnings

* **Status:** Proposed. Needs the epic owner's sign-off (see [Sign-off](#sign-off)).
* **Ticket:** PE-47680, under epic PE-46764 ("Every run says what it's doing and what went wrong").
* **Code baseline:** `main` at `51b207e` (v3.40.0). Line numbers below are for that commit.

## Context

Epic acceptance criterion 1 says a plan never reports success on a failed operation. Today PEADM catches some failures on purpose and carries on without saying so, so a run can end in "succeeded." while something it did failed. Several tickets assume or defer one decision: when may a run that hit a failure still finish, and what does the operator see? PE-47526, PE-47530, PE-47531, PE-47532 and PE-47536 are blocked on it, and PE-47160 asks the same question for the database-node Puppet run.

This note decides that for every failure PEADM catches today (each `_catch_errors` site in `plans/` and `functions/`, each `background` block, and the failures that tasks accept on purpose), and defines what a run that ends with warnings looks like.

## Decision

### The rule

A failure that PEADM catches **fails the run**, unless this note lists it as a warning, as retried-then-fail, as informational or as a harmless probe.

A failure may end the run **with a warning** only when all three hold:

1. The operation the operator asked for completed, and the cluster is usable.
2. The failed part can be finished later without re-running the plan.
3. The warning names the cause and a concrete next action.

Otherwise it fails. An expected, explained event that needs no action (for example the extra-large installer's exit code, below) is **informational**: it prints a line but isn't a warning.

### What "success with warnings" means

* **Exit code 0.** Bolt exits 0 when a plan returns and 1 when it fails. A third exit code isn't available without failing the plan, which would make it a failure rather than a warning.
* **Opt-in failure for strict pipelines.** A new parameter `fail_on_warnings` (Boolean, default `false`) on `install`, `upgrade`, `convert`, `add_replica`, `add_compilers`, `add_database` and `migrate`. When it's `true` and the run recorded a warning, the plan fails with the same summary, so it exits 1. This is additive: no existing parameter, name or return value changes.
* **Final summary.** The end-of-run summary (PE-47530 for install, PE-47525 for upgrade, convert and add_database, PE-47678 for add_compilers and add_replica) says `RESULT: SUCCESS WITH N WARNINGS` and lists each warning: the step, the targets, the cause and the next action.
* **Result file.** In PE-47536's result file, `status` is `success_with_warnings` and each warning is an entry in `warnings[]` with `code`, `step`, `targets`, `message` and `next_action`. `code` is a stable identifier from the table below (for example `ldap_config_failed`), so pipelines can filter on it.

### Failure classes

Outcomes: **fail**; **warning**; **retried, then fail**; **informational**; **harmless probe**.

#### Failures PEADM accepts today (behaviour changes)

| # | Failure | Today | Outcome | Operator message (as it appears in run output) | Rationale | Implemented by |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | LDAP configuration fails (`plans/subplans/configure.pp:160-178`) | Two messages, then `Configuration of Puppet Enterprise <arch> succeeded.` (`:215`) | **Warning** `ldap_config_failed` | `WARN  LDAP configuration failed on <primary> (<HTTP status / RBAC kind>). PE is installed and usable. Next: configure LDAP in the console, or re-run the peadm::pe_ldap_config task with corrected settings.` | PE is installed and works; LDAP can be configured afterwards without re-running install. Failing would make the operator repeat a long install for a setting they can fix in minutes. | PE-47530 |
| 2 | The backgrounded database-node Puppet run fails or hits its 1200 s timeout (`plans/subplans/install.pp:508-510`, waited at `:530` with `_catch_errors`) | Dropped with no message. Added on purpose by PE-42079; configure re-runs Puppet on the database nodes (`configure.pp:181-188`). | **Warning** `db_node_puppet_run_failed`, or `db_node_puppet_run_timeout` | `WARN  The first Puppet run on <db host> failed (<cause>) / was still running after 20 min. The final Puppet run re-checked it and passed. Next: none needed; check the node's last Puppet report if this repeats.` If configure's final run on that node fails, the plan already fails there. | Configure's final Puppet run is the authority, and it fails the plan if the node is still broken. The earlier failure is still evidence the operator should see. This answers PE-47160: record it, don't fail on it. | PE-47530, PE-47160 |
| 3 | The extra-large installer exits non-zero while `pe-puppetserver`, `pe-orchestration-services` and `pe-console-services` are active (`tasks/pe_install.sh:65-73`) | Task exits 0 with no message | **Informational** (kept) | `INFO  The PE installer exited <code> on <primary>. This is expected on extra-large: PuppetDB can't start until its database node is installed. Continuing because pe-puppetserver, pe-orchestration-services and pe-console-services are running.` | Expected behaviour, explained, needing no action. PE-47531's health gate checks every service at the end, so a real problem is still caught. If the installer no longer exits non-zero on the PE versions PEADM supports, remove the acceptance instead (see Open questions). | PE-47526, PE-47531 |
| 4 | `puppet infrastructure upgrade` exits 11, PuppetDB sync still in progress (`tasks/puppet_infra_upgrade.rb:34-36`) | Treated as success with no message | **Warning** `puppetdb_sync_in_progress`, per node. Never a failure. | `WARN  PuppetDB sync on <node> was still running when the upgrade finished. It completes on its own. Next: run 'puppet infrastructure status --host <node>' in about 10 minutes and check that sync shows complete.` | The upgrade itself completed; the sync finishes without operator action. **Upgrade doesn't wait for it.** Adding a wait lengthens long extra-large upgrades for no correctness gain. PE-47532's health gate may poll for a short, bounded time (at most 5 minutes) before reporting this warning, if testing shows the sync usually finishes that quickly. The task must report exit 11 distinctly (for example a `puppetdb_sync` key in its output) so the plan can warn. | PE-47532 |
| 5 | `puppet infrastructure forget` fails (`plans/add_replica.pp:57`) | All errors ignored | **Harmless** when the node isn't known to PE (the usual case for a new replica); **warning** `replica_forget_failed` for any other error | `WARN  Couldn't forget the previous replica <host> (<error>). Its old certificate may not have been revoked. Next: run 'puppet infrastructure forget <host>' on the primary, then check 'puppetserver ca list --all'.` | Forgetting a node that doesn't exist must not fail the plan. Any other error means the old certificate may still be valid, which the operator needs to know, but the new replica is still provisioned. | PE-47534 |
| 6 | `submit_csr` fails (`plans/subplans/prepare_agent.pp:78`) | Error discarded ("ignoring errors to simplify logic"); `sign_csr` then fails with a less clear message, or later steps fail | **Fail** | `FAIL  Couldn't submit a certificate request from <host>: <output of puppet ssl submit_request>. Next: fix the cause on <host> (clock, DNS name, existing request on the CA), then re-run.` | The task already treats an existing signed certificate as success (`tasks/submit_csr.rb`, `puppet ssl verify`), so what's left is a real failure. Continuing only moves the error to a later, less clear step. If a pending request on the CA turns out to return non-zero, that one outcome becomes harmless (see Open questions). | PE-47527 |
| 7 | Compiler services around a new PostgreSQL node (`plans/util/init_db_server.pp:51,89,90`): stop `pe-puppetdb`; start `pe-puppetdb`; restart `pe-puppetserver` | All errors ignored | Stop: **harmless** (the service may already be stopped). Start and restart: **fail** | `FAIL  Couldn't start pe-puppetdb / restart pe-puppetserver on <compiler>: <error>. The compiler can't serve catalogs until it runs. Next: start it on <compiler> and check its log under /var/log/puppetlabs, then re-run peadm::add_database.` | A compiler without PuppetDB or a running puppetserver is degraded: agents served by it fail. That isn't "usable", so rule 1 says fail. PE-47534's health gate would catch it too, but later and with less context. | PE-47534 |

#### Retried, then fail (no change; documented)

| # | Failure | Behaviour | Code |
| --- | --- | --- | --- |
| 8 | `rbac_token` not ready after install or restore | Up to 10 attempts, 20 s apart. A permanent auth failure (kind `peadm/rbac-auth-failure`) fails at once. Fails with the last error after the attempts run out. | `plans/subplans/install.pp:450-490`, `plans/restore.pp:404-430` |
| 9 | `provision_replica` during install (`legacy => true`) | Up to 3 attempts, 15 s apart, then fails. | `plans/subplans/configure.pp:136-157` |
| 10 | `provision_replica` provision and enable in add_replica | Retries only known transient orchestrator errors, up to 3 attempts each; any other error fails at once with the task's output. | `plans/add_replica.pp:143-180`, `:206-245` |
| 11 | A new component's first Puppet run | Retries only transient 503 and connection errors, up to 3 attempts; any other error fails at once. | `plans/subplans/component_install.pp:50-78` |

#### Harmless probes and fallbacks (no change; documented)

| # | Site | Why it's harmless |
| --- | --- | --- |
| 12 | `plans/subplans/modify_certificate.pp:63`: `systemctl is-active puppet.service` | A probe. Its result only decides whether to stop and later restart the service. |
| 13 | `plans/subplans/modify_certificate.pp:72-85`: `puppetserver ca clean` | Accepts only listed outputs ("certificate revoked", "Could not find 'hostcert'", "Could not find files to clean"); anything else fails the plan. |
| 14 | `plans/util/retrieve_and_upload.pp:51`: `test -e` on the Bolt host | A probe for whether the tarball is already downloaded. |
| 15 | `plans/subplans/install.pp:581-625`: does this PE version ship `puppet_enterprise::ca_storage_import`? | A probe with explicit handling: "Could not find a plan named" means skip, with a message; any other result fails the plan. |
| 16 | `plans/restore.pp:38`: `get_peadm_config` on the target | A designed fallback: on failure it prints "Failed to get cluster configuration, loading from backup..." and uses the backup's config. Informational. |
| 17 | `plans/replace_failed_postgresql.pp:35`: `get_peadm_config` on the primary | A designed fallback when the failed host may be the primary; prints a message and continues with the parameters given. Informational. |
| 18 | `functions/warn_group_rules_overwrite.pp:11`: `get_group_rules` | Only feeds a warning about rules that will be overwritten; if it fails, it says so and continues. |

#### Background blocks (no change)

Every `background` block is awaited with a plain `wait()`, so a failure inside one fails the plan: certificate jobs in `plans/convert.pp:319-385` and `plans/convert_compiler_to_legacy.pp:108-130`, and the CSR jobs in `plans/subplans/install.pp:291-357`. The one exception is row 2.

### Effect on the health gates (PE-47531 to PE-47534)

* A service that the gate finds not running: **fail**.
* A gate probe that can't run at all (for example `puppet infrastructure status` unreachable): **warning** `health_check_inconclusive`, with the probe's error and "Next: run 'puppet infrastructure status' on the primary".

## Specs that change

* `spec/plans/subplans/configure_spec.rb:310` ("logs both messages and still succeeds (does not hard-fail) when pe_ldap_config errors"): still succeeds, but must also assert the `ldap_config_failed` warning is recorded and shown.
* `spec/unit/task/puppet_infra_upgrade_spec.rb` ("Returns when the command exits with an expected code"): exit 11 must now be reported distinctly from exit 0.
* New examples: the database-node Puppet run failing and timing out (row 2); the extra-large installer's informational line (row 3, task spec for `pe_install.sh`); `forget` failing with "not found" versus another error (row 5); `submit_csr` failing (row 6); the compiler service start and restart failing (row 7); `fail_on_warnings=true` turning a warning into a failure, for each plan that gets the parameter.
* PE-47528's allow-list of `_catch_errors` sites takes its rationale for each site from this note.

## Consequences for dependent tickets

* **PE-47526** prints row 3's informational line. Its "keep or drop" question is answered: keep, printed.
* **PE-47527** implements row 6.
* **PE-47530** implements rows 1 and 2 and the summary's warnings block for install.
* **PE-47531** keeps the extra-large acceptance and uses the health-gate outcomes above.
* **PE-47532** implements row 4. Upgrade doesn't wait; an optional poll is at most 5 minutes.
* **PE-47534** implements rows 5 and 7.
* **PE-47536** uses `success_with_warnings`, the `warnings[]` fields above and `fail_on_warnings`.
* **PE-47537 and PE-47681** take each accepted-failure scenario's expected outcome from this table.
* **PE-47160** is answered by row 2: record the failure as a warning; configure's final run stays the gate.

## Open questions

1. **Does the extra-large installer still exit non-zero on the PE versions PEADM supports?** The dev XL+DR runs (October 2026) can't show it, because `pe_install.sh` hides the code: the task reports success either way. Check the installer log under `/var/log/puppetlabs/installer` on an extra-large primary, or use PE-47526's new message once it lands. If it no longer exits non-zero, remove the acceptance (row 3).
2. **The exact output of `puppet infrastructure forget` for an unknown node** (row 5), so the "not known to PE" case can be matched reliably.
3. **Does `puppet ssl submit_request` exit non-zero when a request is already pending on the CA** (row 6)? If so, that outcome is harmless.
4. **The PuppetDB sync poll in PE-47532** (row 4): is a bounded poll worth it, and is 5 minutes the right ceiling? Decide from timings on a real extra-large upgrade.

## Sign-off

* **Epic owner (PE-46764):** pending. This changes behaviour that `configure_spec.rb:310` pins today.
* **Reviewers (owners of the dependent tickets):** PE-47526, PE-47530, PE-47531, PE-47532 and PE-47536: pending.
