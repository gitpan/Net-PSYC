package Net::PSYC::Event::Gtk2;

use vars qw($VERSION);
$VERSION = '0.1';

use Exporter;
use strict;

use Gtk2::Helper;
use Glib;
use vars qw(@ISA @EXPORT_OK);

@ISA = qw(Exporter);
@EXPORT_OK = qw(init can_read can_write has_exception add remove startLoop stopLoop revoke);

my (%r, %w, %revoke);

sub can_read {
    croak('can_read() is not yet implemented by Net::PSYC::Event::Gtk2');
}

sub can_write {
    croak('can_write() is not yet implemented by Net::PSYC::Event::Gtk2');
}

sub has_exception {
    croak('has_exception() is not yet implemented by Net::PSYC::Event::Gtk2');
}


#   add (\*fd, flags, cb[, repeat])
sub add {
    my ($fd, $flags, $cb, $repeat) = @_;
    croak('add () using Gtk2 requires a callback!') if (!$cb);
    print STDERR "Net::PSYC::Event::Gtk2->add($fd, $flags, $cb)\n" if Net::PSYC::DEBUG;
    
    # one-shot event!
    if (defined($repeat) && $repeat == 0) {
	$cb = do {
		my ($fd, $flags, $cb) = ($fd, $flags, $cb);
		sub {
		    Net::PSYC::Event::Gtk2::remove($fd, $flags);
		    &$cb();
		}
	};
	$revoke{scalar($fd)} = [ $fd, $flags, $cb ];
    }

    if ($flags =~ /r/) {
	$r{scalar($fd)} = Gtk2::Helper->add_watch(fileno($fd), 'in', $cb);
    }
    if ($flags =~ /w/) {
	$w{scalar($fd)} = Gtk2::Helper->add_watch(fileno($fd), 'out', $cb);
    }
    if ($flags =~ /e/) {
	print STDERR "Callbacks on error are not supported jet. Asl the author of this module to implement is.. he will! :)\n";
    }
}

#   revoke ( \*fd )
sub revoke {
    my $name = scalar(shift);
#   print "Net::PSYC::Event::Gtk2->revoke($name)\n" if Net::PSYC::DEBUG;
    if (exists $revoke{$name}) {
	my $flags = $revoke{$name}->[1];
	return if ((!$flags =~ /r/ || exists $r{$name}) && (!$flags =~ /w/ || exists $w{$name}));
	add(@{$revoke{$name}});
    }
}

#   remove (\*fd[, flags] )
sub remove {
    my ($name, $flags) = (scalar(shift), shift);
#    print "Net::PSYC::Event::Gtk2->remove($name, $flags)\n" if Net::PSYC::DEBUG;
    
    if ((!$flags || $flags =~ /r/) && exists $r{$name} ) {
#	print STDERR "Gtk2::Helper->remove_watch( $r{$name} ) == ";
	Gtk2::Helper->remove_watch( delete $r{$name} );
#	print STDERR ";\n";
    }
    if ((!$flags || $flags =~ /w/) && exists $w{$name}) {
#	print STDERR "Gtk2::Helper->remove_watch( $w{$name} ) == ";
	Gtk2::Helper->remove_watch( delete $w{$name} );
#	print STDERR ";\n";
    }
}



sub startLoop {
    croak('Net::PSYC::Event::Gtk2 does not implement an EventLoop. Use the one implemented by Gtk2!');
}

sub stopLoop {
    croak('Net::PSYC::Event::Gtk2 does not implement an EventLoop. Use the one implemented by Gtk2!');
}

1;
