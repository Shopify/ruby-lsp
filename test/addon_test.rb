# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class AddonTest < Minitest::Test
    def setup
      @addon = Class.new(Addon) do
        attr_reader :activated, :field, :settings

        def initialize
          @field = 123
          super
        end

        def activate(global_state, outgoing_queue)
          @activated = true
          @settings = global_state.settings_for_addon(name)
        end

        def name
          "My Add-on"
        end

        def version
          "0.1.0"
        end
      end
      @global_state = GlobalState.new
      @outgoing_queue = Thread::Queue.new
    end

    def teardown
      RubyLsp::Addon.file_watcher_addons.clear
      RubyLsp::Addon.addon_classes.clear
      RubyLsp::Addon.addons.clear
      @outgoing_queue.close
    end

    def test_registering_an_addon_invokes_activate_on_initialized
      Addon.load_addons(@global_state, @outgoing_queue)
      server = RubyLsp::Server.new

      begin
        capture_subprocess_io do
          server.process_message({ method: "initialized" })
        end

        addon_instance = Addon.addons.find { |addon| addon.is_a?(@addon) } #: as !nil
        assert_predicate(addon_instance, :activated)
      ensure
        server.run_shutdown
      end
    end

    def test_addons_are_automatically_tracked
      Addon.load_addons(@global_state, @outgoing_queue)

      addon = Addon.addons.find { |addon| addon.is_a?(@addon) } #: as untyped
      assert_equal(123, addon.field)
    end

    def test_loading_addons_initializes_them
      Addon.load_addons(@global_state, @outgoing_queue)
      assert(
        Addon.addons.any? { |addon| addon.is_a?(@addon) },
        "Expected add-on to be automatically tracked",
      )
    end

    def test_load_addons_returns_errors
      Class.new(Addon) do
        def activate(global_state, outgoing_queue)
          raise StandardError, "Failed to activate"
        end

        def name
          "My Add-on"
        end

        def version
          "0.1.0"
        end
      end

      Addon.load_addons(@global_state, @outgoing_queue)
      error_addon = Addon.addons.find(&:error?) #: as !nil

      assert_predicate(error_addon, :error?)
      assert_equal(<<~MESSAGE, error_addon.formatted_errors)
        My Add-on:
          Failed to activate
      MESSAGE
    end

    def test_automatically_identifies_file_watcher_addons
      klass = Class.new(::RubyLsp::Addon) do
        def activate(global_state, outgoing_queue); end
        def deactivate; end

        def workspace_did_change_watched_files(changes); end
      end

      Addon.load_addons(@global_state, @outgoing_queue)
      addon = Addon.file_watcher_addons.find { |a| a.is_a?(klass) }
      refute_nil(addon)
    end

    def test_get_an_addon_by_name
      Addon.load_addons(@global_state, @outgoing_queue)
      addon = Addon.get("My Add-on", "0.1.0")
      assert_equal("My Add-on", addon.name)
    end

    def test_raises_if_an_addon_cannot_be_found
      Addon.load_addons(@global_state, @outgoing_queue)
      assert_raises(Addon::AddonNotFoundError) do
        Addon.get("Invalid Addon", "0.1.0")
      end
    end

    def test_raises_if_an_addon_version_does_not_match
      Addon.load_addons(@global_state, @outgoing_queue)
      assert_raises(Addon::IncompatibleApiError) do
        Addon.get("My Add-on", "> 15.0.0")
      end
    end

    def test_raises_if_no_version_constraints_are_passed
      Addon.load_addons(@global_state, @outgoing_queue)
      assert_raises(Addon::IncompatibleApiError) do
        Addon.get("My Add-on")
      end
    end

    def test_addons_receive_settings
      @global_state.apply_options({
        initializationOptions: {
          addonSettings: {
            "My Add-on" => { something: false },
          },
        },
      })

      Addon.load_addons(@global_state, @outgoing_queue)

      addon = Addon.get("My Add-on", "0.1.0") #: as untyped
      assert_equal({ something: false }, addon.settings)
    end

    def test_depend_on_constraints
      Addon.load_addons(@global_state, @outgoing_queue)
      assert_raises(Addon::IncompatibleApiError) do
        Addon.depend_on_ruby_lsp!(">= 10.0.0")
      end

      Addon.depend_on_ruby_lsp!(">= 0.18.0", "< 0.30.0")
    end

    def test_project_specific_addons
      Dir.mktmpdir do |dir|
        addon_dir = File.join(dir, "lib", "ruby_lsp", "test_addon")
        FileUtils.mkdir_p(addon_dir)
        File.write(File.join(addon_dir, "addon.rb"), <<~RUBY)
          class ProjectAddon < RubyLsp::Addon
            attr_reader :hello

            def activate(global_state, outgoing_queue)
              @hello = true
            end

            def name
              "Project Addon"
            end

            def version
              "0.1.0"
            end
          end
        RUBY

        @global_state.apply_options({
          workspaceFolders: [{ uri: URI::Generic.from_path(path: dir).to_s }],
        })
        Addon.load_addons(@global_state, @outgoing_queue)

        addon = Addon.get("Project Addon", "0.1.0") #: as untyped
        assert_equal("Project Addon", addon.name)
        assert_predicate(addon, :hello)
      end
    end

    def test_loading_project_addons_ignores_bundle_path
      Dir.mktmpdir do |dir|
        addon_dir = File.join(dir, "vendor", "bundle", "ruby_lsp", "test_addon")
        FileUtils.mkdir_p(addon_dir)
        File.write(File.join(addon_dir, "addon.rb"), <<~RUBY)
          class ProjectAddon < RubyLsp::Addon
            attr_reader :hello

            def activate(global_state, outgoing_queue)
              @hello = true
            end

            def name
              "Project Addon"
            end

            def version
              "0.1.0"
            end
          end
        RUBY

        @global_state.apply_options({
          workspaceFolders: [{ uri: URI::Generic.from_path(path: dir).to_s }],
        })

        Bundler.stubs(:bundle_path).returns(Pathname.new(File.join(dir, "vendor", "bundle")))
        Addon.load_addons(@global_state, @outgoing_queue)

        assert_raises(Addon::AddonNotFoundError) do
          Addon.get("Project Addon", "0.1.0")
        end
      end
    end

    def test_loading_project_addons_ignores_vendor_bundle
      # Some users have gems installed under `vendor/bundle` despite not having their BUNDLE_PATH configured to be so.
      # That leads to loading the same add-on multiple times if they have the same gem installed both in their
      # BUNDLE_PATH and in `vendor/bundle`
      Dir.mktmpdir do |dir|
        addon_dir = File.join(dir, "vendor", "bundle", "rubocop-1.73.0", "lib", "ruby_lsp", "rubocop")
        FileUtils.mkdir_p(addon_dir)
        File.write(File.join(addon_dir, "addon.rb"), <<~RUBY)
          class OldRuboCopAddon < RubyLsp::Addon
            def activate(global_state, outgoing_queue)
            end

            def name
              "Old RuboCop Addon"
            end

            def version
              "0.1.0"
            end
          end
        RUBY

        @global_state.apply_options({
          workspaceFolders: [{ uri: URI::Generic.from_path(path: dir).to_s }],
        })

        Addon.load_addons(@global_state, @outgoing_queue)

        assert_raises(Addon::AddonNotFoundError) do
          Addon.get("Project Addon", "0.1.0")
        end
      end
    end
  end
end
