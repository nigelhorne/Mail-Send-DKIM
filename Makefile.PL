#!/usr/bin/env perl
#
# Mail::Send::DKIM - named after the module it ships, so that the name in the
# metadata is one a caller can actually C<use>, and so that PAUSE indexes the
# distribution under the module that does the work.  The programmes that use
# the module travel with it and are installed by the same command.

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
