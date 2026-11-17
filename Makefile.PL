#!/usr/bin/env perl
#
# Mail::Send::DKIM - the module is what the distribution is named after,
# because a distribution whose name is not a module it ships is one PAUSE
# cannot index sensibly: App::DMARC promised a namespace with no file behind
# it.  The programmes that use the module travel with it, and are installed by
# the same command.

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
	'NAME' => 'Mail::Send::DKIM',
	'VERSION_FROM' => 'lib/Mail/Send/DKIM.pm',
	'ABSTRACT' => 'Sign mail with DKIM, and summarise DMARC reports',
	'AUTHOR' => 'Nigel Horne <njh@bandsman.co.uk>',
	'LICENSE' => 'gpl_2',
	'MIN_PERL_VERSION' => '5.016',
	'EXE_FILES' => [
		'bin/dmarc-report.pl',
		'bin/dmarc-weekly.sh',
		'bin/dmarc-check-mail.pl',
		'bin/mail-dkim',
	],
	'PREREQ_PM' => {
		'IO::Compress::Gzip' => 0,
		'IO::Compress::Zip' => 0,
		'IO::Uncompress::Gunzip' => 0,
		'IO::Uncompress::Unzip' => 0,
		'Mail::DKIM' => 0,
		'Readonly' => 0,
		'XML::LibXML' => 0,
	},
	'TEST_REQUIRES' => {
		'File::Temp' => 0,
		'Net::DNS' => 0,
		'Pod::Github' => 0,
		'Test::Most' => 0,
		'Time::HiRes' => 0,
	},
	'META_MERGE' => {
		'resources' => {
			'repository' => 'https://github.com/nigelhorne/mail-send-dkim',
			'bugtracker' => 'https://github.com/nigelhorne/mail-send-dkim/issues',
		},
	},
);
