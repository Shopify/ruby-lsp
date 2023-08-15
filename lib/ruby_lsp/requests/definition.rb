# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Definition demo](../../definition.gif)
    #
    # The [definition
    # request](https://microsoft.github.io/language-server-protocol/specification#textDocument_definition) jumps to the
    # definition of the symbol under the cursor.
    #
    # Currently, only jumping to required files is supported.
    #
    # # Example
    #
    # ```ruby
    # require "some_gem/file" # <- Request go to definition on this string will take you to the file
    # ```
    class Definition < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T.nilable(Interface::Location) } }

      sig { override.returns(ResponseType) }
      attr_reader :response

      sig { params(uri: URI::Generic, emitter: EventEmitter, message_queue: Thread::Queue).void }
      def initialize(uri, emitter, message_queue)
        super(emitter, message_queue)

        @uri = uri
        @response = T.let(nil, ResponseType)
        emitter.register(self, :on_call)
      end

      sig { params(node: YARP::CallNode).void }
      def on_call(node)
        message = node.name
        return unless message == "require" || message == "require_relative"

        arguments = node.arguments
        return unless arguments

        argument = arguments.arguments.first
        return unless argument.is_a?(YARP::StringNode)

        required_file = "#{argument.content}.rb"

        case message
        when "require"
          candidate = find_file_in_load_path(required_file)

          if candidate
            @response = Interface::Location.new(
              uri: URI::Generic.from_path(path: candidate).to_s,
              range: Interface::Range.new(
                start: Interface::Position.new(line: 0, character: 0),
                end: Interface::Position.new(line: 0, character: 0),
              ),
            )
          end
        when "require_relative"
          path = @uri.to_standardized_path
          current_folder = path ? Pathname.new(CGI.unescape(path)).dirname : Dir.pwd
          candidate = File.expand_path(File.join(current_folder, required_file))

          if candidate
            @response = Interface::Location.new(
              uri: URI::Generic.from_path(path: candidate).to_s,
              range: Interface::Range.new(
                start: Interface::Position.new(line: 0, character: 0),
                end: Interface::Position.new(line: 0, character: 0),
              ),
            )
          end
        end
      end

      private

      sig { params(file: String).returns(T.nilable(String)) }
      def find_file_in_load_path(file)
        return unless file.include?("/")

        $LOAD_PATH.each do |p|
          found = Dir.glob("**/#{file}", base: p).first
          return "#{p}/#{found}" if found
        end

        nil
      end
    end
  end
end
