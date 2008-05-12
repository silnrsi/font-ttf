package Font::TTF::Dump;

=head1 NAME

Font::TTF::Dump - Debug dump of a font datastructure, avoiding recursion on ' PARENT'

=head1 DESCRIPTION

Font::TTF data structures are trees created from hashes and arrays. When trying to figure
out how the structures work, sometimes it is helpful to use Data::Dumper on them. However,
many of the object structures have ' PARENT' links that refer back to the object's parent,
which means that Data::Dumper ends up dumping the whole font no matter what.

The purpose of this module is to do just one thing: invoke Data::Dumper with a
filter that skips over the ' PARENT' element of any hash.

To reduce output further, this module also skips over ' CACHE' elements and any 
hash element whose value is a Font::TTF::Glyph or Font::TTF::Font object. 
(Really should make this configurable.)

=head1 METHODS

=cut

use strict;
use Data::Dumper;

=head2

Font::TTF::Dump::Dumper($var, [qw(name)])

returns a string

=cut

my %skip = ( Font => 1, Glyph => 1 );

sub Dumper
{
    my ($var, $name) = @_;
    my $res;
    
    my $d = Data::Dumper->new([$var]);
    $d->Names([$name]) if defined $name;
    $d->Sortkeys(\&myfilter);   # This is the trick to keep from dumping the whole font
    $d->Indent(3);  # I want array indicies
    $d->Useqq(1);   # Perlquote -- slower but there might be binary data.
    $res = $d->Dump;
    $d->DESTROY;
    $res;
}

sub myfilter
{
    my ($hash) = @_;
    my @a = grep {
            ($_ eq ' PARENT' || $_ eq ' CACHE') ? 0 :
            ref($hash->{$_}) =~ m/^Font::TTF::(.*)$/ ? !$skip{$1} :
            1
        } (keys %{$hash}) ;
    # Sort numerically if that is reasonable:
    return [ sort {$a =~ /\D/ || $b =~ /\D/ ? $a cmp $b : $a <=> $b} @a ];
}

1;