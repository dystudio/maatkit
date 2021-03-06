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

my $output;
my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 2;
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 616: mk-table-sync inserts NULL values instead of correct values
# #############################################################################
diag(`/tmp/12345/use -D test < $trunk/common/t/samples/issue_616.sql`);
sleep 1;
`$trunk/mk-table-sync/mk-table-sync --sync-to-master h=127.1,P=12346,u=msandbox,p=msandbox --databases issue_616 --execute`;
my $ok_r = [
   [  1, 'from master' ],
   [ 11, 'from master' ],
   [ 21, 'from master' ],
   [ 31, 'from master' ],
   [ 41, 'from master' ],
   [ 51, 'from master' ],
];

my $r = $master_dbh->selectall_arrayref('SELECT * FROM issue_616.t ORDER BY id');
is_deeply(
   $r,
   $ok_r,
   'Issue 616 synced on master'
);
      
$r = $slave_dbh->selectall_arrayref('SELECT * FROM issue_616.t ORDER BY id');
is_deeply(
   $r,
   $ok_r,
   'Issue 616 synced on slave'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
