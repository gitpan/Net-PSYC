package Net::PSYC::Client;
#
# implements some basic client functionality...
# 
# your perl-script (main::) needs to have following subs
# - getPassword()
# 
use Exporter;
use Net::PSYC qw(same_host);
use Net::PSYC::Event qw(registerPSYC unregisterPSYC);
use Net::PSYC::Tie::AbbrevHash;
use Carp;

use Data::Dumper;

@ISA = qw(Exporter);
@EXPORT = qw(register_context unregister_context register_new register_main msg psycLink psycUnlink sendMSG UNI NICK);

my ($new, %ConextReg, $main, $UNI, %react, $SERVER_UNI);


sub UNI { $UNI }
sub NICK { ($UNI) ? substr((parseUNL($UNI))[4], 1) : '' }

#   register_context ( uni, obj )
sub register_context {
    print "register_context: $_[0], $_[1]\n" if Net::PSYC::DEBUG;
    $ContextReg{$_[0]} = $_[1];
}

#   unregister_context ( uni )
sub unregister_context {
    delete $ContextReg{$_[0]};
}

sub register_new {
    $new = shift;
}

sub register_main {
    $main = shift;
}

sub getContext {
    my $uni = shift;
    return $main if ($uni eq $UNI);
    my $obj;
    if ($uni && parseUNL($uni)) {
	$obj = $ContextReg{$uni};
        unless ($obj) {
	    my $name = substr((parseUNL($uni))[4], 1);
            if ($uni =~ /\@|\~/ && $new) { # room
                $obj = &{$new}( $uni, $name );
                register_context($uni, $obj);
            } else {
                $obj = $main;
            }
        }
    } else {
        $obj = $main;
    }
    return $obj;
}

sub getUni {
    my $obj = shift;
    return unless(ref $obj);
    if($obj == $main) { return 0; }
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
    print STDERR "Net::PSYC::Client->msg('$source', '$mc', '$data', $vars)\n" if Net::PSYC::DEBUG;
    my $func = $react{$mc};
    if ($func) {
	&{$func}($source, $mc, $data, $vars);
    } elsif ($main && $main->can('msg')) {
	$main->msg($source, $mc, $data, $vars);
    } else {
	print $mc."\n\n";
    }

    return 1;
}

#sub sendMSG {
#    my ($target, $mc, $data, $vars, $MMPvars) = @_;
#    if ((!$vars || !exists $vars->{'_source'}) && (!$MMPvars || !exists $MMPvars->{'_source'})) {
#	$vars->{'_source'} = $UNI;
#    }
#    Net::PSYC::sendMSG($target, $mc, $data, $vars, $MMPvars);
#}

#   link to a given uni
sub psycLink {
    $UNI = shift;
    my ($u, $h, $p, $t, $o) = parseUNL($UNI);
    registerPSYC($UNI);
    $SERVER_UNI = $t ? "psyc://$h" . ($p ? ":$p" : "") . "$t" : 
			"psyc://$h" . ($p ? ":$p" : "");
    Net::PSYC::sendMSG($UNI, '_request_link', '', {_password=>main::getPassword()});
    # we need to do that raw.. since we want no _source	== UNI
}

sub psycUnlink {
    unregisterPSYC($UNI);
    Net::PSYC::sendMSG($UNI, '_request_exit');
    # we need to do that raw.. since we want no _source	== UNI
}

sub query {
    my ($I, $target, $text, $action) = @_;
    print "Net::PSYC::Client::query\n";
    print Dumper(\@_);
    if(!ref $target && parseUNL($target)) {
	$target = getContext($target)
    } elsif(my $uni = getUni($target) && $text) {
	sendMSG($target->{UNI},'_message_private', $text, $action ?
					{ _action=>$action } : { });
    } elsif(!$text && !ref $target) {
	print "i am at the right place $SERVER_UNI" . '/~' . "$target\n";
	getContext($SERVER_UNI . '/~' . $target);
    } else {
	sendMSG(getUni($target),'_message_private', $text, $action ?
	                                       { _action=>$action } : { });
    }

}

