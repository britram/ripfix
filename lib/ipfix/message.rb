#
#--
# ripfix (IPFIX for Ruby) (c) 2010 Brian Trammell and Hitachi Europe SAS
# Special thanks to the PRISM Consortium (fp7-prism.eu) for its support.
# Distributed under the terms of the GNU Lesser General Public License v3.
#++
# Defines the Message and Session classes, which implement IPFIX Messages on 
# top of InfoModel and Type.
#

require_relative 'model'
require_relative 'eventdispatch'
require 'stringio'

#
# :include: README
#
module IPFIX

#
# An exception used to indicate a read of an invalid IPFIX Message.
#
  class FormatError < StandardError
  end
  
#
# A Template is an ordered list of Information Elements describing an IPFIX
# Data Record. Templates provide the bridge Ruby hashes and IPFIX data sets,
# and also know how to read and write themselves to set buffers.
#
  class Template

# The Set ID used to encode templates (from RFC 5101)
    SetID = 2

# Template ID of this template
    attr_reader :tid

# 
# Create a new, empty Template given an information model and a template ID.
# A template ID is a 16-bit number, 256 of greater.
#
    def initialize(model, tid)
      @model = model
      @tid = tid < 256 ? 256 : (tid > 65535 ? 65535 : tid)
      @elements = Array.new
      @min_length = 0
    end

# 
# Add an Information Element or and Information Element spec, looked up in
# the template's Model, to the Template. Returns the Template, so << can be
# chained.
#
    def <<(ie)
      ie = @model.ie_for_spec(ie) if (ie.kind_of? String)
      if ie
        @elements << ie 
        @min_length += ((ie.size == Type::Varlen) ? 1 : ie.size)
      end
      self
    end

#
# Iterate over the Information Elements in the Template, yielding each.
#
    def each()
      @elements.each do |ie|
        yield ie
      end
    end

#
# Return the number of Information Elements in the Template.
#
    def count
      @elements.length
    end

#
# Return the minimum encoded length of a Data Record represented by this
# Template: the sum of the sizes of the Information Elements, with the minimum
# size of a variable-length Information Element being 1.
#
    def min_length
      @min_length
    end

# 
# Return a template spec, which is simply a newline-separated list of
# Information Element specs for the IEs in the Template.
#
    def spec
      @elements.map(&:spec).join("\n")
    end

#
# Encode a template record and append it to a buffer; buffer must accept
# Set ID 2.
#
    def encode_template_record(buf)
      unless buf.accept_id?(template_set_id)
        raise "Cannot encode a template record to a non-Template Set"
      end
      buf.atomic do
        Type.unsigned.encode(buf, tid, 2)
        Type.unsigned.encode(buf, count, 2)
        each { |ie| ie.encode_field(buf) }
      end
    end

#
# Decode a template record and consume it from a buffer, creating a new
# Template given a Model. Buffer must accept Set ID 2.
#
    def self::decode_template_record(model, buf)
      unless buf.accept_id?(template_set_id)
        raise "Cannot decode a template record from a non-Template Set"
      end
      tid = Type.unsigned.decode(buf, 2)
      count = Type.unsigned.decode(buf, 2)
      tmpl = Template.new(model, tid)
      count.times { tmpl << InfoElement.for_field(model, buf) }
      tmpl
    end

#
# Return the set ID of a set required to encode Templates of this class (2)
#
    def self::template_set_id
      SetID
    end

#
# Return the set ID of a set required to encode this Template (2)
#
    def template_set_id
      self.class.template_set_id
    end

#
# Given a buffer and a hash record, encodes the hash record according to the 
# template and appends it to the buffer. Buffer must accept this template's ID.
#
    def encode_hash(buf, rec)
      unless buf.accept_id?(tid)
        raise "Can't encode record with template ID #{tid} into buffer with set ID #{buf.set_id})"
      end
      buf.atomic do
        each do |ie|
          ie.type.encode(buf, rec[ie.hashkey], ie.size)
        end
      end
    end

#
# Given a buffer, decodes a hash record according to the 
# template and consumes it from the buffer. 
# Buffer must accept this template's ID.
#
    def decode_hash(buf, rec=Hash.new)
      unless buf.accept_id?(tid)
        raise "SetID mismatch on record decode"
      end
      each do |ie|
        rec[ie.hashkey] = ie.type.decode(buf, ie.size)
      end
      rec
    end
  end # class Template

