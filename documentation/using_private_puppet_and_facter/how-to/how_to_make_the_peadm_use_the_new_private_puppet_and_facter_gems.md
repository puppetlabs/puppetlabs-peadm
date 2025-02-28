# How to make the peadm use the new private puppet and facter gems

## Description

This guide shows how to setup the peadm module to use the private gem source for puppet and facter.

## Prerequisites

* Forge API token.  For more information see [How to create your own personal forge api token](how_to_create_your_own_personal_forge_api_token.md).
* `PUPPET_AUTH_TOKEN` set to the forge key above. For more information see [How to securely store and use the PUPPET_AUTH_TOKEN](how_to_securely_store_and_use_the_puppet_auth_token.md).

## Usage

Create a new pdk module and bundle install proving that by default it keeps working as normal, pulling in the public puppet and facter gems

```bash
# clone the peadm
git clone https://github.com/gavindidrichsen-forks/puppetlabs-peadm-softfork.git
cd puppetlabs-peadm-softfork
git switch auth_token_template

# ensure bundler installs gems locally
bundle config --local gemfile Gemfile
bundle config --local path vendor/bundle
bundle config --local bin vendor/bin

# install gems
bundle install

# verify that puppet and facter come from https://rubygems.org as normal
cat Gemfile.lock | grep -E "(remote:|specs:| puppet | facter | hiera )"

# verify tests are all passing
bundle exec rake spec 2>&1 > /tmp/result.txt
tail -10 /tmp/result.txt
```

Now, export the `PUPPET_AUTH_TOKEN`:

```bash
# clean up
rm -rf Gemfile.lock vendor

# set an invalid token
export PUPPET_AUTH_TOKEN=THIS_IS_NOT_A_VALID_TOKEN

# bundle install should fail: "Authentication is required for rubygems-puppetcore.puppet.com."
bundle install

# configure bundler authentication (using the incorrect PUPPET_AUTH_TOKEN)
bundle config --local https://rubygems-puppetcore.puppet.com "forge-key:${PUPPET_AUTH_TOKEN}"

# bundle install should fail: "Bad username or password for rubygems-puppetcore.puppet.com."
bundle install
```

Set export the correct `PUPPET_AUTH_TOKEN`.  **IMPORTANT**: Only proceed after this has been done.

```bash
# reset the bundle authentication using a valid PUPPET_AUTH_TOKEN
bundle config --local https://rubygems-puppetcore.puppet.com "forge-key:${PUPPET_AUTH_TOKEN}"

# verify the bundle REDACTED credentials
bundle config

# bundle install should work now
bundle install

# verify that puppet and facter come from the new private gem source
cat Gemfile.lock | grep -E "(remote:|specs:| puppet | facter | hiera )"     
bundle info puppet
bundle info facter

# re-run the unit tests
bundle exec rake spec 2>&1 > /tmp/result2.txt
tail -10 /tmp/result2.txt
```

## Appendix

### Sample output

```bash
# configure bundle (wthout any credentials or PUPPET_AUTH_TOKEN)
➜  puppetlabs-peadm-softfork git:(auth_token_template) bundle config --local gemfile Gemfile
➜  puppetlabs-peadm-softfork git:(auth_token_template) bundle config --local path vendor/bundle
➜  puppetlabs-peadm-softfork git:(auth_token_template) bundle config --local bin vendor/bin

# bundle install works as normal
➜  puppetlabs-peadm-softfork git:(auth_token_template) bundle install
Fetching gem metadata from https://rubygems.org/.........
Resolving dependencies...
Fetching rake 13.2.1
...
...

# verify https://rubygems.org source for puppet and facter
➜  puppetlabs-peadm-softfork git:(development) cat Gemfile.lock | grep -E "(remote:|specs:| puppet | facter | hiera )"
  remote: https://rubygems.org/
  specs:
      puppet (>= 6.18.0)
    facter (4.10.0)
      facter (< 5.0.0)
    puppet (8.10.0-universal-darwin)
      facter (>= 4.3.0, < 5)
      puppet (>= 6)
      puppet (>= 7, < 9)
      facter (< 5)
      puppet (>= 7, < 9)

# verify the unit tests all pass
➜  puppetlabs-peadm-softfork git:(development) bundle exec rake spec 2>&1 > /tmp/result.txt
...
...
➜  puppetlabs-peadm-softfork git:(development) tail -10 /tmp/result.txt

  6) peadm::util::sanitize_pg_pe_conf  Runs
     # a lack of support for functions requires a workaround to be written
     Failure/Error: expect(run_plan('peadm::util::sanitize_pg_pe_conf', 'targets' => 'foo,bar', 'primary_host' => 'pe-server-d8b317-0.us-west1-a.c.davidsand.internal')).to be_ok
       expected `#<Bolt::PlanResult:0x00000001173329e0 @value=#<Bolt::PAL::PALError: no implicit conversion of Hash into String>, @status="failure">.ok?` to be truthy, got false
     # ./spec/plans/util/sanitize_pg_pe_conf_spec.rb:18:in `block (2 levels) in <top (required)>'

Finished in 4.75 seconds (files took 1.36 seconds to load)
100 examples, 0 failures, 6 pending

➜  puppetlabs-peadm-softfork git:(development) 
```

Now add the `PUPPET_AUTH_TOKEN` and bundler credentials:

```bash
# clean up
➜  puppetlabs-peadm-softfork git:(development) rm -rf Gemfile.lock vendor

# export an invalid PUPPET_AUTH_TOKEN
➜  puppetlabs-peadm-softfork git:(development) export PUPPET_AUTH_TOKEN=THIS_IS_NOT_A_VALID_TOKEN

