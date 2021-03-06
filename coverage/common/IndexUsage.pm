---------------------------- ------ ------ ------ ------ ------ ------ ------
File                           stmt   bran   cond    sub    pod   time  total
---------------------------- ------ ------ ------ ------ ------ ------ ------
...tkit/common/IndexUsage.pm   90.3   62.5   40.0   90.0    0.0   62.4   78.6
IndexUsage.t                  100.0   50.0   40.0  100.0    n/a   37.6   93.8
Total                          94.5   61.1   40.0   95.0    0.0  100.0   84.7
---------------------------- ------ ------ ------ ------ ------ ------ ------


Run:          -e
Perl version: 118.53.46.49.48.46.48
OS:           linux
Start:        Thu Jun 24 19:33:32 2010
Finish:       Thu Jun 24 19:33:32 2010

Run:          IndexUsage.t
Perl version: 118.53.46.49.48.46.48
OS:           linux
Start:        Thu Jun 24 19:33:33 2010
Finish:       Thu Jun 24 19:33:33 2010

/home/daniel/dev/maatkit/common/IndexUsage.pm

line  err   stmt   bran   cond    sub    pod   time   code
1                                                     # This program is copyright 2010-@CURRENTYEAR@ Percona Inc.
2                                                     # Feedback and improvements are welcome.
3                                                     #
4                                                     # THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
5                                                     # WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
6                                                     # MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
7                                                     #
8                                                     # This program is free software; you can redistribute it and/or modify it under
9                                                     # the terms of the GNU General Public License as published by the Free Software
10                                                    # Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
11                                                    # systems, you can issue `man perlgpl' or `man perlartistic' to read these
12                                                    # licenses.
13                                                    #
14                                                    # You should have received a copy of the GNU General Public License along with
15                                                    # this program; if not, write to the Free Software Foundation, Inc., 59 Temple
16                                                    # Place, Suite 330, Boston, MA  02111-1307  USA.
17                                                    # ###########################################################################
18                                                    # IndexUsage package $Revision: 6331 $
19                                                    # ###########################################################################
20                                                    package IndexUsage;
21                                                    
22             1                    1             5   use strict;
               1                                  2   
               1                                  7   
23             1                    1             6   use warnings FATAL => 'all';
               1                                  3   
               1                                  9   
24             1                    1             5   use English qw(-no_match_vars);
               1                                  2   
               1                                  7   
25    ***      1            50      1             6   use constant MKDEBUG => $ENV{MKDEBUG} || 0;
               1                                  2   
               1                                 16   