#
# An Options Template extends a Template to provide scope, which defines
# the applicability of Data Records described by Option Templates.
#
  class OptionsTemplate < Template

    SetID = 3

# 
# Create a new, empty Options Template given an information model and a 
# template ID. A template ID is a 16-bit number, 256 of greater.
#
    def initialize(model, tid)
      super(model, tid)
      @scope = Array.new
    end

# 
# Add an Information Element or and Information Element spec, looked up in
# the template's Model, as a scope IE to the Template. Scope IEs occur in the
# Template before normal IEs. Returns the Template, so add_scope can be
# chained (along with <<)
#
    def add_scope(ie)
      ie = @model.ie_for_spec(ie) if (ie.kind_of? String)
      @scope << ie if ie
      self
    end

#
# Iterate over the Information Elements in the Options Template, yielding each.
#    
    def each()
      @scope.each do |ie|
        yield ie
      end
      super
    end

#
# Return the count of scope IEs in this Options Template.
#
    def scope_count
      @scope.length
    end

#
# Return the total count of IEs in this Options Template.
#
    def count
      super + scope_count
    end

#
# Encode an options template record and append it to a buffer; buffer must 
# accept Set ID 3.
#
    def encode_template_record(buf)
      unless buf.accept_id?(template_set_id)
        raise "Cannot encode an options template record "
              "to a non-Options Template Set"
      end
      buf.atomic do
        Type.unsigned.encode(buf, id, 2)
        Type.unsigned.encode(buf, count, 2)
        Type.unsigned.encode(buf, scope_count, 2)
        each { |ie| ie.encode_field(buf) }
      end
    end

#
# Decode an options template record and consume it from a buffer, creating a 
# new Template given a Model. Buffer must accept Set ID 3.
#
    def self::decode_template_record(model, buf)
      unless buf.accept_id?(template_set_id)
        raise "Cannot decode an options template record "
              "from a non-Options Template Set"
      end
      tid = Type.unsigned.decode(buf, 2)
      count = Type.unsigned.decode(buf, 2)
      scope_count = Type.unsigned.decode(buf, 2)
      tmpl = OptionsTemplate.new(model, tid)
 
      scope_count.times do
        tmpl.add_scope InfoElement.for_field(model, buf)
      end
 
      (count - scope_count).times do
        tmpl << InfoElement.for_field(model, buf)
      end
      tmpl
    end

#
# Return the set ID of a set required to encode Templates of this class (2)
#
    def self::template_set_id
      SetID
    end

  end # class OptionsTemplate

#
# A Session provides a container for state required per Transport Session.
# Each Message must exist with in the context of a Session, which may be
# shared by multiple Sessions. Presently, this contains a set of active 
# Templates indexed by Observation Domain.
#
  class Session
    extend EventDispatch

# Event posted when a template is added. on_template_add yields (domain, template)
    event :template_add    
# Event posted when a template is added. on_template_remove yields (domain, template)
    event :template_remove
# Event posted when an out-of-sequence message is received. on_bad_sequence yields (message, expected)
    event :bad_sequence
# Event posted when a template is missing for a set. on_missing_template yields (message, set)
    event :missing_template
# Event posted when a set has extra data at the end. extra_data yields (message, set)
    event :extra_data

# Information model to use for Template parsing within this Session
    attr_reader :model

#
# Create a new empty Session given an Information Model
#
    def initialize(model)
      @model = model
      @templates = Hash.new { |h,k| h[k] = Hash.new }
      @next_sequence = Hash.new
    end

#
# Return a Template given a domain and template ID
#
    def template(domain, tid)
      @templates[domain][tid]
    end

# 
# Add a Template for a given domain. If the template has no elements,
# it is treated as a template withdrawal message, and removes the
# template from the Session.
#
    def add_template(domain, template)
      if (template.count > 0)
        @templates[domain][template.tid] = template
        post_template_add(domain, template)
      else 
        remove_template(domain, template.tid)
      end
    end

# 
# Remove a template for given domain and template ID.
#
    def remove_template(domain, tid)
        if (@templates[domain][tid])
          post_template_remove(domain, @templates[domain][tid])
        end
        @templates[domain].delete(tid)
    end

#
# Iterate all the templates given a domain, yielding each
#
    def each_template(domain)
      @templates[domain].each_value do |template|
        yield template
      end
    end

