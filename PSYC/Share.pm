package Net::PSYC::Share;

use Net::PSYC::Tie::File;
use Exporter;
use Digest::MD5;
use Fcntl ':mode';
use IO::File;
use IO::Dir;

@ISA = qw(Exporter);
@EXPORT = qw(share %files sendFile search);

#  checksum ->	filename
our %files;

#   share ( filename )
sub share {
    my $filename = shift;
    my @info = stat($filename);

#    print "$filename ";

    if (S_ISDIR($info[2])) {
#	print "is a directory!\n";
	my %f;
	tie %f, 'IO::Dir', $filename;
	
	foreach (keys %f) {
	    share($filename.'/'.$_) if ($_ ne '.' && $_ ne '..');
	}
	untie %f;
	return;
    }
    #print "is a file!\n";
    
    open(FILE, "<$filename");
    $files{Digest::MD5->new()->addfile(FILE)->hexdigest} = $filename;
    close(FILE);
}

#   search(source, string[, max]);
sub search {
    my ($source, $string, $max) = @_;
    my (@r_names, @r_sums);
    foreach (keys %files) {
	last if ($max == 0);
	if ($files{$_} =~ /$string/) {
	    $max--;
	    push(@r_sums, $_);
	    push(@r_names, $files{$_});
	}
    }
    return (\@r_sums, \@r_names) if @r_sums;
    return;
}

#   sendFile(to, checksum)
#
#   replace this!
sub sendFile {
    my $target = shift;
    my $checksum = shift;
    my $filename = $files{$checksum};
    
    my @fragments;
    tie @fragments, 'Net::PSYC::Tie::File', $filename, 4096;
    
    my $head = <<END;
:_filename	$filename
:_checksum	$checksum
:_checksum_type	md5
_message_fileshare_file
END
    unshift(@fragments, $head);
    return send_mmp($target, \@fragments, 
		{ 
		    '_amount_fragments' => scalar(@fragments),
		    '_counter'		=> $checksum,
	    });
}

1;
