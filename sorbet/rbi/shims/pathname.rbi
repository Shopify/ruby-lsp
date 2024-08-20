# typed: false

class Pathname
  sig do
    params(
      external_encoding: T.any(String, Encoding),
      internal_encoding: T.any(String, Encoding),
      encoding: T.any(String, Encoding),
      textmode: BasicObject,
      binmode: BasicObject,
      autoclose: BasicObject,
      mode: String,
    ).returns(String)
  end
  def read(external_encoding: T.unsafe(nil), internal_encoding: T.unsafe(nil), encoding: T.unsafe(nil), textmode: T.unsafe(nil), binmode: T.unsafe(nil), autoclose: T.unsafe(nil), mode: T.unsafe(nil)); end
end
