package Net::PSYC::Datagram;

use vars qw($VERSION);
$VERSION = '0.1';

use strict;
use Carp;
use IO::Socket::INET;

sub TRUST {
    return 1;
}

sub new {
    my $class = shift;

    my $addr = shift || undef;		# NOT 127.1
    my $port = int(shift) || undef;	# also, NOT 4404

    my %a = (LocalPort => $port, Proto => 'udp');
    $a{LocalAddr} = $addr if $addr;
    my $socket = IO::Socket::INET->new(%a)
	or (croak("UDP bind to $addr:$port says: $@") && return 0);
    
    my $self = {
	'SOCKET' => $socket,
	'IP' => $socket->sockhost,
	'PORT' => $port || $socket->sockport,
	'TYPE' => 'd',
	'I_BUFFER' => [],
	'O_BUFFER' => [],
	'O_COUNT'  => 0,
    };
    return bless $self, $class; 
}

#   send ( target, mc, data, vars ) 
sub send {
    my $self = shift;
    my ( $target, $mc, $data, $vars, $v ) = @_;

    push(@{$self->{'O_BUFFER'}}, [ [$target, $mc, $data, $vars, $v] ]);

    if (!$Net::PSYC::AUTOWATCH) { # got no eventing.. send the packet instantly
        return $self->write();
    } else {
        Net::PSYC::Event::revoke($self->{'SOCKET'});
    }
    return 0;
}

sub write () {
    my $self = shift;

    return 1 if (!${$self->{'O_BUFFER'}}[$self->{'O_COUNT'}]);
    
    # get a packet from the buffer
    my $packet = shift(@{${$self->{'O_BUFFER'}}[$self->{'O_COUNT'}]});
    my $target = shift(@$packet);
    my ($user, $host, $port, $type, $object) = Net::PSYC::parseUNL($target);
    
    $port ||= Net::PSYC::PSYC_PORT();
    
    $packet->[2]->{'_target'} ||= $target;

# funny, but not what we want.. returns 0.0.0.0 for INADDR_ANY and even
# when the ip is useful, the port may not - the other side should better
# use its own peer info. or the perl app provides _source.
#
#   $vars->{'_source'} |= "psyc://$self->{'IP'}:$self->{'PORT'}/";

    my $m = ".\n"; # empty packet!
    $m .= Net::PSYC::makeMSG( @$packet );
    
    ($port && $host) or croak('usage: obj->send( $target[, $method[, $data[, $vars[, $mvars]]]] )');

    my $taddr = gethostbyname($host); # hm.. strange thing!
    my $tin = sockaddr_in($port, $taddr);
    
    if (!defined($self->{'SOCKET'}->send($m, 0, $tin))) {
	unshift(@$packet, $target);
        unshift(@{${$self->{'O_BUFFER'}}[$self->{'O_COUNT'}]}, $packet);
        croak($!);
        return $!;
    }
    print STDERR "UDP[$self->{'HOST'}:$self->{'PORT'}] <= $packet->[2]->{'_source'}\: $$packet[0]\n"
	if Net::PSYC::DEBUG;
    if (!scalar(@{${$self->{'O_BUFFER'}}[$self->{'O_COUNT'}]})) {
        # all fragments of this packet sent
        splice(@{$self->{'O_BUFFER'}}, $self->{'O_COUNT'}, 1);
        $self->{'O_COUNT'} = 0 if (!${$self->{'O_BUFFER'}}[$self->{'O_COUNT'}]);
    } else {
        # fragments of this packet left
        $self->{'O_COUNT'} = 0 if (!${$self->{'O_BUFFER'}}[++$self->{'O_COUNT'}]);
    }
    if(scalar(@{$self->{'O_BUFFER'}})) {
        Net::PSYC::Event::revoke($self->{'SOCKET'});
    }
    return 1;
}

sub read () {
    my $self = shift;
    my ($data, $last);
    
    $self->{'LAST_RECV'} = $self->{'SOCKET'}->recv($data, 8192); # READ socket
    
    return if (!$data); # connection lost !?
    # gibt es nen 'richtigen' weg herauszufinden, ob die connection noch lebt?
    # connected() und die ganzen anderen socket-funcs helfen einem da in
    # den ekligen fällen nicht..

    $self->{'I_BUFFER'} .= $data;
}

#   returns _one_ mmp-packet .. or undef if the buffer is empty
sub recv () {    
    my $self = shift;
    if ($self->{'I_BUFFER'}) {
	return Net::PSYC::MMPparse(\$$self{'I_BUFFER'});
    }
    return;
}



1;
