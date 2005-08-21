package Net::PSYC::Client;

$VERSION = '0.2';
use vars qw($VERSION);
#
# implements some basic client functionality...
# 
# your perl-script (main::) needs to have following subs
# - getPassword()
# 
use Exporter;
use Net::PSYC qw(same_host parse_uniform make_uniform psyctext W register_route
		);
use Net::PSYC::Event qw(register_uniform unregister_uniform);
use Net::PSYC::Tie::AbbrevHash;
use Carp;


@ISA = qw(Exporter);
@EXPORT = qw(register_context unregister_context register_new msg psycLink psycUnlink sendmsg UNI NICK enter talk);

my ($new, %ConextReg, $UNI, $NICK, %react, $SERVER_UNI, $SERVER_HOST, %tags);
our (%friends);
sub UNI () { $UNI }

# we like the idea how this "sub" gets inlined, that's why it looks so weird
sub NICK () { $NICK || $UNI? ($NICK = substr((parse_uniform($UNI))[4], 1)) : '' }

#   register_context ( uni, obj )
sub register_context {
    unless (ref $_[1]) {
	delete $ContextReg{$_[0]};
	W("register_context: $_[0]");
	return;
    }
    W("register_context: $_[0], $_[1]");
    
    $ContextReg{$_[0]} = $_[1];
    return;
}

#   unregister_context ( uni )
sub unregister_context {
    delete $ContextReg{$_[0]};
}

sub register_new {
    $new = shift;
}

sub getContext {
    my $vars = shift;
    my ($addr ,$obj, $u);
    unless (ref $vars eq 'HASH') {
	$addr = $vars;
	$vars = {};
    } else {
	$addr = $vars->{'_context'} || $vars->{'_source'};
    }

    $obj = $ContextReg{$addr};
    return $obj if ($obj);
    if ($addr && ($u = parse_uniform($addr)) && $u) {
	W("$addr does not have a path. Assuming it to be a person.", 0)
	    if (!$u->{'object'});
	if ($u->{'object'} !~ /^\@/ && $new) { 
	    my $name;
	    if (same_host($u->{'host'}, $SERVER_HOST)) {
		$name = substr($u->{'object'}, 1);
	    } else {
		$name = $addr;
		register_route($addr, $vars->{'_INTERNAL_origin'})
		    if (exists $vars->{'_INTERNAL_origin'});
	    }
	    $obj = &{$new}( $addr, $name, $silent );
	    register_context($addr, $obj);
	}
    } else {
	W("$addr does not seem to be a valid UNL. Dumping message.", 0);	
	return 0;
    }
    return $obj;
}

# internal
sub verify_enter {
    my $vars = shift;
    my ($addr ,$obj, $u);
    
    $addr = $vars->{'_context'} || $vars->{'_source'};
    
    return 1 if (exists $ContextReg{$addr});
    
    unless (defined delete $tags{$vars->{'_tag'}}
	    || Net::PSYC::get_connection(UNI()) eq $vars->{'_INTERNAL_origin'}) {
	W("$addr is trying to force us in.. revolt! (_tag is wrong)", 0);
	return 0;
    }
    $u = parse_uniform($addr); 
    
    if (ref $u && $u->{'object'} =~ /^\@/ && $new) { 
	my $silent = (exists $vars->{'_control'} 
		      && $vars->{'_control'} eq '_silent') ? 1 : 0;
	my $name;
	if (same_host($u->{'host'}, $SERVER_HOST)) {
	    $name = substr($u->{'object'}, 1);
	} else {
	    $name = $addr;   
	}
	$obj = &{$new}( $addr, $name, $silent );
	register_context($addr, $obj);
	return 1;
    }
    return 0;
}

sub getUni {
    my $obj = shift;
    return unless(ref $obj);
    foreach(keys %ContextReg) {
	if($ContextReg{$_} == $obj) {
	    return $_;
	}
    }
    return 0;
}

# incoming messages
#   msg ( source, mc, data, vars)
sub msg {
    my ($source, $mc, $data, $vars) = @_;
    unless ($mc) {
	return 1;
    }
    W("Client->msg('$source', '$mc', '$data', $vars)");
    my $func = $react{$mc};
    if ($func) {
	&{$func}($source, $mc, $data, $vars);
    } else {
	my $c = getContext($vars);
	# we expect msg to do the right thing
	unless (ref $c) {
	    # this is a message from a room we never entered
	    # we may think about sending _request_place_leave
	    return 1;    
	}
	$c->msg($source, $mc, $data, $vars) if $c;
    }

    return 1;
}