sub say {
    my ($target, $text, $action) = @_;
    my $vars = { _nick=>UNL() };
    $vars->{'_action'} = $action if ($action);
    if(parseUNL($target)) {
	$vars->{'_nick_place'} = substr((parseUNL($target))[4], 1);
	sendMSG($target, '_message_public', $text, $vars ); 
    } else {
	$vars->{'_nick_place'} = $target;
	sendMSG($SERVER_UNI.'/@'.$target, '_message_public', $text, $vars );

	$obj->notice("Could not send the message.");
    }
}

sub join {
    my $chan = shift;
    if(parseUNL($chan)) {
	sendMSG($chan, '_request_enter', '', {_nick=> NICK()} );
    } else {
	$chan =~ s/^[@|#]//o;
	sendMSG($SERVER_UNI."/\@$chan", '_request_enter', '', {_nick=>NICK()} );
    }
}

sub part {
    my ($I, $obj, $chan) = @_;
    if(parseUNL($chan)) {
	sendMSG($chan, '_request_leave', '', { _nick=>NICK(),
					    _nick_place=>$chan});
    } elsif($chan) {
	$chan =~ s/^[@|#]//o;
	sendMSG($SERVER_UNI . "/@" . $chan, '_request_leave', '', 
				{ _nick=>NICK(),
				_nick_place=>$chan });
    } elsif(my $uni = getUni($obj)) {
	sendMSG($uni, '_request_leave', '', { _nick=>NICK(),
					    _nick_place=>$uni });

    }
}

tie %react, 'Net::PSYC::Tie::AbbrevHash';
%react = (
'_message_private'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($source);
    $obj->message($vars->{'_nick'} || $source, $data, $vars->{'_action'});
},
'_message_public'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    
    if ($vars->{'_time_place'}) {
	my $obj = getContext($source);
	return unless($obj->can('history'));
	#     history(time, data)
	$obj->history($vars->{'_time_place'}, $data);
    } else { # history
	my $obj = getContext($vars->{'_context'});
	$obj->message($vars->{'_nick'} || $source, $data, $vars->{'_action'});
    }
},
'_message_echo'	=> sub {
    my ($source, $mc, $data, $vars) = @_;

    my $obj = getContext($vars->{'_context'} || $source);
    $obj->echo($data);
},
'_notice_place_leave'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($vars->{'_context'} || $source);
    $obj->part( $vars->{'_nick'} || $source );
},
'_notice_place_enter'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($vars->{'_context'} || $source);
    $obj->join( $vars->{'_nick'} || $source, $source );
},
'_echo_place_enter_automatic_subscription' => sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($vars->{'_context'} || $source);
    $obj->join( $vars->{'_nick'} || $source, $source );
},
'_query_password'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    sendMSG($UNI, '_set_password', '', {_password=> main::getPassword() });
},
'_status_place_members'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($source);
    
    my $members = {}; # name -> uni
    for (0 .. @{$vars->{'_list_members_nicks'}} - 1) {
	$members->{$vars->{'_list_members_nicks'}->[$_]} = $vars->{'_list_members'}->[$_];
    }
    
    $obj->Members($members);
    $obj->notice(psyctext($data, $vars));
},
'_status_place_topic'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($source);
    $obj->topic($vars->{'_topic'}, $vars->{'_nick'});
},
'_notice_link'		=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my @user = parseUNL($source);
    my @uni = parseUNL($UNI);
    if(same_host($user[1], $uni[1]) && lc($user[4]) eq lc($uni[4])) {
	$UNI = $source;
    } else {
	croak "Something went REALLY wrong! Please check your UNI.\n";
    }
    registerPSYC($UNI);
    my $obj = getContext($source);
    
},
'_notice_link_removed_exit' => sub {
    my ($source, $mc, $data, $vars) = @_;
    $main->notice(psyctext($data, $vars));
    exit();
},
'_notice_circuit_established' => sub {
    my ($source, $mc, $data, $vars) = @_;
    $SERVER_UNI = $source;
},
'_notice'		=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($source);
    $obj->notice(psyctext($data, $vars));
},
'_info'			=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($source);
    $obj->notice(psyctext($data, $vars));
},
# könnte man auch rausnehmen
'_info_nickname'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($source);
    $obj->notice(psyctext($data, $vars));
},
'_status'		=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($source);
    $obj->notice(psyctext($data, $vars));
},
'_list_friends_present'	=> sub {
    my ($source, $mc, $data, $vars) = @_;
    my $obj = getContext($source);
    if ($obj->can('friends')) {
	my $friends = {}; # name -> uni
	for (0 .. @{$vars->{'_list_friends_nicknames'}} - 1) {
	    $friends->{$vars->{'_list_friends_nicknames'}->[$_]} = $vars->{'_list_friends'}->[$_];
	}
	$obj->friends($friends);
    } else {
	$obj->notice(psyctext($data, $vars));
    }
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

=item psycLink( B<$uni> )

Tries to link to (login to) the given B<$unl>. A password if necessary has to be returned by main::getPassword().

=item psycUnlink()

Performs a log-out of the PSYC server.

=item register_new( B<$sub> )

Vielleicht register_person( B<$class> ) und register_room( B<$class> ) ...

=item register_context( B<$uni>, B<$obj> )

Register an object to get all conference with the given UNI. Depending on whether UNI represents a person or a chatroom the object has to implement different interfaces:

=back

=head1 CLIENT INTERFACE

In order to make it easy to implement chat-clients based on the PSYC protocol there are only a few requirements to be met by the actual user interface.

=head2 Default functions (both Person and Chatoom conference)

=over 4

=item B<$obj>-E<gt>notice( B<$text> )

Different notices and status information that simply needs to be printed to the user. 

=back
 
=head2 Chatroom

In addition to I<notice> every object representing a chatroom has to have the following methods

=over 4

=item B<$room>-E<gt>message( B<$nick>, B<$text>, B<$speakaction> )

A public message from B<$nick> in the current chatroom. If B<$text> is an empty string the message is just an action. (For instance I<Jimmy likes blueberry muffins.> would be I<$room-E<gt>message("Jimmy", "", "likes blueberry muffins.")> )

=item B<$room>-E<gt>Members( B<\%members> )

B<\%members> is a reference to a hash containing nicknames and psyc addresses of all users currently in the room represented by B<$room>. The structure of the hash is { nickname =E<gt> psyc address }.

=item B<$room>-E<gt>topic( B<$topic>, B<$nick> )

Whenever the topic in this chatroom is changed this method is called with the new B<$topic> and the B<$nick> who changed it if available.

=item B<$room>-E<gt>history( B<$timestamp>, B<$text> )

Messages that have not been said recently but should be considered historical. B<$timestamp> represents this time in the past in seconds since epoch. Of course this depends on the time the PSYC server considers to be epoch.

=back 
 
=head2 Person
 
In addtion to I<notice> every object representing a private chat has to have following methods

=over 4

=item B<$person>-E<gt>message( B<$nick>, B<$text>, B<$speakaction> )

A private message coming from the user represented by B<$person>. As for I<message> in room context B<$text> being an empty string means that the message is an action.

=back

=head1 SEE ALSO

L<Net::PSYC>, L<Net::PSYC::Event>, L<http://psyc.pages.de/>

=head1 AUTHORS

Arne GE<ouml>deke <el@goodadvice.pages.de>

=head1 COPYRIGHT

Copyright (c) 2004 Arne GE<ouml>deke. All rights reserved.
This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
