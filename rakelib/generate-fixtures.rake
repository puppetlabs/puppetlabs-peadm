require 'json'

desc 'generate fixtures'
task :generate_fixturesfile do |t| 
    mod = JSON.parse(File.read('metadata.json'))['name']
    sh "generate-puppetfile -f -p ./Puppetfile #{mod} --fixtures-only -m #{mod}"
end

