#!/usr/bin/env perl
#
# dmarc-check-mail - send one message from this host to a mailbox you can read,
# so that you can see whether mail from here authenticates before tightening
# the DMARC policy.
#
# The message is signed with Mail::Send::DKIM, the module bin/mail-dkim uses,
# so a test that signed some other way would test something other than the real
# path.  --plain sends it unsigned through sendmail(1) instead, which is
# what cron does, so both outcomes can be seen in the same mailbox.
#
# Usage:
#	dmarc-check-mail.pl                     # sign and send to DMARC_TEST_TO
#	dmarc-check-mail.pl --dry-run           # sign, print the message, send nothing
#	dmarc-check-mail.pl --plain             # unsigned, the way cron sends
#	dmarc-check-mail.pl --keyfile ~/dkim/selector1.private
#
# The message carries a token in the subject and body; find it in the mailbox, choose
# "Show original", and read the Authentication-Results header.

use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use File::Spec;
use POSIX qw(strftime);
use Sys::Hostname qw(hostname);

use FindBin qw($Bin);
use lib grep { -d } "$Bin/../lib";

my %opt = (
	'to' => $ENV{'DMARC_TEST_TO'} || 'nigel@example.org',
	'from' => $ENV{'DMARC_TEST_FROM'} || 'alerts@example.org',
	'domain' => $ENV{'DMARC_TEST_DOMAIN'} || 'example.org',
	'selector' => $ENV{'DMARC_TEST_SELECTOR'} || 'selector1',
	'sendmail' => $ENV{'SENDMAIL'} || '/usr/sbin/sendmail',
	'keyfile' => $ENV{'DKIM_KEYFILE'},
	'plain' => 0,
	'dry-run' => 0,
	'save' => undef,
);

GetOptions(
	'to|t=s' => \$opt{'to'},
	'from|f=s' => \$opt{'from'},
	'domain=s' => \$opt{'domain'},
	'selector=s' => \$opt{'selector'},
	'keyfile|k=s' => \$opt{'keyfile'},
	'sendmail=s' => \$opt{'sendmail'},
	'plain' => \$opt{'plain'},
	'dry-run|n' => \$opt{'dry-run'},
	'save=s' => \$opt{'save'},
	'help|h' => sub { usage(0) },
) or usage(2);

usage(2) unless($opt{'to'} && $opt{'from'});
usage(2) if($opt{'from'} =~ /[\x00-\x20\x7f]/ || $opt{'from'} =~ /\A-/);

my $host = hostname();
my $token = sprintf('%s-%d', $host, time());
my $now = strftime('%Y-%m-%d %H:%M:%S %z', localtime());

# Sending unsigned from the signing path is a mistake worth stopping: the
# whole point is to see a signature arrive.  --plain asks for it deliberately.
my ($keyfile, $mailer);
if($opt{'plain'}) {
	$mailer = 'sendmail(1), unsigned';
} else {
	$keyfile = $opt{'keyfile'} || find_keyfile();
	if(!$keyfile) {
		my @candidates = candidate_keys();
		die "No DKIM key found: name one with --keyfile or set DKIM_KEYFILE.\n"
			. (@candidates ? 'Looked at: ' . join(', ', @candidates) . "\n" : '')
			. "Use --plain to send unsigned on purpose.\n";
	}
	die "Cannot read $keyfile\n" unless(-r $keyfile);
	# Loaded here rather than with use, so that --plain still works on a host
	# without Mail::DKIM: sending unsigned is exactly what it is for there.
	die "Mail::DKIM is not installed for $^X, so nothing can be signed.\n"
		. "Install it, or use --plain to send unsigned on purpose.\n"
		unless(eval { require Mail::DKIM::Signer; require Mail::Send::DKIM; 1 });
	$mailer = "Mail::Send::DKIM, signed with d=$opt{'domain'} s=$opt{'selector'}";
}

my $subject = "DKIM check from $host at $now";
my $body = <<"BODY";
This is a test message from $host at $now.

It was sent by $mailer.

Its only purpose is to show, in the headers at the far end, whether mail from
this host authenticates.  The token below is unique to this run, so the message
can be found again among others:

  $token

Nothing replies to it and nothing depends on it.
BODY

my $message = join('',
	"From: $opt{'from'}\n",
	"To: $opt{'to'}\n",
	"Subject: $subject\n",
	"Date: $now\n",
	"Message-ID: <$token\@$host>\n",
	"MIME-Version: 1.0\n",
	"Content-Type: text/plain; charset=utf-8\n",
	"Content-Transfer-Encoding: 8bit\n",
	"\n",
	$body,
);

