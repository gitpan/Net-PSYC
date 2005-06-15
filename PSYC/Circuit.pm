package Net::PSYC::Circuit;

$VERSION = '0.4';
use vars qw($VERSION);

use strict;
use Carp;
use Socket;
use IO::Socket::INET;

use Net::PSYC::MMP::State;
use Net::PSYC::Event qw(add watch);

INIT {
    require Net::PSYC;
    import Net::PSYC qw(W sendmsg same_host send_mmp parse_uniform AUTOWATCH makeMSG make_psyc parse_psyc parse_mmp PSYC_PORT PSYCS_PORT register_host register_route make_mmp UNL);
}

sub listen {
	# looks funky.. eh? undef makes IO::Socket handle INADDR_ANY properly
	# whereas '' causes an exception. stupid IO::Socket if you ask me.
    my $socket = IO::Socket::INET->new(
			LocalAddr => $_[1] || undef,
				    # undef == use INADDR_ANY
                        LocalPort => $_[2] || undef,
				    # undef == take any port
                        Proto => 'tcp',
                        Listen => 7,
		        Blocking => 0,
                        Reuse => 1)
	|| (croak('TCP bind to '.($_[1] || '127.0.0.1')
		 .':'.($_[2] || 'any')." says: $!") && return 0);
    my $self = { 
	'SOCKET' => $socket,
	'IP' => $socket->sockhost(),
	'PORT' => $_[2] || $socket->sockport,
	'LAST_RECV' => getsockname($socket),
	'TYPE' => 'c',
	'_options' => $_[3],
    };
    W("TCP Listen $self->{'IP'}:$self->{'PORT'} successful.");
    bless $self, 'Net::PSYC::Circuit::L';
    watch($self) if AUTOWATCH();
    return $self;
}

#   new ( \*socket, vars )
sub new {
    my ($class, $socket, $vars) = @_;
    my $self = {
	'_options' => (ref $vars eq 'HASH') ? $vars : {},
	'SOCKET' => $socket,
	'TYPE' => 'c',
	'I_BUFFER' => '',
	'O_BUFFER' => [],
	'O_COUNT' => 0,
	'IP' => $socket->sockhost(),
	'PORT' => $socket->sockport(),
	'R_IP' => $socket->peerhost(),
	'R_PORT' => $socket->peerport(),
	'LAST_RECV' => $socket->peername(),
	'CACHE' => {}, # cache for fragmented data
	'I_LENGTH' => 0, # whether _length of incomplete
			 # packets exceeds buffer-length
	'FRAGMENT_COUNT' => 0,
	'L' => 0,
    };
    bless $self, 'Net::PSYC::Circuit::C';

    $self->{'L'} = 1 if (caller() eq 'Net::PSYC::Circuit::L');
    
    $self->{'_state'} = new Net::PSYC::MMP::State($self);
    $self->{'_state'}->init();
    
    $self->{'R_HOST'} = gethostbyaddr($socket->peeraddr(), AF_INET) || $self->{'R_IP'};
    $self->{'peeraddr'} = "psyc://$self->{'R_HOST'}:$self->{'R_PORT'}/"; 
    $Net::PSYC::C{"$self->{'R_IP'}\:$self->{'R_PORT'}"} = $self;
    
    register_host($self->{'R_IP'}, inet_ntoa($socket->peeraddr()));
    register_host($self->{'R_IP'}, $self->{'R_HOST'}) if ($self->{'R_HOST'});
    register_host('127.0.0.1', $self->{'IP'});
    register_host('127.0.0.1', 'localhost');
    $self->TRUST(11) if (same_host('127.0.0.1', $self->{'R_IP'}));
    register_route("$self->{'R_HOST'}\:$self->{'R_PORT'}", $self);
    register_route(inet_ntoa($socket->peeraddr()).":$self->{'R_PORT'}", $self);

    W("TCP: Connected with $self->{'R_IP'}\:$self->{'R_PORT'}", 1);
    watch($self) if AUTOWATCH();
    
    my $source = (UNL() ne '/') ? { _source => UNL() } : {};
    $self->{'greet'} = make_mmp(
    {
	'_target' => $self->{'peeraddr'},
	%$source,
    },
    make_psyc('_notice_circuit_established', 
		    'Connection to [_source] established!')); 
    $self->{'greet'} .= make_mmp(
    {}, 
    make_psyc('_status_circuit','',
	$self->{'_options'})
    );
    if (!AUTOWATCH() || $self->{'L'} || $Net::PSYC::ANACHRONISM) {
	# fire!
	$self->{'r_options'} = {};
	syswrite($self->{'SOCKET'}, ".\n");
	syswrite($self->{'SOCKET'}, delete $self->{'greet'});
    }
    
    return $self;
}

