require 'stringio'
require_relative '../ipfix/eventdispatch'
require_relative '../../ext/sctp/endpoint'

module SCTP

  class Message < StringIO
  
    attr_accessor :host
    attr_accessor :port
    attr_accessor :stream
    attr_accessor :context
    
    def initialize(string = nil, host = nil, port = nil, stream = 0, context = nil)
      super(string)
      @host = host
      @port = port ? port.to_s : nil
      @stream = stream
      @context = context
    end
  end

  class Endpoint
    extend EventDispatch
    
    event :association_up
    event :association_down
    event :send_failed
    
    attr_reader :peer_host
    attr_reader :peer_port
    
    attr_accessor :message_class, :message_context
    
    private :llinit, :llconnect, :llblock=, :llblock?
    private :llbind, :lllisten, :llaccept, :llclose
    private :lladdrsock, :llsockaddr
    private :llsendmsg, :llrecvmsg

    Maxbuf = 65536
    Backlog = 4
    
    def initialize(host = nil, port = nil, opts = {})
      # Do a low-level init of the socket
      llinit(opts)
      
      # Set the class to initialize on recvmsg
      @message_class = Message
      
      # Set the context object to hand to newly created messages
      @message_context = nil
      
      # By default, no stored peer host or port
      @peer_host = nil
      @peer_port = nil
      
      if ((!opts[:one_to_many] && !opts[:passive]) && host && port)
        # If host and port present for one-to-one active socket, connect
        llconnect(host, port)
        @peer_host = host
        @peer_port = port.to_i
        @connected_flag = true;
      elsif (opts && opts[:passive] && port)
        # If passive, and we have at least a port, go ahead and bind
        llbind(host, port)
        lllisten(Backlog)
        @passive_flag = true; 
      end

      # Set nonblocking if requested
      if (opts && opts[:nonblocking])
        llblock = false
      end
      
      # Note one to many
      if (opts[:one_to_many])
        @one_to_many_flag = true
      end
      
      # Make sure we close on finalization
      ObjectSpace.define_finalizer(self, lambda {|id| self.close})
      
      self
    end
    
    def passive?
      @passive_flag ? true : false
    end

    def connected?
      @connected_flag ? true : false
    end

    def nonblocking?
      llblock? ? false : true
    end

    def one_to_many?
      @one_to_many_flag ? true : false
    end
    
    def accept
      llaccept
    end
    
    def sendmsg(msg)
      if (!connected? && (!msg.host || !msg.port))
        raise "Cannot send message without destination on unconnected socket"
      end
      llsendmsg(msg)
    end
    
    def recvmsg
      llrecvmsg(Maxbuf)
    end
    
    def inspect
      "<SCTP:Endpoint (#{peer_host}:#{peer_port})"+
      (passive? ? " passive" : "") +
      (connected? ? " connected" : "") +
      (one_to_many? ? " one_to_many" : "") +
      ">"
    end
    
    def close
      llclose
    end
  end
  
  class Socket < Endpoint
    
    attr_reader :message
    
    def initialize(host, port, opts = {})
      super(host, port, opts)
      @message = Message.new
    end
    
    def write(str)
      @message.write(str)
    end
    
    def flush(stream = nil)
      @message.stream = stream if stream
      sendmsg(@message)
      @message.truncate(0)
    end
    
    def nextmsg
      @message = readmsg
    end
    
    def read(len)
      str = @message.read(len)
      if (!str)
        return nil unless nextmsg
        str = @message.read(len)
      end
      str
    end
  end

end
