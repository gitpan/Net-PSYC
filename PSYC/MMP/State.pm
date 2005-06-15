package Net::PSYC::MMP::State;

use Storable qw(dclone);

sub new {
    my $class = shift;
    my $obj = shift;
    my $self = {
	'state' => {},
	'vars' => {},
	'temp_state' => {},
	'connection' => $obj,
    };
    return bless $self, $class;
}

sub init { 
    my $self = shift;
    $self->{'connection'}->hook('send', $self);
    $self->{'connection'}->hook('sent', $self);
    $self->{'connection'}->hook('receive', $self);
    return 1;
}

sub send {
    my $self = shift;
    my ($vars, $data) = @_;
#    use Data::Dumper;
#    print STDERR Dumper(@_);
    # the current behaviour is to _set every var that
    # has not changed in 3 packages..
    my $state = $self->{'state'};
    my $temp_state = {};
    my $newvars = {};

    # to bypass automatic state.. use ':'
    foreach (keys %$vars) {

	next if (/^:_/);
	if (/^=_/) {
	    $newvars->{$_} = $vars->{$_};
	    $temp_state->{substr($_, 1)} = [0, $vars->{$_}];
	    next;
	}
	if (/^\+_/) {
	    my $key = substr($_, 1);
	    $newvars->{$_} = $vars->{$_};
	    if (exists $state->{$key}) {
		unless (ref $state->{$key}->[1] eq 'ARRAY') {
		    $temp_state->{$key}->[1] = [ $state->{$key}->[1] ];
		}
		push(@{$temp_state->{$key}->[1]}, $vars->{$_});
	    } else {
		$temp_state->{$key}->[1] = [ $vars->{$_} ];
	    }
	    $temp_state->{$key}->[0] = 0; # we assume it to be consistent
	    next;
	}
	if (/^-_/) {
	    my $key = substr($_, 1);
	    $newvars->{$_} = $vars->{$_};
	    if (exists $state->{$key}) {
		if (ref $state->{$key}->[1] eq 'ARRAY') {
		    $temp_state->{$key}->[1] = grep { $_ eq $vars->{$_} } 
						    @{$state->{$key}->[1]}; 
		} else {
		    if ($state->{$key}->[1] eq $vars->{$_}) {
			$temp_state->{$key}->[0] = -1;	
		    }
		}
	    } else {
		# WOU?
	    }
	    $temp_state->{$key}->[0] = 0; # we assume it to be consistent
	    next;
	}
	
	if (!exists $state->{$_}) {
	    $temp_state->{$_} = [1, $vars->{$_}];
	    $newvars->{$_} = $vars->{$_};
	    next;
	}
	if ($state->{$_}->[1] ne $vars->{$_}) { # var has changed
	    if ($state->{$_}->[0] == 3) { # unset var
		$temp_state->{$_} = [1, $vars->{$_}];
		$newvars->{"=$_"} = '';
	    } elsif ($state->{$_}->[0] > 1) { # decrease counter
		$temp_state->{$_} = [ $state->{$_}->[0] - 1, $state->{$_}->[1]];
	    } elsif ($state->{$_}->[0] != 0) { # nothing set.. 
		$temp_state->{$_} = [1, $vars->{$_}];
	    }
	    $newvars->{$_} = $vars->{$_};
	    next;
	}
	if ($state->{$_}->[1] eq $vars->{$_}) {
	    if ($state->{$_}->[0] == 10 || $state->{$_}->[0] == 0) { 
		# is set anyway
		next;
	    } elsif ($state->{$_}->[0] == 2) {
		$newvars->{"=$_"} = $vars->{$_};
	    } elsif ($state->{$_}->[0] < 2) {
		$newvars->{$_} = $vars->{$_};
	    }
	    $temp_state->{$_} = [$state->{$_}->[0] + 1, $state->{$_}->[1]];
	}
    }

    foreach (keys %$state) {
	next if (exists $newvars->{$_});
	
	if ($state->{$_}->[0] == 3) { # unset var
	    $newvars->{"=$_"} = '';
	    $temp_state->{$_} = [ 2, $state->{$_}->[1]];
	    next;
    	}
	$temp_state->{$_} = [ $state->{$_}->[0] - 1, $state->{$_}->[1]]
	    if ($state->{$_}->[0] != 0);
	$newvars->{$_} = '' if ($state->{$_}->[0] > 3 || $state->{$_}->[0] == 0);
    }
    
    $self->{'temp_state'} = $temp_state;
    %$vars = %$newvars; 
    return 1;
}

sub sent {
    my $self = shift;
    my ($vars, $data) = @_;
    
    foreach (keys %{$self->{'temp_state'}}) {
	if ($self->{'temp_state'}->{$_}->[0] == -1) {
	    delete $self->{'state'}->{$_};
	    next;
	}
	$self->{'state'}->{$_} = $self->{'temp_state'}->{$_};
    }
    return 1;
}

sub receive {
    my $self = shift;
    my ($vars, $data) = @_;
    
    foreach (keys %{$self->{'vars'}}) {
	unless (exists $vars->{$_}) {
#	    print "used assigned var $_ ($self->{'vars'}->{$_})!\n";
	    $vars->{$_} = $self->{'vars'}->{$_};
	}
    }

    foreach (keys %$vars) {
	if (/^_/) {
	    delete $vars->{$_} if ($vars->{$_} eq '');
	    next;
	}
	my $key = substr($_, 1);
	if (/^=_/) {
#	    print "assigned $key!\n";
	    if ($vars->{$_} eq '') {
		delete $self->{'vars'}->{$key};
		delete $vars->{$_};
		next;
	    }
	    $self->{'vars'}->{$key} = (ref $vars->{$_}) 
		? dclone($vars->{$_}) : $vars->{$_};

	    $vars->{$key} = delete $vars->{$_};
	    next;
	}
	if (/^\+_/) {
	    if (!exists $self->{'vars'}->{$key}) {
		$self->{'vars'}->{$key} = [ delete $vars->{$_} ];
		next;
	    }
	    if (ref $self->{'vars'}->{$key} eq 'ARRAY') {
		push(@{$self->{'vars'}->{$key}}, $vars->{$_});
	    } else {
		$self->{'vars'}->{$key} = [ $self->{'vars'}->{$key},
					  $vars->{$_} ];
	    }
	    delete $vars->{$_};
	    next;
	}
	if (/^-_/) {
	    if (!exists $self->{'vars'}->{$key}) {

	    } elsif (!ref $self->{'vars'}->{$key}) {
		delete $self->{'vars'}->{$key} 
		    if ($self->{'vars'}->{$key} eq $vars->{$_});
	    } elsif (ref $self->{'vars'}->{$key} eq 'ARRAY') {
		my $value = $vars->{$key};
		@{$self->{'vars'}->{$key}} = 
		    grep {$_ ne $value } @{$self->{'vars'}->{$key}};
	    }
	    delete $vars->{$_};
	    next;
	}
    }
    return 1;
}

1;
