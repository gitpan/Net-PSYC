package Net::PSYC::Tie::File;

# this modules ties a file to an array.. not line-wise but in chunks of bytes.
# whatever.. fuck my english

use bytes;
use strict;
use Carp;

my %files;

sub TIEARRAY {
    # offset and size are used to specify a range of bytes
    # in the file
    my ($class, $file, $chunksize, $offset, $range) = @_;
    my $fh;
    
    unless (exists $files{$file}) {
	open($fh, '<', $file) or do {
	    print STDERR "Could not open file $file. Says: $!\n";
	    return;
	};
	binmode($fh);
	$files{$file} = [ $fh, 1 ];
    } else {
	$fh = $files{$file}->[0];
	$files{$file}->[1]++;
    }
    
    my @stat = stat($file);
    unless (@stat) {
	print STDERR "Could not stat file $file. Says: $!\n";
	return;
    }
    $offset ||= 0;
    if ($offset >= $stat[7]) {
	$offset = $stat[7] - 1;
    }
    $range ||= $stat[7] - $offset; # 0 means the rest!
    if ($offset + $range > $stat[7]) {
	$range = $stat[7] - $offset
    }
    
    my $array = [ 0 .. int($range / $chunksize) ];
    
    return bless {
	'FH'	=>	$fh,
	'BYTES'	=>	$chunksize,
	'SIZE'	=>	$stat[7],
	'A'	=>	$array,
	'C'	=>	0,
	'NAME'	=>	$file,
	'OFFSET'=>	$offset,
	'RANGE'	=>	$range,
    }, $class;
}

sub read_chunk {
    my ($self, $index) = @_;

    my ($data, $length);
    
    if (($index + 1) * $self->{'BYTES'} > $self->{'RANGE'}) {
	$length = $self->{'RANGE'} % $self->{'BYTES'};
    } else {
	$length = $self->{'BYTES'};
    }
    
    sysseek($self->{'FH'}, $index * $self->{'BYTES'} + $self->{'OFFSET'}, 0);
    my $flag = sysread($self->{'FH'}, $data, $length);
    return $data;
}

sub FETCH {
    my ($self, $index) = @_;
    
    if (ref $self->{'A'}->[$index]) {
	return ${$self->{'A'}->[$index]};
    }
    return read_chunk($self, $self->{'A'}->[$index]);
}

sub FETCHSIZE {
    my $self = shift;
    return scalar @{$self->{'A'}};
}

sub EXISTS {
    my ($self, $index) = @_;
    exists $self->{'A'}->[$index];
}

sub UNTIE {
    my $self = shift;
    unless (--$files{$self->{'NAME'}}->[1]) {
	close $self->{'FH'};
	delete $files{$self->{'NAME'}};
    }
}

# all methods below change the array

sub STORE {
    my ($self, $index, $value) = @_;
    
    $self->{'A'}->[$index] = \$value;
}

sub STORESIZE { }
sub EXTEND { }

sub DELETE {
    my ($self, $index) = @_;
    
    if (ref $self->{'A'}->[$index]) {
	return ${delete $self->{'A'}->[$index]};
    }
#    print STDERR "reading index $index \n";
    return read_chunk($self, delete $self->{'A'}->[$index]);
}

sub CLEAR { }

sub PUSH {
    my $self = shift;
    push(@{$self->{'A'}}, map { \$_ } @_ );
}

sub POP {
    my $self = shift;
    my $last = pop(@{$self->{'A'}});
    (ref $last) ? $$last : read_chunk($self, $last);    
}

sub SHIFT {
    my $self = shift;
    my $first = shift(@{$self->{'A'}});
    (ref $first) ? $$first : read_chunk($self, $first);    
}

sub UNSHIFT {
    my $self = shift;
    unshift(@{$self->{'A'}}, map { \$_ } @_ );
}

sub SPLICE {
    my $self = shift;
    map { (ref $_) ? $$_ : read_chunk($self, $_) } splice(@{$self->{'A'}}, @_);
}

1;
