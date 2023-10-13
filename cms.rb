require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
  set :erb, :escape_html => true
end

before do
  session[:messages] ||= []
  add_user("admin", "secret")
  @users_hash = load_users
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
  File.join(*[File.expand_path("..", __FILE__), subfolder, filename].compact)
end

def create_file(filename, file_content = "")
  File.open(file_path(filename), "w") { |f| f.write(file_content) }
end

def valid_filename(filename)
  !File.extname(filename).empty?
end

def render_content(path)
  content = File.read(path)
  case File.extname(path)
  when ".md"
    erb render_md(content)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  else
    send_file path
  end
end

def load_users(filename = "users.yml")
  path = file_path("users.yml", "private")
  YAML.load_file(path) || {}
end

def add_user(username, secret)
  new_users = load_users
  unless new_users[username]
    new_users[username] = BCrypt::Password.create(secret).to_s
    File.open(file_path("users.yml", "private"), "w") { |f| f.write(new_users.to_yaml) }
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

get "/" do
  @page_title = "File-based CMS"
  @index = Dir.children(file_path).sort
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
    session[:messages] << "#{filename} was created."
    redirect "/"
  else
    session[:messages] << "Not a valid filename."
    status 422
    erb :new_document
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

get "/:filename/edit" do |filename|
  redirect_unless_signed_in

  @page_title = "Edit " + filename
  @cur_content = File.read(file_path(filename))
  @filename = filename
  erb :edit
end

post "/:filename" do |filename|
  redirect_unless_signed_in

  File.open(file_path(filename), "w") { |f| f.write(params[:new_content]) }
  session[:messages] << "#{filename} has been updated."
  redirect "/"
end

post "/:filename/delete" do |filename|
  redirect_unless_signed_in

  File.delete(file_path(filename))
  session[:messages] << "#{filename} has been deleted."
  redirect "/"
end

not_found do
  redirect "/"
end
