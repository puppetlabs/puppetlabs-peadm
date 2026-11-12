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
* **Opt-in failure for strict pipelines.** A new parameter `fail_on_warnings` (Boolean, default `false`) on the plans that have a warning source today: `install` (rows 1 and 2), `upgrade` (row 4) and `add_replica` (row 5). When it's `true` and the run recorded a warning, the plan fails with the error kind `peadm/run-had-warnings`, the same summary as its message, and the warnings in its `details`, so it exits 1 and a pipeline can tell it from a real failure. A plan gets the parameter in the same change that gives it its first warning source; a parameter that can never fire would only mislead. This is additive: no existing parameter, name or return value changes.
* **Final summary.** The end-of-run summary (PE-47530 for install, PE-47525 for upgrade, convert and add_database, PE-47678 for add_compilers and add_replica) has a result line followed by each warning: the step, the targets, the cause and the next action. This note uses `RESULT: SUCCESS WITH N WARNINGS`; the PE-ADM journey map shows `Result: VERIFIED WITH 1 WARNING`. The wording is agreed with design in PE-47530 and doesn't affect anything else here: the warning codes, the result file's fields and the exit codes stay as below.
* **Result file.** In PE-47536's result file, `status` is `success_with_warnings` and each warning is an entry in `warnings[]` with `code`, `step`, `targets`, `message` and `next_action`. `code` is a stable identifier from the table below (for example `ldap_config_failed`), so pipelines can filter on it. A pipeline that checks `status == "success"` treats `success_with_warnings` as a failure; it should check the exit code, or accept both values. Nothing reads this file yet (PE-47536 hasn't shipped), so no existing pipeline breaks.

### Where warnings are recorded

A warning is recorded where the failure is caught, but it's printed in the end-of-run summary, so it has to reach the top-level plan. Bolt plans share no mutable state, so each subplan returns its warnings in its result and its caller adds them to its own. The shape of that record (and of the run ID and log path that go with it) belongs to PE-47519's shared run record; this note only requires that every warning carries `code`, `step`, `targets`, `message` and `next_action`, and that none is dropped on the way up.

Some messages can only be finished at summary time. Row 2's "The final Puppet run re-checked it and passed" is known only after configure's final Puppet run, so `subplans::install` returns the failure and the top-level `install` plan writes the message once configure has finished.

### Failure classes

Outcomes: **fail**; **warning**; **retried, then fail**; **informational**; **harmless probe**. Rows keep their numbers because tickets cite them, so a row added later (row 19) can appear out of order.

#### Failures PEADM accepts today (behaviour changes)

