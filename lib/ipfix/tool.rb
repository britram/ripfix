#
#--
# ripfix (IPFIX for Ruby) (c) 2010 Brian Trammell and Hitachi Europe SAS
#                         (c) 2013 Brian Trammell
# Distributed under the terms of the GNU Lesser General Public License v3.
#++
# Defines classes for implementing Collecting Process command-line tools


require_relative 'collector'
require_relative 'iana'

module IPFIX

  class CollectorTool

    def initialize
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
    
    def start_collector
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
      @c.each { |h, m| yield h, m }
    end

  end

end