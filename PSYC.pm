package Net::PSYC;
#
#		___   __  _   _   __ 
#		|  \ (__   \ /   /   
#		|__/    \   V   |    
#		|    (__/   |    \__ 
#
#	Protocol for SYnchronous Conferencing.
#	 Official API Implementation in PERL.
#	  See  http://psyc.pages.de  for further information.
#
# Copyright (c) 1998-2004 Carlo v. Loesch and Arne Gödeke.
# All rights reserved.
#
# This program is free software; you may redistribute it and/or modify it
# under the same terms as Perl itself. Derivatives may not carry the
# title "Official PSYC API Implementation" or equivalents.
#
# Concerning UDP: No retransmissions or other safety strategies are
# implemented - and none are specified in the PSYC spec. If you use
# counters according to the spec you can implement your own safety
# mechanism best suited for your application.
#
# Status: the Net::PSYC is pretty much stable. Just details and features
# are being refined just as the protocol itself is, so from a software
# developer's point of view this library is quite close to a 1.0 release.
# After six years of development and usage that's presumably appropriate, too.

$VERSION = '0.12';

use strict;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

our (%C);
my ($UDP, $AUTOWATCH, %R, %hosts);
my ($DEBUG, $NO_UDP) = (0, 0);

my %_options = (
    '_accept_modules' => '_length _fragments _state', #this is default
    '_understand_modules' => '_length _fragments _state _onion',
    '_understand_protocols' => 'PSYC/0.99',
    '_implementation' => "Net::PSYC/$VERSION",
);

@EXPORT = qw(bindPSYC psyctext makeUNL UNL sendMSG
	     addReadable removeReadable waitPSYC
	     parseUNL getMSG); # getMSG is obsolete!
	     # why?? it works ,)

@EXPORT_OK = qw(makeMSG parseUNL $UDP %C PSYC_PORT PSYCS_PORT
		BASE SRC DEBUG setBASE setSRC setDEBUG
		registerPSYC makeMMP makePSYC parseMMP parsePSYC
		sendMMP accept_modules refuse_modules getConnection
		register_route register_host same_host
		startLoop stopLoop);

 
sub PSYC_PORT () { 4404 }	# default port for PSYC
sub PSYCS_PORT () { 9404 }	# non-negotiating TLS port for PSYC
 
my $BASE = '/'; # the UNL pointing to this communication endpoint 
                # with trailing / 
my $SRC = '';   # default sending object, without leading $BASE 
 
# inspectors, in form of inline macros 
sub BASE () { $BASE } 
sub SRC () { $SRC } 
sub UNL () { $BASE.$SRC } 
# settors 
sub setBASE { 
    $BASE = shift;
    unless ($BASE =~ /\/$/) {
	$BASE .= '/';
    }
    # its useful to register the host here since it may be dyndns
    register_host('127.0.0.1', parseUNL($BASE)->{'host'});
} 
sub setSRC { $SRC = shift; } 

sub DEBUG () { $DEBUG }
sub setDEBUG { 
    $DEBUG = shift;
    print STDERR "Debug Level $DEBUG set for Net::PSYC $VERSION.\n\n";
}


sub setAUTOWATCH { $AUTOWATCH = shift;}
sub AUTOWATCH { $AUTOWATCH }

use Carp;
use Socket qw(sockaddr_in inet_ntoa inet_aton);

use Net::PSYC::Datagram;
use Net::PSYC::Circuit;
use Net::PSYC::Event ();


print STDERR "Net::PSYC $VERSION loaded in debug mode.\n\n" if DEBUG;


#############
# Exporter..
sub import {
    my $pkg = caller();
    my $list = ' '.join(' ', @_).' ';
#    print STDERR "import($pkg, $list)";
    if ($list =~ / :all /) {
	export($pkg, @EXPORT);
	export($pkg, @EXPORT_OK);
    } elsif ($list =~ / :base /) {
	
    } elsif ($list =~ / :none /) {
	
    } else {
	export($pkg, @EXPORT);
	export($pkg, grep { join(' ', @EXPORT_OK) =~ /^$_ | $_ | $_$/ } @_);
    }
    if ($list =~ /Event=(\S+)/ && Net::PSYC::Event::init($1)) {
	import Net::PSYC::Event qw(watch forget registerPSYC unregisterPSYC 
	                           add remove can_read startLoop stopLoop);
    }
}

