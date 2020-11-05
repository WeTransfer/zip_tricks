require 'spec_helper'

describe ZipTricks::RailsStreaming do
  it 'calls the requisite controller methods' do
    class FakeController
      include ZipTricks::RailsStreaming
      attr_reader :response
      attr_accessor :response_body
      def initialize
        @response = Struct.new(:headers, :sending_file).new({})
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
    expect(response.sending_file).to be(true)

    ref = StringIO.new('', 'wb')
    ZipTricks::Streamer.open(ref) do |z|
      z.write_deflated_file('hello.txt') do |f|
        f << 'ßHello from Rails'
      end
    end

    expect(ZipTricks::Streamer).to receive(:new).with(any_args, auto_rename_duplicate_filenames: true).and_call_original

    out = StringIO.new('', 'wb')
    response_body.each.reduce(out, :<<)
    expect(out.string).to eq(ref.string)
  end
end
