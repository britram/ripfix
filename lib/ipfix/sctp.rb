#
#--
# ripfix (IPFIX for Ruby) (c) 2010 Brian Trammell and Hitachi Europe SAS
# Special thanks to the PRISM Consortium (fp7-prism.eu) for its support.
# Distributed under the terms of the GNU Lesser General Public License v3.
#++
# Provides SCTP support for IPFIX, given SCTP::Endpoint. 
# Doesn't even parse yet.
#

require_relative 'message'
require_relative 'exporter'
require_relative 'collector'
require_relative '../sctp/endpoint'

module IPFIX
  
  class SCTPMessage < Message
    attr_accessor :stream
    attr_accessor :host
    attr_accessor :port

    def initialize (dos = nil, host = nil, port = nil, stream = nil, ctx = nil)
      if ctx.respond_to? :session
        session = ctx.session([host,port])
      else
        session = ctx
      end
      
      super(session, dos)
      
      @stream = stream
      @host = host
      @port = port
    end
    
  end # class SCTPMessage

  class SCTPExporter < Exporter
    
    def self.open(host, port, model, domain)
      begin
        ep = SCTPExporter.new(host, port, model, domain)
        yield ep
      ensure
        ep.close
      end
    end
  
    def initialize(host, port, model, domain)
      @sink = SCTP::Endpoint.new(nil, nil, {one_to_many: true})
      @model = model
      @session = Session.new(model)
      @message = SCTPMessage.new(domain, host, port, 0, @session)
    end
    
    def stream=(stream)
      if (@message.stream != stream)
        flush
        @message.stream = stream
      end
    end

    def domain=(domain)
      if (@message.domain != domain)
        flush
        @message.stream = stream
      end
    end
    
    def flush(export_time = nil)
      @message.export_time = export_time
      @sink.sendmsg(@message)
      @message.reset
    end
    
  end # class SCTPExporter

  class SCTPCollector
    extend EventDispatch
    
    event :new_message
    attr_reader :session_table

    def self.open(host, port, model)
      begin
        cp = SCTPCollector.new(host, port, model)
        yield ep
      ensure
        ep.close
      end
    end

    def initialize(host, port, model)
      @session_table = SessionTable.new(model)
      @source = SCTP::Endpoint.new(host, port, {passive: true, one_to_many: true})
      @source.message_class = IPFIX::SCTPMessage
      @source.message_context = @session_table
      @source.on_association_down do |host, port|
        @session_table.end_session([host, port])
      end
      @interrupt_count = 0
    end
    
    def interrupt
      @interrupt_count += 1
    end
    
    def check_interrupt
      if (@interrupt_count > 0) 
        @interrupt_count -= 1
        true
      else
        false
      end
    end

    def each
      while (!check_interrupt && message = @source.recvmsg)
        post_new_message(message)
        message.each { |h, m| yield(h, m) }
      end
    end

    def close
      @source.close
    end
    
  end

end
