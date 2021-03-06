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

use MaatkitTest;
use Sandbox;
shift @INC;  # These two shifts are required for tools that use base and
shift @INC;  # derived classes.  See mk-query-digest/t/101_slowlog_analyses.t
shift @INC;
require "$trunk/mk-query-advisor/mk-query-advisor";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

my $output = "";
my $cnf    = "/tmp/12345/my.sandbox.cnf";
my @args   = ('-F', $cnf, '-D', 'test');

$sb->create_dbs($dbh, ['test']);
$sb->load_file('master', "mk-query-advisor/t/samples/issue-950.sql", "test");

my $query = "select c from L left join R on l_id = r_id where r_other is null";
$output = output(
  sub { mk_query_advisor::main(@args, '--query', $query) },
);
like(
   $output,
   qr/JOI.004/,
   "JOI.004"
);

$output = output(
  sub { mk_query_advisor::main(@args, '--query', $query,
   '--no-show-create-table') },
);
is(
   $output,
   "",
   "JOI.004 doesn't work with --no-show-create-table"
);

$output = output(
  sub { mk_query_advisor::main(@args, '--query', $query,
   '--no-show-create-table', '--print-all') },
);
is(
   $output,
   "
# Profile
# Query ID           NOTE WARN CRIT Item
# ================== ==== ==== ==== ==========================================
# 0xE697459A77FBF34F    0    0    0 select c from l left join r on l_id = r_id where r_other is ?
",
   "--print-all shows 0/0/0 item"
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
