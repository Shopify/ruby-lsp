# typed: strict
# frozen_string_literal: true

require "rubocop"
require "sorbet-runtime"

module RuboCop
  module Cop
    module RubyLsp
      class Output < Base
        include RangeHelp

        MSG = "Do not write to stdout as it can break the LSP communication. " \
          "Remove it, or use `Notification.window_log_message` instead."
        RESTRICT_ON_SEND = [
          :ap,
          :p,
          :pp,
          :pretty_print,
          :print,
          :puts,
          :binwrite,
          :syswrite,
          :write,
          :write_nonblock,
        ].freeze
        ALLOWED_TYPES = [:send, :csend, :block, :numblock].freeze

        def_node_matcher :output?, <<~PATTERN
          (send nil? {:ap :p :pp :pretty_print :print :puts} ...)
        PATTERN

        def_node_matcher :io_output?, <<~PATTERN
          (send
            {
              (gvar #match_gvar?)
              (const {nil? cbase} {:STDOUT :STDERR})
            }
            {:binwrite :syswrite :write :write_nonblock}
            ...)
        PATTERN

        def on_send(node)
          return if ALLOWED_TYPES.include?(node.parent&.type)
          return if !output?(node) && !io_output?(node)

          range = offense_range(node)

          add_offense(range)
        end

        private

        def match_gvar?(sym)
          [:$stdout, :$stderr].include?(sym)
        end

        def offense_range(node)
          if node.receiver
            range_between(node.source_range.begin_pos, node.loc.selector.end_pos)
          else
            node.loc.selector
          end
        end
      end
    end
  end
end
