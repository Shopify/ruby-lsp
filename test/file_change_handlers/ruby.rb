# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module FileChangeHandlers
    class RubyTest < Minitest::Test
      def setup
        @server = RubyLsp::Server.new(test_mode: true)
      end

      def teardown
        @server.run_shutdown
      end

      def test_did_change_watched_files_does_not_fail_for_non_existing_files
        @server.process_message({
          method: "workspace/didChangeWatchedFiles",
          params: {
            changes: [
              {
                uri: URI::Generic.from_path(path: File.join(Dir.pwd, "lib", "non_existing.rb")).to_s,
                type: RubyLsp::Constant::FileChangeType::CREATED,
              },
            ],
          },
        })

        assert_raises(Timeout::Error) do
          Timeout.timeout(0.5) do
            notification = find_message(RubyLsp::Notification, "window/logMessage")
            flunk(notification.params.message)
          end
        end
      end

      def test_did_change_watched_files_handles_deletions
        path = File.join(Dir.pwd, "lib", "foo.rb")

        @server.global_state.index.expects(:delete).once.with do |uri|
          uri.full_path == path
        end

        uri = URI::Generic.from_path(path: path)

        @server.process_message({
          method: "workspace/didChangeWatchedFiles",
          params: {
            changes: [
              {
                uri: uri,
                type: RubyLsp::Constant::FileChangeType::DELETED,
              },
            ],
          },
        })
      end

      def test_did_change_watched_files_reports_addon_errors
        Class.new(RubyLsp::Addon) do
          def activate(global_state, outgoing_queue); end

          def workspace_did_change_watched_files(changes)
            raise StandardError, "boom"
          end

          def name
            "Foo"
          end

          def deactivate; end

          def version
            "0.1.0"
          end
        end

        Class.new(RubyLsp::Addon) do
          def activate(global_state, outgoing_queue); end

          def workspace_did_change_watched_files(changes)
          end

          def name
            "Bar"
          end

          def deactivate; end

          def version
            "0.1.0"
          end
        end

        @server.load_addons

        bar = RubyLsp::Addon.get("Bar", "0.1.0")
        bar.expects(:workspace_did_change_watched_files).once

        begin
          @server.process_message({
            method: "workspace/didChangeWatchedFiles",
            params: {
              changes: [
                {
                  uri: URI::Generic.from_path(path: File.join(Dir.pwd, ".rubocop.yml")).to_s,
                  type: RubyLsp::Constant::FileChangeType::CREATED,
                },
              ],
            },
          })

          message = @server.pop_response.params.message
          assert_match("Error in Foo add-on while processing watched file notifications", message)
          assert_match("boom", message)
        ensure
          RubyLsp::Addon.unload_addons
        end
      end

      def test_did_change_watched_files_processes_unique_change_entries
        @server.expects(:handle_rubocop_config_change).once
        @server.process_message({
          method: "workspace/didChangeWatchedFiles",
          params: {
            changes: [
              {
                uri: URI::Generic.from_path(path: File.join(Dir.pwd, ".rubocop.yml")).to_s,
                type: RubyLsp::Constant::FileChangeType::CHANGED,
              },
              {
                uri: URI::Generic.from_path(path: File.join(Dir.pwd, ".rubocop.yml")).to_s,
                type: RubyLsp::Constant::FileChangeType::CHANGED,
              },
            ],
          },
        })
      end
    end
  end
end
