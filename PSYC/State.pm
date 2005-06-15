package Net::PSYC::State;

use vars qw($VERSION);
$VERSION = '0.1';

# module implementing psyc-state-maintainance for objects...
#
# the state of mmp-vars is maintained by the connection
# object!
#
# a Tie::State would be nice.. which would react on such things as ^= in keys 
# to the hash. that would make vars _stateful without any crazy class inheritance
#
# hmm.. sexy sexy

#   sendmsg ( target, mc, data, vars[, source || mmp-vars ] )
sub sendmsg {
    my $self = shift;
    my $s = $self->{'psyc_o_state'};

    if (ref $_[4]) {
	$_[4]->{'_source'} ||= $self->{'unl'};
    } else {
	$_[4] ||= $self->{'unl'};
    }
    
    if (exists $s->{$_[0]}) {
	foreach (keys %{$s->{$_[0]}}) {
	    if (!exists $vars->{$_}) {
		$vars->{$_} = '';
	    } elsif ($vars->{$_} eq $s->{$_}) {
		delete $vars->{$_};
	    }
	}
    }

    &Net::PSYC::sendmsg; 
}

#   msg ( source, mc, data, vars )
sub msg {
    my $self = shift;
    my $s = $self->{'psyc_i_state'};

    my ($source, $vars) = ($_[0], $_[3]);

    if (exists $s->{$source}) {
	foreach (keys %{$s->{$source}}) {
	    $vars->{$_} = $s->{$source}->{$_} unless (exists $vars->{$_});
	}
    }
}

#	    ( source, key, value )
sub diminish {
    my $self = shift;
    my $s = $self->{'psyc_i_state'};

    my ($source, $key, $value) = @_;
    $s->{$source} = {} unless (exists $s->{$source});
    
    if (exists $s->{$source}->{$key}) {
	if (ref $s->{$source}->{$key} ne 'ARRAY') {
	    delete $s->{$source}->{$key} if ($s->{$source}->{$key} eq $value);
	} else {
	    @{$s->{$source}->{$key}} = grep { $_ ne $value } @{$s->{$source}->{$key}};
	}
    }
}

sub augment {
    my $self = shift;
    my $s = $self->{'psyc_i_state'};

    my ($source, $key, $value) = @_;
    $s->{$source} = {} unless (exists $s->{$source});
    unless (exists $s->{$source}->{$key}) {
	$s->{$source}->{$key} = [ $value ];
    } elsif (ref $s->{$source}->{$key} ne 'ARRAY') {
	$s->{$source}->{$key} = [ $s->{$source}->{$key}, $value ];
    } else {
	push(@{$s->{$source}->{$key}}, $value);
    }
}

sub assign {
    my $self = shift;
    my $s = $self->{'psyc_i_state'};

    my ($source, $key, $value) = @_;
    $s->{$source} = {} unless (exists $s->{$source});
    $s->{$source}->{$key} = $value;
}



1;
