# typed: true

module Singleton
  sig { params(klass: Class).void }
  def self.__init__(klass); end
end
