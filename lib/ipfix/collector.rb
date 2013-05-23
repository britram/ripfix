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

  #
  # FIXME doesn't work yet -- refactor ripcollect into this
  #
  class CollectorTool

    def initialize(args)
        @tcpmode = false
        @udpmode = false
        @sctpmode = false
        @v9mode = false
        @modelfiles = Array.new
        @fixfile = "-"
        @host = nil
        @port = nil
        
        @cs = nil
        @c = nil
    end

    def parse_args(args)
      postargs = Array.new
      
      while arg = args.shift
        if (/^-m/.match(arg))
          parse_model = true
          parse_file = false
          parse_spec = false
        elsif (/^-f/.match(arg))
          parse_model = false
          parse_file = true
          parse_spec = false
        elsif (/^-s/.match(arg))
          @sctpmode = true
          parse_model = false
          parse_file = false
          parse_spec = true
        elsif (/^-t/.match(arg))
          @tcpmode = true
          parse_model = false
          parse_file = false
          parse_spec = true
        elsif (/^-u/.match(arg))
          @udpmode = true
          parse_model = false
          parse_file = false
          parse_spec = true
        elsif (/^-9/.match(arg))
          @v9mode = true
          parse_model = false
          parse_file = false
          parse_spec = false          
        elsif parse_spec && (argm = /([^:]*)\:(\d+)/.match(arg))
          @host = argm[1].length > 0 ? argm[1] : nil
          @port = argm[2].to_i
        elsif parse_model
          @modelfiles << arg
        elsif parse_file
          @fixfile = arg
        else
          postargs << arg
        end
      end
      
      postargs
    end
    
    def start
      # load information model
      model = InfoModel.new.load_default.load_reverse
      @modelfiles.each do |modelfile| 
        STDERR.puts("loading information model file #{modelfile}")
        model.load(modelfile)
      end
      
      # create collector or collector server
      if @tcpmode
        @c = TCPSingleCollector.new(host, port, model)
      elsif @udpmode
        @c = UDPCollector.new(host, port, model)
      elsif @sctpmode
        require 'ipfix/sctp'
        @c = SCTPCollector.new(host, port, model)
      elsif @v9mode
        require 'ipfix/v9pdu'
        @c = V9FileReader.new(@fixfile, model)
      else 
        @c = FileReader.new(@fixfile, model)
      end
      
      # handle signals for shutdown
      cleanup = Proc.new do
        STDERR.puts("Terminating")
        STDERR.puts("got #{msgcount} messages, #{tmplcount} templates, #{reccount} records")
        c.close
      end

      Signal.trap("TERM", cleanup)
      Signal.trap("INT", cleanup)
    end
    
    def on_template_add(&handler)
      if @c.respond_to?(:session)
        @c.session.set_template_add_proc(handler)
      else
        @c.session_table.on_new_session do |s|
          set_template_add_proc(handler)
        end
      end
    end
    
    def on_missing_template(&handler)
      if @c.respond_to?(:session)
        @c.session.set_missing_template_proc(handler)
      else
        @c.session_table.on_new_session do |s|
          s.set_missing_template_proc(handler)
        end
      end
    end
    
    def on_bad_sequence(&handler)
      if @c.respond_to?(:session)
        @c.session.set_bad_sequence_proc(handler)
      else
        @c.session_table.on_new_session do |s|
          s.set_bad_sequence_proc(handler)
        end
      end
    end
    
    def on_new_message(&handler)
      @c.set_new_message_proc(handler)
    end

    def each
      @c.each do { |h, m| yield h, m }
    end

  end

end # module IPFIX