users.map do |user|
  items.each do |item|
    {
      :user_id => user.id,
      item_id: item.id,
      **status
    }
  end
end