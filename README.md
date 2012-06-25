ripfix
======

IPFIX implementation for Ruby

Provides a bridge between records in IPFIX Messages and Ruby hashes. Intended
as a reference implementation

To write Messages
-----------------

0. create a Model (model = InfoModel.new.load_default)

1. create a Session (session = Session.new(m))

2. create a Message within the Session (message = Message.new(nil, session,
   domain))

3. create Templates and append Information Elements via the << operator

4. append Templates to the Message via the << operator

5. append Hashes to the Message via the << operator

6. Get the encoded message using message.string(), or write it to an IO 
   using message.write()

To read Messages
----------------

0. create a Model (model = InfoModel.new.load_default)

1. create a Session (session = Session.new(m))

2. create a Message within the Session from the encoded string containing the Message (message = Message.new(string, session)), or create an empty Message (message = Message.new(nil, session)) and fill it in from an IO (Message.read(io))

3. Iterate over hashes in the message using Message.each().

See the tests for code examples.

