if ENV['CI']
  require "codeclimate-test-reporter"
  CodeClimate::TestReporter.start
end

VCR.configure do |config|
  config.ignore_hosts 'codeclimate.com' if ENV['CI']
  config.cassette_library_dir = File.join(ManageIQ::Providers::Amazon::Engine.root, 'spec/vcr_cassettes')
end
# VCR.configure do |c|
#   c.after_http_request do |request, response|
#     if request.method == :post
#       puts "POST Request:#{request.uri}"
#       puts "#{request.to_hash}" # or request.body
#     end
#   end
  # c.allow_http_connections_when_no_cassette = true
# end
