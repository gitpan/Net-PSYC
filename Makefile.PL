
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
	      'NAME'  => 'Net::PSYC',
	      'PM'    =>  {
		  'PSYC.pm'        => '$(INST_LIBDIR)/PSYC.pm',
		  'PSYC/Circuit.pm' => '$(INST_LIBDIR)/PSYC/Circuit.pm',
		  'PSYC/Datagram.pm' => '$(INST_LIBDIR)/PSYC/Datagram.pm',
		  'PSYC/Event.pm' => '$(INST_LIBDIR)/PSYC/Event.pm',
		  'PSYC/State.pm' => '$(INST_LIBDIR)/PSYC/State.pm',
		  'PSYC/Event/Event.pm' => '$(INST_LIBDIR)/PSYC/Event/Event.pm',
		  'PSYC/Event/IO_Select.pm' => '$(INST_LIBDIR)/PSYC/Event/IO_Select.pm',
		  'PSYC/Event/Gtk2.pm' => '$(INST_LIBDIR)/PSYC/Event/Gtk2.pm',
		  'PSYC/Storage.pm' => '$(INST_LIBDIR)/PSYC/Storage.pm',
		  'PSYC/Client.pm' => '$(INST_LIBDIR)/PSYC/Client.pm',
		  'PSYC/Tie/AbbrevHash.pm' => '$(INST_LIBDIR)/PSYC/Tie/AbbrevHash.pm',
		  'PSYC/Tie/File.pm' => '$(INST_LIBDIR)/PSYC/Tie/File.pm',
	      },
              'PREREQ_PM' => {
                  'Storable'		=> 0,
                  'Carp'		=> 0,
                  'Socket'		=> 0,
                  'IO::Socket'		=> 0,
                  'Digest::MD5'		=> 0,
                  'Exporter'		=> 0,
              },
	      'VERSION_FROM' => 'PSYC.pm', # finds $VERSION
              'dist' => { 'COMPRESS' => 'gzip --best' },
);
