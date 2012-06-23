#if SCTP_SUPPORT

#include "ruby.h"
#include "ruby/io.h"

#include <unistd.h>
#include <stdio.h>

#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/sctp.h>
#include <netdb.h>
#include <fcntl.h>

VALUE rb_mSCTP;
VALUE rb_cEndpoint;
VALUE rb_eRuntime;

VALUE rb_sIPv6;
VALUE rb_sOneToMany;
VALUE rb_sStreamsIn;
VALUE rb_sStreamsOut;

ID rb_sToS;
ID rb_sString;
ID rb_sHost;
ID rb_sPort;
ID rb_sStream;
ID rb_sSockaddr;
ID rb_sSendFailed;
ID rb_sAssocUp;
ID rb_sAssocDown;

ID rb_ivPeerHost;
ID rb_ivPeerPort;
ID rb_ivMessageClass;
ID rb_ivMessageContext;
ID rb_ivConnectedFlag;

typedef struct endpoint_st {
    int             fd;
    int             af;
    int             socktype;
    int             blocking;
    struct addrinfo *last_ai;
    struct addrinfo *bind_ai;
} endpoint_t;

static void endpoint_free(void *ve)
{
    endpoint_t *e = (endpoint_t *)ve;
    
    if (e->last_ai) {
        freeaddrinfo(e->last_ai);
        e->last_ai = NULL;
    }

    if (e->bind_ai) {
        freeaddrinfo(e->bind_ai);
        e->bind_ai = NULL;
    }

    if (e->fd > 0) {
        close(e->fd);
    }
    
    free(e);
}

static VALUE endpoint_alloc(VALUE klass)
{
    endpoint_t *ep;
  
    return Data_Make_Struct(klass, endpoint_t, NULL, endpoint_free, ep);
}

static VALUE elladdrsock(VALUE self, VALUE sockaddr)
{
    struct sockaddr     *sa = (struct sockaddr *)RSTRING_PTR(sockaddr);
    char                abuf[64];
    const char          *addr;
    uint16_t            port;
    VALUE               addrv, portv;

    if (sa->sa_family == AF_INET) {
        addr = inet_ntop(AF_INET, &((struct sockaddr_in *)sa)->sin_addr, 
                         abuf, sizeof(abuf));
        port = ntohs(((struct sockaddr_in *)sa)->sin_port);
    } else if (sa->sa_family == AF_INET6) {
        addr = inet_ntop(AF_INET6, &((struct sockaddr_in6 *)sa)->sin6_addr, 
                         abuf, sizeof(abuf));
        port = ntohs(((struct sockaddr_in6 *)sa)->sin6_port);
    } else {
        rb_fatal("message from the moon (AF %u)", sa->sa_family);
    }
    
    addrv = rb_str_new2(addr);
    portv = UINT2NUM(port);

    return rb_assoc_new(addrv, portv);
}

static VALUE ellsockaddr(VALUE self, VALUE host, VALUE port, VALUE passive)
{
    endpoint_t      *e;
    struct addrinfo **ai;
    struct addrinfo *tai;
    struct addrinfo hints;
    char   *hostcp, *portcp;
    
    Data_Get_Struct(self, endpoint_t, e);
    ai = RTEST(passive) ? &e->bind_ai : &e->last_ai;
    
    if (*ai) {
        freeaddrinfo(*ai);
        *ai = NULL;
    }
    
    if (RTEST(host)) {
        host = StringValue(host);
        hostcp = RSTRING_PTR(host);
    } else {
        hostcp = NULL;
    }
    
    if (RTEST(port)) {
        port = rb_funcall(port, rb_sToS, 0);
        port = StringValue(port);
        portcp = RSTRING_PTR(port);
    } else {
        portcp = NULL;
    }

    memset(&hints, 0, sizeof(hints));
    hints.ai_flags = AI_ADDRCONFIG;
    hints.ai_flags |= RTEST(passive) ? AI_PASSIVE : 0;
    hints.ai_family = e->af;
    hints.ai_socktype = SOCK_STREAM; /* HACK. No SCTP support for addrinfo. */
    hints.ai_protocol = IPPROTO_TCP; /* HACK. No SCTP support for addrinfo. */
    if (getaddrinfo(hostcp, portcp, &hints, ai)) {
        rb_sys_fail("getaddrinfo(3)");
    }
    
    /* seek through the addrinfo list until we have a compatible AF */
    for (tai = *ai; tai && (tai->ai_family != e->af); tai = tai->ai_next);
    
    if (tai) {
        return rb_str_new((const char *)tai->ai_addr, tai->ai_addrlen);
    } else {
        rb_raise(rb_eRuntime, "Cannot resolve %s", RSTRING_PTR(host));
    }
}

