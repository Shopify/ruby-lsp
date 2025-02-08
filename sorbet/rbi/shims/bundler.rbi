# typed: true

module Bundler
  class Settings
    sig { params(name: String).returns(String) }
    def key_for(name); end
  end

  module CLI
    class Install
      sig { params(options: T::Hash[String, T.untyped]).void }
      def initialize(options); end

      sig { void }
      def run; end
    end

    class Update
      sig { params(options: T::Hash[String, T.untyped], gems: T::Array[String]).void }
      def initialize(options, gems); end

      sig { void }
      def run; end
    end
  end

  module Thor # rubocop:disable Style/ClassAndModuleChildren
    module Shell
      class Basic; end
    end
  end
end
