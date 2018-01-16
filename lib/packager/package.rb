require "fileutils"

class Packager
  class Package
    def initialize(name, version, compiles, props={}, defaults={})
      @name = name
      @version = version
      @props = defaults.merge(props)
      @compiles = compiles
      @workdir = compiles.workdir
      @template_conf = {}
    end

    def build!(target, binary_only=false)
      build_binary

      unless binary_only
        copy_source
        copy_template
        sed_template
        create_tarball
        create_package
        copy_artifacts(target)
      end
    end

    def copy_source
      puts "  >>> copying source %s => %s" % [Dir.pwd, source_dir]
      FileUtils.cp_r(".", source_dir)
    end

    def source_dir
      File.join(@workdir, "source")
    end

    def build_binary
      return unless @props["binary"]

      binary
      copy_binary
    end

    def copy_artifacts(target)
      FileUtils.mkdir_p(target)

      puts "  >>> copying artifacts %s" % artifacts_glob

      Array(artifacts_glob).each do |glob|
        Dir.glob(glob).each do |artifact|
          puts "     >>> %s => %s" % [artifact, target]
          FileUtils.cp_r(artifact, target)
        end
      end
    end

    def create_package
      buildsh = File.join(workdir, "dist", "build.sh")

      puts "  >>> executing builder %s in %s" % [buildsh, mktmpdir]

      unless File.exist?(buildsh)
        raise("No build.sh in the distribution template, cannot build")
      end

      Dir.chdir(mktmpdir) do
        unless system("chmod a+x %s && %s" % [buildsh, buildsh])
          raise("Package build failed with exitcode %d" % $?.exitstatus)
        end
      end
    end

    def create_tarball
      puts "  >>> creading tarball %s" % tarball

      Dir.chdir(mktmpdir) do

        unless system("tar -cvzf %s %s" % [tarball, tarsource])
          raise("Could not create tarball %s from %s, exitcode %d" % tarball, tarsource, $?.exitstatus)
        end
      end
    end

    def copy_binary
      if File.exist?(binary)
        puts "  >>> copying binary %s => %s" % [compile_target.output, workdir]

        FileUtils.cp(binary, workdir)
      end
    end

    def copy_template
      puts "  >>> copying template into work dir %s" % workdir

      global_dir = File.join(template_dir, "..", "global")

      if File.exist?(global_dir)
        Dir.glob("%s/*" % global_dir).each do |entry|
          puts "     >>> %s" % entry
          FileUtils.cp_r(entry, File.join(workdir, "dist"))
        end
      end

      Dir.glob("%s/*" % template_dir).each do |entry|
        puts "     >>> %s" % entry
        FileUtils.cp_r(entry, File.join(workdir, "dist"))
      end
    end

    def sed_template
      puts "  >>> applying build properties to %s" % File.join(workdir, "dist")

      Dir.chdir(File.join(workdir, "dist")) do
        Dir.glob("**/*").each do |file|
          puts "     >>> %s" % file

          next if File.directory?(file)

          system('sed -i.bak "s!{{cpkg_binary}}!%s!g" %s' % [File.basename(binary), file]) if @props["binary"]

          system('sed -i.bak "s!{{cpkg_version}}!%s!g" %s' % [@version, file])
          system('sed -i.bak "s!{{cpkg_tarball}}!%s!g" %s' % [tarball, file])
          system('sed -i.bak "s!{{cpkg_source_dir}}!%s!g" %s' % [source_dir, file])

          @props.each do |name, value|
            system('sed -i.bak "s!{{cpkg_%s}}!%s!g" %s' % [name, value, file])
          end
        end

        Dir.glob("**/*.bak") do |file|
          File.unlink(file)
        end
      end
    end

    def tarball
      if @props["binary"]
        "%s-%s-%s-%s.tgz" % [@props["name"], @version, compile_target.os.downcase, @props["target_arch"]]
      else
        "%s-%s.tgz" % [@props["name"], @version]
      end
    end

    def tarsource
      "%s-%s" % [@props["name"], @version]
    end

    def workdir
      File.join(mktmpdir, tarsource)
    end

    def compile_target
      @compiles[@props["binary"]]
    end

    def binary
      return @_binary if @_binary

      unless compile_target.built?
        puts "  >>> building required binary %s" % compile_target
        compile_target.build!
      end

      @_binary = compile_target.fqoutput
    end

    def mktmpdir
      return @_tmpdir if @_tmpdir

      @_tmpdir = File.join(@workdir, "%s-%s-%s" % [@name, OpenSSL::Random.random_bytes(16).unpack("H*")[0], @version])
      FileUtils.mkdir_p(@_tmpdir)

      FileUtils.mkdir(workdir)
      FileUtils.mkdir(File.join(workdir, "dist"))

      @_tmpdir
    end

    def to_s
      "Package %s: template=%s" % [@name, @props["template"]]
    end

    def validate!
      raise("No name specified in package properties") unless @props["name"]
      raise("No template specified") unless @props["template"]
      raise("Unknown template %s" % @props["template"]) unless File.exist?(template_dir)
      raise("Template has no config.yaml in %s" % template_conf_file) unless File.exist?(template_conf_file)
      raise("Artifacts glob has to be set in config.yaml for the template") unless artifacts_glob

      if @props["binary"]
        raise("Target architecture is not specified") unless @props["target_arch"]
        raise("Unknown compile target %s" % @props["binary"]) unless @compiles[@props["binary"]]
      end

      template_conf.fetch("required_properties", []).each do |required|
        raise("Template required property %s to be set" % required) unless @props[required]
      end

    end

    def artifacts_glob
      template_conf["artifacts"]
    end

    def template_conf
      YAML.load(File.read(template_conf_file))
    end

    def template_conf_file
      File.join(template_dir, "config.yaml")
    end

    def template_dir
      File.join("packager", "templates", @props["template"])
    end
  end
end
