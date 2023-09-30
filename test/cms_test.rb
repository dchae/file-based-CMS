ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_index
    get "/"
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_match(/about\.md/, last_response.body)
    assert_match(/changes\.txt/, last_response.body)
    assert_match(/history\.txt/, last_response.body)
  end

  def test_file_history
    get "/history.txt"
    assert_equal(200, last_response.status)
    assert_equal("text/plain", last_response["Content-Type"])

    first_line = "1993 - Yukihiro Matsumoto dreams up Ruby."
    last_line = "2022 - Ruby 3.2 released."
    assert_includes(last_response.body, first_line)
    assert_includes(last_response.body, last_line)
  end

  def test_file_not_found
    get "/notafile.ext"
    assert_equal(302, last_response.status)
    get last_response["Location"]
    assert_equal(200, last_response.status)
    error_msg = "notafile.ext does not exist."
    assert_includes(last_response.body, error_msg)
    get "/"
    error_msg = "notafile.ext does not exist."
    refute_includes(last_response.body, error_msg)
  end

  def test_edit_file
    # Loading edit page
    get "/history.txt/edit"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<textarea")
    first_line = "1993 - Yukihiro Matsumoto dreams up Ruby."
    last_line = "2022 - Ruby 3.2 released."
    assert_includes(last_response.body, first_line)
    assert_includes(last_response.body, last_line)
    assert_includes(last_response.body, '<button type="submit"')
  end

  def test_update_file
    # Setting up temporary test file
    temp_file_path = File.expand_path("../..", __FILE__) + "/data/temp.txt"
    file_content = "This is a temporary file for testing purposes."
    File.open(temp_file_path, "w") { |f| f.write(file_content) }

    # Posting edit
    delta = "\nThis file has been edited as part of the `test_edit_file` test."
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

    # Cleanup temp file
    File.delete(temp_file_path)
  end
end
