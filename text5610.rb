
require 'ipfix/iana'
require 'ipfix/message'

include IPFIX

model = InfoModel.new.load_default
session = Session.new(model)
message = Message.new(session, 1)

template = Template.new(model, 1001)

template << 'sourceIPv4Address'
template << 'destinationIPv4Address'

message << template

values = {:_ipfix_tid => 1001,
          :sourceIPv4Address => IPAddr.new("127.0.0.1"), 
          :destinationIPv4Address => IPAddr.new("127.0.0.1")}

message << values

s = message.string