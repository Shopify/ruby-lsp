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
    # Currently, only jumping to classes, modules and required files is supported.
    #
    # # Example
    #
    # ```ruby
    # require "some_gem/file" # <- Request go to definition on this string will take you to the file
    # Product.new # <- Request go to definition on this class name will take you to its declaration.
    # ```
    class Definition < ExtensibleListener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T.nilable(T.any(T::Array[Interface::Location], Interface::Location)) } }

      sig { override.returns(ResponseType) }
      attr_reader :_response

      sig do
        params(
          uri: URI::Generic,
          nesting: T::Array[String],
          index: RubyIndexer::Index,
          emitter: EventEmitter,
          message_queue: Thread::Queue,
        ).void
      end
      def initialize(uri, nesting, index, emitter, message_queue)
        @uri = uri
        @nesting = nesting
        @index = index
        @_response = T.let(nil, ResponseType)

        super(emitter, message_queue)

        emitter.register(self, :on_call, :on_constant_read, :on_constant_path)
      end
      sig { override.params(addon: Addon).returns(T.nilable(RubyLsp::Listener[ResponseType])) }
      def initialize_external_listener(addon)
        addon.create_definition_listener(@uri, @nesting, @index, @emitter, @message_queue)
      end

      sig { override.params(other: Listener[ResponseType]).returns(T.self_type) }
      def merge_response!(other)
        other_response = other._response

        case @_response
        when Interface::Location
          @_response = [@_response, *other_response]
        when Array
          @_response.concat(Array(other_response))
        when nil
          @_response = other_response
        end

        self
      end

      sig { params(node: YARP::CallNode).void }
      def on_call(node)
        message = node.name
        return unless message == "require" || message == "require_relative"

        arguments = node.arguments
        return unless arguments

        argument = arguments.arguments.first
        return unless argument.is_a?(YARP::StringNode)

        case message
        when "require"
          entry = @index.search_require_paths(argument.content).find do |indexable_path|
            indexable_path.require_path == argument.content
          end

          if entry
            candidate = entry.full_path

            @_response = Interface::Location.new(
              uri: URI::Generic.from_path(path: candidate).to_s,
              range: Interface::Range.new(
                start: Interface::Position.new(line: 0, character: 0),
                end: Interface::Position.new(line: 0, character: 0),
              ),
            )
          end
        when "require_relative"
          required_file = "#{argument.content}.rb"
          path = @uri.to_standardized_path
          current_folder = path ? Pathname.new(CGI.unescape(path)).dirname : Dir.pwd
          candidate = File.expand_path(File.join(current_folder, required_file))

          @_response = Interface::Location.new(
            uri: URI::Generic.from_path(path: candidate).to_s,
            range: Interface::Range.new(
              start: Interface::Position.new(line: 0, character: 0),
              end: Interface::Position.new(line: 0, character: 0),
            ),
          )
        end
      end

      sig { params(node: YARP::ConstantPathNode).void }
      def on_constant_path(node)
        find_in_index(node.slice)
      end

      sig { params(node: YARP::ConstantReadNode).void }
      def on_constant_read(node)
        find_in_index(node.slice)
      end

      private

      sig { params(value: String).void }
      def find_in_index(value)
        entries = @index.resolve(value, @nesting)
        return unless entries

        # We should only allow jumping to the definition of private constants if the constant is defined in the same
        # namespace as the reference
        first_entry = T.must(entries.first)
        return if first_entry.visibility == :private && first_entry.name != "#{@nesting.join("::")}::#{value}"

        bundle_path = begin
          Bundler.bundle_path.to_s
        rescue Bundler::GemfileNotFound
          nil
        end

        @_response = entries.filter_map do |entry|
          location = entry.location
          # If the project has Sorbet, then we only want to handle go to definition for constants defined in gems, as an
          # additional behavior on top of jumping to RBIs. Sorbet can already handle go to definition for all constants
          # in the project, even if the files are typed false
          file_path = entry.file_path
          if DependencyDetector.instance.typechecker && bundle_path && !file_path.start_with?(bundle_path) &&
              !file_path.start_with?(RbConfig::CONFIG["rubylibdir"])

            next
          end

          Interface::Location.new(
            uri: URI::Generic.from_path(path: file_path).to_s,
            range: Interface::Range.new(
              start: Interface::Position.new(line: location.start_line - 1, character: location.start_column),
              end: Interface::Position.new(line: location.end_line - 1, character: location.end_column),
            ),
          )
        end
      end
    end
  end
end
