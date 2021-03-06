#!./perl

BEGIN {
    chdir 't' if -d 't';
    @INC = '../lib';
    require './test.pl';
}

use strict;
use warnings;
use Config;

BEGIN {
    if (! -c "/dev/null") {
        print "1..0 # Skip: no /dev/null\n";
        exit 0;
    }

    my $dev_tty = '/dev/tty';
    $dev_tty = 'TT:' if ($^O eq 'VMS');
    if (! -c $dev_tty) {
        print "1..0 # Skip: no $dev_tty\n";
        exit 0;
    }
    if ($ENV{PERL5DB}) {
        print "1..0 # Skip: \$ENV{PERL5DB} is already set to '$ENV{PERL5DB}'\n";
        exit 0;
    }
}

plan(11);

my $rc_filename = '.perldb';

sub rc {
    open my $rc_fh, '>', $rc_filename
        or die $!;
    print {$rc_fh} @_;
    close ($rc_fh);

    # overly permissive perms gives "Must not source insecure rcfile"
    # and hangs at the DB(1> prompt
    chmod 0644, $rc_filename;
}

sub _slurp
{
    my $filename = shift;

    open my $in, '<', $filename
        or die "Cannot open '$filename' for slurping - $!";

    local $/;
    my $contents = <$in>;

    close($in);

    return $contents;
}

my $out_fn = 'db.out';

sub _out_contents
{
    return _slurp($out_fn);
}

{
    my $target = '../lib/perl5db/t/eval-line-bug';

    rc(
        <<"EOF",
    &parse_options("NonStop=0 TTY=db.out LineInfo=db.out");

    sub afterinit {
        push(\@DB::typeahead,
            'b 23',
            'n',
            'n',
            'n',
            'c', # line 23
            'n',
            "p \\\@{'main::_<$target'}",
            'q',
        );
    }
EOF
    );

    {
        local $ENV{PERLDB_OPTS} = "ReadLine=0";
        runperl(switches => [ '-d' ], progfile => $target);
    }
}

like(_out_contents(), qr/sub factorial/,
    'The ${main::_<filename} variable in the debugger was not destroyed'
);

{
    local $ENV{PERLDB_OPTS} = "ReadLine=0";
    my $output = runperl(switches => [ '-d' ], progfile => '../lib/perl5db/t/lvalue-bug');
    like($output, qr/foo is defined/, 'lvalue subs work in the debugger');
}

{
    local $ENV{PERLDB_OPTS} = "ReadLine=0 NonStop=1";
    my $output = runperl(switches => [ '-d' ], progfile => '../lib/perl5db/t/symbol-table-bug');
    like($output, qr/Undefined symbols 0/, 'there are no undefined values in the symbol table');
}

SKIP: {
    if ( $Config{usethreads} ) {
        skip('This perl has threads, skipping non-threaded debugger tests');
    } else {
        my $error = 'This Perl not built to support threads';
        my $output = runperl( switches => [ '-dt' ], stderr => 1 );
        like($output, qr/$error/, 'Perl debugger correctly complains that it was not built with threads');
    }

}
SKIP: {
    if ( $Config{usethreads} ) {
        local $ENV{PERLDB_OPTS} = "ReadLine=0 NonStop=1";
        my $output = runperl(switches => [ '-dt' ], progfile => '../lib/perl5db/t/symbol-table-bug');
        like($output, qr/Undefined symbols 0/, 'there are no undefined values in the symbol table when running with thread support');
    } else {
        skip("This perl is not threaded, skipping threaded debugger tests");
    }
}


# Test [perl #61222]
{
    rc(
        <<'EOF',
        &parse_options("NonStop=0 TTY=db.out LineInfo=db.out");

        sub afterinit {
            push(@DB::typeahead,
                'm Pie',
                'q',
            );
        }
EOF
    );

    my $output = runperl(switches => [ '-d' ], stderr => 1, progfile => '../lib/perl5db/t/rt-61222');
    unlike(_out_contents(), qr/INCORRECT/, "[perl #61222]");
}



# Test for Proxy constants
{
    rc(
        <<'EOF',

&parse_options("NonStop=0 ReadLine=0 TTY=db.out LineInfo=db.out");

sub afterinit {
    push(@DB::typeahead,
        'm main->s1',
        'q',
    );
}

EOF
    );

    my $output = runperl(switches => [ '-d' ], stderr => 1, progfile => '../lib/perl5db/t/proxy-constants');
    is($output, "", "proxy constant subroutines");
}

# Testing that we can set a line in the middle of the file.
{
    rc(<<'EOF');
&parse_options("NonStop=0 TTY=db.out LineInfo=db.out");

sub afterinit {
    push (@DB::typeahead,
    'b ../lib/perl5db/t/MyModule.pm:12',
    'c',
    q/do { use IO::Handle; STDOUT->autoflush(1); print "Var=$var\n"; }/,
    'c',
    'q',
    );

}
EOF

    my $output = runperl(switches => [ '-d', '-I', '../lib/perl5db/t', ], stderr => 1, progfile => '../lib/perl5db/t/filename-line-breakpoint');

    like($output, qr/
        ^Var=Bar$
            .*
        ^In\ MyModule\.$
            .*
        ^In\ Main\ File\.$
            .*
        /msx,
        "Can set breakpoint in a line in the middle of the file.");
}


# [perl #66110] Call a subroutine inside a regex
{
    local $ENV{PERLDB_OPTS} = "ReadLine=0 NonStop=1";
    my $output = runperl(switches => [ '-d' ], stderr => 1, progfile => '../lib/perl5db/t/rt-66110');
    like($output, "All tests successful.", "[perl #66110]");
}

# taint tests

{
    local $ENV{PERLDB_OPTS} = "ReadLine=0 NonStop=1";
    my $output = runperl(switches => [ '-d', '-T' ], stderr => 1,
        progfile => '../lib/perl5db/t/taint');
    chomp $output if $^O eq 'VMS'; # newline guaranteed at EOF
    is($output, '[$^X][done]', "taint");
}

# Testing that we can set a breakpoint
{
    rc(<<'EOF');
&parse_options("NonStop=0 TTY=db.out LineInfo=db.out");

sub afterinit {
    push (@DB::typeahead,
    'b 6',
    'c',
    q/do { use IO::Handle; STDOUT->autoflush(1); print "X={$x}\n"; }/,
    'c',
    'q',
    );

}
EOF

    my $output = runperl(switches => [ '-d', ], stderr => 1, progfile => '../lib/perl5db/t/breakpoint-bug');

    like($output, qr/
        X=\{Two\}
        /msx,
        "Can set breakpoint in a line.");
}



# clean up.

END {
    1 while unlink ($rc_filename, $out_fn);
}
