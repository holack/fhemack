
# $Id: 38_netatmo.pm 7953 2015-02-13 11:16:51Z justme1968 $

package main;

use strict;
use warnings;

use Encode qw(encode_utf8);
use JSON;

use HttpUtils;

my $netatmo_isFritzBox = undef;
sub
netatmo_isFritzBox()
{
  $netatmo_isFritzBox = int( qx( [ -f /usr/bin/ctlmgr_ctl ] && echo 1 || echo 0 ) )  if( !defined( $netatmo_isFritzBox) );

  return $netatmo_isFritzBox;
}

sub
netatmo_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "netatmo_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "netatmo_Notify";
  $hash->{UndefFn}  = "netatmo_Undefine";
  $hash->{SetFn}    = "netatmo_Set";
  $hash->{GetFn}    = "netatmo_Get";
  $hash->{AttrFn}   = "netatmo_Attr";
  $hash->{AttrList} = "IODev ".
                      "disable:1 ".
                      "interval ".
                      "nossl:1 ";
  $hash->{AttrList} .= $readingFnAttributes;
}

#####################################

sub
netatmo_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  my $name = $a[0];

  my $subtype;
  if( @a == 3 ) {
    $subtype = "DEVICE";

    my $device = $a[2];

    $hash->{Device} = $device;

    $hash->{INTERVAL} = 60*5 if( !$hash->{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"D$device"};
    return "device $device already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"D$device"} = $hash;

  } elsif( ($a[2] eq "PUBLIC" && @a > 3 ) ) {
    my $device = $a[3];
    $hash->{Device} = $device;

    if( $a[4] && $a[4] =~ m/[\da-f]{2}(:[\da-f]{2}){5}/ ) {
      $subtype = "MODULE";

      my $module = "";
      my $readings = "";

      my @a = splice( @a, 4 );
      while( @a ) {
        $module .= " " if( $module );
        $module .= shift( @a );

        $readings .= " " if( $readings );
        $readings .=  shift( @a );
      }

      $hash->{Module} = $module;
      $hash->{dataTypes} = $readings;

      my $d = $modules{$hash->{TYPE}}{defptr}{"M$module"};
      return "module $module already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

      $modules{$hash->{TYPE}}{defptr}{"M$module"} = $hash;

      my $state_format;
      if( $readings =~ m/temperature/ ) {
        $state_format .= " " if( $state_format );
        $state_format .= "T: temperature";
      }
      if( $readings =~ m/humidity/ ) {
        $state_format .= " " if( $state_format );
        $state_format .= "H: humidity";
      }
      $attr{$name}{stateFormat} = $state_format if( !defined($attr{$name}{stateFormat}) && defined($state_format) );

    } else {
      my $lon = $a[4];
      my $lat = $a[5];
      my $rad = $a[6];
      $rad = 0.02 if( !$rad );

      $hash->{Lat} = $lat;
      $hash->{Lon} = $lon;
      $hash->{Rad} = $rad;

      delete( $hash->{LAST_POLL} );

      $subtype = "DEVICE";

      my $d = $modules{$hash->{TYPE}}{defptr}{"D$device"};
      return "device $device already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

      $modules{$hash->{TYPE}}{defptr}{"D$device"} = $hash;
    }

    $hash->{INTERVAL} = 60*15 if( !$hash->{INTERVAL} );

  } elsif( ($a[2] eq "MODULE" && @a == 5 ) ) {
    $subtype = "MODULE";

    my $device = $a[@a-2];
    my $module = $a[@a-1];

    $hash->{Device} = $device;
    $hash->{Module} = $module;

    $hash->{INTERVAL} = 60*5 if( !$hash->{INTERVAL} );

    my $d = $modules{$hash->{TYPE}}{defptr}{"M$module"};
    return "module $module already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"M$module"} = $hash;

  } elsif( @a == 6  || ($a[2] eq "ACCOUNT" && @a == 7 ) ) {
    $subtype = "ACCOUNT";

    my $username = $a[@a-4];
    my $password = $a[@a-3];
    my $client_id = $a[@a-2];
    my $client_secret = $a[@a-1];

    $hash->{Clients} = ":netatmo:";

    $hash->{username} = $username;
    $hash->{password} = $password;
    $hash->{client_id} = $client_id;
    $hash->{client_secret} = $client_secret;

    $attr{$name}{nossl} = 1 if( !$init_done && netatmo_isFritzBox() );

  } else {
    return "Usage: define <name> netatmo device\
       define <name> netatmo userid publickey\
       define <name> netatmo PUBLIC device latitude longitude [radius]\
       define <name> netatmo [ACCOUNT] username password"  if(@a < 3 || @a > 5);
  }

  $hash->{NAME} = $name;
  $hash->{SUBTYPE} = $subtype;

  $hash->{STATE} = "Initialized";

  if( $init_done ) {
    netatmo_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
    netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
    netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "MODULE" );
  }

  return undef;
}

