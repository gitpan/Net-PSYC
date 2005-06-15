package Net::PSYC::Event;
#
# Net::PSYC::Event - Event wrapper for different event systems.
#
# nur weil diese sachen im jahre 2003 aus Net::PSYC.pm ausgelagert
# wurden, und bis dahin nur mit IO::Select gearbeitet haben,
# haben sie dennoch und nach wie vor den originalcopyright... ;)

use strict;

my (%UNL);
my (%PSYC_SOCKETS);

use Exporter ();
our ($VERSION, @ISA, @EXPORT, @EXPORT_OK);

$VERSION = '0.4';

@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(register_uniform unregister_uniform watch forget init start_loop stop_loop add remove can_read can_write has_exception revoke);

INIT {
    require Net::PSYC;
    import Net::PSYC qw(W sendmsg same_host send_mmp parse_uniform parse_psyc);
}

# dirty_wait hack!
sub PSYC_SOCKETS { \%PSYC_SOCKETS }

# vielleicht sollte man psyc-state auf dauer mit register_uniform verknüpfen. 
# so wie ich es schonmal geplant hatte. Vor allem, was tut man mit den 
# register_uniform() calls. bekommen die _einen_ state oder nochmal getrennt 
# nach source und target mehrere. Sind user in der lage das selbst zu
# entscheiden/begreifen??
sub register_uniform {
    my ($unl, $obj) = @_;
    
    if ($obj) {
	unless ($obj->can('msg')) {
	    W(ref $obj."does not have a msg()-method! Cannot deliver packet!",0);
	    return $obj;
	}
	unless ($obj->can('diminish') && $obj->can('augment') 
	&& $obj->can('assign')) {
	    my $o = $obj;
	    $obj = Net::PSYC::Event::Wrapper->new(sub { $o->msg(@_) }, $unl);
	}
    } else {
	$obj = caller; # just a class.. that sux.
	my $f = eval "\\&$obj\::msg";
	if (defined($unl) && exists $UNL{$unl} && $UNL{$unl}->{'msg'} eq $f) {
	    return $UNL{$unl};
	}
	unless (eval "$obj->can('msg')") {
	    W($obj."does not have a msg() function! Cannot deliver packet!", 0);
	    return $obj;
	}
	$obj = Net::PSYC::Event::Wrapper->new($f, $unl);
    }
    W("register_uniform(".(defined($unl) ? $unl : '').", $obj)");
    unless (defined($unl)) {
	$UNL{'default'} = $obj;
    } else {
	$UNL{$unl} = $obj;
    }
    
    return $obj;
}

sub find_object {
    my $uni = shift;
    W("find_object(".(defined($uni) ? $uni : '').")");
    my $o = $UNL{$uni};
    unless ($o) {
	my $h = parse_uniform($uni);
	if (ref $h) {
	    $o = $UNL{$h->{'object'}};
	}
    }
    $o ||= $UNL{'default'};
    return $o;
}

sub unregister_uniform {
    my $unl = shift;
    delete $UNL{$unl};
    return 1;
}

#   watch(psyc-socket-object)
sub watch {
    my $obj = shift;
    $PSYC_SOCKETS{scalar($obj->{'SOCKET'})} = $obj;
    add($obj->{'SOCKET'}, 'r', sub { deliver($obj->{'SOCKET'}); return 1; } );
    add($obj->{'SOCKET'}, 'w', sub { $obj->write() }, 0);
}

#   forget(psyc-socket-object)
sub forget {
    delete $PSYC_SOCKETS{scalar($_[0]->{'SOCKET'})};
    remove($_[0]->{'SOCKET'});
}

sub deliver {
    return 1 if (!exists $PSYC_SOCKETS{scalar($_[0])});
    my $obj = $PSYC_SOCKETS{scalar($_[0])};
    
    unless ($obj->read()) { # connection lost
	Net::PSYC::shutdown($obj);
	W("Lost connection to $obj->{'R_IP'}:$obj->{'R_PORT'}");
	return 1;
    }
    while (1) {
	my ($MMPvars, $MMPdata) = $obj->recv(); # get a packet
	
	return 1 if (!defined($MMPvars)); # incomplete .. stop
	
	next if ($MMPvars == 0); # fragment .. keep on going
	
	if ($MMPvars == -1) { # shutdown
	    Net::PSYC::shutdown($obj);
	    W("Shutting down connection to $obj->{'R_IP'}:$obj->{'R_PORT'} for being in league with the devil of 'incorrect psyc'.",0);
	    return 1;
	}
	
	if ($MMPvars->{'_target'}) {
	    my $t = parse_uniform($MMPvars->{'_target'});

	    unless (ref $t) {
		Net::PSYC::shutdown($obj);
		W("Shutting down connection to $obj->{'R_IP'}:$obj->{'R_PORT'} for sending a _target ($MMPvars->{'_target'}) we could not parse.",0);
		return 1;
	    }
	    unless (same_host($t->{'host'}, '127.0.0.1')) {
		# this is a remote uni
		if ($obj->TRUST > 10) { # we relay
		    send_mmp($MMPvars->{'_target'}, $MMPdata, $MMPvars);
		    next;
		} # we dont relay
		sendmsg($MMPvars->{'_source'},
			'_error_relay_denied',
			"I won't deliver that!");
		next;
	    }
	}
	
	my ($mc, $data, $vars) = parse_psyc($MMPdata, $obj->{'LF'});

	# in the FUTURE this would be a legal way to send changes in psyc-state
	unless (defined($mc)) {
	    W("Broken PSYC packet from $obj->{'peeraddr'}.",0);
	    W("Shutting down connection to $obj->{'R_IP'}:$obj->{'R_PORT'} for being in league with the devil of 'incorrect psyc'.",0);
	    Net::PSYC::shutdown($obj);
	    return 1;
	}

	my $cb;
	if ((!$MMPvars->{'_target'} && !$MMPvars->{'_context'}) 
	||  $mc eq '_notice_circuit_established') {
	    $cb = find_object(0);
	} else {
	    $cb = find_object($MMPvars->{'_target'});
	}
	
	unless ($cb) {
	    W('Noone registered for '.$MMPvars->{'_target'}, 0);
	    next;
	}
	
	foreach (keys %$vars) {
	    if (/^=_/) {
		$cb->assign($MMPvars->{'_source'}, 
			    substr($_, 1),
			    $vars->{$_});
		$vars->{substr($_, 1)} = delete $vars->{$_};
	    }
	    $cb->augment($MMPvars->{'_source'}, 
			 substr($_, 1),
			 delete $vars->{$_}) if (/^\+_/);
	    $cb->diminish($MMPvars->{'_source'}, 
			  substr($_, 1),
			  delete $vars->{$_}) if (/^-_/);

	}
	    
	$cb->msg($MMPvars->{'_source'}, $mc, $data, { %$MMPvars, %$vars });
    }
    return 1;
}

