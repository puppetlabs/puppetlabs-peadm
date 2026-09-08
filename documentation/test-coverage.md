# Test coverage in PEADM

PEADM tracks test coverage through two separate, non-overlapping mechanisms,
plus one thing that isn't measured by a tool at all. Each covers a different
slice of the codebase, and none of them alone tells you "how much of PEADM is
tested."

## Ruby line coverage (SimpleCov)

**What it measures:** line coverage of Ruby source files -- `tasks/*.rb` and
`lib/puppet/functions/peadm/*.rb`.

**What it doesn't see:** Puppet plans (`plans/**/*.pp`) and Puppet functions
(`functions/**/*.pp`). Those aren't Ruby, so SimpleCov has nothing to
instrument there.

**How to run it locally:**

```
bundle exec rake spec:simplecov
```

This sets `SIMPLECOV=yes` and runs the full spec suite once (sequentially,
not via `parallel_spec`). It prints a coverage table to the terminal and
writes an HTML report to `coverage/index.html`. `spec/spec_helper_local.rb`
widens SimpleCov's tracked-file glob from the `puppetlabs_spec_helper`
default (`lib/**/*.rb` only) to also include `tasks/*.rb`, so task files with
no spec at all show up as an explicit 0% gap instead of being invisible.

**In CI:** the `Coverage` job in `.github/workflows/spec.yml` runs this on
matching PRs (it's gated by the same path filters and fork-PR `setup_matrix`
check as the `Spec` job, so it doesn't run on every PR) and uploads the HTML
report as a build artifact. `spec/spec_helper_local.rb` sets
`SimpleCov.minimum_coverage 12` (as of PE-45737), so the job now fails the
build below that floor. Codecov upload is intentionally disabled (the
`codecov` gem is present but the formatter is dropped in
`spec_helper_local.rb`) since this repo has no `CODECOV_TOKEN` configured;
wiring that up is separate follow-on work.

**Why 12%, not the 90% PE-45737 named as its acceptance criterion:** SimpleCov
only tracks `tasks/*.rb` and `lib/puppet/functions/peadm/*.rb`. PE-45737's
scope named exactly `plan_step.rb`, `file_content_upload.rb`, and four tasks
(`sign_csr.rb`, `ssl_clean.rb`, `rbac_token.rb`, `validate_rbac_token.rb`) --
all of which now have direct specs. But roughly a dozen *other* tasks this
ticket never named -- `get_peadm_config.rb` (152 lines), `check_pe_master_rules.rb`
(125), `cert_data.rb` (80), `code_sync_status.rb` (88), `check_legacy_compilers.rb`
(52), `code_manager_enabled.rb` (48), and several smaller ones -- remain
completely untested and dominate the Ruby line count. Reaching 90% requires
testing those too, which is a substantially larger scope than PE-45737
described. The measured number after this ticket's work is **12.83%
(161/1255 lines)**, up from the 4.29% PE-45655 baseline; the floor is set to
12 (a small margin below that) rather than left at 0, so this at least
catches *regressions* in what's now covered, and rather than silently
expanding this ticket's scope to chase 90%. Closing the remaining gap is
follow-on work (a new ticket under PE-45224).

**Investigated (PE-46426): why `lib/puppet/functions/peadm/*.rb` files can
never show real SimpleCov coverage.** `plan_step.rb` and
`file_content_upload.rb` showed 0.00% in SimpleCov's report *despite* having
direct, passing unit specs (added in PE-45737) that exercise every branch,
while the four tasks tested in the same ticket (`sign_csr.rb`, `ssl_clean.rb`,
`rbac_token.rb`, `validate_rbac_token.rb`) showed improved coverage as
expected. The root cause is confirmed, not just suspected:

* Specs `require_relative` task files directly, so Ruby's `Kernel#require`
  registers them under their canonical repo-root path (e.g.
  `tasks/sign_csr.rb`) -- the exact path SimpleCov's `track_files` glob (run
  from the repo root) expects. Coverage lines up correctly.
