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
   plan tests => 1;
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);

# #############################################################################
# Issue 218: Two NULL column values don't compare properly w/ Stream/GroupBy
# #############################################################################
$sb->create_dbs($master_dbh, [qw(issue218)]);
$sb->use('master', '-e "CREATE TABLE issue218.t1 (i INT)"');
$sb->use('master', '-e "INSERT INTO issue218.t1 VALUES (NULL)"');
qx($trunk/mk-table-sync/mk-table-sync --no-check-slave --print --database issue218 h=127.1,P=12345,u=msandbox,p=msandbox P=12346);
ok(!$?, 'Issue 218: NULL values compare as equal');

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