sub sendmsg {
    my ($target, $mc, $data, $vars, $MMPvars) = @_;
    W("Client->sendmsg('$target', '$mc', '$data', $vars)");
    $MMPvars ||= {};
    $MMPvars->{'_identification'} ||= UNI();
    Net::PSYC::sendmsg($target, $mc, $data, $vars, $MMPvars);
}

#   link to a given uni
sub psycLink {
    $UNI = shift;
    my $u = parse_uniform($UNI);
    unless ($u) {
	return W("I cannot link to that uni: $UNI (It is not valid)",0);
    }
#    register_uniform($UNI);
    register_uniform(); # this is no good
    $SERVER_HOST = $u->{'host'};
    $SERVER_UNI = make_uniform($u->{'user'}, $u->{'host'}, $u->{'port'}, 
			  $u->{'transport'}, ''); 
    Net::PSYC::sendmsg($UNI, '_request_link', '',
		       { _password => main::getPassword(),
#_nick => nick()
		       });
    # we need to do that raw.. since we want no _identification	== UNI
}

sub psycUnlink {
    unregister_uniform(UNI());
    sendmsg(UNI(), '_request_exit');
    # we need to do that raw.. since we want no _source	== UNI
}

sub enter {
    my $target = shift;
    my $vars = {};
    unless (parse_uniform($target)) {
	$target =~ s/^[@|#]//o;
	$target = $SERVER_UNI."/\@$target";
    }
    $vars->{'_tag'} = unpack( "H*",pack("F", rand(10)));
    $tags{$vars->{'_tag'}} = $target;
    $vars->{'_nick'} = NICK();
    sendmsg($target, '_request_enter', '', $vars);	
}

sub talk {
    my $target = shift;
    unless (parse_uniform($target)) {
	$target = $SERVER_UNI."/\~$target";
    }
    sendmsg($target, '_message_private', join(' ', @_), {_nick=>NICK()});
}


tie %react, 'Net::PSYC::Tie::AbbrevHash';
%react = (
'_echo_place_leave'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($vars->{'_context'});
    return unless ($obj);
    unless ($obj->{'type'} eq 'place') {
	return W("Got suspicious _echo_place_leave from $source.", 0);
    }
    $obj->msg(@_);
    $obj->leanforwardandchokeyourself();
},
'_echo_set'		=> sub {
    my ($source, $mc, $data, $vars) = @_;
    if ($vars->{'_key'} eq 'name' && exists $vars->{'_value'}) {
	$NICK = $vars->{'_value'};
    }
    my $c = getContext($vars);
    return unless ($c);
    # we expect msg to do the right thing
    $c->msg($source, $mc, $data, $vars) if $c;
},
'_message_echo_private'	=> sub {
    my ($source, $mc, $data, $vars) = @_;

    my $obj = getContext($vars->{'_source_relay'} || $source);
    return unless ($obj);

    $obj->msg(@_);
},
'_notice_place_leave'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($vars);
    return unless ($obj);
    $obj->msg(@_);
    $obj->leave( $vars->{'_nick'} || $source );
},
'_echo_place_enter'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    unless (verify_enter($vars)) {
	return;
    }
    my $obj = getContext($vars);;
    return unless ($obj);
    $obj->enter( $vars->{'_nick'} || $source, UNI());
    $obj->msg(@_);
},
'_notice_place_enter'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    unless (verify_enter($vars)) {
	return;
    }
    my $obj = getContext($vars);;
    return unless ($obj);
    $obj->enter( $vars->{'_nick'} || $source, $source );
    $obj->msg(@_);
},
'_query_password'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    sendmsg(UNI(), '_set_password', '', {_password=> main::getPassword() });
},
'_status_place_members'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($source);
    return unless ($obj);
    
    if ($obj->can('members')) {
	my $members = {}; # name -> uni
	for (0 .. @{$vars->{'_list_members_nicks'}} - 1) {
	    $members->{$vars->{'_list_members_nicks'}->[$_]} = $vars->{'_list_members'}->[$_];
	}
	$obj->members($members);
    }
    $obj->msg(@_);
},
'_notice_link'		=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my @user = parse_uniform($source);
    my @uni = parse_uniform(UNI());
    if(same_host($user[1], $uni[1]) && lc($user[4]) eq lc($uni[4])) {
	$UNI = $source;
	if (exists $vars->{'_nick'}) {
	    $NICK = $vars->{'_nick'};
	}
	Net::PSYC::get_connection($UNI)->TRUST(6);
    } else {
	W("We received a _notice_link from an uni we did not try to link to.".
	  "(uni: ".UNI().", source: $source)", 0);
    }
},
'_notice_link_removed' => sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($source);
    return unless ($obj);

    $obj->msg(@_);
    # time to exit the client.
},
# könnte man auch rausnehmen
'_status'		=> sub {
    my $c = getContext(UNI());
    return unless ($c);
    $c->msg(@_) if $c;
},
'_error'		=> sub {
    my $c = getContext(UNI());
    return unless ($c);
    $c->msg(@_) if $c;
},
'_list_friends_present'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($source);
    return unless ($obj);

    my $friends = {}; # name -> uni
    for (0 .. @{$vars->{'_list_friends_nicknames'}} - 1) {
	$friends->{$vars->{'_list_friends_nicknames'}->[$_]} = $vars->{'_list_friends'}->[$_];
    }

    if ($obj->can('friends')) {
	$obj->friends($friends);
    } else {
	%friends = %$friends;
    }
    
    $obj->msg(@_);
},
);


