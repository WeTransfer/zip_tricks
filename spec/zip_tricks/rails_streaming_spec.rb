require 'spec_helper'

describe ZipTricks::RailsStreaming do
  it 'calls the requisite controller methods' do
    class FakeController
      include ZipTricks::RailsStreaming
      attr_reader :response
      attr_accessor :response_body
      def initialize
        @response = Struct.new(:headers).new({})
      end

      def send_stream(filename:, type:, disposition:)
        out = StringIO.new
        @response.headers['Content-Type'] = type
        yield(out)
        @response_body = out
        @response_body.rewind
      end

      def stream_zip
        zip_tricks_stream(auto_rename_duplicate_filenames: true) do |z|
          z.write_deflated_file('hello.txt') do |f|
            f << 'ßHello from Rails'
          end
        end
      end
    end

    ctr = FakeController.new
    ctr.stream_zip
    response = ctr.response
    response_body = ctr.response_body

    expect(response.headers['Content-Type']).to eq('application/zip')
    expect(response.headers['X-Accel-Buffering']).to eq('no')

    ref = StringIO.new('', 'wb')
    ZipTricks::Streamer.open(ref) do |z|
      z.write_deflated_file('hello.txt') do |f|
        f << 'ßHello from Rails'
      end
    end

    out = StringIO.new('', 'wb')
    response_body.each.reduce(out, :<<)
    expect(out.string).to eq(ref.string)
  end
end
