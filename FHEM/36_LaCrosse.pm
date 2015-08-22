
# $Id: 36_LaCrosse.pm 8689 2015-06-04 14:42:19Z hcs-svn $


package main;

use strict;
use warnings;
use SetExtensions;

sub LaCrosse_Parse($$);


sub LaCrosse_Initialize($) {
  my ($hash) = @_;

  $hash->{Match}     = "^\\S+\\s+9 ";
  $hash->{SetFn}     = "LaCrosse_Set";
  ###$hash->{GetFn}     = "LaCrosse_Get";
  $hash->{DefFn}     = "LaCrosse_Define";
  $hash->{UndefFn}   = "LaCrosse_Undef";
  $hash->{FingerprintFn}   = "LaCrosse_Fingerprint";
  $hash->{ParseFn}   = "LaCrosse_Parse";
  ###$hash->{AttrFn}    = "LaCrosse_Attr";
  $hash->{AttrList}  = "IODev"
                       ." ignore:1"
                       ." doAverage:1"
                       ." doDewpoint:1"
                       ." filterThreshold"
                       ." resolution"
                       ." $readingFnAttributes";
}

sub LaCrosse_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(int(@a) < 3 || int(@a) > 5) {
    my $msg = "wrong syntax: define <name> LaCrosse <addr> [corr1...corr2]";
    Log3 undef, 2, $msg;
    return $msg;
  }

  $a[2] =~ m/^([\da-f]{2})$/i;
  return "$a[2] is not a valid LaCrosse address" if( !defined($1) );

  my $name = $a[0];
  my $addr = $a[2];

  $hash->{corr1} = ((int(@a) > 3) ? $a[3] : 0);
  $hash->{corr2} = ((int(@a) > 4) ? $a[4] : 0);

  return "LaCrosse device $addr already used for $modules{LaCrosse}{defptr}{$addr}->{NAME}." if( $modules{LaCrosse}{defptr}{$addr} && $modules{LaCrosse}{defptr}{$addr}->{NAME} ne $name );

  $hash->{addr} = $addr;

  $modules{LaCrosse}{defptr}{$addr} = $hash;

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } 
  else {
    Log3 $name, 1, "$name: no I/O device";
  }

  return undef;
}


#-----------------------------------#
sub LaCrosse_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $addr = $hash->{addr};

  delete( $modules{LaCrosse}{defptr}{$addr} );

  return undef;
}


