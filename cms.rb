require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"

before do
  @data_path = File.expand_path("..", __FILE__) + "/data"
end

get "/" do
  @page_title = "File-based CMS"
  @index = Dir.children(@data_path).sort

  erb :index
end

get "/:filename" do |filename|
  @path = @data_path+ "/#{filename}"
  not_found unless File.file?(@path)
  headers["Content-Type"] = "text/plain"
  File.read(@path)#.split("\n").join("<br>")
end

not_found do
  "File or page not found."
end
