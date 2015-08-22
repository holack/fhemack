
# $Id: 36_Level.pm 6317 2014-07-25 19:20:59Z hcs-svn $
#
# TODO:

package main;

use strict;
use warnings;
use SetExtensions;

sub Level_Parse($$);

sub
Level_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}         = "^OK\\sLS\\s";
  $hash->{DefFn}         = "Level_Define";
  $hash->{UndefFn}       = "Level_Undef";
  $hash->{FingerprintFn} = "Level_Fingerprint";
  $hash->{ParseFn}       = "Level_Parse";
  $hash->{AttrList}      = "IODev"
                         ." ignore:1"
                         ." doAverage:1"
                         ." filterThreshold"
                         ." litersPerCm"
                         ." distanceToBottom"
                         ." $readingFnAttributes";
}

sub
Level_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3 ) {
    my $msg = "wrong syntax: define <name> Level <addr>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  $a[2] =~ m/^([\da-f]{1})$/i;
  return "$a[2] is not a valid Level address" if( !defined($1) );

  my $name = $a[0];
  my $addr = $a[2];

  return "Level device $addr already used for $modules{Level}{defptr}{$addr}->{NAME}." if( $modules{Level}{defptr}{$addr}
                                                                                             && $modules{Level}{defptr}{$addr}->{NAME} ne $name );

  $hash->{addr} = $addr;

  $modules{Level}{defptr}{$addr} = $hash;

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }
    
  return undef;
}

#####################################
sub
Level_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $addr = $hash->{addr};

  delete( $modules{Level}{defptr}{$addr} );

  return undef;
}


#####################################
sub
Level_Get($@)
{
  my ($hash, $name, $cmd, @args) = @_;

  return "\"get $name\" needs at least one parameter" if(@_ < 3);

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

sub
Level_Fingerprint($$)
{
  my ($name, $msg) = @_;

  return ( "", $msg );
}

# Format
#  
#   OK LS 1  0    5   100 4   191 60      =  38,0cm    21,5°C   6,0V
#   OK LS 1  0    8   167 4   251 57      = 121,5cm    27,5°C   5,7V   
#
#         0  1    2   3   4   5   6 
#   OK LS ID T    LL  LL  TT  TT  VV
#   |  |  |  |    |   |   |   |   |
#   |  |  |  |    |   |   |   |   `--- Voltage * 10
#   |  |  |  |    |   |   |   `------- Temp. * 10 + 1000 LSB
#   |  |  |  |    |   |   `----------- Temp. * 10 + 1000 MSB
#   |  |  |  |    |   `--------------- Level * 10 + 1000 LSB
#   |  |  |  |    `------------------- Level * 10 + 1000 MSB
#   |  |  |  `------------------------ Sensor type fix 0 at the moment
#   |  |  `--------------------------- Sensor ID ( 0 .. 15)
#   |  `------------------------------ fix "LS"
#   `--------------------------------- fix "OK"
sub
Level_Parse($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  my( @bytes, $addr, $type, $distance, $temperature, $voltage );
  if( $msg =~ m/^OK LS/ ) {
    @bytes = split( ' ', substr($msg, 5) );

    $addr = sprintf( "%01X", $bytes[0] );
    $type = $bytes[1];
    $distance = ($bytes[2]*256 + $bytes[3] - 1000)/10;
    $temperature = ($bytes[4]*256 + $bytes[5] - 1000)/10;
    $voltage = $bytes[6] / 10;
  } else {
    DoTrigger($name, "UNKNOWNCODE $msg");
    Log3 $name, 3, "$name: Unknown code $msg, help me!";
    return undef;
  }

  my $raddr = $addr;
  my $rhash = $modules{Level}{defptr}{$raddr};
  my $rname = $rhash?$rhash->{NAME}:$raddr;
  
  if( !$modules{Level}{defptr}{$raddr} ) {    
    Log3 $name, 3, "Level Unknown device $rname, please define it";

    my $iohash = $rhash->{IODev};

    return undef;
  }

  my @list;
  push(@list, $rname);

  $rhash->{Level_lastRcv} = TimeNow();

  readingsBeginUpdate($rhash);
  
  my $litersPerCm = AttrVal( $rname, "litersPerCm", 1);
  my $distanceToBottom = AttrVal( $rname, "distanceToBottom", 100);
  
  my $level = $distanceToBottom - $distance;
  my $liters = $litersPerCm * $level;
  
  if( AttrVal( $rname, "doAverage", 0 ) && defined($rhash->{"previousLiters"}) ) {
    $liters = int(($rhash->{"previousLiters"}*3+$liters)/4);
  }
  if( AttrVal( $rname, "doAverage", 0 ) && defined($rhash->{"previousTemeprature"}) ) {
    $temperature = int(($rhash->{"previousTemeprature"}*3+$temperature)/4);
  }
      
  readingsBulkUpdate($rhash, "distance", $distance);
  readingsBulkUpdate($rhash, "level", $level);
  readingsBulkUpdate($rhash, "liters", $liters);
  readingsBulkUpdate($rhash, "temperature", $temperature);
  readingsBulkUpdate($rhash, "voltage", $voltage);
  
  my $state = "L: $liters";
  $state .= " T: $temperature";
  $state .= " V: $voltage";
  readingsBulkUpdate($rhash, "state", $state) if( Value($rname) ne $state );

  readingsEndUpdate($rhash,1);

  $rhash->{"previousLiters"} = $liters;
  $rhash->{"previousTemperature"} = $temperature;

  return @list;
}

sub
Level_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  return undef;
}

1;

=pod
=begin html

<a name="Level"></a>
<h3>Level</h3>

<ul>
  <tr><td>
  FHEM module for Level.<br><br>

  It can be integrated in to FHEM via a <a href="#JeeLink">JeeLink</a> as the IODevice.<br><br>

  The JeeNode sketch required for this module can be found in .../contrib/36_LaCrosse-LaCrosseITPlusReader.zip. It must be at least version 10.0c<br><br>

  For more information see: http://forum.fhem.de/index.php/topic,23217.msg165163.html#msg165163<br><br>
  
  <a name="Level_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Level &lt;addr&gt;</code> <br>
    addr is a 1 digit hex number (0 .. F) to identify the Level device.
    <br><br>
  </ul>
  
  <a name="Level_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>liters<br>
    Calculated liters based on distanceToBottom, distance and litersPerCm</li>
    <li>temperature<br>
    Measured temperature</li>
    <li>voltage<br>
    Measured battery voltage</li>
    <li>distance<br>
    Measured distance from the sensor to the fluid</li>
    <li>level<br>
    Calculated level based on the distanceToBottom attribute</li>
  </ul><br>

  <a name="Level_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>distanceToBottom<br>
    Distance from the ultra sonic sensor to the bottom of the tank</li>
    <li>litersPerCm<br>
    Liters for each cm level</li>
  </ul><br>
</ul>

=end html
=cut