| # | Failure | Today | Outcome | Operator message (as it appears in run output) | Rationale | Implemented by |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | LDAP configuration fails (`plans/subplans/configure.pp:160-178`) | Two messages, then `Configuration of Puppet Enterprise <arch> succeeded.` (`:215`) | **Warning** `ldap_config_failed` | `WARN  LDAP configuration failed on <primary> (<HTTP status / RBAC kind>). PE is installed and usable; LDAP users can't log in until this is fixed. Next: configure LDAP in the console (Access control > LDAP), or re-run the peadm::pe_ldap_config task with corrected settings.` | The operator did pass `ldap_config`, so this is part of what they asked for. It still meets the three conditions: the install itself completed, PE is usable through the console admin account, and LDAP is a setting applied through the RBAC API after install, so it can be finished in minutes without re-running a long install. A pipeline that needs LDAP to be in place sets `fail_on_warnings`. Re-running the task is safe after a failure: checked on PE 2025.12.1 (2026-11-12), `rbac-api/v1/command/ldap/create` rejects a bad config with HTTP 400 and creates nothing. It isn't safe after a success: `create` doesn't test the connection and each successful call adds another LDAP config (two calls gave two IDs), so the message suggests a re-run only for this failure. | PE-47530 |
| 2 | The backgrounded database-node Puppet run fails or hits its 1200 s timeout (`plans/subplans/install.pp:508-510`, waited at `:530` with `_catch_errors`) | Dropped with no message. Added on purpose by PE-42079; configure re-runs Puppet on the database nodes (`configure.pp:181-188`). | **Warning** `db_node_puppet_run_failed`, or `db_node_puppet_run_timeout` | `WARN  The first Puppet run on <db host> failed (<cause>) / was still running after 20 min. The final Puppet run re-checked it and passed. Next: none needed; check the node's last Puppet report if this repeats.` If configure's final run on that node fails, the plan already fails there. | Configure's final Puppet run is the authority, and it fails the plan if the node is still broken. The earlier failure is still evidence the operator should see. This answers PE-47160: record it, don't fail on it. **Timeout case:** `wait()` stops waiting after 1200 s but doesn't stop the agent run, so it can still hold the agent lock when configure's final run starts. `puppet_runonce` waits for the lock for `in_progress_timeout` (default 600 s), then starts `puppet agent --onetime` anyway, which exits 1 because a run is already in progress, and the plan fails with a cause that doesn't mention the first run. So configure's final run passes a longer `in_progress_timeout` (1800 s); if the lock is still held after that, the plan fails with `FAIL  The first Puppet run on <db host> was still running after <n> min. Next: check the run on <db host> (/var/log/puppetlabs/puppet), wait for it to finish, then re-run.` | PE-47530, PE-47160 |
| 3 | The extra-large installer exits non-zero while `pe-puppetserver`, `pe-orchestration-services` and `pe-console-services` are active (`tasks/pe_install.sh:65-73`) | Task exits 0 with no message | **Informational** (kept) | `INFO  The PE installer exited <code> on <primary>. This is expected on extra-large: PuppetDB can't start until its database node is installed. Continuing because pe-puppetserver, pe-orchestration-services and pe-console-services are running.` | Expected behaviour, explained, needing no action. PE-47531's health gate checks every service at the end, so a real problem is still caught. Verified on PE 2025.12.1 (2026-11-09): the extra-large primary's installer still fails (its log ends `install_fail_type - exit_code_not_0_or_2` after `Systemd start for pe-puppetdb failed!`), and the install completes once the database node is installed, so the acceptance stays. | PE-47526, PE-47531 |
| 4 | `puppet infrastructure upgrade` exits 11 (`tasks/puppet_infra_upgrade.rb:34-36`) | Treated as success with no message | **Warning** `puppetdb_sync_in_progress`, if it ever happens. Never a failure. | `WARN  PuppetDB sync on <node> was still running when the upgrade finished. It completes on its own. Next: run 'puppet infrastructure status --host <node>' and check that PuppetDB shows a last successful sync.` | The outcome is the same for every PE version: if exit 11 happens, the upgrade the operator asked for has finished and only PuppetDB's sync is still catching up, which completes on its own (rule 1), and the message says how to check it (rule 3). What depends on the version is only whether it can happen. The exit-11 case was added in 2020 (`15ff356`) when `upgrade replica` waited up to 15 minutes for PuppetDB sync and exited 11 on timeout. Exit 11 comes from the *target* version's `puppet infrastructure upgrade`, and PEADM supports upgrades to 2019.7 through 2026.0 (`functions/assert_supported_pe_version.pp`), so older targets such as 2023.8 LTS may still return it; that hasn't been checked. On PE 2025.12.1 it can't happen: `upgrade replica` runs the orchestrator plan `enterprise_tasks::upgrade_secondary` and maps its state to exit 0 or 1 only (`pe_manager` `plan_executor.rb`), and PE's only `exit(11)` is in `provision replica` (`provision/streaming.rb`, see below). Verified on a 2025.12.0 → 2025.12.1 upgrade with a replica (2026-11-11): the replica step took 820 s, exited 0 ("Replica upgrade complete.") and the replica's PuppetDB reported a successful sync straight afterwards. Keep accepting 11 for older targets, as a warning rather than silent success. **No wait and no poll** in upgrade, for any version: on 2025.12 and later there is nothing to wait for, and on older targets PE has already waited up to 15 minutes before exiting 11, while the sync finishes without PEADM. | PE-47532 |
| 5 | `puppet infrastructure forget` fails (`plans/add_replica.pp:57`) | All errors ignored | **Warning** `replica_forget_failed` for any non-zero exit. A node PE doesn't know is not an error: `forget` exits 0 for it, so no output matching is needed | `WARN  Couldn't forget the previous replica <host> (<error>). Its old certificate may not have been revoked. Next: run 'puppet infrastructure forget <host>' on the primary, then check 'puppetserver ca list --all'.` | Forgetting a node that doesn't exist must not fail the plan, and it doesn't: verified on PE 2025.12.1 with Code Manager on (2026-11-10), `forget` of an unknown certname prints `Could not find files to clean`, reports the node removed as an active replica, runs Puppet on the primary and replica, and exits 0. A non-zero exit therefore means the old certificate may still be valid, which the operator needs to know, but the new replica is still provisioned. | PE-47534 |
| 6 | `submit_csr` fails (`plans/subplans/prepare_agent.pp:78`) | Error discarded ("ignoring errors to simplify logic"); `sign_csr` then fails with a less clear message, or later steps fail | **Harmless** when this agent's own request is already pending on the CA: the `submit_csr` task detects that itself and exits 0, so the plan stops ignoring the task's errors and matches no output. **Fail** for any other error, including a pending request made with a different key | `FAIL  Couldn't submit a certificate request from <host>: <output of puppet ssl submit_request>. Next: fix the cause on <host> (clock, DNS name, existing request on the CA), then re-run.` For a different key: `FAIL  A different certificate request for <certname> is already pending on the CA. Next: run 'puppetserver ca clean --certname <certname>' on the primary, then re-run.` | The task already treats an existing signed certificate as success (`tasks/submit_csr.rb`, `puppet ssl verify`). A pending request is the expected case when the agent install already submitted one: verified on PE 2025.12.1 (2026-11-09), a second `submit_request` for a pending certname exits 1 with `Could not submit certificate request for '<certname>' … due to a conflict on the server`. The task shouldn't rely on that English text (row 5 avoids output matching for the same reason). Instead, before submitting, it asks the CA: `GET /puppet-ca/v1/certificate_request/<certname>` needs no client certificate (default `auth.conf` rule "puppetlabs csr") and returns 200 with the request while one is pending, and 404 otherwise, including once it's signed (checked on PE 2025.12.1, 2026-11-12). If the pending request's public key matches the agent's key, the task exits 0 and `sign_csr` signs it; if it doesn't, signing it would give the agent a certificate it can't use, so the task fails. Any other error is a real failure, and continuing only moves it to a later, less clear step. | PE-47527 |
| 7 | Compiler services while `peadm::util::init_db_server` rebuilds a database node (`plans/util/init_db_server.pp:51,89,90`): stop `pe-puppetdb`; start `pe-puppetdb`; restart `pe-puppetserver`. No plan calls `init_db_server`; operators run it by hand in the extra-large database recovery flow (`documentation/backup_restore.md`, "Recovering a non-operational database server") | All errors ignored | Stop: **harmless** (the service may already be stopped). Start and restart: **fail** | `FAIL  Couldn't start pe-puppetdb / restart pe-puppetserver on <compiler>: <error>. The compiler can't serve catalogs until it runs. Next: start it on <compiler> and check its log under /var/log/puppetlabs, then continue with the next step of the database recovery in documentation/backup_restore.md.` The message must not suggest `peadm::add_database`: re-running it on an existing database node can wipe the only `pe-puppetdb` copy (PE-47812). | A compiler without PuppetDB or a running puppetserver is degraded: agents served by it fail. That isn't "usable", so rule 1 says fail. | Follow-up ticket to be filed (no existing ticket covers `init_db_server`) |
| 19 | The `code_manager` task's HTTP calls fail (`tasks/code_manager.sh:154-165`): `curl_wrapper` saves curl's exit code but doesn't return it, curl runs without `--fail`, and nothing checks the HTTP status. Used for `file-sync commit` during install (`plans/subplans/install.pp:504`) and `deploy` in configure (`plans/subplans/configure.pp:192`) | Task exits 0 whatever happens | **Fail** | `FAIL  Code Manager '<action>' failed on <primary>: <curl error, or HTTP status and response body>. Next: check file sync and Code Manager in /var/log/puppetlabs/puppetserver/puppetserver.log on <primary>, fix the cause, then re-run.` | Not caught on purpose: the task can't report a failure at all, so the plan never sees one. Install needs the file-sync commit to set up replication, and a deploy is what the operator asked for, so neither can pass rule 1. Listed here so the "fails unless listed" rule visibly covers it. | PE-47521 |

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
* A gate probe that can't run at all (for example `puppet infrastructure status` unreachable), after the gate's own retries: **fail** with the kind `peadm/health-check-inconclusive`, the probe's error, and "The operation finished, but PEADM couldn't confirm the cluster is healthy. Next: run 'puppet infrastructure status' on the primary; if every service is running, nothing needs re-running." If nobody has shown the cluster is usable, rule 1 isn't met, so this can't be a warning.

