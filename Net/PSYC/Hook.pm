package Net::PSYC::Hook;

sub trigger {
    my $self = shift;
    my $hook = shift;

    return 1 if (!exists $self->{'hooks'}->{$hook});
    foreach (@{$self->{'hooks'}->{$hook}}) {
	unless (&{$_}(@_)) {
	    return 0;
	}
    }
    return 1;
}

sub hook {
    my $self = shift;
    my $hook = shift;
    my $obj = shift;
    
    unless (ref $obj) {
	$obj = eval "$hook->new(\$self);";
	return 0 if (!ref $obj);
    }
    return 0 unless ($obj->can($hook));
    unless (exists $self->{'hooks'}->{$hook}) {
	$self->{'hooks'}->{$hook} = [];
    }
    push(@{$self->{'hooks'}->{$hook}}, eval"sub { \$obj->$hook(\@_) }" );
    return 1;
}


1;
