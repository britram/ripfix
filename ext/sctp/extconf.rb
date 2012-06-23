require 'mkmf'

have_func('sctp_send') && sctp = 1
have_library('sctp','sctp_send') && sctp = 1

if (sctp)
  have_func('getaddrinfo')
  have_header('netdb.h')
  have_header('netinet/sctp.h')
  $defs.push("-DSCTP_SUPPORT=1")
end

create_makefile('sctp/endpoint')