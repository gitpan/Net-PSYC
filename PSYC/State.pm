package Net::PSYC::State;
# module implementing psyc-state-maintainance for objects...
#
# the state of mmp-vars is maintained by the connection
# object!


# gets an UNL and a corresponding psyc-obj

#   new ( class, UNL, psyc-obj )
sub new {
    
    $self = {
	'V'	=> {}, # psyc-vars
	'UNL'	=> $_[1],
	'O'	=> $_[2]
    };
    
    return bless $self, shift;
}

#   sendMSG ( target, mc, data, vars[, source || mmp-vars ] )
sub sendMSG {
    my $self = shift;
    if (!$_[4]) {
	$_[4] = $self->{'UNL'};
    } elsif (ref $_[4]) {
	$_[4]->{'='}->{'_source'} ||= $self->{'UNL'};
    }
    Net::PSYC::sendMSG($_[0], $_[1], $_[2], $_[3], $_[4]); 
}

#   msg ( source, mc, data, :, vars )
sub msg {
    my $self = shift;
    my ($source, $mc, $data, $vars, $mvars) = @_;
    my $V = ( $self->{'V'}->{$source} ||= {} );

    # =
    $V = { %$V, %{$mvars->{'='}} } if(exists $mvars->{'='});
    # +
    if (exists $mvars->{'+'}) {
	foreach (keys %{$mvars->{'+'}}) {
	    if (!ref $V->{$_}) {
		$V->{$_} = [ $V->{$_} ];
	    }
	    push(@{$V->{$_}}, $mvars->{'+'}->{$_}) if (ref $V->{$_} eq 'ARRAY');
	}
    }
    # -
    if (exists $mvars->{'-'}) {
	foreach my $a (keys %{$mvars->{'-'}}) {
	    if (ref $V->{$_} eq 'ARRAY') {
		grep {$_ ne $a} @{$V->{$_}};
	    }
	}
    }
    $self->{'O'}->msg($source, $mc, $data, { %$V, %$vars }, $mvars);
}

1;
