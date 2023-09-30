require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "redcarpet"

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)
  set :erb, :escape_html => true
end

before do
  session[:messages] ||= []
end

helpers do
  def render_md(md_text)
    Redcarpet::Markdown.new(Redcarpet::Render::HTML).render(md_text)
  end
end

def file_path(filename = nil, subfolder = nil)
  if subfolder.nil?
    if ENV["RACK_ENV"] == "test"
      subfolder = "test/data"
    else
      subfolder = "data"
    end
  end
  File.join(*[File.expand_path("..", __FILE__), subfolder, filename].compact)
end

def create_file(filename, file_content = "")
  File.open(file_path(filename), "w") { |f| f.write(file_content) }
end

def render_content(path)
  content = File.read(path)
  case File.extname(path)
  when ".md"
    render_md(content)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  else
    send_file path
  end
end

get "/" do
  @page_title = "File-based CMS"
  @index = Dir.children(file_path).sort
  erb :index, layout: :layout
end

get "/:filename" do |filename|
  path = file_path(filename)

  unless File.file?(path)
    session[:messages] << "#{filename} does not exist."
    pass
  end

  render_content(path)
end

get "/:filename/edit" do |filename|
  @cur_content = File.read(file_path(filename))
  @filename = filename
  erb :edit
end

post "/:filename" do |filename|
  File.open(file_path(filename), "w") { |f| f.write(params[:new_content]) }
  session[:messages] << "#{filename} has been updated."
  redirect "/"
end

not_found do
  redirect "/"
end