# Sign first, then decide what to do with the result, so that what is printed,
# saved and sent are the same bytes - and so that a rehearsal exercises the
# signing rather than pretending to.
my $wire = $opt{'plain'} ? $message : sign($message);

if($opt{'save'}) {
	open(my $fh, '>', $opt{'save'}) or die "Cannot write $opt{'save'}: $!\n";
	print $fh $wire;
	close($fh) or die "Cannot close $opt{'save'}: $!\n";
	print "Message as sent is in $opt{'save'}\n\n";
}

if($opt{'dry-run'}) {
	print $wire;
	print "\n--- nothing was sent; run again without --dry-run ---\n";
	exit(0);
}

open(my $sendmail, '|-', $opt{'sendmail'}, '-t', '-f', $opt{'from'})
	or die "Cannot run $opt{'sendmail'}: $!\n";
print $sendmail $wire;
unless(close($sendmail)) {
	die "sendmail reported a failure; the message was not delivered.\n";
}

print "Sent to $opt{'to'} as $opt{'from'}\n";
print "  via       : $mailer\n";
print "  token     : $token\n\n";
print "In the mailbox, open that message and choose \"Show original\".  You want:\n";
print "  SPF:   pass  (ip= the sending host)\n";
print "  DKIM:  pass  (domain=$opt{'domain'}, selector=$opt{'selector'})\n";
print "  DMARC: pass\n\n";
print "If DKIM is missing, nothing downstream can pass: check that the key is\n";
print "the one published at $opt{'selector'}._domainkey.$opt{'domain'}, and that\n";
print "Mail::DKIM is installed for $^X.\n";

exit(0);

# One signing implementation for the repository: Mail::Send::DKIM, which is
# what bin/mail-dkim uses, so what this sends is what the site's mail looks
# like.  The message's own From: domain is allowed as well as --domain, so a
# test sent as a different address than the one being signed for still signs.
sub sign
{
	my $message = shift;

	require Mail::Send::DKIM;

	my $dkim = Mail::Send::DKIM->new(
		'domains' => [$opt{'domain'}, Mail::Send::DKIM::from_domain($message)],
		'keyfile' => $keyfile,
		'selector' => $opt{'selector'},
	);

	my $signed = $dkim->sign($message);
	return $signed if(defined($signed));

	# The module has already said what went wrong on standard error; this adds
	# what the tester knows and it does not: which key was meant.
	die "Cannot sign with $keyfile.\n"
		. "Check that it is the key published at $opt{'selector'}._domainkey.$opt{'domain'}.\n";
}

# The site's key is wherever the site keeps it; these are the places it has
# lived, so the common case needs no argument.
sub candidate_keys
{
	my @dirs = grep { defined } (
		$ENV{'HOME'} ? File::Spec->catdir($ENV{'HOME'}, 'dkim') : undef,
		$ENV{'HOME'} ? File::Spec->catdir($ENV{'HOME'}, '.dkim') : undef,
		$ENV{'HOME'} ? File::Spec->catdir($ENV{'HOME'}, 'lib', 'dkim') : undef,
	);

	my @keys;
	foreach my $dir (@dirs) {
		next unless(-d $dir);
		foreach my $name (glob(File::Spec->catfile($dir, '*'))) {
			next unless($name =~ /\.(?:private|key|pem)\z/);
			push @keys, $name;
		}
	}

	return @keys;
}

sub find_keyfile
{
	foreach my $key (candidate_keys()) {
		# A directory can hold keys for several domains; the selector names
		# the one this message must be signed with.
		return $key if($key =~ /\Q$opt{'selector'}\E/ || $key =~ /\Q$opt{'domain'}\E/);
	}

	return undef;
}

sub usage
{
	my $status = shift // 0;

	print <<"USAGE";
$0 - send one test message from this host, so its authentication can be read

Usage:
  $0 [options]

  --to ADDR         where to send it          (default $opt{'to'})
  --from ADDR       envelope and header From  (default $opt{'from'})
  --domain DOMAIN   the domain to sign for    (default $opt{'domain'})
  --selector SEL    the DKIM selector         (default $opt{'selector'})
  --keyfile FILE    the DKIM private key      (default: found under ~/dkim)
  --plain           send unsigned via sendmail(1), the way cron does
  --dry-run         sign the message, print it, send nothing
  --save FILE       also write the message, as it is sent, to FILE
  --sendmail PATH   sendmail to use           (default $opt{'sendmail'})
  --help            this text

Sent through Mail::Send::DKIM, the signer bin/mail-dkim uses, so that what
arrives is what the site's mail actually looks like.
USAGE

	exit($status);
}
