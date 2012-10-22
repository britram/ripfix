# coding: UTF-8
#--
# ripfix (IPFIX for Ruby) (c) 2010 Brian Trammell and Hitachi Europe SAS
# Special thanks to the PRISM Consortium (fp7-prism.eu) for its support.
# Distributed under the terms of the GNU Lesser General Public License v3.
#

require 'ipfix/message'
require 'ipfix/exporter'
require 'ipfix/collector'
require 'ipfix/iana'
require 'time'
require 'test/unit'
require_relative 'test-common'

module IPFIX
  class Tests < Test::Unit::TestCase
      
    def test_typesystem
      buf = Buffer.new
      m = InfoModel.new
      
      assert boolean = m.type_for_name('boolean')
      assert uint64 = m.type_for_name('unsigned64')
      assert uint32 = m.type_for_name('unsigned32')
      assert uint16 = m.type_for_name('unsigned16')
      assert uint8 =  m.type_for_name('unsigned8')
      assert int64 = m.type_for_name('signed64')
      assert int32 = m.type_for_name('signed32')
      assert int16 = m.type_for_name('signed16')
      assert int8 =  m.type_for_name('signed8')
      assert mac = m.type_for_name('macAddress')
      assert ip4 = m.type_for_name('ipv4Address')
      assert ip6 = m.type_for_name('ipv6Address')
      assert dtsec = m.type_for_name('dateTimeSeconds')
      assert dtmsec = m.type_for_name('dateTimeMilliseconds')
      assert dtusec = m.type_for_name('dateTimeMicroseconds')
      assert fl32 = m.type_for_name('float32')
      assert fl64 = m.type_for_name('float64')
      assert str = m.type_for_name('string')
    
      assert uint64.encode(buf, 321321321321321)
      assert uint32.encode(buf, 123456)
      assert uint16.encode(buf, 6543)
      assert uint8.encode(buf, 21)
      assert uint32.encode(buf, 567890, 3)
      assert int64.encode(buf, -21321321321321)
      assert int32.encode(buf, 123456)
      assert int16.encode(buf, -6543)
      assert int8.encode(buf, -21)
      assert int32.encode(buf, -567890, 3)
      assert boolean.encode(buf, true)
      assert mac.encode(buf, MACAddress.new("00:01:4e:29:c6:80"))
      assert ip4.encode(buf, IPAddr.new("130.207.244.251"))
      assert ip6.encode(buf, IPAddr.new("fe80::0201:43ff:fe29:c680"))
      assert dtsec.encode(buf, Time.iso8601("2009-05-03T14:30:00"))
      assert dtmsec.encode(buf, Time.iso8601("2009-05-03T14:29:47.500"))
      #assert dtusec.encode(buf, Time.iso8601("2009-05-03T14:29:47.456789"))
      assert fl32.encode(buf, 1098765.4321)
      assert fl64.encode(buf, 12345678.901)
      assert str.encode(buf, "foo")
      assert str.encode(buf, "bar", 6)
      assert str.encode(buf, "qüüx")
    
      assert_equal(321321321321321, uint64.decode(buf))
      assert_equal(123456, uint32.decode(buf))
      assert_equal(6543, uint16.decode(buf))
      assert_equal(21, uint8.decode(buf))
      assert_equal(567890, uint32.decode(buf, 3))   
      assert_equal(-21321321321321, int64.decode(buf))
      assert_equal(123456, int32.decode(buf))
      assert_equal(-6543, int16.decode(buf))
      assert_equal(-21, int8.decode(buf))
      assert_equal(-567890, int32.decode(buf, 3))   
      assert_equal(true, boolean.decode(buf))  
      assert_equal(MACAddress.new("00:01:4e:29:c6:80"), mac.decode(buf))
      assert_equal(IPAddr.new("130.207.244.251"), ip4.decode(buf))
      assert_equal(IPAddr.new("fe80::0201:43ff:fe29:c680"), ip6.decode(buf))
      assert_equal(Time.iso8601("2009-05-03T14:30:00"), dtsec.decode(buf))
      assert_equal(Time.iso8601("2009-05-03T14:29:47.500"), dtmsec.decode(buf))
      # precision hack
      #assert_equal(Time.iso8601("2009-05-03T14:29:47.456789016"), dtusec.decode(buf))
      assert_equal(1098765.4321.to_i, fl32.decode(buf).to_i)
      assert_equal(12345678.901.to_i, fl64.decode(buf).to_i)
      assert_equal("foo", str.decode(buf))
      assert_equal("bar", str.decode(buf, 6))
      assert_equal("qüüx", str.decode(buf))
    end
    
    def test_template_transcode
      buf = Buffer.new
    
      assert m = InfoModel.new.load_default
      assert m.ie_for_spec("flowStartMilliseconds").hashkey = :stamp
      assert m.ie_for_spec("sourceIPv4Address").hashkey = :sip
      
      assert t = Template.new(m, 3333)
      assert(t << "flowStartMilliseconds" << 
                  "sourceIPv4Address" <<
                  "octetDeltaCount[4]")
      assert_equal(16, t.min_length)
            
      h0 = {:stamp => Time.iso8601("2009-05-03T14:29:47.500"),
            :sip => IPAddr.new("130.207.244.251"),
            :octetDeltaCount => 5309,
            :unencodedElement => "not encoded"}
    
      assert t.encode_hash(buf, h0)
      
      assert h1 = t.decode_hash(buf)  
      assert_equal(Time.iso8601("2009-05-03T14:29:47.500"),
                   h1[:stamp])
      assert_equal(IPAddr.new("130.207.244.251"),
                   h1[:sip])
      assert_equal(5309, h1[:octetDeltaCount])
      assert_nil(h1[:unencodedElement])
    end
    
    def test_template_encode
      buf = Buffer.new
      
      assert m = InfoModel.new.load_default.load_reverse
      
      assert t = Template.new(m, 3333)
      assert(t << "flowStartMilliseconds" << 
                  "sourceIPv4Address" <<
                  "octetDeltaCount[4]" <<
                  "reverseOctetDeltaCount[4]")
      assert_equal(20, t.min_length)
      t.encode_template_record(buf)
      
      ss = Array.new
      s = Template.decode_template_record(m, buf)
      s.each { |ie| ss << ie }
      
      assert_equal('flowStartMilliseconds', ss[0].name)
      assert_equal('sourceIPv4Address', ss[1].name)
      assert_equal('octetDeltaCount', ss[2].name)
      assert_equal(4, ss[2].size)
      assert_equal('reverseOctetDeltaCount', ss[3].name)
      assert_equal(4, ss[3].size)
      
    end
    
    def test_message_roundtrip

      assert model = TestCommons.model
      assert osession = Session.new(model)
      assert omsg = Message.new(osession, 330)

      TestCommons.templates(model).each { |t| assert omsg << t }
      
      exported = TestCommons.exported
      expected = TestCommons.expected
      
      exported.each { |h| assert omsg << h }
            
      assert isession = Session.new(model)
      assert imsg = Message.new(isession, omsg.string)
      
      imsg.each_with_index do |h, i|
        assert_equal(expected[i], h[0])
      end
    end

    def test_file_roundtrip
       runs = 5000
     
       assert model = TestCommons.model
       exported = TestCommons.exported
       expected = TestCommons.expected
       
       FileWriter.open("ripfix-test.ipfix", model, 330) do |fw|
         TestCommons.templates(model).each { |t| assert fw << t }
         runs.times do 
           exported.each { |h| assert fw << h }            
         end
       end
     
       FileReader.open("ripfix-test.ipfix", model) do |fr|
         count = 0
         fr.each do |h|
           assert_equal(expected[count % expected.length], h)
           count = count + 1
         end
         assert_equal(runs * expected.length, count)
       end
     end
     
     # def test_udp_simple
     #   runs = 100
     #   
     #   assert model = TestCommons.model
     #   exported = TestCommons.exported
     #   expected = TestCommons.expected
     #   
     #   collector = Thread.new do
     #     assert cp = UDPCollector.new('localhost', 4739, model)
     #   
     #     count = 0
     #     cp.each do |h|
     #       assert_equal(expected[count % expected.length], h)
     #       count = count + 1
     #     end
     # 
     #     assert_equal(runs * expected.length, count)
     #   
     #     cp.close
     #     cps.close
     #   end
     #   
     #   exporter = Thread.new do 
     #     assert ep = UDPExporter.new('localhost', 4739, model, 7654)
     #     ep.message.mtu = 576
     #   
     #     TestCommons.templates(model).each { |t| assert ep << t }
     #     runs.times do 
     #       exported.each { |h| assert ep << h }
     #     end
     # 
     #     ep.close
     #   end
     #   
     #   exporter.join
     #   collector.join
     #   
     # end

     
     def test_tcp_simple
       runs = 100
       
       assert model = TestCommons.model
       exported = TestCommons.exported
       expected = TestCommons.expected
       
       collector = Thread.new do
         assert cps = TCPCollectorServer.new('localhost', 4739, model)
         assert cp = cps.next_collector
       
         count = 0
         cp.each do |h|
           assert_equal(expected[count % expected.length], h)
           count = count + 1
         end
     
         assert_equal(runs * expected.length, count)
       
         cp.close
         cps.close
       end
       
       exporter = Thread.new do 
         assert ep = TCPExporter.new('localhost', 4739, model, 7654)
         ep.message.mtu = 576
       
         TestCommons.templates(model).each { |t| assert ep << t }
         runs.times do 
           exported.each { |h| assert ep << h }
         end
     
         ep.close
       end
       
       exporter.join
       collector.join
       
     end
 

  end
end


