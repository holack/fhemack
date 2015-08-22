
# $Id: 31_HUEDevice.pm 8410 2015-04-09 18:23:30Z justme1968 $

# "Hue Personal Wireless Lighting" is a trademark owned by Koninklijke Philips Electronics N.V.,
# see www.meethue.com for more information.
# I am in no way affiliated with the Philips organization.

package main;

use strict;
use warnings;

use Color;

use POSIX;
use JSON;
use SetExtensions;

use vars qw(%FW_webArgs); # all arguments specified in the GET

my %hueModels = (
  LCT001 => {name => 'Hue Bulb'                 ,type => 'Extended Color light'   ,subType => 'extcolordimmer',},
  LCT002 => {name => 'Hue Bulb BR30'            ,type => 'Extended Color light'   ,subType => 'extcolordimmer',},
  LCT003 => {name => 'Hue Bulb GU10'            ,type => 'Extended Color light'   ,subType => 'extcolordimmer',},
  LLC001 => {name => 'Living Colors G2'         ,type => 'Color Light'            ,subType => 'colordimmer',},
  LLC005 => {name => 'Living Colors Bloom'      ,type => 'Color Light'            ,subType => 'colordimmer',},
  LLC006 => {name => 'Living Colors Gen3 Iris'  ,type => 'Color Light'            ,subType => 'colordimmer',},
  LLC007 => {name => 'Living Colors Gen3 Bloom' ,type => 'Color Light'            ,subType => 'colordimmer',},
  LLC010 => {name => 'Hue Living Colors Iris'   ,type => 'Color Light'            ,subType => 'colordimmer',},
  LLC011 => {name => 'Hue Living Colors Bloom'  ,type => 'Color Light'            ,subType => 'colordimmer',},
  LLC012 => {name => 'Hue Living Colors Bloom'  ,type => 'Color Light'            ,subType => 'colordimmer',},
  LLC013 => {name => 'Disney Living Colors'     ,type => 'Color Light'            ,subType => 'colordimmer',},
  LLC014 => {name => 'Living Colors Aura'       ,type => 'Color Light'            ,subType => 'colordimmer',},
  LLM001 => {name => 'Color Light Module'       ,type => 'Extended Color Light'   ,subType => 'extcolordimmer',},
  LLM010 => {name => 'Color Temperature Module' ,type => 'Extended Temperature Light'   ,subType => 'ctdimmer',},
  LLM011 => {name => 'Color Temperature Module' ,type => 'Extended Temperature Light'   ,subType => 'ctdimmer',},
  LLM012 => {name => 'Color Temperature Module' ,type => 'Extended Temperature Light'   ,subType => 'ctdimmer',},
  LST001 => {name => 'Hue LightStrips'          ,type => 'Color Light'            ,subType => 'colordimmer',},
  LWB001 => {name => 'Living Whites Bulb'       ,type => 'Dimmable light'         ,subType => 'dimmer',},
  LWB003 => {name => 'Living Whites Bulb'       ,type => 'Dimmable light'         ,subType => 'dimmer',},
  LWB004 => {name => 'Hue Lux'                  ,type => 'Dimmable light'         ,subType => 'dimmer',},
  LWL001 => {name => 'LivingWhites Outlet'      ,type => 'Dimmable plug-in unit'  ,subType => 'dimmer',},

 'FLS-H3'  => {name => 'dresden elektronik FLS-H lp'  ,type => 'Color Temperature Light' ,subType => 'ctdimmer',},
 'FLS-PP3' => {name => 'dresden elektronik FLS-PP lp' ,type => 'Extended Color Light'    ,subType => 'extcolordimmer',},

 'Flex RGBW'        => {name => 'LIGHTIFY Flex RGBW'                   ,type => 'Extended Color Light'    ,subType => 'extcolordimmer',},
 'Classic A60 RGBW' => {name => 'LIGHTIFY Classic A60 RGBW'            ,type => 'Extended Color Light'    ,subType => 'extcolordimmer',},
 'Gardenspot RGB'   => {name => 'LIGHTIFY Gardenspot Mini RGB'         ,type => 'Color Light'             ,subType => 'colordimmer',},
 'Surface Light TW' => {name => 'LIGHTIFY Surface light tunable white' ,type => 'Color Temperature Light' ,subType => 'ctdimmer',},
 'Classic A60 TW'   => {name => 'LIGHTIFY Classic A60 tunable white'   ,type => 'Color Temperature Light' ,subType => 'ctdimmer',},
 'PAR16 50 TW'      => {name => 'LIGHTIFY PAR16 50 tunable white'      ,type => 'Color Temperature Light' ,subType => 'ctdimmer',},
);

my %dim_values = (
   0 => "dim06%",
   1 => "dim12%",
   2 => "dim18%",
   3 => "dim25%",
   4 => "dim31%",
   5 => "dim37%",
   6 => "dim43%",
   7 => "dim50%",
   8 => "dim56%",
   9 => "dim62%",
  10 => "dim68%",
  11 => "dim75%",
  12 => "dim81%",
  13 => "dim87%",
  14 => "dim93%",
);



