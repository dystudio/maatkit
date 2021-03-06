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
require "$trunk/mk-config-diff/mk-config-diff";

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
   plan tests => 12;
}

my $cnf = '/tmp/12345/my.sandbox.cnf';
my $output;
my $retval;

# ############################################################################
# Compare active configs.
# ############################################################################

$output = output(
   sub { $retval = mk_config_diff::main(
      'h=127.1,P=12345,u=msandbox,p=msandbox', 'h=127.1')
   },
   stderr => 1,
);

is(
   $retval,
   0,
   "Server active config doesn't differ with itself"
);

is(
   $output,
   "",
   "No output when no diff"
);

# Diff master to slave1.  There should be several differences.
$output = output(
   sub { $retval = mk_config_diff::main(
      'h=127.1,P=12345,u=msandbox,p=msandbox', 'P=12346')
   },
   stderr => 1,
);

is(
   $retval,
   1,
   "Exit 1 when diffs found"
);

like(
   $output,
   qr{datadir\s+/tmp/12345/data/\s+/tmp/12346/data/},
   "Diff output"
);


# ############################################################################
# Compare opt file and active config.
# ############################################################################

$output = output(
   sub { $retval = mk_config_diff::main(
      $cnf, 'h=127.1,P=12345,u=msandbox,p=msandbox')
   },
   stderr => 1,
);

is(
   $retval,
   0,
   "my.sandbox.cnf doesn't differ with active config"
);

is(
   $output,
   "",
   "No output"
);

# Compare master config to slave active/SHOW VARS
$output = output(
   sub { $retval = mk_config_diff::main(
      $cnf, 'h=127.1,P=12346,u=msandbox,p=msandbox')
   },
   stderr => 1,
);

is(
   $retval,
   1,
   "Master my.sandbox.cnf differs from slave active config"
);

like(
   $output,
   qr{server_id\s+12345\s+12346},
   "Config diff output"
);

# ############################################################################
# Compare option file configs.
# ############################################################################

$output = output(
   sub { $retval = mk_config_diff::main($cnf, $cnf) },
   stderr => 1,
);

is(
   $retval,
   0,
   "Server option file config doesn't differ with itself"
);

is(
   $output,
   "",
   "No output"
);

$output = output(
   sub { $retval = mk_config_diff::main(
      '/tmp/12345/my.sandbox.cnf',
      '/tmp/12346/my.sandbox.cnf',
   ) },
   stderr => 1,
);

is(
   $retval,
   1,
   "Master and slave option files differ"
);

like(
   $output,
   qr{port\s+12345\s+12346},
   "Config diff output"
);

# #############################################################################
# Done.
# #############################################################################
exit;
