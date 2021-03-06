#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Time::HiRes qw(sleep);
use Test::More;

use MaatkitTest;
use Sandbox;
require "$trunk/mk-kill/mk-kill";

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 7;
}

my $output;
my $cnf='/tmp/12345/my.sandbox.cnf';

# #############################################################################
# Test that --kill kills the connection.
# #############################################################################

# Shell out to a sleep(10) query and try to capture the query.
# Backticks don't work here.
system("mysql -h127.1 -P12345 -umsandbox -pmsandbox -e 'select sleep(4)' >/dev/null&");
sleep 0.5;
my $rows = $dbh->selectall_hashref('show processlist', 'id');
my $pid;
map  { $pid = $_->{id} }
grep { $_->{info} && $_->{info} =~ m/select sleep\(4\)/ }
values %$rows;

ok(
   $pid,
   'Got proc id of sleeping query'
);

$output = output(
   sub { mk_kill::main('-F', $cnf, qw(--kill --print --run-time 1 --interval 1),
      '--match-info', 'select sleep\(4\)') },
);
like(
   $output,
   qr/KILL $pid /,
   '--kill'
);

sleep 0.5;
$rows = $dbh->selectall_hashref('show processlist', 'id');

my $con_alive = grep { $_->{id} eq $pid } values %$rows;
ok(
   !$con_alive,
   'Killed connection'
);

# #############################################################################
# Test that --kill-query only kills the query, not the connection.
# #############################################################################

# Here's how this works.  This cmd is going to try 2 queries on the same
# connection: sleep5 and sleep3.  --kill-query will kill sleep5 causing
# sleep3 to start using the same connection id (pid).
system("mysql -h127.1 -P12345 -umsandbox -pmsandbox -e 'select sleep(5); select sleep(3)' >/dev/null&");
sleep 0.5;
$rows = $dbh->selectall_hashref('show processlist', 'id');
$pid = 0;  # reuse, reset
map  { $pid = $_->{id} }
grep { $_->{info} && $_->{info} =~ m/select sleep\(5\)/ }
values %$rows;
ok(
   $pid,
   'Got proc id of sleeping query'
);

$output = output(
   sub { mk_kill::main('-F', $cnf, qw(--kill-query --print --run-time 1 --interval 1),
      '--match-info', 'select sleep\(5\)') },
);
like(
   $output,
   qr/KILL QUERY $pid /,
   '--kill-query'
);

sleep 1;
$rows = $dbh->selectall_hashref('show processlist', 'id');
$con_alive = grep { $_->{id} eq $pid } values %$rows;
ok(
   $con_alive,
   'Killed query, not connection'
);

is(
   ($rows->{$pid}->{info} || ''),
   'select sleep(3)',
   'Connection is still alive'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
