desc "Builds and pushes all dockerfiles"
task :build do
  Dir.glob("Dockerfile.*") do |file|
    tag = file.split(/Dockerfile\./).last
    nocache = ENV["NOCACHE"] ? "--no-cache" : ""

    if tag
        sh "docker build -f %s %s --tag choria/packager:%s ." % [file, nocache, tag]
        sh "docker push choria/packager:%s" % tag
    end
  end
end