#   export(caller, list);
sub export {
    my $pkg = shift;
    no strict "refs";
    foreach (@_) {
#	print STDERR "exporting $_ to $pkg\n";
	# 'stolen' from Exporter/Heavy.pm
	if ($_ =~ /^([$%@*&])/) {
	    *{"${pkg}::$_"} =
		$1 eq '&' ? \&{$_} :
		$1 eq '$' ? \${$_} :
		$1 eq '@' ? \@{$_} :
		$1 eq '%' ? \%{$_} : *{$_};
	    next;
	} else {
	    *{"${pkg}::$_"} = \&{$_};
	    
	}
    }
}
#
##############

sub bindPSYC {
    my ($source) = shift || 'psyc://:/'; # get yourself any tcp and udp port
#   $source or croak 'usage: bindPSYC( $UNI )';
    
    my ($user, $host, $port, $prots, $object) = &parseUNL($source);
    my ($ip, @return);
    
    if (!$prots || $prots =~ /d/oi) { # bind a datagram
	my $sock = Net::PSYC::Datagram->new($host, $port);
	if ($sock) {
	    $UDP = $sock;
	    watch($UDP) if ($AUTOWATCH);
	    push (@return, $UDP);
	}
    }
    if (!$prots || $prots =~ /c/oi) { # bind a circuit
	my $sock = Net::PSYC::Circuit->listen($host, $port, \%_options);
	if ($sock) {
	    $C{$host.':'.$port} = $sock;
	    # tcp-sockets watch themselfes
	    push (@return, $C{$host.':'.$port});
	}
    }
    if ($prots =~ /s/oi) { # bind an SSL
	die "We don't allow binding of SSL sockets because SSL should".
	    " be negotiated anyway";
    }
    # how does one check for fqdn properly?
    # TODO $ip is undef !
    my $unlhost = $host =~ /\./ ? $host : $ip || '127.0.0.1';
    warn 'Could not find my own hostname or IP address!?' unless $unlhost;
    return unless (@return);
    
    $SRC = $object;
    $BASE = &makeUNL($user, $unlhost, $port, $prots);
    print STDERR "My UNL is $BASE$SRC\n" if DEBUG;
    return \@return if (defined wantarray);
}

# shutdown a connection-object.. 
sub shutdown {
    my $obj = shift;
    forget($obj); # stop delivering packets ..
    $obj->{'SOCKET'}->close() if ($obj->{'SOCKET'});
    foreach (keys %C) {
	delete $C{$_} if ($C{$_} eq $obj);
    }
    foreach (keys %R) {
	delete $R{$_} if ($R{$_} eq $obj);
    }
}

#   register_route ( ip|ip:port|target, connection )
sub register_route {
    print STDERR "register_route($_[0], $_[1])\n" if DEBUG > 2;
    $R{$_[0]} = $_[1];
}

#   register_host (ip, hosts)
#   TODO : this is still not very efficient.. 2-way hashes would be very nice
sub register_host {
    my $ip = shift;
    if (exists $hosts{$ip}) {
	$ip = $hosts{$ip};
    } else {
	$hosts{$ip} = $ip;
    }
    print STDERR "register_host($ip, ".join(", ", @_).")\n" if (DEBUG() > 1);
    foreach (@_) {
	$hosts{$_} = $ip;
	foreach my $host (keys %hosts) {
	    if ($hosts{$host} eq $_) {
		$hosts{$host} = $ip;
	    }
	}
    }
}

sub dns_lookup {
    my $name = shift;
    print STDERR "dns_lookup($name) == ".join('.', (unpack('C4',gethostbyname($name))))."\n" if DEBUG();
    my $addr = gethostbyname($name);
    if ($addr) {
	my $ip = join('.', (unpack('C4', $addr)));
	register_host($ip, $name);
	return $ip;
    } else { return 0; }
}

