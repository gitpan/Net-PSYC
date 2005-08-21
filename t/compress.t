#!/usr/bin/perl -w

use strict;

my $p_num = 0;
my $s_num = 0;


BEGIN {	
    unless (eval "require Compress::Zlib") {
	print "You need to install Compress::Zlib in order to use compression with Net::PSYC.\nSkipping all tests.\n";
	exit;
    }
    require Test::Simple;
    import Test::Simple qw(tests 8);
    require Net::PSYC;
    import Net::PSYC qw(:event :base make_psyc send_mmp get_connection setDEBUG refuse_modules :compress );
}

ok( register_uniform(), 'registering main::msg for all incoming packets' );
ok( my $c = bind_uniform('psyc://:4405/'), 'binding tcp port 4405' );
sendmsg('psyc://localhost:4405/', '_notice_test_tcp', 'Hey there! That is a message for testing [_thing].', {_thing=>'tcp'});
# STATE
foreach (1 .. 6) {
    sendmsg('psyc://localhost:4405/', '_notice_test_state', 'testing state', {}, {_wurst=>'YEAH!'});
}
sendmsg('psyc://localhost:4405/', '_notice_test_state', 'testing state', {}, {_wurst=>'miuh'});
sendmsg('psyc://localhost:4405/', '_notice_test_state', 'testing state');
sendmsg('psyc://localhost:4405/', '_notice_test_state', 'testing state', {}, {_wurst=>'YEAH!'});
# FRAGMENTS
my $data = make_psyc('_notice_test_fragments', "irgendwaslangesnichtsowichtig,nurnichtzukurz\n\n\rmitnewlinesdrin...\n", {_w=>'lolli'});
my $l = int((length($data)/5) + 1);
send_mmp('psyc://localhost:4405/', [unpack("a$l a$l a$l a$l a$l", $data)]);


ok( start_loop(), 'starting/stopping event loop' );
ok( $s_num == -1, 'MMP state' );

sub msg {
    my ($source, $mc, $data, $vars) = @_;
    $p_num++;
    if ($mc eq '_notice_test_tcp') {
	get_connection($source)->use_module('_compress');
	ok(1, 'sending/receiving psyc packets via tcp');
	ok( psyctext($data, $vars) eq 'Hey there! That is a message for testing tcp.', 'rendering psyc messages with psyctext()' );
    } elsif ($mc eq '_notice_test_state') {
	$s_num-= 2 if (!exists $vars->{'_wurst'});
	$s_num++ if (exists $vars->{'_wurst'} && $vars->{'_wurst'} eq 'YEAH!');
	$s_num-= 6 if (exists $vars->{'_wurst'} && $vars->{'_wurst'} eq 'miuh');
    } elsif ($mc eq '_notice_test_fragments') {
	ok( $data eq "irgendwaslangesnichtsowichtig,nurnichtzukurz\n\n\rmitnewlinesdrin...\n"
	    && $vars->{'_w'} eq 'lolli', 'sending fragments' );
	ok( get_connection($source)->{'_compress'} && (get_connection($source)->{'_compress'}->in_rate() + get_connection($source)->{'_compress'}->out_rate() != 2 ), "Compression (Rate: ".(get_connection($source)->{'_compress'}->in_rate()).")" );
	stop_loop();
    }
    return 1;
}

exit;

__END__
