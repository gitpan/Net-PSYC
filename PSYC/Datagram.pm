package Net::PSYC::Datagram;

use vars qw($VERSION);
$VERSION = '0.4';

use strict;
use Carp;
use IO::Socket::INET;

sub TRUST {
    return 1;
}

sub new {
    my $class = shift;

    my $addr = shift || undef;		# NOT 127.1
    my $port = int(shift||0) || undef;	# also, NOT 4404

    my %a = (LocalPort => $port, Proto => 'udp');
    $a{LocalAddr} = $addr if $addr;
    my $socket = IO::Socket::INET->new(%a)
	or (croak("UDP bind to $addr:$port says: $@") && return 0);
    my $self = {
	'SOCKET' => $socket,
	'IP' => $socket->sockhost,
	'PORT' => $port || $socket->sockport,
	'TYPE' => 'd',
	'I_BUFFER' => '',
	'O_BUFFER' => [],
	'O_COUNT'  => 0,
	'LF' => '',
    };
    print STDERR "UDP bind to $self->{'IP'}:$self->{'PORT'} successful\n" if Net::PSYC::DEBUG;
    return bless $self, $class; 
}

#   send ( target, mc, data, vars ) 
sub send {
    my $self = shift;
    my ( $target, $data, $vars ) = @_;

    push(@{$self->{'O_BUFFER'}}, [ [$target, $data, $vars ] ]);

    if (!$Net::PSYC::AUTOWATCH) { # got no eventing.. send the packet instantly
        return $self->write();
    } else {
        Net::PSYC::Event::revoke($self->{'SOCKET'});
    }
    return 1;
}

sub write () {
    my $self = shift;

    return 1 if (!${$self->{'O_BUFFER'}}[$self->{'O_COUNT'}]);
    
    # get a packet from the buffer
    my $packet = shift(@{${$self->{'O_BUFFER'}}[$self->{'O_COUNT'}]});
    my $target = shift(@$packet);
    my ($user, $host, $port, $type, $object) = Net::PSYC::parseUNL($target);
    
    $port ||= Net::PSYC::PSYC_PORT();
    
    $packet->[1]->{'_target'} ||= $target;

# funny, but not what we want.. returns 0.0.0.0 for INADDR_ANY and even
# when the ip is useful, the port may not - the other side should better
# use its own peer info. or the perl app provides _source.
#
#   $vars->{'_source'} |= "psyc://$self->{'IP'}:$self->{'PORT'}/";

    my $m = ".\n"; # empty packet!
    $m .= Net::PSYC::makeMMP(reverse @$packet);
    
    ($port && $host) or croak('usage: obj->send( $target[, $method[, $data[, $vars[, $mvars]]]] )');

    my $taddr = gethostbyname($host); # hm.. strange thing!
    my $tin = sockaddr_in($port, $taddr);
    
    if (!defined($self->{'SOCKET'}->send($m, 0, $tin))) {
	unshift(@$packet, $target);
        unshift(@{${$self->{'O_BUFFER'}}[$self->{'O_COUNT'}]}, $packet);
        croak($!);
        return $!;
    }
    print STDERR "UDP[$self->{'IP'}:$self->{'PORT'}] <= ".($packet->[1]->{'_source'}||Net::PSYC::UNL())."\n"
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
    # gibt es nen 'richtigen' weg herauszufinden, ob der socket noch lebt?

    $self->{'I_BUFFER'} .= $data;
    delete $self->{'LF'};
    return 1;
}

#   returns _one_ mmp-packet .. or undef if the buffer is empty
sub recv () {    
    my $self = shift;
    print STDERR length($self->{'I_BUFFER'})."\n";
    if (length($self->{'I_BUFFER'}) > 2) {
	if ( $self->{'LF'} || $self->{'I_BUFFER'} =~ s/^\.(\r?\n)//g ) {
	    
	    $self->{'LF'} ||= $1;
	    my ($vars, $data) = Net::PSYC::MMPparse(\$$self{'I_BUFFER'}, $self->{'LF'});
	    return if (!defined $vars);
	    $vars = $vars->{':'};
	    return ($vars, $data);
	}
	# TODO : we need to provide a proper algorithm to clean up the
	# in-buffer if we got corrupted packets in it. and we need to
	# detect corrupted packets.. udp sucks noodles! ,-)
    }
    return;
}



1;
