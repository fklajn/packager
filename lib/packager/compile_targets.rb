class Packager
  class CompileTargets
    include Enumerable

    def initialize(version, workdir, targets={}, flagsmap={})
      @targets = {}
      @workdir = workdir

      defaults = targets["defaults"] || {}

      targets.each do |target, props|
        next if target == "defaults"

        @targets[target] = CompileTarget.new(target, version, props, @workdir, defaults, flagsmap)
      end
    end

    def validate!
      each do |_, target|
        target.validate!
      end
    end

    def build!
      @targets.each do |name, target|
        puts ">>>> building %s" % target
        target.build!
        puts
      end
    end

    def workdir
      File.expand_path(@workdir)
    end

    def each
      @targets.each do |target|
        yield(target)
      end
    end

    def names
      @targets.keys.sort
    end

    def [](target)
      @targets[target]
    end
  end
end
