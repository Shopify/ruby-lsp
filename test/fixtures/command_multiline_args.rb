has_many :something,
  class_name: "Something",
  foreign_key: :something_id,
  inverse_of: :something_else

has_many :something,
  class_name: "Something",
  foreign_key: :something_id,
  inverse_of: :something_else do
    # comment
  end
