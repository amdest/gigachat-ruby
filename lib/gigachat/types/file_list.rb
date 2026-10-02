# frozen_string_literal: true

module GigaChat
  module Types
    class FileList < Base
      enumerable :data, FileObject
    end
  end
end