sub
netatmo_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  netatmo_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
  netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
  netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "MODULE" );

  return undef;
}

sub
netatmo_Undefine($$)
{
  my ($hash, $arg) = @_;

  delete( $modules{$hash->{TYPE}}{defptr}{"D$hash->{Device}"} ) if( $hash->{SUBTYPE} eq "DEVICE" );
  delete( $modules{$hash->{TYPE}}{defptr}{"M$hash->{Module}"} ) if( $hash->{SUBTYPE} eq "MODULE" );

  return undef;
}

sub
netatmo_Set($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "autocreate:noArg";

  if( $cmd eq "autocreate" ) {
    return netatmo_autocreate($hash, 1 );
    return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
netatmo_getToken($)
{
  my ($hash) = @_;

  $hash->{https} = "https";
  $hash->{https} = "http" if( AttrVal($hash->{NAME}, "nossl", 0) );

  my($err,$data) = HttpUtils_BlockingGet({
    url => "$hash->{https}://api.netatmo.net/oauth2/token",
    timeout => 10,
    noshutdown => 1,
    data => {grant_type => 'password', client_id => $hash->{client_id},  client_secret=> $hash->{client_secret}, username => $hash->{username}, password => $hash->{password}},
  });

  netatmo_dispatch( {hash=>$hash,type=>'token'},$err,$data );
}

sub
netatmo_refreshToken($;$)
{
  my ($hash,$nonblocking) = @_;

  if( !$hash->{access_token} ) {
    netatmo_getToken($hash);
    return undef;
  } elsif( !$nonblocking && defined($hash->{expires_at}) ) {
    my ($seconds) = gettimeofday();
    return undef if( $seconds < $hash->{expires_at} - 300 );
  }

  if( $nonblocking ) {
    HttpUtils_NonblockingGet({
      url => "$hash->{https}://api.netatmo.net/oauth2/token",
      timeout => 10,
      noshutdown => 1,
      data => {grant_type => 'refresh_token', client_id => $hash->{client_id},  client_secret=> $hash->{client_secret}, refresh_token => $hash->{refresh_token}},
        hash => $hash,
        type => 'token',
        callback => \&netatmo_dispatch,
    });
  } else {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "$hash->{https}://api.netatmo.net/oauth2/token",
      timeout => 10,
      noshutdown => 1,
      data => {grant_type => 'refresh_token', client_id => $hash->{client_id},  client_secret=> $hash->{client_secret}, refresh_token => $hash->{refresh_token}},
    });

    netatmo_dispatch( {hash=>$hash,type=>'token'},$err,$data );
  }
}
sub
netatmo_refreshTokenTimer($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: refreshing token";

  netatmo_refreshToken($hash, 1);
}