sub init {
    if ($_[0] eq 'Event') {
        require Net::PSYC::Event::Event;
        import Net::PSYC::Event::Event qw(can_read can_write has_exception add remove start_loop stop_loop revoke);
	return 1;
    } elsif ($_[0] eq 'IO::Select') {
        require Net::PSYC::Event::IO_Select;
        import Net::PSYC::Event::IO_Select qw(can_read can_write has_exception add remove start_loop stop_loop revoke);
	return 1;
    } elsif ($_[0] eq 'Gtk2') {
        require Net::PSYC::Event::Gtk2;
        import Net::PSYC::Event::Gtk2 qw(can_read can_write has_exception add remove start_loop stop_loop revoke);
	return 1;
    }
}

package Net::PSYC::Event::Wrapper;
# a wrapper-object to make classes work like objects in register_uniform

use Net::PSYC::State;

# this is beta since it does not allow anyone to handle several psyc-objects at
# once. remember: register_uniform() allows wildcards
use base 'Net::PSYC::State';


sub new {
    my $class = shift;
    my $self = {};
    $self->{'msg'} = shift;
    $self->{'unl'} = shift;
    $self->{'psyc_i_state'} = {};
    $self->{'psyc_o_state'} = {};
    return bless $self, $class;
}

sub msg {
    my $self = shift;
    $self->SUPER::msg(@_);
    &{$self->{'msg'}};
}

1;

__END__

=head1 NAME

Net::PSYC::Event - Event wrapper for various event systems.

=head1 DESCRIPTION

Net::PSYC::Event offers an interface to easily use L<Net::PSYC> with various different Event systems. It currently offers support for Event.pm, IO::Select and Gtk2.

=head1 SYNOPSIS

    # load Net::PSYC::Event for Gtk2 eventing.
    use Net::PSYC qw(Event=Gtk2);
    use Net::PSYC::Event qw(register_uniform unregister_uniform start_loop);

    bind_uniform('psyc://example.org/');
    register_uniform('psyc://example.org/@chatroom');
 
    sub msg {
	my ($source, $mc, $data, $vars) = @_;
	# lets do some conferencing
    }

    start_loop() # start the event-loop
 
=head1 PERL API

=over 4

=item register_uniform( B<$unl>[, B<$object> ] )
	
Registers B<$object> or the calling package for all incoming messages targeted at B<$unl>. Calls 

B<$object>->msg( $source, $mc, $data, $vars ) or

caller()::msg( $source, $mc, $data, $vars )

for every incoming PSYC packet.

=item unregister_uniform( B<$unl> )
	
Unregister an B<$unl>. No more packages will be delivered for that B<$unl> thenceforward.

=item start_loop()

Start the Event loop. 

=item stop_loop()

Stop the Event loop.

=item add( B<$fd>, B<$flags>, B<$callback>[, B<$repeat>])
 
Start watching for events on B<$fd>. B<$fd> may be a GLOB or an IO::Handle object. B<$flags> may be B<r>, B<w> or B<e> (data to be read, written or pending exceptions) or any combination. 
 
If B<$repeat> is set to 0 the callback will only be called once (revoke() may be used to reactivate it). If you don't want one-shot events either leave B<$repeat> out or set it to 1.

=item $id = add( B<$time>, 't', B<$callback>[, B<$repeat>])

Add a timer event. The event will be triggered after B<$time> seconds. This is a one-shot event by default. However, if B<$repeat> is set to 1, B<$callback> will be called every B<$time> seconds until the event is removed.

One-shot timer events are removed automatically and B<revoke> is not possible for them.

Remember: You are not using a real-time system. The accuracy of timer events depends heavily on other events pending, io-operations and system load in general. 

=item remove( B<$fd>[, B<$flags>] )

Stop watching for events on B<$fd>. Different types can not be removed seperately if they have been add()ed together!

=item remove( B<$id> )

Removed the timer-event belonging to the given B<$id>. 

=item revoke( B<$fd> )

Revokes the eventing for B<$fd>. ( one-shot events ) 


=back
 
=head1 SEE ALSO

L<Net::PSYC>, L<Net::PSYC::Client>, L<Net::PSYC::Event::Event>, L<Net::PSYC::Event::IO_Select>, L<Net::PSYC::Event::Gtk2>, L<http://psyc.pages.de/>

=head1 AUTHORS

Arne GE<ouml>deke <el@goodavice.pages.de>

=head1 COPYRIGHT

Copyright (c) 1998-2005 Arne GE<ouml>deke and Carlo v. Loesch.
All rights reserved.
This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut


