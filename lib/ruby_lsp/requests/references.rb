# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![References demo](../../references.gif)
    #
    # The [references
    # request](https://microsoft.github.io/language-server-protocol/specification#textDocument_references) shows all
    # references for the selected symbol.
    #
    # Currently, references is only supported for constants.
    #
    # # Example
    #
    # ```ruby
    # Product.new # <- Request to find references will show all Product references
    # ```
    class References < Listener
      extend T::Sig
      extend T::Generic

      ResponseType = type_member { { fixed: T::Array[Interface::Location] } }

      sig { override.returns(ResponseType) }
      attr_reader :_response

      sig do
        params(
          nesting: T::Array[String],
          index: RubyIndexer::Index,
          context: { includeDeclaration: T::Boolean },
          emitter: EventEmitter,
          message_queue: Thread::Queue,
        ).void
      end
      def initialize(nesting, index, context, emitter, message_queue)
        @nesting = nesting
        @index = index
        @context = context
        @_response = T.let([], ResponseType)

        super(emitter, message_queue)

        emitter.register(self, :on_constant_read, :on_constant_path)
      end

      sig { params(node: YARP::ConstantPathNode).void }
      def on_constant_path(node)
        find_references(node.slice)
      end

      sig { params(node: YARP::ConstantReadNode).void }
      def on_constant_read(node)
        find_references(node.slice)
      end

      private

      sig { params(value: String).void }
      def find_references(value)
        entries = @index.resolve(value, @nesting)
        return unless entries

        bundle_path = begin
          Bundler.bundle_path.to_s
        rescue Bundler::GemfileNotFound
          nil
        end

        add_references(entries, bundle_path) if @context[:includeDeclaration]

        references = @index.find_references(T.must(entries.first).name)
        add_references(references, bundle_path)
      end

      sig do
        params(
          entries: T.any(
            T::Array[RubyIndexer::Index::Entry],
            T::Array[RubyIndexer::Reference],
          ),
          bundle_path: T.nilable(String),
        ).void
      end
      def add_references(entries, bundle_path)
        entries.each do |entry|
          # If the project has Sorbet, then we only want to handle references for constants defined in gems, as
          # an additional behavior on top of jumping to RBIs
          file_path = entry.file_path

          if DependencyDetector.instance.typechecker && bundle_path && !file_path.start_with?(bundle_path) &&
              !file_path.start_with?(RbConfig::CONFIG["rubylibdir"])

            next
          end

          location = entry.location

          @_response << Interface::Location.new(
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
