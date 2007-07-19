#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::More tests => 7;

require "../mysql-explain-tree";

sub load_file {
   my ($file) = @_;
   open my $fh, "<", $file or die $!;
   my $contents = do { local $/ = undef; <$fh> };
   close $fh;
   return $contents;
}
my $e = new ExplainTree;

is_deeply(
   $e->parse( load_file('samples/full_scan_sakila_film.sql') ),
   {  type  => 'Table scan',
      rows  => 935,
      child => {
         type          => 'Table',
         table         => 'film',
         possible_keys => undef,
      }
   },
   'Simple scan',
);

is_deeply(
   $e->parse( load_file('samples/actor_join_film_ref.sql') ),
   {  type => 'JOIN',
      left => {
         type  => 'Table scan',
         rows  => 952,
         child => {
            type          => 'Table',
            table         => 'film',
            possible_keys => 'PRIMARY',
         },
      },
      right => {
         type     => 'Index lookup',
         key      => 'film_actor->idx_fk_film_id',
         key_len  => 2,
         'ref'    => 'sakila.film.film_id',
         rows     => 2,
         child    => {
            type          => 'Table',
            table         => 'film_actor',
            possible_keys => 'idx_fk_film_id',
         },
      },
   },
   'Simple join',
);

is_deeply(
   $e->parse( load_file('samples/film_join_actor_eq_ref.sql') ),
   {  type => 'JOIN',
      left => {
         type  => 'Table scan',
         rows  => 5143,
         child => {
            type          => 'Table',
            table         => 'film_actor',
            possible_keys => 'idx_fk_film_id',
         },
      },
      right => {
         type     => 'Unique index lookup',
         key      => 'film->PRIMARY',
         key_len  => 2,
         'ref'    => 'sakila.film_actor.film_id',
         rows     => 1,
         child    => {
            type          => 'Table',
            table         => 'film',
            possible_keys => 'PRIMARY',
         },
      },
   },
   'Straight join',
);

is_deeply(
   $e->parse( load_file('samples/full_row_pk_lookup_sakila_film.sql') ),
   {  type => 'Constant index lookup',
      key      => 'film->PRIMARY',
      key_len  => 2,
      'ref'    => 'const',
      rows     => 1,
      child    => {
         type          => 'Table',
         table         => 'film',
         possible_keys => 'PRIMARY',
      },
   },
   'Constant lookup',
);

is_deeply(
   $e->parse( load_file('samples/index_scan_sakila_film.sql') ),
   {  type => 'Index scan',
      key      => 'film->idx_title',
      key_len  => 767,
      'ref'    => undef,
      rows     => 952,
      child    => {
         type          => 'Table',
         table         => 'film',
         possible_keys => undef,
      },
   },
   'Index scan',
);

is_deeply(
   $e->parse( load_file('samples/index_scan_sakila_film_using_where.sql') ),
   {  type  => 'Filter with WHERE',
      child => {
         type    => 'Index scan',
         key     => 'film->idx_title',
         key_len => 767,
         'ref'   => undef,
         rows    => 952,
         child   => {
            type          => 'Table',
            table         => 'film',
            possible_keys => undef,
         },
      },
   },
   'Index scan with WHERE clause',
);

is_deeply(
   $e->parse( load_file('samples/pk_lookup_sakila_film.sql') ),
   {  type    => 'Constant index lookup',
      key     => 'film->PRIMARY',
      key_len => 2,
      'ref'   => 'const',
      rows    => 1,
   },
   'PK lookup with covering index',
);
