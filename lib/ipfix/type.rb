#
#--
# ripfix (IPFIX for Ruby) (c) 2010 Brian Trammell and Hitachi Europe SAS
# Special thanks to the PRISM Consortium (fp7-prism.eu) for its support.
# Distributed under the terms of the GNU Lesser General Public License v3.
#++
# Defines the IPFIX Type system and byte buffers, upon which the rest of
# the library is built.
#

require 'time'
require 'ipaddr'
require_relative 'macaddr'
require_relative 'buffer'

module IPFIX

#
# Base class of the IPFIX type system. Defines the interface for Types, and
# implements the default octet array type.
#
  class Type

# Length value representing a variable-length Information Element.
    Varlen = 65535
    
    @@unsigned = nil
    
# Name of the type (see RFCs 5101, 5102, 5610)
    attr_reader :name
# Number of the type (see RFC 5610)
    attr_reader :number
# Native size of the type
    attr_reader :size

#
# Return an internal unsigned type used for encoding unsigned values used by
# the IPFIX protocol; IPFIX client code has no reason to call this.
#
    def self.unsigned
      @@unsigned = UnsignedType.new("__internal_unsigned__", -1, 1) unless @@unsigned
      @@unsigned
    end
    
#
# Create a new type with the given name, number, and size. Used by InfoModel
# to initialize the type system; IPFIX client code has no reason to call this.
#
    def initialize(name, number, size)
      @name = name
      @number = number
      @size = size
    end

    def inspect
      "<Type:#{name}>"
    end

#
# Encode a variable-length information element prefix for the given length,
# appending it to a buffer.
#
private
    def encode_varlen_prefix(buf, len)
      if (len < 255)
        # unless buf.append_avail(1)
        #   raise(WriteOverrun, "Write overrun on 1-byte varlen encode")
        # end
        buf << len
      else
        # unless buf.append_avail(3)
        #   raise(WriteOverrun, "Write overrun on 3-byte varlen encode")
        # end
        buf << 255 << (len >> 8) << (len & 0xff)
      end
    end

#
# Decode a variable-length information element prefix, consuming it from 
# the buffer and returning it.
#
    def decode_varlen_prefix(buf)
      # unless buf.shift_avail(1)
      #   raise(ReadOverrun, "Read overrun on varlen decode")
      # end
      lvec = buf.shift(1)
      if (lvec[0] == 255)
        # unless buf.shift_avail(2)
        #   raise(ReadOverrun, "Read overrun on varlen decode")
        # end
        lvec = buf.shift(2)
        ((lvec[0] & 0xff) << 8) + (lvec[1] & 0xff)
      else
        lvec[0]
      end
    end

#
# Zero-pad or truncate a byte vector to len, left aligned, and append to a
# buffer. Used by subclasses to append unpacked byte-array values for
# reduced-length encoding.
#   
    def encode_tap_left(buf, vec, len, pv = 0)
      if (vec.length < len)
        pad = [pv] * (len - vec.length)
        len = vec.length
      else
        pad = nil
      end

      # unless buf.append_avail(len)
      #   raise(WriteOverrun, "Write overrun encoding #{self.inspect}: "\
      #                        "need #{len}, have #{buf.append_avail}")
      # end
      vec[0...len].each { |b| buf << b }
      pad.each { |b| buf << b } if (pad)
      buf
    end

#
# Zero-pad or truncate a byte vector to len, right aligned, and append to a
# buffer. Used by subclasses to append unpacked integral values for
# reduced-length encoding.
#
    def encode_tap_right(buf, vec, len, pv = 0)
      if (vec.length < len)
        pad = [pv] * (len - vec.length)
        len = vec.length
      else
        pad = nil
      end
    
      # unless buf.append_avail(len)
      #   raise(WriteOverrun, "Write overrun encoding #{self.inspect}: "\
      #                        "need #{len}, have #{buf.append_avail}")
      # end
      pad.each { |b| buf << b } if (pad)
      vec[-len..-1].each { |b| buf << b }
      buf
    end

#
# Deny byte vector padding or truncation, and append the byte vector
# to a buffer.
#
    def encode_tap_direct(buf, vec, len)
      if (vec.length != len)
        raise("cannot truncate or pad while encoding #{self.inspect} of "\
               "natural length #{vec.length} and declared length #{len}.")
      end

      # unless buf.append_avail(len) 
      #   raise(WriteOverrun, "Write overrun encoding #{self.inspect}: "\
      #                       "need #{len}, have #{buf.append_avail}")
      # end
      vec.each { |b| buf << b }
      buf
    end

