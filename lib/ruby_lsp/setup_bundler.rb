# typed: strict
# frozen_string_literal: true

require "bundler"
require "bundler/cli"
require "bundler/cli/install"
require "bundler/cli/update"
require "fileutils"
require "pathname"
require "digest"
require "time"
require "uri"

# This file is a script that will configure a composed bundle for the Ruby LSP. The composed bundle allows developers to
# use the Ruby LSP without including the gem in their application's Gemfile while at the same time giving us access to
# the exact locked versions of dependencies.

Bundler.ui.level = :silent

module RubyLsp
  class SetupBundler
    class BundleNotLocked < StandardError; end
    class BundleInstallFailure < StandardError; end

    module ThorPatch
      #: -> IO
      def stdout
        $stderr
      end
    end

    FOUR_HOURS = 4 * 60 * 60 #: Integer

    #: (String project_path, **untyped options) -> void
    def initialize(project_path, **options)
      @project_path = project_path
      @branch = options[:branch] #: String?
      @launcher = options[:launcher] #: bool?
      force_output_to_stderr! if @launcher

      # Regular bundle paths
      @gemfile = begin
        Bundler.default_gemfile
      rescue Bundler::GemfileNotFound
        nil
      end #: Pathname?
      @lockfile = @gemfile ? Bundler.default_lockfile : nil #: Pathname?

      @gemfile_hash = @gemfile ? Digest::SHA256.hexdigest(@gemfile.read) : nil #: String?
      @lockfile_hash = @lockfile&.exist? ? Digest::SHA256.hexdigest(@lockfile.read) : nil #: String?

      @gemfile_name = @gemfile&.basename&.to_s || "Gemfile" #: String

      # Custom bundle paths
      @custom_dir = Pathname.new(".ruby-lsp").expand_path(@project_path) #: Pathname
      @custom_gemfile = @custom_dir + @gemfile_name #: Pathname
      @custom_lockfile = @custom_dir + (@lockfile&.basename || "Gemfile.lock") #: Pathname
      @lockfile_hash_path = @custom_dir + "main_lockfile_hash" #: Pathname
      @last_updated_path = @custom_dir + "last_updated" #: Pathname
      @error_path = @custom_dir + "install_error" #: Pathname
      @already_composed_path = @custom_dir + "bundle_is_composed" #: Pathname

      dependencies, bundler_version = load_dependencies
      @dependencies = dependencies #: Hash[String, untyped]
      @bundler_version = bundler_version #: Gem::Version?
      @rails_app = rails_app? #: bool
      @retry = false #: bool
      @needs_update_path = @custom_dir + "needs_update" #: Pathname
    end

    # Sets up the composed bundle and returns the `BUNDLE_GEMFILE`, `BUNDLE_PATH` and `BUNDLE_APP_CONFIG` that should be
    # used for running the server
    #: -> Hash[String, String]
    def setup!
      raise BundleNotLocked if !@launcher && @gemfile&.exist? && !@lockfile&.exist?

      # If the bundle was composed ahead of time using our custom `rubyLsp/composeBundle` request, then we can skip the
      # entire process and just return the composed environment
      if @already_composed_path.exist?
        $stderr.puts("Ruby LSP> Composed bundle was set up ahead of time. Skipping...")
        @already_composed_path.delete

        env = bundler_settings_as_env
        env["BUNDLE_GEMFILE"] = @custom_gemfile.exist? ? @custom_gemfile.to_s : @gemfile.to_s

        if env["BUNDLE_PATH"]
          env["BUNDLE_PATH"] = File.expand_path(env["BUNDLE_PATH"], @project_path)
        end

        env["BUNDLER_VERSION"] = @bundler_version.to_s if @bundler_version
        return env
      end

      # Automatically create and ignore the .ruby-lsp folder for users
      @custom_dir.mkpath unless @custom_dir.exist?
      ignore_file = @custom_dir + ".gitignore"
      ignore_file.write("*") unless ignore_file.exist?

      # Do not set up a composed bundle if LSP dependencies are already in the Gemfile
      if @dependencies["ruby-lsp"] &&
          @dependencies["debug"] &&
          (@rails_app ? @dependencies["ruby-lsp-rails"] : true)
        $stderr.puts(
          "Ruby LSP> Skipping composed bundle setup since LSP dependencies are already in #{@gemfile}",
        )

        return run_bundle_install
      end

      write_custom_gemfile

      unless @gemfile&.exist? && @lockfile&.exist?
        $stderr.puts("Ruby LSP> Skipping lockfile copies because there's no top level bundle")
        return run_bundle_install(@custom_gemfile)
      end

      if @lockfile_hash && @custom_lockfile.exist? && @lockfile_hash_path.exist? &&
          @lockfile_hash_path.read == @lockfile_hash
        $stderr.puts(
          "Ruby LSP> Skipping composed bundle setup since #{@custom_lockfile} already exists and is up to date",
        )
        return run_bundle_install(@custom_gemfile)
      end

      FileUtils.cp(@lockfile.to_s, @custom_lockfile.to_s)
      correct_relative_remote_paths
      @lockfile_hash_path.write(@lockfile_hash)
      run_bundle_install(@custom_gemfile)
    end

    private

    #: -> Hash[String, untyped]
    def composed_bundle_dependencies
      @composed_bundle_dependencies ||= begin
        original_bundle_gemfile = ENV["BUNDLE_GEMFILE"]

        if @custom_lockfile.exist?
          ENV["BUNDLE_GEMFILE"] = @custom_gemfile.to_s
          Bundler::LockfileParser.new(@custom_lockfile.read).dependencies
        else
          {}
        end
      ensure
        ENV["BUNDLE_GEMFILE"] = original_bundle_gemfile
      end #: Hash[String, untyped]?
    end

    #: -> void
    def write_custom_gemfile
      parts = [
        "# This custom gemfile is automatically generated by the Ruby LSP.",
        "# It should be automatically git ignored, but in any case: do not commit it to your repository.",
        "",
      ]

      # If there's a top level Gemfile, we want to evaluate from the composed bundle. We get the source from the top
      # level Gemfile, so if there isn't one we need to add a default source
      if @gemfile&.exist? && @lockfile&.exist?
        gemfile_path = @gemfile.relative_path_from(@custom_dir.realpath)
        parts << "eval_gemfile(File.expand_path(\"#{gemfile_path}\", __dir__))"
      else
        parts.unshift('source "https://rubygems.org"')
      end

      unless @dependencies["ruby-lsp"]
        ruby_lsp_entry = +'gem "ruby-lsp", require: false, group: :development'
        ruby_lsp_entry << ", github: \"Shopify/ruby-lsp\", branch: \"#{@branch}\"" if @branch
        parts << ruby_lsp_entry
      end

      unless @dependencies["debug"]
        # The `mri` platform excludes Windows. We want to install the debug gem only on MRI for any operating system,
        # but that constraint doesn't yet exist in Bundler. On Windows, we are manually checking if the engine is MRI
        parts << if Gem.win_platform?
          'gem "debug", require: false, group: :development, install_if: -> { RUBY_ENGINE == "ruby" }'
        else
          'gem "debug", require: false, group: :development, platforms: :mri'
        end
      end

      if @rails_app && !@dependencies["ruby-lsp-rails"]
        parts << 'gem "ruby-lsp-rails", require: false, group: :development'
      end

      content = parts.join("\n")
      @custom_gemfile.write(content) unless @custom_gemfile.exist? && @custom_gemfile.read == content
    end

    #: -> [Hash[String, untyped], Gem::Version?]
    def load_dependencies
      return [{}, nil] unless @lockfile&.exist?

      # We need to parse the Gemfile.lock manually here. If we try to do `bundler/setup` to use something more
      # convenient, we may end up with issues when the globally installed `ruby-lsp` version mismatches the one included
      # in the `Gemfile`
      lockfile_parser = Bundler::LockfileParser.new(@lockfile.read)
      dependencies = lockfile_parser.dependencies

      # When working on a gem, the `ruby-lsp` might be listed as a dependency in the gemspec. We need to make sure we
      # check those as well or else we may get version mismatch errors. Notice that bundler allows more than one
      # gemspec, so we need to make sure we go through all of them
      Dir.glob("{,*}.gemspec").each do |path|
        dependencies.merge!(Bundler.load_gemspec(path).dependencies.to_h { |dep| [dep.name, dep] })
      end

      [dependencies, lockfile_parser.bundler_version]
    end

    #: (?Pathname? bundle_gemfile) -> Hash[String, String]
    def run_bundle_install(bundle_gemfile = @gemfile)
      env = bundler_settings_as_env
      env["BUNDLE_GEMFILE"] = bundle_gemfile.to_s

      # If the user has a composed bundle path configured, we need to ensure that we will use the absolute and not
      # relative version of it when running `bundle install`. This is necessary to avoid installing the gems under the
      # `.ruby-lsp` folder, which is not the user's intention. For example, if the path is configured as `vendor`, we
      # want to install it in the top level `vendor` and not `.ruby-lsp/vendor`
      if env["BUNDLE_PATH"]
        env["BUNDLE_PATH"] = File.expand_path(env["BUNDLE_PATH"], @project_path)
      end

      # Set the specific Bundler version used by the main app. This avoids issues with Bundler restarts, which clean the
      # environment and lead to the `ruby-lsp` executable not being found
      if @bundler_version
        env["BUNDLER_VERSION"] = @bundler_version.to_s
        install_bundler_if_needed
      end

      return run_bundle_install_through_command(env) unless @launcher

      begin
        run_bundle_install_directly(env)
        # If no error occurred, then clear previous errors
        @error_path.delete if @error_path.exist?
        $stderr.puts("Ruby LSP> Composed bundle installation complete")
      rescue Errno::EPIPE, Bundler::HTTPError
        # There are cases where we expect certain errors to happen occasionally, and we don't want to write them to
        # a file, which would report to telemetry on the next launch.
        #
        # - The $stderr pipe might be closed by the client, for example when closing the editor during running bundle
        # install. This situation may happen because, while running bundle install, the server is not yet ready to
        # receive shutdown requests and we may continue doing work until the process is killed.
        # - Bundler might also encounter a network error.
        @error_path.delete if @error_path.exist?
      rescue => e
        # Write the error object to a file so that we can read it from the parent process
        @error_path.write(Marshal.dump(e))
      end

      # If either the Gemfile or the lockfile have been modified during the process of setting up the bundle, retry
      # composing the bundle from scratch
      if @gemfile&.exist? && @lockfile&.exist?
        current_gemfile_hash = Digest::SHA256.hexdigest(@gemfile.read)
        current_lockfile_hash = Digest::SHA256.hexdigest(@lockfile.read)

        if !@retry && (current_gemfile_hash != @gemfile_hash || current_lockfile_hash != @lockfile_hash)
          @gemfile_hash = current_gemfile_hash
          @lockfile_hash = current_lockfile_hash
          @retry = true
          @custom_dir.rmtree
          $stderr.puts("Ruby LSP> Bundle was modified during setup. Retrying from scratch...")
          return setup!
        end
      end

      env
    end

    #: (Hash[String, String] env, ?force_install: bool) -> Hash[String, String]
    def run_bundle_install_directly(env, force_install: false)
      RubyVM::YJIT.enable if defined?(RubyVM::YJIT.enable)

      # The should_bundle_update? check needs to run on the original Bundler environment, but everything else (like
      # updating or running install) requires the modified environment. Here we compute the check ahead of time and
      # merge the environment to ensure correct results.
      #
      # The symptoms of having these operations in the wrong order is seeing unwanted modifications in the application's
      # main lockfile because we accidentally run update on the main bundle instead of the composed one.
      needs_update = should_bundle_update?
      ENV.merge!(env)

      return update(env) if @needs_update_path.exist?

      FileUtils.touch(@needs_update_path) if needs_update

      $stderr.puts("Ruby LSP> Checking if the composed bundle is satisfied...")

      begin
        missing_gems = bundle_check
      rescue Errno::EPIPE, Bundler::HTTPError
        # These are errors cases where we cannot recover
        raise
      rescue => e
        # If anything fails with bundle check, try to bundle install
        $stderr.puts("Ruby LSP> Running bundle install because #{e.message}")
        bundle_install
        return env
      end

      if missing_gems.empty?
        $stderr.puts("Ruby LSP> Bundle already satisfied")
      else
        $stderr.puts(<<~MESSAGE)
          Ruby LSP> Running bundle install because the following gems are not installed:
          #{missing_gems.map { |g| "#{g.name}: #{g.version}" }.join("\n")}
        MESSAGE

        bundle_install
      end

      env
    end

    # Essentially the same as bundle check, but simplified
    #: -> Array[Gem::Specification]
    def bundle_check
      definition = Bundler.definition
      definition.validate_runtime!
      definition.check!
      definition.missing_specs
    end

    #: -> void
    def bundle_install
      Bundler::CLI::Install.new({ "no-cache" => true }).run
      correct_relative_remote_paths if @custom_lockfile.exist?
    end

    #: (Hash[String, String]) -> Hash[String, String]
    def update(env)
      # Try to auto upgrade the gems we depend on, unless they are in the Gemfile as that would result in undesired
      # source control changes
      gems = ["ruby-lsp", "debug", "prism"].reject { |dep| @dependencies[dep] }
      gems << "ruby-lsp-rails" if @rails_app && !@dependencies["ruby-lsp-rails"]

      Bundler::CLI::Update.new({ conservative: true }, gems).run
      correct_relative_remote_paths if @custom_lockfile.exist?
      @needs_update_path.delete
      @last_updated_path.write(Time.now.iso8601)
      env
    end

    #: (Hash[String, String] env) -> Hash[String, String]
    def run_bundle_install_through_command(env)
      # If `ruby-lsp` and `debug` (and potentially `ruby-lsp-rails`) are already in the Gemfile, then we shouldn't try
      # to upgrade them or else we'll produce undesired source control changes. If the composed bundle was just created
      # and any of `ruby-lsp`, `ruby-lsp-rails` or `debug` weren't a part of the Gemfile, then we need to run `bundle
      # install` for the first time to generate the Gemfile.lock with them included or else Bundler will complain that
      # they're missing. We can only update if the custom `.ruby-lsp/Gemfile.lock` already exists and includes all gems

      # When not updating, we run `(bundle check || bundle install)`
      # When updating, we run `((bundle check && bundle update ruby-lsp debug) || bundle install)`
      bundler_path = File.join(Gem.default_bindir, "bundle")
      base_command = (!Gem.win_platform? && File.exist?(bundler_path) ? "#{Gem.ruby} #{bundler_path}" : "bundle").dup

      if env["BUNDLER_VERSION"]
        base_command << " _#{env["BUNDLER_VERSION"]}_"
      end

      command = +"(#{base_command} check"

      if should_bundle_update?
        # If any of `ruby-lsp`, `ruby-lsp-rails` or `debug` are not in the Gemfile, try to update them to the latest
        # version
        command.prepend("(")
        command << " && #{base_command} update "
        command << "ruby-lsp " unless @dependencies["ruby-lsp"]
        command << "debug " unless @dependencies["debug"]
        command << "ruby-lsp-rails " if @rails_app && !@dependencies["ruby-lsp-rails"]
        command.delete_suffix!(" ")
        command << ")"

        @last_updated_path.write(Time.now.iso8601)
      end

      command << " || #{base_command} install) "

      # Redirect stdout to stderr to prevent going into an infinite loop. The extension might confuse stdout output with
      # responses
      command << "1>&2"

      # Add bundle update
      $stderr.puts("Ruby LSP> Running bundle install for the composed bundle. This may take a while...")
      $stderr.puts("Ruby LSP> Command: #{command}")

      # Try to run the bundle install or update command. If that fails, it normally means that the composed lockfile is
      # in a bad state that no longer reflects the top level one. In that case, we can remove the whole directory, try
      # another time and give up if it fails again
      if !system(env, command) && !@retry && @custom_gemfile.exist?
        @retry = true
        @custom_dir.rmtree
        $stderr.puts("Ruby LSP> Running bundle install failed. Trying to re-generate the composed bundle from scratch")
        return setup!
      end

      env
    end

    # Gather all Bundler settings (global and local) and return them as a hash that can be used as the environment
    #: -> Hash[String, String]
    def bundler_settings_as_env
      local_config_path = File.join(@project_path, ".bundle")

      # If there's no Gemfile or if the local config path does not exist, we return an empty setting set (which has the
      # global settings included). Otherwise, we also load the local settings
      settings = begin
        Dir.exist?(local_config_path) ? Bundler::Settings.new(local_config_path) : Bundler::Settings.new
      rescue Bundler::GemfileNotFound
        Bundler::Settings.new
      end

      # List of Bundler settings that don't make sense for the composed bundle and are better controlled manually by the
      # user
      ignored_settings = ["bin", "cache_all", "cache_all_platforms"]

      # Map all settings to their environment variable names with `key_for` and their values. For example, the if the
      # setting name `e` is `path` with a value of `vendor/bundle`, then it will return `"BUNDLE_PATH" =>
      # "vendor/bundle"`
      settings
        .all
        .reject { |setting| ignored_settings.include?(setting) }
        .to_h do |e|
        key = settings.key_for(e)
        value = Array(settings[e]).join(":").tr(" ", ":")

        [key, value]
      end
    end

    #: -> void
    def install_bundler_if_needed
      # Try to find the bundler version specified in the lockfile in installed gems. If not found, install it
      requirement = Gem::Requirement.new(@bundler_version.to_s)
      return if Gem::Specification.any? { |s| s.name == "bundler" && requirement =~ s.version }

      Gem.install("bundler", @bundler_version.to_s)
    end

    #: -> bool
    def should_bundle_update?
      # If `ruby-lsp`, `ruby-lsp-rails` and `debug` are in the Gemfile, then we shouldn't try to upgrade them or else it
      # will produce version control changes
      if @rails_app
        return false if @dependencies.values_at("ruby-lsp", "ruby-lsp-rails", "debug").all?

        # If the composed lockfile doesn't include `ruby-lsp`, `ruby-lsp-rails` or `debug`, we need to run bundle
        # install before updating
        return false if composed_bundle_dependencies.values_at("ruby-lsp", "debug", "ruby-lsp-rails").any?(&:nil?)
      else
        return false if @dependencies.values_at("ruby-lsp", "debug").all?

        # If the composed lockfile doesn't include `ruby-lsp` or `debug`, we need to run bundle install before updating
        return false if composed_bundle_dependencies.values_at("ruby-lsp", "debug").any?(&:nil?)
      end

      # If the last updated file doesn't exist or was updated more than 4 hours ago, we should update
      !@last_updated_path.exist? || Time.parse(@last_updated_path.read) < (Time.now - FOUR_HOURS)
    end

    # When a lockfile has remote references based on relative file paths, we need to ensure that they are pointing to
    # the correct place since after copying the relative path is no longer valid
    #: -> void
    def correct_relative_remote_paths
      content = @custom_lockfile.read
      content.gsub!(/remote: (.*)/) do |match|
        last_match = Regexp.last_match #: as !nil
        path = last_match[1]

        # We should only apply the correction if the remote is a relative path. It might also be a URI, like
        # `https://rubygems.org` or an absolute path, in which case we shouldn't do anything
        if path && !URI(path).scheme
          bundle_dir = @gemfile #: as !nil
            .dirname
          "remote: #{File.expand_path(path, bundle_dir)}"
        else
          match
        end
      rescue URI::InvalidURIError, URI::InvalidComponentError
        # If the path raises an invalid error, it might be a git ssh path, which indeed isn't a URI
        match
      end

      @custom_lockfile.write(content)
    end

    # Detects if the project is a Rails app by looking if the superclass of the main class is `Rails::Application`
    #: -> bool
    def rails_app?
      config = Pathname.new("config/application.rb").expand_path
      application_contents = config.read(external_encoding: Encoding::UTF_8) if config.exist?
      return false unless application_contents

      /class .* < (::)?Rails::Application/.match?(application_contents)
    end

    #: -> void
    def force_output_to_stderr!
      # Bundler and RubyGems have different UI objects used for printing. We need to ensure that both are configured to
      # print only to stderr or else they'll break the connection with the editor
      Gem::DefaultUserInteraction.ui = Gem::StreamUI.new($stdin, $stderr, $stderr, false)

      ui = Bundler.ui
      ui.output_stream = :stderr if ui.respond_to?(:output_stream=)
      ui.level = :info

      Bundler::Thor::Shell::Basic.prepend(ThorPatch) if defined?(Bundler::Thor::Shell::Basic)
    end
  end
end
