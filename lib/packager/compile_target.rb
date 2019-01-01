require "openssl"

class Packager
  class CompileTarget
    attr_accessor :os, :arch, :name

    def initialize(name, version, props, workdir, defaults={}, flagsmap={})
      @name = name
      @os = props["os"]
      @arch = props["arch"]
      @workdir = workdir

      props = defaults.merge(props)

      @output = props["output"]
      @flags = props["flags"] || {}
      @tags = props["tags"] || []
      @precommands = props["pre"] || []
      @postcommands = props["post"] || []
      @build_package = props["build_package"]

      @time = Time.now.strftime("%F %T %z")
      @buildid = OpenSSL::Random.random_bytes(16).unpack("H*")[0]
      @flagsmap = flagsmap
      @version = version
    end

    def copy_artifact(source)
      path = File.join(source, output)

      if File.exist?(path)
        FileUtils.cp(path, fqoutput)
      end
    end

    def validate!
      raise("No OS specified") unless @os
      raise("No architecture specified") unless @arch
      raise("No output specified") unless @output
    end

    def built?
      File.exist?(fqoutput) || File.zero?(fqoutput)
    end

    def build!
      if built?
        puts "   >>> skipping, already built: %s" % fqoutput
        return
      end

      puts "   >>> building %s in %s" % [self, Dir.pwd]

      @precommands.each do |cmd|
        puts "     >>> running pre command: %s" % cmd
        unless system(cmd)
          raise("pre command %s failed with exit code %d" % [cmd, $?.exitstatus])
        end
      end

      cmd = build_cmd.join(" ")

      puts "   >>> executing: %s" % cmd

      ENV["GOOS"] = @os.to_s
      ENV["GOARCH"] = @arch.to_s

      unless system(cmd)
        raise("Could not build %s: exited %d" % [self, $?.exitstatus])
      end

      FileUtils.cp(output, fqoutput)

      raise("Build failed: no output produced") unless built?

      puts
      system("ls -l %s" % output)
      system("file %s" % output)
      system("ldd %s" % output)
      puts

      @postcommands.each do |cmd|
        parsed = cmd.gsub("{{output}}", fqoutput)

        puts "     >>> running post command: %s" % parsed
        unless system(parsed)
          raise("post command %s failed with exit code %d" % [parsed, $?.exitstatus])
        end
      end

      puts
      puts "   >>> built %s" % fqoutput
    end

    def to_s
      "CompileTarget %s: os=%s arch=%s output=%s" % [@name, @os, @arch, output]
    end

    def sha
      return ENV["SHA1"] if ENV["SHA1"]

      rev = `git rev-parse --short HEAD 2>&1`.chomp

      raise("Could not get git reference: %s" % rev) if $?.exitstatus > 0

      rev
    end

    def fqoutput
      File.expand_path(File.join(@workdir, output))
    end

    def output
      out = @output.dup

      out.gsub!("{{version}}", @version)
      out.gsub!("{{VERSION}}", @version)

      out.gsub!("{{os}}", @os.downcase)
      out.gsub!("{{OS}}", @os.upcase)

      out.gsub!("{{arch}}", @arch.to_s.downcase)
      out.gsub!("{{ARCH}}", @arch.to_s.upcase)

      out.gsub!("{{sha}}", sha)
      out.gsub!("{{SHA}}", sha.upcase)

      out
    end

    def build_flags
      flags = []

      flags << '-X "%s=%s"' % [@flagsmap["Version"], @version] if @flagsmap["Version"]
      flags << '-X "%s=%s"' % [@flagsmap["SHA"], sha] if @flagsmap["SHA"]
      flags << '-X "%s=%s"' % [@flagsmap["BuildTime"], @time] if @flagsmap["BuildTime"]
      flags << "-B 0x%s" % @buildid

      @flags.each do |flag, value|
        next if ["Version", "SHA", "BuildTime"].include?(flag)

        if @flagsmap.include?(flag)
          flags << '-X "%s=%s"' % [@flagsmap[flag], value]
        else
          flags << '-X "%s=%s"' % [flag, value]
        end
      end

      flags
    end

    def build_cmd
      args = []

      flags = build_flags

      args << "-o" << output
      args << "--tags" << @tags.join(",") unless @tags.empty?
      args << "-ldflags" << "'%s'" % flags.join(" ") unless flags.empty?
      args << @build_package if @build_package

      ["go", "build", *args]
    end
  end
end
