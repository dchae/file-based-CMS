require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "redcarpet"

configure do
  enable :sessions
  set :session_secret, SecureRandom.hex(32)

end

before do
  session[:messages] ||= []
  @data_path = File.expand_path("..", __FILE__) + "/data"
end

helpers do
  def render_md(md_text)
    Redcarpet::Markdown.new(Redcarpet::Render::HTML).render(md_text)
  end
end

def extension(fn)
  fn.match(/(?<=\.)[a-z0-9]+/i).to_s
end

def load_file(filename)
  case extension(filename)
  when "md"
    markdown_content = File.read(@path)
    render_md(markdown_content)
  when "txt"
    headers["Content-Type"] = "text/plain"
    File.read(@path)
  else
    send_file @path
  end
end

get "/" do
  @page_title = "File-based CMS"
  @index = Dir.children(@data_path).sort
  erb :index, layout: :layout
end

get "/:filename" do |filename|
  @path = @data_path + "/#{filename}"

  unless File.file?(@path)
    session[:messages] << "#{filename} does not exist."
    pass
  end

  load_file(filename)
end

not_found do
  redirect "/"
end
