# frozen_string_literal: true

require "bundler/setup"
require_relative "lib/ruby_lsp/internal"

IRB.conf[:IRB_NAME] = IRB::Color.colorize("ruby-lsp", [:BLUE, :BOLD])
IRB.conf[:HISTORY_FILE] = "~/.irb_history"
