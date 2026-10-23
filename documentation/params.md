# PEADM plan parameters (`params.json`)

Use a Bolt parameters file to supply the named arguments for one plan. This reference follows the usage and JSON examples in [install.md](install.md) and documents the current plan signatures in this checkout.

## Usage

1. Create a Bolt project and an inventory with target names and connection settings as described in [install.md](install.md#usage).
2. Save the JSON example for the desired plan as `params.json` and replace example hosts, paths, passwords and keys.
3. Run the command shown in that plan's section from your Bolt project directory.

`params.json` is an arbitrary filename, not a configuration file automatically read by PEADM. Bolt loads it with `--params @params.json`. The file contains a single JSON object whose keys match the selected plan's arguments. There is no shared parameter set accepted by every plan. Inventory credentials and transport settings belong in the Bolt inventory.

The full examples include every top-level argument, including optional arguments. They illustrate a particular deployment, not defaults to copy unchanged. Alternatives that cannot be used together are shown with one set to `null`. Omit optional keys to use their defaults; JSON `null` maps to Puppet `undef` and is valid only for optional types. Use actual booleans, arrays and objects, not quoted JSON strings. JSON does not support comments.

Single-target parameters use inventory target names (and, for infrastructure hosts, the intended certnames). `TargetSpec` also permits multiple targets; examples use arrays. Names must resolve as required by the deployment; inventory `uri` can provide a separate connection address. Keep real passwords and private keys out of source control.

## Plans

- [install](#install)
- [upgrade](#upgrade)
- [convert](#convert)
- [migrate](#migrate)
- [add_compilers](#add-compilers)
- [add_compiler](#add-compiler)
- [add_replica](#add-replica)
- [add_database](#add-database)
- [replace_failed_postgresql](#replace-failed-postgresql)
- [backup](#backup)
- [restore](#restore)
- [backup_ca](#backup-ca)
- [restore_ca](#restore-ca)
- [status](#status)
- [modify_certificate](#modify-certificate)
- [convert_compiler_to_legacy](#convert-compiler-to-legacy)
- [modify_cert_extensions](#modify-cert-extensions)
- [uninstall](#uninstall)

## install

Plan: [peadm::install](../plans/install.pp).

This full example uses Extra Large with DR, legacy compilers, LDAP, Code Manager and a license. Remove host keys that do not apply to your architecture. Standard requires only `primary_host` and `console_password`; Large adds compilers; Extra Large adds a separate primary PostgreSQL host. DR adds a replica and, for Extra Large, a replica PostgreSQL host. See [install.md](install.md) for inventory and offline media setup.

Use either `r10k_private_key_file` or `r10k_private_key_content`, and either `license_key_file` or `license_key_content`, never both non-null. Inline PEM text must start with `-----BEGIN`; encode line breaks as `\n` in JSON. Replace the host public key with a verified key. The LDAP object shows every accepted field; `group_rdn`, `help_link`, `login`, `password` and `user_rdn` may be omitted. `pe_conf_data` accepts installer settings rather than a fixed set of PEADM keys.

`cloud_database_host` is null in this managed-database example. For a cloud database deployment, set it to the external database hostname and supply the relevant PE connection settings in `pe_conf_data`; the parameter changes node-group configuration and does not provision a cloud database.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `primary_host` | `Peadm::SingleTargetSpec` | **Required** | Primary Puppet server target name and certname. |
| `replica_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Primary replica target; omit for deployments without DR. |
| `compiler_hosts` | `Optional[TargetSpec]` | `undef` | Compiler targets; use an array for multiple hosts. |
| `legacy_compilers` | `Optional[TargetSpec]` | `undef` | Legacy compiler targets. |
| `primary_postgresql_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Separate PuppetDB PostgreSQL host for the primary/selected availability group. |
| `replica_postgresql_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Separate PuppetDB PostgreSQL host for the replica. |
| `cloud_database_host` | `Optional[Stdlib::Host]` | `undef` | External cloud PostgreSQL hostname; changes classifier management. Leave unset for a PEADM-managed database topology. |
| `console_password` | `String` | **Required** | Admin console password. |
| `version` | `Peadm::Pe_version` | `'2023.8.11'` | PE version to install or upgrade to (major.minor.patch, optionally with a suffix). |
| `pe_installer_source` | `Optional[Stdlib::HTTPSUrl]` | `undef` | HTTPS URL of the PE installer tarball; replaces the standard download source. |
| `dns_alt_names` | `Optional[Array[String]]` | `undef` | Certificate DNS alternative names. |
| `compiler_pool_address` | `Optional[String]` | `undef` | Agent-facing compiler/Puppet service address, usually a load balancer. |
| `internal_compiler_a_pool_address` | `Optional[String]` | `undef` | Internal load balancer address for availability group A. |
| `internal_compiler_b_pool_address` | `Optional[String]` | `undef` | Internal load balancer address for availability group B. |
| `pe_conf_data` | `Optional[Hash]` | `{}` | Additional installer pe.conf settings as a JSON object. |
| `ldap_config` | `Optional[Peadm::Ldap_config]` | `undef` | LDAP directory settings; see the complete object in the example. |
| `code_manager_auto_configure` | `Optional[Boolean]` | `undef` | Configure Code Manager automatically. |
| `r10k_remote` | `Optional[String]` | `undef` | Git URL of the control repository. |
| `r10k_private_key_file` | `Optional[String]` | `undef` | Private key file on the Bolt host. |
| `r10k_private_key_content` | `Optional[Peadm::Pem]` | `undef` | Inline PEM private key; alternative to the file parameter. |
| `r10k_known_hosts` | `Optional[Peadm::Known_hosts]` | `undef` | SSH host keys: array of objects with name, type and key; optional title, ensure and host_aliases. |
| `deploy_environment` | `Optional[String]` | `undef` | Code Manager environment to deploy. |
| `license_key_file` | `Optional[String]` | `undef` | License file on the Bolt host. |
| `license_key_content` | `Optional[String]` | `undef` | Inline license text; alternative to the file parameter. |
| `stagingdir` | `Optional[String]` | `undef` | Installer cache directory on the Bolt host; effective install default is /tmp. |
| `uploaddir` | `Optional[String]` | `undef` | Installer directory on target hosts; effective install default is /tmp. |
| `final_agent_state` | `Enum['running', 'stopped']` | `'running'` | Final Puppet agent service state: running or stopped. |
| `download_mode` | `Peadm::Download_mode` | `'bolthost'` | bolthost caches and uploads media; direct downloads on target hosts. |
| `permit_unsafe_versions` | `Boolean` | `false` | Bypass PE version safety checks when true. |
| `token_lifetime` | `String` | `'1y'` | Lifetime of the RBAC token created during installation. |

### Full params.json example

```json
{
  "primary_host": "primary.example.com",
  "replica_host": "replica.example.com",
  "compiler_hosts": [
    "compiler-a.example.com",
    "compiler-b.example.com"
  ],
  "primary_postgresql_host": "database-a.example.com",
  "replica_postgresql_host": "database-b.example.com",
  "legacy_compilers": [
    "legacy-compiler.example.com"
  ],
  "cloud_database_host": null,
  "console_password": "REPLACE_WITH_ADMIN_PASSWORD",
  "version": "2023.8.11",
  "pe_installer_source": null,
  "dns_alt_names": [
    "puppet",
    "puppet.example.com"
  ],
  "compiler_pool_address": "puppet.example.com",
  "internal_compiler_a_pool_address": "compilers-a.example.com",
  "internal_compiler_b_pool_address": "compilers-b.example.com",
  "pe_conf_data": {},
  "ldap_config": {
    "base_dn": "dc=example,dc=com",
    "connect_timeout": 10,
    "disable_ldap_matching_rule_in_chain": false,
    "display_name": "Example LDAP",
    "group_lookup_attr": "cn",
    "group_member_attr": "member",
    "group_name_attr": "cn",
    "group_object_class": "groupOfNames",
    "group_rdn": "ou=groups",
    "help_link": "https://help.example.com",
    "hostname": "ldap.example.com",
    "login": "cn=puppet,dc=example,dc=com",
    "password": "REPLACE_WITH_LDAP_PASSWORD",
    "port": 636,
    "search_nested_groups": false,
    "ssl": true,
    "ssl_hostname_validation": true,
    "ssl_wildcard_validation": false,
    "start_tls": false,
    "user_display_name_attr": "displayName",
    "user_email_attr": "mail",
    "user_lookup_attr": "uid",
    "user_rdn": "ou=people"
  },
  "code_manager_auto_configure": true,
  "r10k_remote": "git@git.example.com:puppet/control-repo.git",
  "r10k_private_key_file": "/secure/control-repo-key",
  "r10k_private_key_content": null,
  "r10k_known_hosts": [
    {
      "name": "git.example.com",
      "type": "ssh-ed25519",
      "key": "REPLACE_WITH_REAL_HOST_PUBLIC_KEY"
    }
  ],
  "deploy_environment": "production",
  "license_key_file": "/secure/license.key",
  "license_key_content": null,
  "stagingdir": "/tmp",
  "uploaddir": "/tmp",
  "final_agent_state": "running",
  "download_mode": "bolthost",
  "permit_unsafe_versions": false,
  "token_lifetime": "1y"
}
```

```sh
bolt plan run peadm::install --params @params.json
```

## upgrade

Plan: [peadm::upgrade](../plans/upgrade.pp).

Supply `version` unless `pe_installer_source` identifies the installer version in its filename. `console_password` is accepted for compatibility but unused. Upgrade does not accept install-only keys such as `legacy_compilers`, `dns_alt_names`, `ldap_config` or `pe_conf_data`; do not reuse a full install file unchanged. Host parameters must describe the existing architecture. See [upgrade.md](upgrade.md).

Allowed `begin_at_step` values: `upgrade-primary`, `upgrade-node-groups`, `upgrade-primary-compilers`, `upgrade-replica`, `upgrade-replica-compilers`, `finalize`.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `primary_host` | `Peadm::SingleTargetSpec` | **Required** | Primary Puppet server target name and certname. |
| `replica_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Primary replica target; omit for deployments without DR. |
| `compiler_hosts` | `Optional[TargetSpec]` | `undef` | Compiler targets; use an array for multiple hosts. |
| `primary_postgresql_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Separate PuppetDB PostgreSQL host for the primary/selected availability group. |
| `replica_postgresql_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Separate PuppetDB PostgreSQL host for the replica. |
| `console_password` | `Optional[String]` | `undef` | Accepted but unused. |
| `version` | `Optional[Peadm::Pe_version]` | `undef` | PE version to install or upgrade to (major.minor.patch, optionally with a suffix). |
| `pe_installer_source` | `Optional[Stdlib::HTTPSUrl]` | `undef` | HTTPS URL of the PE installer tarball; replaces the standard download source. |
| `compiler_pool_address` | `Optional[String]` | `undef` | Agent-facing compiler/Puppet service address, usually a load balancer. |
| `internal_compiler_a_pool_address` | `Optional[String]` | `undef` | Internal load balancer address for availability group A. |
| `internal_compiler_b_pool_address` | `Optional[String]` | `undef` | Internal load balancer address for availability group B. |
| `r10k_known_hosts` | `Optional[Peadm::Known_hosts]` | `undef` | SSH host keys: array of objects with name, type and key; optional title, ensure and host_aliases. |
| `token_file` | `Optional[String]` | `undef` | RBAC token file on the primary; unset uses the task default. |
| `stagingdir` | `String` | `'/tmp'` | Installer cache directory on the Bolt host; effective install default is /tmp. |
| `uploaddir` | `String` | `'/tmp'` | Installer directory on target hosts; effective install default is /tmp. |
| `final_agent_state` | `Enum['running', 'stopped']` | `'running'` | Final Puppet agent service state: running or stopped. |
| `download_mode` | `Peadm::Download_mode` | `'bolthost'` | bolthost caches and uploads media; direct downloads on target hosts. |
| `permit_unsafe_versions` | `Boolean` | `false` | Bypass PE version safety checks when true. |
| `begin_at_step` | `Optional[Peadm::UpgradeSteps]` | `undef` | Resume at a named step; null starts at the beginning. Allowed steps are listed in this section. |
| `node_group_environment` | `String[1]` | `Detected from primary; otherwise production` | Environment for PEADM node groups; detected from primary pe.conf, falling back to production. |
| `primary_host` | `` | **Required** | Primary Puppet server target name and certname. |

### Full params.json example

```json
{
  "primary_host": "primary.example.com",
  "replica_host": "replica.example.com",
  "compiler_hosts": [
    "compiler-a.example.com",
    "compiler-b.example.com"
  ],
  "primary_postgresql_host": "database-a.example.com",
  "replica_postgresql_host": "database-b.example.com",
  "console_password": null,
  "version": "2023.8.11",
  "pe_installer_source": null,
  "compiler_pool_address": "puppet.example.com",
  "internal_compiler_a_pool_address": "compilers-a.example.com",
  "internal_compiler_b_pool_address": "compilers-b.example.com",
  "r10k_known_hosts": [
    {
      "name": "git.example.com",
      "type": "ssh-ed25519",
      "key": "REPLACE_WITH_REAL_HOST_PUBLIC_KEY"
    }
  ],
  "token_file": "/root/.puppetlabs/token",
  "stagingdir": "/tmp",
  "uploaddir": "/tmp",
  "final_agent_state": "running",
  "download_mode": "bolthost",
  "permit_unsafe_versions": false,
  "begin_at_step": null,
  "node_group_environment": "production"
}
```

```sh
bolt plan run peadm::upgrade --params @params.json
```

## convert

Plan: [peadm::convert](../plans/convert.pp).

Convert an existing cluster to PEADM management using its existing host assignments. `compiler_pool_address` defaults to `primary_host`.

Allowed `begin_at_step` values: `modify-primary-certs`, `modify-infra-certs`, `convert-node-groups`, `finalize`. See [convert.md](convert.md).

`console_password` is optional and ignored; it does not change the existing console password. Other parameters must still match this plan's accepted arguments.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `primary_host` | `Peadm::SingleTargetSpec` | **Required** | Primary Puppet server target name and certname. |
| `replica_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Primary replica target; omit for deployments without DR. |
| `compiler_hosts` | `Optional[TargetSpec]` | `undef` | Compiler targets; use an array for multiple hosts. |
| `legacy_compilers` | `Optional[TargetSpec]` | `undef` | Legacy compiler targets. |
| `primary_postgresql_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Separate PuppetDB PostgreSQL host for the primary/selected availability group. |
| `replica_postgresql_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Separate PuppetDB PostgreSQL host for the replica. |
| `compiler_pool_address` | `String` | `$primary_host` | Agent-facing compiler/Puppet service address, usually a load balancer. |
| `primary_host` | `` | **Required** | Primary Puppet server target name and certname. |
| `internal_compiler_a_pool_address` | `Optional[Peadm::SingleTargetSpec] $replica_host = undef, Optional[TargetSpec] $compiler_hosts = undef, Optional[TargetSpec] $legacy_compilers = undef, Optional[Peadm::SingleTargetSpec] $primary_postgresql_host = undef, Optional[Peadm::SingleTargetSpec] $replica_postgresql_host = undef, String $compiler_pool_address = $primary_host, Optional[String]` | `undef` | Internal load balancer address for availability group A. |
| `internal_compiler_b_pool_address` | `Optional[String]` | `undef` | Internal load balancer address for availability group B. |
| `dns_alt_names` | `Array[String]` | `[]` | Certificate DNS alternative names. |
| `begin_at_step` | `Optional[Peadm::ConvertSteps]` | `undef` | Resume at a named step; null starts at the beginning. Allowed steps are listed in this section. |
| `node_group_environment` | `String[1]` | `Detected from primary; otherwise production` | Environment for PEADM node groups; detected from primary pe.conf, falling back to production. |
| `primary_host` | `` | **Required** | Primary Puppet server target name and certname. |
| `console_password` | `Optional[String]` | `undef` | Accepted for params.json compatibility; unused. |

### Full params.json example

```json
{
  "primary_host": "primary.example.com",
  "replica_host": "replica.example.com",
  "compiler_hosts": [
    "compiler-a.example.com",
    "compiler-b.example.com"
  ],
  "primary_postgresql_host": "database-a.example.com",
  "replica_postgresql_host": "database-b.example.com",
  "legacy_compilers": [
    "legacy-compiler.example.com"
  ],
  "compiler_pool_address": "puppet.example.com",
  "internal_compiler_a_pool_address": "compilers-a.example.com",
  "internal_compiler_b_pool_address": "compilers-b.example.com",
  "dns_alt_names": [
    "puppet",
    "puppet.example.com"
  ],
  "begin_at_step": null,
  "node_group_environment": "production",
  "console_password": "REPLACE_WITH_ADMIN_PASSWORD"
}
```

```sh
bolt plan run peadm::convert --params @params.json
```

## migrate

Plan: [peadm::migrate](../plans/migrate.pp).

Specify new hosts for the destination topology. The plan backs up the old primary, installs and restores the new primary, then adds the requested database/replica hosts. `console_password` is accepted but unused; the old primary password is retrieved by the plan. Omit `upgrade_version` to skip the final upgrade.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `old_primary_host` | `Peadm::SingleTargetSpec` | **Required** | Existing primary to migrate from. |
| `new_primary_host` | `Peadm::SingleTargetSpec` | **Required** | New primary to migrate to. |
| `upgrade_version` | `Optional[String]` | `undef` | Optional PE version to upgrade to after migration. |
| `replica_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Primary replica target; omit for deployments without DR. |
| `primary_postgresql_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Separate PuppetDB PostgreSQL host for the primary/selected availability group. |
| `replica_postgresql_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Separate PuppetDB PostgreSQL host for the replica. |
| `console_password` | `Optional[String]` | `undef` | Accepted but unused. |

### Full params.json example

```json
{
  "old_primary_host": "primary.example.com",
  "new_primary_host": "new-primary.example.com",
  "upgrade_version": "2023.8.11",
  "replica_host": "replica.example.com",
  "primary_postgresql_host": "database-a.example.com",
  "replica_postgresql_host": "database-b.example.com",
  "console_password": null
}
```

```sh
bolt plan run peadm::migrate --params @params.json
```

## add_compilers

Plan: [peadm::add_compilers](../plans/add_compilers.pp).

`dns_alt_names` is an array aligned with `compiler_hosts`. Each entry is a comma-separated string, and the literal string `"undef"` means no aliases for that compiler. This differs from install/convert. An unset `primary_postgresql_host` is resolved from the existing configuration. See [add_compilers.md](add_compilers.md).

`console_password` is optional and ignored; it does not change the existing console password. Other parameters must still match this plan's accepted arguments.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `avail_group_letter` | `Enum['A', 'B']` | `'A'` | Availability group A or B for the new compiler(s). |
| `dns_alt_names` | `Optional[Array[String[1]]]` | `undef` | Array of per-compiler comma-separated strings; use the string "undef" for no aliases. |
| `compiler_hosts` | `TargetSpec` | **Required** | Compiler targets; use an array for multiple hosts. |
| `primary_host` | `Peadm::SingleTargetSpec` | **Required** | Primary Puppet server target name and certname. |
| `primary_postgresql_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Separate PuppetDB PostgreSQL host for the primary/selected availability group. |
| `console_password` | `Optional[String]` | `undef` | Accepted for params.json compatibility; unused. |

### Full params.json example

```json
{
  "avail_group_letter": "A",
  "dns_alt_names": [
    "puppet,puppet.example.com",
    "undef"
  ],
  "compiler_hosts": [
    "compiler-a.example.com",
    "compiler-b.example.com"
  ],
  "primary_host": "primary.example.com",
  "primary_postgresql_host": "database-a.example.com",
  "console_password": "REPLACE_WITH_ADMIN_PASSWORD"
}
```

```sh
bolt plan run peadm::add_compilers --params @params.json
```

## add_compiler

Plan: [peadm::add_compiler](../plans/add_compiler.pp).

Proxy for `add_compilers`, accepting one `compiler_host`. Here `dns_alt_names` is a single comma-separated string rather than an array.

`console_password` is optional and ignored; it does not change the existing console password. Other parameters must still match this plan's accepted arguments.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `avail_group_letter` | `Enum['A', 'B']` | `'A'` | Availability group A or B for the new compiler(s). |
| `dns_alt_names` | `Optional[String[1]]` | `undef` | Comma-separated string of aliases for the single compiler. |
| `compiler_host` | `Peadm::SingleTargetSpec` | **Required** | Single new compiler target. |
| `primary_host` | `Peadm::SingleTargetSpec` | **Required** | Primary Puppet server target name and certname. |
| `primary_postgresql_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Separate PuppetDB PostgreSQL host for the primary/selected availability group. |
| `console_password` | `Optional[String]` | `undef` | Accepted for params.json compatibility; unused. |

### Full params.json example

```json
{
  "avail_group_letter": "A",
  "dns_alt_names": "puppet,puppet.example.com",
  "compiler_host": "compiler-a.example.com",
  "primary_host": "primary.example.com",
  "primary_postgresql_host": "database-a.example.com",
  "console_password": "REPLACE_WITH_ADMIN_PASSWORD"
}
```

```sh
bolt plan run peadm::add_compiler --params @params.json
```

## add_replica

Plan: [peadm::add_replica](../plans/add_replica.pp).

Add or replace a replica. Omit `replica_postgresql_host` for Standard/Large; provide it for a separate Extra Large replica database. See [add_replica.md](add_replica.md).

`console_password` is optional and ignored; it does not change the existing console password. Other parameters must still match this plan's accepted arguments.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `primary_host` | `Peadm::SingleTargetSpec` | **Required** | Primary Puppet server target name and certname. |
| `replica_host` | `Peadm::SingleTargetSpec` | **Required** | Primary replica target; omit for deployments without DR. |
| `replica_postgresql_host` | `Optional[Peadm::SingleTargetSpec]` | `undef` | Separate PuppetDB PostgreSQL host for the replica. |
| `token_file` | `Optional[String]` | `undef` | RBAC token file on the primary; unset uses the task default. |
| `node_group_environment` | `String[1]` | `Detected from primary; otherwise production` | Environment for PEADM node groups; detected from primary pe.conf, falling back to production. |
| `primary_host` | `` | **Required** | Primary Puppet server target name and certname. |
| `console_password` | `Optional[String]` | `undef` | Accepted for params.json compatibility; unused. |

### Full params.json example

```json
{
  "primary_host": "primary.example.com",
  "replica_host": "replica.example.com",
  "replica_postgresql_host": "database-b.example.com",
  "token_file": "/root/.puppetlabs/token",
  "node_group_environment": "production",
  "console_password": "REPLACE_WITH_ADMIN_PASSWORD"
}
```

```sh
bolt plan run peadm::add_replica --params @params.json
```

## add_database

Plan: [peadm::add_database](../plans/add_database.pp).

Adds a separate PostgreSQL database host to a Large/Extra Large deployment. Normally let the plan detect `mode`. `is_migration` is used by the migration workflow.

Allowed `begin_at_step` values: `init-db-node`, `replicate-db`, `update-classification`, `update-db-settings`, `cleanup-db`, `finalize`.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `targets` | `Peadm::SingleTargetSpec` | **Required** | Target(s) for this operation; single-target types require exactly one host. |
| `primary_host` | `Peadm::SingleTargetSpec` | **Required** | Primary Puppet server target name and certname. |
| `mode` | `Optional[Enum['init', 'pair']]` | `undef` | init creates the first external database; pair adds its partner. Unset selects automatically. |
| `begin_at_step` | `Optional[Enum[ 'init-db-node', 'replicate-db', 'update-classification', 'update-db-settings', 'cleanup-db', 'finalize']]` | `undef` | Resume at a named step; null starts at the beginning. Allowed steps are listed in this section. |
| `is_migration` | `Optional[Boolean]` | `false` | Migration-specific database setup behavior; normally leave false. |
| `node_group_environment` | `String[1]` | `Detected from primary; otherwise production` | Environment for PEADM node groups; detected from primary pe.conf, falling back to production. |
| `primary_host` | `` | **Required** | Primary Puppet server target name and certname. |

### Full params.json example

```json
{
  "targets": "database-a.example.com",
  "primary_host": "primary.example.com",
  "mode": null,
  "begin_at_step": null,
  "is_migration": false,
  "node_group_environment": "production"
}
```

```sh
bolt plan run peadm::add_database --params @params.json
```

## replace_failed_postgresql

Plan: [peadm::replace_failed_postgresql](../plans/replace_failed_postgresql.pp).



### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `primary_host` | `Peadm::SingleTargetSpec` | **Required** | Primary Puppet server target name and certname. |
| `replica_host` | `Peadm::SingleTargetSpec` | **Required** | Primary replica target; omit for deployments without DR. |
| `working_postgresql_host` | `Peadm::SingleTargetSpec` | **Required** | Surviving PostgreSQL host. |
| `failed_postgresql_host` | `Peadm::SingleTargetSpec` | **Required** | Failed PostgreSQL host being replaced. |
| `replacement_postgresql_host` | `Peadm::SingleTargetSpec` | **Required** | New PostgreSQL host. |

### Full params.json example

```json
{
  "primary_host": "primary.example.com",
  "replica_host": "replica.example.com",
  "working_postgresql_host": "database-a.example.com",
  "failed_postgresql_host": "database-b.example.com",
  "replacement_postgresql_host": "new-database-b.example.com"
}
```

```sh
bolt plan run peadm::replace_failed_postgresql --params @params.json
```

## backup

Plan: [peadm::backup](../plans/backup.pp).

The full example explicitly selects every component with `custom`. With `custom`, omitted component flags default to true. With `recovery` or `migration`, the `backup` object is ignored in favor of the preset. See [backup_restore.md](backup_restore.md) and the component table below.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `targets` | `Peadm::SingleTargetSpec` | **Required** | Target(s) for this operation; single-target types require exactly one host. |
| `backup_type` | `Enum['recovery', 'custom', 'migration']` | `'recovery'` | recovery, custom or migration; controls backup selection. |
| `backup` | `Peadm::Recovery_opts` | `{}` | Custom backup component flags; effective only with backup_type custom. |
| `output_directory` | `String` | `'/tmp'` | Backup output directory on the target host. |

### Full params.json example

```json
{
  "targets": "primary.example.com",
  "backup_type": "custom",
  "backup": {
    "activity": true,
    "ca": true,
    "classifier": true,
    "code": true,
    "config": true,
    "orchestrator": true,
    "puppetdb": true,
    "rbac": true
  },
  "output_directory": "/var/backups/peadm"
}
```

```sh
bolt plan run peadm::backup --params @params.json
```

## restore

Plan: [peadm::restore](../plans/restore.pp).

The full example uses `custom` and explicitly selects all components. Restore only components present in your backup. Omitted custom flags default to true. `recovery`, `recovery-db` and `migration` use presets rather than the `restore` object. `console_password` optionally supplies the restored console password. The archive must already exist on the target. See [backup_restore.md](backup_restore.md).

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `targets` | `Peadm::SingleTargetSpec` | **Required** | Target(s) for this operation; single-target types require exactly one host. |
| `restore_type` | `Enum['recovery', 'recovery-db', 'custom', 'migration']` | `'recovery'` | recovery, recovery-db, custom or migration. |
| `restore` | `Peadm::Recovery_opts` | `{}` | Custom restore component flags; effective only with restore_type custom. |
| `input_file` | `Pattern[/.*\.tar\.gz$/]` | **Required** | Backup archive already on the target host; filename must end in .tar.gz. |
| `console_password` | `Optional[String]` | `undef` | Admin console password. |

### Full params.json example

```json
{
  "targets": "primary.example.com",
  "restore_type": "custom",
  "restore": {
    "activity": true,
    "ca": true,
    "classifier": true,
    "code": true,
    "config": true,
    "orchestrator": true,
    "puppetdb": true,
    "rbac": true
  },
  "input_file": "/var/backups/peadm/peadm-backup.tar.gz",
  "console_password": null
}
```

```sh
bolt plan run peadm::restore --params @params.json
```

## backup_ca

Plan: [peadm::backup_ca](../plans/backup_ca.pp).



### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `target` | `Peadm::SingleTargetSpec` | **Required** | Single target for the CA operation. |
| `output_directory` | `Optional[String]` | `'/tmp'` | Backup output directory on the target host. |

### Full params.json example

```json
{
  "target": "primary.example.com",
  "output_directory": "/var/backups/peadm"
}
```

```sh
bolt plan run peadm::backup_ca --params @params.json
```

## restore_ca

Plan: [peadm::restore_ca](../plans/restore_ca.pp).



### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `target` | `Peadm::SingleTargetSpec` | **Required** | Single target for the CA operation. |
| `file_path` | `String` | **Required** | CA backup archive already on the target host. |
| `recovery_directory` | `Optional[String]` | `'/tmp/peadm_recovery'` | Temporary CA recovery directory on the target. |

### Full params.json example

```json
{
  "target": "primary.example.com",
  "file_path": "/var/backups/peadm/ca_backup.tgz",
  "recovery_directory": "/tmp/peadm_recovery"
}
```

```sh
bolt plan run peadm::restore_ca --params @params.json
```

## status

Plan: [peadm::status](../plans/status.pp).



### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `targets` | `TargetSpec` | **Required** | Target(s) for this operation; single-target types require exactly one host. |
| `format` | `Enum[json,table]` | `'table'` | Output format: json or table. |
| `verbose` | `Boolean` | `false` | Include detailed service status. |
| `summarize` | `Boolean` | `true` | Summarize JSON output. |
| `colors` | `Boolean` | `false for json; true for table` | Use colored output; defaults to false for json and true for table. |

### Full params.json example

```json
{
  "targets": [
    "primary.example.com",
    "another-primary.example.com"
  ],
  "format": "json",
  "verbose": false,
  "summarize": true,
  "colors": false
}
```

```sh
bolt plan run peadm::status --params @params.json
```

## modify_certificate

Plan: [peadm::modify_certificate](../plans/modify_certificate.pp).

Adds/removes certificate extensions and optionally changes DNS names. Omit `dns_alt_names` to leave names unspecified; an empty array explicitly supplies no names. Replace the illustrative extension with your required extension.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `targets` | `TargetSpec` | **Required** | Target(s) for this operation; single-target types require exactly one host. |
| `primary_host` | `Peadm::SingleTargetSpec` | **Required** | Primary Puppet server target name and certname. |
| `add_extensions` | `Hash` | `{}` | Certificate extensions to add as an object. |
| `remove_extensions` | `Array` | `[]` | Certificate extension names to remove as an array. |
| `dns_alt_names` | `Optional[Array]` | `undef` | Certificate DNS alternative names. |
| `force_regenerate` | `Boolean` | `false` | Regenerate the certificate even if no changes are needed. |

### Full params.json example

```json
{
  "targets": [
    "compiler-a.example.com"
  ],
  "primary_host": "primary.example.com",
  "add_extensions": {
    "pp_role": "compiler"
  },
  "remove_extensions": [],
  "dns_alt_names": [
    "puppet",
    "puppet.example.com"
  ],
  "force_regenerate": false
}
```

```sh
bolt plan run peadm::modify_certificate --params @params.json
```

## convert_compiler_to_legacy

Plan: [peadm::convert_compiler_to_legacy](../plans/convert_compiler_to_legacy.pp).

Private helper plan; converts the specified compilers to legacy compilers.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `primary_host` | `Peadm::SingleTargetSpec` | **Required** | Primary Puppet server target name and certname. |
| `legacy_hosts` | `TargetSpec` | **Required** | Compiler targets to convert to legacy compilers. |
| `remove_pdb` | `Optional[Boolean]` | `true` | Remove PuppetDB during conversion. |
| `node_group_environment` | `String[1]` | `Detected from primary; otherwise production` | Environment for PEADM node groups; detected from primary pe.conf, falling back to production. |
| `primary_host` | `` | **Required** | Primary Puppet server target name and certname. |

### Full params.json example

```json
{
  "primary_host": "primary.example.com",
  "legacy_hosts": [
    "legacy-compiler.example.com"
  ],
  "remove_pdb": true,
  "node_group_environment": "production"
}
```

```sh
bolt plan run peadm::convert_compiler_to_legacy --params @params.json
```

## modify_cert_extensions

Plan: [peadm::modify_cert_extensions](../plans/modify_cert_extensions.pp).

Private helper plan for changing certificate extensions; prefer `modify_certificate` for the general certificate workflow.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `targets` | `TargetSpec` | **Required** | Target(s) for this operation; single-target types require exactly one host. |
| `primary_host` | `Peadm::SingleTargetSpec` | **Required** | Primary Puppet server target name and certname. |
| `add` | `Hash` | `{}` | Certificate extensions to add. |
| `remove` | `Array` | `[]` | Certificate extension names to remove. |

### Full params.json example

```json
{
  "targets": [
    "compiler-a.example.com"
  ],
  "primary_host": "primary.example.com",
  "add": {
    "pp_role": "compiler"
  },
  "remove": []
}
```

```sh
bolt plan run peadm::modify_cert_extensions --params @params.json
```

## uninstall

Plan: [peadm::uninstall](../plans/uninstall.pp).

Private, experimental plan. Running this command uninstalls Puppet Enterprise from the specified targets.

### Parameters

| Parameter | Type | Default | Usage |
| --- | --- | --- | --- |
| `targets` | `TargetSpec` | **Required** | Target(s) for this operation; single-target types require exactly one host. |

### Full params.json example

```json
{
  "targets": [
    "retired-primary.example.com"
  ]
}
```

```sh
bolt plan run peadm::uninstall --params @params.json
```

## Backup and restore component options

The `backup` and `restore` objects accept the same boolean keys. These presets come from [recovery_opts_default.pp](../functions/recovery_opts_default.pp), [recovery_opts_all.pp](../functions/recovery_opts_all.pp) and [migration_opts_default.pp](../functions/migration_opts_default.pp).

| Key | Component | recovery | custom (if omitted) | migration |
| --- | --- | --- | --- | --- |
| `activity` | Activity database | false | true | true |
| `ca` | CA data | true | true | true |
| `classifier` | Classification | false | true | true |
| `code` | Puppet code | true | true | false |
| `config` | PE configuration | true | true | false |
| `orchestrator` | Orchestrator data | false | true | true |
| `puppetdb` | PuppetDB data | true | true | true |
| `rbac` | RBAC data | false | true | true |

`recovery` also uses the PE recovery backup/restore workflow; these flags do not fully describe its archive contents. `recovery-db` is a restore-only mode selecting PuppetDB database recovery; consult [backup_restore.md](backup_restore.md) before choosing it.

## Internal plans and existing parameter files

Plans under [subplans](../plans/subplans) and [util](../plans/util) are implementation helpers called with arguments constructed by the parent plans. They do not read `params.json` themselves and do not add accepted keys to their parent plans. In particular, `init_db_server`, `db_purge` and `db_disable_pglogical` receive database settings from their callers. Their signatures remain the reference for direct internal use. The private [misc::divert_code_manager](../plans/misc/divert_code_manager.pp) helper takes only `primary_host` and is intended for advised exceptional configurations.

Existing usage reviewed for this reference:

- [install.md](install.md), [upgrade.md](upgrade.md), [convert.md](convert.md), [add_replica.md](add_replica.md), [add_compilers.md](add_compilers.md) and [backup_restore.md](backup_restore.md) demonstrate Bolt parameter files.
- [spec/docker/install.sh](../spec/docker/install.sh) reads each architecture's `params.json`; [spec/docker/upgrade.sh](../spec/docker/upgrade.sh) reads `upgrade_params.json` under the same directories.
- [examples/upgrade.json](../examples/upgrade.json) is another upgrade argument file. Files under [examples/provision](../examples/provision) belong to provisioning workflows and are not a shared PEADM plan parameter schema.

Use the selected plan's signature, rather than a filename or another plan's example, to determine accepted arguments. You can inspect it with `bolt plan show peadm::<plan>`.