sub same_host {
    my ($one, $two) = @_;
    print STDERR "same_host('$one', '$two');\n" if (DEBUG() > 1);
    if (($one && $two) && (exists $hosts{$one} || dns_lookup($one)) && (exists $hosts{$two} || dns_lookup($two))) {
	return $hosts{$_[0]} eq $hosts{$_[1]};	
    }
    return 0;
}

# switches on modules for all connections established afterwards..
# to switch on modules in existing connections use $obj->accept_modules(@list)
# default ist: _length _fragments _state for TCP
# 	       _length _fragments for UDP <- TODO
sub accept_modules {
    foreach (@_) {
	next if ($_options{'_accept_modules'} =~ /$_/);
	next if (!$_options{'_understand_modules'} =~ /$_/);
	$_options{'_accept_modules'} =~ s/ /\ $_\ /; 
    }
    return $_options{'_accept_modules'};
}

# switches off modules .. use $obj->refuse_modules(@list) for established 
# connections
sub refuse_modules {
    foreach (@_) {
	$_options{'_accept_modules'} =~ s/\ ?$_\ ?/ /g;
    }
}



#   getConnection ( target )
sub getConnection {
    my $target = shift;

    my ($user, $host, $port, $prots, $object) = &parseUNL($target);

    $port ||= PSYC_PORT;
    # hm.. irgendwo müssen wir aus undef 4404 machen.. 
    # goto sucks.. i will correct that later!   -elridion
    # goto rocks.. please keep it.. i love goto  ;-)   -lynX 
    #
    if ( $prots =~ /c/i ) { # TCP
	goto TCP; 
    } elsif ( $prots =~ /d/i ) { # UDP
	goto UDP;
    } elsif ( $prots =~ /s/i ) {
	goto TCP;
    } else { # AI
	goto TCP;
	if (!$NO_UDP) {
	    goto UDP;
	} else { # TCP
	    goto TCP;
	}
    }
    TCP:
    my @addresses = gethostbyname($host);
    if (@addresses > 4) {
	$host = inet_ntoa($addresses[4]);
    }
    if (exists $C{$host.':'.$port}) { # we have a connection
	return $C{$host.':'.$port};
    }
    if ($R{$target} || $R{$host.':'.$port} || $R{$host}) {
	return $R{$target} || $R{$host.':'.$port} || $R{$host};
    }
    if ( $prots =~ /s/i ) {
	$C{$host.':'.$port} = Net::PSYC::Circuit->ssl_connect($host, $port, \%_options) or return 0;
	$R{$host.':'.'4404'} = $C{$host.':'.$port};
	# We assume that the ssl-connection may be used to
	# route packets to the standard port
    } else {
	$C{$host.':'.$port} = Net::PSYC::Circuit->connect($host, $port, \%_options) or return 0;
    }
    return $C{$host.':'.$port};
    
    UDP:
    unless ($UDP) {
	$UDP = Net::PSYC::Datagram->new;
	watch($UDP) if ($AUTOWATCH);
    }
    return $UDP;

}

#   sendMSG ( target, mc, data, vars[, MMP-vars] )
sub sendMSG {
    my ($target, $mc, $data, $vars, $MMPvars) = @_;
    
    $MMPvars->{'_target'} ||= $target;
    foreach ('_source', '_target', '_context', '_source_relay') {
	next if (exists $MMPvars->{$_});
	my $var = delete $vars->{':'}->{$_};
	$var = delete $vars->{'='}->{$_};
	$var = delete $vars->{$_};
	$MMPvars->{$_} = $var if($var);
    }
    # maybe we can check for the caller of sendMSG and use his unl as
    # source.. TODO ( works with Event only ). stone perloo
    $target or croak 'usage: sendMSG( $UNL, $method, $data, %vars )';
    #
    # presence of a method or data is not mandatory:
    # a simple modification of a variable may be sent as well,
    # although that only starts making sense once _state is implemented.
    my $connection = getConnection( $target );

    return 0 if (!$connection); 
    return $connection->send( $target, makePSYC( $mc, $data, $vars ), $MMPvars ); 
}

