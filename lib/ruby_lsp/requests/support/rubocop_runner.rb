# typed: true
# frozen_string_literal: true

begin
  require "rubocop"
rescue LoadError
  return
end

begin
  gem("rubocop", ">= 1.4.0")
rescue LoadError
  raise StandardError, "Incompatible RuboCop version. Ruby LSP requires >= 1.4.0"
end

if RuboCop.const_defined?(:LSP) # This condition will be removed when requiring RuboCop >= 1.61.
  RuboCop::LSP.enable
end

require "prism/translation/parser/rubocop"

module RubyLsp
  module Requests
    module Support
      class InternalRuboCopError < StandardError
        extend T::Sig

        MESSAGE = <<~EOS
          An internal error occurred %s.
          Updating to a newer version of RuboCop may solve this.
          For more details, run RuboCop on the command line.
        EOS

        sig { params(rubocop_error: T.any(RuboCop::ErrorWithAnalyzedFileLocation, StandardError)).void }
        def initialize(rubocop_error)
          message = case rubocop_error
          when RuboCop::ErrorWithAnalyzedFileLocation
            format(MESSAGE, "for the #{rubocop_error.cop.name} cop")
          when StandardError
            format(MESSAGE, rubocop_error.message)
          end
          super(message)
        end
      end

      # :nodoc:
      class RuboCopRunner < RuboCop::Runner
        extend T::Sig

        class ConfigurationError < StandardError; end

        sig { returns(T::Array[RuboCop::Cop::Offense]) }
        attr_reader :offenses

        DEFAULT_ARGS = T.let(
          [
            "--stderr", # Print any output to stderr so that our stdout does not get polluted
            "--force-exclusion",
            "--format",
            "RuboCop::Formatter::BaseFormatter", # Suppress any output by using the base formatter
          ],
          T::Array[String],
        )

        begin
          RuboCop::Options.new.parse(["--raise-cop-error"])
          DEFAULT_ARGS << "--raise-cop-error"
        rescue OptionParser::InvalidOption
          # older versions of RuboCop don't support this flag
        end
        DEFAULT_ARGS.freeze

        sig { params(args: String).void }
        def initialize(*args)
          @options = T.let({}, T::Hash[Symbol, T.untyped])
          @offenses = T.let([], T::Array[RuboCop::Cop::Offense])
          @errors = T.let([], T::Array[String])
          @warnings = T.let([], T::Array[String])
          @parse_result = T.let(nil, T.nilable(Prism::ParseResult))

          args += DEFAULT_ARGS
          rubocop_options = ::RuboCop::Options.new.parse(args).first
          config_store = ::RuboCop::ConfigStore.new

          super(rubocop_options, config_store)
        end

        sig { params(path: String, contents: String, parse_result: Prism::ParseResult).void }
        def run(path, contents, parse_result)
          # Clear Runner state between runs since we get a single instance of this class
          # on every use site.
          @errors = []
          @warnings = []
          @offenses = []
          @options[:stdin] = contents
          @parse_result = parse_result

          super([path])

          # RuboCop rescues interrupts and then sets the `@aborting` variable to true. We don't want them to be rescued,
          # so here we re-raise in case RuboCop received an interrupt.
          raise Interrupt if aborting?
        rescue RuboCop::Runner::InfiniteCorrectionLoop => error
          raise Formatting::Error, error.message
        rescue RuboCop::ValidationError => error
          raise ConfigurationError, error.message
        rescue StandardError => error
          raise InternalRuboCopError, error
        end

        sig { returns(String) }
        def formatted_source
          @options[:stdin]
        end

        sig { params(file: String).returns(RuboCop::ProcessedSource) }
        def get_processed_source(file)
          config = @config_store.for_file(file)
          parser_engine = config.parser_engine
          return super unless parser_engine == :parser_prism

          processed_source = T.unsafe(::RuboCop::AST::ProcessedSource).new(
            @options[:stdin],
            Prism::Translation::Parser::VERSION_3_3,
            file,
            parser_engine: parser_engine,
            prism_result: @parse_result,
          )
          processed_source.config = config
          processed_source.registry = mobilized_cop_classes(config)
          # We have to reset the result to nil after returning the processed source the first time. This is needed for
          # formatting because RuboCop will keep re-parsing the same file until no more auto-corrects can be applied. If
          # we didn't reset it, we would end up operating in a stale AST
          @parse_result = nil
          processed_source
        end

        class << self
          extend T::Sig

          sig { params(cop_name: String).returns(T.nilable(T.class_of(RuboCop::Cop::Base))) }
          def find_cop_by_name(cop_name)
            cop_registry[cop_name]&.first
          end

          private

          sig { returns(T::Hash[String, [T.class_of(RuboCop::Cop::Base)]]) }
          def cop_registry
            @cop_registry ||= T.let(
              RuboCop::Cop::Registry.global.to_h,
              T.nilable(T::Hash[String, [T.class_of(RuboCop::Cop::Base)]]),
            )
          end
        end

        private

        sig { params(_file: String, offenses: T::Array[RuboCop::Cop::Offense]).void }
        def file_finished(_file, offenses)
          @offenses = offenses
        end
      end
    end
  end
end

# Processed Source patch so that we can pass the existing AST to RuboCop without having to re-parse files a second time
module ProcessedSourcePatch
  extend T::Sig

  sig do
    params(
      source: String,
      ruby_version: Float,
      path: T.nilable(String),
      parser_engine: Symbol,
      prism_result: T.nilable(Prism::ParseResult),
    ).void
  end
  def initialize(source, ruby_version, path = nil, parser_engine: :parser_whitequark, prism_result: nil)
    @prism_result = prism_result

    # Invoking super will end up invoking our patched version of tokenize, which avoids re-parsing the file
    super(source, Prism::Translation::Parser::VERSION_3_3, path, parser_engine: parser_engine)
  end

  sig { params(parser: T.untyped).returns(T::Array[T.untyped]) }
  def tokenize(parser)
    begin
      ast, comments, tokens = parser.tokenize(@buffer, parse_result: @prism_result)
      ast ||= nil
    rescue Parser::SyntaxError
      comments = []
      tokens = []
    end

    ast&.complete!
    tokens.map! { |t| RuboCop::AST::Token.from_parser_token(t) }

    [ast, comments, tokens]
  end

  RuboCop::AST::ProcessedSource.prepend(self)
end

module Prism
  module Translation
    class Parser < ::Parser::Base
      extend T::Sig

      sig do
        params(
          source_buffer: ::Parser::Source::Buffer,
          recover: T::Boolean,
          parse_result: T.nilable(Prism::ParseResult),
        ).returns(T::Array[T.untyped])
      end
      def tokenize(source_buffer, recover = false, parse_result: nil)
        @source_buffer = T.let(source_buffer, T.nilable(::Parser::Source::Buffer))
        source = source_buffer.source

        offset_cache = build_offset_cache(source)
        result = if @prism_result
          @prism_result
        else
          begin
            unwrap(
              Prism.parse_lex(source, filepath: source_buffer.name, version: convert_for_prism(version)),
              offset_cache,
            )
          rescue ::Parser::SyntaxError
            raise unless recover
          end
        end

        program, tokens = result.value
        ast = build_ast(program, offset_cache) if result.success?

        [
          ast,
          build_comments(result.comments, offset_cache),
          build_tokens(tokens, offset_cache),
        ]
      ensure
        @source_buffer = nil
      end

      module ProcessedSource
        extend T::Sig
        extend T::Helpers

        requires_ancestor { Kernel }

        sig { params(ruby_version: Float, parser_engine: Symbol).returns(T.untyped) }
        def parser_class(ruby_version, parser_engine)
          if ruby_version == Prism::Translation::Parser::VERSION_3_3
            require "prism/translation/parser33"
            Prism::Translation::Parser33
          elsif ruby_version == Prism::Translation::Parser::VERSION_3_4
            require "prism/translation/parser34"
            Prism::Translation::Parser34
          else
            super
          end
        end
      end
    end
  end
end
