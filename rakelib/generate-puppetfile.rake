#require 'generate-puppetfile'
require 'json'

desc 'generate puppetfile'
task :generate_puppetfile, [:mod] do |t, args| 
    args.with_defaults(:mod => JSON.parse(File.read('metadata.json'))['name'])
    sh "generate-puppetfile -c  #{args.mod}"
end


desc 'generate fixtures'
task :generate_fixturesfile do |t| 
    mod = JSON.parse(File.read('metadata.json'))['name']
    sh "generate-puppetfile -f -p ./Puppetfile #{mod} --fixtures-only -m #{mod}"
end