#   sendMMP (target, data, vars)
sub sendMMP {
    my ( $target, $data, $vars ) = @_;
    
    # maybe we can check for the caller of sendMSG and use his unl as
    # source.. TODO ( works with Event only ). stone perloo
    $target or croak 'usage: sendMMP( $UNL, $MMPdata, %MMPvars )';
    #
    # presence of a method or data is not mandatory:
    # a simple modification of a variable may be sent as well,
    # although that only starts making sense once _state is implemented.
    
    $vars->{'_target'} ||= $target;
    
    my $connection = getConnection( $target );
    return 0 if (!$connection);
    return $connection->send( $target, $data, $vars );
}

sub psyctext {
    my $text = shift;
    $text =~ s/\[(_\w+)\]/my $ref = ($_[0]->{$1} || ''); (ref $ref eq 'ARRAY') ? join(' ', @$ref) : $ref;/goe;
    return $text;
}

sub MMPparse {
    use bytes;
    my $d = shift;
    my $linefeed = shift || "\n";
    # ^^ das ist irgendwie nötig, weil alle anderen wege ein CR?LF zu erwischen
    # mit kaputten daten enden können. (vars könnten mit \r enden.. )
    # man sollte es immer übergeben, wenn man angst um seine daten hat. 
    # die connection-objekte machen es selbstständig
    my ($vars, $data) = ( {}, '' );
    my $ref;
    if (ref $d eq 'SCALAR') {
	$ref = 1;
    } else {
	$d = \$d;
    }
#    pos($$d) = 0;
#    print STDERR "Starting to parse MMP:\n";

    while ($$d =~ m/\G([+-:=\?])(\w+)\s+(.*?)$linefeed/gc) {
        my ($mod, $key, $value) = ( $1, $2, $3 );
        $$vars{$mod}->{$key} = $value;
#	print STDERR "\$\$vars{$mod}->{$key} = $value;\n";
        $mod = '\\'.$mod; # '?' causes regexp to die
        while ($$d =~ m/\G($mod)\s+(.*?)$linefeed/gc) {
            $$vars{$1}->{$key} = [$$vars{$1}->{$key}]
                if (!ref $$vars{$1}->{$key}); # create an array
            push(@{$$vars{$1}->{$key}}, $2); # push new element
#	    print STDERR "push(\@{\$\$vars{$1}->{$key}}, $2);\n";
        }
    }
#    print STDERR "position before \\n: ".pos($$d)."\n";
#    pos($$d)++; # s/^\n/
    $$d =~ m/^$linefeed/gcm;
#    if ($$d =~ m/^\n/gcm) {
#	print STDERR "Finished parsing vars!\n";
#	if (!scalar(keys %$vars)) {
#	    print STDERR "NO VARS found\n";
#	    print STDERR "bumping data into psyc.raw... ";
#	    if (open(file, ">>psyc.raw")) {
#		print file $$d;
#		close(file);
#		print STDERR "done.\n";
#	    } else {
#		print STDERR "failed.\n";
#	    }
#	    sleep(4);
#	    return;
#	}
#    }
#    print STDERR "position after \\n: ".pos($$d)."\n";
    return unless(defined(pos($$d)));
    my $length = ($$vars{'='} && $$vars{'='}->{'_length'})
		 ? $$vars{'='}->{'_length'}
		 : ($$vars{':'} && $$vars{':'}->{'_length'}) 
                 ? $$vars{':'}->{'_length'} : 0;
#    print STDERR "position: ".pos($$d).", reallength: ".length($$d).", length: $length\n";
    if ($length && length($$d) < $length + pos($$d) + length($linefeed)*2 + 1) {
	# hmm.. vielleicht dann den punkt suchen? ,)
	# wir laufen hier immer wieder rein, das ist schlecht
	# wir müssen das kaputte paket irgendwie loswerden.
	#
	# el: es muss nicht zwingend ein kaputtes paket sein,
	# es kann einfach mal passieren, dass man im buffer nen 
	# \n.\n findet, ohne dass das paket schon komplett da ist!
	#
	# dann sollte allerdings _length mitkommen .. naja.. egal
	# TODO
	#
	# Für alle packets, bei denen ne richtige _length mitkommt, ist alles
	# ok.. für falsche _length oder kaputte packets im allgemeinen
	# sollte man vielleicht die connection dicht machen.. protcol error
	# "Ras H. Tafari! What's going on here?" or
	# "Sweet Manatee of Galilee!" or
	# "Great llamas of the Bahamas!" .. etc ,]
#	print STDERR "incomplete packet or wrong _length!\n" if DEBUG;
	return length($$d) - ($length + pos($$d) + length($linefeed)*2 + 1);
    } elsif (!$length) {
	$length = index($$d, "$linefeed.$linefeed", pos($$d)) - pos($$d);
#	print STDERR "incomplete packet!\n" if DEBUG && $length < 0;
	return if ($length < 0);
    }
#    print STDERR "complete packet!\n";
    $data = substr($$d, pos($$d), $length);
    pos($$d) += $length;
    
    if ($ref) {
	if (Net::PSYC::DEBUG > 1) {
	    print STDERR "\n".("=" x 60)."\n";
	    print STDERR substr($$d, 0, pos($$d) + 3, '');
	    print STDERR ("=" x  60);
	    print STDERR "\n";
	} else {
	    substr($$d, 0, pos($$d) + 3, '');
#	    open(file, ">>psyc.raw");
#	    print file substr($$d, 0, pos($$d) + 3, '');
#	    print file "\n\n====================================\n\n";
#	    close(file);
	}
    }
#    use Data::Dumper;
#    print STDERR "REturning packet:\n";
#    print STDERR Dumper($vars);
    return ($vars, $data);
}