sub connect {
    my $socket = IO::Socket::INET->new(Proto     => 'tcp',
                                       PeerAddr  => $_[1],
				       Blocking	=> 1,
                                       PeerPort  => $_[2] || PSYC_PORT() );
    if (!$socket) {
	W("TCP connect to $_[1]:".($_[2]||PSYC_PORT())." says: $!", 0);
	return 0;
    }
    return Net::PSYC::Circuit->new($socket, $_[3]);
}

# TCP connection class
package Net::PSYC::Circuit::C;


use bytes;
use strict;
use vars qw(@ISA);

use Carp;

use Net::PSYC::Hook;

INIT {
    require Net::PSYC;
    import Net::PSYC qw(W sendmsg same_host send_mmp parse_uniform AUTOWATCH makeMSG make_psyc parse_psyc parse_mmp make_mmp register_route register_host);
}

@ISA = qw(Net::PSYC::Hook);

sub TRUST {
    my $self = shift;
    if ($_[0]) {
	$self->{'TRUST'} = $_[0];
    }
    return $self->{'TRUST'} || 3;
}

sub use_module {
    my $self = shift;
    my $mod = shift;
}

sub tls_init_server { 1 }
sub tls_init_client {
    my $self = shift;
    my $t = IO::Socket::SSL->start_SSL($self->{'SOCKET'}); 
#	SSL_server => ($self->{'L'}) ? 1 : 0);
    if (ref $t ne 'IO::Socket::SSL') {
	return 1;
    }
    W("Using encryption to $self->{'peeraddr'}.",0);
    $self->{'SOCKET'} = $t;
    if (AUTOWATCH()) {
	Net::PSYC::Event::forget($self);
	Net::PSYC::Event::watch($self);
	Net::PSYC::Event::revoke($self->{'SOCKET'}, 'w');
    }
}

sub send {
    my ($self, $target, $data, $vars, $prio) = @_;
    W("send($self, $target, ".($data||'').", ".($vars||'undef').
      ", ".($prio||'undef').")",2);
    if (ref $data eq 'ARRAY') {
	$vars->{'_counter'} = $self->{'FRAGMENT_COUNTER'}++; 
	$vars->{'_amount_fragments'} = scalar(@$data);
    } else {
	$data = [ $data ];
    }

    push(@{$self->{'O_BUFFER'}}, [ $data, $vars, 0 ]);

    $self->{'O_COUNT'} = scalar(@{$self->{'O_BUFFER'}}) - 1 if ($prio);
    
    if (!AUTOWATCH() || $Net::PSYC::ANACHRONISM) { # send the packet instantly
        $self->write();
    } else {
	Net::PSYC::Event::revoke($self->{'SOCKET'}, 'w');
    }
    
    return 0;
}

# no state here! dont use this function unless you have brass balls. i mean it!
sub fire {
    my ($self, $target, $mc, $data, $vars) = @_;
    $vars->{'_target'} = $target if $target;
    my $m = makeMSG($mc, $data, $vars);

    $self->trigger('encrypt', \$m);

    if (!defined(syswrite($self->{'SOCKET'}, $m))) {
	# put the packet back into the queue
	croak($!);
	return 1;
    }
}

