#!/usr/bin/perl -w

use strict;
use Test::Simple tests => 2;

use Net::PSYC qw(:event :base make_psyc send_mmp setDEBUG);

setDEBUG(0);

register_uniform();
bind_uniform('psyc://:4405/');

my $o1 = Object1->new();
register_uniform('@o1', $o1);
my $o2 = Object2->new();
register_uniform('@o2', $o2);

sendmsg('psyc://localhost:4405/@o2', '_test', '', 
	{
	    '=_var'	=> "wuff",
	});
sendmsg('psyc://localhost:4405/@o2', '_test', '');
sendmsg('psyc://localhost:4405/@o2', '_test', '', 
	{
	    '_var'	=> "dwuff",
	});

sendmsg('psyc://localhost:4405/@o1', '_test', '', 
	{
	    '=_boo'	=> ["wuff", "duff"],
	});
sendmsg('psyc://localhost:4405/@o1', '_test', '', 
	{
	    '+_boo'	=> "muh",
	});
sendmsg('psyc://localhost:4405/@o1', '_test', '', 
	{
	    '-_boo'	=> "wuff",
	});


sub msg {
    my ($source, $mc, $data, $vars) = @_;
    stop_loop();
    return 1;
}

start_loop();

exit;

package Object1;
use Net::PSYC qw(:event :base make_psyc send_mmp setDEBUG);

sub new {
    my $class = shift;
    return bless {}, $class; 
}

sub msg {
    my $self = shift;
    my ($source, $mc, $data, $vars) = @_;

    if (scalar(@{$vars->{'_boo'}}) == 2 &&
	$vars->{'_boo'}->[0] eq "wuff" &&
	$vars->{'_boo'}->[1] eq "duff") {
	$self->{'c'}++;
    }
    if (scalar(@{$vars->{'_boo'}}) == 3 &&
	$vars->{'_boo'}->[0] eq "wuff" &&
	$vars->{'_boo'}->[2] eq "muh" &&
	$vars->{'_boo'}->[1] eq "duff") {
	$self->{'c'} += 2;
    }
    if (scalar(@{$vars->{'_boo'}}) == 2 &&
	$vars->{'_boo'}->[0] eq "duff" &&
	$vars->{'_boo'}->[1] eq "muh") {
	main::ok(1, "Augment and Diminish lists.");
	main::stop_loop();
    }
}

package Object2;
use Net::PSYC qw(:event :base make_psyc send_mmp setDEBUG);

sub new {
    my $class = shift;
    return bless {}, $class; 
}

sub msg {
    my $self = shift;
    my ($source, $mc, $data, $vars) = @_;
    if ($vars->{'_var'} eq 'wuff') {
	$self->{'c'}++;
    }
    main::ok(1,
       "Assigning variables.") if ($self->{'c'} == 2 && $vars->{'_var'} eq 'dwuff');
    
}
__END__