static VALUE ellinit_accepted(VALUE self, VALUE sockfd, VALUE sockaddr, VALUE parent)
{
    endpoint_t                  *e;
    struct sockaddr     *sa = (struct sockaddr *)RSTRING_PTR(sockaddr);
    VALUE hpp;
    
    Data_Get_Struct(self, endpoint_t, e);

    e->fd = NUM2INT(sockfd);
    e->af = sa->sa_family;
    e->socktype = SOCK_STREAM;
    
    hpp = elladdrsock(self, sockaddr);

    rb_ivar_set(self, rb_ivPeerHost, rb_ary_entry(hpp, 0));
    rb_ivar_set(self, rb_ivPeerPort, rb_ary_entry(hpp, 1));
    rb_ivar_set(self, rb_ivMessageClass, rb_ivar_get(parent, rb_ivMessageClass));
    rb_ivar_set(self, rb_ivMessageContext, rb_ivar_get(parent, rb_ivMessageContext));
    rb_ivar_set(self, rb_ivConnectedFlag, Qtrue);
    
    return self;
}

static VALUE ellinit(VALUE self, VALUE oh)
{        
    endpoint_t                  *e;
    struct sctp_initmsg         sinit;
    struct sctp_event_subscribe esub;
    VALUE                       v;
    int                         pf;
    
    Data_Get_Struct(self, endpoint_t, e);

    /* Default socket type information */
    pf = PF_INET;
    e->af = AF_INET;
    e->socktype = SOCK_STREAM;
    e->blocking = 1;
    
    /* handle socket type options */
    if (!NIL_P(oh)) {
        /* :ipv6 to enable IPv6 mode */
        if (RTEST(rb_hash_aref(oh, rb_sIPv6))) {
            pf = PF_INET6;
            e->af = AF_INET6;
        }
    
        /* handle :onetomany option */
        if (RTEST(rb_hash_aref(oh, rb_sOneToMany))) {
            e->socktype = SOCK_SEQPACKET;
        }
    }
    
    e->fd = socket(pf, e->socktype, IPPROTO_SCTP);
    if (e->fd == -1) {
        rb_sys_fail("socket(2)");
    }
    
    /* set up SCTP notifications */
    memset(&esub, 0, sizeof(esub));
    esub.sctp_data_io_event = 1;
    if (e->socktype == SOCK_SEQPACKET) {
        esub.sctp_send_failure_event = 1;
        esub.sctp_association_event = 1;
    }

    if (setsockopt(e->fd, IPPROTO_SCTP, SCTP_EVENTS, &esub, sizeof(esub))) {
        rb_sys_fail("notification setsockopt(2)");
    }

    /* set up streams */
    if (!NIL_P(oh)) {

        /* initialize sinit socket option defaults */
        memset(&sinit, 0, sizeof(sinit));
    
        /* get output streams count */
        if (!NIL_P(v = rb_hash_aref(oh, rb_sStreamsOut))) {
            sinit.sinit_num_ostreams = (uint16_t)NUM2UINT(v);
        }
    
        /* get input streams count */
        if (!NIL_P(v = rb_hash_aref(oh, rb_sStreamsIn))) {
            sinit.sinit_max_instreams = (uint16_t)NUM2UINT(v);
        }
    
        /* set socket options */
        if (setsockopt(e->fd, IPPROTO_SCTP, SCTP_INITMSG, &sinit, sizeof(sinit))) {
            rb_sys_fail("initmsg setsockopt(2)");
        }
    }
    
    return self;
}