sub HUEDevice_Initialize($)
{
  my ($hash) = @_;

  # Provide

  #Consumer
  $hash->{DefFn}    = "HUEDevice_Define";
  $hash->{UndefFn}  = "HUEDevice_Undefine";
  $hash->{SetFn}    = "HUEDevice_Set";
  $hash->{GetFn}    = "HUEDevice_Get";
  $hash->{AttrList} = "IODev ".
                      "delayedUpdate:1 ".
                      "realtimePicker:1 ".
                      "color-icons:1,2 ".
                      "transitiontime ".
                      "model:".join(",", sort map { $_ =~ s/ /#/g ;$_} keys %hueModels)." ".
                      "subType:extcolordimmer,colordimmer,ctdimmer,dimmer,switch ".
                      $readingFnAttributes;

  #$hash->{FW_summaryFn} = "HUEDevice_summaryFn";

  FHEM_colorpickerInit();
}

sub
HUEDevice_devStateIcon($)
{
  my($hash) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );
  return undef if( $hash->{helper}->{devtype} );

  my $name = $hash->{NAME};

  return ".*:light_question" if( !$hash->{helper}{reachable} );

  return ".*:off:toggle" if( ReadingsVal($name,"state","off") eq "off" );

  my $percent = ReadingsVal($name,"pct","100");
  my $s = $dim_values{int($percent/7)};
  $s="on" if( $percent eq "100" );

  return ".*:$s:toggle" if( $attr{$name}{subType} eq "dimmer" );
  return ".*:$s:toggle" if( AttrVal($name, "model", "") eq "LWL001" );

  #return ".*:$s:toggle" if( AttrVal($name, "model", "") eq "LWB001" );
  #return ".*:$s:toggle" if( AttrVal($name, "model", "") eq "LWB003" );
  #return ".*:$s:toggle" if( AttrVal($name, "model", "") eq "LWB004" );


  return ".*:$s@#".CommandGet("","$name RGB").":ct:hue:pct" if( $percent < 100 && AttrVal($name, "color-icons", 0) == 2 );
  return ".*:on@#".CommandGet("","$name rgb").":ct:hue:pct" if( AttrVal($name, "color-icons", 0) != 0 );

  return '<div style="width:32px;height:19px;'.
         'border:1px solid #fff;border-radius:8px;background-color:#'.CommandGet("","$name rgb").';"></div>';
}
sub
HUEDevice_summaryFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash   = $defs{$d};
  my $name = $hash->{NAME};

  return HUEDevice_devStateIcon($hash);
}

sub HUEDevice_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  $hash->{helper}->{devtype} = "";
  if( $args[2] eq "group" ) {
    $hash->{helper}->{devtype} = "G";
    splice( @args, 2, 1 );
  } elsif( $args[2] eq "sensor" ) {
    $hash->{helper}->{devtype} = "S";
    splice( @args, 2, 1 );
  }

  my $iodev;
  my $i = 0;
  foreach my $param ( @args ) {
    if( $param =~ m/IODev=(.*)/ ) {
      $iodev = $1;
      splice( @args, $i, 1 );
      last;
    }
    $i++;
  }


  return "Usage: define <name> HUEDevice [group|sensor] <id> [interval]"  if(@args < 3);

  my ($name, $type, $id, $interval) = @args;

  $hash->{STATE} = 'Initialized';

  $hash->{ID} = $hash->{helper}->{devtype}.$id;

  AssignIoPort($hash,$iodev) if( !$hash->{IODev} );
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  my $code = $hash->{ID};
  $code = $hash->{IODev}->{NAME} ."-". $code if( defined($hash->{IODev}->{NAME}) );
  my $d = $modules{HUEDevice}{defptr}{$code};
  return "HUEDevice device $hash->{ID} on HUEBridge $d->{IODev}->{NAME} already defined as $d->{NAME}."
         if( defined($d)
             && $d->{IODev} == $hash->{IODev}
             && $d->{NAME} ne $name );

  $modules{HUEDevice}{defptr}{$code} = $hash;

  if( AttrVal($hash->{IODev}->{NAME}, "pollDevices", undef) ) {
    $interval = 0 unless defined($interval);
  } else {
    $interval = 60 unless defined($interval);
  }

  $interval = 60 if( $interval && $interval < 10 );

  $args[3] = "" if( !defined( $args[3] ) );
  if( !$hash->{helper}->{devtype} ) {
    $hash->{DEF} = "$id $args[3]";

    $hash->{INTERVAL} = $interval;

    $hash->{helper}{on} = -1;
    $hash->{helper}{reachable} = undef;
    $hash->{helper}{colormode} = '';
    $hash->{helper}{bri} = -1;
    $hash->{helper}{ct} = -1;
    $hash->{helper}{hue} = -1;
    $hash->{helper}{sat} = -1;
    $hash->{helper}{xy} = '';
    $hash->{helper}{alert} = '';
    $hash->{helper}{effect} = '';

    $hash->{helper}{percent} = -1;

    $attr{$name}{devStateIcon} = '{(HUEDevice_devStateIcon($name),"toggle")}' if( !defined( $attr{$name}{devStateIcon} ) );

    my $icon_path = AttrVal("WEB", "iconPath", "default:fhemSVG:openautomation" );
    $attr{$name}{'color-icons'} = 2 if( !defined( $attr{$name}{'color-icons'} ) && $icon_path =~ m/openautomation/ );

  } elsif( $hash->{helper}->{devtype} eq 'G' ) {
    $hash->{DEF} = "group $id $args[3]";
    $attr{$name}{delayedUpdate} = 1 if( !defined( $attr{$name}{delayedUpdate} ) );

  } elsif( $hash->{helper}->{devtype} eq 'S' ) {
    $hash->{DEF} = "sensor $id $args[3]";
    $hash->{INTERVAL} = $interval;

  }

  RemoveInternalTimer($hash);
  if( $init_done ) {
    HUEDevice_GetUpdate($hash);
  } else {
    InternalTimer(gettimeofday()+10, "HUEDevice_GetUpdate", $hash, 0);
  }

  return undef;
}

sub HUEDevice_Undefine($$)
{
  my ($hash,$arg) = @_;

  RemoveInternalTimer($hash);

  my $code = $hash->{ID};
  $code = $hash->{IODev}->{NAME} ."-". $code if( defined($hash->{IODev}->{NAME}) );

  delete($modules{HUEDevice}{defptr}{$code});

  return undef;
}

