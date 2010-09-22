package Font::TTF::DSIG;

use strict;
use vars qw(@ISA);

require Font::TTF::Table;
use Font::TTF::Utils;

@ISA = qw(Font::TTF::Table);

sub create
{
    my ($class) = @_;
    my ($self) = { 'version' => 1, 'numtables' => 0, 'perms' => 0 };
    bless $self, ref $class || $class;
    return $self;
}

sub read
{
    my ($self) = @_;
    my ($dat, $i, @records, $r);

    $self->SUPER::read || return $self;
    $self->{' INFILE'}->read($dat, 8);
    ($self->{'version'}, $self->{'numtables'}, $self->{'perms'}) = unpack("LNN", $dat);
    for ($i = 0; $i < $self->{'numtables'}; $i++)
    {
        $self->{' INFILE'}->read($dat, 12);
        push (@records, [unpack("L3", $dat)]);
    }
    foreach $r (@records)
    {
        if ($r->[0] == 1)
        {
            $self->{' INFILE'}->seek($self->{' OFFSET'} + $r->[2]);
            $self->{' INFILE'}->read($dat, $r->[1]);
            push @{$self->{'records'}}, substr($dat, 8);
        }
    }
    $self;
}


sub out
{
    my ($self, $fh) = @_;
    my ($i, $curlen);

    return $self->SUPER::out($fh) unless $self->{' read'};      # this is never true
    $fh->print(pack("LNN", $self->{'version'}, $self->{'numtables'}, $self->{'perms'}));
    $curlen = 0;
    for ($i = 0; $i < $self->{'numtables'}; $i++)
    {
        $fh->print(pack("L3", 1, length($self->{'records'}[$i]) + 8, $curlen + $self->{'numtables'} * 12 + 8));
        $curlen += length($self->{'records'}[$i]) + 8;
    }
    for ($i = 0; $i < $self->{'numtables'}; $i++)
    {
        $fh->print(pack("NNL", 0, 0, length($self->{'records'}[$i])));
        $fh->print($self->{'records'}[$i]);
    }
    $self;
}
   