sub write () {
    my $self = shift;
    
    # no permission to send packets.. and we are not wierdo enough!
    return 1 unless (exists $self->{'r_options'});
    
    return 1 if (!${$self->{'O_BUFFER'}}[$self->{'O_COUNT'}]); # no packets!
    
    my ($data, $vars, $count) = @{$self->{'O_BUFFER'}->[$self->{'O_COUNT'}]};
    

    $vars->{'_fragment'} = $count if ($vars->{'_amount_fragments'});

    my $d = $data->[$count];
    use Storable qw(dclone);
    $vars = dclone($vars); # we would not need that.. but the current design.. TODO
    $self->trigger('send', $vars, \$d);
    
    my $m = make_mmp($vars, $d);
    $self->trigger('encrypt', \$m);

    if (!defined(syswrite($self->{'SOCKET'}, $m))) {
	# put the packet back into the queue
	croak($!);
	return 1;
    }
    
    $self->trigger('sent', $vars, \$d);
    W("TCP: wrote ".length($m)." bytes of data to the socket",2);     
    W("TCP: >>>>>>>> OUTGOING >>>>>>>>\n$m\nTCP: <<<<<<< OUTGOING <<<<<<<\n",2);
    if (($vars->{'_amount_fragments'} || @$data) == $count + 1) {
	# all fragments of this packet sent
	# delete it..
	splice(@{$self->{'O_BUFFER'}}, $self->{'O_COUNT'}, 1);
    } else {
	# fragments of this packet left
	# increase the fragment-id
	$self->{'O_BUFFER'}->[$self->{'O_COUNT'}]->[2]++;
	# increase the packet id.. 
	$self->{'O_COUNT'}++;
    }
    $self->{'O_COUNT'} = 0 unless ( $self->{'O_BUFFER'}->[$self->{'O_COUNT'}] );
    if ( @{$self->{'O_BUFFER'}} ) {
	if (!AUTOWATCH() || $Net::PSYC::ANACHRONISM) { # send the packet 
	    $self->write();
	} else {
	    Net::PSYC::Event::revoke($self->{'SOCKET'}, 'w');
	}	
    }
    return 1;
}

sub read () {
    my $self = shift;
    my ($data, $read);
    
    # if you change the buffer-size.. remember to fix buffersize of
    # MMP::Compress and rest..
    $read = sysread($self->{'SOCKET'}, $data, 4096);
    
    return if (!$read); # connection lost !?
    # gibt es nen 'richtigen' weg herauszufinden, ob die connection noch lebt?
    # connected() und die ganzen anderen socket-funcs helfen einem da in
    # den ekligen fällen nicht..
    
    $self->trigger('decrypt', \$data);

    
    $$self{'I_BUFFER'} .= $data;
    warn $! unless (defined($read));
    $self->{'I_LENGTH'} += $read;
#    open(file, ">>$self->{'HOST'}:$self->{'PORT'}.in");
#    print file $data;
#    print file "\n========\n";
#    close file;
    W("TCP: Read $read bytes from socket.\n",2);
    Net::PSYC::W("TCP: >>>>>>>> INCOMING >>>>>>>>\n$data\nTCP: <<<<<<< INCOMING <<<<<<<\n",2);
    
    unless ($self->{'LF'}) {
	# we need to check for a leading ".\n"
	# this is not the very best solution though.. 
	if ($self->{'I_LENGTH'} > 2) {
	    if ( $self->{'I_BUFFER'} =~ s/^\.(\r?\n)//g ) {
		$self->{'LF'} = $1;
		# remember if the other side uses \n or \r\n
		# to terminate lines.. we need that for proper
		# and safe parsing
	    } else {
		syswrite($self->{'SOCKET'}, "protocol error\n");
		W("Closed Connection to $self->{'R_HOST'}", 0);
		Net::PSYC::shutdown($self);
	    }
	}
    }
    
    return 1;
}

