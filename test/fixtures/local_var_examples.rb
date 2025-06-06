def method_with_local_var
  # on_local_variable_write_node_enter
  a_local_var = 1
  # on_local_variable_and_write_node_enter
  a_local_var &&= 1
  # on_local_variable_operator_write_node_enter
  a_local_var += 1
  # on_local_variable_or_write_node_enter
  a_local_var ||= 1
  # on_local_variable_target_node_enter
  a_local_var, _ = [1, 2]
  # on_local_variable_read_node_enter
  a_local_var
end

def another_method
  a_local_var = 2
end

def method_with_block_and_shadowing
  a_local_var = 1

  block do |a_local_var, bar|
    a_local_var = 2
  end
end
