#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use Grants;
use DSNParser;
use Sandbox;
use MaatkitTest;

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);

my $dbh = $sb->get_dbh_for('master');
if ( !$dbh ) {
   plan skip_all => "Cannot connect to sandbox master";
}
else {
   plan tests => 4;
}

my $gr = new Grants;
isa_ok($gr, 'Grants');

diag(`/tmp/12345/use -u root -e "GRANT USAGE ON *.* TO ''\@'%'"`);
my $anon_dbh = DBI->connect(
   "DBI:mysql:;host=127.0.0.1;port=12345", undef, undef,
   { PrintError => 0, RaiseError => 1 });
ok(!$gr->have_priv($anon_dbh, 'process'), 'Anonymous user does not have PROCESS priv');

diag(`/tmp/12345/use -uroot -umsandbox -e "DROP USER ''\@'%'"`);

ok($gr->have_priv($dbh, 'PROCESS'), 'Normal user does have PROCESS priv');

eval {
   $gr->have_priv($dbh, 'foo');
};
like($EVAL_ERROR, qr/no check for privilege/, 'Dies if privilege has no check');

exit;
