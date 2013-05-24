#
#--
# ripfix (IPFIX for Ruby) (c) 2010 Brian Trammell and Hitachi Europe SAS
# Special thanks to the PRISM Consortium (fp7-prism.eu) for its support.
# Distributed under the terms of the GNU Lesser General Public License v3.
#++
# Defines classes for implementing Collecting Processes and File Readers
#

require_relative 'message'
require_relative 'eventdispatch'
require 'socket'

module IPFIX

  class SessionTable
    extend EventDispatch
    
    event :new_session
    event :session_end
    
    def initialize(model)
      @sessions = Hash.new
      @model = model
    end
    
    def session(tuple)
      s = @sessions[tuple]
      unless s
        s = Session.new(@model)
        @sessions[tuple] = s
        post_new_session(s)
      end
      s
    end
    
    def end_session(tuple)
      s = @sessions[tuple]
      if s
        post_session_end(s)
        @sessions.delete(tuple)
      end
    end
    
  end

  class Collector
    extend EventDispatch
    include Enumerable
    
    event :new_message

    attr_reader :model
    attr_reader :session
    attr_reader :message
    attr_reader :source
    
    def initialize(source, model)
      @model = model
      @session = Session.new(model)
      @message = Message.new(session, 0)
      @source = source
    end
    
    def each
      while @message.read(@source)
        post_new_message(@message)
        @message.each { |h, m| yield(h, m) }
      end
    end
    
    def close
      @source.close
    end
    
  end

  class FileReader < Collector
    
    def self.open(filename, model)
      cp = FileReader.new(filename, model)
      yield cp
    ensure
      cp.close
    end
    
    def initialize(filename, model)
      if (filename == "-")
        super(STDIN,model)
      else
        super(File.new(filename,"r"),model)
      end
    end
    
  end

  class TCPCollectorServer < TCPServer

    def initialize(host, port, model)
      super(host, port)
      @model = model
    end

    def next_collector
      Collector.new(accept, @model)
    end

  end
  
  class TCPSingleCollector < Collector
    
    def initialize(host, port, model)
      super(TCPServer.new(host,port).accept, model)
    end

  end

  class UDPCollector
    extend EventDispatch
    
    event :new_message
    attr_reader :session_table
    
    def self.open(host, port, model)
      begin
        cp = UDPCollector.new(host, port, model)
        yield ep
      ensure
        ep.close
      end
    end

    def initialize(host, port, model)
      @session_table = SessionTable.new(model)
      @source = UDPSocket.new()
      @source.bind(host, port)
      @interrupt_count = 0
      
      @source.setsockopt(:SOCKET, :SO_RCVBUF, 1024 * 1024)
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
      while (!check_interrupt)
        (msgbytes,tuple) = @source.recvfrom(65535)
        message = IPFIX::Message.new(@session_table.session(tuple), msgbytes)
        post_new_message(message)
        message.each { |h, m| yield(h, m) }
      end
    end

    def close
      @source.close
    end
    
  end

end # module IPFIX