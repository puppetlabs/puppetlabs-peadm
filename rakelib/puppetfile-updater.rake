require 'puppetfile-updater/task'

# Update all modules, avoid major version updates
PuppetfileUpdater::RakeTask.new :sync_refs do |config|
  # This is required to avoid hitting the GitHub connection rate
  config.gh_login    = 'github_robot'
  config.gh_password = 'github_password'
end

