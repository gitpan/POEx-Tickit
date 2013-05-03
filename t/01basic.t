#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use POE;
use POEx::Tickit;

my $tickit;

my $later;
my $sigwinch;

POE::Session->create(
   inline_states => {
      _start => sub {
         pipe( my ( $my_rd, $term_wr ) ) or die "Cannot pipe() - $!";

         $tickit = POEx::Tickit->new(
            term_out => $term_wr,
         );

         isa_ok( $tickit, 'POEx::Tickit', '$tickit' );

         $tickit->later( sub { $later++; kill SIGWINCH => $$ } );
      },
   },
);

no warnings 'redefine';
*Tickit::_SIGWINCH = sub { $sigwinch++; $tickit->stop };

POE::Kernel->run;

is( $later, 1, '$later 1 after ->later' );
is( $sigwinch, 1, '$sigwinch 1 after raise SIGWINCH' );

done_testing;