* Puppet functions are never `require`d. rspec-puppet's function example
  group loads them through Puppet's own loader
  (`Puppet::Pops::Loader::Loader::AbstractPathBasedModuleLoader#instantiate`),
  which resolves the file via `Dir.glob` against whatever path is registered
  on `Puppet[:module_path]` -- for rspec-puppet, that's
  `spec/fixtures/modules` (set by `puppetlabs_spec_helper`). `.fixtures.yml`
  maps `spec/fixtures/modules/peadm` to this repo via a *symlink*
  (`symlinks: peadm: '#{source_dir}'`), and `Dir.glob` does not resolve
  symlinks in the paths it returns -- so the resolved path is the literal
  string `spec/fixtures/modules/peadm/lib/puppet/functions/peadm/plan_step.rb`,
  not `lib/puppet/functions/peadm/plan_step.rb`.
* For `Puppet::Functions.create_function`-style functions, the loader's
  `RubyFunctionInstantiator.create` then `eval`s the file's contents as a
  string, passing that symlinked-fixture path as the `eval` filename. Ruby's
  `Coverage` module attributes executed lines to whatever filename string
  was passed to `eval`, so the recorded coverage lands under the symlinked
  fixture path -- a key SimpleCov's `track_files('lib/**/*.rb')` glob (run
  from the repo root) never produces or looks up. The real, executed lines
  are not missing; they're recorded under a path SimpleCov never reads.

**Proof this is a measurement defect, not a testing gap:**
`lib/puppet/functions/peadm/bolt_version.rb` has had a passing spec
(`spec/functions/bolt_version_spec.rb`) since before PE-45737 or PE-46426
existed, and it *still* shows as uncovered in SimpleCov's report. A file
with a real, passing, unrelated-to-this-investigation spec cannot be
"untested" -- the measurement itself is what's broken. This means **no**
`lib/puppet/functions/peadm/*.rb` file can show real SimpleCov coverage
under the current toolchain, regardless of how many specs exist for it.
`node_manager_yaml_location_spec.rb` and `module_version_spec.rb` (added in
PE-46426) are worth having for correctness/regression protection, but
neither will move this metric, and each spec says so in a comment for
exactly this reason.

**Not fixed here (out of scope for PE-46426), for a future ticket under
PE-45224 to pick up:**

1. Repoint rspec-puppet's `module_path` at the repo root directly instead of
   through a symlinked fixture, if module-loading semantics allow it; or
2. Add a SimpleCov result post-processor that folds
   `spec/fixtures/modules/peadm/...` coverage keys back onto their canonical
   `lib/...` keys before the report is generated -- more surgical, doesn't
   require changing how rspec-puppet resolves modules.

Either is real implementation work, not a documentation change, and should
be scoped and reviewed as its own ticket.

## Puppet resource coverage (`RSpec::Puppet::Coverage`)

**What it measures:** the percentage of individual resource declarations
(e.g. `File['/etc/foo']`) across `manifests/*.pp` classes that get touched
by catalog compilation during specs (via `rspec-puppet`, part of
`puppetlabs_spec_helper`) -- not resource *types* as a category.

**What it doesn't see:** almost all of PEADM. This repo's logic lives
overwhelmingly in plans and functions, neither of which compile a catalog --
running only `spec/plans` reports "0 total resources, 100% coverage", which
is vacuously true and covers nothing. This metric is only meaningful for the
small number of classes under `manifests/`.

**How to run it locally:** it runs automatically as part of any spec run
(`bundle exec rspec`, `bundle exec rake parallel_spec`, etc.) via the
`after(:suite)` hook in `spec/spec_helper.rb`, and prints a report at the
end.

**In CI:** `RSpec::Puppet::Coverage.report!(90)` in `spec/spec_helper.rb`
(as of PE-45737, up from `0`) fails the build below 90%. This floor is
realistic here: `manifests/setup/node_manager.pp` is the only class in this
repo with resource declarations, and PE-45737 brought its measured resource
coverage from 41.67% (5/12) to **100.00% (12/12)** by adding direct
`contain_node_group` assertions in `spec/classes/setup/node_manager_spec.rb`
for the groups that were compiling but had never been asserted against.

