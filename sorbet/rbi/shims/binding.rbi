# typed: true

class Binding
  def b(pre: nil, do: nil, up_level: 0); end
  def break(pre: nil, do: nil, up_level: 0); end
end

module Kernel
  def debugger(pre: nil, do: nil, up_level: 0); end
end
