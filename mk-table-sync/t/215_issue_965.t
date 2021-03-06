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
require "$trunk/mk-table-sync/mk-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 2;
}

my $output;

# #############################################################################
# Issue 965: mk-table-sync --trim can cause impossible WHERE, invalid SQL
# #############################################################################
$sb->wipe_clean($dbh);
$sb->load_file('master', 'mk-table-sync/t/samples/issue_965.sql');

$output = output(
   sub {
      mk_table_sync::main(qw(--trim --print --execute -F /tmp/12345/my.sandbox.cnf),
         'D=issue_965,t=t1', 'D=issue_965,t=t2')
   },
   trf => \&remove_traces,
);

is(
   $output,
"DELETE FROM `issue_965`.`t2` WHERE `b_ref`='aae' AND `r`='5' AND `o_i`='100' LIMIT 1;
INSERT INTO `issue_965`.`t2`(`b_ref`, `r`, `o_i`, `r_s`) VALUES ('aae', '5', '1', '2010-03-29 14:44:00');
",
   "Correct SQL statements"
);

is_deeply(
   $dbh->selectall_arrayref('select o_i from issue_965.t2 where b_ref="aae"'),
   [[1]],
   'Synced 2nd table'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