26                                                    
27                                                    # This module's job is to keep track of how many times queries use indexes, and
28                                                    # show which are unused.  You use it by telling it about all the tables and
29                                                    # indexes that exist, and then you give it index usage stats (from
30                                                    # ExplainAnalyzer).  Afterwards, you ask it to show you unused indexes.
31                                                    sub new {
32    ***      1                    1      0      5      my ( $class, %args ) = @_;
33             1                                  8      my $self = {
34                                                          %args,
35                                                          tables_for  => {}, # Keyed off db
36                                                          indexes_for => {}, # Keyed off db->tbl
37                                                       };
38             1                                 21      return bless $self, $class;
39                                                    }
40                                                    
41                                                    # Tell the object that an index exists.  Internally, it just creates usage
42                                                    # counters for the index and the table it belongs to.  The arguments are as
43                                                    # follows:
44                                                    #   - The name of the database
45                                                    #   - The name of the table
46                                                    #   - A hashref to an indexes struct returned by TableParser::get_keys()
47                                                    sub add_indexes {
48    ***      4                    4      0     26      my ( $self, %args ) = @_;
49             4                                 17      my @required_args = qw(db tbl indexes);
50             4                                 13      foreach my $arg ( @required_args ) {
51    ***     12     50                          52         die "I need a $arg argument" unless $args{$arg};
52                                                       }
53             4                                 18      my ($db, $tbl, $indexes) = @args{@required_args};
54                                                    
55             4                                 20      $self->{tables_for}->{$db}->{$tbl}  = 0;
56             4                                 17      $self->{indexes_for}->{$db}->{$tbl} = $indexes;
57                                                    
58                                                       # Add to the indexes struct a cnt key for each index which is
59                                                       # incremented in add_index_usage().
60             4                                 15      foreach my $index ( keys %$indexes ) {
61             6                                 26         $indexes->{$index}->{cnt} = 0;
62                                                       }
63                                                    
64             4                                 17      return;
65                                                    }
66                                                    
67                                                    # This method just counts the fact that a table was used (regardless of whether
68                                                    # any indexes in it are used).  The arguments are just database and table name.
69                                                    sub add_table_usage {
70    ***      3                    3      0     55      my ( $self, $db, $tbl ) = @_;
71    ***      3     50     33                   36      die "I need a db and table" unless defined $db && defined $tbl;
72             3                                 14      ++$self->{tables_for}->{$db}->{$tbl};
73                                                    }
74                                                    
75                                                    # This method accepts information about how a query used an index, and saves it
76                                                    # for later retrieval.  The arguments are as follows:
77                                                    #  usage       The usage information, in the same format as the output from
78                                                    #              ExplainAnalyzer::get_index_usage()
79                                                    sub add_index_usage {
80    ***      1                    1      0      6      my ( $self, %args ) = @_;
81             1                                  4      foreach my $arg ( qw(usage) ) {
82    ***      1     50                           7         die "I need a $arg argument" unless defined $args{$arg};
83                                                       }
84             1                                  6      my ($id, $chk, $pos_in_log, $usage) = @args{qw(id chk pos_in_log usage)};
85             1                                  5      foreach my $access ( @$usage ) {
86             2                                  8         my ($db, $tbl, $idx, $alt) = @{$access}{qw(db tbl idx alt)};
               2                                 10   
87                                                          # Increment the index(es)'s usage counter.
88             2                                  7         foreach my $index ( @$idx ) {
89             3                                 21            $self->{indexes_for}->{$db}->{$tbl}->{$index}->{cnt}++;
90                                                          }
91                                                       }
92                                                    }
93                                                    
94                                                    # For every table in every database, determine whether each index was used or
95                                                    # not.  But only if the table was used.  Don't say "this index should be
96                                                    # dropped" if the table was never queried.  For each table, collect the unused
97                                                    # indexes and execute the callback subroutine with a hashref that looks like
98                                                    # this:
99                                                    # { db => db, tbl => tbl, idx => [<list of unused indexes on this table>] }
100                                                   sub find_unused_indexes {
101   ***      1                    1      0      5      my ( $self, $callback ) = @_;
102   ***      1     50                           5      die "I need a callback" unless $callback;
103                                                   
104                                                      # Local references to save typing
105            1                                  3      my %indexes_for = %{$self->{indexes_for}};
               1                                  6   
106            1                                  7      my %tables_for  = %{$self->{tables_for}};
               1                                  5   
107                                                   
108            1                                  8      DATABASE:
109            1                                  4      foreach my $db ( sort keys %{$self->{indexes_for}} ) {
110            1                                  7         TABLE:
111            1                                  3         foreach my $tbl ( sort keys %{$self->{indexes_for}->{$db}} ) {
112            4    100                          22            next TABLE unless $self->{tables_for}->{$db}->{$tbl}; # Skip unused
113            3                                 13            my $indexes = $self->{indexes_for}->{$db}->{$tbl};
114            3                                  6            my @unused_indexes;
115            3                                 14            foreach my $index ( sort keys %$indexes ) {
116            5    100                          26               if ( !$indexes->{$index}->{cnt} ) { # count of times accessed/used
117            2                                 10                  push @unused_indexes, $indexes->{$index};
118                                                               }
119                                                            }
120            3    100                          12            if ( @unused_indexes ) {
121            2                                 12               $callback->(
122                                                                  {  db  => $db,
123                                                                     tbl => $tbl,
124                                                                     idx => \@unused_indexes,
125                                                                  }
126                                                               );
127                                                            }
128                                                         } # TABLE
129                                                      } # DATABASE
130                                                   
131            1                                  5      return;
132                                                   }
133                                                   
134                                                   sub _d {
135   ***      0                    0                    my ($package, undef, $line) = caller 0;
136   ***      0      0                                  @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
      ***      0                                      
      ***      0                                      
137   ***      0                                              map { defined $_ ? $_ : 'undef' }
138                                                           @_;
139   ***      0                                         print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
140                                                   }
141                                                   
142                                                   1;
143                                                   
144                                                   # ###########################################################################
145                                                   # End IndexUsage package
146                                                   # ###########################################################################


