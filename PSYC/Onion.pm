package Net::PSYC::Onion;

# Gedanken:
#
# - damit irgendwelche queries nichts ewig durchs netz geistern, werden
#   wir zweierlei techniken anwenden müssen:
#   1. Falls ich zu einer Suchanfrage etwas finde, schicke ich den query
#      nicht an alle peers weiter, die ich kenne.. sondern nur an einen
#      bestimmten prozentsatz. Ich finde diese Lösung wesentlich netter
#      als time-of-life oder gar hop-counter, da es gewährleistet, dass
#      suchanfragen nach seltenen sachen nicht erfolglos enden, obwohl
#      irgendwo im netz etwas vorhanden ist. Im übrigen sind die anderen
#      beiden techniken eh müll.. sie verraten viel zu viel über den
#      ursprung der msg.
#   2. Man merkt sich immer welche suchanfragen oder file-anfragen man
#      von welcher pseudo-source bekommen hat und dropt sie, wenn sie
#      das zweite mal kommen. Das soll vor allem verhindern, dass sich
#      loops bilden.
#
#

use Net::PSYC qw(register_uniform UNL send_mmp);
use Net::PSYC::Tie::AbbrevHash;
use Net::PSYC::Tie::File;
use Net::PSYC::Share::FileMap;
use Digest::MD5;

our %files;
my (%temp, $STORE);
my (%searches, %links, %react);
my (%search_results);
my %requests;
my $MAX_REQUESTS = 5; # TODO this is bullshit for testing 

#register_uniform();
register_uniform('@onion');

sub set_tempdir {
    &Net::PSYC::Share::FileMap::set_basedir;
}

sub set_storedir {
    $STORE = shift;
}

sub UNL () { Net::PSYC::UNL.'@onion' }

sub fake_source {
    my $sum = shift;
    unless (exists $requests{$sum}) {
	$requests{$sum} = 'onion://'.Digest::MD5->new()->add(UNL().$sum.time())->hexdigest.'/';
	register_uniform($requests{$sum});
    }
    
    return $requests{$sum};
}

sub msg {
    my ($source, $mc, $data, $vars) = @_;
    
    my $sub = $react{$mc};
    if ($sub) {
	&$sub($source, $mc, $data, $vars);	
    } else {
	print "Received unknown mc: $mc\nsource: $source\ndata: ".length($data)."\n";
    }
    return 1;
}

