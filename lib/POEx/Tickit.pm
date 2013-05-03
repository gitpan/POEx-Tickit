#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013 -- leonerd@leonerd.org.uk

package POEx::Tickit;

use strict;
use warnings;
use base qw( Tickit );

our $VERSION = '0.01';

use Carp;

use POE;
use Tickit;

=head1 NAME

C<POEx::Tickit> - use C<Tickit> with C<POE>

=head1 SYNOPSIS

 use POE;
 use POEx::Tickit;

 my $tickit = POEx::Tickit->new;

 # Create some widgets
 # ...
 
 $tickit->set_root_widget( $rootwidget );

 $tickit->run;

=head1 DESCRIPTION

This class allows a L<Tickit> user interface to run alongside other
L<POE>-driven code, using C<POE> as a source of IO events.

=cut

my $next_alias_id = 0;

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( %args );
   $self->{session_alias} = __PACKAGE__ . "-" . $next_alias_id++;

   POE::Session->create(
      object_states => [
         $self => {
            _start   => "_poe_start",
            sigwinch => "_poe_sigwinch",
            input    => "_poe_input",
            timeout  => "_poe_timeout",
            _stop    => "_poe_stop",
         },
      ],
      inline_states => {
         invoke => sub { $_[-1]->() },
      },
   );

   return $self;
}

sub _poe_start
{
   my $self = $_[OBJECT];

   $_[KERNEL]->alias_set( $self->{session_alias} );

   $_[KERNEL]->sig( WINCH => sigwinch => );

   $_[KERNEL]->select_read( $self->term->get_input_handle, input => );
}

sub _poe_stop
{
   my $self = $_[OBJECT];

   $_[KERNEL]->sig( WINCH => () );

   $_[KERNEL]->select_read( $self->term->get_input_handle, () )
}

sub _poe_sigwinch
{
   $_[OBJECT]->_SIGWINCH;
}

sub _poe_input
{
   my $self = $_[OBJECT];

   my $term = $self->term;

   $_[KERNEL]->alarm_remove( delete $_[HEAP]{timeout_id} ) if $_[HEAP]{timeout_id};

   $term->input_readable;

   _poe_timeout( @_ );
}

sub _poe_timeout
{
   my $self = $_[OBJECT];
   my $term = $self->term;

   if( defined( my $timeout = $term->check_timeout ) ) {
      $_[HEAP]{timeout_id} = $_[KERNEL]->delay_set( timeout => $timeout / 1000 ); # msec
   }
}

sub later
{
   my $self = shift;
   POE::Kernel->post( $self->{session_alias}, invoke => $_[0] );
}

sub stop
{
   my $self = shift;
   POE::Kernel->call( $self->{session_alias}, _stop => );
}

sub run
{
   my $self = shift;

   POE::Session->create(
      inline_states => {
         _start => sub {
            $_[KERNEL]->alias_set( "$self->{session_alias}-SIGINT" );
            $_[KERNEL]->sig( INT => stop => );
         },
         stop   => sub {
            $self->stop;
         },
      },
   );

   $self->setup_term;

   my $ret = eval { POE::Kernel->run };
   my $e = $@;

   {
      local $@;

      $self->teardown_term;
   }

   die $@ if $@;
   return $ret;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
