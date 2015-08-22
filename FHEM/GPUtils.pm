##############################################
# $Id: GPUtils.pm 6653 2014-10-02 11:59:37Z ntruchsess $
##############################################
package GPUtils;
use Exporter qw( import );

use strict;
use warnings;

our %EXPORT_TAGS = (all => [qw(GP_Define GP_Catch GP_ForallClients GP_Import)]);
Exporter::export_ok_tags('all');

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
  if (!grep(/FHEM\/lib$/,@INC)) {
    foreach my $inc (grep(/FHEM$/,@INC)) {
      push @INC,$inc."/lib";
    };
  };
};

sub GP_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  my $module = $main::modules{$hash->{TYPE}};
  return $module->{NumArgs}." arguments expected" if ((defined $module->{NumArgs}) and ($module->{NumArgs} ne scalar(@a)-2));
  $hash->{STATE} = 'defined';
  if ($main::init_done) {
    eval { &{$module->{InitFn}}( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return GP_Catch($@) if $@;
  }
  return undef;
}

sub GP_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

sub GP_ForallClients($$@)
{
  my ($hash,$fn,@args) = @_;
  foreach my $d ( sort keys %main::defs ) {
    if (   defined( $main::defs{$d} )
      && defined( $main::defs{$d}{IODev} )
      && $main::defs{$d}{IODev} == $hash ) {
      	&$fn($main::defs{$d},@args);
    }
  }
  return undef;
}

sub GP_Import(@)
{
  no strict qw/refs/; ## no critic
  my $pkg = caller(0);
  foreach (@_) {
    *{$pkg.'::'.$_} = *{'main::'.$_};
  }
}

1;

