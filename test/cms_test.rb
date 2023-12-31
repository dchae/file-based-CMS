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
    FileUtils.rm_rf(file_path("private"))
  end

  def users_setup
    default_user_hash = { "admin" => BCrypt::Password.create("secret").to_s }
    File.open(file_path("users.yml", "private"), "w") { |f| f.write(default_user_hash.to_yaml) }
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    users_setup
    { "rack.session" => { username: "admin" } }
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

  def test_index_hidden_files
    create_file("test.txt")
    create_file(".test2.txt")
    get "/"
    assert_equal(200, last_response.status)
    refute_includes(last_response.body, ".test_txt.yml")
    refute_includes(last_response.body, ".test2.txt")
  end

  def test_index_unsupported_files
    create_file("test.bin")
    create_file("test2.rtf")
    get "/"
    assert_equal(200, last_response.status)
    refute_includes(last_response.body, "test.bin")
    refute_includes(last_response.body, "test2.rtf")
  end
  def test_view_text_file
    file_content = "1993 - Yukihiro Matsumoto dreams up Ruby."
    create_file("history.txt", file_content)

    get "/history.txt"
    assert_equal(200, last_response.status)
    assert_equal("text/plain", last_response["Content-Type"])
    assert_includes(last_response.body, file_content)
  end

  def test_view_markdown_file
    file_content = "# Header 1"
    create_file("temp.md", file_content)

    get "/temp.md"
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "<h1>Header 1</h1>")
  end

  def test_file_not_found
    get "/notafile.ext"
    assert_equal(302, last_response.status)

    error_msg = "notafile.ext does not exist."
    assert_includes(session[:messages], error_msg)

    # Test error message disappears
    get last_response["Location"]
    assert_equal(200, last_response.status)

    get "/"
    refute_includes(last_response.body, error_msg)
  end

  def test_edit_file
    file_content = "This is a temporary file for testing purposes."
    create_file("temp.txt", file_content)
    # Loading edit page
    get "/temp.txt/edit", {}, admin_session
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "<textarea")
    assert_includes(last_response.body, file_content)
    assert_includes(last_response.body, '<button type="submit"')
  end

  def test_edit_file_signed_out
    file_content = "This is a temporary file for testing purposes."
    create_file("temp.txt", file_content)
    get "/temp.txt/edit"

    assert_equal(302, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(session[:messages], "You must be signed in to do that.")
  end

  def test_update_file
    # Setting up temporary test file
    file_content = "This is a temporary file for testing purposes."
    create_file("temp.txt", file_content)

    # Posting edit
    delta = "\nThis file has been edited as part of the `test_update_file` test."
    post("/temp.txt", { new_content: file_content + delta }, admin_session)

    # Test update message
    assert_includes(session[:messages], "temp.txt has been updated.")

    # Redirecting to index
    assert_equal(302, last_response.status)
    get last_response["Location"]
    assert_equal(200, last_response.status)

    # Testing that file has been changed
    get "/temp.txt"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, file_content + delta)
  end

  def test_update_file_rename
    create_file("temp.txt")

    # Posting edit
    post("/temp.txt", { new_filename: "temp_2.txt" }, admin_session)

    # Test update message
    assert_includes(session[:messages], "temp_2.txt has been updated.")

    # Redirecting to index
    assert_equal(302, last_response.status)
    get last_response["Location"]
    assert_equal(200, last_response.status)

    # Testing that file has been changed
    assert_includes(last_response.body, "temp_2.txt")
  end

  def test_update_file_rename_no_extension
    create_file("temp.txt")

    post("/temp.txt", { new_filename: "temp_2" }, admin_session)

    # Test update message
    assert_includes(last_response.body, "File extension cannot change.")

    # Test that we are still on edit page
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "Edit content of:")

    # Test that filename has not changed
    get "/"
    refute_includes(last_response.body, "temp_2")
  end

  def test_update_file_rename_different_extension
    create_file("temp.txt")

    post("/temp.txt", { new_filename: "temp_2.md" }, admin_session)

    # Test update message
    assert_includes(last_response.body, "File extension cannot change.")

    # Test that we are still on edit page
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "Edit content of:")

    # Test that filename has not changed
    get "/"
    refute_includes(last_response.body, "temp_2.md")
  end

  def test_update_file_signed_out
    create_file("temp.txt", "")
    post("/temp.txt", { new_content: "delta" })
    assert_equal(302, last_response.status)
    assert_includes(session[:messages], "You must be signed in to do that.")
    get "/temp.txt"
    refute_includes(last_response.body, "delta")
  end

  def test_load_file_history
    create_file("temp.txt", "initial content")
    post("/temp.txt", { new_content: "edit 1" }, admin_session)
    post("/temp.txt", { new_content: "edit 2" })

    keys = YAML.load_file(file_path(history_filename("temp.txt"))).keys.sort
    get("/temp.txt/edit", { version: keys[0]})
    assert_includes(last_response.body, "initial content")
    get("/temp.txt/edit", { version: keys[1]})
    assert_includes(last_response.body, "edit 1")
    get("/temp.txt/edit", { version: keys[2]})
    assert_includes(last_response.body, "edit 2")
  end

  def test_view_new_file_form
    get "/new", {}, admin_session
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "Create a new document:")
    assert_includes(last_response.body, '<button type="submit"')
  end

  def test_view_new_file_form_signed_out
    get "/new"
    assert_equal(302, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(session[:messages], "You must be signed in to do that.")
  end

  def test_create_new_file
    post("/new", { filename: "temp.txt" }, admin_session)
    assert_equal(302, last_response.status)
    # Test update message
    assert_includes(session[:messages], "temp.txt was created.")

    # Test redirect
    get last_response["Location"]
    assert_equal(200, last_response.status)
    # Test that file has been added to index
    assert_includes(last_response.body, '<a href="/temp.txt">temp.txt')
  end

  def test_create_new_file_signed_out
    post("/new", { filename: "temp.txt" })
    assert_equal(302, last_response.status)
    assert_includes(session[:messages], "You must be signed in to do that.")

    # Test redirect
    get last_response["Location"]
    assert_equal(200, last_response.status)
    # Test that file has not been added to index
    refute_includes(last_response.body, '<a href="/temp.txt">temp.txt')
  end

  def test_create_file_without_extension
    post("/new", { filename: "noextension" }, admin_session)
    assert_equal(422, last_response.status)
    # Test update message
    assert_includes(last_response.body, "Not a valid filename.")
    # Test that we are still on create file page
    assert_includes(last_response.body, "Create a new document:")
    assert_includes(last_response.body, '<button type="submit"')
  end

  def test_create_file_empty_filename
    post("/new", { filename: "" }, admin_session)
    assert_equal(422, last_response.status)
    # Test update message
    assert_includes(last_response.body, "Not a valid filename.")
    # Test that we are still on create file page
    assert_includes(last_response.body, "Create a new document:")
    assert_includes(last_response.body, '<button type="submit"')
  end

  def test_upload_file
    # Need to write test for uploading files
    # post("/upload", { enctype:"multipart/form-data" upload})
  end

  def test_duplicate_file
    create_file("temp.txt", "test content")
    post("/temp.txt/duplicate", {}, admin_session)
    assert_equal(302, last_response.status)
    assert_includes(session[:messages], "temp.txt was duplicated.")
    get last_response["Location"]
    assert_includes(last_response.body, "temp copy.txt")
    get "/temp%20copy.txt"
    assert_includes(last_response.body, "test content")
  end

  def test_delete_file
    create_file("temp.txt")
    post "/temp.txt/delete", {}, admin_session
    assert_equal(302, last_response.status)
    assert_includes(session[:messages], "temp.txt has been deleted.")

    get last_response["Location"]
    assert_equal(200, last_response.status)
    refute_includes(last_response.body, '<a href="/temp.txt">temp.txt')
  end

  def test_delete_file_signed_out
    create_file("temp.txt")

    post "/temp.txt/delete"
    assert_equal(302, last_response.status)
    assert_includes(session[:messages], "You must be signed in to do that.")

    # Test that file was not created
    get last_response["Location"]
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, '<a href="/temp.txt">temp.txt')
  end

  def test_sign_in_button
    get "/"
    assert_includes(last_response.body, '<button type="submit">Sign In')
  end

  def test_signed_in
    get "/", {}, admin_session
    assert_includes(last_response.body, "Signed in as admin")
    assert_includes(last_response.body, '<button type="submit">Sign Out')
  end

  def test_sign_in_page
    get "/users/signin"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<input")
    assert_includes(last_response.body, '<button type="submit">Sign In')
  end

  def test_sign_in
    post "/users/signin", username: "admin", password: "secret"
    assert_equal(302, last_response.status)
    assert_includes(session[:messages], "Welcome!")
    assert_equal("admin", session[:username])

    get last_response["Location"]
    assert_includes(last_response.body, "Signed in as admin")
  end

  def test_sign_in_invalid_credentials
    post "/users/signin", username: "admin", password: "notsecret"
    assert_equal(422, last_response.status)
    assert_nil(session[:username])

    assert_includes(last_response.body, "Invalid credentials")
  end

  def test_sign_out
    post "/users/signout", {}, { "rack.session" => { username: "admin" } }
    get last_response["Location"]
    assert_nil(session[:username])
    assert_includes(last_response.body, "You have been signed out.")
    assert_includes(last_response.body, '<button type="submit">Sign In')
  end
end

def test_sign_in_button
  get "/"
  assert_includes(last_response.body, '<button type="submit">Sign Up')
end

def test_sign_up_page
  get "/users/signup"
  assert_equal(200, last_response.status)
  assert_includes(last_response.body, '<button type="submit">Sign Up')
end

def test_sign_up
  post "/users/signup", username: "new_user", password: "pass123"
  assert_equal(302, last_response.status)
  assert_includes(session[:messages], "Thank you for signing up!")
  assert_equal("new_user", session[:username])

  get last_response["Location"]
  assert_includes(last_response.body, "Signed in as new_user")
end

def test_sign_up_invalid_credentials
  post "/users/signup", username: "admin", password: "notsecret"
  assert_equal(422, last_response.status)
  assert_nil(session[:username])

  assert_includes(last_response.body, "This user already exists. Please try a different username or sign in.")
end
