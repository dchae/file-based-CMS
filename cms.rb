require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"
require "date"

SUPPORTED_DOCTYPES = %w[.md .txt].freeze
SUPPORTED_IMAGETYPES = %w[.jpg .jpeg .png .gif].freeze

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
  set :erb, :escape_html => true
end

before do
  session[:messages] ||= []
  @users_hash = load_users || {}
  add_user("admin", "secret")
end

helpers do
  def render_md(md_text)
    Redcarpet::Markdown.new(Redcarpet::Render::HTML).render(md_text)
  end
end

def file_path(filename = nil, subfolder = "data")
  if ENV["RACK_ENV"] == "test"
    subfolder = "test/" + subfolder
  else
    subfolder = "/" + subfolder
  end
  filename = File.basename(filename) if filename
  File.join(*[File.expand_path("..", __FILE__), subfolder, filename].compact)
end

def create_file(filename, file_content = "")
  File.open(file_path(filename), "w") { |f| f.write(file_content) }
  history = { cur_time => file_content }
  write_file_history(filename, history)
end

def delete_file(filename)
  File.delete(file_path(filename))
  File.delete(file_path(history_filename(filename)))
end

def valid_filename(filename)
  # for validating names of files to be created
  extension = File.extname(filename).downcase
  SUPPORTED_DOCTYPES.include?(extension)
end

def valid_filename_upload(filename)
  # for validating files to be uploaded
  extension = File.extname(filename).downcase
  (SUPPORTED_DOCTYPES + SUPPORTED_IMAGETYPES).include?(extension)
end

def redirect_unless_supported_doctype(filename)
  unless SUPPORTED_DOCTYPES.include?(File.extname(filename))
    status 422
    session[:messages] << "Invalid Filetype"
    redirect "/"
  end
end

def render_content(path)
  content = File.read(path)
  ext = File.extname(path)
  case
  when ext == ".md"
    erb render_md(content)
  when ext == ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when SUPPORTED_IMAGETYPES.include?(ext)
    send_file path
  else
    status 422
    session[:messages] << "Invalid Filetype"
    not_found
  end
end

def load_users(filename = "users.yml")
  path = file_path("users.yml", "private")
  YAML.load_file(path) if File.file?(path)
end

def add_user(username, secret)
  unless @users_hash[username]
    @users_hash[username] = BCrypt::Password.create(secret).to_s
    File.open(file_path("users.yml", "private"), "w") { |f| f.write(@users_hash.to_yaml) }
  end
end

def valid_user?(username, password)
  @users_hash[username] && BCrypt::Password.new(@users_hash[username]) == password
end

def signed_in?
  session[:username] && !session[:username].empty?
end

def redirect_unless_signed_in(location = "/")
  unless signed_in?
    session[:messages] << "You must be signed in to do that."
    redirect location
  end
end

get "/users/signup" do
  erb :signup
end

post "/users/signup" do
  username, password = params[:username], params[:password]
  if @users_hash[username]
    session[:messages] << "This user already exists. Please try a different username or sign in."
    status 422
    erb :signup
  else
    add_user(username, password)
    session[:username] = username
    session[:messages] << "Thank you for signing up!"
    redirect "/"
  end
end

get "/users/signin" do
  erb :signin
end

post "/users/signin" do
  if valid_user?(params[:username], params[:password])
    session[:username] = params[:username]
    session[:messages] << "Welcome!"
    redirect "/"
  else
    session[:messages] << "Invalid credentials."
    status 422
    erb :signin
  end
end

post "/users/signout" do
  session.delete(:username)
  session[:messages] << "You have been signed out."
  redirect "/"
end

def reject_unsupported(index)
  supported = SUPPORTED_DOCTYPES + SUPPORTED_IMAGETYPES
  index.select { |fn| supported.include?(File.extname(fn)) && !fn.start_with?(".") }.sort
end

