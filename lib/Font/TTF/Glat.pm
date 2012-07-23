package Font::TTF::Glat;

use Font::TTF::Table;
use Font::TTF::Utils;
use strict;
use vars qw(@ISA);
@ISA = qw(Font::TTF::Table);

sub read
{
    my ($self) = @_;
    my ($gloc) = $self->{' PARENT'}{'Gloc'};
    my ($fh) = $self->{' INFILE'};
    my ($numGlyphs) = $self->{' PARENT'}{'maxp'}{'numGlyphs'};
    my ($base) = $self->{' OFFSET'};
    my ($dat, $i);

    $self->SUPER::read or return $self;
    $gloc->read;
    $fh->read($dat, 4);
    ($self->{'Version'}) = TTF_Unpack('v', $dat);

    for ($i = 0; $i < $numGlyphs; $i++)
    {
        my ($j) = 0;
        my ($num) = $gloc->{'locations'}[$i + 1] - $gloc->{'locations'}[$i];
        my ($first, $number, @vals);
        $fh->seek($base + $gloc->{'locations'}[$i], 0);
        $fh->read($dat, $num);
        if ($self->{'Version'} > 1)
        {
            ($first, $number) = unpack("n2", substr($dat, $j, 4));
            @vals = unpack("n$number", substr($dat, $j + 4, $number * 2));
        }
        else
        {
            ($first, $number) = unpack("C2", substr($dat, $j, 2));
            @vals = unpack("n$number", substr($dat, $j + 2, $number));
        }
        for (my $k = 0; $k < $number; $k++)
        { $self->{'attribs'}[$i]{$first + $k} = $vals[$k]; }
    }
}

sub out
{
    my ($self, $fh) = @_;
    my ($gloc) = $self->{' PARENT'}{'Gloc'};
    my ($numGlyphs) = $self->{' PARENT'}{'maxp'}{'numGlyphs'};
    my ($base) = $fh->tell();
    my ($i, $type);

    return $self->SUPER::out($fh) unless ($self->{' read'});
    if ($gloc->{'numAttrib'} > 256)
    {
        $self->{'Version'} = 2;
        $type = "n";
    }
    else
    {
        $self->{'Version'} = 1;
        $type = "C";
    }

    $gloc->{'locations'} = [];
    for ($i = 0; $i < $numGlyphs; $i++)
    {
        my (@a) = sort {$a <=> $b} keys %{$self->{'attribs'}[$i]};
        push(@{$gloc->{'locations'}}, $fh->tell() - $base);
        while (@a)
        {
            my ($first) = shift(@a);
            my ($next) = $first;
            my (@v, $j);
            while (@a and $a[0] <= $next + 2)
            { $next = shift(@a); }
            for ($j = $first; $j <= $next; $j++)
            { push (@v, $self->{'attribs'}[$i]{$j}); }
            { $fh->print(pack("${type}2n*", $first, $next - $first + 1, @v)); }
        }
    }
    push(@{$gloc->{'locations'}}, $fh->tell() - $base);
}

1;

