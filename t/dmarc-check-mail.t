#!/usr/bin/env perl
#
# dmarc-check-mail.pl is the "does mail from this host authenticate?" tester:
# it signs one message and either prints it or hands it to sendmail, so that a
# mailbox you can read shows what receivers make of this host's mail.
#
# The key pair is made at run time, so no key material lives in the repository,
# and the public half is served to the verifier through a stubbed DNS lookup
# rather than being published anywhere.  What is under test is the programme's
# own behaviour: the signature it prints, the absence of one under --plain, and
# what it says when there is no key to sign with.

use strict;
use warnings;

use Test::Most;

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($Bin);

my $SCRIPT = File::Spec->catfile($Bin, File::Spec->updir(), 'bin', 'dmarc-check-mail.pl');

BAIL_OUT("Cannot find $SCRIPT") unless(-r $SCRIPT);

plan skip_all => 'Mail::DKIM is needed to sign and verify'
	unless(eval { require Mail::DKIM::Signer; require Mail::DKIM::Verifier; require Mail::DKIM::DNS; require Net::DNS::RR; 1 });

my $openssl;
foreach my $dir (File::Spec->path()) {
	my $candidate = File::Spec->catfile($dir, 'openssl');
	if(-x $candidate) {
		$openssl = $candidate;
		last;
	}
}
plan skip_all => 'openssl is needed to make a key pair' unless($openssl);

my $TMP = tempdir(CLEANUP => 1);

# One HOME with a key in the place the programme looks first, and one with
# nothing, so that "found by itself" and "found nothing" are both real.
my $HOME = File::Spec->catdir($TMP, 'home');
my $KEYS = File::Spec->catdir($HOME, 'dkim');
my $EMPTY_HOME = File::Spec->catdir($TMP, 'empty-home');
make_path($KEYS, $EMPTY_HOME) or BAIL_OUT("Cannot make the test directories: $!");

my $KEY = File::Spec->catfile($KEYS, 'selector1.private');
my $DEVNULL = File::Spec->devnull;
system(qq{"$openssl" genrsa -out "$KEY" 2048 2>"$DEVNULL"}) == 0
	or BAIL_OUT("openssl could not make $KEY");

# The public half, as the TXT record at <selector>._domainkey.<domain> would
# carry it: base64 of the SubjectPublicKeyInfo, with the PEM markers gone.
# Made once - every verification asks the same question.
my @TXT_RECORD;

sub txt_record
{
	unless(@TXT_RECORD) {
		open(my $pipe, '-|', qq{"$openssl" rsa -in "$KEY" -pubout 2>"$DEVNULL"})
			or BAIL_OUT("Cannot run openssl: $!");
		my $pem = do { local $/; <$pipe> };
		close($pipe);
		BAIL_OUT("openssl could not read $KEY") unless($pem =~ /KEY-----/);

		$pem =~ s/-----[^-]+-----//g;
		$pem =~ s/\s+//g;
		my $record = 'v=DKIM1; k=rsa; p=' . $pem;
		for(my $offset = 0; $offset < length($record); $offset += 255) {
			push @TXT_RECORD, substr($record, $offset, 255);
		}
	}

	return @TXT_RECORD;
}

# A receiving site hashes the message in its CRLF form, which is what the
# sending MTA puts on the wire, so what the programme signs is verified the
# same way: after the line endings an MTA would have converted.
sub verify_signature
{
	my $message = shift;

	$message =~ s/\r\n/\n/g;
	$message =~ s/\n/\r\n/g;

	my @chunks = txt_record();

	no warnings qw(once redefine);
	local *Mail::DKIM::DNS::query = sub {
		return Net::DNS::RR->new(type => 'TXT', txtdata => \@chunks);
	};

	my $verifier = Mail::DKIM::Verifier->new();
	$verifier->PRINT($message);
	$verifier->CLOSE;

	return $verifier->result;
}

sub slurp
{
	my $path = shift;

	local $/;
	open(my $fh, '<', $path) or return '';
	my $text = <$fh>;
	close($fh);

	return $text;
}

