ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(file_path)
  end

  def teardown
    FileUtils.rm_rf(file_path)
  end

  def test_index
    create_file("temp1.md")
    create_file("temp2.txt")
    get "/"
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "temp1.md")
    assert_includes(last_response.body, "temp2.txt")
  end

  def test_view_text_file
    file_content = "1993 - Yukihiro Matsumoto dreams up Ruby."
    create_file("history.txt", file_content )

    get "/history.txt"
    assert_equal(200, last_response.status)
    assert_equal("text/plain", last_response["Content-Type"])
    assert_includes(last_response.body, file_content )
  end

  def test_view_markdown_file
    file_content = "# Header 1"
    create_file("temp.md", file_content )

    get "/temp.md"
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "<h1>Header 1</h1>")
  end

  def test_file_not_found
    get "/notafile.ext"
    assert_equal(302, last_response.status)

    get last_response["Location"]
    assert_equal(200, last_response.status)

    error_msg = "notafile.ext does not exist."
    assert_includes(last_response.body, error_msg)

    get "/"
    refute_includes(last_response.body, error_msg)
  end

  def test_edit_file
    file_content = "This is a temporary file for testing purposes."
    create_file("temp.txt", file_content)
    # Loading edit page
    get "/temp.txt/edit"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<textarea")
    assert_includes(last_response.body, file_content )
    assert_includes(last_response.body, '<button type="submit"')
  end

  def test_update_file
    # Setting up temporary test file
    file_content = "This is a temporary file for testing purposes."
    create_file("temp.txt", file_content)

    # Posting edit
    delta = "\nThis file has been edited as part of the `test_update_file` test."
    post "/temp.txt", new_content: file_content + delta

    # Redirecting to index
    assert_equal(302, last_response.status)
    get last_response["Location"]
    assert_equal(200, last_response.status)

    # Test update message
    assert_includes(last_response.body, "temp.txt has been updated.")

    # Testing that file has been changed
    get "/temp.txt"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, file_content + delta)
  end
end
