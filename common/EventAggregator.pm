# This program is copyright 2008-@CURRENTYEAR@ Percona Inc.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.

# #############################################################################
# EventAggregator package $Revision$
# #############################################################################

package EventAggregator;

# This package's function is to take hashrefs and aggregate them as you specify.
# It basically does a GROUP BY.  If you say to group by z and calculate
# aggregate statistics for a, b, c then it manufactures functions to record
# various kinds of stats for the a per z, b per z, and c per z in incoming
# hashrefs.  Usually you'll use it a little less abstractly: you'll say the
# incoming hashrefs are parsed query events from the MySQL slow query log, and
# you want it to calculate stats for Query_time, Rows_read etc aggregated by
# query fingerprint.  It automatically determines whether a specified property
# is a string, number or Yes/No value and aggregates them appropriately.  It can
# collect and aggregate by several things simultaneously, e.g. you could group
# by fingerprint at the same time that you group by user.

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use POSIX qw(floor);

# #############################################################################
# Set up some constants for bucketing values.  It is impossible to keep all
# values seen in memory, but putting them into logarithmically scaled buckets
# and just incrementing the bucket each time works, although it is imprecise.
# #############################################################################
use constant MKDEBUG      => $ENV{MKDEBUG};
use constant BUCK_SIZE    => 1.05;
use constant BASE_LOG     => log(BUCK_SIZE);
use constant BASE_OFFSET  => -floor(log(.000001) / BASE_LOG); # typically 284
use constant NUM_BUCK     => 1000;
use constant MIN_BUCK     => .000001;
use constant WHERE_CLASS  => 0;
use constant WHERE_GLOBAL => 1;

our @buckets  = map { 0 } (1 .. NUM_BUCK);
my @buck_vals = (MIN_BUCK, MIN_BUCK * BUCK_SIZE);
{
   my $cur = BUCK_SIZE;
   for ( 2 .. NUM_BUCK - 1 ) {
      push @buck_vals, MIN_BUCK * ($cur *= BUCK_SIZE);
   }
}

# The best way to see how to use this is to look at the .t file.
#
# %args is a hash containing:
# classes      A hashref.  Each key of the hashref is the name of an element to
#              group-by.  Usually this will be 'fingerprint' at a minimum when
#              you're processing a slow log.  The value is a hashref itself,
#              whose keys are names of elements to aggregate within that
#              group-by.  And the values of those elements are arrayrefs of the
#              values to pull from the hashref, with any second or subsequent
#              values being fallbacks for the first in case it's not defined.
# globals      Similar to classes, but not a deeply nested structure.
# save         The name of an element which defines the "worst" hashref in its
#              class.  If this is Query_time, then each class will contain
#              a sample that holds the event with the largest Query_time.
# unroll_limit If this many events have been processed and some handlers haven't
#              been generated yet (due to lack of sample data) unroll the loop
#              anyway.  Defaults to 50.
# attrib_limit Sanity limit for attribute values.  If the value exceeds the
#              limit, use the last-seen for this class; if none, then 0.
sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(classes) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   return bless {
      classes      => $args{classes},
      globals      => $args{globals},
      save         => $args{save},
      unroll_limit => $args{unroll_limit} || 50,
      attrib_limit => $args{attrib_limit},
   }, $class;
}

# Aggregate an event hashref's properties.
sub aggregate {
   my ( $self, $event ) = @_;

   CLASS:
   foreach my $class ( keys %{$self->{classes}} ) {
      my @attribs = sort keys %{$self->{classes}->{$class}};
      my $group_by = $event->{$class};
      defined $group_by or next CLASS;
      ATTRIB:
      foreach my $attrib ( @attribs ) {
         my $class_attrib
            = $self->{result_class}->{$class}->{$group_by}->{$attrib} ||= {};
         my $handler = $self->{handlers}->{ $attrib };
         if ( !$handler ) {
            $handler = $self->make_handler(
               $attrib,
               $event,
               wor => (($self->{save} || '') eq $attrib),
               alt => $self->{classes}->{$class}->{$attrib},
            );
            if ( $handler ) {
               $self->{handlers}->{$attrib} = $handler;
            }
         }
         next ATTRIB unless $handler;
         $handler->($event, $class_attrib, WHERE_CLASS);
      }
   }

   if ( $self->{globals} ) {
      my @attribs = sort keys %{$self->{globals}};
      ATTRIB:
      foreach my $attrib ( @attribs ) {
         my $global_attrib
            = $self->{result_globals}->{$attrib} ||= {};
         my $handler = $self->{handlers}->{ $attrib };
         if ( !$handler ) {
            $handler = $self->make_handler(
               $attrib,
               $event,
               alt => $self->{globals}->{$attrib},
            );
            if ( $handler ) {
               $self->{handlers}->{$attrib} = $handler;
            }
         }
         next ATTRIB unless $handler;
         $handler->($event, $global_attrib, WHERE_GLOBAL);
      }
   }

   return;
}

