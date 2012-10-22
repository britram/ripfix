#
#--
# ripfix (IPFIX for Ruby) (c) 2010 Brian Trammell and Hitachi Europe SAS
#                         (c) 2011 Brian Trammell
# Special thanks to the PRISM Consortium (fp7-prism.eu) for its support.
# Distributed under the terms of the GNU Lesser General Public License v3.
#++
# Defines byte buffers, upon which the type system is built
#

module IPFIX

#
# An exception used by a buffer to signal end of buffer. This happens when
# attempting to read past the end of the buffer, or write past the write limit.
#
  class EndOfBuffer < StandardError
  end

#
# A read-write buffer based on a byte array. Used by the Type class
# for transcoding. A buffer has a cursor, for efficient shifting
#
  class Buffer

#
# Creates a Buffer. If passed a String, decomposes the string into bytes
# and stores those bytes; otherwise, creates a new, empty Buffer.
#
    def initialize(str = nil)
      @a = str ? str.unpack('C*') : Array.new
      @c = 0
      @wl = nil
    end

#
# Returns the current length of the buffer in bytes
#
    def length
      @a.length
    end

#
# Rewinds the buffer cursor to 0; subsequent shift operations will
# begin from the start of the buffer
#
    def rewind
      @c = 0
    end

#
# Save the buffer state (shift cursor, limit, and contents), then perform the 
# block. If the block raises an exception, restore the buffer state to before 
# the block. Used by the Type system to make sure encode operations can be
# rewound.
#
    def atomic
      cp = @a.length
      cc = @c
      cwl = @wl
      begin
        #STDERR.puts("Begin atomic section len #{@a.length}")
        yield
        #STDERR.puts("  End atomic section len #{@a.length}")
      rescue Exception
        #STDERR.puts("  Before rollback len #{@a.length}: #{$!}")
        @a.pop(@a.length - cp)
        @c = cc
        @wl = cwl
        #STDERR.puts("  After rollback len #{@a.length}")
        raise
      end
    end

#
# Append a byte as an integer to the buffer. Clamps the byte range to 0..255.
# Raises EndOfBuffer on attempt to append beyond the limit, if set.
# Returns the buffer, so << calls may be chained.
#

    def <<(byte)
      if (@wl && @a.length > @wl)
        raise EndOfBuffer
      end
      @a << (byte.to_i & 0xff)
      self
    end

#
# Determine whether a buffer can accept content of a given Set ID. This is
# used by the SetBuffer subclass; normal Buffers can accept anything, so
# this always returns true.
#
    def accept_id?(aid)
      true
    end

# 
# Return the current append limit: buffer size beyond which << will be
# ignored. Returns nil if no limit has been set.
#    
    def limit
      @wl
    end

#
# Set the current append limit: the buffer size beyond which << will be
# ignored. Truncates the buffer if it is already larger than the limit.
#
    def limit=(n)
      @a.pop(@a.length - n) if (n && (n < @a.length))
      @wl = n
    end

#
# Remove a previously set append limit.
#
    def unlimit
      @wl = nil
    end

#
# Consumes n bytes from the buffer and returns them in an array (or 1 byte
# if n is not given). Raises EndOfBuffer if not enough bytes are available.
#
    def shift(n = 1)
      if @c + n > @a.length
        raise EndOfBuffer
      end
      
      b = @c    # shift will return from current cursor
      @c += n   # to next cursor
      @a[b...@c]
    end

#
# Return how many bytes may be shifted from the buffer.
# 
    def shift_avail
      @a.length - @c
    end


#
# Frame a buffer as a string, e.g. for output via an IO object
#
    def string
      @a.pack('C*')
    end

#
# Dump a byte array as a hexdump with ll bytes per line (16 if not given).
# Used for debugging.
#
    def self::dump(a, ll=16)
      out = ''
      addr = 0
      a.each_slice(ll) do |line|
        out << sprintf("%04x: ", addr)
        line.each { |byte| out << sprintf("%02x ", byte) }
        if (line.length < ll)
          (ll - line.length).times { out << "   " }
        end
        out << " "
        line.each { |byte| out << ((byte > 31 && byte < 127) ? byte.chr : '.') }
        out << "\n"
        addr += ll
      end
      out
    end

#
# Dump this buffer as a hexdump with ll bytes per line (16 if not given).
# Used for debugging.
#
    def dump(ll=16)
      Buffer::dump(@a,ll)
    end

  end # class Buffer

#
# A read-write buffer based on a byte array, that provides the functionality
# an IPFIX Set. Extends Buffer to provide a Set ID, and to read and write
# set headers.
#-
#
  class SetBuffer < Buffer

# Length of a Set Header
    SetHeaderLen = 4

# Set ID of this SetBuffer
    attr_accessor :set_id

#
# Creates a SetBuffer. If passed a String, decomposes the string into bytes,
# parses the first four bytes as a set header, and stores the rest of the
# bytes; otherwise, creates a new, empty Buffer. If set_id is given,
# will only accept writes for that set_id (see accept_id?).
#
    def initialize(str=nil, set_id=nil)
      if str
        @set_id, len = str[0..3].unpack('n2')
        if (str.length < len)
          raise FormatError, "Incomplete set (have #{str.length}, need #{len})"
        end
        super(str[4...len])
      else
        super(nil)
        @set_id = set_id
      end
    end

#
# Returns the current length of the buffer in bytes, including four bytes for
# the set header.
#    
    def length
      SetHeaderLen + super
    end

#
# Returns the current limit on the buffer in bytes, including four bytes for
# the set header
#

    def limit
      suplim = super
      if (suplim) 
        SetHeaderLen + suplim
      else
        nil
      end
    end

#
# Returns true if the buffer can accept content of the given set_id.
#
    def accept_id?(set_id)
      if @set_id
        @set_id == set_id 
      else
        true
      end
    end

#
# Frame the buffer as a string, including the set header, for output
#
    def string
      so = ([(@set_id & 0xffff), length]).pack('n2C*') + super
      #STDERR.puts("SetBuffer #{"%x"%(object_id<<1)} (length #{length}) was asked for its string.")
      #STDERR.puts(Buffer.dump(so.bytes.to_a))
      so
    end
    
    def inspect
      "<SetBuffer id #{@set_id} length #{length}>"
    end

  end # class SetBuffer

end #module IPFIX