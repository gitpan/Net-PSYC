package Net::PSYC::Event;
#
#
$VERSION = '0.1';

use strict;
use Exporter;
use Carp;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

my (%UNL);
my (%PSYC_SOCKETS);

@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(registerPSYC unregisterPSYC watch forget init startLoop add remove can_read can_write has_exception revoke);

# waitPSYC hack!
sub PSYC_SOCKETS { \%PSYC_SOCKETS }

sub registerPSYC {
    my ($unl, $obj) = @_;
    if ($obj) {
	if (wantarray ne undef) { # return a state-object
	    require Net::PSYC::State;
	    $obj = Net::PSYC::State->new($unl, $obj);
	}	    
    } else {
	$obj = caller; # just a class.. that sux.
    }
    print STDERR "registerPSYC($unl, $obj)\n" if Net::PSYC::DEBUG;
    foreach ((ref $unl) ? @$unl : ($unl)) {
	if (!$_) {
	    $UNL{'default'} = $obj;
	} else {
	    $UNL{$_} = $obj;
	}
    }
    
    return $obj;
}

sub unregisterPSYC {
    my $unl = shift;
    if (!ref $unl) {
	delete $UNL{$unl};
	return 1;
    } elsif (ref $unl eq 'ARRAY') {
	foreach (@$unl) {
	    delete $UNL{$_};
	}
	return 1;
    }
}

#   watch(psyc-socket-object)
sub watch {
    my $obj = shift;
    if (ref $obj eq 'ARRAY') {
	foreach (@$obj) {
	    $PSYC_SOCKETS{scalar($_->{'SOCKET'})} = $_;
	    add($_->{'SOCKET'}, 'r', sub { deliver($_->{'SOCKET'}) } );
	    add($_->{'SOCKET'}, 'w', sub { $_->write() }, 0);
	}
    } else {
	$PSYC_SOCKETS{scalar($obj->{'SOCKET'})} = $obj;
	add($obj->{'SOCKET'}, 'r', sub { deliver($obj->{'SOCKET'}); return 1; } );
	add($obj->{'SOCKET'}, 'w', sub { $obj->write() }, 0);
    } 
}

#   forget(psyc-socket-object)
sub forget {
    delete $PSYC_SOCKETS{scalar($_[0]->{'SOCKET'})};
    remove($_[0]->{'SOCKET'});
}

sub deliver {
#    print STDERR "Net::PSYC::Event->deliver(@_)\n";
    if (exists $PSYC_SOCKETS{scalar($_[0])}) {
	my $obj = $PSYC_SOCKETS{scalar($_[0])};
	
	unless ($obj->read()) { # connection lost
	    Net::PSYC::shutdown($obj);
	    print "Lost connection to $obj->{'R_IP'}:$obj->{'R_PORT'}\n" if Net::PSYC::DEBUG();
	    return 1;
	}
	while (1) {
	    my ($MMPvars, $MMPdata) = $obj->recv(); # get a packet
	    my $cb;
	    
#	    use Data::Dumper;
#	    print Dumper($MMPvars, $MMPdata);
	    return 1 if (!defined($MMPvars)); # incomplete .. stop
	    
	    next if ($MMPvars == 0); # fragment .. keep on going
	    next if (!exists $MMPvars->{'_target'});
	    
	    if (!exists $UNL{$MMPvars->{'_target'}}) {
		my ($host) = $MMPvars->{'_target'} =~ m/^psyc:\/\/(\S+?)[:\/]/;
		unless (Net::PSYC::same_host($host, '127.0.0.1')) {
		    if ($obj->TRUST > 10) { # relay!
			$MMPvars->{'_source_relay'} ||= $MMPvars->{'_source'};
			# ^^ is that correct ?? TODO
			print STDERR "Relaying for $obj->{'R_IP'} (_target: $MMPvars->{'_target'})\n" if Net::PSYC::DEBUG;
			$MMPvars->{'_source'} = Net::PSYC::UNL();
			Net::PSYC::sendMMP($MMPvars->{'_target'}, $MMPdata, $MMPvars);
			next;
		    }
		    Net::PSYC::sendMSG($MMPvars->{'_source'},
				       '_error_relay_denied',
				       "I won't deliver that!");
		    # else reply a _error_relay_denied
		    next;		    
		}
		# TODO .. new parseUNL-stuff please
		my @u = Net::PSYC::parseUNL($MMPvars->{'_target'});
		if (defined($u[0]) && exists $UNL{$u[4]}) {
		    $cb = $UNL{$u[4]};
		} elsif ($UNL{'default'}) {
		    $cb = $UNL{'default'};
		} else {
		    print STDERR "$MMPvars->{'_target'} has not been registered! use registerPSYC()!\n" if Net::PSYC::DEBUG;
		    next;
		} 
	    } else {
		$cb = $UNL{$MMPvars->{'_target'}};
	    }
	    
	    my ($mc, $data, $vars, $v) = Net::PSYC::PSYCparse($MMPdata, $obj->{'LF'});

	    $vars = {%{$v->{'='}}, %$vars} if ($v->{'='}); # TODO .. 
	    
	    if (ref $cb) { # we have an object
		croak(ref $cb." does not have a msg()-method! Cannot deliver packet!") if !$cb->can('msg');
		$cb->msg($MMPvars->{'_source'}, $mc, $data, {%$MMPvars, %$vars});
	    } else { # we have a package
		eval $cb.'::msg($MMPvars->{\'_source\'}, $mc, $data, {%$MMPvars, %$vars});' or croak("Could not call ".$cb."::msg(). $@");
	    }
	}
    }
    return 1;
}