sub PSYCparse {
    my $d = shift;
    my $linefeed = shift || "\n";
    my ($vars, $mc, $data) = ( {}, '', '');
    $d = $$d if (ref $d eq 'SCALAR');

    # vars
    # hier noch alle \n\t mitnehmen, für multiline-support
    while ($d =~ s/^([+-:=?])(_\w+)\s*(.*)$linefeed//g) {
        $vars->{$1}->{$2} = $3;
        my ($mod, $key) = ($1, $2);

        while ($d =~ s/^$mod\t(.*)$linefeed//g) { #list
	    # hier noch alle \n\t mitnehmen, für multiline-support
            $vars->{$mod}->{$key} = [$vars->{$mod}->{$key}]
                unless (ref $vars->{$mod}->{$key});
            push(@{$vars->{$mod}->{$key}}, $1);
        }
    }
    # mc
    if ($d =~ s/^(_\w+)$linefeed//g || $d =~ s/^(_\w+)$//g) {
        $mc = $1;
    }
    return ($mc, $d, $vars->{':'} || {}, $vars);
}

sub makeMMP {
    use bytes;
    my ($vars, $data) = @_;
    my $m;
    
    $vars->{':'}->{'_length'} = length($data)
	if (index($data, "\n.\n") != -1 || index($data, "\r\n.\r\n") != -1);
    
    $m = makeVARS($vars);

    $m .= "\n$data\n.\n";
    return $m;
}

sub makeVARS {
    my ($vars) = shift;
    my $m = '';
    foreach (keys %$vars) {
	if ($_ eq '=' || $_ eq ':' || $_ eq '-' || $_ eq '+' || $_ eq '?') {
	    foreach my $key (keys %{$vars->{$_}}) {
		$m .= "$_$key\t".VAR($vars->{$_}->{$key}, $_)."\n";
	    }
	    next;
	}
	$m .= ":$_\t".VAR($vars->{$_}, ':')."\n";
    }   
    return $m;
    sub VAR {
	my ($val, $mod) = @_;
	return '' unless(defined($val));
	if (ref $val eq 'ARRAY') {
	    #return join("\n$mod\t", map { s/\n/\n\t/g } @{$val}) 
	    return join("\n$mod\t", @$val) 
	} else {
	    $val =~ s/\n/\n\t/g;
	    return $val;
	}
    }
}

#   makePSYC ( mc, data, vars)
sub makePSYC {
    my ($mc, $data, $vars) = @_;
    return makeVARS($vars).$mc."\n".($data || '');
}