# Return the aggregated results.
sub results {
   my ( $self ) = @_;
   return {
      classes => $self->{result_class},
      globals => $self->{result_globals},
   };
}

# Make subroutines that do things with events.
#
# $attrib: the name of the attrib (Query_time, Rows_read, etc)
# $event:  a sample event
# %args:
#     min => keep min for this attrib (default except strings)
#     max => keep max (default except strings)
#     sum => keep sum (default for numerics)
#     cnt => keep count (default except strings)
#     unq => keep all unique values per-class (default for strings and bools)
#     all => keep a bucketed list of values seen per class (default for numerics)
#     glo => keep stats globally as well as per-class (default)
#     trf => An expression to transform the value before working with it
#     wor => Whether to keep worst-samples for this attrib (default no)
#     alt => Arrayref of other name(s) for the attribute, like db => Schema.
#
# The bucketed list works this way: each range of values from MIN_BUCK in
# increments of BUCK_SIZE (that is 5%) we consider a bucket.  We keep NUM_BUCK
# buckets.  The upper end of the range is more than 1.5e15 so it should be big
# enough for almost anything.  The buckets are accessed by a log base BUCK_SIZE,
# so floor(log(N)/log(BUCK_SIZE)).  The smallest bucket's index is -284. We
# shift all values up 284 so we have values from 0 to 999 that can be used as
# array indexes.  A value that falls into a bucket simply increments the array
# entry.
#
# This eliminates the need to keep and sort all values to calculate median,
# standard deviation, 95th percentile etc.  Thus the memory usage is bounded by
# the number of distinct aggregated values, not the number of events.
#
# Return value:
# a subroutine with this signature:
#    my ( $event, $store, $where ) = @_;
# where
#  $event   is the event
#  $store   is the container to store the aggregated values
#  $where   is either WHERE_CLASS or WHERE_GLOBAL
sub make_handler {
   my ( $self, $attrib, $event, %args ) = @_;
   die "I need an attrib" unless defined $attrib;
   return unless $event;
   my ($val) = grep { defined $_ } map { $event->{$_} } @{ $args{alt} };
   return unless defined $val; # Can't decide type if it's undef.

   # Ripped off from Regexp::Common::number.
   my $float_re = qr{[+-]?(?:(?=\d|[.])\d*(?:[.])\d{0,})?(?:[E](?:[+-]?\d+)|)}i;
   my $type = $val  =~ m/^(?:\d+|$float_re)$/o ? 'num'
            : $val  =~ m/^(?:Yes|No)$/         ? 'bool'
            :                                    'string';
   MKDEBUG && _d("Type for $attrib is $type (sample: $val)");

   %args = ( # Set up defaults
      min => 1,
      max => 1,
      sum => $type =~ m/num|bool/    ? 1 : 0,
      cnt => $type eq 'string'       ? 0 : 1,
      unq => $type =~ m/bool|string/ ? 1 : 0,
      all => $type eq 'num'          ? 1 : 0,
      glo => 1,
      trf => ($type eq 'bool') ? q{($val || '' eq 'Yes') ? 1 : 0} : undef,
      wor => 0,
      alt => [],
      %args,
   );

   my @lines = ("# type: $type"); # Lines of code for the subroutine
   if ( $args{trf} ) {
      push @lines, q{$val = } . $args{trf} . ';';
   }

   if ( $args{min} ) {
      my $op   = $type eq 'num' ? '<' : 'lt';
      push @lines, '$store->{min} = $val if !defined $store->{min} || $val '
         . $op . ' $store->{min};';
   }
   if ( $args{max} ) {
      my $op = ($type eq 'num') ? '>' : 'gt';
      push @lines, '$store->{max} = $val if !defined $store->{max} || $val '
         . $op . ' $store->{max};';
   }
   if ( $args{sum} ) {
      push @lines, '$store->{sum} += $val;';
   }
   if ( $args{cnt} ) {
      push @lines, '++$store->{cnt};';
   }
   if ( $args{unq} ) {
      push @lines, '++$store->{unq}->{$val} unless $where == WHERE_GLOBAL;';
   }
   if ( $args{all} ) {
      push @lines, (
         # If you change this code, change the similar code in bucketize.
         # '$store->{all} ||= [ map { 0 } (1..NUM_BUCK) ];',
         '$store->{all} ||= [ @buckets ];',
         'my $idx = BASE_OFFSET + ($val > 0 ? floor(log($val) / BASE_LOG) : 0);',
         '++$store->{all}->[ $idx > NUM_BUCK ? NUM_BUCK : $idx ];',
      );
   }
   if ( $args{wor} ) {
      my $op = $type eq 'num' ? '>=' : 'ge';
      push @lines, (
         'if ( $where ne WHERE_GLOBAL && $val ' . $op . ' ($store->{max} || 0) ) {',
         '   $store->{sample} = $event;',
         '}',
      );
   }

   # Make sure the value is constrained to legal limits.  If it's out of bounds,
   # just use the last-seen value for it.
   my @limit;
   if ( $args{all} && $type eq 'num' && $self->{attrib_limit} ) {
      push @limit, (
         "if ( \$val > $self->{attrib_limit} ) {",
         '   $val = $store->{last} ||= 0;',
         '}',
         '$store->{last} = $val;',
      );
   }

   # Save the code for later, as part of an "unrolled" subroutine.
   my @unrolled = (
      '$val = $event->{' . $attrib . '};',
      (map { "\$val = \$event->{$_} unless defined \$val;" } @{$args{alt}}),
      'defined $val && do {',
      ( map { s/^/   /gm; $_ } (@limit, @lines) ), # Indent for debugging
      '};',
   );
   $self->{unrolled_for}->{$attrib} = join("\n", @unrolled);

   # Build a subroutine with the code.
   unshift @lines, (
      'sub {',
      'my ( $event, $store, $where ) = @_;',
      'my $val = $event->{' . $attrib . '};',
      (map { "\$val = \$event->{$_} unless defined \$val;" } @{$args{alt}}),
      'return unless defined $val;',
      @limit,
   );
   push @lines, '}';
   my $code = join("\n", @lines);
   $self->{code_for}->{$attrib} = $code;

   MKDEBUG && _d("Metric handler for $attrib: ", @lines);
   my $sub = eval join("\n", @lines);
   die if $EVAL_ERROR;
   return $sub;
}

