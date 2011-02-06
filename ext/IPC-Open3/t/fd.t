#!./perl

BEGIN {
    if (!PerlIO::Layer->find('perlio') || $ENV{PERLIO} eq 'stdio') {
	print "1..0 # Skip: not perlio\n";
	exit 0;
    }
}
use strict;
use warnings;

use Test::More tests => 4;
use Test::PerlRun 'perlrun';

# [perl #76474]
{
    my ($stdout, $stderr, $status)
	= perlrun(switches => ['-MIPC::Open3', '-w'],
		  code => 'open STDIN, q _Makefile_ or die $!; open3(q _<&1_, my $out, undef, $ENV{PERLEXE}, q _-e0_)',
		  );
    {
	local $::TODO = "Bogus warning in IPC::Open3::spawn_with_handles"
	    if $^O eq 'MSWin32';
	$stderr =~ s/(Use of uninitialized value.*Open3\.pm line \d+\.)\n//;
	is($1, undef, 'No bogus warning found');
    }

    is($stdout, '',
       'dup STDOUT in a child process by using its file descriptor');
    is($stderr, '', 'no errors');
    is($status, 0, 'clean exit');
}