static VALUE ellclose (VALUE self)
{
    endpoint_t          *e;

    Data_Get_Struct(self, endpoint_t, e);

    if (e->fd > 0) {
        close(e->fd);
        e->fd = 0;
    }
    
    return Qnil;
}

static VALUE ellconnect (VALUE self, VALUE host, VALUE port)
{
    endpoint_t          *e;
    VALUE               sockaddr;
    int                 rc;
    
    Data_Get_Struct(self, endpoint_t, e);

    if (e->fd <= 0) {
        rb_raise(rb_eRuntime, "Cannot connect closed socket");
    }

    sockaddr = ellsockaddr(self, host, port, Qfalse);
    if ((rc = connect(e->fd, (struct sockaddr *)RSTRING_PTR(sockaddr), 
                   RSTRING_LEN(sockaddr))) < 0) {
        rb_sys_fail("connect(2)");
    }
    
    return self;
}


static VALUE ellbind (VALUE self, VALUE host, VALUE port)
{
    endpoint_t          *e;
    VALUE               sockaddr;
    int                 rc;
    
    Data_Get_Struct(self, endpoint_t, e);

    if (e->fd <= 0) {
        rb_raise(rb_eRuntime, "Cannot bind closed socket");
    }

    sockaddr = ellsockaddr(self, host, port, Qtrue);
    if ((rc = bind(e->fd, (struct sockaddr *)RSTRING_PTR(sockaddr), 
                   RSTRING_LEN(sockaddr))) < 0) {
        rb_sys_fail("bind(2)");
    }
    
    return self;
}

static VALUE elllisten (VALUE self, VALUE backlog)
{
    endpoint_t          *e;
    int                 rc;

    Data_Get_Struct(self, endpoint_t, e);

    if (e->fd <= 0) {
        rb_raise(rb_eRuntime, "Cannot listen on closed socket");
    }

    if ((rc = listen(e->fd, NUM2INT(backlog))) < 0) {
        rb_sys_fail("listen(2)");
    }
    
    return self;
}

typedef struct llaccept_args_st {
    int                     rc;
    int                     fd;
    struct sockaddr_storage from;
    socklen_t               fromlen;
} llaccept_args_t;

static VALUE ellaccept_inner (void *vpargs)
{
    llaccept_args_t    *args = (llaccept_args_t *)vpargs;
    
    args->rc = accept(args->fd, (struct sockaddr *)&args->from, &args->fromlen);
    return (args->rc < 0) ? Qfalse : Qtrue;    
}

static VALUE ellaccept (VALUE self)
{
    endpoint_t              *e;
    llaccept_args_t         args;
    VALUE                   sockaddr, nep;
    
    Data_Get_Struct(self, endpoint_t, e);

    if (e->fd <= 0) {
        rb_raise(rb_eRuntime, "Cannot accept on closed socket");
    }

    /* Initialize args */
    args.fd = e->fd;
    args.fromlen = sizeof(args.from);

    if (e->blocking) {
        /* Release the GIL if we're blocking */
        while (rb_thread_wait_fd(args.fd),
               !RTEST(rb_thread_blocking_region(ellaccept_inner, 
                                                &args, RUBY_UBF_IO, 0)))
        {
            rb_sys_fail("accept(2)");
        }
    } else {
        /* NBIO means hang out and wait. */
        if (!RTEST(ellaccept_inner(&args))) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                return Qnil;
            } else {
                rb_sys_fail("accept(2)");
            }
        }
    }

    /* Create sockaddr */
    sockaddr = rb_str_new((const char *)&args.from, args.fromlen);

    /* Allocate new endpoint wrapped around the socket */
    nep = endpoint_alloc(RBASIC(self)->klass);
    
    /* And initialize it */
    return ellinit_accepted(nep, INT2NUM(args.rc), sockaddr, self);
}   
    