sub init {
    if ($_[0] eq 'Event') {
        require Net::PSYC::Event::Event;
        import Net::PSYC::Event::Event qw(can_read can_write has_exception add remove startLoop stopLoop revoke);
	Net::PSYC::setAUTOWATCH(1);
	return 1;
    } elsif ($_[0] eq 'IO::Select') {
        require Net::PSYC::Event::IO_Select;
        import Net::PSYC::Event::IO_Select qw(can_read can_write has_exception add remove startLoop stopLoop revoke);
	Net::PSYC::setAUTOWATCH(1);
	return 1;
    } elsif ($_[0] eq 'Gtk2') {
        require Net::PSYC::Event::Gtk2;
        import Net::PSYC::Event::Gtk2 qw(can_read can_write has_exception add remove startLoop stopLoop revoke);
	Net::PSYC::setAUTOWATCH(1);
	return 1;
    }
}

1;

__END__

=head1 NAME

Net::PSYC::Event - Event wrapper for different event systems.

=head1 DESCRIPTION

Net::PSYC::Event offers an interface to easily use L<Net::PSYC> with different Event systems. It currently offers support for Event, IO::Select and Gtk2.

=head1 SYNOPSIS

    # load Net::PSYC::Event for Gtk2 eventing.
    use Net::PSYC qw(Event=Gtk2);
    use Net::PSYC::Event qw(registerPSYC unregisterPSYC startLoop);

    bindPSYC('psyc://myfunkyhostname/');
    registerPSYC('psyc://myfunkyhostname/@chatroom');
 
    sub msg {
	my ($source, $mc, $data, $vars) = @_;
	# lets do some conferencing
    }

    startLoop() # start the event-loop
 
=head1 PERL API

=over 4

=item registerPSYC( B<$unl>[, B<$object> ] )
	
Registers B<$object> or the calling package for all incoming messages targeted at B<$unl>. Calls 

B<$object>->msg( $source, $mc, $data, $vars ) or

caller()::msg( $source, $mc, $data, $vars )

for every incoming PSYC packet.

=item unregisterPSYC( B<$unl> )
	
Unregister an B<$unl>. No more packages will be delivered for that B<$unl> thenceforward.

=item startLoop()

Start the Event loop. 

=item stopLoop()

Stop the Event loop.

=item add( B<$fd>, B<$flags>, B<$callback>[, B<$repeat>])
 
Start watching for events on B<$fd>. B<$fd> may be a GLOB or an IO::Handle object. B<$flags> may be B<r>, B<w> or B<e> (data to be read, written or pending exceptions) or any combination. 
 
If B<$repeat> is set to 0 the callback will only be called once (revoke() may be used to reactivate it). If you don't want one-shot events either leave B<$repeat> out or set it to 1.

=item revoke( B<$fd> )

Revokes the eventing for B<$fd>. ( one-shot events ) 

=item remove( B<$fd>[, B<$flags>] )

Stop watching for events on B<$fd>. Different types can not be removed seperately if they have been add()ed together!

=back
 
=head1 SEE ALSO

L<Net::PSYC>, L<Net::PSYC::Client>, L<Net::PSYC::Event::Event>, L<Net::PSYC::Event::IO_Select>, L<Net::PSYC::Event::Gtk2>, L<http://psyc.pages.de/>

=head1 AUTHORS

Arne GE<ouml>deke <el@goodavice.pages.de>

=head1 COPYRIGHT

Copyright (c) 2003-2004 Arne GE<ouml>deke. All rights reserved.
This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut


