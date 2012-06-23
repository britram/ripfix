#
#--
# ripfix (IPFIX for Ruby) (c) 2010 Brian Trammell and Hitachi Europe SAS
# Special thanks to the PRISM Consortium (fp7-prism.eu) for its support.
# Distributed under the terms of the GNU Lesser General Public License v3.
#++
# Defines the InfoModel and InfoElement classes, which implement IPFIX
# Information Elements.
#

require_relative 'type'

module IPFIX
#
# An IPFIX Information Model is a canonical registry of Information Elements.
#
  class InfoModel

#
# Create a new empty, information model. This model will contain a complete
# type system, but no information elements; use load to load these from
# a spec file, or see load_iana in ipfix/iana.rb to dynamically load the
# IANA registry.
#
# Most IPFIX applications should use a single Information Model, so creating
# one of these and holding on to it is the first step to using IPFIX.
#
    def initialize()
      # Initialize type registry  
      @types = Array.new
      @typesByName = Hash.new

      [
        Type.new('octetArray', 0, Type::Varlen),
        UnsignedType.new('unsigned8', 1, 1),
        UnsignedType.new('unsigned16', 2, 2),
        UnsignedType.new('unsigned32', 3 ,4),
        UnsignedType.new('unsigned64', 4, 8),
        SignedType.new('signed8', 5, 1),
        SignedType.new('signed16', 6, 2),
        SignedType.new('signed32', 7, 4),
        SignedType.new('signed64', 8, 8),
        FloatType.new('float32', 9, 4),
        FloatType.new('float64', 10, 8),
        BooleanType.new('boolean', 11, 1),
        MACAddressType.new('macAddress', 12, 6),
        StringType.new('string', 13, Type::Varlen),
        SecondsType.new('dateTimeSeconds', 14, 4),
        MillisecondsType.new('dateTimeMilliseconds', 15, 8),
        NTPType.new('dateTimeMicroseconds', 16, 8),
        NTPType.new('dateTimeNanoseconds', 17, 8),
        IPAddressType.new('ipv4Address', 18, 4),
        IPAddressType.new('ipv6Address', 19, 16)
      ].each do |t|
        @types[t.number] = t
        @typesByName[t.name] = t
      end

      # Initialize information element registry
      @elements = Hash.new { |h,k| h[k] = Hash.new }
      @elementsByName = Hash.new

    end

#
# Returns the Type for a given type number (see RFC 5610)
#
    def type_for_number(number)
      @types[number]
    end

#
# Returns the Type for a given name.
#
    def type_for_name(name)
      @typesByName[name]
    end

#
# Returns the information element for a given PEN and number. Use PEN 0 for
# IANA information elements, and InfoElement::ReversePEN for reverse
# informaton elements. Used mainly to look up information elements from
# template field specifiers
#
    def ie_for_number(pen, number)
      @elements[pen][number]
    end

#
# Returns the information element from this Model for a given name. You 
# probably want ie_for_spec(), instead.
#
    def ie_for_name(name)
      @elementsByName[name]
    end

#
# Returns the information element from this Model for a given information
# element spec. A spec has the following form:
#
# informationElementName(pen/number)<typeName>[size]
#
# where all elements except the name are optional. If a number is given, 
# looks up the information element by number and ignores the name; otherwise
# looks up the information element by name. If pen is not present, it is 
# assumed to be 0 (for IANA information elements). The type name is ignored. If a
# size is given, the returned information element will have this size 
# regardless of the native size in the Model; this is used to support
# reduced-length encoding.
#
    def ie_for_spec(spec)
      ps = InfoElement.parse_spec(spec)
      return nil unless ps
      
      if ps[:number]
        ie = ie_for_number(ps[:pen], ps[:number])
        ie = ie.for_size(ps[:size]) if (ie && ps[:size] > 0)
      elsif ps[:name]
        ie = ie_for_name(ps[:name])
        ie = ie.for_size(ps[:size]) if (ie && ps[:size] > 0)
      end
      ie
    end

#
# Add an information element to the model. Replaces any existing IE sharing
# the number and name of the given IE.
#
    def add(ie)
      if (ie)
        @elements[ie.pen][ie.number] = ie
        @elementsByName[ie.name] = ie if (ie.name != "__none__")
      end
      ie
    end

#
# Add an information element to the model by spec. A spec has the following
# form:
#
# informationElementName(pen/number)<typeName>[size]
#
# For adding information elements to the model, all fields are required except
# pen and size. If pen is omitted, assumes zero (for an IANA IE). If size is 
# omitted, uses the native size of the type.
#
    def add_spec(spec)
      add(InfoElement.for_spec(self, spec))
    end

#
# Load an information model from a file containing newline-separated
# information element specifiers. Returns the Model, so multiple loads
# may be chained together (e.g., to load multiple private IEs)
#
    def load(filename)
      File.open(filename) do |file|
        file.each do |line|
          add_spec(line)
        end
      end
      self
    end

#
# Save an information model to a file containing newline-separated
# information element specifiers, suitable for later loading with
# Model.load()
#
    def save(filename)
      File.open(filename, "w") do |file|
        each do |ie|
          file.puts(ie.spec)
        end
      end
    end

#
# Iterate over the Model, yielding each information element.
#
    def each()
      @elements.each_value do |pen_ies|
        pen_ies.each_value do |ie|
          yield ie if ie
        end
      end
    end

    def inspect
      "<InfoModel:#{@types.length}:#{@elements.keys.to_a.inspect}>"
    end
  end # class InfoModel

#
# An IPFIX Information Element: a type/name/size tuple representing an
# element within a Template.
#
  class InfoElement

# PEN for RFC 5103 compliant reverse-direction information elements
    ReversePEN = 29305

# Regular expression for parsing specs. A spec has the form:
#
# informationElementName(pen/number)<typeName>[size]
    SpecRegex = /^([^\s\[\<\(]+)?(\(((\d+)\/)?(\d+)\))?(\<(\S+)\>)?(\[(\S+)\])?/

# Name of the Information Element
    attr_reader :name 
# Private Enterprise Number of the Information Element, 
# or 0 for IANA Information Elements
    attr_reader :pen 
# Number of the Information Element
    attr_reader :number
# Type of the Information Element
    attr_reader :type
# Size of the Information Element in bytes, or Type::Varlen 
# for variable-length IEs
    attr_reader :size
# Hashkey used to represent this Information Element in decoded hashes; 
# defaults to the full name of the Information Element as a symbol. Provided
# as a way to have a more convenient (i.e. shorter) hash key for frequently
# used elements.
    attr_accessor :hashkey

#
# Create an Information Element given a name, private enterprise number (0
# for IANA), IE number, IPFIX::Type, and size in octets. For IEs within an
# Information Model, size is the native size of the type (or the expected
# maximum length for strings). For IEs within a Template, size may be used for
# reduced length encoding.
#
    def initialize(name, pen, number, type, size = nil)
      @name = name
      @pen = pen
      @number = number
      @type = type
      @size = size ? size : type.size
      @hashkey = name.to_sym
    end

#
# Get an IE identical to the reciever, for a given size. Used to implement
# reduced-length encoding.
#
    def for_size(size = nil)
      if size == nil || @size == size
        self
      else
        element = InfoElement.new(@name, @pen, @number, @type, size)
        element.hashkey = @hashkey
        element
      end
    end

#
# Get an IE identical to the reciever, but for the reverse direction in RFC
# 5103 biflows. Only works for IANA IEs (i.e., if pen is 0).
#
    def for_reverse()
      if @pen == ReversePEN
        self
      elsif @pen != 0
        nil
      else
        InfoElement.new("reverse" + @name[0].upcase + @name[1..-1],
                                ReversePEN, @number, @type, @size)
      end
    end

#
# True if the IE is enterprise-specific (i.e., if pen > 0)
#
    def is_ep?()
      !(@pen == 0)
    end

#
# True if the IE is variable length (i.e., if size == 65535)
#
    def is_varlen?()
      (@size == 65535)
    end

#
# Get the full spec for this IE. An IE spec has the form:
#
# informationElementName(pen/number)<typeName>[size]
#
    def spec()
      specnum = is_ep? ? "#{@pen}/#{@number}" : @number
      size = is_varlen? ? "v" : @size
      "#{@name}(#{specnum})<#{@type.name}>[#{size}]"
    end
    
    def inspect()
      spec
    end

#
# Parse a spec into a hash
#
    def self::parse_spec(spec)
      sm = SpecRegex.match(spec)
      return nil unless sm
      ps = Hash.new
      ps[:name] = sm[1]
      ps[:pen] = sm[4] ? sm[4].to_i : 0
      ps[:number] = sm[5] ? sm[5].to_i : nil
      ps[:type] = sm[7]
      if (sm[9] && sm[9][0] == "v")
        ps[:size] = 65535
      else
        ps[:size] = sm[9].to_i
      end
      ps
    end

#
# Create an Information Element given a spec. A spec has the following form:
#
# informationElementName(pen/number)<typeName>[size]
#
# All fields are required except pen and size. If pen is omitted, assumes 
# zero (for an IANA IE). If size is omitted, uses the native size of the type.
#
    def self::for_spec(model,spec)
      ps = InfoElement.parse_spec(spec)
      return nil unless ps
      
      if (ps[:name] && ps[:number] && ps[:type])
        new(ps[:name], ps[:pen], ps[:number], model.type_for_name(ps[:type]), ps[:size])
      else
        nil
      end
    end

#
# Encode a template field representing this Information Element to a buffer.
# Used by Template.
#
    def encode_field(buf)
      Type.unsigned.encode(buf, is_ep? ? (@number | 0x8000) : @number, 2)
      Type.unsigned.encode(buf, @size, 2)
      Type.unsigned.encode(buf, @pen, 4) if @pen > 0
    end

#
# Create an Information Element by consuming a template field from a buffer.
# Uses the model to look up types and canonical information elements; if
# the IE is not found by PEN and number in the model, creates a new 
# information element with the name __none__, which will not be searchable
# by name.
#
    def self::for_field(model, buf)
      number = Type.unsigned.decode(buf, 2)
      size = Type.unsigned.decode(buf, 2)
      
      if (number & 0x8000) > 0
        number = number & 0x7fff
        pen = Type.unsigned.decode(buf, 4)
      else
        pen = 0
      end
      
      ie = model.ie_for_number(pen, number)
      ie = ie.for_size(size) if ie
      
      unless ie
        ie = new("_ipfix_#{pen}_#{number}", pen, number, model.type_for_name("octetArray"), size)
        model.add(ie)
      end
      ie
    end
    
    def <=>(other)
      x = pen <=> other.pen
      if x != 0
        x
      else
        num <=> other.number
      end
    end
    
    def ==(other)
      ((self <=> other) == 0) ? true : false
    end
  end # class InfoElement
end # module IPFIX