GameNetworkingSockets

connecting:
- B: connect with ip address + secure key ig
- all messages are secured with the key

multiplayer

- for editing maps:
- the server owns the map files
- clients send presence status to all other clients
- clients send an Operation once their line is complete
- clients inverse the Operation and send it to undo
- each Operation affects only one chunk, group multiple together to
  have things that happen over multiple chunks
- when the server recieves the Operation, it finds where you said to
  insert it in sequence, then mutates your operation until it fits at the
  end of the sequence, then sends it out to everyone observing that
  chunk
- the server makes sure everyone has the same operations base in
  the chunk. the client acknowledges which operations it has received.

also operations can be extremely simple because we're not doing text