Branches
--------

line  err      %   true  false   branch
----- --- ------ ------ ------   ------
51    ***     50      0     12   unless $args{$arg}
71    ***     50      0      3   unless defined $db and defined $tbl
82    ***     50      0      1   unless defined $args{$arg}
102   ***     50      0      1   unless $callback
112          100      1      3   unless $$self{'tables_for'}{$db}{$tbl}
116          100      2      3   if (not $$indexes{$index}{'cnt'})
120          100      2      1   if (@unused_indexes)
136   ***      0      0      0   defined $_ ? :


Conditions
----------

and 3 conditions

line  err      %     !l  l&&!r   l&&r   expr
----- --- ------ ------ ------ ------   ----
71    ***     33      0      0      3   defined $db and defined $tbl

or 2 conditions

line  err      %      l     !l   expr
----- --- ------ ------ ------   ----
25    ***     50      0      1   $ENV{'MKDEBUG'} || 0


Covered Subroutines
-------------------

Subroutine          Count Pod Location                                         
------------------- ----- --- -------------------------------------------------
BEGIN                   1     /home/daniel/dev/maatkit/common/IndexUsage.pm:22 
BEGIN                   1     /home/daniel/dev/maatkit/common/IndexUsage.pm:23 
BEGIN                   1     /home/daniel/dev/maatkit/common/IndexUsage.pm:24 
BEGIN                   1     /home/daniel/dev/maatkit/common/IndexUsage.pm:25 
add_index_usage         1   0 /home/daniel/dev/maatkit/common/IndexUsage.pm:80 
add_indexes             4   0 /home/daniel/dev/maatkit/common/IndexUsage.pm:48 
add_table_usage         3   0 /home/daniel/dev/maatkit/common/IndexUsage.pm:70 
find_unused_indexes     1   0 /home/daniel/dev/maatkit/common/IndexUsage.pm:101
new                     1   0 /home/daniel/dev/maatkit/common/IndexUsage.pm:32 

Uncovered Subroutines
---------------------

Subroutine          Count Pod Location                                         
------------------- ----- --- -------------------------------------------------
_d                      0     /home/daniel/dev/maatkit/common/IndexUsage.pm:135


IndexUsage.t

line  err   stmt   bran   cond    sub    pod   time   code
1                                                     #!/usr/bin/perl
2                                                     
3                                                     BEGIN {
4     ***      1     50     33      1            31      die
5                                                           "The MAATKIT_TRUNK environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
6                                                           unless $ENV{MAATKIT_TRUNK} && -d $ENV{MAATKIT_TRUNK};
7              1                                  8      unshift @INC, "$ENV{MAATKIT_TRUNK}/common";
8                                                     }
9                                                     
10             1                    1            11   use strict;
               1                                  2   
               1                                  5   
11             1                    1             6   use warnings FATAL => 'all';
               1                                  2   
               1                                  6   
12             1                    1            11   use English qw(-no_match_vars);
               1                                  3   
               1                                  9   
13             1                    1            10   use Test::More tests => 1;
               1                                  3   
               1                                  9   
14                                                    
15             1                    1            13   use IndexUsage;
               1                                  3   
               1                                 10   
16             1                    1            12   use MaatkitTest;
               1                                  3   
               1                                 37   
17                                                    
18    ***      1            50      1             8   use constant MKDEBUG => $ENV{MKDEBUG} || 0;
               1                                  3   
               1                                 23   
19                                                    
20             1                    1             6   use Data::Dumper;
               1                                  2   
               1                                  5   