## Plans and functions (tracked manually, no percentage)

Puppet's plan language has no line-coverage tool. For `plans/**/*.pp` and
`functions/**/*.pp`, "covered" means something more deliberate: every
meaningful branch and failure path has a spec assertion that would actually
fail if that logic broke -- not just a test that runs the plan end-to-end and
asserts `is expected to run successfully` (checking the plan compiles and
runs isn't the same as checking it does the right thing on every branch).

There's no automated gate for this, so it's enforced through code review and
ticket acceptance criteria instead. A useful check when writing or reviewing
one of these tests: for each assertion, can you name the specific bug it
would catch -- a flipped condition, a deleted branch, a swallowed error? If
not, the test may be exercising the code without actually verifying it.

## Open items

Standing up the tools above (PE-45655) and closing the specific gaps named
in PE-45737 (negative-path plan specs, the three previously-spec-less
plans, direct function/task unit specs, the remaining `configure.pp`
branches, and `RSpec::Puppet::Coverage` reaching a real, enforced 90% floor)
are both done as of PE-45737.

PE-46426 closed most of the remaining *Ruby line coverage* gap tracked
under [PE-45224](https://perforce.atlassian.net/browse/PE-45224): direct
unit specs were added for the ten previously-untested tasks
(`get_peadm_config.rb`, `check_pe_master_rules.rb`, `cert_data.rb`,
`code_sync_status.rb`, `check_legacy_compilers.rb`, `code_manager_enabled.rb`,
`classify_compilers.rb`, `backup_classification.rb`, `get_group_rules.rb`,
`cert_valid_status.rb`) and the two previously-unspec'd functions
(`node_manager_yaml_location.rb`, `module_version.rb`; `bolt_version.rb`
already had a spec). `classify_compilers.rb` and `cert_valid_status.rb`
also needed a structural-only class-wrap-and-guard commit before they could
be spec'd at all, matching the same pattern PE-45737 used for
`ssl_clean.rb`/`rbac_token.rb`. The SimpleCov attribution question for
`lib/puppet/functions/peadm/*.rb` files is now investigated and documented
above, with a confirmed root cause rather than an open question.

**Measured result:** `bundle exec rake spec:simplecov` (run on Ruby 3.1.7,
since this ticket's local dev machine's pinned rbenv Ruby 3.1.0 has a
broken `socket` native extension -- see PE-46426's implementation notes)
now reports **55.18% (575/1042 lines)**, up from the 12.83% (161/1255
lines) PE-45737 baseline. `SimpleCov.minimum_coverage` in
`spec/spec_helper_local.rb` is raised to 54, a small margin below that,
the same discipline PE-45737 used for `RSpec::Puppet::Coverage`'s floor --
not rounded up to the measured number itself, and not forced to 90%, since
the `lib/puppet/functions/peadm/*.rb` attribution issue documented above
means the real achievable ceiling for this metric is permanently below
100% regardless of test effort: every function file, including
`bolt_version.rb` (which has a real, passing, pre-existing spec), measures
0.00%.

**Still open:** running the full measurement also surfaced six task files
never named in PE-45737 or PE-46426's scope, still completely untested and
now the largest remaining gap: `tasks/update_pe_master_rules.rb` (90
lines), `tasks/node_group_unpin.rb` (95 lines), `tasks/pe_ldap_config.rb`
(56 lines), `tasks/restore_classification.rb` (34 lines),
`tasks/transform_classification_groups.rb` (34 lines), and
`tasks/get_psql_version.rb` (9 lines) -- 318 lines combined. A follow-on
ticket under [PE-45224](https://perforce.atlassian.net/browse/PE-45224)
should write specs for these next, following the same mutation-reasoning
discipline, then raise the floor again incrementally, the same way this
one did.