typedef struct llsendmsg_args_st {
    int             rc;
    int             fd;
    const void      *msg;
    size_t          len;
    struct sockaddr *to;
    socklen_t       tolen;
    uint32_t        ppid;
    uint32_t        flags;
    uint16_t        stream_no;
    uint16_t        timetolive;
    uint32_t        context;
} llsendmsg_args_t;

static VALUE ellsendmsg_inner(void *vpargs)
{
    llsendmsg_args_t *args = (llsendmsg_args_t *)vpargs;
    
    args->rc = sctp_sendmsg(args->fd, args->msg, args->len,
                            args->to, args->tolen,
                            args->ppid, args->flags, args->stream_no,
                            args->timetolive, args->context);
    
    return (args->rc < 0) ? Qfalse : Qtrue;
}

static VALUE ellsendmsg(VALUE self, VALUE msg)
{
    endpoint_t          *e;
    VALUE               msg_str;
    VALUE               msg_host = Qnil;
    VALUE               msg_port = Qnil;
    VALUE               msg_stream = Qnil;
    VALUE               sockaddr = Qnil;

    llsendmsg_args_t    args;
    
    memset(&args, 0, sizeof(args));
    
    Data_Get_Struct(self, endpoint_t, e);

    if (e->fd <= 0) {
        rb_raise(rb_eRuntime, "Cannot sendmsg to closed socket");
    }

    args.fd = e->fd;

    msg_str = rb_funcall(msg, rb_sString, 0);
    args.msg = RSTRING_PTR(msg_str);
    args.len = RSTRING_LEN(msg_str);

    if (rb_respond_to(msg, rb_sSockaddr)) {
        sockaddr = rb_funcall(msg, rb_sSockaddr, 0);
    }

    if (!RTEST(sockaddr)) {
        if (rb_respond_to(msg, rb_sHost)) {
            msg_host = rb_funcall(msg, rb_sHost, 0);
        }
        
        if (rb_respond_to(msg, rb_sPort)) {
            msg_port = rb_funcall(msg, rb_sPort, 0);
        }

        if (RTEST(msg_host) && RTEST(msg_port)) {
            sockaddr = ellsockaddr(self, msg_host, msg_port, Qfalse);
        }
    }

    if (rb_respond_to(msg, rb_sStream)) {
        msg_stream = rb_funcall(msg, rb_sStream, 0);
    }
    if (msg_stream == Qnil) {
        args.stream_no = 0;
    } else {
        args.stream_no = (uint16_t)NUM2UINT(msg_stream);
    }
    
    if (RTEST(sockaddr)) {
        args.to = (struct sockaddr *)RSTRING_PTR(sockaddr);
        args.tolen = RSTRING_LEN(sockaddr);
    } else {
        args.to = NULL;
        args.tolen = 0;
    }

    if (e->blocking) {
        /* release the GIL if we're blocking */
        if (!rb_thread_blocking_region(ellsendmsg_inner, &args, RUBY_UBF_IO, 0)) {
            rb_sys_fail("sctp_sendmsg(2)");
        }
    } else {
        /* NBIO means hang out and wait. */
        if (!RTEST(ellsendmsg_inner(&args))) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                return Qnil;
            } else {
                rb_sys_fail("sctp_recvmsg(2)");
            }
        }
    }
    
    return UINT2NUM(args.rc);
}

