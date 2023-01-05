# typed: true
# frozen_string_literal: true

class Indexer
  VM_DEFINECLASS_TYPE_CLASS           = 0x00
  VM_DEFINECLASS_TYPE_SINGLETON_CLASS = 0x01
  VM_DEFINECLASS_TYPE_MODULE          = 0x02
  VM_DEFINECLASS_FLAG_SCOPED          = 0x08
  VM_DEFINECLASS_FLAG_HAS_SUPERCLASS  = 0x10

  def initialize(root)
    @root = root
    @index = {
      constant: (Hash.new { |h,k| h[k] = [] }),
      method: (Hash.new { |h,k| h[k] = [] })
    }
  end

  def run
    Dir["#{@root}/**/*.rb"].each do |file|
      index_file(file)
    end
  end

  def locs_for_symbol(symbol, kind)
    $stderr.puts "--- Looking for #{symbol} of kind #{kind}"
    index.dig(kind, symbol)
  end

  private

  attr_reader :root, :index

  def index_file(file)
    iseq = RubyVM::InstructionSequence.compile(File.read(file)).to_a
    index_iseq(iseq) do |line, event, message|
      index[event][message] << [File.absolute_path(file), line]
    end
  end

  def index_iseq(iseq, nesting = [], &blk)
    line = iseq[9]
    iseq[13].each_with_index do |insn, index|
      case insn
      in Integer
        line = insn
      in [:defineclass, name, class_iseq, ^(VM_DEFINECLASS_TYPE_SINGLETON_CLASS)]
        # if iseq[13][index - 2] == [:putself]
        #   index_iseq(iseq, nesting + [name], &blk)
        # else
        #   raise NotImplementedError, "singleton class with non-self receiver"
        # end
      in [:defineclass, name, class_iseq, flags] if flags & VM_DEFINECLASS_TYPE_MODULE > 0
        blk.call(line, :constant, (nesting + [name]).join("::"))
        index_iseq(class_iseq, nesting + [name], &blk)
      in [:defineclass, name, class_iseq, flags]
        blk.call(line, :constant, (nesting + [name]).join("::"))
        index_iseq(class_iseq, nesting + [name], &blk)
      in [:definemethod, name, method_iseq]
        blk.call(line, :method, "#{name}")
      in [:definesmethod, name, method_iseq]
        blk.call(line, :method, "#{name}")
      else
        # skip other instructions
      end
    end
  end
end