sub
netatmo_connect($)
{
  my ($hash) = @_;

  netatmo_getToken($hash);
}
sub
netatmo_initDevice($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  my $device;
  if( $hash->{Module} ) {
    $device = netatmo_getDeviceDetail( $hash, $hash->{Module} );
  } else {
    $device = netatmo_getDeviceDetail( $hash, $hash->{Device} );
  }

  $hash->{stationName} = $device->{station_name} if( $device->{station_name} );

  $hash->{model} = $device->{type};
  $hash->{firmware} = $device->{firmware};
  if( $device->{place} ) {
    $hash->{country} = $device->{place}{country};
    $hash->{bssid} = $device->{place}{bssid};
    $hash->{altitude} = $device->{place}{altitude};
    $hash->{city} = $device->{place}{geoip_city};
    $hash->{location} = $device->{place}{location}[0] .",". $device->{place}{location}[1];
  }

  my $state_format;
  if( $device->{data_type} ) {
    delete($hash->{dataTypes});

    my @reading_names = ();
    foreach my $type (@{$device->{data_type}}) {
      $hash->{dataTypes} = "" if ( !defined($hash->{dataTypes}) );
      $hash->{dataTypes} .= "," if ( $hash->{dataTypes} );
      $hash->{dataTypes} .= $type;

      push @reading_names, lc($type);

      if( $type eq "Temperature" ) {
        $state_format .= " " if( $state_format );
        $state_format .= "T: temperature";
      } elsif( $type eq "Humidity" ) {
        $state_format .= " " if( $state_format );
        $state_format .= "H: humidity";
      }
    }

    $hash->{helper}{readingNames} = \@reading_names;
  }

  $attr{$name}{stateFormat} = $state_format if( !defined($attr{$name}{stateFormat}) && defined($state_format) );

  netatmo_poll($hash);
}

sub
netatmo_getDevices($;$)
{
  my ($hash,$blocking) = @_;

  netatmo_refreshToken($hash);

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "$hash->{https}://api.netatmo.net/api/devicelist",
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, scope => 'read_station' },
    });

    netatmo_dispatch( {hash=>$hash,type=>'devicelist'},$err,$data );

    return $hash->{helper}{devices};
  } else {
    HttpUtils_NonblockingGet({
      url => "$hash->{https}://api.netatmo.net/api/devicelist",
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, scope => 'read_station', },
      hash => $hash,
      type => 'devicelist',
      callback => \&netatmo_dispatch,
    });
  }
}
sub
netatmo_getPublicDevices($$;$$$$)
{
  my ($hash,$blocking,$lon_ne,$lat_ne,$lon_sw,$lat_sw) = @_;
  my $name = $hash->{NAME};

  my $iohash = $hash->{IODev};
  $iohash = $hash if( !defined($iohash) );

  if( !defined($lat_ne) ) {
    my $s = $lon_ne;
    $s = 0.025 if ( !defined($s) );
    my $lat = AttrVal("global","latitude", 50.112);
    my $lon = AttrVal("global","longitude", 8.686);

    $lon_ne = $lon + $s;
    $lat_ne = $lat + $s;
    $lon_sw = $lon - $s;
    $lat_sw = $lat - $s;
  } elsif( !defined($lat_sw) ) {
    my $lat = $lat_ne;
    my $lon = $lon_ne;
    my $s = $lon_sw;
    $s = 0.025 if ( !defined($s) );

    $lon_ne = $lon + $s;
    $lat_ne = $lat + $s;
    $lon_sw = $lon - $s;
    $lat_sw = $lat - $s;
  }
  Log3 $name, 4, "$name getpublicdata: $lon_ne, $lon_sw, $lat_ne, $lat_sw";

  netatmo_refreshToken($iohash);

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "$iohash->{https}://api.netatmo.net/api/getpublicdata",
      noshutdown => 1,
      data => { access_token => $iohash->{access_token}, lat_ne => $lat_ne, lon_ne => $lon_ne, lat_sw => $lat_sw, lon_sw => $lon_sw },
    });

      return netatmo_dispatch( {hash=>$hash,type=>'publicdata'},$err,$data );
  } else {
    HttpUtils_NonblockingGet({
      url => "$iohash->{https}://api.netatmo.net/api/getpublicdata",
      noshutdown => 1,
      data => { access_token => $iohash->{access_token}, lat_ne => $lat_ne, lon_ne => $lon_ne, lat_sw => $lat_sw, lon_sw => $lon_sw },
      hash => $hash,
      type => 'publicdata',
      callback => \&netatmo_dispatch,
    });
  }
}

