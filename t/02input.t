#!/usr/bin/perl

use strict;
use warnings;

# We need a UTF-8 locale to force libtermkey into UTF-8 handling, even if the
# system locale is not
# We also need to fool libtermkey into believing TERM=xterm even if it isn't,
# so we can reliably control it with fake escape sequences
BEGIN {
   $ENV{LANG} .= ".UTF-8" unless $ENV{LANG} =~ m/\.UTF-8$/;
   $ENV{TERM} = "xterm";
}

use Test::More;

use POE;
use POEx::Tickit;

pipe( my ( $term_rd, $my_wr ) ) or die "Cannot pipe() - $!";
open my $term_wr, ">", \my $output;

my $tickit;

my @key_events;
my @mouse_events;

# We can't get at the key/mouse events easily from outside, so we'll hack it

no warnings 'redefine';
*Tickit::on_key = sub {
   my ( $self, $type, $str ) = @_;
   push @key_events, [ $type => $str ];
};
*Tickit::on_mouse = sub {
   my ( $self, $ev, $button, $line, $col ) = @_;
   push @mouse_events, [ $ev => $button, $line, $col ];
};

POE::Session->create(
   inline_states => {
      _start => sub {
         $tickit = POEx::Tickit->new(
            UTF8     => 1,
            term_in  => $term_rd,
            term_out => $term_wr,
         );

         $_[KERNEL]->yield( test_keys => );
      },
      test_keys => sub {
         $my_wr->syswrite( "h" );
         $my_wr->syswrite( "\cA" );
         $my_wr->syswrite( "\eX" );

         $my_wr->syswrite( "\e" );
         # 10msec should be enough for us to have to wait but short enough for
         # libtermkey to consider this
         $_[KERNEL]->delay_set( test_keys_2 => 0.010 );
      },
      test_keys_2 => sub {
         $my_wr->syswrite( "Y" );
         # We'll test with a Unicode character outside of Latin-1, to ensure it
         # roundtrips correctly
         #
         # 'ĉ' [U+0109] - LATIN SMALL LETTER C WITH CIRCUMFLEX
         #  UTF-8: 0xc4 0x89

         $my_wr->syswrite( "\xc4\x89" );

         $_[KERNEL]->yield( test_mouse => );
      },
      test_mouse => sub {
         # Mouse encoding == CSI M $b $x $y
         # where $b, $l, $c are encoded as chr(32+$). Position is 1-based
         $my_wr->syswrite( "\e[M".chr(32+0).chr(32+21).chr(32+11) );

         $_[KERNEL]->yield( done => );
      },
      done => sub {
         $tickit->stop;
      },
   },
);

POE::Kernel->run;

is_deeply( shift @key_events, [ text => "h" ], 'on_key h' );
is_deeply( shift @key_events, [ key => "C-a" ], 'on_key Ctrl-A' );
is_deeply( shift @key_events, [ key => "M-X" ], 'on_key Alt-X' );
is_deeply( shift @key_events, [ key => "M-Y" ], 'on_key Alt-Y split write' );
is_deeply( shift @key_events, [ text => "\x{109}" ], 'on_key reads UTF-8' );

# Tickit::Term reports position 0-based
is_deeply( shift @mouse_events, [ press => 1, 10, 20 ], 'on_mouse press(1) @20,10' );

done_testing;
