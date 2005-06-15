#!/usr/bin/perl -w

use strict;
use Test::Simple tests => 3;

use Net::PSYC qw(Event=Event);

my $c = 0;
my $f;

sub t {
    ok(1, 'Setting up timer-events with Event.pm.');
}

sub g {
    if ($c == 1) {
	ok(1, 'Setting up repeating timer-events.');
	remove($f);
	add(2, 't', \&stop_loop);
    }
    $c++;
}

add(0.5, 't', \&t);
$f = add(1, 't', \&g, 1);
print "!\tIf nothing happens for more than 5 seconds,\n!\tterminate the test and report the failure!\n";
start_loop();
ok( $c == 2, 'Removing timer-event.');

__END__