#
# Return the next sequence number to be emitted or expected for the given domain
#
    def next_sequence(domain)
      ns = @next_sequence[domain]
      ns ? ns : 0
    end

#
# Ensure the message's sequence number matches expected, post a bad_sequence
# event if not. Resynchronizes the sequence number stream to the message's
# sequence number value.
#
    def check_sequence(message)
      domain = message.domain
      sequence = message.sequence
      expected = @next_sequence[domain]
      unless (expected == sequence) || !expected
        post_bad_sequence(message, expected)
        @next_sequence[domain] = sequence
      end
    end

#
# Increment the next sequence number for a completely read or written message
#
    def increment_sequence(message)
      @next_sequence[message.domain] = message.sequence + message.data_count
    end
    
  end # class Session

#
# An IPFIX Message is the basic data unit of the IPFIX Protocol. This class
# models a Message as a collection of Templates and Data Records within Sets.
# It provides an interface for reading Messages from an IO, packing Messages
# to a string, adding records and templates to a Message, and iterating over
# records in a Message.
#
  class Message
    extend EventDispatch

    include Enumerable

    HeaderLen = 16
    DefaultMtu = 65535
    
    attr_reader :domain
    attr_reader :template
    attr_reader :template_count
    attr_reader :data_count
    attr_reader :sequence
    attr_accessor :export_time

# Maximum size of a message; append beyone MTU raises EndOfBuffer
    attr_accessor :mtu
    
# Set to TRUE to ensure every Set has only one record
    attr_accessor :srs_mode

#
# Create a new Message within a given Session. If the second argument is a
# string, decode the Message as a packed string. If the second argument is a
# number, create the Message within the specified Observation Domain.
# 
# :call-seq: Message.new(session)
#            Message.new(session, domain)
#            Message.new(session, string)
#
    def initialize(session, dos = nil)
      @mtu = DefaultMtu
      @srs_mode = false
      @session = session
      @domain = nil
      raise "Cannot initialize IPFIX Message with nil Session" unless @session
      
      if (dos.respond_to? :to_int)
        reset(dos.to_int)
      else
        reset
      end
      
      if (dos.respond_to? :to_str)
        decode(dos.to_str)
      end
    end

#
# Reset a Message, clearing its content, and optionally changing its
# Observation Domain.
#
    def reset(domain = nil, sequence = 0, export_time = nil)
      @sets = Array.new
      @export_time = export_time
      @template = nil
      @domain = domain if (domain)
      @data_count = 0
      @template_count = 0
      @sequence = sequence
      @sequence_increment_done = false
      self
    end

#
# Get the message header as a packed string
#
    def header_string
      # default export time
      export_time = @export_time ? @export_time.to_i : Time.new.to_i
      
      # calculate length
      length = @sets.inject(HeaderLen) { |a, s| a + s.length }
      
      # get sequence number
      unless @sequence_increment_done
        @sequence = @session.next_sequence(@domain)
        @session.increment_sequence(self)
        @sequence_increment_done = true
      end
      
      # puts "message header len #{length} et #{export_time} seq #{@sequence} dom #{@domain}"
      
      # pack header
      [10, length, export_time.to_i, @sequence, @domain].pack("n2N3")
    end

#
# Get the encoded message as a packed string
#
    def string
      # prune any set that doesn't have any content
      prune_empty_set
      # inject header into sets
      @sets.inject(header_string) { |m, s| m + s.string }
    end

#
# Write an encoded Message into an IO
#
    def write(io)
      io.write(string)
    end

#
# Decode a packed string into a Message, overwriting its content.
#
    def decode(str)
      read(StringIO.new(str))
    end

#
# Read a Message from an IO. Raises FormatError if the bytes from the IO 
# do not seem to contain an IPFIX Message.
#
    def read(io)
      # read a message header
      hdr = io.read(HeaderLen)
      return nil if !hdr 

      if hdr.length < HeaderLen
        raise FormatError, "Incomplete message header from #{io.inspect}"
      end

      # decode it, look for signs it's not valid ipfix
      version, length, export_epoch, sequence, domain = hdr.unpack("n2N3")
      if version != 10
        raise FormatError, "Unsupported IPFIX message version #{version}."
      end
      if length < HeaderLen
        raise FormatError, "Impossibly short IPFIX message length #{length}."
      end

      # now read the body
      body = io.read(length-HeaderLen)
      if body.length < length-HeaderLen
        raise FormatError, "Incomplete message body from #{io.inspect}: header says #{length}, but have #{body.length} bytes"
      end

      # Okay, we're pretty sure we have a valid message now. 
      # Reset the message, storing the header
      reset(domain, sequence, Time.at(export_epoch).utc)

      # and split it into Sets
      while body.length > 0
        @sets << SetBuffer.new(body)
        body = body[@sets[-1].length..-1]
      end
      
      # Finally, check the message sequence number
      @session.check_sequence(self)
      
      self
    end