# return undef if packets are incomplete
# return 0 if there maybe/are still packets in the buffer
# return the packet
sub recv () {
    my $self = shift;
    
    return unless ($self->{'LF'});
    return if ($self->{'I_LENGTH'} < 0 || !$self->{'I_BUFFER'});
    
    my $_v = $self->{'VARS'};
    my ($vars, $data) = parse_mmp(\$$self{'I_BUFFER'}, $self->{'LF'});
    
    return if (!defined($vars));

    if ($vars < 0) {
	$self->{'I_LENGTH'} = $vars;
	return;
    }
    
    $self->trigger('receive', $vars, \$data);
    unless (exists $self->{'me'} || $self->{'L'} || !exists $vars->{'_target'}) {
	$self->{'me'} = $vars->{'_target'};
	my $r = parse_uniform($vars->{'_target'});
	if (ref $r && $r->{'host'}) {
	    register_host('127.0.0.1', $r->{'host'});
	} else {
	    W("unparseable _target",0);
	}
    }
    
    # TODO return -1 unless trigger(). 
     
    unless (exists $vars->{'_source'}) {
	$vars->{'_source'} = "psyc://$self->{'R_IP'}:$self->{'R_PORT'}/";
    } else {
	my $h = parse_uniform($vars->{'_context'}||$vars->{'_source'});
	unless (ref $h) {
	    W("I could not parse that uni: ".($vars->{'_context'}
					     ||$vars->{'_source'}),0);
	    return -1;
	}
	
	unless (same_host($h->{'host'}, $self->{'R_IP'})) {
	    if ($self->TRUST < 5) {
		# just dont relay
		W("TCP: Refused packet from $self->{'R_IP'}. (_source: $vars->{'_source'})", 0);
		return 0;
	    }
	} else {
	    # we will relay for you in the future
	    register_route($vars->{'_source'}, $self);
	}
    }
=skdjf    
    if (exists $vars->{'_source_relay'} && $self->{'_options'}->{'_accept_modules'} =~ /_onion/ && $self->{'r_options'}->{'_accept_modules'} =~ /_onion/) {
	register_route($vars->{'_source_relay'}, $self);
	W("_Onion: Use $self->{'R_IP'} to route $vars->{'_source_relay'}",2);
	# remember pseudo-address to route packets back!
    }
=cut
    ####
    # FRAGMENT
    # handle fragmented data
    if (exists $vars->{'_fragment'}) {
	# {source} {logical target} {counter} [ {fragment} ]
	my $packet_id = '{'.($vars->{'_source'} || '').
			'}{'.($vars->{'_target'} || '').
			'}{'.($vars->{'_counter'} || '').'}';
	if (!exists $self->{'CACHE'}->{$packet_id}) {
	    $self->{'CACHE'}->{$packet_id} = [
		{
		    '_totalLength' => $vars->{'_totalLength'},
		    '_amount_fragments' => $vars->{'_amount_fragments'},
		    '_amount' => 0,
		},
		[]
	    ];
	}
	my $v = $self->{'CACHE'}->{$packet_id}->[0];
	my $c = $self->{'CACHE'}->{$packet_id}->[1];
	# increase the counter
	$v->{'_amount'}++ if (!$c->[$vars->{'_fragment'}]);
	#print STDERR "Fragment: $vars->{'_fragment'} (total: $vars->{'_amount_fragments'}, amount: $v->{'_amount'}, id: '$packet_id')\n";
	    
	$c->[$vars->{'_fragment'}] = $data;
	if ($v->{'_amount'} == $v->{'_amount_fragments'}) {
	    W("TCP: Fragmented packet complete!");
	    $data = join('', @$c);
	} else {
	    return 0;
	}
    }
    ####
    return 0 if ($data eq '');
    
    W("TCP[$vars->{'_source'}] => ".($vars->{'_target'}||''), 2);
    $vars->{'_INTERNAL_origin'} = $self;
    return ($vars, $data);	
}

sub DESTROY {
    my $self = shift;
    $self->{'SOCKET'}->shutdown(0) if $self->{'SOCKET'};
}

# TCP listen class
package Net::PSYC::Circuit::L;

sub read () {
    my $self = shift;
    my $socket = $self->{'SOCKET'}->accept();
    my $obj = Net::PSYC::Circuit->new($socket, $self->{'_options'});
    return 1;
}

sub recv () { }

sub send {
    print "\nTCP: I am listening, not sending! Dont use me that way!\n";
}

sub TRUST {
    print "\nTCP: Dont TRUST() me, I'm only listening.\n";
}

1;
