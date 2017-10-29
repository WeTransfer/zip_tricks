# frozen_string_literal: true

require File.dirname(__FILE__) + '/rack_application.rb'

# Demonstrates a Rack app that can offer a ZIP download composed
# at runtime (see rack_application.rb)
run ZipDownload.new
