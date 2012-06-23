#
#--
# ripfix (IPFIX for Ruby) (c) 2010 Brian Trammell and Hitachi Europe SAS
# Special thanks to the PRISM Consortium (fp7-prism.eu) for its support.
# Distributed under the terms of the GNU Lesser General Public License v3.
#++
# Defines the MACAddress class, for storing MAC addresses.
#

#--
# rubydoc hack
nil

module IPFIX

#
# Represents a MAC address as an array of bytes in network byte order.
#
  class MACAddress
    MacRegexp = /([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2})/
    
    attr_reader :bytes

# 
# Create a new MAC address from either 1. an encoded, network byte order string
# of six bytes; 2. an array of six bytes in network byte order; or 3. a hex
# sextuplet string (e.g. "00:02:0a:ff:ff:ff").
#
    def initialize(aos)
      if (aos.length == 6)
        if aos.respond_to?(:unpack)
          self.bytes = aos.unpack("C6")
        else
          self.bytes = aos
        end
      else
        match = MacRegexp.match(aos)
        if match
          self.bytes = match[1..6].map { |b| b.hex }
        else
          self.bytes = [0,0,0,0,0,0]
        end
      end
    end

#
# Compare two MAC addresses.
#
    def ==(other)
      return false if (!other.respond_to?(:bytes)) 
      bytes == other.bytes
    end

#
# Return the string representation of a MAC address as a hex sextuplet.
# 
    def to_s()
      sprintf("%02x:%02x:%02x:%02x:%02x:%02x",*bytes)
    end

    def inspect()
      "<MACAddress #{to_s}>"
    end

private
    def bytes=(byteEnum)
      @bytes = byteEnum.map do |byte|
        byte = byte.to_i
        byte = 0 if byte < 0
        byte = 255 if byte > 255
        byte
      end
      self
    end
  end

end # module IPFIX