sub
HUEDevice_SetParam($$@)
{
  my ($name, $obj, $cmd, $value, $value2) = @_;

  if( $cmd eq "color" ) {
    $value = int(1000000/$value);
    $cmd = 'ct';
  } elsif( $cmd eq "toggle" ) {
    $cmd = ReadingsVal($name,"state","on") eq "off" ? "on" :"off";
  } elsif( $cmd =~ m/^dim(\d+)/ ) {
    $value2 = $value;
    $value = $1;
    $value =   0 if( $value <   0 );
    $value = 100 if( $value > 100 );
    $cmd = 'pct';
  } elsif( !defined($value) && $cmd =~ m/^(\d+)/) {
    $value2 = $value;
    $value = $1;
    $value =   0 if( $value < 0 );
    $value = 254 if( $value > 254 );
    $cmd = 'bri';
  }

  $cmd = "off" if($cmd eq "pct" && $value == 0 );

  if($cmd eq 'on') {
    $obj->{'on'}  = JSON::true;
    $obj->{'bri'} = 254 if( ReadingsVal($name,"bri","0") eq 0 );
    $obj->{'transitiontime'} = $value * 10 if( defined($value) );

  } elsif($cmd eq 'off') {
    $obj->{'on'}  = JSON::false;
    $obj->{'transitiontime'} = $value * 10 if( defined($value) );

  } elsif($cmd eq "pct") {
    my $bri;
    if( $value > 50 ) {
      $bri = 2.57 * ($value-50) + 128;
    } else {
      $bri = 2.59 * ($value-50) + 128;
    }
    $bri = 0 if( $bri < 0 );
    $bri = 254 if( $bri > 254 );
    #$value = 3.5 if( $value < 3.5 && AttrVal($name, "model", "") eq "LWL001" );
    $obj->{'on'}  = JSON::true;
    #$obj->{'bri'}  = int(2.55 * $value);
    $obj->{'bri'}  = int($bri);
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );

  } elsif($cmd eq "bri") {
    #$value = 8 if( $value < 8 && AttrVal($name, "model", "") eq "LWL001" );
    $obj->{'on'}  = JSON::true;
    $obj->{'bri'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );

  } elsif($cmd eq "dimUp") {
    my $bri = ReadingsVal($name,"bri","0");
    $bri += 25;
    $bri = 254 if( $bri > 254 );
    $obj->{'on'}  = JSON::true;
    $obj->{'bri'}  = 0+$bri;
    $obj->{'transitiontime'} = 1;
    #$obj->{'transitiontime'} = $value * 10 if( defined($value) );
    $defs{$name}->{helper}->{update_timeout} = 0;

  } elsif($cmd eq "dimDown") {
    my $bri = ReadingsVal($name,"bri","0");
    $bri -= 25;
    $bri = 0 if( $bri < 0 );
    $obj->{'on'}  = JSON::true;
    $obj->{'bri'}  = 0+$bri;
    $obj->{'transitiontime'} = 1;
    #$obj->{'transitiontime'} = $value * 10 if( defined($value) );
    $defs{$name}->{helper}->{update_timeout} = 0;

  } elsif($cmd eq "ct") {
    $obj->{'on'}  = JSON::true;
    $value = int(1000000/$value) if( $value > 1000 );
    $obj->{'ct'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );
  } elsif($cmd eq "hue") {
    $obj->{'on'}  = JSON::true;
    $obj->{'hue'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );
  } elsif($cmd eq "sat") {
    $obj->{'on'}  = JSON::true;
    $obj->{'sat'}  = 0+$value;
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );
  } elsif($cmd eq "xy" && $value =~ m/^(.+),(.+)/) {
    my ($x,$y) = ($1, $2);
    $obj->{'on'}  = JSON::true;
    $obj->{'xy'}  = [0+$x, 0+$y];
    $obj->{'transitiontime'} = $value2 * 10 if( defined($value2) );
  } elsif( $cmd eq "rgb" && $value =~ m/^(..)(..)(..)/) {
    my( $r, $g, $b ) = (hex($1)/255.0, hex($2)/255.0, hex($3)/255.0);

    if( !defined( AttrVal($name, "model", undef) ) ) {
      my( $h, $s, $v ) = Color::rgb2hsv($r,$g,$b);

      $obj->{'on'}  = JSON::true;
      $obj->{'hue'} = int( $h * 65535 );
      $obj->{'sat'} = int( $s * 254 );
      $obj->{'bri'} = int( $v * 254 );
    } else {
      # calculation from http://www.everyhue.com/vanilla/discussion/94/rgb-to-xy-or-hue-sat-values/p1

      my $X =  1.076450 * $r - 0.237662 * $g + 0.161212 * $b;
      my $Y =  0.410964 * $r + 0.554342 * $g + 0.034694 * $b;
      my $Z = -0.010954 * $r - 0.013389 * $g + 1.024343 * $b;
      #Log3 $name, 3, "rgb: ". $r . " " . $g ." ". $b;
      #Log3 $name, 3, "XYZ: ". $X . " " . $Y ." ". $Y;

      if( $X != 0
          || $Y != 0
          || $Z != 0 ) {
        my $x = $X / ($X + $Y + $Z);
        my $y = $Y / ($X + $Y + $Z);
        #Log3 $name, 3, "xyY:". $x . " " . $y ." ". $Y;

        $Y = 1 if( $Y > 1 );

        my $bri  = maxNum($r,$g,$b);
        #my $bri  = $Y;

        $obj->{'on'}  = JSON::true;
        $obj->{'xy'}  = [0+$x, 0+$y];
        $obj->{'bri'}  = int(254*$bri);
      } else {
        $obj->{'on'}  = JSON::false;
      }
    }
  } elsif( $cmd eq "hsv" && $value =~ m/^(..)(..)(..)/) {
    my( $h, $s, $v ) = (hex($1), hex($2), hex($3));

    $s = 254 if( $s > 254 );
    $v = 254 if( $v > 254 );

    $obj->{'on'}  = JSON::true;
    $obj->{'hue'}  = int($h*256);
    $obj->{'sat'}  = 0+$s;
    $obj->{'bri'}  = 0+$v;
  } elsif( $cmd eq "alert" ) {
    $obj->{'alert'}  = $value;
  } elsif( $cmd eq "effect" ) {
    $obj->{'effect'}  = $value;
  } elsif( $cmd eq "transitiontime" ) {
    $obj->{'transitiontime'} = 0+$value;
  } elsif( $cmd eq "delayedUpdate" ) {
    $defs{$name}->{helper}->{update_timeout} = 1;
  } elsif( $cmd eq "immediateUpdate" ) {
    $defs{$name}->{helper}->{update_timeout} = 0;
  } elsif( $cmd eq "noUpdate" ) {
    $defs{$name}->{helper}->{update_timeout} = -1;
  } else {
    return 0;
  }

  return 1;
}
sub HUEDevice_Set($@);
sub
HUEDevice_Set($@)
{
  my ($hash, $name, @aa) = @_;

  my %obj;

  $hash->{helper}->{update_timeout} =  AttrVal($name, "delayedUpdate", 0);

  if( $hash->{helper}->{devtype} eq 'G' ) {
    if( $aa[0] eq 'lights' ) {
      my @lights = ();
      for my $param (@aa[1..@aa-1]) {
        $param = $defs{$param}{ID} if( defined $defs{$param} && $defs{$param}{TYPE} eq 'HUEDevice' );
        push( @lights, $param );
      }

      my $obj = { 'lights' => \@lights, };

      my $result = HUEDevice_ReadFromServer($hash,$hash->{ID},$obj);
      if( $result->{success} ) {
        RemoveInternalTimer($hash);
        HUEDevice_GetUpdate($hash);
      }

      return $result->{error}{description} if( $result->{error} );

    }
  } elsif( $hash->{helper}->{devtype} eq 'S' ) {

    if( $aa[0] eq "statusRequest" ) {
      RemoveInternalTimer($hash);
      HUEDevice_GetUpdate($hash);
      return undef;
    }

    return "Unknown argument $aa[0], choose one of statusRequest:noArg";
  }

  if( $aa[0] eq 'rename' ) {
    my $new_name =  join( ' ', @aa[1..@aa-1]);
    my $obj = { 'name' => $new_name, };

    my $result = HUEDevice_ReadFromServer($hash,$hash->{ID},$obj);
    if( $result->{success} ) {
      RemoveInternalTimer($hash);
      HUEDevice_GetUpdate($hash);
      CommandAttr(undef,"$name alias $new_name");
      CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );
    }

    return $result->{error}{description} if( $result->{error} );
    return undef;
  }

  if( (my $joined = join(" ", @aa)) =~ /:/ ) {
    my @cmds = split(":", $joined);
    for( my $i = 0; $i <= $#cmds; ++$i ) {
      HUEDevice_SetParam($name, \%obj, split(" ", $cmds[$i]) );
    }
  } else {
    my ($cmd, $value, $value2, @a) = @aa;

    if( $cmd eq "statusRequest" ) {
      RemoveInternalTimer($hash);
      HUEDevice_GetUpdate($hash);
      return undef;
    }

    HUEDevice_SetParam($name, \%obj, $cmd, $value, $value2);
  }

  if( !defined($obj{transitiontime} ) ) {
    my $transitiontime =  AttrVal($name, "transitiontime", undef);

    $obj{transitiontime} = 0 + $transitiontime if( defined( $transitiontime ) );
  }

