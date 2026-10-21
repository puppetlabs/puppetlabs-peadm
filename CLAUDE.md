# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`puppetlabs-peadm` is a Puppet module made almost entirely of **Bolt plans and tasks** that install, upgrade, convert, expand, back up/restore and uninstall Puppet Enterprise (PE) infrastructure. It runs from an operator's machine (or CI runner) over SSH against the PE nodes; it is not applied as a normal Puppet catalog. User docs live in `documentation/` (install, upgrade, convert, classification, recovery, release_process).

## Commands

Ruby is pinned to **3.1.0** (`.ruby-version`); CI uses Ruby 3.1. Use Bolt from this repo's bundle, not a globally installed one.

```bash
bundle install
bundle exec rake spec_prep          # REQUIRED before specs: populates spec/fixtures/modules
                                    # (symlinks peadm + peadm_spec). Without it every plan
                                    # spec fails with "Could not find a plan named 'peadm::…'".

# Static checks exactly as CI runs them (spec.yml "Run Static & Syntax Tests")
bundle exec rake validate lint check rubocop
#   `check` includes strings:validate:reference → REFERENCE.md must be current.
#   After adding/changing a plan, task, function or parameter docs, regenerate it:
bundle exec rake strings:generate:reference

# Unit/spec tests
bundle exec rake parallel_spec
bundle exec rspec spec/plans/subplans/install_spec.rb        # one file
bundle exec rspec spec/plans/subplans/install_spec.rb:654    # one example
```

Running plans by hand against real VMs (same shape CI uses):

```bash
bundle exec bolt plan run peadm::install --params @params.json \
  --inventoryfile <inventory.yaml> --modulepath spec/fixtures/modules --stream
```

- `--stream` prints each target's stdout/stderr live; without it Bolt prints only `Starting:`/`Finished:` lines. The PE installer's own log is only on the node under `/var/log/puppetlabs/installer/`.
- Bolt rejects mixing `--params @file` with `key=value` args, so `begin_at_step` must go inside the params JSON.
- `console_password` must satisfy PE complexity (needs a special character); PE only rejects it late in the installer run.

## Architecture

### Architecture is inferred from which hosts are passed
`functions/assert_supported_architecture.pp` maps the presence of `primary_host`, `replica_host`, `primary_postgresql_host`, `replica_postgresql_host` (+ compilers) to `standard` / `large` / `extra-large`, each with or without `disaster-recovery`. Any other combination fails. Most plans call it up front and branch on the returned hash.

### Install = two subplans
`plans/install.pp` is a thin wrapper around:
1. **`plans/subplans/install.pp`**: precheck, generate a **per-node `pe.conf`** (`peadm::generate_pe_conf`), download the tarball, add CSR extension requests, run the PE installer (primary, then PostgreSQL nodes on XL), sign certs, install agents on replica/compilers, run Puppet.
2. **`plans/subplans/configure.pp`**: copy secrets/`hiera.yaml` to the replica, `apply()` the classification (below), provision the replica via the `peadm::provision_replica` task (with retries), final Puppet runs.

### Roles live in certificate extensions; classification keys off them
- Each node's role and availability group are baked into its certificate as trusted extensions. OIDs are in `functions/oid.pp`: `peadm_role` (e.g. `puppet/server`, `puppet/puppetdb-database`), `peadm_availability_group` (`A`/`B`), plus `pp_auth_role` for compilers. `plans/util/insert_csr_extension_requests.pp` writes them before the CSR; `modify_cert_extensions` / `modify_certificate` change them later.
- `manifests/setup/node_manager.pp` (applied on the primary via `apply()` with the `node_manager` module) creates/updates the console node groups whose **rules match those extensions**: PE Master, PE Compiler, PE Database, PE Primary A/B, PE HA Replica, PE Compiler Group A/B, PE Legacy Compiler (A/B). A = primary side, B = replica side. Compilers are split across A/B by index.
- `add_replica`, `add_compilers`, `add_database`, `backup` and `restore` read the cluster layout back with the `peadm::get_peadm_config` task. `upgrade` and `convert` still take every host as a parameter (`upgrade` runs `get_peadm_config` but only to log it), and `status` uses `peadm::infrastatus`.

### Plans run on the operator side, tasks run on targets
- `tasks/` are shell/Ruby scripts executed on the PE nodes (`pe_install.sh`, `puppet_runonce`, `rbac_token`, `provision_replica`, `get_peadm_config`, …). Each has a matching `.json` metadata file.
- `functions/` are mostly Puppet-language helpers used inside plans. Common idioms:
  - `peadm::get_targets($spec, 1)` normalises optional host params into target arrays; it returns `[]` for undef.
  - `.peadm::certname()` on an empty target returns `undef`, and `pe.conf` hashes rely on dropping undef values. That is how one code path serves every architecture.
- `peadm::plan_step('<name>') || { … }` (`lib/puppet/functions/peadm/plan_step.rb`) implements resumable steps with `begin_at_step`. Only `upgrade`, `convert` and `add_database` use it.

### XL database layout constraint
On extra-large, only **PuppetDB's** database moves to the dedicated PostgreSQL node (`puppet_enterprise::puppetdb_database_host`). The console databases (rbac, classifier, activity, orchestrator, …) must stay on the primary: do **not** set the general `puppet_enterprise::database_host` in the primary's `pe.conf`. PE's `primary_master_replica` profile hardcodes the replica's console DBs to its local PostgreSQL, replicated (pglogical) from the primary node, so moving them breaks DR replicas (PE-47384, regression from PE-46576). The spec in `spec/plans/subplans/install_spec.rb` guards this.

## Tests

- `spec/plans/**`: BoltSpec plan tests (`expect_task` / `allow_task` / `expect_plan` stubs; no real targets).
- `spec/unit/task/`: specs for task scripts.
- `spec/functions/`, `spec/classes/`: function and `node_manager` class specs.
- `spec/acceptance/peadm_spec/`: a **fixtures module**, not rspec. It holds Bolt plans that the GitHub Actions acceptance workflows run (`provision_test_cluster`, `install_test_cluster`, `upgrade_test_cluster`, `verify_replica`, `perform_failover`, …). It is symlinked into `spec/fixtures/modules/peadm_spec` by `spec_prep`.
- Acceptance workflows (`.github/workflows/test-*.yaml`) provision cloud VMs per architecture (`standard`, `standard-with-dr`, `large`, `large-with-dr`, `extra-large`, `extra-large-with-dr`) and run those plans. When they run:
  - The matrix workflows (`*-matrix`, `install-rhel-9`, `migration`, `legacy-*`, `replace-failed-postgresql`) run on every `pull_request` to `main` that touches code paths (`plans/`, `tasks/`, `spec/`, `functions/`, …). A docs-only PR triggers none of them.
  - `test-backup-restore` runs on `ready_for_review`.
  - The single-architecture workflows (`test-install`, `test-upgrade`, `test-failover`, …) only run via `workflow_dispatch`; the `*-nightly` ones run on a schedule.

## Conventions

- Commits and PR titles: `(PE-NNNNN) Short description`; branches: `PE-NNNNN/main/short-description`.
- `.github/pull_request_template.md` has a checklist (spec tests, acceptance tests, test coverage, docs). Fill it in.
- Releases are cut through the Release Prep → Publish module GitHub Actions; see `documentation/release_process.md`.
