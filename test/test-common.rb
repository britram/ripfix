module IPFIX
  class TestCommons
    
    def self.model
      model = InfoModel.new.load_default.load_reverse
      model.ie_for_spec("flowStartMilliseconds").hashkey = :stamp
      model.ie_for_spec("sourceIPv4Address").hashkey = :sip
      model.ie_for_spec("octetDeltaCount").hashkey = :bytes
      model.ie_for_spec("reverseOctetDeltaCount").hashkey = :rbytes
      model.ie_for_spec("packetDeltaCount").hashkey = :pkts
      model.ie_for_spec("reversePacketDeltaCount").hashkey = :rpkts
      model
    end
    
    def self.templates(model)
      templates = Array.new
      templates << (Template.new(model, 4444) <<
        "flowStartMilliseconds" << 
        "sourceIPv4Address" <<
        "octetDeltaCount[4]" <<
        "reverseOctetDeltaCount[4]")
      templates << (Template.new(model, 4445) <<
        "flowStartMilliseconds" << 
        "sourceIPv4Address" <<
        "packetDeltaCount" <<
        "reversePacketDeltaCount")
      templates
    end
    
    def self.exported
      a = Array.new
      a[0] = { :_ipfix_tid => 4444,
               :stamp => Time.iso8601("2009-05-03T14:29:47.500"),
               :sip => IPAddr.new("1.1.1.1"),
               :bytes => 1111,
               :rbytes => 1111 }
      a[1] = { :_ipfix_tid => 4444,
               :stamp => Time.iso8601("2009-05-03T14:29:47.660"),
               :sip => IPAddr.new("2.2.2.2"),
               :bytes => 2222,
               :rbytes => 2222 }
      a[2] = { :_ipfix_tid => 4445,
               :stamp => Time.iso8601("2009-05-03T14:29:47.750"),
               :sip => IPAddr.new("3.3.3.3"),
               :pkts => 33333,
               :rpkts => 33333 }
      a[3] = { :_ipfix_tid => 4445,
               :stamp => Time.iso8601("2009-05-03T14:29:47.950"),
               :sip => IPAddr.new("4.4.4.4"),
               :pkts => 4444,
               :rpkts => 4444 }
      a
    end

    def self.expected
      a = Array.new
      self.exported.each do |h|
        h.delete(:_ipfix_tid)
        a << h
      end
      a
    end

  end
end