#  if( $hash->{helper}->{update_timeout} == -1 ) {
#    my $diff;
#    my ($seconds, $microseconds) = gettimeofday();
#    if( $hash->{helper}->{timestamp} ) {
#      my ($seconds2, $microseconds2) = @{$hash->{helper}->{timestamp}};
#
#      $diff = (($seconds-$seconds2)*1000000 + $microseconds-$microseconds2)/1000;
#    }
#    $hash->{helper}->{timestamp} = [$seconds, $microseconds];
#
#    return undef if( $diff < 100 );
#  }

  if( scalar keys %obj ) {
    my $result;
    if( $hash->{helper}->{devtype} eq 'G' ) {
      $hash->{helper}->{update} = 1;
      $result = HUEDevice_ReadFromServer($hash,$hash->{ID}."/action",\%obj);
    } else {
      $result = HUEDevice_ReadFromServer($hash,$hash->{ID}."/state",\%obj);
    }

    if( defined($result) && $result->{'error'} ) {
      $hash->{STATE} = $result->{'error'}->{'description'};
      return undef;
    }

    return undef if( !defined($result) );

    if( $hash->{helper}->{update_timeout} == -1 ) {
    } elsif( $hash->{helper}->{update_timeout} ) {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+$hash->{helper}->{update_timeout}, "HUEDevice_GetUpdate", $hash, 0);
    } else {
      RemoveInternalTimer($hash);
      HUEDevice_GetUpdate( $hash );
    }

    return undef;
  }

  my $subtype = AttrVal($name, "subType", "extcolordimmer");

  my $list = "off:noArg on:noArg toggle:noArg statusRequest:noArg";
  $list .= " pct:slider,0,1,100 bri:slider,0,1,254" if( $subtype =~ m/dimmer/ );
  $list .= " dimUp:noArg dimDown:noArg" if( !$hash->{helper}->{devtype} && $subtype =~ m/dimmer/ );
  $list .= " rgb:colorpicker,RGB" if( $subtype =~ m/color/ );
  $list .= " color:colorpicker,CT,2000,1,6500 ct:colorpicker,CT,154,1,500" if( $subtype =~ m/ct|ext/ );
  $list .= " hue:colorpicker,HUE,0,1,65535 sat:slider,0,1,254 xy effect:none,colorloop" if( $subtype =~ m/color/ );
  $list .= " alert:none,select,lselect";

  #$list .= " dim06% dim12% dim18% dim25% dim31% dim37% dim43% dim50% dim56% dim62% dim68% dim75% dim81% dim87% dim93% dim100%" if( $subtype =~ m/dimmer/ );

  $list .= " lights" if( $hash->{helper}->{devtype} eq 'G' );
  $list .= " rename";

  return SetExtensions($hash, $list, $name, @aa);
}

