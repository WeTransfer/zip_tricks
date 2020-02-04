# Serve the test directory, where we are going to emit the ZIP file into.
# Rack::File provides built-in support for Range: HTTP requests.
run Rack::File.new(Dir.pwd)