## Specs that change

* `spec/plans/subplans/configure_spec.rb:310` ("logs both messages and still succeeds (does not hard-fail) when pe_ldap_config errors"): still succeeds, but must also assert the `ldap_config_failed` warning is recorded and shown.
* `spec/unit/task/puppet_infra_upgrade_spec.rb` ("Returns when the command exits with an expected code"): exit 11 must now be reported distinctly from exit 0.
* New examples: the database-node Puppet run failing and timing out, including a first run still holding the agent lock when configure's final run starts (row 2); the extra-large installer's informational line (row 3, task spec for `pe_install.sh`); `forget` exiting 0 versus non-zero (row 5); `submit_csr` with this agent's request pending, with a different key's request pending, and failing for another reason (row 6); the compiler service start and restart failing (row 7); the `code_manager` task failing on a curl error and on an HTTP error (row 19, task spec for `code_manager.sh`); a health-gate probe that can't run; `fail_on_warnings=true` turning a warning into a `peadm/run-had-warnings` failure, for each plan that gets the parameter.
* PE-47528's allow-list of `_catch_errors` sites takes its rationale for each site from this note.

## Consequences for dependent tickets

* **PE-47519** defines the shared run record that carries warnings up to the summary (see [Where warnings are recorded](#where-warnings-are-recorded)).
* **PE-47521** implements row 19.
* **PE-47526** prints row 3's informational line. Its "keep or drop" question is answered: keep, printed.
* **PE-47527** implements row 6, including the pending-request check in the `submit_csr` task.
* **PE-47530** implements rows 1 and 2, the longer lock wait in configure's final run, and the summary's warnings block for install. It also agrees the result line's wording with design.
* **PE-47531** keeps the extra-large acceptance and uses the health-gate outcomes above.
* **PE-47532** implements row 4: report exit 11 as a warning, no wait and no poll.
* **PE-47534** implements row 5.
* **PE-47536** uses `success_with_warnings`, the `warnings[]` fields above, `fail_on_warnings` and the `peadm/run-had-warnings` kind.
* **Row 7** needs a new ticket for `init_db_server`; none exists yet.
* **PE-47537 and PE-47681** take each accepted-failure scenario's expected outcome from this table.
* **PE-47160** is answered by row 2: record the failure as a warning; configure's final run stays the gate.

## Open questions

None.

Settled on dev VMs (2026-11-09 to 2026-11-11, PE 2025.12.1, `main` at `51b207e`): the extra-large installer still exits non-zero (row 3); `submit_request` with a pending request exits 1 with a conflict error (row 6); and `forget` of an unknown node exits 0 when Code Manager is on (row 5). Without Code Manager, `forget` exits 1 before looking the node up ("Puppet cannot forget a replica until Code Manager and file sync are enabled"), but add_replica refuses to run without Code Manager, so that case can't reach this call. `upgrade replica` exits 0 or 1, never 11 (row 4). Checked on 2026-11-12 after review: `ldap/create` creates nothing on a rejected config and a new config on every accepted one (row 1), and the CA's `certificate_request` endpoint tells a pending request from none without a client certificate (row 6). Not checked: whether a 2023.8 target's `upgrade replica` can still exit 11 (row 4's outcome doesn't depend on it), and the retry counts in rows 8, 10 and 11, which are as read from the code.

Found while settling row 4: on PE 2025.12.1, `puppet infrastructure provision replica` exits 11 when the replica's services aren't running after 5 checks, or PuppetDB's first sync times out, and tells the operator to run `enable replica` later. `tasks/provision_replica.sh` runs with `set -e`, so that exit fails the task, and the replica is never enabled. That is the right outcome under rule 1 (the requested replica isn't usable), so it stays a failure; configure retries it up to 3 times (row 9).

## Sign-off

* **Epic owner (PE-46764):** pending. This changes behaviour that `configure_spec.rb:310` pins today.
* **Reviewers (owners of the dependent tickets):** PE-47526, PE-47530, PE-47531, PE-47532 and PE-47536: pending.