# The programme reads nothing on stdin and writes a whole message to stdout, so
# a run is a process and three files.  The environment is built from scratch:
# a DKIM_KEYFILE or DMARC_TEST_* left over in the developer's shell would
# otherwise decide the outcome of a test about finding keys.
sub run_script
{
	my ($home, @args) = @_;

	my $out = File::Spec->catfile($TMP, 'stdout.txt');
	my $err = File::Spec->catfile($TMP, 'stderr.txt');

	my $pid = fork();
	die "fork: $!" unless(defined($pid));

	if(!$pid) {
		foreach my $name (qw(DKIM_KEYFILE SENDMAIL DMARC_TEST_TO DMARC_TEST_FROM
				DMARC_TEST_DOMAIN DMARC_TEST_SELECTOR)) {
			delete($ENV{$name});
		}
		$ENV{'HOME'} = $home;
		open(STDIN, '<', File::Spec->devnull()) or exit 127;
		open(STDOUT, '>', $out) or exit 127;
		open(STDERR, '>', $err) or exit 127;
		exec($^X, $SCRIPT, @args) or exit 127;
	}

	waitpid($pid, 0);

	return ($? >> 8, slurp($out), slurp($err));
}

subtest '--dry-run prints a signed message, and the signature verifies' => sub {
	# No --keyfile: the key has to be found in ~/dkim by its selector, which
	# is the way the programme is meant to be used.
	my ($status, $out, $err) = run_script($HOME,
		'--dry-run', '--from' => 'alerts@example.org', '--to' => 'webmaster@example.org',
		'--domain' => 'example.org', '--selector' => 'selector1');

	is($status, 0, 'it exited 0');
	is($err, '', 'nothing on stderr') or diag($err);

	like($out, qr/\ADKIM-Signature: /, 'the message starts with the signature');
	like($out, qr/d=example\.org/, 'for the domain asked for');
	like($out, qr/s=selector1/, 'under the selector asked for');
	like($out, qr/^From: alerts\@example\.org$/m, 'and it is the message that was asked for');
	like($out, qr/^To: webmaster\@example\.org$/m, 'to the address asked for');
	like($out, qr/nothing was sent/, 'and it said nothing was sent');

	# The printed message is what the mailbox would have shown, so take it
	# back out of the output - the marker line is not part of it.
	(my $signed = $out) =~ s/\n--- .*\z//s;
	is(verify_signature($signed), 'pass', 'the signature verifies against the published key');
};

subtest '--keyfile signs with the key it names' => sub {
	# Run from a HOME with no key, so the only key in play is the one named.
	my ($status, $out, $err) = run_script($EMPTY_HOME,
		'--dry-run', '--keyfile' => $KEY, '--from' => 'alerts@example.org',
		'--domain' => 'example.org', '--selector' => 'selector1');

	is($status, 0, 'it exited 0');
	is($err, '', 'nothing on stderr') or diag($err);
	like($out, qr/\ADKIM-Signature: /, 'the message is signed');

	(my $signed = $out) =~ s/\n--- .*\z//s;
	is(verify_signature($signed), 'pass', 'and the signature verifies');
};

subtest '--plain prints a message with no signature at all' => sub {
	# Deliberately run with no key anywhere: --plain must not need one, since
	# it exists to show what the unsigned path looks like.
	my ($status, $out, $err) = run_script($EMPTY_HOME,
		'--plain', '--dry-run', '--from' => 'alerts@example.org', '--to' => 'webmaster@example.org');

	is($status, 0, 'it exited 0');
	is($err, '', 'and did not complain about the missing key') or diag($err);

	unlike($out, qr/DKIM-Signature/, 'there is no signature in it');
	like($out, qr/^From: alerts\@example\.org$/m, 'but the message is still there');
	like($out, qr/unsigned/, 'and it says the message went unsigned');
};

subtest 'with no key to be found it says so, and what to do about it' => sub {
	my ($status, $out, $err) = run_script($EMPTY_HOME,
		'--dry-run', '--from' => 'alerts@example.org', '--to' => 'webmaster@example.org');

	isnt($status, 0, 'it failed rather than printing an unsigned message');
	is($out, '', 'so no message was printed');

	like($err, qr/No DKIM key found/, 'it said there was no key');
	like($err, qr/--keyfile/, 'and how to name one');
	like($err, qr/--plain/, 'and how to send unsigned on purpose');
};

subtest 'a key that cannot be read is reported as such' => sub {
	my $unreadable = File::Spec->catfile($TMP, 'not-there.private');

	my ($status, $out, $err) = run_script($EMPTY_HOME,
		'--dry-run', '--keyfile' => $unreadable, '--from' => 'alerts@example.org');

	isnt($status, 0, 'it failed');
	is($out, '', 'and printed no message');
	like($err, qr/Cannot read \Q$unreadable\E/, 'naming the file it could not read');
};

done_testing();
