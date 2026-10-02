# frozen_string_literal: true

module GigaChat
  module Resources
    class Files < Base
      def upload(file, purpose: "general", filename: nil, content_type: nil, request_options: {})
        io, name, owned = open_upload(file, filename)
        part = Faraday::Multipart::FilePart.new(io, content_type || Internal::MimeTypes.for(name), name)
        @client.request(method: :post, path: "files", form: { file: part, purpose: }, type: Types::FileObject,
                        request_options:)
      ensure
        io.close if owned && io
      end

      def list(request_options: {})
        @client.request(method: :get, path: "files", type: Types::FileList, request_options:)
      end

      def retrieve(id, request_options: {})
        @client.request(method: :get, path: "files/#{escape(id)}", type: Types::FileObject, request_options:)
      end

      # The API deletes with POST /files/{id}/delete, not DELETE.
      def delete(id, request_options: {})
        @client.request(method: :post, path: "files/#{escape(id)}/delete", type: Types::FileDeleted, request_options:)
      end

      def content(id, request_options: {})
        @client.request(method: :get, path: "files/#{escape(id)}/content", headers: { "Accept" => "*/*" },
                        binary: true, request_options:)
      end

      private

      # Returns [io, filename, owned]; `owned` IOs are opened here and closed after the request.
      def open_upload(file, filename)
        case file
        when String, Pathname
          path = Pathname(file)
          [path.open("rb"), nfc(filename || path.basename.to_s), true]
        else
          raise ArgumentError, "file must be a path or an IO-like object" unless file.respond_to?(:read)

          name = filename || (File.basename(file.path) if file.respond_to?(:path) && file.path)
          raise ArgumentError, "filename: is required when the IO has no path" if name.to_s.empty?

          [file, nfc(name), false]
        end
      end

      # macOS returns NFD names from the file system ("й" as "и" + U+0306); send the composed form.
      def nfc(name) = name.unicode_normalize(:nfc)
    end
  end
end
