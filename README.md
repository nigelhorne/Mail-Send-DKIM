# Mail::Send::DKIM

## Name

Mail::Send::DKIM - sign a message with DKIM and hand it to sendmail

## Version

0.002.0

## Synopsis

```perl
    use Mail::Send::DKIM;

    my $dkim = Mail::Send::DKIM->new(
            domains => ['example.org'],
            keydir => "$ENV{HOME}/dkim",
    );

    my $signed = $dkim->sign($message);
    $message = $signed if(defined($signed));

    exit($dkim->send($message, '-t', '-f', 'alerts@example.org'));
```

## Description

Signs a message with DKIM when its `From:` domain is one this host signs for,
and hands it to sendmail with whatever arguments sendmail should have.  The
signed form is `rsa-sha256` with `relaxed` canonicalization, which is the
shape receiving sites expect.

The signature covers the message in the form DKIM defines, where every line
ends CRLF.  What is handed to sendmail is the local form instead: LF line
endings, and no carriage return anywhere, whatever arrived.  A CR would be data
to the MTA that keeps the message - Postfix and Exim both write the CRLF of
SMTP themselves - so a message that had travelled with CRLF in it would reach
the receiver with the CRs doubled and fail the signature it had just been given.

Nothing here dies because a key is missing: signing either produces a signed
message or produces nothing and says why on standard error, so a caller can
always fall back to sending the message as it is.

## Platforms

