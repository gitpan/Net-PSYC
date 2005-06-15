package Net::PSYC::Event::Event;

use vars qw($VERSION);
$VERSION = '0.1';

use Exporter;
use strict;
use Event qw(loop unloop);
use Net::PSYC qw(W);
use vars qw(@ISA @EXPORT_OK);

@ISA = qw(Exporter);
@EXPORT_OK = qw(init can_read can_write has_exception add remove start_loop stop_loop revoke);


my (%s, %revoke);

sub can_read {
    croak('can_read() is not yet implemented by Net::PSYC::Event::Event');
}

sub can_write {
    croak('can_write() is not yet implemented by Net::PSYC::Event::Event');
}

sub has_exception {
    croak('has_exception() is not yet implemented by Net::PSYC::Event::Event');
}

#   add (\*fd, flags, cb, repeat)
sub add {
    my ($fd, $flags, $cb, $repeat) = @_;
    if (!$flags || !$cb || !ref $cb eq 'CODE') {
	croak('Net::PSYC::Event::Event::add() requires flags and a callback!');
    }
#    print STDERR "Added ".scalar($fd)."\n";
    
    my $watcher;
    if ($flags eq 't') {
	$watcher = Event->timer( after => $fd,
				 repeat => defined($repeat) ? $repeat : 0,
				 cb => (!$repeat) 
		    ? sub { remove(scalar($watcher)); $cb->() } 
		    : $cb );	
	$s{'t'}->{scalar($watcher)} = $watcher;
	return scalar($watcher);
    } else {
	$watcher = Event->io( fd => $fd,
			      cb => $cb,
			      poll => $flags,
			      repeat => defined($repeat) ? $repeat : 1);
    }

    foreach ('r', 'w', 'e') {
	next if (!$flags =~ /$_/);
	$s{$_}->{scalar($fd)} = $watcher;
	$revoke{$_}->{scalar($fd)} = $watcher if (defined($repeat) && $repeat == 0);
    }
}
#   revoke( \*fd[, flags] )
sub revoke {
    my $name = scalar(shift);
    my $flags = shift;
    W("revoked $name",2);
    foreach ('r', 'w', 'e') {
	next if($flags && !$flags =~ /$_/);
	$s{$_}->{$name}->again() if(exists $s{$_}->{$name});
    }
}

#   remove ( \*fd[, flags] )
sub remove {
    my $name = scalar(shift);
    my $flags = shift;
    W("removing $name",2);
    foreach ('r', 'w', 'e', 't') {
	next if($flags && $flags !~ /$_/);
	next unless (exists $s{$_}->{$name});
	$s{$_}->{$name}->cancel();
	delete $s{$_}->{$name};
	delete $revoke{$_}->{$name};
    }
}

sub start_loop {
    loop();
}

sub stop_loop {
    unloop();
}


1;
