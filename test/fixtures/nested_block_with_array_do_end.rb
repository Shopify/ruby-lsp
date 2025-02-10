groups.each do |group|
  users.map do |user|
    [
      group.id,
      user.id,
      Time.now
    ]
  end
end