sub
cttorgb($)
{
  my ($ct) = @_;

  # calculation from http://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code
  # adjusted by 1000K
  my $temp = (1000000/$ct)/100 + 10;

  my $r = 0;
  my $g = 0;
  my $b = 0;

  $r = 255;
  $r = 329.698727446 * ($temp - 60) ** -0.1332047592 if( $temp > 66 );
  $r = 0 if( $r < 0 );
  $r = 255 if( $r > 255 );

  if( $temp <= 66 ) {
    $g = 99.4708025861 * log($temp) - 161.1195681661;
  } else {
    $g = 288.1221695283 * ($temp - 60) ** -0.0755148492;
  }
  $g = 0 if( $g < 0 );
  $g = 255 if( $g > 255 );

  $b = 255;
  $b = 0 if( $temp <= 19 );
  if( $temp < 66 ) {
    $b = 138.5177312231 * log($temp-10) - 305.0447927307;
  }
  $b = 0 if( $b < 0 );
  $b = 255 if( $b > 255 );

  return( $r, $g, $b );
}

sub
xyYtorgb($$$)
{
  # calculation from http://www.brucelindbloom.com/index.html
  my ($x,$y,$Y) = @_;
#Log 3, "xyY:". $x . " " . $y ." ". $Y;

  my $r = 0;
  my $g = 0;
  my $b = 0;

  if( $y > 0 ) {
    my $X = $x * $Y / $y;
    my $Z = (1 - $x - $y)*$Y / $y;

    if( $X > 1
        || $Y > 1
        || $Z > 1 ) {
      my $f = maxNum($X,$Y,$Z);
      $X /= $f;
      $Y /= $f;
      $Z /= $f;
    }
#Log 3, "XYZ: ". $X . " " . $Y ." ". $Y;

    $r =  0.7982 * $X + 0.3389 * $Y - 0.1371 * $Z;
    $g = -0.5918 * $X + 1.5512 * $Y + 0.0406 * $Z;
    $b =  0.0008 * $X + 0.0239 * $Y + 0.9753 * $Z;

    if( $r > 1
        || $g > 1
        || $b > 1 ) {
      my $f = maxNum($r,$g,$b);
      $r /= $f;
      $g /= $f;
      $b /= $f;
    }
#Log 3, "rgb: ". $r . " " . $g ." ". $b;

    $r *= 255;
    $g *= 255;
    $b *= 255;
  }

  return( $r, $g, $b );
}

sub
HUEDevice_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];
  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];

  if($cmd eq "rgb") {
    my $r = 0;
    my $g = 0;
    my $b = 0;

    my $cm = ReadingsVal($name,"colormode","");
    if( $cm eq "ct" ) {
      if( ReadingsVal($name,"ct","") =~ m/(\d+) .*/ ) {
        ($r,$g,$b) = cttorgb($1);
      }
    } elsif( $cm eq "hs" ) {
      my $h = ReadingsVal($name,"hue",0) / 65535.0;
      my $s = ReadingsVal($name,"sat",0) / 254.0;
      my $v = ReadingsVal($name,"bri",0) / 254.0;
      ($r,$g,$b) = Color::hsv2rgb($h,$s,$v);

      $r *= 255;
      $g *= 255;
      $b *= 255;
    } elsif( ReadingsVal($name,"xy","") =~ m/(.+),(.+)/ ) {
      my ($x,$y) = ($1, $2);
      my $Y = ReadingsVal($name,"bri","") / 254.0;

      ($r,$g,$b) = xyYtorgb($x,$y,$Y);
    }
    return sprintf( "%02x%02x%02x", $r+0.5, $g+0.5, $b+0.5 );
  } elsif($cmd eq "RGB") {
    my $r = 0;
    my $g = 0;
    my $b = 0;

    my $cm = ReadingsVal($name,"colormode","");
    if( $cm eq "ct" ) {
      if( ReadingsVal($name,"ct","") =~ m/(\d+) .*/ ) {
        ($r,$g,$b) = cttorgb($1);
      }
    } elsif( $cm eq "hs" ) {
      my $h = ReadingsVal($name,"hue",0) / 65535.0;
      my $s = ReadingsVal($name,"sat",0) / 254.0;
      my $v = 1;
      ($r,$g,$b) = Color::hsv2rgb($h,$s,$v);

      $r *= 255;
      $g *= 255;
      $b *= 255;
    } elsif( ReadingsVal($name,"xy","") =~ m/(.+),(.+)/ ) {
      my ($x,$y) = ($1, $2);
      my $Y = 1;

      ($r,$g,$b) = xyYtorgb($x,$y,$Y);
    }
    return sprintf( "%02x%02x%02x", $r+0.5, $g+0.5, $b+0.5 );
  } elsif ( $cmd eq "devStateIcon" ) {
    return HUEDevice_devStateIcon($hash);
  }

  return "Unknown argument $cmd, choose one of rgb:noArg RGB:noArg devStateIcon:noArg";
}