Windows is not supported.  [Mail::DKIM](https://metacpan.org/pod/Mail%3A%3ADKIM) needs [Crypt::OpenSSL::RSA](https://metacpan.org/pod/Crypt%3A%3AOpenSSL%3A%3ARSA), and that
module and its prerequisites, [Crypt::OpenSSL::Random](https://metacpan.org/pod/Crypt%3A%3AOpenSSL%3A%3ARandom) and
[Crypt::OpenSSL::Bignum](https://metacpan.org/pod/Crypt%3A%3AOpenSSL%3A%3ABignum), do not link on Windows: Strawberry Perl's static
OpenSSL needs the `crypt32` library, which their `Makefile.PL` files do not
ask for.  `Makefile.PL` stops with `OS unsupported` there, rather than failing
part-way through the install.

## Environment

**DKIM\_DOMAINS**, **DKIM\_KEYDIR**, **DKIM\_SELECTOR**, **DKIM\_KEYFILE** and
**SENDMAIL** are read by **new** when the corresponding option is not given, so
the command line programs needs no configuration of its own.

## Programs

The distribution is named after this module and installs four programs with
it, each with a page of its own: `perldoc bin/mail-dkim`,
`perldoc bin/dmarc-report.pl`, `perldoc bin/dmarc-check-mail.pl` and
`perldoc bin/dmarc-weekly.sh` in a checkout, and the same pages as manual
pages once installed.

- [mail-dkim](https://github.com/nigelhorne/Mail-Send-DKIM/blob/master/bin/mail-dkim)

    The front end to this module: a message on standard input is signed when its
    `From:` domain is one named in `DKIM_DOMAINS`, and handed to sendmail(1) with
    the arguments it was given.  Put it where a script or a crontab calls sendmail
    and the mail is signed without the script being changed.  Its page has the
    environment variables, the key layout and the exit status.

- [dmarc-report](https://github.com/nigelhorne/Mail-Send-DKIM/blob/master/bin/dmarc-report.pl)

    Reads a directory of DMARC aggregate reports and says who sent mail for each
    domain, marking every source that is not an expected one (`DMARC_EXPECTED`),
    every expected one whose mail did not authenticate, and every message that was
    quarantined or rejected by policy despite passing.  The exit status is non-zero
    when anything needs looking at.  Its page has the options.

- [dmarc-weekly.sh](https://github.com/nigelhorne/Mail-Send-DKIM/blob/master/bin/dmarc-weekly.sh)

    The cron wrapper around it: silent when the week is clean, a mail with the full
    output when it is not, and the reports moved aside to an archive afterwards.
    `DRY_RUN=1` rehearses a run and `--crontab` prints the line to paste into a
    crontab; see ["A CRONTAB ENTRY"](#a-crontab-entry) below.

- [dmarc-check-mail.pl](https://github.com/nigelhorne/Mail-Send-DKIM/blob/master/bin/dmarc-check-mail.pl)

    Sends one message, signed with this module, to a mailbox that can be read, so
    that the `Authentication-Results` header at the far end shows what receivers
    make of this host's mail before the DMARC policy is tightened.  `--plain`
    sends the same message unsigned, which is what a cron job without the module
    looks like.

The three DMARC programs are the reason the module exists: they report on the
mail it signs, and the weekly one sends its own report through it.

## Methods

### **New** %Options

- `domains`

    The domains to sign for, either an array reference or a string of them
    separated by commas or spaces.  Defaults to `$ENV{DKIM_DOMAINS}`.  A message
    from any other domain is left alone.

- `keydir`

    Where the private keys are.  Defaults to `$ENV{DKIM_KEYDIR}`, or `~/dkim`.
    The value is used as it stands: a relative path is taken from the working
    directory, and `~` is not expanded - the shell does that, and only when the
    assignment is written unquoted.

- `selector`

    The selector the key is published under, which names the key file
    `<keydir>/<selector>.private`.  Defaults to `$ENV{DKIM_SELECTOR}`; with
    neither set, the key file's own name is the selector when **keyfile** is given,
    and otherwise the only `*.private` file in **keydir** is used and its name is
    the selector.

- `keyfile`

    The private key to sign with, when it does not live at
    `<keydir>/<selector>.private` - a tester given one key to try, for
    instance.  Defaults to `$ENV{DKIM_KEYFILE}`.  It is used as it stands, and
    the selector comes from its name unless one is given.

- `sendmail`

    The program **send** hands the message to.  Defaults to `$ENV{SENDMAIL}`, or
    `/usr/sbin/sendmail`.

- `messages`

    A hash reference of message formats that replace or add to the ones this
    module speaks with, keyed by message key, for a language other than English or
    wording of your own.  See **i18n** for the format.  Because **new** reads its
    options through [Object::Configure](https://metacpan.org/pod/Object%3A%3AConfigure), the same hash can come from a
    configuration file.

#### Purpose

Builds the signer.  No file is read and no program is run here, so a mistake
in **keydir** or **keyfile** shows when a message is signed, not when the object
is made.

#### Example

```perl
    # Everything from the environment: DKIM_DOMAINS, DKIM_KEYDIR, ...
    my $dkim = Mail::Send::DKIM->new();

    # Everything given, a list of domains, a named key and a test sendmail
    my $dkim = Mail::Send::DKIM->new(
            domains => 'example.org, example.net',
            keyfile => '/etc/dkim/2026.private',
            sendmail => '/usr/local/bin/capture-sendmail',
    );

    # A message in another language
    my $dkim = Mail::Send::DKIM->new(
            messages => { sendmail_failed => 'sendmail %{sendmail}s: %{os_error}s' },
    );
```

#### Api Specification

##### Input (Params::Validate::Strict)

```perl
    {
            domains => { type => ['string', 'arrayref'], optional => 1 },
            keydir => { type => 'string', optional => 1 },
            selector => { type => 'string', optional => 1 },
            keyfile => { type => 'string', optional => 1 },
            sendmail => { type => 'string', optional => 1 },
            home => { type => 'string', optional => 1 },
            messages => { type => 'hashref', optional => 1 },
    }
```

Options not listed are ignored.  The options may be given as a hash or as a
hash reference.

##### Output (Return::Set)

```perl
    { type => 'object', isa => 'Mail::Send::DKIM' }
```

#### Messages

An option of the wrong type is refused with the message of
[Params::Validate::Strict](https://metacpan.org/pod/Params%3A%3AValidate%3A%3AStrict), which names the option.  Nothing else is said.

#### Formal Specification

```
    ┌─ New ───────────────────────────────────────────────
    │ opts? : STRING ⇸ VALUE
    │ self! : Signer
    ├─────────────────────────────────────────────────────
    │ self!.domains  = { lower(d) | d ∈ split(opts?.domains ∨ DKIM_DOMAINS) ∧ d ≠ "" }
    │ self!.keydir   = opts?.keydir ∨ DKIM_KEYDIR ∨ home ⁀ "/dkim"
    │ self!.sendmail = opts?.sendmail ∨ SENDMAIL ∨ "/usr/sbin/sendmail"
    │ self!.selector, self!.keyfile follow the same rule, and may be absent
    └─────────────────────────────────────────────────────
```

#### Pseudocode

```
    options = get_params(args)
    options = Object::Configure(options)       # config files, environment
    options = validate(options, NEW_SCHEMA)    # croak on a wrong type
    home    = options.home or $HOME or passwd entry or "."
    domains = split(options.domains or $DKIM_DOMAINS), lower-cased, as a set
    messages = defaults overlaid with options.messages
    return object(domains, keydir, selector, keyfile, sendmail, messages)
```

### **Sign** $Message

Returns the message with a `DKIM-Signature` header added, or `undef` when
there is nothing to do or nothing that can be done: the domain is not one of
**domains**, there is no `From:` header, no key can be found or read, or the
signer failed.  The reasons are warnings on standard error; the message itself
is never altered in the undef case, so the caller sends it unchanged.
Carriage returns are folded to LF on the way, so what comes back is in the
local form.

#### Purpose

Signs the message when, and only when, a key for its `From:` domain can be
found and used.  Nothing is raised for a failure to sign: the caller sends the
message as it is.

#### Example

```perl
    my $signed = $dkim->sign($message);
    $message = $signed if(defined($signed));
```

#### Api Specification

##### Input (Params::Validate::Strict)

```perl
    { message => { type => 'string' } }
```

An undefined message is treated as an empty one, which has no `From:`.  It
may be given positionally or as `message => $text`.

##### Output (Return::Set)

```perl
    { type => 'string', optional => 1 }
```

The signed message in the local form, or `undef`.

#### Messages

```
    Message key       Text                                      Meaning and resolution
    key_unreadable    no readable key at FILE; sending DOMAIN   The key file is absent or not
                      unsigned                                  readable: fix the path or the mode.
    sign_failed       cannot sign for DOMAIN (REASON); ...      Mail::DKIM refused the key or
                                                                the message: see REASON.
    keydir_unreadable, keys_ambiguous                           As for selector, below.
```

Each is a warning, and the return is `undef`.

#### Formal Specification

```
    ┌─ Sign ──────────────────────────────────────────────
    │ ΞSigner
    │ message? : STRING
    │ signed!  : STRING ∪ {⊥}
    ├─────────────────────────────────────────────────────
    │ d = fromDomain(message?)
    │ d ∈ domains ∧ keyUsable(d) ∧ signerSucceeds(d) ⇒
    │     signed! = signature(d, crlf(message?)) ⁀ "\n" ⁀ local(message?)
    │ ¬(d ∈ domains ∧ keyUsable(d) ∧ signerSucceeds(d)) ⇒ signed! = ⊥
    └─────────────────────────────────────────────────────
```

### **Send** $Message, @Arguments

Pipes the message to **sendmail** with the arguments given - `-t`, `-f` and
the rest are sendmail's own - and returns `0` when sendmail accepted the
message, sendmail's exit status when it did not, and `1` when sendmail cannot
be run at all.  The message is normalised to LF first, so nothing that arrived
with CRLF - signed or passed through unsigned - carries a carriage return to
the MTA.

#### Purpose

Delivers the message to the local MTA and reports what the MTA said.

#### Example

```perl
    my $status = $dkim->send($message, '-t', '-f', 'alerts@example.org');
    exit($status);
```

#### Api Specification

##### Input (Params::Validate::Strict)

```perl
    {
            message => { type => 'string' },
            arguments => { type => 'arrayref', optional => 1 },   # the rest of @_
    }
```

##### Output (Return::Set)

```perl
    { type => 'integer', min => 0, max => 255 }
```

#### Messages

```
    Message key        Meaning and resolution
    sendmail_failed    The sendmail program could not be started (not found,
                       not executable): fix the sendmail option or SENDMAIL.
                       The return is 1.
```

A sendmail that exits before it has read the whole message does not stop the
caller with SIGPIPE: its exit status is returned.

#### Formal Specification

```
    ┌─ Send ──────────────────────────────────────────────
    │ Σ Signer
    │ message? : STRING;  args? : seq STRING;  status! : ℕ
    ├─────────────────────────────────────────────────────
    │ ¬runnable(sendmail)                      ⇒ status! = 1
    │ runnable(sendmail) ∧ accepted(local(message?)) ⇒ status! = 0
    │ runnable(sendmail) ∧ ¬accepted(local(message?)) ⇒
    │     status! = exitStatus(sendmail) ∨ 1  (1 when that status would be 0)
    └─────────────────────────────────────────────────────
```

#### Pseudocode

```
    ignore SIGPIPE's default action (a handler, so sendmail does not inherit it)
    open a pipe to sendmail with the arguments, as a list so no shell is involved
    if that fails: warn sendmail_failed, return 1
    write the local form of the message, then close the pipe
    if the write and the close both succeeded: return 0
    return sendmail's exit status, or 1 when that would have been 0
```

### **Log\_Send** $Message, @Arguments

Records in syslog, under the identity `mail-dkim` and the `mail` facility,
the sender, the recipients and the subject of a message that has been sent.
The arguments are those given to **send**.  The sender is the address after
`-f` when there is one, and the address in the `From:` header otherwise.  The
recipients are the arguments that are not options and, when `-t` was given,
the addresses in the `To:`, `Cc:` and `Bcc:` headers too.  A value that is
missing is logged as `-`, and control characters in the subject are replaced
by spaces so that a message cannot forge a log line.

Returns true when the line was written.  Logging never stands between a message
and its recipient: a syslog that cannot be reached is a warning, and a false
return.

#### Purpose

Leaves a trace, in the system log, of every message that was passed on.

#### Example

```
    $dkim->log_send($message, '-t', '-f', 'alerts@example.org')
            if($dkim->send($message, '-t', '-f', 'alerts@example.org') == 0);
```

#### Api Specification

##### Input (Params::Validate::Strict)

```perl
    {
            message => { type => 'string' },
            arguments => { type => 'arrayref', optional => 1 },
    }
```

##### Output (Return::Set)

```perl
    { type => 'boolean' }
```

#### Messages

```
    Message key        Meaning and resolution
    syslog_failed      openlog or syslog failed: check that a syslog daemon is
                       running and its socket is reachable.  The return is 0.
```

#### Formal Specification

```
    ┌─ LogSend ───────────────────────────────────────────
    │ message? : STRING;  args? : seq STRING;  written! : 𝔹
    ├─────────────────────────────────────────────────────
    │ sender     = valueOf(-f, args?) ∨ firstAddress(From)
    │ recipients = nonOptions(args?) ⁀ (headerAddresses(To, Cc, Bcc) ◁ "-t" ∈ flags(args?))
    │ line = "sender=" ⁀ (sender ∨ "-") ⁀ " recipient=" ⁀ (join "," recipients ∨ "-")
    │        ⁀ " subject=" ⁀ (subject ∨ "-")        (control characters made spaces)
    │ written! = line reached syslog
    └─────────────────────────────────────────────────────
```

#### Pseudocode

```
    parse the arguments into (sender, recipients, whether -t was given), where an
        option that takes a value, attached or separate, never yields a recipient
    parse the headers of the message once
    sender   = the -f value, else the first address of From
    if -t was given: add the addresses of To, Cc and Bcc to the recipients
    subject  = the Subject, or "-"
    make the line, replace control characters by spaces
    write it to syslog; if that fails, warn syslog_failed and return 0
    return 1
```

### **From\_Domain** $Message

The domain of the address in the first `From:` header, in lower case, or
`undef` when there is no such header.  Folded headers and display names are
understood.

#### Purpose

Says whose domain a message claims to be from, which is what decides whether
it is signed.  The address is read by [Mail::Address](https://metacpan.org/pod/Mail%3A%3AAddress), so quoted display
names, comments and groups are handled by a parser that has seen them before.
Only a plain host name is accepted as a domain (letters, digits, dots and
hyphens).

#### Example

```perl
    my $domain = Mail::Send::DKIM::from_domain($message);   # 'example.org'
    my $same = $dkim->from_domain($message);
```

#### Api Specification

##### Input (Params::Validate::Strict)

```perl
    { message => { type => 'string' } }
```

It may be called as a function or as a method.

##### Output (Return::Set)

```perl
    { type => 'string', optional => 1, matches => qr/\A[a-z0-9.-]+\z/ }
```

#### Messages

None: a message without a usable From: is not an error, the answer is `undef`.

#### Formal Specification

```
    ┌─ FromDomain ────────────────────────────────────────
    │ message? : STRING;  domain! : STRING ∪ {⊥}
    ├─────────────────────────────────────────────────────
    │ first(From, headers(message?)) = ⊥ ⇒ domain! = ⊥
    │ a = firstAddress(first(From, headers(message?)))
    │ host(a) matches [A-Za-z0-9.-]+ ⇒ domain! = lower(host(a))
    │ otherwise domain! = ⊥
    └─────────────────────────────────────────────────────
```

### **Selector**

The selector the message will be signed under: the one given to **new** or read
from `DKIM_SELECTOR`, otherwise the name of the **keyfile** when one is given,
otherwise the name of the only `*.private` file in **keydir**.  `undef` when it
cannot be decided - no key, or several keys and no name - and the reason is a
warning on standard error.  **sign** asks this before doing anything else.

#### Purpose

Settles which of the keys is to be used, once, in one place.

#### Example

```perl
    my $selector = $dkim->selector();
    die 'no usable key' unless(defined($selector));
```

#### Api Specification

##### Input (Params::Validate::Strict)

```
    {}
```

##### Output (Return::Set)

```perl
    { type => 'string', optional => 1 }
```

#### Messages

```
    Message key         Meaning and resolution
    keydir_unreadable   keydir cannot be opened: create it, or fix the mode or
                        the keydir option.
    keys_ambiguous      keydir holds no key, or more than one, and no selector
                        was named: add the key, or set DKIM_SELECTOR.
```

#### Formal Specification

```
    ┌─ Selector ──────────────────────────────────────────
    │ ΞSigner;  selector! : STRING ∪ {⊥}
    ├─────────────────────────────────────────────────────
    │ selector ≠ ⊥ ∧ selector ≠ ""    ⇒ selector! = selector
    │ keyfile ≠ ⊥ ∧ name(keyfile) ≠ "" ⇒ selector! = strip(name(keyfile))
    │ #privateKeys(keydir) = 1         ⇒ selector! = strip(the one)
    │ otherwise                          selector! = ⊥
    └─────────────────────────────────────────────────────
```

#### Pseudocode

```
    if a selector was given: return it
    if a key file was given: return its name without .private, .key or .pem
    list the *.private files in keydir (a warning and undef if it cannot be read)
    if there is not exactly one: warn, return undef
    return its name without .private
```

### **i18n** $Key, \\%Arguments

Returns the text of a message, in the language this object speaks, with the
arguments put in.  This is the one place any sentence is made, so a caller can
change every message by giving **new** a `messages` option.

A message is a format whose placeholders are named, `%{name}s` or
`%{name}d`, and which may carry the usual `sprintf` width and flags
(`%{name}-8s`).  It may instead be a hash of formats, from which one is chosen
by the arguments: `count` selects `zero`, `one` or `other` (`other` when
there is no better one), and `variant` - a grammatical gender, for instance -
selects the entry of that name, or `variant.one`, `variant.other` and so on
when the choice is both.  An argument a format asks for and was not given is an
error, not an empty string.

Croaks if `$key` is not a message that is defined.

#### Example

```perl
    my $text = $dkim->i18n('keys_ambiguous', { keydir => '/etc/dkim', count => 2 });
    # '... /etc/dkim holds 2 keys; name the selector to choose one'

    my $french = Mail::Send::DKIM->new(messages => {
            'keys_ambiguous' => {
                    'one' => '%{keydir}s contient %{count}d cle',
                    'other' => '%{keydir}s contient %{count}d cles',
            },
    });
```

#### Api Specification

##### Input (Params::Validate::Strict)

```perl
    {
            key => { type => 'string' },
            arguments => { type => 'hashref', optional => 1 },
    }
```

##### Output (Return::Set)

```perl
    { type => 'string' }
```

#### Messages

```
    Message key        Meaning and resolution
    unknown_message    The key is not in the catalogue: fix the caller, or add it to messages.
    missing_argument   A placeholder has no argument: pass it.
```

#### Formal Specification

```
    ┌─ I18n ──────────────────────────────────────────────
    │ ΞSigner;  key? : STRING;  args? : STRING ⇸ VALUE;  text! : STRING
    ├─────────────────────────────────────────────────────
    │ key? ∈ dom messages
    │ text! = format(choose(messages(key?), args?.count, args?.variant), args?)
    └─────────────────────────────────────────────────────
```

## A Crontab Entry

A job that sends mail from cron is where an unsigned message is least likely to
be noticed, so that is usually where this module earns its keep: the program
that ships with it, `mail-dkim`, is put where the job would have called
sendmail(1), and the job itself is not changed.

The weekly summary in this distribution is such a job, and its mail goes out
through `mail-dkim`.  A crontab line for it looks like this, with the values of
the machine it runs on:

```
    0 6 * * 1 DMARC_EXPECTED=192.0.2.10 MAIL_TO=alerts@example.org \
            PERL=/usr/bin/perl /usr/local/bin/dmarc-weekly.sh
```

The three settings are not optional, because cron starts a job with almost no
environment.  `DMARC_EXPECTED` is what makes a sender nobody expected a
finding, and the run stops with a usage error without it, since guessing would
excuse every sender.  `MAIL_TO` is where a week that needs looking at is
mailed, and is also the address the alert is sent as unless `MAIL_FROM` says
otherwise.  `PERL` has to be an absolute path to a perl that has
`XML::PP`, as cron's `PATH` usually holds only the system one; `--crontab`
fills it in with the first perl on the machine that can load the module.
`DMARC_DIR` and `DMARC_ARCHIVE_DIR` are left out of the line because they
default to `~/Downloads` and `~/dmarc-archive`.

`dmarc-weekly.sh --crontab` prints that line with the path and the perl filled
in for the machine it runs on, which is more use than an example carrying
somebody else's values; for that reason no example crontab file is shipped or
installed.  A job of your own takes the same shape with `mail-dkim` in place of
the wrapper: `DKIM_DOMAINS` and `DKIM_KEYDIR` say what to sign for, and the
arguments given to it are passed to sendmail(1) as they are.

## Limitations

These are the weaknesses of the design, set down so that they are chosen rather
than found.

- One key for every domain

    A single selector and key serve every domain in `domains`.  A host that signs
    for several customers with a key each cannot say so; it needs one object per
    key.

- Only the From: domain is looked at

    A message is signed when its first `From:` domain is ours.  A message with two
    `From:` headers is signed with the first one's domain, and the signature does
    not oversign the header, so a second `From:` can be added later without
    breaking it.  Refusing such a message would be the safer rule.

- The key is not checked

    That the key file is readable is checked; its mode is not, and nor is whether
    the public half is published in DNS.  A key that is readable by others is not
    reported.

- The whole message is in memory

    The message is a string, held two or three times over while it is signed.  A
    very large message costs that much memory; a stream would not.

- Sending cannot be interrupted

    **send** waits for sendmail as long as sendmail takes.  There is no timeout.

- A bare carriage return is removed

    The local form has no CR at all, as specified, so a lone CR inside a line is
    deleted instead of becoming a line break, and the two halves of the line join.

- Addresses are RFC 822

    [Mail::Address](https://metacpan.org/pod/Mail%3A%3AAddress) is a lenient RFC 822 parser.  Internationalised addresses and
    domain names are not understood, and a From: domain that is not plain ASCII is
    treated as having none.

- The messages are English, with English plurals

    The catalogue is English.  `count` knows `zero`, `one` and `other`, which is
    not enough for languages with more plural forms; a translation that needs them
    would be better served by [Locale::Maketext](https://metacpan.org/pod/Locale%3A%3AMaketext), which this module does not use
    to avoid a language class for six sentences.  The text of an operating system
    error follows the locale of the process that raised it, which this module does
    not control.

- log\_send reads sendmail's options approximately

    **log\_send** knows which of sendmail's options take a value, but not every
    MTA's.  An option it has not heard of that takes a value would have that value
    logged as a recipient.

- rsa-sha256 only

    There is one signature, `rsa-sha256` with `relaxed` canonicalization.  Ed25519
    and a second signature are not offered.

- Windows

    ["PLATFORMS"](#platforms) applies.

- Private means private

    The helpers whose names begin with an underscore are enforced private
    ([Sub::Private](https://metacpan.org/pod/Sub%3A%3APrivate)) and the message writer is protected ([Sub::Protected](https://metacpan.org/pod/Sub%3A%3AProtected)), at
    the cost of a check on every call.  A subclass cannot replace a private helper.

## See Also

- [Configure an Object at Runtime](https://metacpan.org/pod/Object%3A%3AConfigure)
- [Test Dashboard](https://nigelhorne.github.io/Mail-Send-DKIM/coverage/)

[Mail::DKIM::Signer](https://metacpan.org/pod/Mail%3A%3ADKIM%3A%3ASigner), which does the signing underneath, and ["PROGRAMS"](#programs)
above for the programs this distribution installs beside the module.

## Author

Nigel Horne, `<njh at nigelhorne.com>`

## Licence and Copyright

Copyright 2026 Nigel Horne.

Usage is subject to the GPL2 licence terms.
If you use it,
please let me know.
