#!/usr/bin/perl -w

use strict;
use Test::Simple tests => 11;
# udp does not work yet.. fuck the system!

my $p_num = 0;
use Net::PSYC qw(Event=IO::Select startLoop stopLoop psyctext registerPSYC); 

ok( registerPSYC(), 'registering main::msg for all incoming packets' );
ok( bindPSYC('psyc://:4405d/'), 'binding udp port 4405' );
ok( bindPSYC('psyc://:4405c/'), 'binding tcp port 4405' );
ok( my $d = Net::PSYC::Datagram->new(), 'getting an random udp port');
ok( $d->send('psyc://localhost:4405d/@test',
	     Net::PSYC::makePSYC('_notice_test_udp', 'Hey there! That is a message for testing [_thing].', { _thing => 'udp'})), 
#ok( sendMSG('psyc://localhost:4405d/@test','_notice_test_udp', 'Hey there! That is a message for testing [_thing].', { _thing => 'udp'}),
    'sending a psyc packet via udp' );

ok( sendMSG('psyc://localhost:4405c/@test', '_notice_test_tcp', 'Hey there! That is a message for testing [_thing].', { _thing => 'tcp' }), 'sending a psyc packet via tcp' );
ok( startLoop(), 'starting/stopping event loop' );


sub msg {
    my ($source, $mc, $data, $vars) = @_;
    $p_num++;
    if ($mc eq '_notice_test_udp') {
	ok( psyctext($data, $vars) eq 'Hey there! That is a message for testing udp.', 'rendering psyc messages with psyctext()' );
	ok(1, 'receiving psyc packet via udp');
    } elsif ($mc eq '_notice_test_tcp') {
	ok( psyctext($data, $vars) eq 'Hey there! That is a message for testing tcp.', 'rendering psyc messages with psyctext()' );
	ok(1, 'receiving psyc packet via tcp');
    }
    
    if ($p_num == 4) {
	stopLoop();
    }
    return 1;
}

exit;
__END__