sub makeMSG { 
    my ($mc, $data) = @_;
    my $vars = $_[2] || {};
    my $MMPvars = {};
    
    foreach my $m ('=', '+', '-', '?', ':') {
	next unless(exists $vars->{$m});
	foreach (keys %{$vars->{$m}}) {
	    if ($_ eq '_target'
	    ||	$_ eq '_source'
	    || 	$_ eq '_context') {
		$MMPvars->{$m}->{$_} = delete($vars->{$m}->{$_});
	    }
	}
    }
    foreach (keys %{$vars}) {
            if ($_ eq '_target'
            ||  $_ eq '_source'
            ||  $_ eq '_context') {
                $MMPvars->{':'}->{$_} = delete($vars->{$_});
            }
    }
    return ($MMPvars, makePSYC($mc, $data, $vars)) if wantarray;
    # we want data and MMP-stuff seperated to do fragmentation
    return makeMMP($MMPvars, makePSYC($mc, $data, $vars));
}
=wu
sub parseUNL {
        ($_) = @_;
	unless (s/^\s*psyc:(\S+)\s*$/$1/i) {
	    print STDERR "'$_' is no PSYC UNL";
	    return;
	}
        unless (s!^//!!) {
	    print STDERR 'well-known UNIs not defined yet';
	    return;
        }
        my $u = $1 if s!^([^/:\@]+)\@!!;
        my ($h,$p,$t,$o) = m!^([^/:]*):?(\d*)([a-z]*)(?:/(.*))*$!i;
	unless ($h || $p || $t || $o) {
	    return;
	}
	return ($u||'', $h, $p, $t, $o);
}
=cut

sub parseUNL {
    my $arg = shift;
    my $user;
    my ($scheme, $host) = ($arg =~ m/^(\w+)\:\/\/([^\/:]*)/gcm);
    my ($port, $proto) = ($arg =~ m/\G\:(\d*)(\w*)/gcm);
    my ($object) = ($arg =~ m/\G\/(.*)$/gcm);
    if ($host =~ /([^@]+)\@([^@]+)/) {
	$user = $1; $host = $2;
    }
    return ($user||'', $host, $port, $proto, $object) if wantarray;
    return {
	unl => $arg,
	host => $host,
	port => $port,
	transport => $proto,
	user => $user||'',
    };    
}


sub makeUNL {
        my ($user, $host, $port, $type, $object) = @_;
        $port = '' if $port == PSYC_PORT || !$port;
        $object = '' unless $object;
        $type = '' unless $type;
        unless ($host) {
                croak 'well-known UNIs not standardized yet';
                # return "psyc:$object"
        }
        $host = "$user\@$host" if $user;
        return "psyc://$host/$object" unless $port || $type;
        return "psyc://$host:$port$type/$object";
}

################################################################
# Functions needed to be downward compatible to Net::PSYC 0.7
# Not entirely clear which of these we can really call obsolete
# 
sub waitPSYC {
    return Net::PSYC::Event::can_read(@_);
}
#
sub addReadable {
    Net::PSYC::Event::add(@_); 
}
sub removeReadable { Net::PSYC::Event::remove(@_); }
#
# alright, so this should definitely not be used as it will not
# be able to handle multiple and incomplete packets in one read operation.
sub getMSG {
    my $key;
    my @readable = Net::PSYC::Event::can_read(@_);
    my %sockets = %{&Net::PSYC::Event::PSYC_SOCKETS()};
    my ($mc, $data, $vars);
    SOCKET: foreach (@readable) {
	$key = scalar($_);
	if (exists $sockets{$key}) { # found a readable psyc-obj
	    $sockets{$key}->read();
	    while (1) {
		my ($MMPvars, $MMPdata) = $sockets{$key}->recv();
		next SOCKET if (!defined($MMPdata));
		
		($mc, $data, $vars) = PSYCparse($MMPdata, $sockets{$key}->{'LF'});	
		last if($mc); # ignore empty messages..
	    }
	    print "\n=== getMSG ", '=' x 67, "\n", $data, '=' x 79, "\n"
	      if DEBUG;
	    my ($port, $ip) = sockaddr_in($sockets{$key}->{'LAST_RECV'})
		if $sockets{$key}->{'LAST_RECV'};
	    $ip = inet_ntoa($ip) if $ip;
	    return ('', $ip, $port, $mc, $data, %$vars);
	    return ('', '', 0, $mc, $data, %$vars);
	}
    }
    return ('NO PSYC-SOCKET READABLE!', '', 0, '', '', ());
}
#
################################################################


