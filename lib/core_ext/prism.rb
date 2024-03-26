# typed: strict
# frozen_string_literal: true

module Prism
  LocalVariableNode = T.type_alias do
    T.any(
      Prism::LocalVariableWriteNode,
      Prism::LocalVariableTargetNode,
      Prism::LocalVariableAndWriteNode,
      Prism::LocalVariableOrWriteNode,
      Prism::LocalVariableReadNode,
      Prism::LocalVariableOperatorWriteNode,
      Prism::RequiredParameterNode,
      Prism::OptionalParameterNode,
      Prism::RequiredKeywordParameterNode,
      Prism::OptionalKeywordParameterNode,
      Prism::BlockLocalVariableNode,
      Prism::RestParameterNode,
      Prism::KeywordRestParameterNode,
    )
  end
end