###################################
# This could be IORead in fhem, But there is none.
# Read http://forum.fhem.de/index.php?t=tree&goto=54027&rid=10#msg_54027
# to find out why.
sub
HUEDevice_ReadFromServer($@)
{
  my ($hash,@a) = @_;

  my $name = $hash->{NAME};
  no strict "refs";
  my $ret;
  unshift(@a,$name);
  #$ret = IOWrite($hash, @a);
  $ret = IOWrite($hash,$hash,@a);
  use strict "refs";
  return $ret;
  return if(IsDummy($name) || IsIgnored($name));
  my $iohash = $hash->{IODev};
  if(!$iohash ||
     !$iohash->{TYPE} ||
     !$modules{$iohash->{TYPE}} ||
     !$modules{$iohash->{TYPE}}{ReadFn}) {
    Log3 $name, 5, "No I/O device or ReadFn found for $name";
    return;
  }

  no strict "refs";
  #my $ret;
  unshift(@a,$name);
  $ret = &{$modules{$iohash->{TYPE}}{ReadFn}}($iohash, @a);
  use strict "refs";
  return $ret;
}

sub
HUEDevice_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( $hash->{helper}->{devtype} eq 'G' ) {
    my $result = HUEDevice_ReadFromServer($hash,$hash->{ID});

    if( !defined($result) ) {
      $hash->{STATE} = "unknown";
      return;
    } elsif( $result->{'error'} ) {
      $hash->{STATE} = $result->{'error'}->{'description'};
      return;
    }

    HUEDevice_Parse($hash,$result);

    return undef;
  } elsif( $hash->{helper}->{devtype} eq 'S' ) {
  }

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "HUEDevice_GetUpdate", $hash, 0) if( $hash->{INTERVAL} );
  }

  my $result = HUEDevice_ReadFromServer($hash,$hash->{ID});
  if( !defined($result) ) {
    $hash->{helper}{reachable} = 0;
    $hash->{STATE} = "unknown";
    return;
  } elsif( $result->{'error'} ) {
    $hash->{helper}{reachable} = 0;
    $hash->{STATE} = $result->{'error'}->{'description'};
    return;
  }

  HUEDevice_Parse($hash,$result);
}

