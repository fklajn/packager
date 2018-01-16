class Packager
  class Packages
    include Enumerable

    def initialize(version, packages, compiles)
      @version = version
      @compiles = compiles
      @packages = {}

      defaults = packages["defaults"] || {}

      packages.each do |package, props|
        next if package == "defaults"

        @packages[package] = Package.new(package, version, compiles, props, defaults)
      end
    end

    def validate!
      each do |_, pkg|
        pkg.validate!
      end
    end

    def each
      @packages.each do |pkg|
        yield(pkg)
      end
    end

    def names
      @packages.keys.sort
    end

    def [](package)
      @packages[package]
    end
  end
end
