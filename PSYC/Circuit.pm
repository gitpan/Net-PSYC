package Net::PSYC::Circuit;

$VERSION = '0.1';
use vars qw($VERSION);

use strict;
use Carp;
use Socket;
use IO::Socket::INET;

use Net::PSYC::Event qw(add watch);


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
		 .':'.($_[2] || 'any')." says: $@") && return 0);
    my $self = { 
	'SOCKET' => $socket,
	'IP' => $socket->sockhost(),
	'PORT' => $_[2] || $socket->sockport,
	'LAST_RECV' => getsockname($socket),
	'TYPE' => 'c',
	'_options' => $_[3],
    };
    print STDERR "TCP Listen $self->{'IP'}:$self->{'PORT'} successful.\n"
	if Net::PSYC::DEBUG; #  <---  wie macht man den import richtig?
    bless $self, 'Net::PSYC::Circuit::L';
    watch($self) if Net::PSYC::AUTOWATCH;
    return $self;
}

#   new ( \*socket, vars )
sub new {
    my ($class, $socket, $vars) = @_;
    my $self = {
	'_options' => (ref $vars eq 'HASH') ? $vars : {},
	'r_options' => {},
	'SOCKET' => $socket,
	'TYPE' => 'c',
	'I_BUFFER' => '',
	'O_BUFFER' => [],
	'O_COUNT' => 0,
	'VARS' => {},
	'STATE_MEM' => {},
	'IP' => $socket->sockhost(),
	'PORT' => $socket->sockport(),
	'R_IP' => $socket->peerhost(),
	'R_PORT' => $socket->peerport(),
	'LAST_RECV' => $socket->peerhost(),
	'CACHE' => {}, # cache for fragmented data
	'I_LENGTH' => 0, # whether _length of incomplete
			 # packets exceeds buffer-length
	'FRAGMENT_COUNT' => 0,
    };
    bless $self, 'Net::PSYC::Circuit::C';
    
    $self->{'R_HOST'} = gethostbyaddr($socket->peeraddr(), AF_INET) || $self->{'R_IP'};
    
    $Net::PSYC::C{"$self->{'R_IP'}\:$self->{'R_PORT'}"} = $self;
    
    Net::PSYC::register_host($self->{'R_IP'}, inet_ntoa($socket->peeraddr()));
    Net::PSYC::register_host($self->{'R_IP'}, $self->{'R_HOST'}) if ($self->{'R_HOST'});
    Net::PSYC::register_host('127.0.0.1', $self->{'IP'});
    Net::PSYC::register_host('127.0.0.1', 'localhost');
    $self->TRUST(11) if (Net::PSYC::same_host('127.0.0.1', $self->{'R_IP'}));
    Net::PSYC::register_route("$self->{'R_HOST'}\:$self->{'R_PORT'}", $self);
    Net::PSYC::register_route(inet_ntoa($socket->peeraddr()).":$self->{'R_PORT'}", $self);

    print STDERR "TCP: Connected with $self->{'R_IP'}\:$self->{'R_PORT'}\n" if Net::PSYC::DEBUG;
    watch($self) if Net::PSYC::AUTOWATCH;

    my $source = (Net::PSYC::UNL ne '/') ? { _source => Net::PSYC::UNL } : {};
    syswrite($self->{'SOCKET'}, ".\n");
    $self->send(Net::PSYC::makePSYC('_notice_circuit_established', 'Connected!'), {
	_target => "psyc://$self->{'R_IP'}:$self->{'R_PORT'}/",
	%$source,
	_understand_modules => $self->{'_options'}->{'_understand_modules'},
	_accept_modules => $self->accept_modules(),
	_understand_protcols => $self->{'_options'}->{'_understand_protocols'},
	_using_protocols => $self->{'_options'}->{'_understand_protocols'}, # TODO
	_implementation => $self->{'_options'}->{'_implementation'},
    });
    return $self;
}

