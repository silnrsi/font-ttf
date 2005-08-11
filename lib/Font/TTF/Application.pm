package Font::TTF::Application;

=head1 NAME

Font::TTF::Application - Application helper functions

=head1 DESCRIPTION

Various application helper functions to facilitate script chaining

=head1 FUNCTIONS

The following functions are exported

=cut

use strict;
use vars qw(@ISA @EXPORT $VERSION @EXPORT_OK);
require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(opts_vars);

=head2 opts_vars(\%opts)

Converts a reference to an options hash into $opt_x option variables

=cut

sub opts_vars
{
    no strict 'refs';
    my ($opts) = @_;
    my ($k, $p);

    $p = caller;
    foreach $k (grep {length($_) == 1} keys %{$opts})
    { ${"$p::opt_$k"} = $opts->{$k}; }
}
