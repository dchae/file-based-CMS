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

def abs_path(filename=nil, subfolder="data" )
  [File.expand_path("..", __FILE__), subfolder, filename].compact.join("/")
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
  @index = Dir.children(abs_path).sort
  erb :index, layout: :layout
end

get "/:filename" do |filename|
  path = abs_path(filename)

  unless File.file?(path)
    session[:messages] << "#{filename} does not exist."
    pass
  end

  render_content(path)
end

get "/:filename/edit" do |filename|
  @cur_content = File.read(abs_path(filename))
  @filename = filename
  erb :edit
end

post "/:filename" do |filename|
  File.open(abs_path(filename), "w") { |f| f.write(params[:new_content])}
  session[:messages] << "#{filename} has been updated."
  redirect "/"
end

not_found do
  redirect "/"
end
