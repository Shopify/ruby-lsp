namespace :foo do
  namespace "bar" do
    task :one
    task "two"
    task three: []
    task "four" => []
  end
end
