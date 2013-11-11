use strict;
use ExtUtils::MakeMaker;
use Getopt::Std;

our ($opt_d, $opt_r, $opt_v);
getopts('d:rv:');

my %pbuilderopts = (
	'gutsy' => '--bindmounts /media/hosk_1'
	);

$opt_v ||= 1;

if ($^O eq 'linux' && !defined $opt_d)
{
    $opt_d = `lsb_release -c`;
    $opt_d =~ s/^.*?(\w+)\s*$/$1/o;
}

my (@extras, @theselibs);

@theselibs = (grep {-f } glob("lib/Font/TTF/*"), "lib/Font/TTF.pm");

# incantation to enable MY::pm_to_blib later on
if ($^O eq 'MSWin32')
{
    push(@ExtUtils::MakeMaker::Overridable, qw(pm_to_blib));
    @extras = ('dist' => { 'TO_UNIX' => 'perl -Mtounix -e "tounix(\"$(DISTVNAME)\")"' });
}

if ($^O eq 'MSWin32') {
	# incantation to solve the problem of everyone's $Config{make} being 'nmake'
	# when we want 'pmake'. And $Config{} is read only.
	# actually, this is just a copy of the code from ExtUtiles::MM_Win32 tidied
	# up (to expose tabs) and the dependency on Config removed
	*MY::pm_to_blib = sub
	{
	    my $self = shift;
	    my($autodir) = $self->catdir('$(INST_LIB)','auto');
	    return <<"EOT";

pm_to_blib: \$(TO_INST_PM)
\t$self->{NOECHO}\$(PERL) \"-I\$(INST_ARCHLINE)\" \"-I\$(INST_LIB)\" \\
\t\"-I\$(PERL_ARCHLIB)\" \"-I\$(PERL_LIB)\" -MExtUtils::Install \\
\t-e \"pm_to_blib({ qw[\$(PM_TO_BLIB)] }, '$autodir')
\t$self->{NOECHO}\$(TOUCH) \$@

EOT
	};

}
elsif ($^O eq 'linux')
{

	*MY::postamble = sub
	{
	    my ($self) = @_;
	    my ($res);
	    my ($package) = lc($self->{'NAME'});
		my ($pversion) = $self->{'VERSION'};
	    my ($svn) = `svnversion`;
		my ($sign) = '--auto-debsign' if ($opt_r);
	    my ($fpackage);
	
        $svn =~ s/\s+$//o;
        if ($svn and $svn ne "exported")
        {
    	    $svn =~ s/[0-9]*://og;
        }
        else
        {
            $svn = `hg identify -n`;
            $svn =~ s/\+?\s+$//o;
        }
	    $package =~ s/::/-/g;
	    $package = "lib${package}-perl";
	    $pversion .= "+$svn" unless ($opt_r);
	    $fpackage = "$package-$pversion";
	
	    $res = <<"EOT";
debsrc: dist
	rm -fr $self->{'DISTVNAME'}
	rm -fr $package
	rm -fr $fpackage
	tar xvzf $self->{'DISTVNAME'}.tar.gz
	cp -r $self->{'DISTVNAME'} $package
	tar cvzf ${package}_${pversion}.orig.tar.gz $package
	cp -r $package $fpackage
	cp -a debian $fpackage
	cd $fpackage && dch -v $pversion "interim dev release" && dpkg-buildpackage -S

# make deb builds an interim deb from svn source for release
deb: deb-base
EOT
	
	    foreach my $d (split(' ', $opt_d))
	    {
	    	$res .= <<"EOT";
	mkdir -p dists/$d	
	dch -D $d -v $pversion-$opt_v -m -b -c $fpackage/debian/changelog "Auto build from perl for $d"
	cd $fpackage && pdebuild --buildresult ../dists/$d -- --basetgz /var/cache/pbuilder/base-$d.tgz $pbuilderopts{$d}
EOT
	    }
	
	    return $res;
	};
	
}

my %makeinfo = (
        NAME => 'Font::TTF',
        VERSION_FROM => 'lib/Font/TTF.pm',
#        VERSION => "0.38",
#        HTMLLIBPODS => {map {my $t = $_; $t=~s/\..*?$/.html/o; $t='blib/Html/'.$t; $_ => $t;} @theselibs},
#        HTMLSCRIPTPODS => {map {my $t=$_; $t=~s/\..*?$/.html/o; $t='blib/Html/'.$t; $_ => $t;} @scripts},
        AUTHOR => "martin_hosken\@sil.org",
        ABSTRACT => "TTF font support for Perl",
        LICENSE => "artistic_2",
        PREREQ_PM => {
            'IO::String' => 0
        },
        @extras
    );

WriteMakefile(%makeinfo);

