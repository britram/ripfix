require 'sctp/endpoint'
require 'test/unit'
require 'ipfix/sctp'
require 'ipfix/iana'

require_relative 'test-common'

module SCTP
  class Tests < Test::Unit::TestCase
  
    def test_1to1
      server = Thread.new do
        assert e = Endpoint.new("localhost", 43331, {passive: true})
        assert ee = e.accept
        m = ee.recvmsg
        assert_equal("test TSET TEST tset", m.string)
        assert_equal("127.0.0.1", m.host)
        assert_equal(1, m.stream)
        ee.sendmsg(Message.new("ok KO OK ko", nil, nil, 1))
        ee.close
        e.close        
     end
     
     sleep(0.5)
     
     client = Thread.new do
        assert e = Endpoint.new("localhost", 43331)
        assert e.sendmsg(Message.new("test TSET TEST tset", nil, nil, 1));
        m = e.recvmsg
        assert_equal("ok KO OK ko", m.string)
        assert_equal("127.0.0.1", m.host)
        assert_equal(1, m.stream)
        e.close
      end
      
      client.join
      server.join
    end
    
    def test_1tomany
      server = Thread.new do
        assert e = Endpoint.new("localhost", 43332, {passive: true, one_to_many: true})
        m = e.recvmsg
        assert_equal("test TSET TEST tset", m.string)
        assert_equal("127.0.0.1", m.host)
        assert_equal(2, m.stream)
        m = Message.new("ok KO OK ko", m.host, m.port, 2)
        e.sendmsg(m)
        e.close
      end
      
      sleep(0.5)
      
      client = Thread.new do
        assert e = Endpoint.new(nil, nil, {one_to_many: true})
        begin
          assert e.sendmsg(Message.new("test TSET TEST tset", "localhost", 43332, 2));
        rescue Exception
          puts "sendmsg fail"
        end
          
        m = e.recvmsg
        assert_equal("ok KO OK ko", m.string)
        assert_equal("127.0.0.1", m.host)
        assert_equal(2, m.stream)
        e.close
      end
      
      client.join
      server.join
    end    
  end
end

module IPFIX
  class SCTPTests < Test::Unit::TestCase
    
    def test_sctp_simple
      runs = 10
      
      assert model = TestCommons.model
      exported = TestCommons.exported
      expected = TestCommons.expected
      
      mutex = Mutex.new

      ccount = 0
      ecount = 0
      pcount = 0
      export_done = false
      
      collector = Thread.new do
        assert cp = SCTPCollector.new('localhost', 4739, model)
        
        cp.each do |h|
          mutex.synchronize do
            assert_equal(expected[ccount % expected.length], h)
            ccount += 1
            pcount -= 1
            #puts "collector got record #{ccount}, #{pcount} pending"
            if export_done && pcount == 0
              cp.interrupt
            end
          end
        end
    
        assert_equal(runs * expected.length, ccount)
      
        cp.close
      end
      
      exporter = Thread.new do 
        assert ep = SCTPExporter.new('localhost', 4739, model, 7654)
        ep.message.mtu = 576
      
        TestCommons.templates(model).each { |t| assert ep << t }
        runs.times do 
          exported.each do |h| 
            mutex.synchronize do 
              assert ep << h
              ecount += 1
              pcount += 1            
              #puts "exporter sent record #{ecount}, #{pcount} pending"
            end
          end
        end
    
        export_done = true
        ep.close
      end
      
      exporter.join
      collector.join
      
    end
    
  end
end