sub
netatmo_getAddress($$$$)
{
  my ($hash,$blocking,$lon,$lat) = @_;
  my $name = $hash->{NAME};

  my $iohash = $hash->{IODev};
  $iohash = $hash if( !defined($iohash) );

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "$iohash->{https}://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lon",
      noshutdown => 1,
    });

      return netatmo_dispatch( {hash=>$hash,type=>'address'},$err,$data );
  } else {
    HttpUtils_NonblockingGet({
      url => "$iohash->{https}://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lon",
      noshutdown => 1,
      hash => $hash,
      type => 'address',
      callback => \&netatmo_dispatch,
    });
  }
}
sub
netatmo_getLatLong($$$)
{
  my ($hash,$blocking,$addr) = @_;
  my $name = $hash->{NAME};

  my $iohash = $hash->{IODev};
  $iohash = $hash if( !defined($iohash) );

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => "$iohash->{https}://maps.googleapis.com/maps/api/geocode/json?address=germany+$addr",
      noshutdown => 1,
    });

      return netatmo_dispatch( {hash=>$hash,type=>'latlng'},$err,$data );
  } else {
    HttpUtils_NonblockingGet({
      url => "$iohash->{https}://maps.googleapis.com/maps/api/geocode/json?address=germany+$addr",
      noshutdown => 1,
      hash => $hash,
      type => 'latlng',
      callback => \&netatmo_dispatch,
    });
  }
}

sub
netatmo_getDeviceDetail($$)
{
  my ($hash,$id) = @_;

  $hash = $hash->{IODev} if( defined($hash->{IODev}) );

  netatmo_getDevices($hash,1) if( !$hash->{helper}{devices} );

  foreach my $device (@{$hash->{helper}{devices}}) {
    return $device if( $device->{_id} eq $id );
  }

  return undef;
}
sub
netatmo_requestDeviceReadings($@)
{
  my ($hash,$id,$type,$module) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  $type = $hash->{dataTypes} if( !$type );
  $type = "Temperature,Co2,Humidity,Noise,Pressure" if( !$type );

  netatmo_refreshToken( $iohash );

  my %data = (access_token => $iohash->{access_token}, device_id => $id, scale => "max", type => $type);
  $data{"module_id"} = $module if( $module );

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );
  $data{"date_begin"} = $lastupdate if( defined($lastupdate) );

  HttpUtils_NonblockingGet({
    url => "$iohash->{https}://api.netatmo.net/api/getmeasure",
    timeout => 10,
    noshutdown => 1,
    data => \%data,
    hash => $hash,
    type => 'getmeasure',
    requested => $type,
    callback => \&netatmo_dispatch,
  });
}

sub
netatmo_poll($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);

  if( $hash->{SUBTYPE} eq "DEVICE" ) {
    netatmo_pollDevice($hash);
  } elsif( $hash->{SUBTYPE} eq "MODULE" ) {
    netatmo_pollDevice($hash);
  }

  if( defined($hash->{helper}{update_count}) && $hash->{helper}{update_count} > 1024 ) {
    InternalTimer(gettimeofday()+2, "netatmo_poll", $hash, 0);
  } else {
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "netatmo_poll", $hash, 0);
  }
}

sub
netatmo_dispatch($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  $hash->{openRequests} -= 1 if( $param->{type} eq 'getmeasure' );

  if( $err ) {
    Log3 $name, 2, "$name: http request failed: $err";
  } elsif( $data ) {
    Log3 $name, 4, "$name: $data";

    $data =~ s/\n//g;
    if( $data !~ m/^{.*}$/m ) {
      Log3 $name, 2, "$name: invalid json detected: >>$data<<";
      return undef;
    }

    my $json;
    if( netatmo_isFritzBox() ) {
      $json = decode_json($data);
    } else {
      $json = JSON->new->utf8(0)->decode($data);
    }

    if( $json->{error} ) {
      #$hash->{lastError} = $json->{error}{message};
    }

    if( $param->{type} eq 'token' ) {
      netatmo_parseToken($hash,$json);
    } elsif( $param->{type} eq 'devicelist' ) {
      netatmo_parseDeviceList($hash,$json);
    } elsif( $param->{type} eq 'getmeasure' ) {
      netatmo_parseReadings($hash,$json,$param->{requested});
    } elsif( $param->{type} eq 'publicdata' ) {
      return netatmo_parsePublic($hash,$json);
    } elsif( $param->{type} eq 'address' ) {
      return netatmo_parseAddress($hash,$json);
    } elsif( $param->{type} eq 'latlng' ) {
      return netatmo_parseLatLng($hash,$json);
    }
  }
}

