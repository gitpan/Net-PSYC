package Net::PSYC::Event::IO_Select;

use vars qw($VERSION);
$VERSION = '0.1';

use Exporter;

use strict;
use IO::Select;
use vars qw(@ISA @EXPORT_OK);

@ISA = qw(Exporter);
@EXPORT_OK = qw(init can_read can_write has_exception add remove startLoop stopLoop revoke);

my (%S, %cb, $LOOP);

%cb = (
	'r' => {},
	'w' => {},
	'e' => {},
    );

sub can_read {
    $S{'r'}->can_read(@_);
}

sub can_write {
    $S{'w'}->can_write(@_);
}

sub has_exception {
    $S{'e'}->has_exception(@_);
}

#   add (\*fd, flags, cb, repeat)
sub add {
    my ($fd, $flags, $cb, $repeat) = @_;
    foreach (split(//, $flags || 'r')) {
	if ($_ eq 'r' or $_ eq 'w' or $_ eq 'e') {
	    $S{$_} = new IO::Select() unless $S{$_};
	    $S{$_}->add($fd);
	} else { next; }
	if ($cb) {
	    $cb{$_}->{scalar($fd)} = [ defined($repeat) ? $repeat : -1, $cb ];
	}
    }
}

sub revoke {
    my $name = scalar(shift);
    foreach ('w', 'e', 'r') {
	if (exists $cb{$_}->{$name} 
	and $cb{$_}->{$name}[0] == 0) {
	    $cb{$_}->{$name}[0] = 1;
	}
    }
    print STDERR "revoked ".$name."\n" if (Net::PSYC::DEBUG() > 1);
}

#   remove (\*fd[, flags] )
sub remove {
    print STDERR "removing ".scalar($_[0])."\n" if (Net::PSYC::DEBUG() > 1);
    foreach ('w', 'e', 'r') {
	if (exists $cb{$_}->{scalar($_[0])}) {
	    if (!$_[1] || $_[1] =~ /$_/) {
		delete $cb{$_}->{scalar($_[0])};
		$S{$_}->remove($_[0]);
	    }
	}
    }
}

sub startLoop {
    my (@E, $sock, $name);
    $LOOP = 1;
    while ($LOOP) {
	@E = IO::Select::select((pending('r')) ? $S{'r'} : undef, 
				(pending('w')) ? $S{'w'} : undef, 
				(pending('e')) ? $S{'e'} : undef, 1);
	
	foreach $sock (@{$E[0]}) { # read    
	    $name = scalar($sock);
	    
	    if (exists $cb{'r'}->{$name} # exists
	    and $cb{'r'}->{$name}[0] != 0) {	 # repeat or not	
		$cb{'r'}->{$name}[0] = 0 if ($cb{'r'}->{$name}[0] > 0);
		
		&{$cb{'r'}->{$name}[1]}($sock);
	    }
	}
	foreach $sock (@{$E[1]}) { # write
	    $name = scalar($sock);
	    
	    if (exists $cb{'w'}->{$name} # exists
	    and $cb{'w'}->{$name}[0] != 0) {	 # repeat or not
		$cb{'w'}->{$name}[0] = 0 if ($cb{'w'}->{$name}[0] > 0);
		&{$cb{'w'}->{$name}[1]}($sock);
	    }
	}
	foreach $sock (@{$E[2]}) { # error
	    $name = scalar($sock);

	    if (exists $cb{'e'}->{$name} # exists
	    and $cb{'e'}->{$name}[0] != 0) {	 # repeat or not
		$cb{'e'}->{$name}[0] = 0 if ($cb{'e'}->{$name}[0] > 0);
		&{$cb{'e'}->{$name}[1]}($sock);
	    }
	}
    }
    #   pending ( flag )
    sub pending {
	foreach (keys %{$cb{$_[0]}}) {
	    return 1 if ($cb{$_[0]}->{$_}[0] != 0);
	}
    }
}

sub stopLoop {
    $LOOP = 0;
}

1;