#
# Encode nil by returning a vector of zeroes
#
    def encode_nil(len)
      len = 0 if (len == Varlen)
      [0] * len
    end

#
# Append a byte vector to a buffer with the natural truncation
# and padding for this type.
#
    def encode_tap(buf, vec, len)
      encode_tap_left(buf, vec, len)
    end

#
# Turn a value into a byte vector, with the target length; the resulting
# byte vector will be truncated, padded, and appended later with 
# encode_tap, so there is no need to ensure the output vector is of the
# target length.
#
    def encode_vec(val, len)
      val.map { |v| v > 255 ? 255 : (v < 0 ? 0 : v) }
    end

#
# Turn a byte vector into a value of the appropriate native Ruby type.
#
    def decode_vec(vec)
      vec
    end

#
# Encode a value of the given type and append it to a buffer.
# Passes the value down to encode_vec to turn a natural value into a
# natural byte vector, handles varlen prefix encoding, calls encode_tp 
# for truncation and padding.
#
public
    def encode(buf, val, len = size)
      if (val)
        vec = encode_vec(val, len)
      else
        vec = encode_nil(len)
      end
      
      if (len == Varlen)
        len = 0
        encode_varlen_prefix(buf, vec.length)
      end
      
      if (len == 0)
        len = vec.length
      end
      
      encode_tap(buf, vec, len)
    end

#
# Decode a value of the given type, consume it from a buffer.
# Finds a byte vector of the correct length, passes it to decode_vec
# to create an appropriate Ruby object.
#
    def decode(buf, len = size)
      if (len == Varlen)
        len = decode_varlen_prefix(buf)
      end
      
      # unless buf.shift_avail(len)
      #   raise(ReadOverrun, "Read overrun decoding #{self.inspect}: "\
      #         "need #{len}, have #{buf.shift_avail}")
      # end
      vec = buf.shift(len)
      decode_vec(vec)
    end

#
# Parse a string of this Type into an instance of the Ruby class this
# Type represents. For octet arrays, parses the string into a byte array.
#
  def parse(str)
    str.bytes
  end
  
  end # class Type

#
# Type implementing UTF8 strings
#
  class StringType < Type
private
    def encode_vec(val, len)
      val.unpack("U*")
    end
  
    def decode_vec(vec)
      s = vec.pack("U*")
      s.gsub(/\x00*$/,'')
    end
    
public
    def parse(str)
      str
    end
  end

#
# Type implementing arbitrary-length unsigned integers
#
  class UnsignedType < Type
private
    def encode_tap(buf, vec, len)
      encode_tap_right(buf, vec, len)
    end
    
    def encode_vec(val, len)
      vec = Array.new
      while (val > 0) do
        vec.unshift(val & 0xff)
        val = val >> 8
      end
      vec
    end
    
    def decode_vec(vec)
      vec.inject(0) { |a, c| (a << 8) + c }
    end
    
public
    def parse(str)
      str.to_i
    end
  end

#
# Type representing signed integer.
#
  class SignedType < UnsignedType
  
    def encode_tap(buf, vec, len)
      encode_tap_right(buf, vec, len, ((vec[0] & 0x80) > 0) ? 0xff : 0x00 )
    end
  
    def encode_vec(val, len)
      if (val >= 0)
        # positive
        super(val, len)
      else
        # negative
        super(~val, len).map{ |u| (~u) & 0xff }
      end
    end
  
    def decode_vec(vec)
      if (vec[0] & 0x80) > 0
        # negative
        ~super(vec.map{ |u| (~u) & 0xff })
      else
        # positive
        super(vec)
      end
    end
  end


#
# Type representing boolean values
#  
  class BooleanType < UnsignedType
private
    def encode_vec(val, len)
      super(val ? 1 : 2, len)
    end

    def decode_vec(vec)
      (super(vec) == 1) ? true : false
    end
    
public
    def parse(str)
      if (!str || str == 0 || str == "0" || 
                  str == "f" || str == "F" || 
                  str == "n" || str == "N")
        false
      else
        true
      end
    end
  end

#
# Type representing IEEE single or double precision floating point numbers  
#
  class FloatType < Type
private
    def encode_tap(buf, vec, len)
      encode_tap_direct(buf, vec, len)
    end

    def encode_vec(val, len)
      case len
      when 4
        [val].pack('g').unpack('C*')
      when 8, Varlen
        [val].pack('G').unpack('C*')
      else
        raise "cannot encode #{len}-byte float"
      end
    end  
  
    def decode_vec(vec)      
      case vec.length
      when 4
        vec.pack('C*').unpack('g').shift
      when 8
        vec.pack('C*').unpack('G').shift
      else
        raise "cannot decode #{vec.length}-byte float"
      end
    end

public
    def parse(str)
      str.to_f
    end
  end

#
# Type representing the Ruby native IPAddr objects
#
  class IPAddressType < Type
private
    def encode_tap(buf, vec, len)
      encode_tap_direct(buf, vec, len)
    end

    def encode_vec(val, len)
      val.hton.unpack("C*")
    end
    
    def decode_vec(vec)
      IPAddr.new_ntoh(vec.pack("C*"))
    end
    
public
    def parse(str)
      IPAddr.new(str)
    end
  end

#
# Type representing 6-octet MAC addresses; for encoding MACAddress objects
#
  class MACAddressType < Type
private
    def encode_tap(buf, vec, len)
      encode_tap_direct(buf, vec, len)
    end

    def encode_vec(val, len)
      val.bytes
    end
    
    def decode_vec(vec)
      MACAddress.new(vec)
    end

public
    def parse(str)
      MACAddress.new(str)
    end
  end

#
# Type representing time in seconds since the epoch (0 UTC 1 Jan 1970);
# for encoding Ruby Time objects.
#
  class SecondsType < UnsignedType
private
    def encode_vec(val, len)
      super(val.to_i, len)
    end

    def decode_vec(vec)
      Time.at(super(vec)).utc
    end
    
public
    def parse(str)
      Time.parse(str)
    end
  end

#
# Type representing time in milliseconds since the epoch (0 UTC 1 Jan 1970);
# for encoding Ruby Time objects.
#
  class MillisecondsType < UnsignedType
private
    def encode_vec(val, len)
      super((val.to_f * 1000).to_i, len)
    end

    def decode_vec(vec)
      millis = super(vec)
      Time.at(millis/1000, (millis % 1000)*1000).utc
    end

public
    def parse(str)
      Time.parse(str)
    end    
  end



#
# Type representing NTP-encoded time in seconds and fractional
# seconds since the epoch (0 UTC 1 Jan 1970); for encoding Ruby Time objects.
# Reimplement this. Use a fraction that always gets multiplied by two and test
# the integer part against 1, while rotating an OR mask down from 0xf0000000.
# To decode, continue adding a fraction .5 divided by two while rotating an 
# AND mask down from 0xf0000000.
#
  class NTPType < Type
    def encode_tap(buf, vec, len)
      encode_tap_direct(buf, vec, len)
    end
    
    def encode_vec(val, len)
      # length is 64-bit fixed
      if len != 8
        raise "cannot encode #{len}-byte NTP time"
      end        

      sec = val.to_i
      fsec = val.to_f - sec
      
      # rotate the fraction mask down
      fsmask = 0x80000000
      fsfrac = 0.5
      fntp = 0
      while fsmask != 0
        if fsec > fsfrac
          fntp = fntp | fsmask
          fsec -= fsfrac
        end
        fsfrac /= 2
        fsmask >>= 1
      end
      
      # pack the whole and fraction
      [sec, fntp].pack('N2').unpack('C*')
    end
  
    def decode_vec(vec)
      # length is 64-bit fixed
      if vec.length != 8
        raise "cannot decode #{vec.length}-byte NTP time"
      end        

      # unpack whole and fraction
      sec, fntp = vec.pack('C*').unpack('N2')
      
      # rotate the fraction mask down
      fsmask = 0x80000000
      fsfrac = 0.5
      fsec = 0
      while fsmask != 0
        if fsmask & fntp != 0
          fsec += fsfrac
        end
        fsfrac /= 2
        fsmask >>= 1
      end
      
      usec = fsec * 1000000.0
      Time.at(sec, usec)
    end
  end

end # module IPFIX