sub
netatmo_autocreate($;$)
{
  my($hash,$force) = @_;
  my $name = $hash->{NAME};

  if( !$hash->{helper}{devices} ) {
    netatmo_getDevices($hash);
    return undef if( !$force );
  }

  if( !$force ) {
    foreach my $d (keys %defs) {
      next if($defs{$d}{TYPE} ne "autocreate");
      return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
    }
  }

  my $autocreated = 0;

  my $devices = $hash->{helper}{devices};
  foreach my $device (@{$devices}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"D$device->{_id}"}) ) {
      Log3 $name, 4, "$name: device '$device->{_id}' already defined";
      next;
    }
    if( defined($modules{$hash->{TYPE}}{defptr}{"M$device->{_id}"}) ) {
      Log3 $name, 4, "$name: module '$device->{_id}' already defined";
      next;
    }

    my $id = $device->{_id};
    my $devname = "netatmo_D". $id;
    $devname =~ s/:/_/g;
    my $define= "$devname netatmo $id";
    if( $device->{main_device} ) {
      $devname = "netatmo_M". $id;
      $devname =~ s/:/_/g;
      $define= "$devname netatmo MODULE $device->{main_device} $id";
    }

    Log3 $name, 3, "$name: create new device '$devname' for device '$id'";
    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".$device->{module_name}) if( defined($device->{module_name}) );
      $cmdret= CommandAttr(undef,"$devname room netatmo");
      $cmdret= CommandAttr(undef,"$devname IODev $name");

      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );

  return "created $autocreated devices";
}

sub
netatmo_parseToken($$)
{
  my($hash, $json) = @_;

  RemoveInternalTimer($hash);

  my $had_token = $hash->{access_token};

  $hash->{access_token} = $json->{access_token};
  $hash->{refresh_token} = $json->{refresh_token};

  if( $hash->{access_token} ) {
    $hash->{STATE} = "Connected";

    ($hash->{expires_at}) = gettimeofday();
    $hash->{expires_at} += $json->{expires_in};

    netatmo_getDevices($hash) if( !$had_token );

    InternalTimer(gettimeofday()+$json->{expires_in}*3/4, "netatmo_refreshTokenTimer", $hash, 0);
  } else {
    $hash->{STATE} = "Error" if( !$hash->{access_token} );
    InternalTimer(gettimeofday()+60, "netatmo_refreshTokenTimer", $hash, 0);
  }
}
sub
netatmo_parseDeviceList($$)
{
  my($hash, $json) = @_;

  my $do_autocreate = 1;
  $do_autocreate = 0 if( !defined($hash->{helper}{devices}) ); #autocreate

  my @devices = ();
  foreach my $device (@{$json->{body}{devices}}) {
    push( @devices, $device );
  }
  foreach my $module (@{$json->{body}{modules}}) {
    push( @devices, $module );
  }

  $hash->{helper}{devices} = \@devices;

  netatmo_autocreate($hash) if( $do_autocreate );
}

sub
netatmo_updateReadings($$)
{
  my($hash, $readings) = @_;

  my ($seconds) = gettimeofday();

  my $latest = 0;
  if( $readings && @{$readings} ) {
    readingsBeginUpdate($hash);
    my $i = 0;
    foreach my $reading (sort { $a->[0] <=> $b->[0] } @{$readings}) {
      $hash->{".updateTimestamp"} = FmtDateTime($reading->[0]);
      $hash->{CHANGETIME}[$i++] = FmtDateTime($reading->[0]);
      readingsBulkUpdate( $hash, $reading->[1], $reading->[2] );
      $latest = $reading->[0] if( $reading->[0] > $latest );
    }
    #$hash->{helper}{update_count} = int(@{$readings});

    #$seconds = $latest + 1 if( $latest );
    readingsBulkUpdate( $hash, ".lastupdate", $seconds, 0 );

    readingsEndUpdate($hash,1);

    delete $hash->{CHANGETIME};
  }

  return ($seconds,$latest);
}
sub
netatmo_parseReadings($$;$)
{
  my($hash, $json, $requested) = @_;
  my $name = $hash->{NAME};

  my $reading_names = $hash->{helper}{readingNames};
  if( $requested ) {
    my @readings = split( ',', $requested );
    $reading_names = \@readings;
  }

  if( $json ) {
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );
    my @r = ();
    my $readings = \@r;
    $readings = $hash->{readings} if( defined($hash->{readings}) );
    if( $hash->{status} eq "ok" ) {
      foreach my $values ( @{$json->{body}}) {
        my $time = $values->{beg_time};
        my $step_time = $values->{step_time};

        foreach my $value (@{$values->{value}}) {
          my $i = 0;
          foreach my $reading (@{$value}) {
            next if( !defined($reading) );

            #my $name = $hash->{helper}{readingNames}[$i];
            my $name = lc($reading_names->[$i++]);

            push(@{$readings}, [$time, $name, $reading]);
          }

          $time += $step_time if( $step_time );
        }
      }

      if( $hash->{openRequests} ) {
        $hash->{readings} = $readings;
      } else {
        my ($seconds,undef) = netatmo_updateReadings( $hash, $readings );
        $hash->{LAST_POLL} = FmtDateTime( $seconds );
        delete $hash->{readings};
      }
    }
  }
}

