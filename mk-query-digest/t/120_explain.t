#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use Sandbox;
use MaatkitTest;
use VersionParser;
# See 101_slowlog_analyses.t for why we shift.
shift @INC;  # our unshift (above)
shift @INC;  # MaatkitTest's unshift
shift @INC;  # Sandbox

require "$trunk/mk-query-digest/mk-query-digest";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $vp  = new VersionParser();
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 5;
}

my $sample = "mk-query-digest/t/samples/";

$dbh->do('drop database if exists food');
$dbh->do('create database food');
$dbh->do('use food');
$dbh->do('create table trees (fruit varchar(24), unique index (fruit))');

my $output = '';
my @args   = ('--explain', 'h=127.1,P=12345,u=msandbox,p=msandbox,D=food', qw(--report-format=query_report --limit 10));

# The table has no rows so EXPLAIN will return NULL for most values.
ok(
   no_diff(
      sub { mk_query_digest::main(@args,
         "$trunk/common/t/samples/slow007.txt") },
      ($sandbox_version ge '5.1' ? "$sample/slow007_explain_1-51.txt"
                                 : "$sample/slow007_explain_1.txt")
   ),
   'Analysis for slow007 with --explain, no rows',
);

# Normalish output from EXPLAIN.
$dbh->do('insert into trees values ("apple"),("orange"),("banana")');

ok(
   no_diff(
      sub { mk_query_digest::main(@args,
         "$trunk/common/t/samples/slow007.txt") },
      ($sandbox_version ge '5.1' ? "$sample/slow007_explain_2-51.txt"
                                 : "$sample/slow007_explain_2.txt")
   ),
   'Analysis for slow007 with --explain',
);

# #############################################################################
# Issue 1141: Add "spark charts" to mk-query-digest profile
# #############################################################################
ok(
   no_diff(
      sub { mk_query_digest::main(@args,
         "$trunk/common/t/samples/slow007.txt", qw(--report-format profile)) },
      "$sample/slow007_explain_4.txt",
   ),
   'EXPLAIN sparkline in profile'
);

# #############################################################################
# Failed EXPLAIN.
# #############################################################################
$dbh->do('drop table trees');

ok(
   no_diff(
      sub { mk_query_digest::main(@args,
         '--report-format', 'query_report,profile',
         "$trunk/common/t/samples/slow007.txt") },
      "mk-query-digest/t/samples/slow007_explain_3.txt",
      trf => "sed 's/at [a-zA-Z\/\-]\\+ line [0-9]\\+/at line ?/'",
   ),
   'Analysis for slow007 with --explain, failed',
);


# #############################################################################
# Issue 1196: mk-query-digest --explain is broken
# #############################################################################
$sb->load_file('master', "mk-query-digest/t/samples/issue_1196.sql");

ok(
   no_diff(
      sub { mk_query_digest::main(@args,
         '--report-format', 'profile,query_report',
         "$trunk/mk-query-digest/t/samples/issue_1196.log",)
      },
      ($sandbox_version ge '5.1'
         ? "mk-query-digest/t/samples/issue_1196-output.txt"
         : "mk-query-digest/t/samples/issue_1196-output-5.0.txt"),
   ),
   "--explain sparkline uses event db and doesn't crash ea (issue 1196"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