get "/" do
  @page_title = "File-based CMS"
  @index = reject_unsupported(Dir.children(file_path))

  erb :index, layout: :layout
end

get "/new" do
  redirect_unless_signed_in

  erb :new_document
end

post "/new" do
  redirect_unless_signed_in

  filename = params[:filename].strip
  if valid_filename(filename)
    create_file(filename)
    file_history = { cur_time => "" }
    write_file_history(filename, file_history)
    session[:messages] << "#{filename} was created."
    redirect "/"
  else
    session[:messages] << "Not a valid filename."
    status 422
    erb :new_document
  end
end

get "/upload" do
  redirect_unless_signed_in

  erb :upload
end

post "/upload" do
  redirect_unless_signed_in

  filename = params[:upload][:filename]
  if !valid_filename_upload(filename)
    session[:messages] << "Unsupported filetype. Supported filetypes: #{(SUPPORTED_DOCTYPES + SUPPORTED_IMAGETYPES).join(", ")}."

    erb :upload
  else
    file = params[:upload][:tempfile]

    file_history = { cur_time => file.read }
    file.rewind
    write_file_history(filename, file_history)
    File.open(file_path(filename), "wb") { |f| f.write(file.read) }

    redirect "/"
  end
end

get "/:filename" do |filename|
  @page_title = filename
  path = file_path(filename)

  unless File.file?(path)
    session[:messages] << "#{filename} does not exist."
    pass
  end

  render_content(path)
end

def history_filename(filename)
  ".#{filename.gsub(/\./, "_")}.yml"
end

def load_history(filename)
  path = file_path(history_filename(filename))
  write_file_history(filename, {}) unless File.file?(path)
  YAML.load_file(path)
end

def write_file_history(filename, history)
  File.open(file_path(history_filename(filename)), "w") { |f| f.write(history.to_yaml) }
end

def last_version(file_history)
  if file_history.empty?
    file_history[cur_time] = "File history initialised."
  end
  file_history.to_a.last.last
end

def cur_time
  DateTime.now.strftime("%Y%m%d-%H:%M:%S")
end

def time_id
  id = cur_time
  id += "-1" if @file_history[id]
  while @file_history[id]
    id.next!
  end
  id
end

get "/:filename/edit" do |filename|
  redirect_unless_signed_in
  redirect_unless_supported_doctype(filename)

  @filename = filename
  timestamp = params[:version]
  @page_title = "Edit " + filename
  @file_history = load_history(filename)
  @cur_content = @file_history[timestamp] || File.read(file_path(filename))
  erb :edit
end

post "/:filename" do |filename|
  redirect_unless_signed_in
  @filename = filename
  @file_history = load_history(filename)
  new_filename = params[:new_filename] || filename
  old_file_ext = File.extname(filename)
  new_file_ext = File.extname(new_filename)
  if new_file_ext == old_file_ext
    if new_filename != filename
      File.rename(file_path(filename), file_path(new_filename))
      File.rename(file_path(history_filename(filename)), file_path(history_filename(new_filename)))
    end
    if last_version(@file_history) != params[:new_content]
      File.open(file_path(new_filename), "w") { |f| f.write(params[:new_content]) }

      @file_history[time_id] = params[:new_content]
      write_file_history(new_filename, @file_history)
    end
    session[:messages] << "#{new_filename} has been updated."
    redirect "/"
  else
    session[:messages] << "File extension cannot change."
    status 422
    erb :edit
  end
end

post "/:filename/duplicate" do |filename|
  redirect_unless_signed_in
  file_content = File.open(file_path(filename), "r") { |f| f.read }
  create_file(File.basename(filename, ".*") + " copy" + File.extname(filename), file_content)
  session[:messages] << "#{filename} was duplicated."
  redirect "/"
end

post "/:filename/delete" do |filename|
  redirect_unless_signed_in

  delete_file(filename)
  session[:messages] << "#{filename} has been deleted."
  redirect "/"
end

not_found do
  redirect "/"
end