1;

__END__

=head1 NAME

Net::PSYC - Implementation of the Protocol for SYnchronous Conferencing.

=head1 DESCRIPTION

PSYC is an innovative protocol for chat servers and conferencing
in general. It is intended to overcome problems of traditional
approaches like IRC and ICQ. But you may aswell use it as a simple
all-purpose messaging protocol.

This implementation is in beta state, the application programming
interface (API) may change in future versions until version 1.0
is released.

See http://psyc.pages.de for protocol specs and other info on PSYC.

=head1 SYNOPSIS
    
    # small example on how to send one single message:
    use Net::PSYC;
    sendMSG('psyc://myhost/~someuser', '_notice_whatever', 
	    'Whatever happened to the 80\'s...');

	    
    # receive messages...
		    # Event, Gtk2 is possible too
    use Net::PSYC qw(Event=IO::Select startLoop registerPSYC); 
    registerPSYC(); # get all messages
    bindPSYC(); # start listening on :4404 tcp and udp.
    
    startLoop(); # start the Event loop
    
    sub msg {
	my ($source, $mc, $data, $vars) = @_;
	print "A message ($mc) from $source reads: '$data'\n";
    }    
 
=head1 PERL API

=over 4

=item bindPSYC( B<$localpsycUNI> )

Starts listening on a local hostname and TCP and/or UDP port according to the PSYC UNI specification. When omitted, a random port will be chosen for both service types. 

=item sendMSG( B<$target>, B<$mc>, B<$data>, B<$vars> )

compatible to psycMUVEs sendmsg, accepts four of five PSYC packet elements, source being defined by setSRC if necessary.
 
=item sendMMP( B<$target>, B<$data>, B<$vars> )

sends a MMP packet to the given B<$target>. B<$data> may be a reference to an array of fragmented data. 

=item psyctext( B<$format>, B<$vars> )

compatible to psycMUVEs psyctext, renders the strings in B<$vars> into the B<$format> and returns the resulting text conformant to the text/psyc content type specification.

=item makeUNL( $user, $host, $port, $type, $object )

produces a PSYC UNI out of the given elements.
 
=item UNL()

returns the current complete source UNI.

=item accept_modules( @modules )

=item refuse_modules( @modules )

Set or get modules currently accepted by the MMP part of your PSYC application. Changes to this setting do not take effect in established connections. ( Have a look at getConnection and Net::PSYC::Circuit::accept_modules()! ) Modules that are understood by the current version are _state, _fragment, _length and _onion of which _state, _fragment and _length are accepted by default.

=back
 
=head1 Eventing

addReadable, removeReadable and waitPSYC implement a pragmatic IO::Select wrapper for applications that do not need any other event management like Event.pm. See Net::PSYC::Event for more.

You may also find it useful to export the following: makeMSG, parseUNL, parse, setBASE, setSRC, setDEBUG

For further details.. Use The Source, Luke!

=head1 SEE ALSO

L<Net::PSYC::Event>, L<Net::PSYC::Client>, L<http://psyc.pages.de> for more information about the PSYC protocol, L<http://muve.pages.de> for a rather mature psyc server implementation (also offering irc, jabber and a telnet-interface) 

=head1 AUTHORS

=over 4

=item Carlo v. Loesch

L<psyc://ve.symlynX.com/~lynX>

L<http://symlynX.com/>

=item Arne GE<ouml>deke

L<psyc://ve.symlynx.com/~elridion>

L<http://www.elridion.de/>

=back

=head1 COPYRIGHT

Copyright (c) 1998-2004 Carlo v. Loesch and Arne GE<ouml>deke. All rights reserved.

This program is free software; you may redistribute it and/or modify it
under the same terms as Perl itself. Derivatives may not carry the
title "Official PSYC API Implementation" or equivalents.
	
=cut