sub
netatmo_parsePublic($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  if( $json ) {
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    if( $hash->{status} eq "ok" ) {
      if( $hash->{Lat} ) {
        my $found = 0;
        my @readings = ();
        my $devices = $json->{body};
        if( ref($devices) eq "ARRAY" ) {
          foreach my $device (@{$devices}) {
            next if( $device->{_id} ne $hash->{Device} );
            next if( ref($device->{measures}) ne "HASH" );
            Log3 $name, 4, "$name found:  $device->{_id}: $device->{place}->{location}->[0] $device->{place}->{location}->[1]";
            foreach my $module ( keys %{$device->{measures}}) {
              next if( ref($device->{measures}->{$module}->{res}) ne "HASH" );
              foreach my $timestamp ( keys %{$device->{measures}->{$module}->{res}} ) {
                next if( $hash->{LAST_POLL} && $timestamp <= $hash->{LAST_POLL} );
                my $i = 0;
                foreach my $value ( @{$device->{measures}->{$module}->{res}->{$timestamp}} ) {
                  my $type = $device->{measures}->{$module}->{type}[$i];

                  push(@readings, [$timestamp, lc($type), $value]);

                  ++$i;
                }
              }
            }

            $found = 1;
            last;
          }
        }

        my (undef,$latest) = netatmo_updateReadings( $hash, \@readings );
        $hash->{LAST_POLL} = $latest if( @readings );

        $hash->{STATE} = "Error: device not found" if( !$found );
      } else {
        return $json->{body};
      }
    } else {
      return $hash->{status};
    }
  }
}

sub
netatmo_parseAddress($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  if( $json ) {
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    if( $hash->{status} eq "OK" ) {
      if( $json->{results} ) {
        return $json->{results}->[0]->{formatted_address};
      }
    } else {
      return $hash->{status};
    }
  }
}

sub
netatmo_parseLatLng($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  if( $json ) {
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    if( $hash->{status} eq "OK" ) {
      if( $json->{results} ) {
        return $json->{results}->[0]->{geometry}->{bounds};
      }
    } else {
      return $hash->{status};
    }
  }
}

sub
netatmo_pollDevice($)
{
  my ($hash) = @_;

  $hash->{openRequests} = 0 if ( !defined(  $hash->{openRequests}) );

  if( $hash->{Module} ) {
    my @types = split( ' ', $hash->{dataTypes} );
    my $lastupdate = ReadingsVal( $hash->{NAME}, ".lastupdate", undef );
    #$lastupdate = "2014-07-18 14:06:54";
    $hash->{openRequests} += int(@types);
    foreach my $module (split( ' ', $hash->{Module} ) ) {
      my $type;
      $type = shift(@types) if( $hash->{Module} =~ m/ / );
      readingsSingleUpdate($hash, ".lastupdate", $lastupdate, 0);
      netatmo_requestDeviceReadings( $hash, $hash->{Device}, $type, $module ne $hash->{Device}?$module:undef );
    }
  } elsif( defined($hash->{Lat}) ) {
    $hash->{openRequests} += 1;
    netatmo_getPublicDevices($hash, 0, $hash->{Lon}, $hash->{Lat}, $hash->{Rad} );
  } else {
    $hash->{openRequests} += 1;
    netatmo_requestDeviceReadings( $hash, $hash->{Device} );
  }
}