# This method is for testing only.  If you change this code, change the code
# above too (look for bucketize).
sub bucketize {
   my ( $self, $vals ) = @_;
   my @bucketed = @buckets;
   my ($sum, $max, $min);
   $max = $min = $vals->[0];
   foreach my $val ( @$vals ) {
      my $idx = BASE_OFFSET + ($val > 0 ? floor(log($val) / BASE_LOG) : 0);
      ++$bucketed[ $idx > NUM_BUCK ? NUM_BUCK : $idx ];
      $max = $max > $val ? $max : $val;
      $min = $min < $val ? $min : $val;
      $sum += $val;
   }
   return (\@bucketed, { sum => $sum, max => $max, min => $min, cnt => scalar @$vals});
}

# This method is for testing only.
sub unbucketize {
   my ( $self, $vals ) = @_;
   my @result;
   foreach my $i ( 0 .. NUM_BUCK - 1 ) {
      next unless $vals->[$i];
      foreach my $j ( 1 .. $vals->[$i] ) {
         push @result, $buck_vals[$i];
      }
   }
   return @result;
}

# Given an arrayref of vals, returns a hashref with the following
# statistical metrics:
#
#    pct_95    => The 95th percentile
#    cutoff    => How many values fall into the 95th percentile
#    stddev    => of 95% values
#    median    => of 95% values
#
# The vals arrayref is the buckets as per the above (see the comments at the top
# of this file).  $args should contain cnt, min, max and sum properties.
sub calculate_statistical_metrics {
   my ( $self, $vals, $args ) = @_;
   my $statistical_metrics = {
      pct_95    => 0,
      stddev    => 0,
      median    => 0,
      cutoff    => undef,
   };

   # These cases might happen when there is nothing to get from the event, for
   # example, processlist sniffing doesn't gather Rows_examined, so $args won't
   # have {cnt} or other properties.
   return $statistical_metrics
      unless defined $vals && @$vals && $args->{cnt};

   # Return accurate metrics for some cases.
   my $n_vals = $args->{cnt};
   if ( $n_vals == 1 || $args->{max} == $args->{min} ) {
      my $v      = $args->{max} || 0;
      my $bucket = floor( log($v > 0 ? $v : MIN_BUCK) / log(10)) + 6;
      $bucket    = $bucket > 7 ? 7 : $bucket < 0 ? 0 : $bucket;
      return {
         pct_95 => $v,
         stddev => 0,
         median => $v,
         cutoff => $n_vals,
      };
   }
   elsif ( $n_vals == 2 ) {
      foreach my $v ( $args->{min}, $args->{max} ) {
         my $bucket = floor( log($v && $v > 0 ? $v : MIN_BUCK) / log(10)) + 6;
         $bucket = $bucket > 7 ? 7 : $bucket < 0 ? 0 : $bucket;
      }
      my $v      = $args->{max} || 0;
      my $mean = (($args->{min} || 0) + $v) / 2;
      return {
         pct_95 => $v,
         stddev => sqrt((($v - $mean) ** 2) *2),
         median => $mean,
         cutoff => $n_vals,
      };
   }

   # Determine cutoff point for 95% if there are at least 10 vals.  Cutoff
   # serves also for the number of vals left in the 95%.  E.g. with 50 vals the
   # cutoff is 47 which means there are 47 vals: 0..46.  $cutoff is NOT an array
   # index.
   my $cutoff = $n_vals >= 10 ? int ( $n_vals * 0.95 ) : $n_vals;
   $statistical_metrics->{cutoff} = $cutoff;

   my $total_left = $n_vals;
   my $i = NUM_BUCK - 1;

   # Find the 95th percentile biggest value.  And calculate the values of the
   # ones we exclude.
   my $sum_excl  = 0;
   while ( $i-- && $total_left > $cutoff ) {
      if ( $vals->[$i] ) {
         $total_left -= $vals->[$i];
         $sum_excl   += $buck_vals[$i] * $vals->[$i];
      }
   }

   # Continue until we find the next array element that has a value.
   my $bucket_95;
   while ( $i-- ){
      $bucket_95 = $i;
      last if $vals->[$i];
   }
   return $statistical_metrics unless $vals->[$bucket_95];
   # At this point, $bucket_95 points to the first value we want to keep.

   # Calculate the standard deviation, median, and max value of the 95th
   # percentile of values.
   my $sum    = $buck_vals[$bucket_95] * $vals->[$bucket_95];
   my $sumsq  = $sum ** 2;
   my $mid    = int($cutoff / 2);
   my $median = 0;
   my $prev   = $bucket_95; # Used for getting median when $cutoff is odd

   # Continue through the rest of the values.
   while ( $i-- ) {
      my $val = $vals->[$i];
      if ( $val ) {
         $total_left -= $val;
         if ( !$median && $total_left <= $mid ) {
            $median = (($cutoff % 2) || ($val > 1)) ? $buck_vals[$i]
                    : ($buck_vals[$i] + $buck_vals[$prev]) / 2;
         }
         $sum        += $buck_vals[$i] * $val;
         $sumsq      += ($buck_vals[$i] ** 2 ) * $val;
         $prev       =  $i;
      }
   }

   my $stddev   = sqrt (($sumsq - (($sum**2) / $cutoff)) / ($cutoff -1 || 1));
   my $maxstdev = (($args->{max} || 0) - ($args->{min} || 0)) / 2;
   $stddev      = $stddev > $maxstdev ? $maxstdev : $stddev;

   MKDEBUG && _d("95 cutoff $cutoff, sum $sum, sumsq $sumsq, stddev $stddev");

   $statistical_metrics->{stddev} = $stddev;
   $statistical_metrics->{pct_95} = $buck_vals[$bucket_95];
   $statistical_metrics->{median} = $median;

   return $statistical_metrics;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   # Use $$ instead of $PID in case the package
   # does not use English.
   print "# $package:$line $$ ", @_, "\n";
}

1;

# #############################################################################
# End EventAggregator package
# #############################################################################
