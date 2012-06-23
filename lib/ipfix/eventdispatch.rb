#
#--
# ripfix (IPFIX for Ruby) (c) 2010 Brian Trammell and Hitachi Europe SAS
# Special thanks to the PRISM Consortium (fp7-prism.eu) for its support.
# Distributed under the terms of the GNU Lesser General Public License v3.
#++
# Defines the event class macro
#

module EventDispatch

# Define an event on this class. An event allows a user of an object to
# specify a block to be executed when something happens inside the object. 
#
# This class-level macro defines two methods, given an event_name: a private 
# post_event_name method, and a public on_event_name method. When 
# post_event_name is called from within a method of an object of this class, 
# it yields the post_event_name argument list to the last block passed to 
# on_event_name.
#     
  
  def event(event_name)
    define_method("post_#{event_name}") do |*args|
      if @_event_handlers && @_event_handlers[event_name]
        @_event_handlers[event_name].call(*args)
      end
    end
    #private("post_#{event_name}")
    define_method("on_#{event_name}") do |&handler|
      @_event_handlers = Hash.new unless @_event_handlers
      @_event_handlers[event_name] = handler
    end
  end
end