#
#--
# ripfix (IPFIX for Ruby) (c) 2010 Brian Trammell and Hitachi Europe SAS
# Special thanks to the PRISM Consortium (fp7-prism.eu) for its support.
# Distributed under the terms of the GNU Lesser General Public License v3.
#++
# Defines the V9PDUStream class, which can be used to read NetFlow V9 PDUs as
# if they were IPFIX Messages. Implements, in part, the V9->IPFIX
# equivalence in Appendix B of RFC 555.
#
# Writing Netflow V9 PDUs is not supported by this module.
#

require_relative 'message'

module IPFIX
  
  class V9Template < Template
    SetID = 0
      
    def self.template_set_id
      SetID
    end
  end
  
  class V9OptionsTemplate < OptionsTemplate
    SetID = 1

    def self.template_set_id
      SetID
    end
  end
  
  class V9PDUStream
    extend EventDispatch

    attr_reader :template, :domain, :export_time, :base_time, :sysuptime_ms
  
    event :new_message
    
    HeaderLen = 20
    SetHeaderLen = 4
    
#
# Create a new V9PDU within a given Session, reading from a given IO.
# 
    def initialize(session, io)
      # store initialization parameters
      @session = session
      @io = io
      raise "Cannot initialize NetFlow V9 PDU with nil Session" unless @session
      raise "Cannot initialize NetFlow V9 PDU with nil IO" unless @io
    end

#
# Read a PDU header after the version and count fields.
# 
    def read_pdu_header(count)
      # read and unpack rest of header
      hdr = @io.read(HeaderLen-SetHeaderLen)
      return nil if !hdr 

      # handle short read
      if hdr.length < HeaderLen-SetHeaderLen
        raise FormatError, "Incomplete V9 PDU header from #{@io.inspect}"
      end
      
      @sysuptime_ms, export_epoch, sequence, @domain = hdr.unpack("N43")
       
      # store export time
      @export_time = Time.at(export_epoch).utc

      # calculate and store base time: FIXME, need correction factor
      @base_time = @export_time - (@sysuptime_ms / 1000.0)
      
      post_new_message(self)
      
      count
    end

#
# Read a set header and body, consuming PDU headers as necessary
#
    def next_set
      # loop to find something that isn't a PDU header
      while (true)
        # read a set header from the stream
        shdr = @io.read(SetHeaderLen)

        # check for EOF
        return nil if !shdr
      
        # check for short read
        if shdr.length < SetHeaderLen
          raise FormatError, "Incomplete V9 set header from #{@io.inspect}"
        end
      
        # get set ID and header
        sid, slen = shdr.unpack("n2")
      
        # set ID 9 = PDU header; read next PDU
        if (sid == 9)
          read_pdu_header(slen)
        else
          break
        end
      end

      # okay, we probably have a real set. read the body from the stream  
      sbody = @io.read(slen-SetHeaderLen)
      if sbody.length < slen-SetHeaderLen
         raise FormatError, "Incomplete V9 set body from #{@io.inspect} (need #{slen-SetHeaderLen}, got #{sbody.len}"
      end
            
      # sick hack: combine header and body into a set buffer
      SetBuffer.new(shdr+sbody)
    end

    
    def each # :yields: hash, pdu
      while set = next_set # automagically eats message headers
        case set.set_id
        when V9Template::SetID
          while set.shift_avail > 4 
            @session.add_template(@domain, V9Template.decode_template_record(@session.model, set))
          end
        when V9OptionsTemplate::SetID          
          while set.shift_avail > 6
            @session.add_template(@domain, V9OptionsTemplate.decode_template_record(@session.model, set))
          end
        else
          if @template = @session.template(@domain, set.set_id)
            while set.shift_avail >= @template.min_length
              rec = Hash.new
              rec[:_v9_basetime] = @base_time
              yield @template.decode_hash(set), self
            end
          else
            # missing template
            @session.post_missing_template(self, set)
          end
        end
      end
    end
  end
  
  class V9FileReader < V9PDUStream
    
    def self.open(filename, model)
      cp = V9FileReader.new(filename, model)
      yield cp
    ensure
      cp.close
    end
    
    def initialize(filename, model)
      if (filename == "-")
        super(STDIN,model)
      else
        super(File.new(filename,"r"),new Session(model))
      end
    end
    
    
  end
  
end

