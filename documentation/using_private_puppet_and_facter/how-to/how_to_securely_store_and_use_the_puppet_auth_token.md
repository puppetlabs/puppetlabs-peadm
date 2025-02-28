# How to securely store and use the PUPPET_AUTH_TOKEN

## Description

A brief overview of what this guide helps the reader achieve.

## Prerequisites

List any setup steps, dependencies, or prior knowledge needed before following this guide.

## Usage

### Sourcing a "secrets" file

One way I frequently use to safely store and load secret environment variables is by creating a "secret" file that exports my credential variable.  Whenever I need this secret, then I simply "source" the file.

For example, do the following to set the `PUPPET_AUTH_TOKEN`:

* create a "secrets" file exporting your `PUPPET_AUTH_TOKEN`

```bash
mkdir -p ~/.secrets/forge/forge.puppet.com

cat << 'EOL' ~/.secrets/forge/forge.puppet.com/forge_authentication_token
# My personal forge API token called "longer_key"
export PUPPET_AUTH_TOKEN=<YOUR_PERSONAL_FORGE_TOKEN>
EOL
```

* export `PUPPET_AUTH_TOKEN` to your command-line

```bash
# set your $PUPPET_AUTH_TOKEN, e.g.,
source ~/.secrets/forge/forge.puppet.com/forge_authentication_token
```
