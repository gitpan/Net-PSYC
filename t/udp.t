#!/usr/bin/perl -w

use strict;
use Test::Simple tests => 7;
# udp does not work yet.. fuck the system!

my $p_num = 0;
use Net::PSYC qw(:event :base setDEBUG);
ok( register_uniform(), 'registering main::msg for all incoming packets' );
ok( bind_uniform('psyc://:4405d/'), 'binding udp port 4405' );
ok( my $d = Net::PSYC::Datagram->new(), 'getting an random udp port');
ok( !$d->send('psyc://localhost:4405d/@test',
	     Net::PSYC::make_psyc('_notice_test_udp', 'Hey there! That is a message for testing [_thing].', { _thing => 'udp'})), 'sending a psyc packet via udp' );

ok( start_loop(), 'starting/stopping event loop' );


sub msg {
    my ($source, $mc, $data, $vars) = @_;
    $p_num++;
    if ($mc eq '_notice_test_udp') {
	ok(1, 'receiving psyc packet via udp');
	ok( psyctext($data, $vars) eq 'Hey there! That is a message for testing udp.', 'rendering psyc messages with psyctext()' );
	stop_loop();
    }
    
    return 1;
}

exit;
__END__
