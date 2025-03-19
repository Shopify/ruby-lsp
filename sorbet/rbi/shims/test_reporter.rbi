# typed: strict

# Once we update Sorbet to support T.let syntax in RBS we can remove this

module ::RubyLsp
  module TestReporter
    ORIGINAL_STDOUT = T.let($stdout, IO)
  end
end