1;

__END__

=pod

=head1 NAME

Net::PSYC::Client 

=head1 DESCRIPTION

Net::PSYC::Client offers an easy-to-implement interface to build chat clients using the PSYC protocol.

=head1 SYNOPSIS

    use Net::PSYC::Client;
    
=head1 PERL API

=over 4

=item psycLink( B<$identity> )

Tries to link to (login to) the given B<$identity>. A password, if necessary, has to be returned by main::getPassword().

=item psycUnlink()

Performs a log-out of the PSYC server.

=item register_new( B<$sub> )

B<$sub> is called each time a new object has to be created. Normally this occurs when the user joins a room or receives a private message. &{B<$sub>}( uni, name[, silent]) has to return an object of a class implementing the interface specified below. The silent flag is 1 if the room does not allow talking. You may refrain from allowing input in that case and, when in a windowing environment, refrain from opening an extra window and rather direct messages to the console.

=item enter( B<$room> )

Sends a request for entrance to the given room. B<$room> may be the full UNI or just the name of the room in which case it is assumed to be on the server the user is linked to.

=item talk( B<$person>, B<@text> )

Sends a private message to the given person. B<$person> may be a UNI or just a local nickname.

=item sendmsg( B<$target>, B<$mc>, [B<$data>[, B<$vars>[, B<$MMPvars>]]] )

For a description of sendmsg() have a look at L<Net::PSYC>. Use this sendmsg instead of the one from L<Net::PSYC> in case you are sending messages _as_ the user you are linked to. Basically it just assigns the _identification variable for you.

=item register_context( B<$uni>, B<$obj> )

Register an object to receive all conference messages from the given UNI. Depending on whether UNI represents a person or a chatroom the object has to implement the appropriate interface:

=back

=head1 CLIENT INTERFACE

In order to make it easy to implement chat-clients based on the PSYC protocol there are only a few requirements to be met by the actual user interface.

=head2 Default functions (both Person and Chatoom conference)

=over 4

=item B<$obj>-E<gt>msg( B<$source>, B<$mc>, B<$data>, B<$vars> )

Every message that's worth printing is delivered to the msg() method. You could implement different templates for every method (B<$mc>) though this basic implementation should be enough for simple applications.
 
    sub msg {
	my ($source, $mc, $data, $vars) = @_;
	print Net::PSYC::psyctext($data, $vars);
	return 1;
    }

=item B<$obj>-E<gt>leanforwardandchokeyourself()

When the user himself has left a room B<$obj>-E<gt>leanforwardandchokeyourself() is called to tell the object that it is no longer needed. 
Keep the user from sending any more messages to that room and close the window.
The name of this callback method may change one day. Suggest something.

=item B<$obj>-E<gt>{'type'}

would be 'person' or 'place'.

=back
 
=head2 Chatroom

In addition to I<msg> every object representing a chatroom has to have the following methods

=over 4

=item B<$room>-E<gt>members( B<\%members> )

B<\%members> is a reference to a hash containing nicknames and psyc addresses of all users currently in the room represented by B<$room>. The structure of the hash is { nickname =E<gt> psyc address }. 

=item B<$room>-E<gt>enter( B<$nick>, B<$uni>)

enter() is called whenever someone enters B<$room>.

=item B<$leave>-E<gt>leave( B<$nick> )

leave() is called whenever someone leaves B<$room>. 

=item B<$room>-E<gt>topic( B<$topic>, B<$nick> )

Whenever the topic in this chatroom is changed this method is called with the new B<$topic> and the B<$nick> who changed it, if available.

=back 
 
=head1 SEE ALSO

L<Net::PSYC>, L<Net::PSYC::Event>, L<http://psyc.pages.de/>, L<http://perlpsyc.pages.de> for a bunch of scripts and a client (psycion) using L<Net::PSYC> 

=head1 AUTHORS

Arne GE<ouml>deke <el@goodadvice.pages.de>

=head1 COPYRIGHT

Copyright (c) 2004-2005 Arne GE<ouml>deke. All rights reserved.
This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