sub
netatmo_Get($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list;
  if( $hash->{SUBTYPE} eq "DEVICE"
      || $hash->{SUBTYPE} eq "MODULE" ) {
    $list = "update:noArg updateAll:noArg";

    if( $cmd eq "updateAll" ) {
      $cmd = "update";
      CommandDeleteReading( undef, "$name .*" );
    }

    if( $cmd eq "update" ) {
      netatmo_poll($hash);
      return undef;
    }
  } elsif( $hash->{SUBTYPE} eq "ACCOUNT" ) {
    $list = "devices:noArg public";

    if( $cmd eq "devices" ) {
      my $devices = netatmo_getDevices($hash,1);
      my $ret;
      foreach my $device (@{$devices}) {
        $ret .= "\n" if( $ret );
        $ret .= "$device->{_id}\t$device->{module_name}\t$device->{hw_version}\t$device->{firmware}";
      }

      $ret = "id\t\t\tname\t\thw\tfw\n" . $ret if( $ret );
      $ret = "no devices found" if( !$ret );
      return $ret;
    } elsif( $cmd eq "public" ) {
      my $station;
      $station = shift @args if( $args[0] && $args[0] =~ m/[\da-f]{2}(:[\da-f]{2}){5}/ );

      if( $args[0] && ( $args[0] =~ m/^\d{5}$/
                        || $args[0] =~ m/^a:/ ) ) {
        my $addr = shift @args;
        $addr = substr($addr,2) if( $addr =~ m/^a:/ );

        my $bounds =  netatmo_getLatLong( $hash,1,$addr );
        $args[0] = $bounds->{northeast}->{lng};
        $args[1] = $bounds->{northeast}->{lat};
        $args[2] = $bounds->{southwest}->{lng};
        $args[3] = $bounds->{southwest}->{lat};
      }

      my $devices = netatmo_getPublicDevices($hash, 1, $args[0], $args[1], $args[2], $args[3] );
      my $ret;

      if( ref($devices) eq "ARRAY" ) {
        foreach my $device (@{$devices}) {
          next if( $station && $station ne $device->{_id} );
          $ret .= "\n" if( $ret );
          $ret .= sprintf( "%s\t%.8f\t%.8f\t%i", $device->{_id},
                                                 $device->{place}->{location}->[0], $device->{place}->{location}->[1],
                                                 $device->{place}->{altitude} );
          $ret .= "\t";

          my $addr .= netatmo_getAddress( $hash, 1, $device->{place}->{location}->[0], $device->{place}->{location}->[1] );
          next if( ref($device->{measures}) ne "HASH" );

          my $ext;
          foreach my $module ( sort keys %{$device->{measures}}) {
            next if( ref($device->{measures}->{$module}->{res}) ne "HASH" );

            $ext .= "$module ";
            $ext .= join(',', @{$device->{measures}->{$module}->{type}});
            $ext .= " ";

            foreach my $timestamp ( keys %{$device->{measures}->{$module}->{res}} ) {
              my $i = 0;
              foreach my $value ( @{$device->{measures}->{$module}->{res}->{$timestamp}} ) {
                my $type = $device->{measures}->{$module}->{type}[$i];

                if( $type eq "temperature" ) {
                  $ret .= sprintf( "\t%.1f \xc2\xb0C", $value );
                } elsif( $type eq "humidity" ) {
                  $ret .= sprintf( "\t%i %%", $value );
                } elsif( $type eq "pressure" ) {
                  $ret .= sprintf( "\t%i hPa", $value );
                } elsif( $type eq "rain" ) {
                  $ret .= sprintf( "\t%i mm", $value );
                }

              ++$i;
              }
              last;
            }
          }
          my $got_rain = 0;
          foreach my $module ( keys %{$device->{measures}}) {
            my $value = $device->{measures}->{$module}->{rain_60min};
            if( defined($value) ) {
              $got_rain = 1;

              $ext .= "$module ";
              $ext .= join(',', "rain");
              $ext .= " ";

              $ret .= sprintf( "\t%i mm", $value ) if( defined($value) );
            }
          }
          $ret .= "\t" if( !$got_rain );

          $ret .= "\t$addr";

          $ret .= "\n\tdefine netatmo_P$device->{_id} netatmo PUBLIC $device->{_id} $ext" if( $station );
        }
      } else {
        $ret = $devices if( !ref($devices) );
      }

      $ret = "id\t\t\tlongitude\tlatitude\taltitude\n" . $ret if( $ret );
      $ret = "no devices found" if( !$ret );
      return $ret;
    }
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
netatmo_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval");
  $attrVal = 60*5 if($attrName eq "interval" && $attrVal < 60*5 && $attrVal != 0);

  if( $attrName eq "interval" ) {
    my $hash = $defs{$name};
    $hash->{INTERVAL} = $attrVal;
    $hash->{INTERVAL} = 60*5 if( !$hash->{INTERVAL} );
  } elsif( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    RemoveInternalTimer($hash);
    if( $cmd eq "set" && $attrVal ne "0" ) {
    } else {
      $attr{$name}{$attrName} = 0;
      netatmo_poll($hash);
    }
  } elsif( $attrName eq "nossl" ) {
    my $hash = $defs{$name};
    if( $hash->{SUBTYPE} eq "ACCOUNT" ) {
      if( $cmd eq "set" && $attrVal ne "0" ) {
        $hash->{https} = "http";
      } else {
        $hash->{https} = "https";
      }
    } else {
      return $attrName ." not allowed for netatmo $hash->{SUBTYPE}";
    }
  }

  if( $cmd eq "set" ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}


1;

=pod
=begin html

<a name="netatmo"></a>
<h3>netatmo</h3>
<ul>
  A Fhem module for netatmo weatherstations.<br><br>

  Notes:
  <ul>
    <li>JSON has to be installed on the FHEM host.</li>
  </ul><br>

  <a name="netatmo_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; netatmo &lt;device&gt;</code><br>
    <code>define &lt;name&gt; netatmo [ACCOUNT] &lt;username&gt; &lt;password&gt; &lt;client_id&gt; &lt;client_secret&gt;</code><br>
    <br>

    Defines a netatmo device.<br><br>
    If a netatmo device of the account type is created all fhem devices for the netatmo devices are automaticaly created
    (if autocreate is not disabled).
    <br>

    Examples:
    <ul>
      <code>define netatmo netatmo ACCOUNT abc@test.com myPassword 2134123412399119d4123134 AkqcOIHqrasfdaLKcYgZasd987123asd</code><br>
      <code>define netatmo netatmo 2f:13:2b:93:12:31</code><br>
      <code>define netatmo netatmo MODULE  2f:13:2b:93:12:31 f1:32:b9:31:23:11</code><br>
    </ul>
  </ul><br>

  <a name="netatmo_Readings"></a>
  <b>Readings</b>
  <ul>
  </ul><br>

  <a name="netatmo_Set"></a>
  <b>Set</b>
  <ul>
    <li>autocreate<br>
      Create fhem devices for all netatmo devices.</li>
  </ul><br>

  <a name="netatmo_Get"></a>
  <b>Get</b>
  <ul>
    <li>devices<br>
      list the netatmo devices for this account</li>
    <li>update<br>
      trigger an update</li>
    <li>public [&lt;station&gt;] [&lt;address&gt;] &lt;args&gt;<br>
      no arguments -> get all public stations in a radius of 0.025&deg; around global fhem longitude/latitude<br>
      &lt;rad&gt; -> get all public stations in a radius of &lt;rad&gt;&deg; around global fhem longitude/latitude<br>
      &lt;lon&gt; &lt;lat&gt; [&lt;rad&gt;] -> get all public stations in a radius of 0.025&deg; or &lt;rad&gt;&deg; around &lt;lon&gt;/&lt;lat&gt;<br>
      &lt;lon_ne&gt; &lt;lat_ne&gt; &lt;lon_sw&gt; &lt;lat_sw&gt; -> get all public stations in the area of &lt;lon_ne&gt; &lt;lat_ne&gt; &lt;lon_sw&gt; &lt;lat_sw&gt;<br>
      if &lt;address&gt; is given then list stations in the area of this address. can be given as 5 digit german postal code or a: followed by a textual address. all spaces have to be replaced by a +.<br>
      if &lt;station&gt; is given then print fhem define for this station<br></li>
  </ul><br>

  <a name="netatmo_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>interval<br>
      the interval in seconds used to check for new values.</li>
    <li>disable<br>
      1 -> stop polling</li>
    <li>nossl<br>
      1 -> don't use ssl.</li><br>
  </ul>
</ul>

=end html
=cut