private
    def prune_empty_set
      if (@sets[-1].length == SetBuffer::SetHeaderLen)
        @sets.pop
      end
    end

    def append_new_set(set_id)
      @sets << SetBuffer.new(nil, set_id)
      baselim = @mtu - HeaderLen - SetBuffer::SetHeaderLen
      @sets[-1].limit = (@sets.inject(baselim) { |a, s| a - s.length })
      if @sets[-1].limit <= 0
        @sets.pop
        raise(EndOfBuffer, "Write overrun on new set header")
      end
    end

    def append_ensure_set(set_id)
      if (!@sets[-1] || srs_mode || !@sets[-1].accept_id?(set_id))
        append_new_set(set_id)
      end
    end
public

#
# Append a Template to a message
#
    def append_template(template)
      @session.add_template(@domain, template)
      append_ensure_set(template.template_set_id)
      template.encode_template_record(@sets[-1])
      @template_count += 1
      self
    end

#
# Append all active Templates in the Message's Session to the Message.
#
    def append_active_templates
      session.each_template(@domain) { |template| append_template(template) }
    end

#
# Activate the given Template; cause subsequent appended records to be encoded
# using this Template. Appends the Template to the Message if it is not yet
# present in the Session.
#
    def activate_template(template)
      @template = template
      unless (@session.template(@domain, @template.tid))
        append_template(@template)
      end
      template
    end    

#
# Activate the Template in the present domain with the present tid; raises
# a RuntimeError if there is no such Template. 
#
    def activate_template_id(tid)
      if (template = @session.template(@domain, tid))
        activate_template(template)
      else
        raise "No template #{tid} in session for domain #{@domain}"
      end
    end

#
# Append a record encoded as a hash to this Message, encoding it according to
# the currently active Template. The hash keys will be the information 
# element names in the Template as Symbols, unless the Information Element
# hashkeys in the associated Model have been set with 
# InformationElement::hashkey=(). If the hash contains the special key 
# :_ipfix_tid, activates the specified template ID before appending.
#
    def append_hash(h)
      if (h[:_ipfix_tid])
        activate_template_id(h[:_ipfix_tid].to_i)
      end
      append_ensure_set(@template.tid)
      @template.encode_hash(@sets[-1], h)
      @data_count += 1
      self
    end
  
#
# Append someting to the message. Given a Template, appends a Template, otherwise,
# appends the object as a hash.
#
    def <<(thing)
      if thing.is_a? Template
        append_template(thing)
      else
        append_hash(thing)
      end
    end

#
# Iterate over the data records in the Hash as records, yielding each. Adds
# any Templates in the Message during decode to the associated Session.
#
    def each # :yields: hash, message
      @sets.each do |set|
        case set.set_id
        when 0..1
          raise FormatError, "Invalid Set ID #{set.set_id}"
        when Template::SetID
          while set.shift_avail > 4
            @session.add_template(@domain, Template.decode_template_record(@session.model, set))
            @template_count += 1 
          end
        when OptionsTemplate::SetID          
          while set.shift_avail > 6
            @session.add_template(@domain, OptionsTemplate.decode_template_record(@session.model, set))
            @template_count += 1
          end
        else
          if @template = @session.template(@domain, set.set_id)
            while set.shift_avail >= @template.min_length
              yield @template.decode_hash(set), self
              @data_count += 1
            end
            if set.shift_avail > 0
              @session.post_extra_data(self, set)
            end
          else
            @session.post_missing_template(self, set)
          end
        end
      end
      
      # Update sequence number
      @session.increment_sequence(self)
    end

#
# Return the count of records in the message. For written messages, counts
# records as they are appended. For read messages, counts records read so far
# (i.e., this will be 0 after Message::read before Message::each)
#    
    def record_count
      data_count + template_count
    end
    
    def inspect
      "<Message domain #{@domain} seq #{@sequence}: #{@template_count} TR #{@data_count} DR>"
    end
    
  end # class Message

end # module IPFIX