tie %react, 'Net::PSYC::Tie::AbbrevHash';
%react = (
'_request_search' => sub {
	my ($source, $mc, $data, $vars) = @_;
	my ($sums, $names, $size) = local_search($vars->{'_query'});
        if (@$sums) {
            sendmsg($vars->{'_source_relay'}, '_reply_search', 'Found '.scalar(@$sums).' matching "'.$vars->{'_query'}.'"',
                    {   
                        '_query' => $vars->{'_query'},
                        '_amount' => scalar(@$sums),
                        '_files' => $names,
                        '_files_checksum' => $sums,
                        '_files_size'     => $size,
                        '_source_relay' => fake_source(),
                        '_source' => UNL(),
                    });
#           return 1; # we dont send on if we found something
        }
        castmsg($source, '_request_search', $data, 
		{
		    '_query' => $vars->{'_query'},
		    '_source_relay' => $vars->{'_source_relay'},
		    '_source' => UNL(),
		});
        return 1;
},
'_request_file' => sub {
	my ($source, $mc, $data, $vars) = @_;
	if (exists $files{$vars->{'_checksum'}}) {
            my $f = $files{$vars->{'_checksum'}};
            my @file;
            tie @file, 'Net::PSYC::Tie::File', $f->[2], 4096, $vars->{'_offset'}, $vars->{'_range'};
            unshift(@file,":_checksum   $vars->{'_checksum'}
:_filename      $f->[2]
:_offset        ".($vars->{'_offset'} || 0)."
:_range         ".($vars->{'_range'} || ($f->[1] - ($vars->{'_offset'} || 0)))."
:_filesize      $f->[1]
_reply_file
");     
            send_mmp($vars->{'_source_relay'}, \@file,
                    {
                        _source_relay => fake_source($vars->{'_checksum'}),
                        _source => UNL(),
                        _amount_fragments => scalar(@file),
                    });
            return 1;
        } # do we send it on?
        castmsg($source, '_request_file', 'gib gib!',
                {
                    _source => UNL(),
                    _source_relay => $vars->{'_source_relay'},
                    _checksum => $vars->{'_checksum'},
                    _offset => $vars->{'_offset'},
                    _range => $vars->{'_range'},
                });
	return 1;
	
},
'_reply_search' => sub {
	my ($source, $mc, $data, $vars) = @_;
	print Net::PSYC::psyctext($data, $vars)."\n";
        my $i = 0;
	foreach (@{( ref $vars->{'_files'}) ? $vars->{'_files'} : [ $vars->{'_files'} ]}) {
            $search_results{${$vars->{'_files_checksum'}}[$i]} = [
                $_, ${$vars->{'_files_size'}}[$i]
            ];                                            
            print ${$vars->{'_files_checksum'}}[$i]."\t$_\n";
            $i++;
        }	
},
'_notice_unlink_onion' => sub {
	my ($source, $mc, $data, $vars) = @_;
	if (exists $links{$source}) {
            delete $links{$source};                       
            sendmsg($source, '_notice_unlink_onion', 'Astalavista, Baby!',
		    { '_source' => UNL() });
            return 1;
        }
},
'_notice_link_denied' => sub {
	my ($source, $mc, $data, $vars) = @_;
	my $obj = Net::PSYC::get_connection($source);
        Net::PSYC::shutdown($obj); # you dont like me, i dont like you!
        return 1;
},
'_reply_file' => sub {
	my ($source, $mc, $data, $vars) = @_;
	if (save($vars, $data)) {
            request($vars->{'_checksum'});
        }
},
'_notice_link_onion' => sub {
	my ($source, $mc, $data, $vars) = @_;
	if (!exists $links{$source}) {
		sendmsg($source, '_notice_unlink_onion', '',
			{ '_source' => UNL() });
	    return 1;
	}
	print "Link to $source established!\n";
	my $obj = Net::PSYC::get_connection($source);
	$obj->TRUST(11) if $obj;
	return 1;
},
'_request_link_onion' => sub {
	my ($source, $mc, $data, $vars) = @_;
	sendmsg($source, '_notice_link_onion', '', { '_source' => UNL() });
	$links{$source} = 1;
}
);


sub castmsg {
    my ($source, $mc, $data, $vars) = @_;
    foreach (keys %links) {
	next if ($_ eq $source);
	sendmsg($_, $mc, $data, $vars);
    }
}

sub search {
    # generate a $source
    # 
    my $query = shift;
    foreach (keys %links) {
	sendmsg($_, '_request_search', 'SUCHEN!',
		{
		    _query => $query,
		    _source => UNL(),
		    _source_relay => fake_source($query),
		    # this is of course just to test
		}
		);
    }
}

sub request {
    my $sum = shift;
    unless (exists $temp{$sum}) {
	$temp{$sum} = Net::PSYC::Share::FileMap->open($sum);
	unless ($temp{$sum} || exists $search_results{$sum}) {
	    print STDERR "I dont know anything about $sum.\n";
	    delete $temp{$sum};
	    return 0;
	}
	$temp{$sum} ||= Net::PSYC::Share::FileMap->create($sum, $search_results{$sum}->[0], $search_results{$sum}->[1]);
	unless ($temp{$sum}) {
	    delete $temp{$sum};
	    return 0;
	}
    }
    my ($offset, $range) = $temp{$sum}->get_range(1024 * 128); # change that to a proper value!!!!
    return unless(defined($offset));
    if ($offset == -1) {
	my @temp = split(/\//,$temp{$sum}->{'name'});
	use Data::Dumper;
	print Dumper($temp{$sum});
	
	my $name = pop(@temp);
	link($temp{$sum}->{'filename'}, $STORE.$name);
	unlink($temp{$sum}->{'filename'});
	unlink($temp{$sum}->{'filename'}.'.map');
	delete $temp{$sum};
	print "Downloaded $name to $STORE$name.\n";
	return 1;
    }
    castmsg('', '_request_file', '', 
	    {
		_checksum => $sum,
		_source => UNL(),
		_offset => $offset,
		_range => $range,
		_source_relay => fake_source($sum),
	    });
}

sub local_search {
    my $query = shift;
#    print "Searching for $query\n";
    my (@sums, @names, @size);
    foreach (values %files) {
	if ($_->[2] =~ /$query/) {
#	    print "found $_->[2]\n";
	    push(@sums, $_->[0]);
	    push(@names, $_->[2]);
	    push(@size, $_->[1]);
	}
    }
    return (\@sums, \@names, \@size);
}

sub link {
    my $uni = shift;
    $links{$uni} = 1;
    sendmsg($uni, '_request_link_onion', 'ich will sharen!', { _source => UNL() });
}

sub link_onion {
    my $uni = shift;
    my $pass = shift;
    sendmsg($uni, '_request_link_onion', 'Link me!', 
	    { 
		_password => $pass, 
		_location => UNL(),
	    });
}

sub unlink_onion {
    my $uni = shift;
    my $pass = shift;
    sendmsg($uni, '_request_unlink_onion', 'Unlink me!',
	    {
		_password => $pass,
	    });
}

sub save {
    my ($vars, $data) = @_;
    unless (exists $temp{$vars->{'_checksum'}}) {
	$temp{$vars->{'_checksum'}} = Net::PSYC::Share::FileMap->open($vars->{'_checksum'});
	unless ($temp{$vars->{'_checksum'}}) {
	    print STDERR "Received File I did not request! (checksum: $temp{$vars->{'_checksum'}})\n";
	    delete $temp{$vars->{'_checksum'}};
	}
    }
    $name = $temp{$vars->{'_checksum'}}->{'filename'};
    open(file, '>>', $name) or do {
	print STDERR "Could not open $name for writing!\n";
	return 0;
    };
    $temp{$vars->{'_checksum'}}->set_map($vars->{'_offset'}, $vars->{'_range'});
    print "Writing ".length($data)." to $name\n";
    sysseek(file, $vars->{'_offset'}, 0);
    syswrite(file, $data);
    close (file);
#    sleep(10);
}

1;
