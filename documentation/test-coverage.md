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
report as a build artifact. It currently only
*reports* -- it does not fail the build at any threshold yet. Codecov
upload is intentionally disabled (the `codecov` gem is present but the
formatter is dropped in `spec_helper_local.rb`) since this repo has no
`CODECOV_TOKEN` configured; wiring that up is separate follow-on work.

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

**In CI:** `RSpec::Puppet::Coverage.report!(0)` in `spec/spec_helper.rb`
passes `0` as its minimum-coverage argument, which disables enforcement
entirely -- the number is printed but can never fail a build. Raising this
to a real floor, once one is established, is tracked separately (see
[Open items](#open-items) below).

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

Standing up the tools above is one thing; using them to close PEADM's actual
coverage gap is separate, larger work, tracked under
[PE-45224](https://perforce.atlassian.net/browse/PE-45224). At the time this
doc was written, the honest SimpleCov baseline (once `tasks/*.rb` is
included) is **4.29% (55/1283 lines, 27 files)** -- most task files have no
spec at all, so this number moves a lot with each file that gets one.
Neither the SimpleCov job nor the `RSpec::Puppet::Coverage` threshold
enforces a floor yet; both are report-only until that gap is actually
closed.
