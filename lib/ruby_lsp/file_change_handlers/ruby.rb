# typed: strict
# frozen_string_literal: true

module RubyLsp
  module FileChangeHandlers
    class Ruby
      class << self
        extend T::Sig
        sig { params(store: Store, index: RubyIndexer::Index, file_path: String, change_type: Integer).void }
        def change(store, index, file_path, change_type)
          load_path_entry = $LOAD_PATH.find { |load_path| file_path.start_with?(load_path) }
          uri = URI::Generic.from_path(load_path_entry: load_path_entry, path: file_path)

          case change_type
          when Constant::FileChangeType::CREATED
            content = File.read(file_path)
            # If we receive a late created notification for a file that has already been claimed by the client, we want to
            # handle change for that URI so that the require path tree is updated
            store.key?(uri) ? index.handle_change(uri, content) : index.index_single(uri, content)
          when Constant::FileChangeType::CHANGED
            content = File.read(file_path)
            # We only handle changes on file watched notifications if the client is not the one managing this URI.
            # Otherwise, these changes are handled when running the combined requests
            index.handle_change(uri, content) unless store.key?(uri)
          when Constant::FileChangeType::DELETED
            index.delete(uri)
          end
        rescue Errno::ENOENT
          # If a file is created and then delete immediately afterwards, we will process the created notification before we
          # receive the deleted one, but the file no longer exists. This may happen when running a test suite that creates
          # and deletes files automatically.
        end
      end
    end
  end
end
