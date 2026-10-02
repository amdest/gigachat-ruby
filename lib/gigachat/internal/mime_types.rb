# frozen_string_literal: true

module GigaChat
  module Internal
    # Upload MIME types exactly as the spec's file-storage table lists them (`xlsx` really is
    # application/vnd.ms-excel there). `jpg` and `tif` are aliases the table does not spell out.
    module MimeTypes
      TYPES = {
        "txt" => "text/plain", "doc" => "application/msword",
        "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "pdf" => "application/pdf", "epub" => "application/epub", "ppt" => "application/ppt",
        "pptx" => "application/pptx", "xlsx" => "application/vnd.ms-excel",
        "jpeg" => "image/jpeg", "jpg" => "image/jpeg", "png" => "image/png", "tiff" => "image/tiff",
        "tif" => "image/tiff", "bmp" => "image/bmp",
        "mp4" => "audio/mp4", "mp3" => "audio/mp3", "m4a" => "audio/x-m4a", "wav" => "audio/x-wav",
        "weba" => "audio/webm", "ogg" => "audio/x-ogg", "opus" => "audio/opus"
      }.freeze
      DEFAULT = "application/octet-stream"

      def self.for(filename) = TYPES.fetch(File.extname(filename.to_s).delete_prefix(".").downcase, DEFAULT)
    end
  end
end
