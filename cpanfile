# Generated from Makefile.PL using makefilepl2cpanfile

requires 'perl', '5.016';

requires 'Carp';
requires 'File::Basename';
requires 'IO::Compress::Gzip';
requires 'IO::Compress::Zip';
requires 'IO::Uncompress::Gunzip';
requires 'IO::Uncompress::Unzip';
requires 'IPC::System::Simple';   # autodie's :system
requires 'Mail::Address';
requires 'Mail::DKIM';
requires 'Mail::DKIM::Signer';
requires 'Object::Configure';
requires 'Params::Get';
requires 'Params::Validate::Strict';
requires 'Readonly';
requires 'Sub::Private';
requires 'Sub::Protected';
requires 'Sys::Syslog';
requires 'XML::PP';

on 'configure' => sub {
	requires 'ExtUtils::MakeMaker', '6.64';   # Minimum version for TEST_REQUIRES
};

on 'test' => sub {
	requires 'File::Spec';
	requires 'File::Temp';
	requires 'Net::DNS';
	requires 'Pod::Github';
	requires 'Test::DescribeMe';
	requires 'Test::Memory::Cycle';
	requires 'Test::Mockingbird';
	requires 'Test::Most';
	requires 'Test::Needs';
	requires 'Test::Returns';
	requires 'Time::HiRes';
};

on 'develop' => sub {
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
