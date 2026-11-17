# Generated from Makefile.PL using makefilepl2cpanfile

on 'configure' => sub {
	requires 'ExtUtils::MakeMaker', '6.64';   # Minimum version for TEST_REQUIRES
};

on 'develop' => sub {
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