21             1                                  4   $Data::Dumper::Indent    = 1;
22             1                                  4   $Data::Dumper::Sortkeys  = 1;
23             1                                  3   $Data::Dumper::Quotekeys = 0;
24                                                    
25             1                                  5   my $iu = new IndexUsage();
26                                                    
27                                                    # These are mock TableParser::get_keys() structs.
28             1                                  8   my $actor_idx = {
29                                                       PRIMARY             => { name => 'PRIMARY', },
30                                                       idx_actor_last_name => { name => 'idx_actor_last_name', }
31                                                    };
32             1                                  6   my $film_actor_idx = {
33                                                       PRIMARY        => { name => 'PRIMARY', },
34                                                       idx_fk_film_id => { name => 'idx_fk_film_id', },
35                                                    };
36             1                                  6   my $film_idx = {
37                                                       PRIMARY => { name => 'PRIMARY', },
38                                                    };
39             1                                  9   my $othertbl_idx = {
40                                                       PRIMARY => { name => 'PRIMARY', },
41                                                    };
42                                                    
43                                                    # This is more of an integration test than a unit test.
44                                                    # First we explore all the databases/tables/indexes in the server.
45             1                                  7   $iu->add_indexes(db=>'sakila', tbl=>'actor',      indexes=>$actor_idx);
46             1                                  5   $iu->add_indexes(db=>'sakila', tbl=>'film_actor', indexes=>$film_actor_idx );
47             1                                  5   $iu->add_indexes(db=>'sakila', tbl=>'film',       indexes=>$film_idx );
48             1                                  5   $iu->add_indexes(db=>'sakila', tbl=>'othertbl',   indexes=>$othertbl_idx);
49                                                    
50                                                    # Now, we see some queries that use some tables, but not all of them.
51             1                                  4   $iu->add_table_usage(qw(sakila      actor));
52             1                                  6   $iu->add_table_usage(qw(sakila film_actor));
53             1                                  6   $iu->add_table_usage(qw(sakila   othertbl));    # But not sakila.film!
54                                                    
55                                                    # Some of those queries also use indexes.
56             1                                 22   $iu->add_index_usage(
57                                                       usage      => [
58                                                          {  db  => 'sakila',
59                                                             tbl => 'film_actor',
60                                                             idx => [qw(PRIMARY idx_fk_film_id)],
61                                                             alt => [],
62                                                          },
63                                                          {  db  => 'sakila',
64                                                             tbl => 'actor',
65                                                             idx => [qw(PRIMARY)],
66                                                             alt => [qw(idx_actor_last_name)],
67                                                          },
68                                                       ],
69                                                    );
70                                                    
71                                                    # Now let's find out which indexes were never used.
72             1                                  6   my @unused;
73                                                    $iu->find_unused_indexes(
74                                                       sub {
75             2                    2             7         my ($thing) = @_;
76             2                                 11         push @unused, $thing;
77                                                       }
78             1                                 14   );
79                                                    
80             1                                 22   is_deeply(
81                                                       \@unused,
82                                                       [
83                                                          {
84                                                             db  => 'sakila',
85                                                             tbl => 'actor',
86                                                             idx => [ { name=>'idx_actor_last_name', cnt=>0 } ],
87                                                          },
88                                                          {
89                                                             db  => 'sakila',
90                                                             tbl => 'othertbl',
91                                                             idx => [ { name=>'PRIMARY', cnt=>0 } ],
92                                                          },
93                                                       ],
94                                                       'Got unused indexes for sakila.actor and film_actor',
95                                                    );
96                                                    
97                                                    # #############################################################################
98                                                    # Done.
99                                                    # #############################################################################
100            1                                  2   exit;


Branches
--------

line  err      %   true  false   branch
----- --- ------ ------ ------   ------
4     ***     50      0      1   unless $ENV{'MAATKIT_TRUNK'} and -d $ENV{'MAATKIT_TRUNK'}


Conditions
----------

and 3 conditions

line  err      %     !l  l&&!r   l&&r   expr
----- --- ------ ------ ------ ------   ----
4     ***     33      0      0      1   $ENV{'MAATKIT_TRUNK'} and -d $ENV{'MAATKIT_TRUNK'}

or 2 conditions

line  err      %      l     !l   expr
----- --- ------ ------ ------   ----
18    ***     50      0      1   $ENV{'MKDEBUG'} || 0


Covered Subroutines
-------------------

Subroutine Count Location       
---------- ----- ---------------
BEGIN          1 IndexUsage.t:10
BEGIN          1 IndexUsage.t:11
BEGIN          1 IndexUsage.t:12
BEGIN          1 IndexUsage.t:13
BEGIN          1 IndexUsage.t:15
BEGIN          1 IndexUsage.t:16
BEGIN          1 IndexUsage.t:18
BEGIN          1 IndexUsage.t:20
BEGIN          1 IndexUsage.t:4 
__ANON__       2 IndexUsage.t:75