#-----------------------------------#
sub LaCrosse_Get($@) {
  my ($hash, $name, $cmd, @args) = @_;

  return "\"get $name\" needs at least one parameter" if(@_ < 3);

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

#-----------------------------------#
sub LaCrosse_Attr(@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  return undef;
}


#-----------------------------------#
sub LaCrosse_Fingerprint($$) {
  my ($name, $msg) = @_;

  return ( "", $msg );
}


#-----------------------------------#
sub LaCrosse_CalcDewpoint (@) {
  my ($temp,$hum) = @_;

  my($SDD, $DD, $a, $b, $v, $DP);

  if($temp>=0) {
    $a = 7.5;
    $b = 237.3;
  } 
  else {
    $a = 7.6;
    $b = 240.7;
  }

  $SDD = 6.1078*10**(($a*$temp)/($b+$temp));
  $DD = $hum/100 * $SDD;
  $v = log($DD/6.1078)/log(10);

  $DP = ($b*$v)/($a-$v);

  return $DP;
}

#-----------------------------------#
sub LaCrosse_RemoveReplaceBattery($) {
  my $hash = shift;
  delete($hash->{replaceBattery});
}

sub LaCrosse_Set($@) {
  my ($hash, $name, $cmd, $arg, $arg2) = @_;

  my $list = "replaceBatteryForSec";

  if( $cmd eq "replaceBatteryForSec" ) {
    foreach my $d (sort keys %defs) {
      next if (!defined($defs{$d}) );
      next if ($defs{$d}->{TYPE} ne "LaCrosse" );
      LaCrosse_RemoveReplaceBattery{$defs{$d}};
    }
    return "Usage: set $name replaceBatteryForSec <seconds_active> [ignore_battery]" if(!$arg || $arg !~ m/^\d+$/ || ($arg2 && $arg2 ne "ignore_battery"));
    $hash->{replaceBattery} = $arg2?2:1;
    InternalTimer(gettimeofday()+$arg, "LaCrosse_RemoveReplaceBattery", $hash, 0);

  }
  else {
    return "Unknown argument $cmd, choose one of ".$list;
  }

  return undef;
}

#-----------------------------------#
sub LaCrosse_Parse($$) {
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  my( @bytes, $addr, $typeNumber, $typeName, $battery_new, $battery_low, $error, $type, $channel, $temperature, $humidity, $windDirection, $windSpeed, $windGust, $rain );    
  $temperature = 0xFFFF;
  $humidity = 0xFF;
  $windDirection = 0xFFFF;
  $windSpeed = 0xFFFF;
  $windGust = 0xFFFF;
  $rain = 0xFFFF;  
  $error = 0;
  
  if( $msg =~ m/^OK 9/ ) {
    # Temperature sensor - Format:
    #      0  1   3   3   4
    # ----------------------
    # OK 9 56 1   4   156 37     ID = 56  T: 18.0  H: 37  no NewBatt
    # OK 9 49 1   4   182 54     ID = 49  T: 20.6  H: 54  no NewBatt
    # OK 9 55 129 4 192 56       ID = 55  T: 21.6  H: 56  WITH NewBatt 
    
    # OK 9 2 1   4 212 106       ID = 2   T: 23.6  H: -- Channel: 1
    # OK 9 2 130 4 225 125       ID = 2   T: 24.9  H: -- Channel: 2
    
    # OK 9 ID XXX XXX XXX XXX
    # |  | |  |   |   |   |
    # |  | |  |   |   |   --- Humidity incl. WeakBatteryFlag
    # |  | |  |   |   |------ Temp * 10 + 1000 LSB
    # |  | |  |   |---------- Temp * 10 + 1000 MSB
    # |  | |  |-------------- Sensor type (1 or 2) +128 if NewBatteryFlag
    # |  | |----------------- Sensor ID
    # |  |------------------- fix "9"
    # |---------------------- fix "OK"

    @bytes = split( ' ', substr($msg, 5) );

    $addr = sprintf( "%02X", $bytes[0] );
    $battery_new = ($bytes[1] & 0x80) >> 7;
    $battery_low = ($bytes[4] & 0x80) >> 7;
    $typeNumber = 0;
    $typeName = "T(H)";
    $type = ($bytes[1] & 0x70) >> 4;
    $channel = $bytes[1] & 0x0F;
    $temperature = ($bytes[2]*256 + $bytes[3] - 1000)/10;
    $humidity = $bytes[4] & 0x7f;
  } 
  elsif ($msg =~ m/^OK WS/) {
    # Weather station - Format:
    #        0   1   2   3   4   5   6   7   8   9   10  11  12  13
    #   -----------------------------------------------------------
    #  OK WS 14  1   4   208 53  0   0   7   8   0   29  0   31  1  I D=0E  23.2°C  52%rH  0mm  Dir.: 180.0°  Wind:2.9m/s  Gust:3.1m/s  new Batt.
    #  OK WS ID  XXX TTT TTT HHH RRR RRR DDD DDD SSS SSS GGG GGG FFF
    #  |  |  |   |   |   |   |   |   |   |   |   |   |   |   |   |-- Flags *
    #  |  |  |   |   |   |   |   |   |   |   |   |   |   |   |------ WindGust * 10 LSB (0.0 ... 50.0 m/s)           FF/FF = none 
    #  |  |  |   |   |   |   |   |   |   |   |   |   |   |---------- WindGust * 10 MSB
    #  |  |  |   |   |   |   |   |   |   |   |   |   |-------------- WindSpeed  * 10 LSB(0.0 ... 50.0 m/s)          FF/FF = none  
    #  |  |  |   |   |   |   |   |   |   |   |   |------------------ WindSpeed  * 10 MSB
    #  |  |  |   |   |   |   |   |   |   |   |---------------------- WindDirection * 10 LSB (0.0 ... 365.0 Degrees) FF/FF = none
    #  |  |  |   |   |   |   |   |   |   |-------------------------- WindDirection * 10 MSB
    #  |  |  |   |   |   |   |   |   |------------------------------ Rain * 0.5mm LSB (0 ... 9999 mm)               FF/FF = none
    #  |  |  |   |   |   |   |   |---------------------------------- Rain * 0.5mm MSB
    #  |  |  |   |   |   |   |-------------------------------------- Humidity (1 ... 99 %rH)                        FF = none
    #  |  |  |   |   |   |------------------------------------------ Temp * 10 + 1000 LSB (-40 ... +60 °C)          FF/FF = none
    #  |  |  |   |   |---------------------------------------------- Temp * 10 + 1000 MSB
    #  |  |  |   |-------------------------------------------------- Sensor type (1=TX22)
    #  |  |  |------------------------------------------------------ Sensor ID (1 ... 63)
    #  |  |--------------------------------------------------------- fix "WS"
    #  |------------------------------------------------------------ fix "OK"
    #
    #   * Flags: 128  64  32  16  8   4   2   1        
    #                                 |   |   |
    #                                 |   |   |-- New battery
    #                                 |   |------ ERROR
    #                                 |---------- Low battery
    
    @bytes = split( ' ', substr($msg, 5) );
    
    $addr = sprintf( "%02X", $bytes[0] );
    $typeNumber = $bytes[1];
    $typeName = $typeNumber == 1 ? "TX22" : "unknown";
    
    $battery_new = $bytes[13] & 0x01;
    $battery_low = $bytes[13] & 0x04;
    $error = $bytes[13] & 0x02;
    $type = 0;
    $channel = 1;

    my $rh = $modules{LaCrosse}{defptr}{$addr};
    
    if($bytes[2] != 0xFF && $bytes[3] != 0xFF) {
      $temperature = ($bytes[2]*256 + $bytes[3] - 1000)/10;
      $rh->{"bufferedT"} = $temperature;
    }
    else {
      if(defined($rh->{"bufferedT"})) {
        $temperature = $rh->{"bufferedT"};
      }
    }
    
    if($bytes[4] != 0xFF) {
      $humidity = $bytes[4];
      if (defined($rh)) {
        $rh->{"bufferedH"} = $humidity;
      }
    }
    else {
      if(defined($rh->{"bufferedH"})) {
        $humidity = $rh->{"bufferedH"};
      }
    }
    
    
    if($bytes[5] != 0xFF && $bytes[6] != 0xFF) {
      $rain = ($bytes[5]*256 + $bytes[6]) * 0.5;
    }
    if($bytes[7] != 0xFF && $bytes[8] != 0xFF) {
      $windDirection = ($bytes[7]*256 + $bytes[8]) / 10;
    }
    if($bytes[9] != 0xFF && $bytes[10] != 0xFF) {
      $windSpeed = ($bytes[9] * 256 + $bytes[10]) / 10;
    }
    if($bytes[11] != 0xFF && $bytes[12] != 0xFF) {
      $windGust = ($bytes[11] * 256 + $bytes[12]) / 10;
    }
    
  }
  else {
    DoTrigger($name, "UNKNOWNCODE $msg");
    Log3 $name, 3, "$name: Unknown code $msg, help me!";
    return "";
  }

  my $raddr = $addr;
  my $rhash = $modules{LaCrosse}{defptr}{$raddr};
  my $rname = $rhash?$rhash->{NAME}:$raddr;

  return "" if( IsIgnored($rname) );

  if( !$modules{LaCrosse}{defptr}{$raddr} ) {
    foreach my $d (sort keys %defs) {
      next if( !defined($defs{$d}) );
      next if( !defined($defs{$d}->{TYPE}) );
      next if( $defs{$d}->{TYPE} ne "LaCrosse" );
      next if( !$defs{$d}->{replaceBattery} );
      if( $battery_new ||  $defs{$d}->{replaceBattery} == 2 ) {
        $rhash = $defs{$d};
        $raddr = $rhash->{addr};

        Log3 $name, 3, "LaCrosse: Changing device $rname from $raddr to $addr";

        delete $modules{LaCrosse}{defptr}{$raddr};
        $rhash->{DEF} = $addr;
        $rhash->{addr} = $addr;
        $modules{LaCrosse}{defptr}{$addr} = $rhash;

        LaCrosse_RemoveReplaceBattery($rhash);

        CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

        return "";
      }
    }
    Log3 $name, 3, "LaCrosse: Unknown device $rname, please define it";

    Log3 $name, 3, "LaCrosse: check commandref on usage of LaCrossePairForSec" if( !$hash->{LaCrossePair} && !defined($modules{LaCrosse}{defptr}) );
   
    return "" if( !$hash->{LaCrossePair} );

    return "UNDEFINED LaCrosse_$rname LaCrosse $raddr" if( $battery_new || $hash->{LaCrossePair} == 2 );
    return "";
  }

  $rhash->{battery_new} = $battery_new;

  my @list;
  push(@list, $rname);

  $rhash->{LaCrosse_lastRcv} = TimeNow();
  $rhash->{"sensorType"} = "$typeNumber=$typeName"; 

  if( $type == 0x00) {
    $channel = "" if( $channel == 1 );
                                         
    # Handle resolution
    if(my $resolution = AttrVal( $rname, "resolution", 0 )) {
      if ($temperature != 0xFFFF) {
        $temperature = int($temperature*10 / $resolution + 0.5) * $resolution / 10;
      }
      if ($humidity != 0xFF) {
        $humidity = int($humidity / $resolution + 0.5) * $resolution;
      }
    }
  
    # Calculate average
    if( AttrVal( $rname, "doAverage", 0 ) && defined($rhash->{"previousT$channel"}) && $temperature != 0xFFFF ) {
      $temperature = ($rhash->{"previousT$channel"}*3+$temperature)/4;
    }
    if( AttrVal( $rname, "doAverage", 0 ) && defined($rhash->{"previousH$channel"}) && $humidity != 0xFF ) {
      $humidity = ($rhash->{"previousH$channel"}*3+$humidity)/4;
    }
    
    # Check filterThreshold
    if( defined($rhash->{"previousT$channel"})
        && abs($rhash->{"previousH$channel"} - $humidity) <= AttrVal( $rname, "filterThreshold", 10 )
        && abs($rhash->{"previousT$channel"} - $temperature) <= AttrVal( $rname, "filterThreshold", 10 ) ) {

      readingsBeginUpdate($rhash);

      if ($typeNumber > 0) {
        readingsBulkUpdate($rhash, "error", $error ? "1" : "0");
      }

      # Battery state
      readingsBulkUpdate($rhash, "battery$channel", $battery_low?"low":"ok");

      # Calculate dewpoint
      my $dewpoint;
      if( AttrVal( $rname, "doDewpoint", 0 ) && $humidity && $humidity <= 99 && $temperature != 0xFFFF ) {
        $dewpoint = LaCrosse_CalcDewpoint($temperature,$humidity);
        $dewpoint = int($dewpoint*10 + 0.5) / 10;
        readingsBulkUpdate($rhash, "dewpoint$channel", $dewpoint);
      }
      
      # Round and write temperature and humidity
      if ($temperature != 0xFFFF) {           
        $temperature = int($temperature*10 + 0.5) / 10;
        readingsBulkUpdate($rhash, "temperature$channel", $temperature + $rhash->{corr1});
      }
      if ($humidity && $humidity <= 99) {
        $humidity = int($humidity*10 + 0.5) / 10;
        readingsBulkUpdate($rhash, "humidity$channel", $humidity + $rhash->{corr2} );
      }

      # STATE
      if( !$channel ) {
        my $state = "T: ". ($temperature + $rhash->{corr1});
        $state .= " H: ". ($humidity + $rhash->{corr2}) if( $humidity && $humidity <= 99 );
        $state .= " D: $dewpoint" if( $dewpoint );
        
        readingsBulkUpdate($rhash, "state", $state) if( Value($rname) ne $state );
      }

      readingsEndUpdate($rhash,1);
    } 
    else {
      readingsSingleUpdate($rhash, "battery$channel", $battery_low ? "low" : "ok", 1);
    }

    $rhash->{"previousT$channel"} = $temperature;
    $rhash->{"previousH$channel"} = $humidity;
    
    readingsBeginUpdate($rhash);
    
    if ($typeNumber > 0 && $windSpeed != 0xFFFF) {
      readingsBulkUpdate($rhash, "windSpeed", $windSpeed );
    }
    
    if ($typeNumber > 0 && $windGust != 0xFFFF) {
      readingsBulkUpdate($rhash, "windGust", $windGust );
    }
    
    if ($typeNumber > 0 && $rain != 0xFFFF) {
      readingsBulkUpdate($rhash, "rain", $rain );
    }
    
    if ($typeNumber > 0 && $windDirection != 0xFFFF) {
      readingsBulkUpdate($rhash, "windDirectionDegree", $windDirection );
      
      my $windDirectionText = "---";
      if    ($windDirection >=    0 && $windDirection <=  11.2) { $windDirectionText = "N"; }
      elsif ($windDirection >  11.2 && $windDirection <=  33.7) { $windDirectionText = "NNE"; }
      elsif ($windDirection >  33.7 && $windDirection <=  56.2) { $windDirectionText = "NE"; }
      elsif ($windDirection >  56.2 && $windDirection <=  78.7) { $windDirectionText = "ENE"; }
      elsif ($windDirection >  78.7 && $windDirection <= 101.2) { $windDirectionText = "E"; }
      elsif ($windDirection > 101.2 && $windDirection <= 123.7) { $windDirectionText = "ESE"; }
      elsif ($windDirection > 123.7 && $windDirection <= 146.2) { $windDirectionText = "SE"; }
      elsif ($windDirection > 146.2 && $windDirection <= 168.7) { $windDirectionText = "SSE"; }
      elsif ($windDirection > 168.7 && $windDirection <= 191.2) { $windDirectionText = "S"; }
      elsif ($windDirection > 191.2 && $windDirection <= 213.7) { $windDirectionText = "SSW"; }
      elsif ($windDirection > 213.7 && $windDirection <= 236.2) { $windDirectionText = "SW"; }
      elsif ($windDirection > 236.2 && $windDirection <= 258.7) { $windDirectionText = "WSW"; }
      elsif ($windDirection > 258.7 && $windDirection <= 281.2) { $windDirectionText = "W"; }
      elsif ($windDirection > 281.2 && $windDirection <= 303.7) { $windDirectionText = "WNW"; }
      elsif ($windDirection > 303.7 && $windDirection <= 326.2) { $windDirectionText = "NW"; }
      elsif ($windDirection > 326.2 && $windDirection <= 348.7) { $windDirectionText = "NNW"; };
      
      readingsBulkUpdate($rhash, "windDirectionText", $windDirectionText );
    }
    
    readingsEndUpdate($rhash,1);
    
  }

  return @list;
}


1;

=pod
=begin html

<a name="LaCrosse"></a>
<h3>LaCrosse</h3>
<ul>

  <tr><td>
  FHEM module for LaCrosse Temperature and Humidity sensors and weather stations like WS 1600 (TX22 sensor).<br><br>

  It can be integrated in to FHEM via a <a href="#JeeLink">JeeLink</a> as the IODevice.<br><br>

  The JeeNode sketch required for this module can be found in .../contrib/36_LaCrosse-pcaSerial.zip.<br><br>

  <a name="LaCrosseDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LaCrosse &lt;addr&gt; [corr1...corr2]</code> <br>
    <br>
    addr is a 2 digit hex number to identify the LaCrosse device.<br>
    corr1..corr2 are up to 2 numerical correction factors, which will be added to the respective value to calibrate the device.<br><br>
    Note: devices are autocreated only if LaCrossePairForSec is active for the <a href="#JeeLink">JeeLink</a> IODevice device.<br>
  </ul>
  <br>

  <a name="LaCrosse_Set"></a>
  <b>Set</b>
  <ul>
    <li>replaceBatteryForSec &lt;sec&gt; [ignore_battery]<br>
    sets the device for &lt;sec&gt; seconds into replace battery mode. the first unknown address that is
    received will replace the current device address. this can be partly automated with a readings group configured
    to show the battery state of all LaCrosse devices and a link/command to set replaceBatteryForSec on klick.
    </li>
  </ul><br>

  <a name="LaCrosse_Get"></a>
  <b>Get</b>
  <ul>
  </ul><br>

  <a name="LaCrosse_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>battery[]<br>
      ok or low</li>
    <li>temperature (°C)<br>
      Notice: see the filterThreshold attribute.</li>
    <li>humidity (%rH)</li>
    <li>Wind speed (m/s), gust (m/s) and direction (degree)</li>
    <li>Rain (mm)</li>
  </ul><br>

  <a name="LaCrosse_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>doAverage<br>
      use an average of the last 4 values for temperature and humidity readings</li>
    <li>doDewpoint<br>
      calculate dewpoint</li>
    <li>filterThreshold<br>
      if the difference between the current and previous temperature is greater than filterThreshold degrees
      the readings for this channel are not updated. the default is 10.</li>
    <li>resolution<br>
      the resolution in 1/10 degree for the temperature reading</li>
    <li>ignore<br>
    1 -> ignore this device.</li>
  </ul><br>
</ul>

=end html
=cut
