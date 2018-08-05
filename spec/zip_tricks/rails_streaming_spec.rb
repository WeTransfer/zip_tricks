require 'spec_helper'

describe ZipTricks::RailsStreaming do
  it 'calls the requisite controller methods' do
    class FakeController
      include ZipTricks::RailsStreaming
      attr_reader :response
      def initialize
        @response = Struct.new(:headers, :stream).new({}, StringIO.new)
      end

      def stream_zip
        zip_tricks_stream do |z|
          z.write_deflated_file('hello.txt') do |f|
            f << 'ßHello from Rails'
          end
        end
      end
    end

    ctr = FakeController.new
    ctr.stream_zip
    response = ctr.response

    expect(response.headers['Content-Type']).to eq('application/zip')
    expect(response.headers['X-Accel-Buffering']).to eq('no')
    output_stream = response.stream
    expect(output_stream).to be_closed
    expect(output_stream.string).not_to be_empty
  end
end