static VALUE ellnotdispatch (VALUE self, VALUE noti, VALUE host, VALUE port)
{
    union sctp_notification *snp = (union sctp_notification *)RSTRING_PTR(noti);

    struct sctp_assoc_change *sac;
    struct sctp_send_failed *ssf;

    switch (snp->sn_header.sn_type) {
      case SCTP_ASSOC_CHANGE:
        sac = &snp->sn_assoc_change;
        switch (sac->sac_state) {
          case SCTP_COMM_UP:
          case SCTP_RESTART:
            rb_funcall(self, rb_sAssocUp, 2, host, port);
            break;
          case SCTP_COMM_LOST:
          case SCTP_SHUTDOWN_COMP:
          case SCTP_CANT_STR_ASSOC:
            rb_funcall(self, rb_sAssocDown, 2, host, port);
            break;
            break;
          default:
            break;
        }
        break;
      case SCTP_SEND_FAILED:
        ssf = &snp->sn_send_failed;
        rb_funcall(self, rb_sSendFailed, 3, host, port, UINT2NUM(ssf->ssf_error));
        break;
      default:
        fprintf(stderr, "Unexpected SCTP notification\n");
        break;
    }
    
    return Qnil;
}

typedef struct llrecvmsg_args_st {
    int                     rc;
    int                     fd;
    void                    *msg;
    size_t                  len;
    struct sockaddr_storage from;
    socklen_t               fromlen;
    struct sctp_sndrcvinfo  sinfo;
    int                     flags;
} llrecvmsg_args_t;


static VALUE ellrecvmsg_inner (void *vpargs)
{
    llrecvmsg_args_t    *args = (llrecvmsg_args_t *)vpargs;
    
    args->rc = sctp_recvmsg(args->fd, args->msg, args->len, 
                            (struct sockaddr *)&args->from, 
                            &args->fromlen, &args->sinfo, &args->flags);
    return (args->rc < 0) ? Qfalse : Qtrue;
}

static VALUE ellrecvmsg (VALUE self, VALUE maxlen)
{
    endpoint_t          *e;
    VALUE               msg, str, msginit_argv[1];
    VALUE               sockaddr, hpp;

    llrecvmsg_args_t    args;

    Data_Get_Struct(self, endpoint_t, e);
    
    if (e->fd <= 0) {
        rb_raise(rb_eRuntime, "Cannot recvmsg from closed socket");
    }

    /* Loop to handle notifications */
    while (1) {

        /* Clear args array */
        memset(&args, 0, sizeof(args));

        /* Pass socket to args array */
        args.fd = e->fd;

        /* Create string to hold message */
        args.len = NUM2INT(maxlen);
        str = rb_tainted_str_new(0, args.len);
        args.msg = RSTRING_PTR(str);

        /* Set length of sockaddr buffer */
        args.fromlen = sizeof(args.from);

        if (e->blocking) {
            /* Release the GIL if we're blocking */
            while (rb_thread_wait_fd(args.fd),
                   !RTEST(rb_thread_blocking_region(ellrecvmsg_inner, 
                                                    &args, RUBY_UBF_IO, 0)))
            {
                rb_sys_fail("sctp_recvmsg(2)");
            }
        } else {
            /* NBIO means hang out and wait. */
            if (!RTEST(ellrecvmsg_inner(&args))) {
                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    return Qnil;
                } else {
                    rb_sys_fail("sctp_recvmsg(2)");
                }
            }
        }

        /* Truncate string to recieved message length */
        if (args.rc < RSTRING_LEN(str)) {
            rb_str_set_len(str, args.rc);
        }
        
        /* Create sockaddr */
        sockaddr = rb_str_new((const char *)&args.from, args.fromlen);
        hpp = elladdrsock(self, sockaddr);

        if (args.flags & MSG_NOTIFICATION) {
            /* Handle notification */
            ellnotdispatch(self, str, rb_ary_entry(hpp, 0), rb_ary_entry(hpp, 1));
        } else {
            /* Done. */
            break;
        }
    }

    /* Create a new Message */
    msginit_argv[0] = str;
    msginit_argv[1] = rb_ary_entry(hpp, 0);
    msginit_argv[2] = rb_ary_entry(hpp, 1);
    msginit_argv[3] = INT2NUM(args.sinfo.sinfo_stream);
    msginit_argv[4] = rb_ivar_get(self, rb_ivMessageContext);
    msg = rb_class_new_instance(5, msginit_argv, rb_ivar_get(self, rb_ivMessageClass));
    
    return msg;
}

