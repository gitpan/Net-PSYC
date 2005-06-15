package Net::PSYC::Share::FileMap;

my $basedir;

sub basedir { $basedir }
sub set_basedir {
    $basedir = shift;
}

sub open {
    my $class = shift;
    my $filename = shift; # filename
    my $self = {
	'filename' => $basedir.'/'.$filename,
    };
    bless $self, $class;
    if ($self->parse()) {
	return $self;
    }
    return 0;
}

sub create {
    my $class = shift;
    my $filename = shift;
    my $name = shift;
    my $size = shift;
    my $self = {
	'filename' => $basedir.'/'.$filename,
	'size'	  => $size,
	'name'	  => $name,
	'map'	  => [ [$size, $size] ],
    };
    bless $self, $class;
    if ($self->save()) {
	return $self;
    }
    return 0;
}

sub parse {
    my $self = shift;
    if (stat($self->{'filename'}.'.map') 
    && open ($self->{'fh'}, '<', $self->{'filename'}.'.map')) {
	while (defined($_ = readline($self->{'fh'})) && $_ =~ /^(\w)\:\s?(\.*)$/ && $1 ne 'filename' && $1 ne 'fh') {
	    if ($_ eq 'map') {
		$self->{'map'} = [];
		goto MAP;
	    }
	    $self->{$1} = $2;
	    $_ = 0;
	}
	print STDERR "Error while parsing $self->{'filename'}.map \n";
	return 0;
	MAP:
	while (($_ || (defined($_ = readline($self->{'fh'})))) && $_ =~ /(\d+)\-(\d+)/) {
	    push(@{$self->{'map'}}, [ $1, $2 ]);
	    $_ = 0;
	}
	push(@{$self->{'map'}}, [ $self->{'size'}, $self->{'size'} ]);
	close($self->{'fh'});
	return 1;
    }
}

sub save {
    my $self = shift;
    if (open ($self->{'fh'}, '>', $self->{'filename'}.'.map')) {
	my $string = "name: $self->{'name'}\nsize: $self->{'size'}\nmap:\n";
	foreach (@{$self->{'map'}}) {
	    $string .= "$_->[0]-$_->[1]\n";
	}
	syswrite($self->{'fh'}, $string) or print "$!\n";
	return 1;
    }
    print STDERR "Failed saving $self->{'filename'}.map. ($!)\n";
    return 0;
}


###
# these are range-operating functions
# dont get confused
sub get_range {
    my $self = shift;
    my $size = shift;
    my $last = -1;
    foreach (@{union($self->{'map'}, $self->{'queue'})}) {
	if ($_->[0] > $last + 1) {
	    if ($_->[0] > $last + $size) {
		$self->set_queue($last + 1, $size);
		return ($last + 1, $size);
	    } else {
		$self->set_queue($last + 1, $_->[0] - $last);
		return ($last + 1, $_->[0] - $last);
	    }
	}
	$last = $_->[1];
    }
    return -1 if (!scalar(@{$self->{'queue'}}));
    return;
}

sub set_queue {
    my $self = shift;
    $self->{'queue'} = set_range($self->{'queue'}, @_);
}

sub set_map {
    my $self = shift;
    $self->{'map'} = set_range($self->{'map'}, @_);
    $self->{'queue'} = relative_complement($self->{'queue'}, [[ $offset, $offset + $range - 1]]);
    return $self->save();
}

sub set_range {
    my ($array, $offset, $range) = (shift, shift, shift);
    return union($array, [[ $offset, $offset + $range - 1 ]]);    
}
#
###

sub union {
    my ($m, $n) = (shift, shift);
    my $M = [];
    my $i = 0;
    my $j = 0;
    while ( $i < scalar(@$n) || $j < scalar(@$m) ) {
	if (!exists $m->[$j]) { push(@$M, $n->[$i++]); next; } 
	if (!exists $n->[$i] || $n->[$i]->[0] > $m->[$j]->[1]) { 
	    push(@$M, $m->[$j++]);
	    next;
	}
	if ($m->[$j]->[0] > $n->[$i]->[1]) { push(@$M, $n->[$i++]); next; }
	push(@$M, [ min($m->[$j]->[0], $n->[$i]->[0]), max($m->[$j++]->[1], $n->[$i++]->[1]) ]);
    }
    return clean($M);
}

sub intersection {
    my ($m, $n) = (shift, shift);
    my $M = [];
    my $i = 0;
    my $j = 0;
    while ( $i < scalar(@$n) && $j < scalar(@$m) ) {
	if ($n->[$i]->[0] > $m->[$j]->[1]) { $j++; next; }
	if ($m->[$j]->[0] > $n->[$i]->[1]) { $i++; next; }
	push(@$M, [ max($m->[$j]->[0], $n->[$i]->[0]), min($m->[$j++]->[1], $n->[$i++]->[1]) ]);
    }
    return $M;
}

sub relative_complement {
    my ($m, $n) = (shift, shift);
    use Storable qw(dclone);
    $m = dclone($m);
    $n = dclone($n);
    my $M = [];
    my $i = 0;
    my $j = 0;
    while ( $i < scalar(@$n) || $j < scalar(@$m) ) {
	if (!exists $m->[$j]) { push(@$M, $n->[$i++]); next; } 
	if (!exists $n->[$i] || $n->[$i]->[0] > $m->[$j]->[1]) { 
	    push(@$M, $m->[$j++]);
	    next;
	}
	if ($m->[$j]->[0] > $n->[$i]->[1]) { push(@$M, $n->[$i++]); next; }
	push(@$M, [ min($m->[$j]->[0], $n->[$i]->[0]), max($m->[$j]->[0], $n->[$i]->[0]) - 1 ]) if ($m->[$j]->[0] != $n->[$i]->[0]);
	if ($n->[$i]->[1] > $m->[$j]->[1]) {
	    $n->[$i]->[0] = $m->[$j++]->[1] + 1; # cut the rest off! 
	} elsif ($n->[$i]->[1] < $m->[$j]->[1]) {
	    $m->[$j]->[0] = $n->[$i++]->[1] + 1; # cut cut
	} else {
	    $i++; $j++;
	}
    }
    return $M;
}

sub clean {
    my $m = shift;
    for (my $i = 1; $i < scalar(@$m); $i++) {
	if ($m->[$i]->[0] == $m->[$i - 1]->[1] + 1) {
	    splice(@$m, $i - 1, 2, [ $m->[$i - 1]->[0], $m->[$i]->[1] ]);
	}
    }
    return $m;
}

sub Dumper {
    use Data::Dumper;
    my $data = join("", Data::Dumper::Dumper(@_));
    $data =~ s/\n//g;
    $data =~ s/\s+/\ /g;
    return $data;
}

sub max {
    return $_[0] if ($_[0] > $_[1]);
    return $_[1];
}

sub min {
    return $_[0] if ($_[0] < $_[1]);
    return $_[1];
}

sub DESTROY {
    my $self = shift;
    close($self->{'fh'});
}


1;
