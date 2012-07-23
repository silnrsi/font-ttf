package Font::TTF::Gloc;

=head1 TITLE

Font::TTF::Gloc - Offsets into Glat table for the start of the attributes for each glyph

=head1 DESCRIPTION

The Gloc table is a bit like the Loca table only for Graphite glyph attributes. The table
has the following elements:

=over 4

=item Version

Table format version

=item numAttrib

Maximum number of attributes associated with a glyph.

=item locations

An array of offsets into the Glat table for the start of each glyph

=item names

If defined, an array of name table name ids indexed by attribute number.

=cut

use Font::TTF::Table;
use Font::TTF::Utils;
use strict;
use vars qw(@ISA);
@ISA = qw(Font::TTF::Table);

sub read
{
    my ($self) = @_;
    my ($fh) = $self->{' INFILE'};
    my ($numGlyphs) = $self->{' PARENT'}{'maxp'}{'numGlyphs'};
    my ($dat, $flags);

    $self->SUPER::read or return $self;
    $fh->read($dat, 4);
    ($self->{'Version'}) = TTF_Unpack("v", $dat);
    $fh->read($dat, 4);
    ($flags, $self->{'numAttrib'}) = TTF_Unpack("SS", $dat);
    if ($flags & 1)
    {
        $fh->read($dat, 4 * ($numGlyphs + 1));
        $self->{'locations'} = [unpack("N*", $dat)];
    }
    else
    {
        $fh->read($dat, 2 * ($numGlyphs + 1));
        $self->{'locations'} = [unpack("n*", $dat)];
    }
    if ($flags & 2)
    {
        $fh->read($dat, 2 * $self->{'numAttrib'});
        $self->{'names'} = [unpack("n*", $dat)];
    }
    return $self;
}

sub out
{
    my ($self, $fh) = @_;
    my ($numGlyphs) = $self->{' PARENT'}{'maxp'}{'numGlyphs'};
    my ($flags, $num);

    return $self->SUPER::out($fh) unless ($self->{' read'});
    $num = $self->{'numAttrib'};
    $flags = 1 if ($self->{'locations'}[-1] > 0xFFFF);
    $flags |= 2 if ($self->{'names'});
    $fh->print(TTF_Pack("vSS", $self->{'Version'}, $flags, $num));
    if ($flags & 1)
    { $fh->write(pack(($flags & 1 ? "N" : "n") . $numGlyphs, @{$self->{'locations'}})); }
    if ($flags & 2)
    { $fh->write(pack("n$num", @{$self->{'names'}})); }
}

1;