sub
HUEDevice_Parse($$)
{
  my($hash,$result) = @_;
  my $name = $hash->{NAME};

  if( ref($result) ne "HASH" ) {
    Log3 $name, 2, "$name: got wrong status message for $name: $result";
    return undef;
  }

  Log3 $name, 4, "parse status message for $name";
  #Log3 $name, 5, Dumper $result;

  $hash->{name} = $result->{'name'};
  $hash->{type} = $result->{'type'};

  if( $hash->{helper}->{devtype} eq 'G' ) {
    $hash->{lights} = join( ",", @{$result->{lights}} ) if( $result->{lights} );

    foreach my $id ( @{$result->{lights}} ) {
      my $code = $hash->{IODev}->{NAME} ."-". $id;
      my $chash = $modules{HUEDevice}{defptr}{$code};

      HUEDevice_GetUpdate($chash) if( defined($chash) && defined($hash->{helper}->{update}) );
    }

    delete $hash->{helper}->{update};

    return undef;

  }

  $hash->{modelid} = $result->{modelid};
  $hash->{uniqueid} = $result->{uniqueid};
  $hash->{manufacturername} = $result->{manufacturername};
  $hash->{swversion} = $result->{swversion};

  if( $hash->{helper}->{devtype} eq 'S' ) {

    if( $result->{state} ) {
      substr( $result->{state}{lastupdated}, 10, 1, ' ' );
      if( $result->{state}{lastupdated} ne 'none' ) {
        if( $result->{state}{buttonevent}
            && ReadingsTimestamp($name,"state","") ne $result->{state}{lastupdated} ) {
          readingsBeginUpdate($hash);
          $hash->{".updateTimestamp"} = $result->{state}{lastupdated};
          $hash->{CHANGETIME}[0] = $result->{state}{lastupdated};
          readingsBulkUpdate($hash, "state", $result->{state}{buttonevent}, 1);
          readingsEndUpdate($hash,1);
          delete $hash->{CHANGETIME};
        }
      }
    }

    return undef;

  }


  $attr{$name}{model} = $result->{modelid} if( !defined($attr{$name}{model}) && $result->{modelid} );

  if( !defined($attr{$name}{subType}) ) {
    if( defined($attr{$name}{model}) ) {
      if( defined($hueModels{$attr{$name}{model}}{subType}) ) {
        $attr{$name}{subType} = $hueModels{$attr{$name}{model}}{subType};

      } elsif( $attr{$name}{model} =~ m/TW$/ ) {
        $attr{$name}{subType} = 'ctdimmer';

      } elsif( $attr{$name}{model} =~ m/RGB$/ ) {
        $attr{$name}{subType} = 'colordimmer';

      } elsif( $attr{$name}{model} =~ m/RGBW$/ ) {
        $attr{$name}{subType} = 'extcolordimmer';

      }

    } elsif( $hash->{type} ) {
      if( $hash->{type} eq "Extended color light" ) {
        $attr{$name}{subType} = 'extcolordimmer';

      } elsif( $hash->{type} eq "Color light" ) {
        $attr{$name}{subType} = 'colordimmer';

      } elsif( $hash->{type} eq "Color Temperature Light" ) {
        $attr{$name}{subType} = 'ctdimmer';

      } elsif( $hash->{type} eq "Dimmable light" ) {
        $attr{$name}{subType} = 'dimmer';

      } elsif( $hash->{type} eq "Dimmable plug-in unit" ) {
        $attr{$name}{subType} = 'dimmer';

      }

    }

  } elsif( $attr{$name}{subType} eq "colordimmer" && defined($attr{$name}{model}) ) {
    $attr{$name}{subType} = $hueModels{$attr{$name}{model}}{subType} if( defined($hueModels{$attr{$name}{model}}{subType}) );
  }


  $attr{$name}{devStateIcon} = '{(HUEDevice_devStateIcon($name),"toggle")}' if( !defined( $attr{$name}{devStateIcon} ) );

  if( !defined($attr{$name}{webCmd}) && defined($attr{$name}{subType}) ) {
    my $subtype = $attr{$name}{subType};

    if( !$hash->{helper}->{devtype} ) {
      $attr{$name}{webCmd} = 'rgb:rgb ff0000:rgb DEFF26:rgb 0000ff:ct 490:ct 380:ct 270:ct 160:toggle:on:off' if( $subtype eq "extcolordimmer" );
      $attr{$name}{webCmd} = 'hue:rgb:rgb ff0000:rgb 98FF23:rgb 0000ff:toggle:on:off' if( $subtype eq "colordimmer" );
      $attr{$name}{webCmd} = 'ct:ct 490:ct 380:ct 270:ct 160:toggle:on:off' if( $subtype eq "ctdimmer" );
      $attr{$name}{webCmd} = 'pct:toggle:on:off' if( $subtype eq "dimmer" );
      $attr{$name}{webCmd} = 'toggle:on:off' if( $subtype eq "switch" );
    } elsif( $hash->{helper}->{devtype} eq 'G' ) {
      $attr{$name}{webCmd} = 'on:off';
    }
  }

  readingsBeginUpdate($hash);

  my $state = $result->{'state'};

  my $on        = $state->{on};
  my $reachable = $state->{reachable}?1:0;
  my $colormode = $state->{'colormode'};
  my $bri       = $state->{'bri'};
  my $ct        = $state->{'ct'};
  my $hue       = $state->{'hue'};
  my $sat       = $state->{'sat'};
  my $xy        = undef;
     $xy        = $state->{'xy'}->[0] .",". $state->{'xy'}->[1] if( defined($state->{'xy'}) );
  my $alert = $state->{alert};
  my $effect = $state->{effect};

  if( defined($colormode) && $colormode ne $hash->{helper}{colormode} ) {readingsBulkUpdate($hash,"colormode",$colormode);}
  if( defined($bri) && $bri != $hash->{helper}{bri} ) {readingsBulkUpdate($hash,"bri",$bri);}
  if( defined($ct) && $ct != $hash->{helper}{ct} ) {
    if( $ct == 0 ) {
      readingsBulkUpdate($hash,"ct",$ct);
    }
    else {
      readingsBulkUpdate($hash,"ct",$ct . " (".int(1000000/$ct)."K)");
    }
  }
  if( defined($hue) && $hue != $hash->{helper}{hue} ) {readingsBulkUpdate($hash,"hue",$hue);}
  if( defined($sat) && $sat != $hash->{helper}{sat} ) {readingsBulkUpdate($hash,"sat",$sat);}
  if( defined($xy) && $xy ne $hash->{helper}{xy} ) {readingsBulkUpdate($hash,"xy",$xy);}
  if( !defined($hash->{helper}{reachable}) || $reachable != $hash->{helper}{reachable} ) {readingsBulkUpdate($hash,"reachable",$reachable);}
  if( defined($alert) && $alert ne $hash->{helper}{alert} ) {readingsBulkUpdate($hash,"alert",$alert);}
  if( defined($effect) && $effect ne $hash->{helper}{effect} ) {readingsBulkUpdate($hash,"effect",$effect);}

  my $s = '';
  my $percent;
  if( $on )
    {
      $s = 'on';
      if( $on != $hash->{helper}{on} ) {readingsBulkUpdate($hash,"onoff",1);}

      $percent = int($bri * 99 / 254 + 1);
      if( $percent > 0
          && $percent < 100  ) {
        $s = $dim_values{int($percent/7)};
      }
      $s = 'off' if( $percent == 0 );
    }
  else
    {
      $on = 0;
      $s = 'off';
      $percent = 0;
      if( $on != $hash->{helper}{on} ) {readingsBulkUpdate($hash,"onoff",0);}
    }

  if( $percent != $hash->{helper}{percent} ) {readingsBulkUpdate($hash,"pct", $percent);}
  #if( $percent != $hash->{helper}{percent} ) {readingsBulkUpdate($hash,"level", $percent . ' %');}

  $s = 'unreachable' if( !$reachable );

  $hash->{helper}{on} = $on;
  $hash->{helper}{reachable} = $reachable;
  $hash->{helper}{colormode} = $colormode;
  $hash->{helper}{bri} = $bri;
  $hash->{helper}{ct} = $ct;
  $hash->{helper}{hue} = $hue;
  $hash->{helper}{sat} = $sat;
  $hash->{helper}{xy} = $xy;
  $hash->{helper}{alert} = $alert;
  $hash->{helper}{effect} = $effect;

  $hash->{helper}{percent} = $percent;

  if( $s ne $hash->{STATE} ) {readingsBulkUpdate($hash,"state",$s);}

  readingsEndUpdate($hash,1);

  readingsSingleUpdate($hash,"rgb", CommandGet("","$name rgb"),1 );
}

1;

=pod
=begin html