# bundle install fails...
➜  puppetlabs-peadm-softfork git:(development) bundle install
Authentication is required for rubygems-puppetcore.puppet.com.
Please supply credentials for this source. You can do this by running:
`bundle config set --global rubygems-puppetcore.puppet.com username:password`
or by storing the credentials in the `BUNDLE_RUBYGEMS___PUPPETCORE__PUPPET__COM` environment variable
➜  puppetlabs-peadm-softfork git:(development) 

# set bundler credentials using the invalid PUPPET_AUTH_TOKEN
➜  puppetlabs-peadm-softfork git:(development) bundle config --local https://rubygems-puppetcore.puppet.com "forge-key:${PUPPET_AUTH_TOKEN}"

# bundle install fails...
➜  puppetlabs-peadm-softfork git:(development) bundle install
Bad username or password for rubygems-puppetcore.puppet.com.
Please double-check your credentials and correct them.
➜  puppetlabs-peadm-softfork git:(development) 
```

Now, set valid `PUPPET_AUTH_TOKEN` and bundler credentials:

```bash
# load the valid PUPPET_AUTH_TOKEN
➜  puppetlabs-peadm-softfork git:(development) source ~/.secrets/forge/forge.puppet.com/forge_authentication_token

# set the bundler credentials
➜  puppetlabs-peadm-softfork git:(development) bundle config --local https://rubygems-puppetcore.puppet.com "forge-key:${PUPPET_AUTH_TOKEN}"
You are replacing the current local value of https://rubygems-puppetcore.puppet.com, which is currently "forge-key:THIS_IS_NOT_A_VALID_TOKEN"

# bundle install succeeds
➜  puppetlabs-peadm-softfork git:(development) bundle install
Fetching gem metadata from https://rubygems-puppetcore.puppet.com/...
Fetching gem metadata from https://rubygems.org/.........
Resolving dependencies...
Fetching rake 13.2.1
...
...
➜  puppetlabs-peadm-softfork git:(development) 

# verify private gem source for puppet and facter
➜  puppetlabs-peadm-softfork git:(development) cat Gemfile.lock | grep -E "(remote:|specs:| puppet | facter | hiera )"    
  remote: https://rubygems-puppetcore.puppet.com/
  specs:
    facter (4.11.0)
    puppet (8.11.0-universal-darwin)
      facter (>= 4.3.0, < 5)
  remote: https://rubygems.org/
  specs:
      puppet (>= 6.18.0)
      facter (< 5.0.0)
      puppet (>= 6)
      puppet (>= 7, < 9)
      facter (< 5)
      puppet (>= 7, < 9)
➜  puppetlabs-peadm-softfork git:(development) 

# verify puppet and facter versions
➜  puppetlabs-peadm-softfork git:(development) bundle info puppet
  * puppet (8.11.0)
        Summary: Puppet, an automated configuration management tool
        Homepage: https://github.com/puppetlabs/puppet
        Path: /Users/gavin.didrichsen/@REFERENCES/github/app/development/tools/puppet/@products/bolt/@investigations/authenticate_bolt_against_private_endpoints/dump/DEMO/puppetlabs-peadm-softfork/vendor/bundle/ruby/3.2.0/gems/puppet-8.11.0-universal-darwin
        Reverse Dependencies: 
                bolt (4.0.0) depends on puppet (>= 6.18.0)
                puppet-debugger (1.4.0) depends on puppet (>= 6)
                puppet-syntax (4.1.1) depends on puppet (>= 7, < 9)
                rspec-puppet-facts (5.2.0) depends on puppet (>= 7, < 9)
➜  puppetlabs-peadm-softfork git:(development) bundle info facter
  * facter (4.11.0)
        Summary: Facter, a system inventory tool
        Homepage: https://github.com/puppetlabs/facter
        Path: /Users/gavin.didrichsen/@REFERENCES/github/app/development/tools/puppet/@products/bolt/@investigations/authenticate_bolt_against_private_endpoints/dump/DEMO/puppetlabs-peadm-softfork/vendor/bundle/ruby/3.2.0/gems/facter-4.11.0
        Reverse Dependencies: 
                facterdb (3.4.0) depends on facter (< 5.0.0)
                puppet (8.11.0) depends on facter (>= 4.3.0, < 5)
                rspec-puppet-facts (5.2.0) depends on facter (< 5)
➜  puppetlabs-peadm-softfork git:(development) 

# verify tests continue to pass
➜  puppetlabs-peadm-softfork git:(development) bundle exec rake spec 2>&1 > /tmp/result2.txt
...
...
➜  puppetlabs-peadm-softfork git:(development) 
➜  puppetlabs-peadm-softfork git:(development) tail -10 /tmp/result2.txt

  6) peadm::util::sanitize_pg_pe_conf  Runs
     # a lack of support for functions requires a workaround to be written
     Failure/Error: expect(run_plan('peadm::util::sanitize_pg_pe_conf', 'targets' => 'foo,bar', 'primary_host' => 'pe-server-d8b317-0.us-west1-a.c.davidsand.internal')).to be_ok
       expected `#<Bolt::PlanResult:0x000000012113c5f0 @value=#<Bolt::PAL::PALError: no implicit conversion of Hash into String>, @status="failure">.ok?` to be truthy, got false
     # ./spec/plans/util/sanitize_pg_pe_conf_spec.rb:18:in `block (2 levels) in <top (required)>'

Finished in 4.59 seconds (files took 1.47 seconds to load)
100 examples, 0 failures, 6 pending

➜  puppetlabs-peadm-softfork git:(development) 
```
