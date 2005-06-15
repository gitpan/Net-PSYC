package Net::PSYC::Event::IO_Select;

use vars qw($VERSION);
$VERSION = '0.3';

use Exporter;

use strict;
use IO::Select;
use Net::PSYC qw(W);
use vars qw(@ISA @EXPORT_OK);

@ISA = qw(Exporter);
@EXPORT_OK = qw(init can_read can_write has_exception add remove start_loop stop_loop revoke);

my (%S, %cb, $LOOP, @T);

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
    unless ($cb && ref $cb eq 'CODE') {
	W("You need a proper callback for add()! (has to be a code-ref)",0);    
	return;
    }
    foreach (split(//, $flags || 'r')) {
	if ($_ eq 'r' or $_ eq 'w' or $_ eq 'e') {
	    $S{$_} = new IO::Select() unless $S{$_};
	    $S{$_}->add($fd);
	} elsif ($_ eq 't') {
	    my $i = 0;
	    my $t = time() + $fd;
	    while (exists $T[$i] && $T[$i]->[0] <= $t) {
		$i++;
	    }
	    splice(@T, $i, 0, [$t, $cb, $repeat||0, $fd]);
	    return scalar($cb).$fd;
	} else { next; }
	$cb{$_}->{scalar($fd)} = [ defined($repeat) ? $repeat : -1, $cb ];
    }
}

sub revoke {
    my $name = scalar(shift);
    foreach ('w', 'e', 'r') {
	if (exists $cb{$_}->{$name} and $cb{$_}->{$name}[0] == 0) {
	    $cb{$_}->{$name}[0] = 1;
	    W("revoked $name", 2);
	}
    }
}

#   remove (\*fd[, flags] )
sub remove {
    W("removing ".scalar($_[0]));
    if (!ref $_[0]) {
	my $i = 0;
	foreach (@T) {
	    if (scalar($T[$i]->[1]).$T[0]->[3] eq $_[0]) {
		splice(@T, $i, 1);
		return 1;
	    }
	    $i++;
	}
    }
    foreach ('w', 'e', 'r') {
	if (exists $cb{$_}->{scalar($_[0])}) {
	    if (!$_[1] || $_[1] =~ /$_/) {
		delete $cb{$_}->{scalar($_[0])};
		$S{$_}->remove($_[0]);
	    }
	}
    }
}

sub start_loop {
    my (@E, $sock, $name);
    $LOOP = 1;
    my $time = undef;
    while ($LOOP) {
	if (scalar(@T)) {
	    $time = $T[0]->[0] - time();
	    $time = 0 if ($time < 0);
	} else { $time = undef; }

	@E = IO::Select::select((pending('r')) ? $S{'r'} : undef, 
				(pending('w')) ? $S{'w'} : undef, 
				(pending('e')) ? $S{'e'} : undef, $time);

	while (scalar(@T) && $T[0]->[0] <= time()) {
	    if ($T[0]->[2]) { # repeat!
		add($T[0]->[3], 't', $T[0]->[1], 1);
	    }
	    $T[0]->[1]->();
	    shift @T;
	}
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
    return 1;
}

sub stop_loop {
    $LOOP = 0;
    return 1;
}

1;
