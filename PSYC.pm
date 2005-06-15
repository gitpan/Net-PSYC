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
# Copyright (c) 1998-2005 Carlo v. Loesch and Arne GE<ouml>deke.
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

# last snapshot (0.12) made when i changed 0.12 into 0.13 -lynX
$VERSION = '0.14';

use strict;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

our (%C, %L);
our $ANACHRONISM = 0;
my ($UDP, $AUTOWATCH, %R, %hosts);
my ($DEBUG, $NO_UDP) = (0, 0);

my %_options = (
    # please don't expect the other side to support these features by default..
    # you can wait for the other side's _understand_modules to make a schnitt-
    # menge and send it out as _using_modules.. (done already?)
    '_using_modules' => '_length;_fragments;_state', #this is default
    '_understand_modules' => '_length;_fragments;_state',
    '_understand_protocols' => 'PSYC/0.9 TCP IP/4, PSYC/0.9 UDP IP/4',
    '_implementation' => sprintf "Net::PSYC/%s perl/v%vd %s", $VERSION, $^V, $^O
);

@EXPORT = qw(bind_uniform psyctext make_uniform UNL sendmsg
	     dirty_add dirty_remove dirty_wait
	     parse_uniform dirty_getmsg); # dirty_getmsg is obsolete!

@EXPORT_OK = qw(makeMSG parse_uniform $UDP %C PSYC_PORT PSYCS_PORT
		UNL W AUTOWATCH sendmsg make_uniform psyctext
		BASE SRC DEBUG setBASE setSRC setDEBUG
		register_uniform make_mmp make_psyc parse_mmp parse_psyc
		send_mmp get_connection
		register_route register_host same_host dns_resolve
		start_loop stop_loop psyctext);

 
sub PSYC_PORT () { 4404 }	# default port for PSYC
#sub PSYCS_PORT () { 9404 }	# non-negotiating TLS port for PSYC
 
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
    register_host('127.0.0.1', parse_uniform($BASE)->{'host'});
} 
sub setSRC { $SRC = shift; } 

sub DEBUG { $DEBUG }
sub setDEBUG { 
    $DEBUG = shift;
    W("Debug Level $DEBUG set for Net::PSYC $VERSION.",0);
}

# the "other" sub W should be used, but this one is .. TODO
sub W {
    my $line = shift;
    my $level = shift;
    $level = 1 unless(defined($level));
    print STDERR "\r$line\r\n" if DEBUG() >= $level;
}

sub AUTOWATCH { 
    if (defined($_[0])) {
	$AUTOWATCH = $_[0];
    }
    return $AUTOWATCH;
}

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
    $list =~ s/Net::PSYC//g; # 
    if ($list =~ s/Event=(\S+)// && Net::PSYC::Event::init($1)
    || ($list =~ / :event / && Net::PSYC::Event::init('IO::Select'))) {
	import Net::PSYC::Event qw(watch forget register_uniform 
				   unregister_uniform add remove 
				   can_read start_loop stop_loop revoke);
	export($pkg, qw(watch forget register_uniform unregister_uniform 
			revoke add remove can_read start_loop stop_loop));
	AUTOWATCH(1);
    } elsif ($list =~ / :anachronism /) {
	unless (Net::PSYC::Event::init('IO::Select')) {
	    W("Your IO::Select does not work very well!",0);
	    return 0;
	}
	#its not possible to do negotiation with getMSG.. or you do it yourself
	import Net::PSYC::Event qw(watch forget register_uniform 
				   unregister_uniform revoke add 
				   remove can_read start_loop stop_loop);
	export($pkg, qw(watch forget register_uniform unregister_uniform revoke
			add remove can_read start_loop stop_loop));
	export($pkg, @EXPORT);
	AUTOWATCH(1);
	$ANACHRONISM = 1;
    }

    if ($list =~ s/ :tls | :ssl | :encrypt // && !$ANACHRONISM) {
	if (eval { require IO::Socket::SSL }) {
	    $_options{'_understand_modules'} .= ';_encrypt';
	} else {
	    W("You need IO::Socket::SSL to use _encrypt. require() said: $@", 0);   
	}
    }
    if ($list =~ s/ :zlib | :compress // && !$ANACHRONISM) {
	if (eval { require Net::PSYC::MMP::Compress }) {
	    $_options{'_understand_modules'} .= ';_compress';
	} else {
	    W("You need Compress::Zlib to use _compress. require() said: $@", 0);   
	}
    }

    return export($pkg, @EXPORT) unless ($list =~ /\w/);
    
    if ($list =~ / :all /) {
	export($pkg, @EXPORT);
	export($pkg, @EXPORT_OK);
    } elsif ($list =~ / :base /) {
	export($pkg, @EXPORT);
    }
    
    my @subs = grep { $list =~ /$_/ } @EXPORT_OK;
    if (scalar(@subs)) {
        export($pkg, @subs);
    }
    
}

