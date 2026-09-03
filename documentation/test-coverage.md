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

**A note for whoever picks up that follow-on work:** `plan_step.rb` and
`file_content_upload.rb` still show 0.00% in SimpleCov's report *despite*
having direct, passing unit specs (added in PE-45737) that exercise every
branch. The four tasks' coverage improved as expected under the same
process. This looks like SimpleCov (or the underlying Ruby `Coverage`
module) not attributing execution back to `lib/puppet/functions/peadm/*.rb`
source files when they're loaded through Puppet's function loader, rather
than a gap in the new specs -- worth investigating before assuming any
`lib/puppet/functions/peadm/*.rb` file's SimpleCov number reflects its real
test coverage.

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
are both done as of PE-45737. What's left, tracked under
[PE-45224](https://perforce.atlassian.net/browse/PE-45224), is the *Ruby
line coverage* gap: SimpleCov sits at 12.83% (161/1255 lines) against a
12% enforced floor, well short of 90%, because roughly a dozen tasks outside
PE-45737's named scope (`get_peadm_config.rb`, `check_pe_master_rules.rb`,
`cert_data.rb`, `code_sync_status.rb`, `check_legacy_compilers.rb`,
`code_manager_enabled.rb`, `classify_compilers.rb`, `backup_classification.rb`,
`get_group_rules.rb`, `cert_valid_status.rb`, and a few smaller ones) have no
spec at all and dominate the line count. A follow-on ticket under PE-45224
should write unit specs for those, following the same mutation-reasoning
discipline as PE-45737, then raise `SimpleCov.minimum_coverage` in
`spec/spec_helper_local.rb` toward 90% as real coverage is added -- not in
one jump, the same way `RSpec::Puppet::Coverage`'s floor here was only
raised once the number backing it was real. That ticket should also
investigate why `plan_step.rb`/`file_content_upload.rb` report 0% despite
having passing direct specs (see the SimpleCov section above) before relying
on this metric for any `lib/puppet/functions/peadm/*.rb` file.
