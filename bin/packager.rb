#!/usr/bin/env ruby

require "packager"

abort("Please choose a build using BUILD") unless ENV["BUILD"]
abort("Please set VERSION") unless ENV["VERSION"]
abort("Please set ARTIFACTS") unless ENV["ARTIFACTS"]
abort("Please set PACKAGE") unless ENV["PACKAGE"] unless ENV["BINARY_ONLY"]

if ENV["SOURCE_DIR"]
  Dir.chdir(ENV["SOURCE_DIR"])
end

abort("Please ensure package is a directory") unless File.directory?("packager")
abort("Please ensure packager/buildspec.yaml exist") unless File.exist?("packager/buildspec.yaml")
abort("Artifacts directory %s does not exist" % ENV["ARTIFACTS"]) unless File.directory?(ENV["ARTIFACTS"])

if ENV["BUILD_CACHE"]
  abort("BUILD_CACHE is set but does not exist") unless File.directory?(ENV["BUILD_CACHE"])
end

puts "Building build %s @ %s package %s in %s" % [ENV["BUILD"], ENV["VERSION"], ENV["PACKAGE"], Dir.pwd]

# ruby 1.8 doesnt have mktmpdir :(
tmpdir = File.join("/tmp/%s" % OpenSSL::Random.random_bytes(16).unpack("H*")[0])
FileUtils.mkdir_p(tmpdir)

begin
  defn = YAML.load(File.read("packager/buildspec.yaml"))

  flags_map = defn["flags_map"] || {}

  targets = Packager::CompileTargets.new(
    ENV["VERSION"],
    tmpdir,
    defn[ENV["BUILD"]]["compile_targets"],
    flags_map
  )

  targets.validate!

  if ENV["BINARY_ONLY"]
    targets.build!
    exit
  end

  packages = Packager::Packages.new(
    ENV["VERSION"],
    defn[ENV["BUILD"]]["packages"],
    targets
  )

  packages.validate!

  if ENV["BUILD_CACHE"]
    targets.each do |_, target|
      target.copy_artifact(ENV["BUILD_CACHE"])
    end
  end

  packages[ENV["PACKAGE"]].build!(ENV["ARTIFACTS"])
rescue
  STDERR.puts "Build failed: %s: %s" % [$!.class, $!]
  STDERR.puts $!.backtrace.join("\n\t")
  exit 1
end