<a name="HUEDevice"></a>
<h3>HUEDevice</h3>
<ul>
  <br>
  <a name="HUEDevice_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HUEDevice [group|sensor] &lt;id&gt; [&lt;interval&gt;]</code><br>
    <br>

    Defines a device connected to a <a href="#HUEBridge">HUEBridge</a>.<br><br>

    This can be a hue bulb, a living colors light or a living whites bulb or dimmer plug.<br><br>

    The device status will be updated every &lt;interval&gt; seconds. 0 means no updates.
    The default and minimum is 60 if the IODev has not set pollDevices to 1.
    The default ist 0 if the IODev has set pollDevices to 1.
    Groups are updated only on definition and statusRequest<br><br>

    Examples:
    <ul>
      <code>define bulb HUEDevice 1</code><br>
      <code>define LC HUEDevice 2</code><br>
      <code>define allLights HUEDevice group 0</code><br>
    </ul>
  </ul><br>

  <a name="HUEDevice_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>bri<br>
    the brightness reported from the device. the value can be betwen 1 and 254</li>
    <li>colormode<br>
    the current colormode</li>
    <li>ct<br>
    the colortemperature in mireds and kelvin</li>
    <li>hue<br>
    the current hue</li>
    <li>level<br>
    the current brightness in percent</li>
    <li>onoff<br>
    the current on/off state as 0 or 1</li>
    <li>sat<br>
    the current saturation</li>
    <li>xy<br>
    the current xy color coordinates</li>
    <li>state<br>
    the current state</li>
    <br>
    Notes:
      <ul>
      <li>groups have no readings.</li>
      <li>not all readings show the actual device state. all readings not related to the current colormode have to be ignored.</li>
      <li>the actual state of a device controlled by a living colors or living whites remote can be different and will
          be updated after some time.</li>
      </ul><br>
  </ul><br>

  <a name="HUEDevice_Set"></a>
    <b>Set</b>
    <ul>
      <li>on [&lt;ramp-time&gt;]</li>
      <li>off [&lt;ramp-time&gt;]</li>
      <li>toggle [&lt;ramp-time&gt;]</li>
      <li>statusRequest<br>
        Request device status update.</li>
      <li>pct &lt;value&gt; [&lt;ramp-time&gt;]<br>
        dim to &lt;value&gt;<br>
        Note: the FS20 compatible dimXX% commands are also accepted.</li>
      <li>color &lt;value&gt;<br>
        set colortemperature to &lt;value&gt; kelvin.</li>
      <li>bri &lt;value&gt; [&lt;ramp-time&gt;]<br>
        set brighness to &lt;value&gt;; range is 0-254.</li>
      <li>dimUp</li>
      <li>dimDown</li>
      <li>ct &lt;value&gt; [&lt;ramp-time&gt;]<br>
        set colortemperature to &lt;value&gt; in mireds (range is 154-500) or kelvin (rankge is 2000-6493).</li>
      <li>hue &lt;value&gt; [&lt;ramp-time&gt;]<br>
        set hue to &lt;value&gt;; range is 0-65535.</li>
      <li>sat &lt;value&gt; [&lt;ramp-time&gt;]<br>
        set saturation to &lt;value&gt;; range is 0-254.</li>
      <li>xy &lt;x&gt;,&lt;y&gt; [&lt;ramp-time&gt;]<br>
        set the xy color coordinates to &lt;x&gt;,&lt;y&gt;</li>
      <li>alert [none|select|lselect]</li>
      <li>effect [none|colorloop]</li>
      <li>transitiontime &lt;time&gt;<br>
        set the transitiontime to &lt;time&gt; 1/10s</li>
      <li>rgb &lt;rrggbb&gt;<br>
        set the color to (the nearest equivalent of) &lt;rrggbb&gt;</li>
      <br>
      <li>delayedUpdate</li>
      <li>immediateUpdate</li>
      <br>
      <li>lights &lt;light-1&gt[ &lt;light-2&gt;..&lt;light-n&gt;]<br>
      Only valid for groups. Changes the list of lights in this group.
      The lights can be given as fhem device names or bridge device numbers.</li>
      <li>rename &lt;new name&gt;<br>
      Renames the device in the bridge and changes the fhem alias.</li>
      <br>
      <li><a href="#setExtensions"> set extensions</a> are supported.</li>
      <br>
      Note:
        <ul>
        <li>&lt;ramp-time&gt; is given in seconds</li>
        <li>multiple paramters can be set at once separated by <code>:</code><br>
          Examples:<br>
            <code>set LC on : transitiontime 100</code><br>
            <code>set bulb on : bri 100 : color 4000</code><br></li>
        </ul>
    </ul><br>

  <a name="HUEDevice_Get"></a>
    <b>Get</b>
    <ul>
      <li>rgb</li>
      <li>RGB</li>
      <li>devStateIcon<br>
      returns html code that can be used to create an icon that represents the device color in the room overview.</li>
    </ul><br>

  <a name="HUEDevice_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>color-icon<br>
      1 -> use lamp color as icon color and 100% shape as icon shape<br>
      2 -> use lamp color scaled to full brightness as icon color and dim state as icon shape</li>
    <li>subType<br>
      extcolordimmer -> device has rgb and color temperatur control<br>
      colordimmer -> device has rgb controll<br>
      ctdimmer -> device has color temperature control<br>
      dimmer -> device has brightnes controll<br>
      switch -> device has on/off controll<br></li>
    <li>transitiontime<br>
      default transitiontime for all set commands if not specified directly in the set.</li>
    <li>delayedUpdate<br>
      1 -> the update of the device status after a set command will be delayed for 1 second. usefull if multiple devices will be switched.
</li>
    <li>devStateIcon<br>
      will be initialized to <code>{(HUEDevice_devStateIcon($name),"toggle")}</code> to show device color as default in room overview.</li>
    <li>webCmd<br>
      will be initialized to a device specific value according to subType.</li>
  </ul>

</ul><br>

=end html
=cut