static VALUE ellblock (VALUE self)
{
    endpoint_t          *e;
    int                 flags;

    Data_Get_Struct(self, endpoint_t, e);

    if (e->fd <= 0) {
        rb_raise(rb_eRuntime, "Cannot get blocking on closed socket");
    }
    
    flags = fcntl(e->fd, F_GETFL, 0);
    
    if (flags & O_NONBLOCK) {
        return Qfalse;
    } else {
        return Qtrue;
    }
}

static VALUE ellblockassign (VALUE self, VALUE blockp)
{
    endpoint_t          *e;
    int                 flags;
    
    Data_Get_Struct(self, endpoint_t, e);

    if (e->fd <= 0) {
        rb_raise(rb_eRuntime, "Cannot set blocking on closed socket");
    }

    if (RTEST(blockp)) {
        flags = fcntl(e->fd, F_GETFL, 0);
        fcntl(e->fd, F_SETFL, flags & ~O_NONBLOCK);        
        e->blocking = 1;
    } else {
        flags = fcntl(e->fd, F_GETFL, 0);
        fcntl(e->fd, F_SETFL, flags | O_NONBLOCK);
        e->blocking = 0;
    }
    
    return blockp;
}

void Init_endpoint()
{
    rb_require("stringio");

    rb_mSCTP = rb_define_module("SCTP");
    rb_cEndpoint = rb_define_class_under(rb_mSCTP, "Endpoint", rb_cObject);
    
    rb_eRuntime = rb_const_get(rb_cObject, rb_intern("RuntimeError"));

    rb_sIPv6 = ID2SYM(rb_intern("ipv6"));
    rb_sOneToMany = ID2SYM(rb_intern("one_to_many"));
    rb_sStreamsIn = ID2SYM(rb_intern("streams_in"));
    rb_sStreamsOut = ID2SYM(rb_intern("streams_out"));  

    rb_sToS =           rb_intern("to_s");
    rb_sString =        rb_intern("string");
    rb_sHost =          rb_intern("host");
    rb_sPort =          rb_intern("port");
    rb_sStream =        rb_intern("stream");
    rb_sSockaddr =      rb_intern("sockaddr");

    rb_sSendFailed =    rb_intern("post_send_failed");
    rb_sAssocUp =       rb_intern("post_association_up");
    rb_sAssocDown =     rb_intern("post_association_down");
    
    rb_ivPeerHost =      rb_intern("@peer_host");
    rb_ivPeerPort =      rb_intern("@peer_port");
    rb_ivMessageClass =  rb_intern("@message_class");
    rb_ivMessageContext= rb_intern("@message_context");
    rb_ivConnectedFlag = rb_intern("@connected_flag");

    rb_define_alloc_func(rb_cEndpoint, endpoint_alloc);
    rb_define_method(rb_cEndpoint, "llinit", ellinit, 1);
    
    rb_define_method(rb_cEndpoint, "llconnect", ellconnect, 2);
    rb_define_method(rb_cEndpoint, "llbind", ellbind, 2);
    rb_define_method(rb_cEndpoint, "lllisten", elllisten, 1);
    rb_define_method(rb_cEndpoint, "llaccept", ellaccept, 0);
    rb_define_method(rb_cEndpoint, "llclose", ellclose, 0);
    
    rb_define_method(rb_cEndpoint, "llsendmsg", ellsendmsg, 1);
    rb_define_method(rb_cEndpoint, "llrecvmsg", ellrecvmsg, 1);
    
    rb_define_method(rb_cEndpoint, "llblock?", ellblock, 1);
    rb_define_method(rb_cEndpoint, "llblock=", ellblockassign, 1);
    rb_define_method(rb_cEndpoint, "llsockaddr", ellsockaddr, 3);
    rb_define_method(rb_cEndpoint, "lladdrsock", elladdrsock, 1);
}

#endif /* SCTP_SUPPORT */