# frozen_string_literal: true

require "test_helper"

class FilesTest < GigaChatTestCase
  def setup
    super
    stub_oauth
    @client = build_client
  end

  def multipart_body(req) = req.body.dup.force_encoding(Encoding::UTF_8)

  def test_upload_path_sends_multipart_with_mime_from_the_spec_table
    stub_request(:post, "#{API}/files").to_return(json_response({ id: "f-1", object: "file", filename: "отчёт.pdf" }))

    file = Dir.mktmpdir do |dir|
      path = File.join(dir, "отчёт.pdf")
      File.write(path, "%PDF-1.7")
      @client.files.upload(path)
    end

    assert_equal "f-1", file.id
    assert_requested(:post, "#{API}/files") do |req|
      body = multipart_body(req)
      req.headers["Content-Type"].start_with?("multipart/form-data") && body.include?('filename="отчёт.pdf"') &&
        body.include?("Content-Type: application/pdf") && body.match?(/name="purpose"\r\n\r\ngeneral/)
    end
  end

  def test_upload_normalizes_macos_nfd_filenames_to_nfc
    stub_request(:post, "#{API}/files").to_return(json_response({ id: "f-1" }))

    Dir.mktmpdir do |dir|
      path = File.join(dir, "йод.txt".unicode_normalize(:nfd))
      File.write(path, "x")
      @client.files.upload(Pathname(path))
    end

    assert_requested(:post, "#{API}/files") { |req| multipart_body(req).include?('filename="йод.txt"') }
  end

  def test_upload_io_without_a_path_needs_a_filename
    assert_raises(ArgumentError) { @client.files.upload(StringIO.new("x")) }
  end

  def test_upload_rewinds_the_io_before_a_retry
    stub_request(:post, "#{API}/files").to_return(json_response({ message: "busy" }, status: 503))
                                       .then.to_return(json_response({ id: "f-2" }))

    file = @client.files.upload(StringIO.new("hello"), filename: "hello.txt")

    assert_equal "f-2", file.id
    assert_requested(:post, "#{API}/files", times: 2) { |req| multipart_body(req).include?("hello") }
  end

  # An IO that can be read but cannot seek back. A real pipe can't be used here: multipart-post needs a
  # body length and fails on pipes before any request is made.
  class UnseekableIO < StringIO
    def pos = raise(Errno::ESPIPE)
  end

  def test_upload_from_an_unseekable_io_is_not_retried
    stub_request(:post, "#{API}/files").to_return(json_response({ message: "busy" }, status: 503))

    assert_raises(GigaChat::ServerError) { @client.files.upload(UnseekableIO.new("data"), filename: "stream.txt") }
    assert_requested(:post, "#{API}/files", times: 1)
  end

  def test_list_retrieve_delete_and_content
    stub_request(:get, "#{API}/files").to_return(json_response({ data: [{ id: "f-1", filename: "a.txt" }] }))
    stub_request(:get, "#{API}/files/f-1").to_return(json_response({ id: "f-1", access_policy: "private" }))
    stub_request(:post, "#{API}/files/f-1/delete").to_return(json_response({ id: "f-1", deleted: true }))
    stub_request(:get, "#{API}/files/f-1/content").to_return(status: 200, body: "\x89PNG\r\n".b,
                                                             headers: { "Content-Type" => "application/octet-stream" })

    assert_equal ["f-1"], @client.files.list.map(&:id)
    assert_equal "private", @client.files.retrieve("f-1").access_policy
    assert_predicate @client.files.delete("f-1"), :deleted?
    content = @client.files.content("f-1")

    assert_equal Encoding::ASCII_8BIT, content.encoding
    assert content.start_with?("\x89PNG".b), "content must be the raw bytes"
  end

  def test_mime_types_follow_the_spec_table
    assert_equal "application/vnd.ms-excel", GigaChat::Internal::MimeTypes.for("report.XLSX")
    assert_equal "audio/x-m4a", GigaChat::Internal::MimeTypes.for("voice.m4a")
    assert_equal "application/octet-stream", GigaChat::Internal::MimeTypes.for("data.bin")
  end
end
