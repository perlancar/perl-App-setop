#!perl

use 5.010;
use strict;
use warnings;
use FindBin;

use File::chdir;
use File::Slurp::Tiny qw(write_file);
use File::Temp qw(tempdir);
use IPC::Cmd qw(run_forked);
use String::ShellQuote;
use Test::More 0.98;

BEGIN {
    if ($^O =~ /win/i) {
        plan skip_all => "run_forked() not available on Windows";
        exit 0;
    }
}

sub lines { join("", map {"$_\n"} @_) }

my ($tmpdir) = tempdir(CLEANUP => 1);
$CWD = $tmpdir;

write_file("f1", lines(1, 3, 2, 3));
write_file("f2", lines(2, 3, 4, 1, 1));
write_file("f3", lines(3, 4, 3, 5));

subtest "no operation -> error" => sub {
    test_setop(
        args     => [qw/f1 f2/],
        exitcode => 99,
    );
};

subtest "unknown operation -> error" => sub {
    test_setop(
        args     => [qw/--op foo f1 f2/],
        exitcode => 99,
    );
};

subtest "no file -> error" => sub {
    test_setop(
        args     => [qw/--union/],
        exitcode => 99,
    );
};

subtest "stdin specified twice -> error" => sub {
    test_setop(
        args     => [qw/--union - -/],
        input    => lines(1, 2, 3),
        exitcode => 99,
    );
};

subtest "union" => sub {
    test_setop(
        args    => [qw/--union -/],
        input   => lines(0, 1),
        output  => lines(0, 1),
    );
    test_setop(
        args    => [qw/--union - f1/],
        input   => lines(0, 1),
        output  => lines(0, 1, 3, 2),
    );
    test_setop(
        args    => [qw/--op union f1 f2/],
        output  => lines(1, 3, 2, 4),
    );
    test_setop(
        args    => [qw/--op union f1 f2 f3/],
        output  => lines(1, 3, 2, 4, 5),
    );
};

subtest "intersect" => sub {
    test_setop(
        args    => [qw/--intersect -/],
        input   => lines(0, 1),
        output  => lines(0, 1),
    );
    test_setop(
        args    => [qw/--intersect - f1/],
        input   => lines(0, 2, 1),
        output  => lines(2, 1),
    );
    test_setop(
        args    => [qw/--op intersect f1 f2/],
        output  => lines(1, 3, 2),
    );
    test_setop(
        args    => [qw/--op intersect f2 f1/],
        output  => lines(2, 3, 1),
    );
    test_setop(
        args    => [qw/--op intersect f2 f3/],
        output  => lines(3, 4),
    );
    test_setop(
        args    => [qw/-i f1 f2 f3/],
        output  => lines(3),
    );
};

subtest "diff" => sub {
    test_setop(
        args    => [qw/--diff -/],
        input   => lines(0, 1),
        output  => lines(0, 1),
    );
    test_setop(
        args    => [qw/--diff - f1/],
        input   => lines(0, 1),
        output  => lines(0),
    );
    test_setop(
        args    => [qw/--op diff f1 f2/],
        output  => lines(),
    );
    test_setop(
        args    => [qw/--op diff f2 f1/],
        output  => lines(4),
    );
    test_setop(
        args    => [qw/--op diff - f1 f2 f3/],
        input   => lines(6, 1, 0, 2, 3),
        output  => lines(6, 0),
    );
};

subtest "symdiff" => sub {
    test_setop(
        args    => [qw/--symdiff -/],
        input   => lines(0, 1),
        output  => lines(0, 1),
    );
    test_setop(
        args    => [qw/--symdiff - f1/],
        input   => lines(0, 1),
        output  => lines(0, 2),
    );
    test_setop(
        args    => [qw/--op symdiff f1 f2/],
        output  => lines(4),
    );
    test_setop(
        args    => [qw/--op symdiff f2 f1/],
        output  => lines(4),
    );
    test_setop(
        args    => [qw/--op symdiff - f1 f2 f3/],
        input   => lines(6, 1, 0, 2, 3),
        output  => lines(6, 0, 5),
    );
    test_setop(
        args    => [qw/--op symdiff f3 f2 f1 -/],
        input   => lines(6, 1, 0, 2, 3),
        output  => lines(5, 6, 0),
    );
};

DONE_TESTING:
done_testing;
$CWD = "/";

sub test_setop {
    my %args = @_;

    my @progargs = @{ $args{args} // [] };
    my $name = $args{name} // join(" ", @progargs);
    subtest $name => sub {
        my $expected_exit = $args{exitcode} // 0;
        my %runopts;
        $runopts{child_stdin} = $args{input} if defined $args{input};
        # run_forked() doesn't accept arrayref command, lame
        my $cmd = join(
            " ",
            map {shell_quote($_)}
                ($^X, "$FindBin::Bin/../bin/setop", @progargs));
        note "cmd: $cmd";
        my $res = run_forked($cmd, \%runopts);

        is($res->{exit_code}, $expected_exit,
           "exit code = $expected_exit") or do {
               if ($expected_exit == 0) {
                   diag explain $res;
               }
           };

        if (defined $args{output}) {
            is($res->{stdout}, $args{output}, "output");
        }
    };
}