sub connect {
    my $socket = IO::Socket::INET->new(Proto     => 'tcp',
                                       PeerAddr  => $_[1],
				       Blocking	=> 1,
                                       PeerPort  => $_[2] || Net::PSYC::PSYC_PORT );
    if (!$socket || !$socket->connected()) {
	print STDERR "TCP connect to $_[1]:".($_[2]||Net::PSYC::PSYC_PORT)." says: $!\n";
	return 0;
    }
    return Net::PSYC::Circuit->new($socket, $_[3]);
}

sub ssl_connect {
    require IO::Socket::SSL;
    my $socket = IO::Socket::SSL->new(Proto     => 'tcp',
				      PeerAddr  => $_[1],
				      Blocking	=> 1,
				      PeerPort  => $_[2] || Net::PSYC::PSYCS_PORT );

    if (!$socket || !$socket->connected()) {
	print STDERR "TCP connect to $_[1]:".($_[2]||Net::PSYC::PSYCS_PORT)." says: $!\n";
	return 0;
    }
    return Net::PSYC::Circuit->new($socket, $_[3]);
}


# TCP connection class
package Net::PSYC::Circuit::C;

use bytes;
use strict;
use Carp;


sub TRUST {
    my $self = shift;
    if ($_[0]) {
	$self->{'TRUST'} = $_[0];
    }
    return $self->{'TRUST'} || 3;
}

sub accept_modules {
    my $self = shift;
    my $changed = 0;
    foreach (@_) {
	next if(!$self->{'_options'}->{'_understand_modules'} =~ /$_/);
	next if($self->{'_options'}->{'_accept_modules'} =~ /$_/);
	$self->{'_options'}->{'_accept_modules'} =~ s/\ /\ $_\ /;
	$changed = 1;
    }
    if ($changed) {
	$self->send('',{_accept_modules=>$self->{'_accept_modules'}});
    }
    return $self->{'_options'}->{'_accept_modules'};
}

sub refuse_modules {
    my $self = shift;
    foreach (@_) {
	$self->{'_options'}->{'_accept_modules'} =~ s/\ ?$_\ ?/ /g;
    }
}

sub send {
    my ($self, $data, $vars) = @_;

    if (ref $data eq 'ARRAY') {
	$vars->{'_counter'} = $self->{'FRAGMENT_COUNTER'}++; 
    } else {
	$data = [ $data ];
    }

    push(@{$self->{'O_BUFFER'}}, [ $data, $vars, 0 ]);

    if (!Net::PSYC::AUTOWATCH) { # got no eventing.. send the packet instantly
        $self->write();
    } else {
	Net::PSYC::Event::revoke($self->{'SOCKET'}, 'w');
    }
    
    return 1;
}

sub write () {
    my $self = shift;
    return 1 if (!${$self->{'O_BUFFER'}}[$self->{'O_COUNT'}]); # no packets!
    
    my ($data, $vars, $count) = @{$self->{'O_BUFFER'}->[$self->{'O_COUNT'}]};
    use Storable qw(dclone);
    my $TMPvars = dclone($vars); # we desperately need a copy here..
                                 # since we will mess around with it
    my $state = $self->{'STATE_MEM'};

    ####
    # DEATH to TMPvars [ we delete ]
    # implementation of automatic state.. "3 * :" -> "="
    # if the packet is not send.. this sux TODO
#   foreach (keys %$vars) {
#   _length, _context .. should not be set! TODO
    foreach (keys %$state) {
	
	# _reset 
	if ($state->{$_}->[1] > 3 && !exists $vars->{$_}) {
	    $TMPvars->{$_} = '';
	    next;
	}
	
	if (exists $vars->{$_} && $state->{$_}->[0] eq $vars->{$_}) {
	    if ($state->{$_}->[1] == 3
	    && !$TMPvars->{'='}->{$_}) { # do not overwrite
		
		$TMPvars->{'='}->{$_} = delete $TMPvars->{$_};
	    } elsif ($state->{$_}->[1] > 3) {
		delete $TMPvars->{$_};
	    }
	    $state->{$_}->[1]++ if ($state->{$_}->[1] < 10);
	    # ^^
	    # this is wrong if we fail to send
	} 
    }
    ####
    
    $TMPvars->{'_fragment'} = $count if ($vars->{'_amount_fragments'});
    
    my $m = Net::PSYC::makeMMP($TMPvars, $data->[$count]);
    if (!defined(syswrite($self->{'SOCKET'}, $m))) {
	# put the packet back into the queue
	croak($!);
	return 1;
    }
    #sleep(1);

    ###
    # STATE 
    # sent was successful .. remember the vars
    foreach (keys %{$$TMPvars{'='}}) {
	if ($TMPvars->{'='}->{$_} eq '') {
	    delete $state->{$_};
	} else {
	    $state->{$_} = [ $TMPvars->{'='}->{$_}, 4 ];
	}
    }
    foreach (keys %$TMPvars) {
	if ($TMPvars->{$_} eq '') {
	    # TODO
	}
    }
    foreach (keys %$vars) {
	next if ($_ eq ':' || $_ eq '+' || $_ eq '-' || $_ eq '?');
	next if (exists $state->{$_} && $state->{$_}->[0] eq $vars->{$_});
	if (exists $state->{$_} && $state->{$_}->[1] > 4) {
	    $state->{$_}->[1]--;
	    next;
    	}
	$state->{$_} = [ $vars->{$_}, 1 ];
    }
    #
    ###
    
#    open(file, ">>$self->{'HOST'}:$self->{'PORT'}.out");
#    print file $m;
#    close file;
#    print "TCP: Wrote $w/".length($m)." bytes to the socket!\n";
    if (Net::PSYC::DEBUG > 1) {
	print STDERR "TCP: >>>>>>>> OUTGOING >>>>>>>>\n";
	print STDERR $m;
	print STDERR "\nTCP: <<<<<<< OUTGOING <<<<<<<\n";
    } 
    if (Net::PSYC::DEBUG) {
	my ($mc) = $m =~ m/^(_.+?)$/m;
	print STDERR "TCP[$self->{'R_IP'}:$self->{'R_PORT'}] <= ".
	($vars->{'_source'} || $state->{'_source'}->[0]).": ".($mc || 'MMP')."\n";
    }
	
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
	if (!Net::PSYC::AUTOWATCH) { # got no eventing.. send the packet 
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
    
    $read = sysread($self->{'SOCKET'}, $data, 8192);
    
    return if (!$read); # connection lost !?
    # gibt es nen 'richtigen' weg herauszufinden, ob die connection noch lebt?
    # connected() und die ganzen anderen socket-funcs helfen einem da in
    # den ekligen fällen nicht..
    $$self{'I_BUFFER'} .= $data;
    warn $! unless (defined($read));
    $self->{'I_LENGTH'} += $read;
#    open(file, ">>$self->{'HOST'}:$self->{'PORT'}.in");
#    print file $data;
#    print file "\n========\n";
#    close file;
    if (Net::PSYC::DEBUG > 1) {
	print STDERR "TCP: Read $read bytes from socket.\n";
	print STDERR "TCP: >>>>>>>> INCOMING >>>>>>>>\n";
	print STDERR $data;
	print STDERR "\nTCP: <<<<<<< INCOMING <<<<<<<\n";
    } 
    
    unless ($self->{'LF'}) {
	# we need to check for a leading ".\n"
	# this is not the very best solution though.. 
	if ($self->{'I_LENGTH'} >= 2) {
	    if ( $self->{'I_BUFFER'} =~ s/^\.(\r?\n)//g ) {
		$self->{'LF'} = $1;
		# remember if the other side uses \n or \r\n
		# to terminate lines.. we need that for proper
		# and safe parsing
	    } else {
		syswrite($self->{'SOCKET'}, "protocol error\n");
		print STDERR "Closed Connection to $self->{'R_HOST'}\n";
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
    my ($vars, $data) = Net::PSYC::MMPparse(\$$self{'I_BUFFER'}, $self->{'LF'});
    
    return if (!defined($vars));
    if ($vars < 0) {
	$self->{'I_LENGTH'} = $vars;
	return;
    }
    
    
    # handle all modifiers.. =, +, - for MMP vars
    # =
    foreach (keys %{$$vars{'='}}) {
	if($$vars{'='}->{$_} eq '') { # reset
	    delete $_v->{$_};
	} else {                         # assign
	    $_v->{$_} = $$vars{'='}->{$_};
	}
    }
    # +
    foreach (keys %{$$vars{'+'}}) {
	if (exists $_v->{$_}
	    && ref $_v->{$_} eq 'ARRAY') {
	    
	    push(@{$_v->{$_}}, $$vars{'+'}->{$_}); # add to list
	}
    }
    
    
    # -
    foreach my $key (keys %{$$vars{'-'}}) {
	if (exists $_v->{$key}
	    && ref $_v->{$key} eq 'ARRAY') {
		
	    @{$_v->{$key}} = grep { $_ ne $$vars{'-'}->{$key}}
					      @{$_v->{$key}};
	}
    }
    
    $vars = { %$_v, %{ $$vars{':'}||{} }};
    
    unless (exists $vars->{'_source'}) {
	$vars->{'_source'} = "psyc://$self->{'R_IP'}:$self->{'R_PORT'}/";
    } else {
	my @u = Net::PSYC::parseUNL($vars->{'_source'});
	unless (Net::PSYC::same_host($u[1], $self->{'R_IP'})) {
	    if ($self->TRUST < 5) {
		# just dont relay
		print STDERR "TCP: Refused packet from $self->{'R_IP'}. (_source: $vars->{'_source'})\n" if Net::PSYC::DEBUG;
		return 0;
	    }
	} else {
	    Net::PSYC::register_route($vars->{'_source'}, $self);
	}
    }
    
    if (exists $vars->{'_source_relay'} && $self->{'_options'}->{'_accept_modules'} =~ /_onion/ && $self->{'r_options'}->{'_accept_modules'} =~ /_onion/) {
	Net::PSYC::register_route($vars->{'_source_relay'}, $self);
	print STDERR "_Onion: Use $self->{'R_IP'} to route $vars->{'_source_relay'}\n" if Net::PSYC::DEBUG > 1;
	# remember pseudo-address to route packets back!
    }
    
    ####
    # FRAGMENT
    # handle fragmented data
    if (exists $vars->{'_fragment'}) {
	# {source} {logical target} {counter} [ {fragment} ]
	my $packet_id = '{'.($vars->{'_source'} || '').
			'}{'.($vars->{'_target'} || '').
			'}{'.($vars->{'_counter'} || '').'}';
#	print STDERR "Fragment: $vars->{'_fragment'}\n";
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
	    
	$c->[$vars->{'_fragment'}] = $data;
	if ($v->{'_amount'} == $v->{'_amount_fragments'}) {
	    print STDERR "TCP: Fragmented packet complete!\n";
	    $data = join('', @$c);
	} else {
	    return 0;
	}
    }
    ####
    
    return 0 if ($data eq '');
    
    my ($mc) = $data =~ m/^(_.+?)$/m;
    if ($mc && $mc eq '_notice_circuit_established') { # hackily
	foreach ('_using_modules', '_accept_modules') {
	    if (exists $vars->{$_}) {
		$self->{'r_options'}->{$_} = delete $vars->{$_};
	    }
	}
	if (exists $vars->{'_target'}) { # NAT?? get our ip.. 
	    # that is highly critical.. since we could fake
	    # TRUST.. so.. remember to change that, el! TODO
	    my ($ip) = $vars->{'_target'} =~ m/^psyc:\/\/(\S+?)[:\/]/;
	    Net::PSYC::register_host($self->{'IP'}, $ip);
	    
	    #Net::PSYC::setBASE($vars->{'_target'}) if (Net::PSYC::);
	}
    }

    print STDERR "TCP[$vars->{'_source'}] => ".$vars->{'_target'}.": ".
		 ($mc || 'MMP')."\n" if Net::PSYC::DEBUG;
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
    Net::PSYC::Circuit->new($socket, $self->{'_options'});
    return 1;
}

sub recv () { }

sub send {
    print "\nTCP: I am listening, not sending! Dont use me that way!\n";
}

sub TRUST {
    print "\nTCP: Dont TRUST() me, I'm ony listening.\n";
}

1;