#   export(caller, list);
sub export {
    my $pkg = shift;
    no strict "refs";
    foreach (@_) {
	W("exporting $_ to $pkg",2);
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
##############
# DNS
#   register_route ( ip|ip:port|target, connection )
sub register_route {
    W("register_route($_[0], $_[1])");
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
    W("register_host($ip, ".join(", ", @_).")");
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
    W("dns_lookup($name) == ".join('.', (unpack('C4',gethostbyname($name)))));
    my $addr = gethostbyname($name);
    if ($addr) {
	my $ip = join('.', (unpack('C4', $addr)));
	register_host($ip, $name);
	return $ip;
    } else { return 0; }
}

sub same_host {
    my ($one, $two) = @_;
    W("same_host('$one', '$two');");
    if (($one && $two) && (exists $hosts{$one} || dns_lookup($one)) && (exists $hosts{$two} || dns_lookup($two))) {
	return $hosts{$_[0]} eq $hosts{$_[1]};	
    }
    return 0;
}
#
##############

sub bind_uniform {
    my ($source) = shift || 'psyc://:/'; # get yourself any tcp and udp port
#   $source or croak 'usage: bind_uniform( $UNI )';
    
    my ($user, $host, $port, $prots, $object) = &parse_uniform($source);
    my ($ip, $return);
    
    if (!$prots || $prots =~ /d/oi) { # bind a datagram
	my $sock = Net::PSYC::Datagram->new($host, $port);
	if ($sock) {
	    $UDP = $sock;
	    watch($UDP) if ($AUTOWATCH);
	    $return = $UDP;
	    $port = $return->{'PORT'};
	}
    }
    if (!$prots || $prots =~ /c/oi) { # bind a circuit
	my $sock = Net::PSYC::Circuit->listen($host, $port, \%_options);
	if ($sock) {
	    $L{$host.':'.$port} = $sock;
	    # tcp-sockets watch themselfes
	    $return = $L{$host.':'.$port};
	    $port = $return->{'PORT'};
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
    return unless ($return);
    
    $SRC = $object;
    $BASE = &make_uniform($user, $unlhost, $port, $prots);
    print STDERR "My UNL is $BASE$SRC\n" if DEBUG;
    return $return if (defined wantarray);
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

##############
# MODULES
=ui
sub want_modules {
    &accept_modules
}

sub require_modules {
    return ();
}

# switches on modules for all connections established afterwards..
# to switch on modules in existing connections use $obj->accept_modules(@list)
sub accept_modules {
    foreach my $module (@_) {
	unless (grep {$module eq $_} qw(_state _compress _encrypt _fragments _length)) {
	    W("$module is not supported by this implementation!",0);
	    next;
	}
	next if (grep {$module eq $_} @{$_options{'_understand_modules'}});
	push(@{$_options{'_understand_modules'}}, $module);
    }
    return @{$_options{'_understand_modules'}};
}

# switches off modules .. use $obj->refuse_modules(@list) for established 
# connections
sub refuse_modules {
    foreach my $module (@_) {
	@{$_options{'_understand_modules'}} = grep {
	    $_ ne $module
	} @{$_options{'_understand_modules'}};
    }
}
=cut
#
##############

#   get_connection ( target )
sub get_connection {
    my $target = shift;

    register_uniform(0) if AUTOWATCH();
    my ($user, $host, $port, $prots, $object) = &parse_uniform($target);
    # hm.. irgendwo müssen wir aus undef 4404 machen.. 
    # goto sucks.. i will correct that later!   -elridion
    # goto rocks.. please keep it.. i love goto  ;-)   -lynX 
    #
    if ( !$prots || $prots =~ /c/i ) { # TCP
	$port ||= PSYC_PORT;
	goto TCP; 
    } elsif ( $prots =~ /d/i ) { # UDP
	$port ||= PSYC_PORT;
	goto UDP;
    } elsif ( $prots =~ /s/i ) {
	$port ||= PSYCS_PORT();
	goto TCP;
    } else { # AI
	goto TCP;
#	if (!$NO_UDP) {
#	    goto UDP;
#	} else { # TCP
#	    goto TCP;
#	}
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
    $C{$host.':'.$port} = Net::PSYC::Circuit->connect($host, $port, \%_options) or return $!;
    return $C{$host.':'.$port};
    
    UDP:
    unless ($UDP) {
	$UDP = Net::PSYC::Datagram->new;
	watch($UDP) if ($AUTOWATCH);
    }
    return $UDP;

}

#   sendmsg ( target, mc, data, vars[, source || MMP-vars] )
sub sendmsg {
    my ($target, $mc, $data, $vars, $MMPvars) = @_;

    $MMPvars = { '_source' => $MMPvars } if ($MMPvars && !ref $MMPvars);
    
    $MMPvars->{'_target'} ||= $target;

    foreach (keys %$vars) {
	if (/^[\+-=\?]?_source/ ||
	    /^[\+-=\?]?_target/ ||
	    /^[\+-=\?]?_context/) {
	    $MMPvars->{$_} = delete $vars->{$_} unless (exists $MMPvars->{$_});
	}
    }
    
    # maybe we can check for the caller of sendmsg and use his unl as
    # source.. TODO ( works with Event only ). stone perloo
    $target or croak 'usage: sendmsg( $UNL, $method, $data, %vars )';
    #
    # presence of a method or data is not mandatory:
    # a simple modification of a variable may be sent as well,
    # although that only starts making sense once _state is implemented.
    my $connection = get_connection( $target );

    return 'SendMSG failed: '.$connection if (!ref $connection); 
    return $connection->send( $target, make_psyc( $mc, $data, $vars ), $MMPvars ); 
}

#   send_mmp (target, data, vars)
sub send_mmp {
    my ( $target, $data, $vars ) = @_;
    
    # maybe we can check for the caller of sendmsg and use his unl as
    # source.. TODO ( works with Event only ). stone perloo
    $target or croak 'usage: send_mmp( $UNL, $MMPdata, %MMPvars )';
    #
    # presence of a method or data is not mandatory:
    # a simple modification of a variable may be sent as well,
    # although that only starts making sense once _state is implemented.
    $vars ||= {};
    $vars->{'_target'} ||= $target;
    
    my $connection = get_connection( $target );
    return 0 if (!$connection);
    return $connection->send( $target, $data, $vars );
}

# this is root-msg
#
# i would like to change this one day.. 
sub msg {
    my ($source, $mc, $data, $vars) = @_;
    
    my $obj = $vars->{'_INTERNAL_origin'};

    return 0 unless($obj);

    if ($mc eq '_notice_circuit_established') {
	unless ($obj->{'L'}) {
	    if ($vars->{'_target'}) {
		my $r = parse_uniform($vars->{'_target'});
		if (ref $r && $r->{'host'}) {
		    register_host('127.0.0.1', $r->{'host'});
		}
	    }
	}
    } elsif ($mc eq '_status_circuit') {
	$obj->{'r_options'} = $vars;
	unless ($obj->{'L'}) {
	    syswrite($obj->{'SOCKET'}, ".\n");
	    syswrite($obj->{'SOCKET'}, delete $obj->{'greet'});
	}

	return 1 if (!exists $vars->{'_understand_modules'});
	    
	unless (ref $vars->{'_understand_modules'} eq 'ARRAY') {
	    $vars->{'_understand_modules'} = [ 
		split(/;/,$vars->{'_understand_modules'}) 
	    ];
	}
	# TODO . find out why the revoke after the if stops psycion
	# in certain situations.. 
	revoke($obj->{'SOCKET'}, 'w');
	if (member($vars->{'_understand_modules'}, '_encrypt')) {
	    return 1 unless eval{ require IO::Socket::SSL };
	    $obj->fire('', '', '', { '_using_modules' => '_encrypt' } );
	    $obj->{'SSL_client'} = 1;
	    remove($obj->{'SOCKET'}, 'w');
	    return 1;
	} elsif (member($vars->{'_understand_modules'}, '_compress')) {
	    return 1 unless eval{ require Net::PSYC::MMP::Compress };
	    $obj->fire('', '', '', { '_using_modules' => '_compress' } );
	    unless ($obj->{'_compress'}) {
		$obj->{'_compress'} = new Net::PSYC::MMP::Compress($obj);
	    }
	    $obj->{'_compress'}->init('encrypt');
	}
	#revoke($obj->{'SOCKET'}, 'w');
	return 1;
    } elsif (!$mc) {
	# TODO switch to + when the muve is capable
	unless (exists $vars->{'_using_modules'}) {
	    return 1;
	}
	if ($vars->{'_using_modules'} eq '_encrypt') {
	    return 1 unless eval{ require IO::Socket::SSL };
	    if ($obj->{'SSL_client'}) {
		$obj->tls_init_client();
		return 1;
	    }
	    $obj->tls_init_server();
	    return 1;
	} elsif ($vars->{'_using_modules'} eq '_compress') {
	    return 1 unless eval{ require Net::PSYC::MMP::Compress };
	    # strange days here we come..
	    # somehow _compress does not work, which is not fatal
	    unless ($obj->{'_compress'}) {
		$obj->{'_compress'} = new Net::PSYC::MMP::Compress($obj);
	    }
	    $obj->{'_compress'}->init('decrypt');
	    
	    if ($obj->{'I_BUFFER'}) { # encrypted data in the buffer
		$obj->{'_compress'}->decrypt(\$obj->{'I_BUFFER'});
	    }
	    return 1;
	}
	
    }
    
    return 1;
    sub member { scalar(grep {$_ eq $_[1]} @{$_[0]}) }
}
sub psyctext {
    my $text = shift;
    $text =~ s/\[(_\w+)\]/my $ref = ((exists $_[0]->{$1}) ? $_[0]->{$1} : ''); (ref $ref eq 'ARRAY') ? join(' ', @$ref) : $ref;/goe;
    return $text;
}

sub parse_mmp {
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
#    W("Starting to parse MMP:");

    while ($$d =~ m/\G([+-:=\?])(\w+)[\t\ ]+(.*?)$linefeed/gc) {
#	print "$&\n";
        my ($mod, $key, $value) = ( $1, $2, $3 );
	$key = $mod.$key unless ($mod eq ':');
        $vars->{$key} = $value;
#	W("\$\$vars{$mod}->{$key} = $value;");
        $mod = '\\'.$mod; # '?' causes regexp to die
        while ($$d =~ m/\G$mod[\t\ ]+(.*?)$linefeed/gc) {
            $vars->{$key} = [$vars->{$key}]
                if (!ref $vars->{$key}); # create an array
            push(@{$vars->{$key}}, $1); # push new element
        }
	if ($key =~ /^[=+-\?]?_list_/ && !ref($vars->{$key})) {
	    $vars->{$key} = [ $vars->{$key} ];
	}
    }
#    print STDERR "position before \\n: ".pos($$d)."\n";
#    pos($$d)++; # s/^\n/
#    empty packets hack
    if ($$d =~ /\G$linefeed\.$linefeed/ || $$d =~ /\G\.$linefeed/) {
	substr($$d, 0, (pos($$d)||0) + length($&), '');
	return ($vars, ''); 
    }
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
    return unless(defined(pos($$d))); # protocol error!
    my $length = $vars->{'=_length'} || $vars->{'_length'} || 0;
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
	# TODO - 3 is wrong.. $linefeed may be \r\n
	substr($$d, 0, pos($$d) + 3, '');
    }
#    use Data::Dumper;
#    print STDERR "REturning packet:\n";
#    print STDERR Dumper($vars);
    return ($vars, $data);
}

sub parse_psyc {
    my $d = shift;
    my $linefeed = shift || "\n";
    my ($vars, $mc, $data) = ( {}, '', '');
    $d = $$d if (ref $d eq 'SCALAR');
    # vars
    # hier noch alle \n\t mitnehmen, für multiline-support
    while ($d =~ s/^([+-:=?])(_\w+)\s*(.*)$linefeed//) {
        my ($mod, $key) = ($1, $2);
	$key = $mod.$key unless ($mod eq ':');
        $vars->{$key} = $3;

	$mod = '\\'.$mod;
        while ($d =~ s/^$mod\t(.*)$linefeed//) { #list
	    # hier noch alle \n\t mitnehmen, für multiline-support
            $vars->{$key} = [$vars->{$key}]
                unless (ref $vars->{$key});
            push(@{$vars->{$key}}, $1);
        }
	if ($key =~ /^[=+-\?]?_list_/ && !ref($vars->{$key})) {
	    $vars->{$key} = [ $vars->{$key} ];
	}
    }
    # mc
    if ($d =~ s/^(_\S+)$linefeed// || $d =~ s/^(_\S+)$//) {
        $mc = $1;
    } else {
	# W("Syntax error in incoming PSYC packet!", 0);
    }
    return ($mc, $d, $vars);
}

sub make_mmp {
    use bytes;
    my ($vars, $data) = @_;
    my $m;
    
    $vars->{'_length'} = length($data)
	if (index($data, "\n.\n") != -1 || index($data, "\r\n.\r\n") != -1);
    
    $m = makeVARS($vars);
    if ($data =~ /^[:+=-?]/ || 1) {
	$m .= "\n$data\n.\n";
    } else { # this may not work with pypsyc and muve.. maybe. so we dont use it
	$m .= "$data\n.\n";
    }
    return $m;
}

sub makeVARS {
    my ($vars) = shift;
    my $m = '';
    return $m unless ref $vars;
    
    # sort keys to avoid
    foreach (sort keys %$vars) {
	my $mod = substr($_, 0, 1);
	my $key = $_;
	
	if ($mod ne '_') {
	    $key = substr($_, 1);
	} else { $mod = ':'; }

	$m .= "$mod$key\t".VAR($vars->{$_}, $mod)."\n";
	
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

#   make_psyc ( mc, data, vars)
sub make_psyc {
    my ($mc, $data, $vars) = @_;
    return makeVARS($vars).$mc."\n".($data || '');
}


sub makeMSG { 
    my ($mc, $data) = @_;
    my $vars = $_[2] || {};
    my $MMPvars = {};
    
    foreach (keys %{$vars}) {
            if (/[+=-\?]?_target/
            ||  /[+=-\?]?_source/
            ||  /[+=-\?]?_context/) {
                $MMPvars->{$_} = delete($vars->{$_});
            }
    }
    return ($MMPvars, make_psyc($mc, $data, $vars)) if wantarray;
    # we want data and MMP-stuff seperated to do fragmentation
    return make_mmp($MMPvars, make_psyc($mc, $data, $vars));
}

sub parse_uniform {
    my $arg = shift;
    my $user;
    my ($scheme, $host) = ($arg =~ m/^(\w+)\:\/\/([^\/:]*)/gcm);
    return 0 unless ($scheme);
    my ($port, $proto) = ($arg =~ m/\G\:(\d*)(\w*)/gcm);
    my ($object) = ($arg =~ m/\G\/(.*)$/gcm);
    if ($host =~ /([^@]+)\@([^@]+)/) {
	$user = $1; $host = $2;
    }
    return ($user||'', $host, $port||'', $proto||'', $object||'') if wantarray;
    return {
	unl => $arg,
	host => $host||'',	
	port => $port||0,
	transport => $proto||'',
	object => $object||'',
	user => $user||'',
	scheme => $scheme||'',
    };    
}


sub make_uniform {
        my ($user, $host, $port, $type, $object) = @_;
        $port = '' if $port == PSYC_PORT || !$port;
	unless ($object) {
	    $object = '';
	} else {
	    $object = '/'.$object;
	}
	
        $type = '' unless $type;
        unless ($host) {
                croak 'well-known UNIs not standardized yet';
                # return "psyc:$object"
        }
        $host = "$user\@$host" if $user;
        return "psyc://$host$object" unless $port || $type;
        return "psyc://$host:$port$type$object";
}

################################################################
# Functions needed to be downward compatible to Net::PSYC 0.7
# Not entirely clear which of these we can really call obsolete
# 
sub dirty_wait {
    return Net::PSYC::Event::can_read(@_);
}
#
sub dirty_add {
    Net::PSYC::Event::add($_[0], 'r', sub { 1 }); 
}
sub dirty_remove { Net::PSYC::Event::remove(@_); }
#
# alright, so this should definitely not be used as it will not
# be able to handle multiple and incomplete packets in one read operation.
sub dirty_getmsg {
    my $key;
    my @readable = Net::PSYC::Event::can_read(@_);
    my %sockets = %{&Net::PSYC::Event::PSYC_SOCKETS()};
    my ($mc, $data, $vars);
    SOCKET: foreach (@readable) {
	$key = scalar($_);
	if (exists $sockets{$key}) { # found a readable psyc-obj
	    unless (defined($sockets{$key}->read())) {
		Net::PSYC::shutdown($sockets{$key});
		W("Lost connection to $sockets{$key}->{'R_IP'}:$sockets{$key}->{'R_PORT'}");
		next SOCKET;
	    }
	    while (1) {
		my ($MMPvars, $MMPdata) = $sockets{$key}->recv();
		print STDERR "mmp-data: ",$MMPdata,"\n\r";
		next SOCKET if (!defined($MMPdata));
		
		($mc, $data, $vars) = parse_psyc($MMPdata, $sockets{$key}->{'LF'});	
		last if($mc); # ignore empty messages..
	    }
	    print "\n=== dirty_getmsg ",'=' x 67,"\n", $data, "\n",'=' x 79,"\n"
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

PSYC is a flexible text-based protocol for delivery of data to a flexible
amount of recipients by unicast or multicast TCP or UDP. It is primarily
used for chat conferencing, multicasting presence, friendcasting, newscasting,
event notifications and plain instant messaging, but not limited to that.

Existing systems can easily use PSYC, since PSYC hides its complexity from
them. For example if an application wants to send data to one person or a
group of people, it just needs to drop a few lines of text into a TCP
connection (or UDP packet) to a static address. In other words: trivial.

The PSYC network resembles more the Web rather than IRC, which it once was
inspired by. Each administrator of a machine on the Internet can install a
PSYC server which has equal rights in the world wide network. No hierarchies,
no boundaries. The administrator then has the right to decide which rooms or
people to host, without interfering with other PSYC servers. Should an
administrator behave incorrectly towards her users, they will simply move on
to a different server. Thus, administrators must behave to be a popular PSYC
host for their friends and social network.

This implementation is in pretty stable and has been doing a good job in
production environments for several years.

See http://psyc.pages.de for protocol specs and other info on PSYC.

=head1 SYNOPSIS

Small example on how to send one single message:

    use Net::PSYC;
    sendmsg('psyc://example.org/~user', '_notice_whatever', 
	    'Whatever happened to the 80\'s...');

Receiving messages:
	    
    use Net::PSYC qw(:event bind_uniform); 
    register_uniform(); # get all messages
    bind_uniform(); # start listening on :4404 tcp and udp.
    
    start_loop(); # start the Event loop
    
    sub msg {
	my ($source, $mc, $data, $vars) = @_;
	print "A message ($mc) from $source reads: '$data'\n";
    }    
 
=head1 PERL API

=over 4

=item bind_uniform( B<$localpsycUNI> )

starts listening on a local hostname and TCP and/or UDP port according to the PSYC UNI specification. When omitted, a random port will be chosen for both service types. 

=item sendmsg( B<$target>, B<$mc>, B<$data>, B<$vars> )

compatible to psycMUVEs sendmsg, accepts four of five PSYC packet elements, source being defined by setSRC if necessary.
 
=item castMSG( B<$context>, B<$mc>, B<$data>, B<$vars> )

is NOT available yet. Net::PSYC does not implement neither context masters nor
multicasting. if you need to distribute content to several recipients please
allocate a context on a psycMUVE and sendmsg to it.

=item send_mmp( B<$target>, B<$data>, B<$vars> )

sends an MMP packet to the given B<$target>. B<$data> may be a reference to an array of fragmented data. 

=item psyctext( B<$format>, B<$vars> )

compatible to psycMUVEs psyctext, renders the strings in B<$vars> into the B<$format> and returns the resulting text conformant to the text/psyc content type specification.

=item make_uniform( B<$user>, B<$host>, B<$port>, B<$type>, B<$object> )

Renders a PSYC uniform specified by the given elements. It basically produces: "psyc://$user@$host:$port$type/$object"
 
=item UNL()

returns the current complete source uniform.
UNL stands for Uniform Network Location.

=item setDEBUG( B<$level> )

Sets B<$level> of debug:

0 - no debug, only critical errors are reported

1 - some

2 - a lot (even incoming/outgoing packets)

=item DEBUG()

returns the current level of debug.

=item W( B<$text>, B<$level> )

W() is used internally to print out debug-messages depending on the level of debug. You may want to overwrite this function to redirect output since the default is STDERR which can be really fancy-shmancy.

=item dns_lookup( B<$host> )

Tries to resolve B<$host> and returns the ip if successful. else 0.

Take care, dns_lookup is blocking. Maybe I will try to switch to nonblocking dns in the future.

=item same_host( B<$host1>, B<$host2> )

Returns 1 if the two hosts are considered identical. 0 else. Use this function instead of your own dns_lookup magic since hostnames are cached internally.

=item register_host( B<$ip>, B<$host> )

Make B<$host> point to B<$ip> internally.

=item register_route( B<$target>, B<$connection> )

From now on all packets for B<$target> are send via B<$connection> (Net::PSYC::Circuit or Net::PSYC::Datagram). B<$target> may be an UNI or a host[:port].

=back

=head1 Export

Apart from the shortcuts below every single function may be exported seperately. You can switch on Eventing by using 

    use Net::PSYC qw(Event=IO::Select); 
    # or
    use Net::PSYC qw(Event=Gtk2);
    # or
    use Net::PSYC qw(Event=Event); # Event.pm

=over 4

=item use Net::PSYC qw(:encrypt);

Try to use ssl for tcp connections. You need to have L<IO::Socket::SSL> installed. Right now only tls client functionality works. 

=item use Net::PSYC qw(:compress);

Use L<Compress::Zlib> to compress data sent via tcp. Works fine for connections to applications using Net::PSYC and L<psycMUVE>.

=item use Net::PSYC qw(:event);

:event activates eventing (by default IO::Select which should work on every system) and exports some functions (watch, forget, register_uniform, unregister_uniform, add, remove, start_loop, stop_loop) that are useful in that context. Have a look at L<Net::PSYC::Event> for further documentation.

=item use Net::PSYC qw(:base);

exports bind_uniform, psyctext, make_uniform, UNL, sendmsg, dirty_add, dirty_remove, dirty_wait, parse_uniform and dirty_getmsg.

=item use Net::PSYC qw(:all);

exports makeMSG, parse_uniform, PSYC_PORT, PSYCS_PORT, UNL, W, AUTOWATCH, sendmsg, make_uniform, psyctext, BASE, SRC, DEBUG, setBASE, setSRC, setDEBUG, register_uniform, make_mmp, make_psyc, parse_mmp, parse_psyc, send_mmp, get_connection, register_route, register_host, same_host, dns_resolve, start_loop, stop_loop and psyctext.

=back

=head1 Eventing

See Net::PSYC::Event for more.

dirty_add, dirty_remove and dirty_wait implement a pragmatic IO::Select wrapper for applications that do not need an event loop. 

For further details.. Use The Source, Luke!

=head1 SEE ALSO

L<Net::PSYC::Event>, L<Net::PSYC::Client>, L<http://psyc.pages.de> for more information about the PSYC protocol, L<http://muve.pages.de> for a rather mature PSYC server implementation (also offering IRC, Jabber and a Telnet interface) , L<http://perlpsyc.pages.de> for a bunch of applications using Net::PSYC.

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

Copyright (c) 1998-2005 Carlo v. Loesch and Arne GE<ouml>deke. All rights reserved.

This program is free software; you may redistribute it and/or modify it
under the same terms as Perl itself. Derivatives may not carry the
title "Official PSYC API Implementation" or equivalents.
	
