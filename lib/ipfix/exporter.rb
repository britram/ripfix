#
#--
# ripfix (IPFIX for Ruby) (c) 2010 Brian Trammell and Hitachi Europe SAS
# Special thanks to the PRISM Consortium (fp7-prism.eu) for its support.
# Distributed under the terms of the GNU Lesser General Public License v3.
#++
# Defines classes for implementing Exporting Processes and File Writers
#


require_relative 'message'
require 'socket'

module IPFIX
  
  class Exporter

    attr_reader :model
    attr_reader :session
    attr_reader :message
    attr_reader :sink

    def initialize(sink, model, domain)
      @sink = sink
      @model = model
      @session = Session.new(model)
      @message = Message.new(session, domain)
    end
    
    def flush(export_time = nil)
      @message.export_time = export_time
      s = @message.string
      #STDERR.puts("Writing message:\n "+Buffer::dump(s.bytes.to_a))
      @sink.write(s)
      @message.reset(@message.domain,@message.sequence)
    end

    def domain
      @message.domain
    end

    def domain=(domain)
      if (@message.domain != domain)
        if @message.record_count > 0
          flush
        end
        @message.reset(domain,@message.sequence)
      end
    end

    def <<(thing)
      begin
        #STDERR.puts("Exporter: Appending #{thing} to #{@message.inspect}")
        @message << thing
      rescue EndOfBuffer => e
        #STDERR.puts("Exporter: Overrun on #{@message.inspect}, message flush")
        flush
        #STDERR.puts("Exporter: Appending #{thing} to new #{@message.inspect}")
        @message << thing
      end
        @message
    end

    def close
      flush if (@message.record_count > 0)
      @sink.close
    end
  end
  
  class FileWriter < Exporter
    
    def self.open(filename, model, domain)
      ep = FileWriter.new(filename, model, domain)
      yield ep
    ensure
      ep.close
    end
    
    def initialize(filename, model, domain)
      if (filename == "-")
        super(STDOUT, model, domain)
      else
        super(File.new(filename,"w"), model, domain)
      end
    end

  end
  
  class TCPExporter < Exporter

    def self.open(host, port, model, domain)
      ep = TCPExporter.new(host, port, model, domain)
      yield ep
    ensure
      ep.close
    end
    
    def initialize (host, port, model, domain)
      super(TCPSocket.new(host, port), model, domain)
    end
    
  end
  
  class UDPExporter < Exporter

    def self.open(host, port, model, domain)
      ep = UDPExporter.new(host, port, model, domain)
      yield ep
    ensure
      ep.close
    end
    
    def initialize (host, port, model, domain)
      sock = UDPSocket.new()
      sock.connect(host,port)
      super(sock, model, domain)
    end
    
  end

  
end
