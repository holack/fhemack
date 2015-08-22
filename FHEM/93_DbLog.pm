##############################################
# $Id: 93_DbLog.pm 8653 2015-05-30 11:03:38Z tobiasfaust $
#
# 93_DbLog.pm
# written by Dr. Boris Neubert 2007-12-30
# e-mail: omega at online dot de
#
# modified and maintained by Tobias Faust since 2012-06-26
# e-mail: tobias dot faust at online dot de
#
##############################################

package main;
use strict;
use warnings;
use DBI;
use Data::Dumper;
use feature qw/say switch/;

my %columns = ("DEVICE"  => 64,
               "TYPE"    => 64,
               "EVENT"   => 512,
               "READING" => 64,
               "VALUE"   => 128,
               "UNIT"    => 32
          );

sub dbReadings($@);

################################################################
sub DbLog_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "DbLog_Define";
  $hash->{UndefFn}  = "DbLog_Undef";
  $hash->{NotifyFn} = "DbLog_Log";
  $hash->{SetFn}    = "DbLog_Set";
  $hash->{GetFn}    = "DbLog_Get";
  $hash->{AttrFn}   = "DbLog_Attr";
  $hash->{ShutdownFn} = "DbLog_Shutdown";
  $hash->{AttrList} = "disable:0,1 ".
           "DbLogType:Current,History,Current/History ".
           "shutdownWait ".
           "suppressUndef:0,1 ".
           "DbLogSelectionMode:Exclude,Include,Exclude/Include";

  # Das Attribut DbLogSelectionMode legt fest, wie die Device-Spezifischen Atrribute 
  # DbLogExclude und DbLogInclude behandelt werden sollen.
  #            - Exclude:      Es wird nur das Device-spezifische Attribut Exclude beruecksichtigt, 
  #                                    d.h. generell wird alles geloggt, was nicht per DBLogExclude ausgeschlossen wird
  #            - Include:  Es wird nur das Device-spezifische Attribut Include beruecksichtigt,
  #                                    d.h. generell wird nichts geloggt, ausßer dem was per DBLogInclude eingeschlossen wird
  #            - Exclude/Include:      Es wird zunaechst Exclude geprueft und bei Ausschluß wird ggf. noch zusaetzlich Include geprueft,
  #                                                    d.h. generell wird alles geloggt, es sei denn es wird per DBLogExclude ausgeschlossen.
  #                                                    Wird es von DBLogExclude ausgeschlossen, kann es trotzdem wieder per DBLogInclude
  #                                                    eingeschlossen werden.
  

  addToAttrList("DbLogInclude");
  addToAttrList("DbLogExclude");

  $hash->{FW_detailFn}      = "DbLog_fhemwebFn";
  $hash->{SVG_sampleDataFn} = "DbLog_sampleDataFn";

}

###############################################################
sub DbLog_Define($@)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> DbLog configuration regexp"
    if(int(@a) != 4);

  my $regexp = $a[3];

  eval { "Hallo" =~ m/^$regexp$/ };
  return "Bad regexp: $@" if($@);
  $hash->{REGEXP} = $regexp;

  $hash->{CONFIGURATION}= $a[2];

  #remember PID for plotfork
  $hash->{PID} = $$;

  # read configuration data
  my $ret = _DbLog_readCfg($hash);
  return $ret if ($ret); # return on error while reading configuration

  readingsSingleUpdate($hash, 'state', 'waiting for connection', 1);
  eval { DbLog_Connect($hash); };

  return undef;
}

#####################################
sub DbLog_Undef($$) {
  my ($hash, $name) = @_;

  my $dbh= $hash->{DBH};
  $dbh->disconnect() if(defined($dbh));
  
  return undef;
}

#####################################
sub DbLog_Shutdown($) {  
  my ($hash) = @_;
  
  my $name = $hash->{NAME};
  my $shutdownWait = AttrVal($name,"shutdownWait",undef);
  if(defined($shutdownWait)) {
    Log3($name, 2, "DbLog $name waiting for shutdown");
    sleep($shutdownWait);
  }
  return undef; 
}


################################################################
#
# Wird bei jeder Aenderung eines Attributes dieser
# DbLog-Instanz aufgerufen
#
################################################################
sub DbLog_Attr(@)
{
  my @a = @_;
  my $do = 0;

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $defs{$a[1]}{STATE} = ($do == 1 ? "disabled" : "active");

  return undef;
}

################################################################
#
# Parsefunktion, abhaengig vom Devicetyp
#
################################################################
sub DbLog_ParseEvent($$$)
{
  my ($device, $type, $event)= @_;
  my @result;
  my $reading;
  my $value;
  my $unit;

  my $dtype = $defs{$device}{TYPE};
  if($modules{$dtype}{DbLog_splitFn}) {
    # let the module do the job!
    Log 4,"DbLog_ParseEvent calling external DbLog_splitFn for type: $dtype";
    no strict "refs";
    ($reading,$value,$unit) = 
        &{$modules{$dtype}{DbLog_splitFn}}($event);
    use strict "refs";
    @result= ($reading,$value,$unit);
    return @result;
  }

  # split the event into reading, value and unit
  # "day-temp: 22.0 (Celsius)" -> "day-temp", "22.0 (Celsius)"
  my @parts   = split(/: /,$event);
  $reading = shift @parts;
  if(@parts == 2) { 
    $value = $parts[0];
    $unit  = $parts[1];
  } else {
    $value   = join(": ", @parts);
    $unit    = "";
  } 

  #default
  if(!defined($reading)) { $reading = ""; }
  if(!defined($value))   { $value   = ""; }
  if( $value eq "" ) {
    $reading= "state";
    $value= $event;
  }

  #globales Abfangen von 
  # - temperature
  # - humidity
  if   ($reading =~ m(^temperature)) { $unit= "°C"; } # wenn reading mit temperature beginnt
  elsif($reading =~ m(^humidity)) { $unit= "%"; }


  # the interpretation of the argument depends on the device type
  # EMEM, M232Counter, M232Voltage return plain numbers
  if(($type eq "M232Voltage") ||
     ($type eq "M232Counter") ||
     ($type eq "EMEM")) {
  }
  #OneWire 
  elsif(($type eq "OWMULTI")) {
    if(int(@parts)>1) {
      $reading = "data";
      $value = $event;
    } else {
      @parts = split(/\|/, AttrVal($device, $reading."VUnit", ""));
      $unit = $parts[1] if($parts[1]);
      if(lc($reading) =~ m/temp/) {
        $value=~ s/ \(Celsius\)//;
        $value=~ s/([-\.\d]+).*/$1/;
        $unit= "°C";
      }
      elsif(lc($reading) =~ m/(humidity|vwc)/) { 
        $value=~ s/ \(\%\)//; 
        $unit= "%"; 
      }
    }
  }
  # Onewire
  elsif(($type eq "OWAD") ||
        ($type eq "OWSWITCH")) {
      if(int(@parts)>1) {
        $reading = "data";
        $value = $event;
      } else {
        @parts = split(/\|/, AttrVal($device, $reading."Unit", ""));
        $unit = $parts[1] if($parts[1]);
      }
  }

  # FBDECT
  elsif (($type eq "FBDECT")) {
    if ( $value=~/([\.\d]+)\s([a-z])/i ) {
     $value = $1;
     $unit  = $2;
    }
  }

  # MAX
  elsif(($type eq "MAX")) {
    $unit= "°C" if(lc($reading) =~ m/temp/);
    $unit= "%"   if(lc($reading) eq "valveposition");
  }

  # FS20
  elsif(($type eq "FS20") ||
        ($type eq "X10")) {
    if($reading =~ m/^dim(\d+).*/o) {
      $value = $1;
      $reading= "dim";
      $unit= "%";
    }
    elsif(!defined($value) || $value eq "") {
      $value= $reading;
      $reading= "data";
    }
  }

  # FHT
  elsif($type eq "FHT") {
    if($reading =~ m(-from[12]\ ) || $reading =~ m(-to[12]\ )) {
      @parts= split(/ /,$event);
      $reading= $parts[0];
      $value= $parts[1];
      $unit= "";
    }
    elsif($reading =~ m(-temp)) { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
    elsif($reading =~ m(temp-offset)) { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
    elsif($reading =~ m(^actuator[0-9]*)) {
      if($value eq "lime-protection") {
        $reading= "actuator-lime-protection";
        undef $value;
      }
      elsif($value =~ m(^offset:)) {
        $reading= "actuator-offset";
        @parts= split(/: /,$value);
        $value= $parts[1];
        if(defined $value) {
          $value=~ s/%//; $value= $value*1.; $unit= "%";
        }
      }
      elsif($value =~ m(^unknown_)) {
        @parts= split(/: /,$value);
        $reading= "actuator-" . $parts[0];
        $value= $parts[1];
        if(defined $value) {
          $value=~ s/%//; $value= $value*1.; $unit= "%";
        }
      }
      elsif($value =~ m(^synctime)) {
        $reading= "actuator-synctime";
        undef $value;
      }
      elsif($value eq "test") {
        $reading= "actuator-test";
        undef $value;
      }
      elsif($value eq "pair") {
        $reading= "actuator-pair";
        undef $value;
      }
      else {
        $value=~ s/%//; $value= $value*1.; $unit= "%";
      }
    }
  }
  # KS300
  elsif($type eq "KS300") {
    if($event =~ m(T:.*)) { $reading= "data"; $value= $event; }
    elsif($event =~ m(avg_day)) { $reading= "data"; $value= $event; }
    elsif($event =~ m(avg_month)) { $reading= "data"; $value= $event; }
    elsif($reading eq "temperature") { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
    elsif($reading eq "wind") { $value=~ s/ \(km\/h\)//; $unit= "km/h"; }
    elsif($reading eq "rain") { $value=~ s/ \(l\/m2\)//; $unit= "l/m2"; }
    elsif($reading eq "rain_raw") { $value=~ s/ \(counter\)//; $unit= ""; }
    elsif($reading eq "humidity") { $value=~ s/ \(\%\)//; $unit= "%"; }
    elsif($reading eq "israining") {
      $value=~ s/ \(yes\/no\)//;
      $value=~ s/no/0/;
      $value=~ s/yes/1/;
    }
  }
  # HMS
  elsif($type eq "HMS" ||
        $type eq "CUL_WS" ||
        $type eq "OWTHERM") {
    if($event =~ m(T:.*)) { $reading= "data"; $value= $event; }
    elsif($reading eq "temperature") {
      $value=~ s/ \(Celsius\)//; 
      $value=~ s/([-\.\d]+).*/$1/; #OWTHERM
      $unit= "°C"; 
    }
    elsif($reading eq "humidity") { $value=~ s/ \(\%\)//; $unit= "%"; }
    elsif($reading eq "battery") {
      $value=~ s/ok/1/;
      $value=~ s/replaced/1/;
      $value=~ s/empty/0/;
    }
  }
  # CUL_HM
  elsif ($type eq "CUL_HM") {
    # remove trailing %  
    $value=~ s/ \%$//;
  }

  # BS
  elsif($type eq "BS") {
    if($event =~ m(brightness:.*)) {
      @parts= split(/ /,$event);
      $reading= "lux";
      $value= $parts[4]*1.;
      $unit= "lux";
    }
  }

  # RFXTRX Lighting
  elsif($type eq "TRX_LIGHT") {
    if($reading =~ m/^level (\d+)/) {
        $value = $1;
        $reading= "level";
    }
  }

  # RFXTRX Sensors
  elsif($type eq "TRX_WEATHER") {
    if($reading eq "energy_current") { $value=~ s/ W//; }
    elsif($reading eq "energy_total") { $value=~ s/ kWh//; }
#    elsif($reading eq "temperature") {TODO}
#    elsif($reading eq "temperature")  {TODO
    elsif($reading eq "battery") {
      if ($value=~ m/(\d+)\%/) { 
        $value= $1; 
      }
      else {
        $value= ($value eq "ok");
      }
    }
  }

  # Weather
  elsif($type eq "WEATHER") {
    if($event =~ m(^wind_condition)) {
      @parts= split(/ /,$event); # extract wind direction from event
      if(defined $parts[0]) {
        $reading = "wind_direction";
        $value= $parts[2];
      }
    }
    elsif($reading eq "wind_chill") { $unit= "°C"; }
    elsif($reading eq "wind_direction") { $unit= ""; }
    elsif($reading =~ m(^wind)) { $unit= "km/h"; } # wind, wind_speed
    elsif($reading =~ m(^temperature)) { $unit= "°C"; } # wenn reading mit temperature beginnt
    elsif($reading =~ m(^humidity)) { $unit= "%"; }
    elsif($reading =~ m(^pressure)) { $unit= "hPa"; }
    elsif($reading =~ m(^pressure_trend)) { $unit= ""; }
  }

  # FHT8V
  elsif($type eq "FHT8V") {
    if($reading =~ m(valve)) {
      @parts= split(/ /,$event);
      $reading= $parts[0];
      $value= $parts[1];
      $unit= "%";
    }
  }

  # Dummy
  elsif($type eq "DUMMY")  {
    if( $value eq "" ) {
      $reading= "data";
      $value= $event;
    }
    $unit= "";
  }

  @result= ($reading,$value,$unit);
  return @result;
}

################################################################
#
# param1: hash
# param2: DbLogType -> Current oder History oder Current/History
# param4: Timestamp
# param5: Device
# param6: Type
# param7: Event
# param8: Reading
# param9: Value
# param10: Unit
#
################################################################
sub DbLog_Push(@) {
  my ($hash, $DbLogType, $timestamp, $device, $type, $event, $reading, $value, $unit) = @_;
  my $dbh= $hash->{DBH};
  
  # Daten auf maximale laenge beschneiden
  $device   = substr($device,0, $columns{DEVICE});
  $type     = substr($type,0, $columns{TYPE});
  $event    = substr($event,0, $columns{EVENT});
  $reading  = substr($reading,0, $columns{READING});
  $value    = substr($value,0, $columns{VALUE});
  $unit     = substr($unit,0, $columns{UNIT});

  $dbh->{RaiseError} = 1;
  $dbh->{PrintError} = 0;  

  $dbh->begin_work();
  
  my $sth_ih = $dbh->prepare_cached("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)") if (lc($DbLogType) =~ m(history) );
  my $sth_ic = $dbh->prepare_cached("INSERT INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)") if (lc($DbLogType) =~ m(current) );
  my $sth_uc = $dbh->prepare_cached("UPDATE current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)") if (lc($DbLogType) =~ m(current) );

  Log3 $hash->{NAME}, 5, "DbLog: logging of Device: $device , Type: $type , Event: $event , Reading: $reading , Value: $value , Unit: $unit";

  eval {
    # insert into history
    if (lc($DbLogType) =~ m(history) ) {
      my $rv_ih = $sth_ih->execute(($timestamp, $device, $type, $event, $reading, $value, $unit));
    }

    # update or insert current
    if (lc($DbLogType) =~ m(current) ) {
      my $rv_uc = $sth_uc->execute(($timestamp, $type, $event, $value, $unit, $device, $reading));
      if ($rv_uc == 0) {
        my $rv_ic = $sth_ic->execute(($timestamp, $device, $type, $event, $reading, $value, $unit));
      }
    }
  };

  
  if ($@) {
    Log3 $hash->{NAME}, 2, "DbLog: Failed to insert new readings into database: $@";
    $dbh->rollback();
    # reconnect
    $dbh->disconnect();  
    DbLog_Connect($hash);
  }
  else {
    $dbh->commit();
    $dbh->{RaiseError} = 0; 
    $dbh->{PrintError} = 1;
  }

  return $dbh->{RaiseError};
}

################################################################
#
# Hauptroutine zum Loggen. Wird bei jedem Eventchange
# aufgerufen
#
################################################################
sub DbLog_Log($$) {
  # Log is my entry, Dev is the entry of the changed device
  my ($hash, $dev) = @_;

  return undef if($hash->{STATE} eq "disabled");

  # name and type required for parsing
  my $n= $dev->{NAME};
  my $t= uc($dev->{TYPE});

  # timestamp in SQL format YYYY-MM-DD hh:mm:ss
  #my ($sec,$min,$hr,$day,$mon,$yr,$wday,$yday,$isdst)= localtime(time);
  #my $ts= sprintf("%04d-%02d-%02d %02d:%02d:%02d", $yr+1900,$mon+1,$day,$hr,$min,$sec);

  my $re = $hash->{REGEXP};
  my $max = int(@{$dev->{CHANGED}});
  my $ts_0 = TimeNow();
  my $now = gettimeofday(); # get timestamp in seconds since epoch
  my $DbLogExclude = AttrVal($dev->{NAME}, "DbLogExclude", undef);
  my $DbLogInclude = AttrVal($dev->{NAME}, "DbLogInclude",undef);
  my $DbLogSelectionMode=AttrVal($hash->{NAME},"DbLogSelectionMode","Exclude");  
  my $DbLogType = AttrVal($hash->{NAME}, "DbLogType", "Current/History");
      
  #one Transaction
  eval {    
    for (my $i = 0; $i < $max; $i++) {
      my $s = $dev->{CHANGED}[$i];
      $s = "" if(!defined($s));
      if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/ || $DbLogSelectionMode eq 'Include') {
        my $ts = $ts_0;
        $ts = $dev->{CHANGETIME}[$i] if(defined($dev->{CHANGETIME}[$i]));
        # $ts is in SQL format YYYY-MM-DD hh:mm:ss
    
        my @r= DbLog_ParseEvent($n, $t, $s);
        my $reading= $r[0];
        my $value= $r[1];
        my $unit= $r[2];
        if(!defined $reading) { $reading= ""; }
        if(!defined $value) { $value= ""; }
        if(!defined $unit || $unit eq "") {
          $unit = AttrVal("$n", "unit", "");
        }


        #Je nach DBLogSelectionMode muss das vorgegebene Ergebnis der Include-, bzw. Exclude-Pruefung
        #entsprechend unterschiedlich vorbelegt sein.
        #keine Readings loggen die in DbLogExclude explizit ausgeschlossen sind
        my $DoIt = 0;
        $DoIt = 1 if($DbLogSelectionMode =~ m/Exclude/ );
        if($DbLogExclude && $DbLogSelectionMode =~ m/Exclude/) {
          # Bsp: "(temperature|humidity):300 battery:3600"
          my @v1 = split(/,/, $DbLogExclude);
          for (my $i=0; $i<int(@v1); $i++) {
            my @v2 = split(/:/, $v1[$i]);
            $DoIt = 0 if(!$v2[1] && $reading =~ m/^$v2[0]$/); #Reading matcht auf Regexp, kein MinIntervall angegeben
            if(($v2[1] && $reading =~ m/^$v2[0]$/) && ($v2[1] =~ m/^(\d+)$/)) {
              #Regexp matcht und MinIntervall ist angegeben
              my $lt = $defs{$dev->{NAME}}{Helper}{DBLOG}{$reading}{$hash->{NAME}}{TIME};
              my $lv = $defs{$dev->{NAME}}{Helper}{DBLOG}{$reading}{$hash->{NAME}}{VALUE};
              $lt = 0 if(!$lt);
              $lv = "" if(!$lv);

              if(($now-$lt < $v2[1]) && ($lv eq $value)) {
                # innerhalb MinIntervall und LastValue=Value
                $DoIt = 0;
              }
            }
          }
        }
        #Hier ggf. zusaetlich noch dbLogInclude pruefen, falls bereits durch DbLogExclude ausgeschlossen
        #Im Endeffekt genau die gleiche Pruefung, wie fuer DBLogExclude, lediglich mit umgegkehrtem Ergebnis.
        if($DoIt == 0) {
                if($DbLogInclude && ($DbLogSelectionMode =~ m/Include/)) {
                  my @v1 = split(/,/, $DbLogInclude);
                  for (my $i=0; $i<int(@v1); $i++) {
                        my @v2 = split(/:/, $v1[$i]);
                        $DoIt = 1 if(!$v2[1] && $reading =~ m/^$v2[0]$/); #Reading matcht auf Regexp, kein MinIntervall angegeben
                        if(($v2[1] && $reading =~ m/^$v2[0]$/) && ($v2[1] =~ m/^(\d+)$/)) {
                          #Regexp matcht und MinIntervall ist angegeben
                          my $lt = $defs{$dev->{NAME}}{Helper}{DBLOG}{$reading}{$hash->{NAME}}{TIME};
                          my $lv = $defs{$dev->{NAME}}{Helper}{DBLOG}{$reading}{$hash->{NAME}}{VALUE};
                          $lt = 0 if(!$lt);
                          $lv = "" if(!$lv);
       
                          if(($now-$lt < $v2[1]) && ($lv eq $value)) {
                                # innerhalb MinIntervall und LastValue=Value
                                $DoIt = 1;
                          }
                        }
                  }
                }
        }

        next if($DoIt == 0);

        $defs{$dev->{NAME}}{Helper}{DBLOG}{$reading}{$hash->{NAME}}{TIME}  = $now;
        $defs{$dev->{NAME}}{Helper}{DBLOG}{$reading}{$hash->{NAME}}{VALUE} = $value;

        DbLog_Push($hash, $DbLogType, $ts, $n, $t, $s, $reading, $value, $unit)

      }
    } 
  };
  
  return "";
}

################################################################
#
# zerlegt uebergebenes FHEM-Datum in die einzelnen Bestandteile
# und fuegt noch Defaultwerte ein
# uebergebenes SQL-Format: YYYY-MM-DD HH24:MI:SS
#
################################################################
sub DbLog_explode_datetime($%) {
  my ($t, %def) = @_;
  my %retv;

  my (@datetime, @date, @time);
  @datetime = split(" ", $t); #Datum und Zeit auftrennen
  @date = split("-", $datetime[0]);
  @time = split(":", $datetime[1]) if ($datetime[1]);
  if ($date[0]) {$retv{year}  = $date[0];} else {$retv{year}  = $def{year};}
  if ($date[1]) {$retv{month} = $date[1];} else {$retv{month} = $def{month};}
  if ($date[2]) {$retv{day}   = $date[2];} else {$retv{day}   = $def{day};}
  if ($time[0]) {$retv{hour}  = $time[0];} else {$retv{hour}  = $def{hour};}
  if ($time[1]) {$retv{minute}= $time[1];} else {$retv{minute}= $def{minute};}
  if ($time[2]) {$retv{second}= $time[2];} else {$retv{second}= $def{second};}

  $retv{datetime}=DbLog_implode_datetime($retv{year}, $retv{month}, $retv{day}, $retv{hour}, $retv{minute}, $retv{second});

  #Log 1, Dumper(%retv);
  return %retv
}

sub DbLog_implode_datetime($$$$$$) {
  my ($year, $month, $day, $hour, $minute, $second) = @_;
  my $retv = $year."-".$month."-".$day." ".$hour.":".$minute.":".$second;

  return $retv;
}

################################################################
#
# Verbindung zur DB aufbauen
#
################################################################
sub _DbLog_readCfg($){
  my ($hash)= @_;
  my $name = $hash->{NAME};

  my $configfilename= $hash->{CONFIGURATION};
  my %dbconfig; 
  my $ret;

# use generic fileRead to get configuration data
  my ($err, @config) = FileRead($configfilename);
  return $err if($err);

  eval join("\n", @config);

  $hash->{dbconn}     = $dbconfig{connection};
  $hash->{dbuser}     = $dbconfig{user};
  $attr{"sec$name"}{secret} = $dbconfig{password};

  #check the database model
  if($hash->{dbconn} =~ m/pg:/i) {
    $hash->{DBMODEL}="POSTGRESQL";
  } elsif ($hash->{dbconn} =~ m/mysql:/i) {
    $hash->{DBMODEL}="MYSQL";
  } elsif ($hash->{dbconn} =~ m/oracle:/i) {
    $hash->{DBMODEL}="ORACLE";
  } elsif ($hash->{dbconn} =~ m/sqlite:/i) {
    $hash->{DBMODEL}="SQLITE";
  } else {
    $hash->{DBMODEL}="unknown";
    Log3 $hash->{NAME}, 3, "Unknown dbmodel type in configuration file $configfilename.";
    Log3 $hash->{NAME}, 3, "Only Mysql, Postgresql, Oracle, SQLite are fully supported.";
    Log3 $hash->{NAME}, 3, "It may cause SQL-Erros during generating plots.";
  }
	return;
}

sub DbLog_Connect($)
{
  my ($hash)= @_;
  my $name = $hash->{NAME};
  my $dbconn     = $hash->{dbconn};
  my $dbuser     = $hash->{dbuser};
  my $dbpassword = $attr{"sec$name"}{secret};
  
  Log3 $hash->{NAME}, 3, "Connecting to database $dbconn with user $dbuser";
  my $dbh = DBI->connect_cached("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0 });
  if(!$dbh) {
    RemoveInternalTimer($hash);
    Log3 $hash->{NAME}, 4, 'DbLog: Trying to connect to database';
    InternalTimer(time+5, 'DbLog_Connect', $hash, 0);
    Log3 $hash->{NAME}, 4, 'Waiting for database connection';
    return 0;
  }

  Log3 $hash->{NAME}, 3, "Connection to db $dbconn established for pid $$";
  readingsSingleUpdate($hash, 'state', 'connected', 1);

  $hash->{DBH}= $dbh;
  
  if ($hash->{DBMODEL} eq "SQLITE") {
    $dbh->do("PRAGMA temp_store=MEMORY");
    $dbh->do("PRAGMA synchronous=NORMAL");
    $dbh->do("PRAGMA journal_mode=WAL");
    $dbh->do("PRAGMA cache_size=4000");
    $dbh->do("CREATE TEMP TABLE IF NOT EXISTS current (TIMESTAMP TIMESTAMP, DEVICE varchar(64), TYPE varchar(64), EVENT varchar(512), READING varchar(64), VALUE varchar(128), UNIT varchar(32))");
    $dbh->do("CREATE TABLE IF NOT EXISTS history (TIMESTAMP TIMESTAMP, DEVICE varchar(64), TYPE varchar(64), EVENT varchar(512), READING varchar(64), VALUE varchar(128), UNIT varchar(32))");
    $dbh->do("CREATE INDEX IF NOT EXISTS Search_Idx ON `history` (DEVICE, READING, TIMESTAMP)");
  }

  # no webfrontend connection for plotfork
  return 1 if( $hash->{PID} != $$ );
  
  # creating an own connection for the webfrontend, saved as DBHF in Hash
  # this makes sure that the connection doesnt get lost due to other modules
  my $dbhf = DBI->connect_cached("dbi:$dbconn", $dbuser, $dbpassword, { PrintError => 0 });
  if(!$dbh) {
    RemoveInternalTimer($hash);
    Log3 $hash->{NAME}, 4, 'DbLog: Trying to connect to database';
    InternalTimer(time+5, 'DbLog_Connect', $hash, 0);
    Log3 $hash->{NAME}, 4, 'Waiting for database connection';
    return 0;
  }

#  if(!$dbhf) {
#   Log3 $hash->{NAME}, 2, "Can't connect to $dbconn: $DBI::errstr";
#    return 0;
#  }
  Log3 $hash->{NAME}, 3, "Connection to db $dbconn established";
  $hash->{DBHF}= $dbhf;

  return 1;
}

################################################################
#
# Prozeduren zum Ausfuehren des SQLs
#
# param1: hash
# param2: pointer : DBFilehandle
# param3: string  : SQL
################################################################
sub DbLog_ExecSQL1($$$)
{
  my ($hash,$dbh,$sql)= @_;

  my $sth = $dbh->do($sql);
  if(!$sth) {
    Log3 $hash->{NAME}, 2, "DBLog error: " . $DBI::errstr;
    return 0;
  }
  return $sth;
}

sub DbLog_ExecSQL($$)
{
  my ($hash,$sql)= @_;
  Log3 $hash->{NAME}, 4, "Executing $sql";
  my $dbh= $hash->{DBH};
  my $sth = DbLog_ExecSQL1($hash,$dbh,$sql);
  if(!$sth) {
    #retry
    $dbh->disconnect();
    if(!DbLog_Connect($hash)) {
      Log3 $hash->{NAME}, 2, "DBLog reconnect failed.";
      return 0;
    }
    $dbh= $hash->{DBH};
    $sth = DbLog_ExecSQL1($hash,$dbh,$sql);
    if(!$sth) {
      Log3 $hash->{NAME}, 2, "DBLog retry failed.";
      return 0;
    }
    Log3 $hash->{NAME}, 2, "DBLog retry ok.";
  }
  return $sth;
}

################################################################
#
# GET Funktion
# wird zb. zur Generierung der Plots implizit aufgerufen
# infile : [-|current|history]
# outfile: [-|ALL|INT|WEBCHART]
#
################################################################
sub
DbLog_Get($@)
{
  my ($hash, @a) = @_;

  return dbReadings($hash,@a) if $a[1] =~ m/^Readings/;

  return "Usage: get $a[0] <in> <out> <from> <to> <column_spec>...\n".
     "  where column_spec is <device>:<reading>:<default>:<fn>\n" .
     "  see the #DbLog entries in the .gplot files\n" .
     "  <in> is not used, only for compatibility for FileLog, please use - \n" .
     "  <out> is a prefix, - means stdout\n"
    if(int(@a) < 5);
  shift @a;
  my $inf  = lc(shift @a);
  my $outf = lc(shift @a);
  my $from = shift @a;
  my $to   = shift @a; # Now @a contains the list of column_specs
  my ($internal, @fld);

  if($inf eq "-") {
    $inf = "history";
  }

  if($outf eq "int" && $inf eq "current") {
    $inf = "history";
    Log3 $hash->{NAME}, 3, "Defining DbLog SVG-Plots with :CURRENT is deprecated. Please define DbLog SVG-Plots with :HISTORY instead of :CURRENT. (define <mySVG> SVG <DbLogDev>:<gplotfile>:HISTORY)";
  }

  if($outf eq "int") {
    $outf = "-";
    $internal = 1;
  } elsif($outf eq "array"){

  } elsif(lc($outf) eq "webchart") {
    # redirect the get request to the chartQuery function
    return chartQuery($hash, @_);
  }

  my @readings = ();
  my (%sqlspec, %from_datetime, %to_datetime);

  #uebergebenen Timestamp anpassen
  #moegliche Formate: YYYY | YYYY-MM | YYYY-MM-DD | YYYY-MM-DD_HH24
  $from =~ s/_/\ /g;
  $to   =~ s/_/\ /g;
  %from_datetime = DbLog_explode_datetime($from, DbLog_explode_datetime("2000-01-01 00:00:00", ()));
  %to_datetime   = DbLog_explode_datetime($to, DbLog_explode_datetime("2099-01-01 00:00:00", ()));
  $from = $from_datetime{datetime};
  $to = $to_datetime{datetime};


  my ($retval,$retvaldummy,$hour,$sql_timestamp, $sql_device, $sql_reading, $sql_value, $type, $event, $unit) = "";
  my @ReturnArray;
  my $writeout = 0;
  my (@min, @max, @sum, @cnt, @lastv, @lastd, @mind, @maxd);
  my (%tstamp, %lasttstamp, $out_tstamp, $out_value, $minval, $maxval, $deltacalc); #fuer delta-h/d Berechnung

  #extract the Device:Reading arguments into @readings array
  for(my $i = 0; $i < int(@a); $i++) {
    @fld = split(":", $a[$i], 5);
    $readings[$i][0] = $fld[0]; # Device
    $readings[$i][1] = $fld[1]; # Reading
    $readings[$i][2] = $fld[2]; # Default
    $readings[$i][3] = $fld[3]; # function
    $readings[$i][4] = $fld[4]; # regexp

    $readings[$i][1] = "%" if(!$readings[$i][1] || length($readings[$i][1])==0); #falls Reading nicht gefuellt setze Joker
  }

  #create new connection for plotfork
  if( $hash->{PID} != $$ ) {
    $hash->{DBH}->disconnect();
    return "Can't connect to database." if(!DbLog_Connect($hash));
  }

  my $dbh= $hash->{DBH};

  #vorbereiten der DB-Abfrage, DB-Modell-abhaengig
  if ($hash->{DBMODEL} eq "POSTGRESQL") {
    $sqlspec{get_timestamp}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')";
    $sqlspec{from_timestamp} = "TO_TIMESTAMP('$from', 'YYYY-MM-DD HH24:MI:SS')";
    $sqlspec{to_timestamp}   = "TO_TIMESTAMP('$to', 'YYYY-MM-DD HH24:MI:SS')";
    #$sqlspec{reading_clause} = "(DEVICE || '|' || READING)";
    $sqlspec{order_by_hour}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24')";
    $sqlspec{max_value}      = "MAX(VALUE)";
    $sqlspec{day_before}     = "($sqlspec{from_timestamp} - INTERVAL '1 DAY')";
  } elsif ($hash->{DBMODEL} eq "ORACLE") {
    $sqlspec{get_timestamp}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')";
    $sqlspec{from_timestamp} = "TO_TIMESTAMP('$from', 'YYYY-MM-DD HH24:MI:SS')";
    $sqlspec{to_timestamp}   = "TO_TIMESTAMP('$to', 'YYYY-MM-DD HH24:MI:SS')";
    $sqlspec{order_by_hour}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24')";
    $sqlspec{max_value}      = "MAX(VALUE)";
    $sqlspec{day_before}     = "DATE_SUB($sqlspec{from_timestamp},INTERVAL 1 DAY)";
  } elsif ($hash->{DBMODEL} eq "MYSQL") {
    $sqlspec{get_timestamp}  = "DATE_FORMAT(TIMESTAMP, '%Y-%m-%d %H:%i:%s')";
    $sqlspec{from_timestamp} = "STR_TO_DATE('$from', '%Y-%m-%d %H:%i:%s')";
    $sqlspec{to_timestamp}   = "STR_TO_DATE('$to', '%Y-%m-%d %H:%i:%s')";
    $sqlspec{order_by_hour}  = "DATE_FORMAT(TIMESTAMP, '%Y-%m-%d %H')";
    $sqlspec{max_value}      = "MAX(CAST(VALUE AS DECIMAL(20,8)))";
    $sqlspec{day_before}     = "DATE_SUB($sqlspec{from_timestamp},INTERVAL 1 DAY)";
  } elsif ($hash->{DBMODEL} eq "SQLITE") {
    $sqlspec{get_timestamp}  = "TIMESTAMP";
    $sqlspec{from_timestamp} = "'$from'";
    $sqlspec{to_timestamp}   = "'$to'";
    $sqlspec{order_by_hour}  = "strftime('%Y-%m-%d %H', TIMESTAMP)";
    $sqlspec{max_value}      = "MAX(VALUE)";
    $sqlspec{day_before}     = "date($sqlspec{from_timestamp},'-1 day')";
  } else {
    $sqlspec{get_timestamp}  = "TIMESTAMP";
    $sqlspec{from_timestamp} = "'$from'";
    $sqlspec{to_timestamp}   = "'$to'";
    $sqlspec{order_by_hour}  = "strftime('%Y-%m-%d %H', TIMESTAMP)";
    $sqlspec{max_value}      = "MAX(VALUE)";
    $sqlspec{day_before}     = "date($sqlspec{from_timestamp},'-1 day')";
  }

  if($outf =~ m/(all|array)/) {
    $sqlspec{all}  = ",TYPE,EVENT,UNIT";
    $sqlspec{all_max}  = ",MAX(TYPE) AS TYPE,MAX(EVENT) AS EVENT,MAX(UNIT) AS UNIT";
  } else {
    $sqlspec{all}  = "";
    $sqlspec{all_max}  = "";
  }

  for(my $i=0; $i<int(@readings); $i++) {
    # ueber alle Readings
    # Variablen initialisieren
    $min[$i]   =  999999;
    $max[$i]   = -999999;
    $sum[$i]   = 0;
    $cnt[$i]   = 0;
    $lastv[$i] = 0;
    $lastd[$i] = "undef";
    $mind[$i]  = "undef";
    $maxd[$i]  = "undef";
    $minval    =  999999;
    $maxval    = -999999;
    $deltacalc = 0;

    if($readings[$i]->[3] && ($readings[$i]->[3] eq "delta-h" || $readings[$i]->[3] eq "delta-d")) {
      $deltacalc = 1;
    }

    my $stm;
    my $stm2;
    my $stmdelta;
    $stm =  "SELECT
                  MAX($sqlspec{get_timestamp}) AS TIMESTAMP,
                  MAX(DEVICE) AS DEVICE,
                  MAX(READING) AS READING,
                  $sqlspec{max_value}
                  $sqlspec{all_max} ";

    $stm .= "FROM current " if($inf eq "current");
    $stm .= "FROM history " if($inf eq "history");

    $stm .= "WHERE 1=1 ";
    
    $stm .= "AND DEVICE  = '".$readings[$i]->[0]."' "   if ($readings[$i]->[0] !~ m(\%));
    $stm .= "AND DEVICE LIKE '".$readings[$i]->[0]."' " if(($readings[$i]->[0] !~ m(^\%$)) && ($readings[$i]->[0] =~ m(\%)));

    $stm .= "AND READING = '".$readings[$i]->[1]."' "    if ($readings[$i]->[1] !~ m(\%));
    $stm .= "AND READING LIKE '".$readings[$i]->[1]."' " if(($readings[$i]->[1] !~ m(^%$)) && ($readings[$i]->[1] =~ m(\%)));

    $stmdelta = $stm;

    $stm .= "AND TIMESTAMP < $sqlspec{from_timestamp} ";
    $stm .= "AND TIMESTAMP > $sqlspec{day_before} ";

    $stm .= "UNION ALL ";

    $stm2 =  "SELECT
                  $sqlspec{get_timestamp},
                  DEVICE,
                  READING,
                  VALUE
                  $sqlspec{all} ";

    $stm2 .= "FROM current " if($inf eq "current");
    $stm2 .= "FROM history " if($inf eq "history");

    $stm2 .= "WHERE 1=1 ";

    $stm2 .= "AND DEVICE  = '".$readings[$i]->[0]."' "   if ($readings[$i]->[0] !~ m(\%));
    $stm2 .= "AND DEVICE LIKE '".$readings[$i]->[0]."' " if(($readings[$i]->[0] !~ m(^\%$)) && ($readings[$i]->[0] =~ m(\%)));

    $stm2 .= "AND READING = '".$readings[$i]->[1]."' "    if ($readings[$i]->[1] !~ m(\%));
    $stm2 .= "AND READING LIKE '".$readings[$i]->[1]."' " if(($readings[$i]->[1] !~ m(^%$)) && ($readings[$i]->[1] =~ m(\%)));

    $stm2 .= "AND TIMESTAMP >= $sqlspec{from_timestamp} ";
    $stm2 .= "AND TIMESTAMP < $sqlspec{to_timestamp} ";
    $stm2 .= "ORDER BY TIMESTAMP";

    if($deltacalc) {
      $stmdelta .= "AND TIMESTAMP >= $sqlspec{from_timestamp} ";
      $stmdelta .= "AND TIMESTAMP < $sqlspec{to_timestamp} ";

      $stmdelta .= "GROUP BY $sqlspec{order_by_hour} " if($deltacalc);
      $stmdelta .= "ORDER BY TIMESTAMP";
      $stm .= $stmdelta;
    } else {
      $stm = $stm2;
    }


    Log3 $hash->{NAME}, 4, "Processing Statement: $stm";

    my $sth= $dbh->prepare($stm) ||
      return "Cannot prepare statement $stm: $DBI::errstr";
    my $rc= $sth->execute() ||
      return "Cannot execute statement $stm: $DBI::errstr";

    if($outf =~ m/(all|array)/) {
      $sth->bind_columns(undef, \$sql_timestamp, \$sql_device, \$sql_reading, \$sql_value, \$type, \$event, \$unit);
    }
    else {
      $sth->bind_columns(undef, \$sql_timestamp, \$sql_device, \$sql_reading, \$sql_value);
    }

    if ($outf =~ m/(all)/) {
      $retval .= "Timestamp: Device, Type, Event, Reading, Value, Unit\n";
      $retval .= "=====================================================\n";
    }

    while($sth->fetch()) {

      if($sql_timestamp lt $from && $deltacalc) {
        if(Scalar::Util::looks_like_number($sql_value)){
          #nur setzen wenn nummerisch
          $minval = $sql_value if($sql_value < $minval);
          $maxval = $sql_value if($sql_value > $maxval);
          $lastv[$i] = $sql_value;
        }
      } else {

        $writeout   = 0;
        $out_value  = "";
        $out_tstamp = "";
        $retvaldummy = "";

        ############ Auswerten des 5. Parameters: Regexp ###################
        # die Regexep wird vor der Function ausgewertet und der Wert im Feld
        # Value angepasst.
        ####################################################################
        if($readings[$i]->[4] && $readings[$i]->[4]) {
          #evaluate
          my $val = $sql_value;
          my $ts  = $sql_timestamp;
          eval("$readings[$i]->[4]");
          $sql_value = $val;
          $sql_timestamp = $ts;
          if($@) {Log3 $hash->{NAME}, 3, "DbLog: Error in inline function: <".$readings[$i]->[4].">, Error: $@";}
          $out_tstamp = $sql_timestamp;
          $writeout=1;
        }

        ############ Auswerten des 4. Parameters: function ###################
        if($readings[$i]->[3] && $readings[$i]->[3] eq "int") {
          #nur den integerwert uebernehmen falls zb value=15°C
          $out_value = $1 if($sql_value =~ m/^(\d+).*/o);
          $out_tstamp = $sql_timestamp;
          $writeout=1;

        } elsif ($readings[$i]->[3] && $readings[$i]->[3] =~ m/^int(\d+).*/o) {
          #Uebernehme den Dezimalwert mit den angegebenen Stellen an Nachkommastellen
          $out_value = $1 if($sql_value =~ m/^([-\.\d]+).*/o);
          $out_tstamp = $sql_timestamp;
          $writeout=1;

        } elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-ts" && lc($sql_value) !~ m(ignore)) {
          #Berechung der vergangen Sekunden seit dem letten Logeintrag
          #zb. die Zeit zwischen on/off
          my @a = split("[- :]", $sql_timestamp);
          my $akt_ts = mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);
          if($lastd[$i] ne "undef") {
            @a = split("[- :]", $lastd[$i]);
          }
          my $last_ts = mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);
          $out_tstamp = $sql_timestamp;
          $out_value = sprintf("%02d", $akt_ts - $last_ts);
          if(lc($sql_value) =~ m(hide)){$writeout=0;} else {$writeout=1;}

        } elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-h") {
          #Berechnung eines Stundenwertes
          %tstamp = DbLog_explode_datetime($sql_timestamp, ());
          if($lastd[$i] eq "undef") {
            %lasttstamp = DbLog_explode_datetime($sql_timestamp, ());
            $lasttstamp{hour} = "00";
          } else {
            %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
          }
          #    04                   01
          #    06                   23
          if("$tstamp{hour}" ne "$lasttstamp{hour}") {
            # Aenderung der stunde, Berechne Delta
            #wenn die Stundendifferenz größer 1 ist muss ein Dummyeintrag erstellt werden
            $retvaldummy = "";
            if(($tstamp{hour}-$lasttstamp{hour}) > 1) {
              for (my $j=$lasttstamp{hour}+1; $j < $tstamp{hour}; $j++) {
                $out_value  = "0";
                $hour = $j;
                $hour = '0'.$j if $j<10;
                $cnt[$i]++;
                $out_tstamp = DbLog_implode_datetime($tstamp{year}, $tstamp{month}, $tstamp{day}, $hour, "30", "00");
                if ($outf =~ m/(all)/) {
                  # Timestamp: Device, Type, Event, Reading, Value, Unit
                  $retvaldummy .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
              
                } elsif ($outf =~ m/(array)/) {
                  push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
              
                } else {
                  $out_tstamp =~ s/\ /_/g; #needed by generating plots
                  $retvaldummy .= "$out_tstamp $out_value\n";
                }
              }
            }
            if(($tstamp{hour}-$lasttstamp{hour}) < 0) {
              for (my $j=0; $j < $tstamp{hour}; $j++) {
                $out_value  = "0";
                $hour = $j;
                $hour = '0'.$j if $j<10;
                $cnt[$i]++;
                $out_tstamp = DbLog_implode_datetime($tstamp{year}, $tstamp{month}, $tstamp{day}, $hour, "30", "00");
                if ($outf =~ m/(all)/) {
                  # Timestamp: Device, Type, Event, Reading, Value, Unit
                  $retvaldummy .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
              
                } elsif ($outf =~ m/(array)/) {
                  push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
              
                } else {
                  $out_tstamp =~ s/\ /_/g; #needed by generating plots
                  $retvaldummy .= "$out_tstamp $out_value\n";
                }
              }
            }
            $out_value = sprintf("%g", $maxval - $minval);
            $sum[$i] += $out_value;
            $cnt[$i]++;
            $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, $lasttstamp{hour}, "30", "00");
            #$minval =  999999;
            $minval = $maxval;
#            $maxval = -999999;
            $writeout=1;
          }
        } elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-d") {
          #Berechnung eines Tageswertes
          %tstamp = DbLog_explode_datetime($sql_timestamp, ());
          if($lastd[$i] eq "undef") {
            %lasttstamp = DbLog_explode_datetime($sql_timestamp, ());
          } else {
            %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
          }
          if("$tstamp{day}" ne "$lasttstamp{day}") {
            # Aenderung des Tages, Berechne Delta
            $out_value = sprintf("%g", $maxval - $minval);
            $sum[$i] += $out_value;
            $cnt[$i]++;
            $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, "12", "00", "00");
#            $minval =  999999;
            $minval = $maxval;
#            $maxval = -999999;
            $writeout=1;
          }
        } else {
          $out_value = $sql_value;
          $out_tstamp = $sql_timestamp;
          $writeout=1;
        }

        # Wenn Attr SuppressUndef gesetzt ist, dann ausfiltern aller undef-Werte
        $writeout = 0 if (!defined($sql_value) && AttrVal($hash->{NAME}, "suppressUndef", 0));
 
        ###################### Ausgabe ###########################
        if($writeout) {
            if ($outf =~ m/(all)/) {
              # Timestamp: Device, Type, Event, Reading, Value, Unit
              $retval .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
              $retval .= $retvaldummy;
            
            } elsif ($outf =~ m/(array)/) {
              push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
              
            } else {
              $out_tstamp =~ s/\ /_/g; #needed by generating plots
              $retval .= "$out_tstamp $out_value\n";
              $retval .= $retvaldummy;
            }
        }

        if(Scalar::Util::looks_like_number($sql_value)){
          #nur setzen wenn nummerisch
          if($sql_value < $min[$i]) {
            $min[$i] = $sql_value;
            $mind[$i] = $sql_timestamp;
          }
          if($sql_value > $max[$i]) {
            $max[$i] = $sql_value;
            $maxd[$i] = $sql_timestamp;
          }
          if($deltacalc) {
            $maxval = $sql_value;
          } else {
            $sum[$i] += $sql_value;
            $minval = $sql_value if($sql_value < $minval);
            $maxval = $sql_value if($sql_value > $maxval);
          }
        } else {
          $min[$i] = 0;
          $max[$i] = 0;
          $sum[$i] = 0;
          $minval  = 0;
          $maxval  = 0;
        }
        if(!$deltacalc) {
          $cnt[$i]++;
        }
        $lastv[$i] = $sql_value;
        $lastd[$i] = $sql_timestamp;
      }
    } #while fetchrow

    ######## den letzten Abschlusssatz rausschreiben ##########
    if($readings[$i]->[3] && ($readings[$i]->[3] eq "delta-h" || $readings[$i]->[3] eq "delta-d")) {
      if($lastd[$i] eq "undef") {
        $out_value  = "0";
        $out_tstamp = DbLog_implode_datetime($from_datetime{year}, $from_datetime{month}, $from_datetime{day}, $from_datetime{hour}, "30", "00") if($readings[$i]->[3] eq "delta-h");
        $out_tstamp = DbLog_implode_datetime($from_datetime{year}, $from_datetime{month}, $from_datetime{day}, "12", "00", "00") if($readings[$i]->[3] eq "delta-d");
      } else {
        %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
        $out_value = sprintf("%g", $maxval - $minval);
        $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, $lasttstamp{hour}, "30", "00") if($readings[$i]->[3] eq "delta-h");
        $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, "12", "00", "00") if($readings[$i]->[3] eq "delta-d");
      }  
      $sum[$i] += $out_value;
      $cnt[$i]++;
      if($outf =~ m/(all)/) {
        $retval .= sprintf("%s: %s %s %s %s %s %s\n", $out_tstamp, $sql_device, $type, $event, $sql_reading, $out_value, $unit);
      
      } elsif ($outf =~ m/(array)/) {
        push(@ReturnArray, {"tstamp" => $out_tstamp, "device" => $sql_device, "type" => $type, "event" => $event, "reading" => $sql_reading, "value" => $out_value, "unit" => $unit});
          
      } else {
        $out_tstamp =~ s/\ /_/g; #needed by generating plots
        $retval .= "$out_tstamp $out_value\n";
      }
    }
    # DatenTrenner setzen
    $retval .= "#$readings[$i]->[0]";
    $retval .= ":";
    $retval .= "$readings[$i]->[1]" if($readings[$i]->[1]);
    $retval .= ":";
    $retval .= "$readings[$i]->[2]" if($readings[$i]->[2]);
    $retval .= ":";
    $retval .= "$readings[$i]->[3]" if($readings[$i]->[3]);
    $retval .= ":";
    $retval .= "$readings[$i]->[4]" if($readings[$i]->[4]);
    $retval .= "\n";
  } #for @readings

  #Ueberfuehren der gesammelten Werte in die globale Variable %data
  for(my $j=0; $j<int(@readings); $j++) {
    my $k = $j+1;
    $data{"min$k"} = $min[$j] == 999999 ? "undef" : $min[$j];
    $data{"max$k"} = $max[$j] == -999999 ? "undef" : $max[$j];
    $data{"avg$k"} = $cnt[$j] ? sprintf("%0.2f", $sum[$j]/$cnt[$j]) : "undef";
    $data{"sum$k"} = $sum[$j];
    $data{"cnt$k"} = $cnt[$j] ? $cnt[$j] : "undef";
    $data{"currval$k"} = $lastv[$j];
    $data{"currdate$k"} = $lastd[$j];
    $data{"mindate$k"} = $mind[$j];
    $data{"maxdate$k"} = $maxd[$j];
  }

  #cleanup plotfork connection
  $dbh->disconnect() if( $hash->{PID} != $$ );

  if($internal) {
    $internal_data = \$retval;
    return undef;

  } elsif($outf =~ m/(array)/) {
    return @ReturnArray;
  
  } else {
    return $retval;
  }
}

sub DbLog_Set($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $usage = "Unknown argument, choose one of reopen:noArg rereadcfg:noArg count:noArg deleteOldDays userCommand";
	return $usage if(int(@a) < 2);
	my $dbh = $hash->{DBH};
	my $ret;

	given ($a[1]) {

		when ('reopen') {
			Log3($name, 4, "DbLog $name: Reopen requested.");
			$dbh->commit() if(! $dbh->{AutoCommit});
			$dbh->disconnect();
			DbLog_Connect($hash);
			$ret = "Reopen executed.";
		}

		when ('rereadcfg') {
			Log3($name, 4, "DbLog $name: Rereadcfg requested.");
			$dbh->commit() if(! $dbh->{AutoCommit});
			$dbh->disconnect();
			$ret = _DbLog_readCfg($hash);
			return $ret if $ret;
			DbLog_Connect($hash);
			$ret = "Rereadcfg executed.";
		}

		when ('count') {
			Log3($name, 4, "DbLog $name: Records count requested.");
			my $c = $dbh->selectrow_array('SELECT count(*) FROM history');
			readingsSingleUpdate($hash, 'countHistory', $c ,1);
			$c = $dbh->selectrow_array('SELECT count(*) FROM current');
			readingsSingleUpdate($hash, 'countCurrent', $c ,1);
		}

		when ('deleteOldDays') {
			Log3($name, 4, "DbLog $name: Deletion of old records requested.");
			my ($c, $cmd);
			my $dbModel = InternalVal($name, 'DBMODEL', 'unknown');
			$cmd = "delete from history where TIMESTAMP < ";
			given ($dbModel) {
				when ('SQLITE')			{ $cmd .= "datetime('now', '-$a[2] days')"; }
				when ('MYSQL')			{ $cmd .= "DATE_SUB(CURDATE(),INTERVAL $a[2] DAY)"; }
				when ('POSTGRESQL')	{ $cmd .= "NOW() - INTERVAL '$a[2] DAY"; }
				default {
					$cmd = undef;
					$ret = 'Unkwon database type. Maybe you can try userCommand anyway.';
				}
			}

			if(defined($cmd)) {
				$c = $dbh->do($cmd);
				readingsSingleUpdate($hash, 'lastRowsDeleted', $c ,1);
			}
		}

		when ('userCommand') {
			Log3($name, 4, "DbLog $name: userCommand execution requested.");
			my ($c, @cmd, $sql);
			@cmd = @a;
			shift(@cmd); shift(@cmd);
			$sql = join(" ",@cmd);
			readingsSingleUpdate($hash, 'userCommand', $sql, 1);
			$c = $dbh->selectrow_array($sql);
			readingsSingleUpdate($hash, 'userCommandResult', $c ,1);
		}

		default { $ret = $usage; }

	}

	return $ret;

}

################################################################
#
# Charting Specific functions start here
#
################################################################

################################################################
#
# Error handling, returns a JSON String
#
################################################################
sub jsonError($) {
  my $errormsg = $_[0]; 
  my $json = '{"success": "false", "msg":"'.$errormsg.'"}';
  return $json;
}


################################################################
#
# Prepare the SQL String
#
################################################################
sub prepareSql(@) {

    my ($hash, @a) = @_;
    my $starttime = $_[5];
    $starttime =~ s/_/ /;
    my $endtime   = $_[6];
    $endtime =~ s/_/ /;
    my $device = $_[7];
    my $userquery = $_[8];
    my $xaxis = $_[9]; 
    my $yaxis = $_[10]; 
    my $savename = $_[11]; 
    my $jsonChartConfig = $_[12];
    my $pagingstart = $_[13]; 
    my $paginglimit = $_[14]; 
    my $dbmodel = $hash->{DBMODEL};
    my ($sql, $jsonstring, $countsql, $hourstats, $daystats, $weekstats, $monthstats, $yearstats);

    if ($dbmodel eq "POSTGRESQL") {
        ### POSTGRESQL Queries for Statistics ###
        ### hour:
        $hourstats = "SELECT to_char(timestamp, 'YYYY-MM-DD HH24:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $hourstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $hourstats .= "COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $hourstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### day:
        $daystats = "SELECT to_char(timestamp, 'YYYY-MM-DD 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $daystats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $daystats .= "COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $daystats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### week:
        $weekstats = "SELECT date_trunc('week',timestamp) AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $weekstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $weekstats .= "COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $weekstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### month:
        $monthstats = "SELECT to_char(timestamp, 'YYYY-MM-01 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $monthstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $monthstats .= "COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $monthstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### year:
        $yearstats = "SELECT to_char(timestamp, 'YYYY-01-01 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $yearstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $yearstats .= "COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $yearstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";
   
    } elsif ($dbmodel eq "MYSQL") {
        ### MYSQL Queries for Statistics ###
        ### hour:
        $hourstats = "SELECT date_format(timestamp, '%Y-%m-%d %H:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $hourstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $hourstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' ";
        $hourstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### day:
        $daystats = "SELECT date_format(timestamp, '%Y-%m-%d 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $daystats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $daystats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' ";
        $daystats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### week:
        $weekstats = "SELECT date_format(timestamp, '%Y-%m-%d 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $weekstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $weekstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' ";
        $weekstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' ";
        $weekstats .= "GROUP BY date_format(timestamp, '%Y-%u 00:00:00') ORDER BY 1;";

        ### month:
        $monthstats = "SELECT date_format(timestamp, '%Y-%m-01 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $monthstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $monthstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' ";
        $monthstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### year:
        $yearstats = "SELECT date_format(timestamp, '%Y-01-01 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $yearstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $yearstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' ";
        $yearstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

    } elsif ($hash->{DBMODEL} eq "SQLITE") {
        ### SQLITE Queries for Statistics ###
        ### hour:
        $hourstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $hourstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $hourstats .= "FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $hourstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m-%d %H:00:00', TIMESTAMP);";
  
        ### day:
        $daystats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $daystats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $daystats .= "FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $daystats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m-%d 00:00:00', TIMESTAMP);";

        ### week:
        $weekstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $weekstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $weekstats .= "FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $weekstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%W 00:00:00', TIMESTAMP);";

        ### month:
        $monthstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $monthstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $monthstats .= "FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $monthstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m 00:00:00', TIMESTAMP);";

        ### year:
        $yearstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $yearstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $yearstats .= "FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $yearstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y 00:00:00', TIMESTAMP);";

    } else {
        $sql = "errordb";
    }

    if($userquery eq "getreadings") {
        $sql = "SELECT distinct(reading) FROM history WHERE device = '".$device."'";
    } elsif($userquery eq "getdevices") {
        $sql = "SELECT distinct(device) FROM history";
    } elsif($userquery eq "timerange") {
        $sql = "SELECT ".$xaxis.", VALUE FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' ORDER BY TIMESTAMP;";
    } elsif($userquery eq "hourstats") {
        $sql = $hourstats;
    } elsif($userquery eq "daystats") {
        $sql = $daystats;
    } elsif($userquery eq "weekstats") {
        $sql = $weekstats;
    } elsif($userquery eq "monthstats") {
        $sql = $monthstats;
    } elsif($userquery eq "yearstats") {
        $sql = $yearstats;
    } elsif($userquery eq "savechart") {
        $sql = "INSERT INTO frontend (TYPE, NAME, VALUE) VALUES ('savedchart', '$savename', '$jsonChartConfig')";
    } elsif($userquery eq "renamechart") {
        $sql = "UPDATE frontend SET NAME = '$savename' WHERE ID = '$jsonChartConfig'";
    } elsif($userquery eq "deletechart") {
        $sql = "DELETE FROM frontend WHERE TYPE = 'savedchart' AND ID = '".$savename."'";
    } elsif($userquery eq "updatechart") {
        $sql = "UPDATE frontend SET VALUE = '$jsonChartConfig' WHERE ID = '".$savename."'";
    } elsif($userquery eq "getcharts") {
        $sql = "SELECT * FROM frontend WHERE TYPE = 'savedchart'";
    } elsif($userquery eq "getTableData") {
        if ($device ne '""' && $yaxis ne '""') {
            $sql = "SELECT * FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
            $sql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql .= " LIMIT '$paginglimit' OFFSET '$pagingstart'"; 
            $countsql = "SELECT count(*) FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' "; 
            $countsql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'"; 
        } elsif($device ne '""' && $yaxis eq '""') {  
            $sql = "SELECT * FROM history WHERE DEVICE = '$device' ";
            $sql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql .= " LIMIT '$paginglimit' OFFSET '$pagingstart'";
            $countsql = "SELECT count(*) FROM history WHERE DEVICE = '$device' ";
            $countsql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
        } else {
            $sql = "SELECT * FROM history";
            $sql .= " WHERE TIMESTAMP Between '$starttime' AND '$endtime'"; 
            $sql .= " LIMIT '$paginglimit' OFFSET '$pagingstart'";
            $countsql = "SELECT count(*) FROM history"; 
            $countsql .= " WHERE TIMESTAMP Between '$starttime' AND '$endtime'"; 
        }
        return ($sql, $countsql);
    } else {
        $sql = "error";
    }

    return $sql;
}

################################################################
#
# Do the query
#
################################################################
sub chartQuery($@) {

    my ($sql, $countsql) = prepareSql(@_);

    if ($sql eq "error") {
       return jsonError("Could not setup SQL String. Maybe the Database is busy, please try again!");
    } elsif ($sql eq "errordb") {
       return jsonError("The Database Type is not supported!");
    }

    my ($hash, @a) = @_;
    my $dbhf= $hash->{DBHF};

    my $totalcount;
    
    if (defined $countsql && $countsql ne "") {
        my $query_handle = $dbhf->prepare($countsql) 
        or return jsonError("Could not prepare statement: " . $dbhf->errstr . ", SQL was: " .$countsql);
        
        $query_handle->execute() 
        or return jsonError("Could not execute statement: " . $query_handle->errstr);

        my @data = $query_handle->fetchrow_array();
        $totalcount = join(", ", @data);
        
    }

    # prepare the query
    my $query_handle = $dbhf->prepare($sql) 
        or return jsonError("Could not prepare statement: " . $dbhf->errstr . ", SQL was: " .$sql);
    
    # execute the query
    $query_handle->execute() 
        or return jsonError("Could not execute statement: " . $query_handle->errstr);
    
    my $columns = $query_handle->{'NAME'};
    my $columncnt;

    # When columns are empty but execution was successful, we have done a successful INSERT, UPDATE or DELETE
    if($columns) {
        $columncnt = scalar @$columns;
    } else {
        return '{"success": "true", "msg":"All ok"}';
    }

    my $i = 0;
    my $jsonstring = '{"data":[';

    while ( my @data = $query_handle->fetchrow_array()) {

        if($i == 0) {
            $jsonstring .= '{';
        } else {
            $jsonstring .= ',{';
        } 
 
        for ($i = 0; $i < $columncnt; $i++) {
            $jsonstring .= '"';
            $jsonstring .= uc($query_handle->{NAME}->[$i]); 
            $jsonstring .= '":';

            if (defined $data[$i]) {
                my $fragment =  substr($data[$i],0,1);
                if ($fragment eq "{") {
                    $jsonstring .= $data[$i];
                } else {
                    $jsonstring .= '"'.$data[$i].'"';
                }
            } else {
                $jsonstring .= '""'
            }
            
            if($i != ($columncnt -1)) {
               $jsonstring .= ','; 
            }
        }
        $jsonstring .= '}'; 
    }
    $jsonstring .= ']';
    if (defined $totalcount && $totalcount ne "") {
        $jsonstring .= ',"totalCount": '.$totalcount.'}';
    } else {
        $jsonstring .= '}';
    }
    return $jsonstring;
}

#########################
sub
DbLog_fhemwebFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

   my $ret;
   my $newIdx=1;
   while($defs{"SVG_${d}_$newIdx"}) {
     $newIdx++;
   }
   my $name = "SVG_${d}_$newIdx";
   $ret .= FW_pH("cmd=define $name SVG $d:templateDB:HISTORY;".
                  "set $name copyGplotFile&detail=$name",
                  "<div class=\"dval\">Create SVG plot from DbLog</div>", 0, "dval", 1);
 
   return $ret;

}

sub
DbLog_sampleDataFn($$$$$)
{
  my ($dlName, $dlog, $max, $conf, $wName) = @_;
  my $desc = "Device:Reading";
  my @htmlArr;
  my @example;
  my @colregs;
  my $counter;

  my $currentPresent = AttrVal($dlName,'DbLogType','Current');
  if($currentPresent =~ m/Current/) {
  # Table Current present, use it for sample data

    my $dbhf = $defs{$dlName}{DBHF};
    my $query = "select device,reading,value from current where device <> '' group by device,reading order by device,reading";
    my $sth = $dbhf->prepare( $query );  
    $sth->execute();
    while (my @line = $sth->fetchrow_array()) {
      $counter++;
      push (@example, join (" ",@line)) if($counter <= 8); # show max 8 examples
      push (@colregs, "$line[0]:$line[1]"); # push all eventTypes to selection list
    }
    my $cols = join(",", sort @colregs);

    $max = 8 if($max > 8);
    for(my $r=0; $r < $max; $r++) {
      my @f = split(":", ($dlog->[$r] ? $dlog->[$r] : ":::"), 4);
      my $ret = "";
      $ret .= SVG_sel("par_${r}_0", $cols, "$f[0]:$f[1]");
#      $ret .= SVG_txt("par_${r}_2", "", $f[2], 1); # Default not yet implemented
#      $ret .= SVG_txt("par_${r}_3", "", $f[3], 3); # Function
#      $ret .= SVG_txt("par_${r}_4", "", $f[4], 3); # RegExp
      push @htmlArr, $ret;
    }

  } else {
  # Table Current not present, so create an empty input field
    push @example, "No sample data due to missing table 'Current'";

    $max = 8 if($max > 8);
    for(my $r=0; $r < $max; $r++) {
      my @f = split(":", ($dlog->[$r] ? $dlog->[$r] : ":::"), 4);
      my $ret = "";
      $ret .= SVG_txt("par_${r}_0", "", "$f[0]:$f[1]:$f[2]:$f[3]:$f[4]", 20);
#      $ret .= SVG_txt("par_${r}_2", "", $f[2], 1); # Default not yet implemented
#      $ret .= SVG_txt("par_${r}_3", "", $f[3], 3); # Function
#      $ret .= SVG_txt("par_${r}_4", "", $f[4], 3); # RegExp
      push @htmlArr, $ret;
    }

  }

  return ($desc, \@htmlArr, join("<br>", @example));
}

#
# get <dbLog> ReadingsVal       <device> <reading> <default>
# get <dbLog> ReadingsTimestamp <device> <reading> <default>
#
sub dbReadings($@) {
  my($hash,@a) = @_;
  my $dbhf= $hash->{DBHF};
  return 'Wrong Syntax for ReadingsVal!' unless defined($a[4]);
  my $DbLogType = AttrVal($a[0],'DbLogType','current');
  my $query;
  if (lc($DbLogType) =~ m(current) ) {
    $query = "select VALUE,TIMESTAMP from current where DEVICE= '$a[2]' and READING= '$a[3]'";
  } else {
    $query = "select VALUE,TIMESTAMP from history where DEVICE= '$a[2]' and READING= '$a[3]' order by TIMESTAMP desc limit 1";
  }
  my ($reading,$timestamp) = $dbhf->selectrow_array($query);
  $reading = (defined($reading)) ? $reading : $a[4];
  $timestamp = (defined($timestamp)) ? $timestamp : $a[4];
  return $reading   if $a[1] eq 'ReadingsVal';
  return $timestamp if $a[1] eq 'ReadingsTimestamp';
  return "Syntax error: $a[1]";
}

1;

=pod
=begin html

<a name="DbLog"></a>
<h3>DbLog</h3>
<ul>
  <br>

  <a name="DbLogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; DbLog &lt;configfilename&gt; &lt;regexp&gt;</code>
    <br><br>

    Log events to a database. The database connection is defined in
    <code>&lt;configfilename&gt;</code> (see sample configuration file
    <code>contrib/dblog/db.conf</code>). The configuration is stored in a separate file
    to avoid storing the password in the main configuration file and to have it
    visible in the output of the <a href="../docs/commandref.html#list">list</a> command.
    <br><br>

    The modules <code>DBI</code> and <code>DBD::&lt;dbtype&gt;</code>
    need to be installed (use <code>cpan -i &lt;module&gt;</code>
    if your distribution does not have it).
    <br><br>

    <code>&lt;regexp&gt;</code> is the same as in <a href="../docs/commandref.html#FileLog">FileLog</a>.
    <br><br>
    Sample code to create a MySQL/PostgreSQL database is in
    <code>&lt;DBType&gt;_create.sql</code>.
    The database contains two tables: <code>current</code> and
    <code>history</code>. The latter contains all events whereas the former only
    contains the last event for any given reading and device.
    The columns have the following meaning:
    <ol>
      <li>TIMESTAMP: timestamp of event, e.g. <code>2007-12-30 21:45:22</code></li>
      <li>DEVICE: device name, e.g. <code>Wetterstation</code></li>
      <li>TYPE: device type, e.g. <code>KS300</code></li>
      <li>EVENT: event specification as full string,
                                          e.g. <code>humidity: 71 (%)</code></li>
      <li>READING: name of reading extracted from event,
                      e.g. <code>humidity</code></li>

      <li>VALUE: actual reading extracted from event,
                      e.g. <code>71</code></li>
      <li>UNIT: unit extracted from event, e.g. <code>%</code></li>
    </ol>
    The content of VALUE is optimized for automated post-processing, e.g.
    <code>yes</code> is translated to <code>1</code>
    <br><br>
    The current values can be retrieved by the following code like FileLog:<br>
    <ul>
      <code>get myDbLog - - 2012-11-10 2012-11-10 KS300:temperature::</code>
    </ul>
    <br><br>
    <b>Examples:</b>
    <ul>
        <code># log everything to database</code><br>

        <code>define myDbLog DbLog /etc/fhem/db.conf .*:.*</code>
    </ul>
  </ul>
  <br/><br/>

  <a name="DbLogset"></a>
  <b>Set</b> 
  <ul>
    <code>set &lt;name&gt; reopen </code><br/><br/>
      <ul>Perform a database disconnect and immediate reconnect to clear cache and flush journal file.</ul><br/>

    <code>set &lt;name&gt; rereadcfg </code><br/><br/>
      <ul>Perform a database disconnect and immediate reconnect to clear cache and flush journal file.<br/>
      Probably same behavior als reopen, but rereadcfg will read the configuration data before reconnect.</ul><br/>

    <code>set &lt;name&gt; count </code><br/><br/>
      <ul>Count records in tables current and history and write results into readings countCurrent and countHistory.</ul><br/>

    <code>set &lt;name&gt; deleteOldDays &lt;n&gt;</code><br/><br/>
      <ul>Delete records from history older than &lt;n&gt; days. Number of deleted record will be written into reading lastRowsDeleted.</ul><br/>

    <code>set &lt;name&gt; userCommand &lt;validSqlStatement&gt;</code><br/><br/>
      <ul><b>DO NOT USE THIS COMMAND UNLESS YOU REALLY (REALLY!) KNOW WHAT YOU ARE DOING!!!</b><br/><br/>
          Perform any (!!!) sql statement on connected database. Useercommand and result will be written into corresponding readings.<br/>
      </ul><br/>

  </ul><br>

  <a name="DbLogget"></a>
  <b>Get</b>
  <ul>
  <code>get &lt;name&gt; ReadingsVal&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; &lt;device&gt; &lt;reading&gt; &lt;default&gt;</code><br/>
  <code>get &lt;name&gt; ReadingsTimestamp &lt;device&gt; &lt;reading&gt; &lt;default&gt;</code><br/>
  <br/>
  Retrieve one single value, use and syntax are similar to ReadingsVal() and ReadingsTimestamp() functions.<br/>
  </ul>
  <br/>
  <br/>
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;column_spec&gt; </code>
    <br><br>
    Read data from the Database, used by frontends to plot data without direct
    access to the Database.<br>

    <ul>
      <li>&lt;in&gt;<br>
        A dummy parameter for FileLog compatibility. Sessing by defaultto <code>-</code><br>
        <ul>
          <li>current: reading actual readings from table "current"</li>
          <li>history: reading history readings from table "history"</li>
          <li>-: identical to "history"</li>
        </ul> 
      </li>
      <li>&lt;out&gt;<br>
        A dummy parameter for FileLog compatibility. Setting by default to <code>-</code>
        to check the output for plot-computing.<br>
        Set it to the special keyword
        <code>all</code> to get all columns from Database.
        <ul>
          <li>ALL: get all colums from table, including a header</li>
          <li>Array: get the columns as array of hashes</li>
          <li>INT: internally used by generating plots</li>
          <li>-: default</li>
        </ul>
      </li>
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Used to select the data. Please use the following timeformat or
        an initial substring of it:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <li>&lt;column_spec&gt;<br>
        For each column_spec return a set of data separated by
        a comment line on the current connection.<br>
        Syntax: &lt;device&gt;:&lt;reading&gt;:&lt;default&gt;:&lt;fn&gt;:&lt;regexp&gt;<br>
        <ul>
          <li>&lt;device&gt;<br>
            The name of the device. Case sensitive. Using a the joker "%" is supported.</li>
          <li>&lt;reading&gt;<br>
            The reading of the given device to select. Case sensitive. Using a the joker "%" is supported.
            </li>
          <li>&lt;default&gt;<br>
            no implemented yet
            </li>
          <li>&lt;fn&gt;
            One of the following:
            <ul>
              <li>int<br>
                Extract the integer at the beginning of the string. Used e.g.
                for constructs like 10%</li>
              <li>int&lt;digit&gt;<br>
                Extract the decimal digits including negative character and
                decimal point at the beginning og the string. Used e.g.
                for constructs like 15.7&deg;C</li>
              <li>delta-h / delta-d<br>
                Return the delta of the values for a given hour or a given day.
                Used if the column contains a counter, as is the case for the
                KS300 rain column.</li>
              <li>delta-ts<br>
                Replaced the original value with a measured value of seconds since
                the last and the actual logentry.
              </li>
            </ul></li>
            <li>&lt;regexp&gt;<br>
              The string is evaluated as a perl expression.  The regexp is executed
              before &lt;fn&gt; parameter.<br>
              Note: The string/perl expression cannot contain spaces,
              as the part after the space will be considered as the
              next column_spec.<br>
              <b>Keywords</b>
              <li>$val is the current value returned from the Database.</li>
              <li>$ts is the current timestamp returned from the Database.</li>
              <li>This Logentry will not print out if $val contains th keyword "hide".</li>
              <li>This Logentry will not print out and not used in the following processing
                  if $val contains th keyword "ignore".</li>
            </li>
        </ul></li>
      </ul>
    <br><br>
    Examples:
      <ul>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature</code></li>
        <li><code>get myDbLog current ALL - - %:temperature</code></li><br>
            you will get all actual readings "temperature" from all logged devices. 
            Be carful by using "history" as inputfile because a long execution time will be expected!
        <li><code>get myDbLog - - 2012-11-10_10 2012-11-10_20 KS300:temperature::int1</code><br>
           like from 10am until 08pm at 10.11.2012</li>
        <li><code>get myDbLog - all 2012-11-10 2012-11-20 KS300:temperature</code></li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature KS300:rain::delta-h KS300:rain::delta-d</code></li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 MyFS20:data:::$val=~s/(on|off).*/$1eq"on"?1:0/eg</code><br>
           return 1 for all occurance of on* (on|on-for-timer etc) and 0 for all off*</li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 Bodenfeuchte:data:::$val=~s/.*B:\s([-\.\d]+).*/$1/eg</code><br>
           Example of OWAD: value like this: <code>"A: 49.527 % B: 66.647 % C: 9.797 % D: 0.097 V"</code><br>
           and output for port B is like this: <code>2012-11-20_10:23:54 66.647</code></li>
        <li><code>get DbLog - - 2013-05-26 2013-05-28 Pumpe:data::delta-ts:$val=~s/on/hide/</code><br>
           Setting up a "Counter of Uptime". The function delta-ts gets the seconds between the last and the
           actual logentry. The keyword "hide" will hide the logentry of "on" because this time 
           is a "counter of Downtime"</li>

      </ul>
    <br><br>
  </ul>

  <b>Get</b> when used for webcharts
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;device&gt; &lt;querytype&gt; &lt;xaxis&gt; &lt;yaxis&gt; &lt;savename&gt; </code>
    <br><br>
    Query the Database to retrieve JSON-Formatted Data, which is used by the charting frontend.
    <br>

    <ul>
      <li>&lt;name&gt;<br>
        The name of the defined DbLog, like it is given in fhem.cfg.</li>
      <li>&lt;in&gt;<br>
        A dummy parameter for FileLog compatibility. Always set to <code>-</code></li>
      <li>&lt;out&gt;<br>
        A dummy parameter for FileLog compatibility. Set it to <code>webchart</code>
        to use the charting related get function.
      </li>
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Used to select the data. Please use the following timeformat:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <li>&lt;device&gt;<br>
        A string which represents the device to query.</li>
      <li>&lt;querytype&gt;<br>
        A string which represents the method the query should use. Actually supported values are: <br>
          <code>getreadings</code> to retrieve the possible readings for a given device<br>
          <code>getdevices</code> to retrieve all available devices<br>
          <code>timerange</code> to retrieve charting data, which requires a given xaxis, yaxis, device, to and from<br>
          <code>savechart</code> to save a chart configuration in the database. Requires a given xaxis, yaxis, device, to and from, and a 'savename' used to save the chart<br>
          <code>deletechart</code> to delete a saved chart. Requires a given id which was set on save of the chart<br>
          <code>getcharts</code> to get a list of all saved charts.<br>
          <code>getTableData</code> to get jsonformatted data from the database. Uses paging Parameters like start and limit.<br>
          <code>hourstats</code> to get statistics for a given value (yaxis) for an hour.<br>
          <code>daystats</code> to get statistics for a given value (yaxis) for a day.<br>
          <code>weekstats</code> to get statistics for a given value (yaxis) for a week.<br>
          <code>monthstats</code> to get statistics for a given value (yaxis) for a month.<br>
          <code>yearstats</code> to get statistics for a given value (yaxis) for a year.<br>
      </li>
      <li>&lt;xaxis&gt;<br>
        A string which represents the xaxis</li>
      <li>&lt;yaxis&gt;<br>
         A string which represents the yaxis</li>
      <li>&lt;savename&gt;<br>
         A string which represents the name a chart will be saved with</li>
      <li>&lt;chartconfig&gt;<br>
         A jsonstring which represents the chart to save</li>
      <li>&lt;pagingstart&gt;<br>
         An integer used to determine the start for the sql used for query 'getTableData'</li>
      <li>&lt;paginglimit&gt;<br>
         An integer used to set the limit for the sql used for query 'getTableData'</li>
      </ul>
    <br><br>
    Examples:
      <ul>
        <li><code>get logdb - webchart "" "" "" getcharts</code><br>
            Retrieves all saved charts from the Database</li>
        <li><code>get logdb - webchart "" "" "" getdevices</code><br>
            Retrieves all available devices from the Database</li>
        <li><code>get logdb - webchart "" "" ESA2000_LED_011e getreadings</code><br>
            Retrieves all available Readings for a given device from the Database</li>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e timerange TIMESTAMP day_kwh</code><br>
            Retrieves charting data, which requires a given xaxis, yaxis, device, to and from<br>
            Will ouput a JSON like this: <code>[{'TIMESTAMP':'2013-02-11 00:10:10','VALUE':'0.22431388090756'},{'TIMESTAMP'.....}]</code></li>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e savechart TIMESTAMP day_kwh tageskwh</code><br>
            Will save a chart in the database with the given name and the chart configuration parameters</li>      
        <li><code>get logdb - webchart "" "" "" deletechart "" "" 7</code><br>
            Will delete a chart from the database with the given id</li>
      </ul>
    <br><br>
  </ul>
  <a name="DbLogattr"></a>
  <b>Attributes</b> 
  <ul><b>shutdownWait</b>
    <ul><code>attr &lt;device&gt; shutdownWait <n></code><br/>
      causes fhem shutdown to wait n seconds for pending database commit<br/>
    </ul>
  </ul><br/>
  <ul><b>DbLogSelectionMode</b>
    <ul><code>attr &lt;device&gt; DbLogSelectionMode <Exclude|Include|Exclude/Include></code><br/>
      Thise DbLog-Device-Attribute specifies how the device specific Attributes DbLogExclude and DbLogInclude are handled.
         If this Attribute is missing it defaults to "Exclude".
         <ul>
               <li>Exclude: DbLog behaves just as usual. This means everything specified in the regex in DEF will be logged by default and anything excluded
                       via the DbLogExclude attribute will not be logged</li>
               <li>Include: Nothing will be logged, except the readings specified via regex in the DbLogInclude attribute
               </li>
               <li>Exclude/Include: Just almost the same as Exclude, but if the reading matches the DbLogExclude attribute, then
                       it will further be checked against the regex in DbLogInclude whicht may possibly re-include the already 
                       excluded reading.
               </li>
         </ul>
         <br/>
    </ul>
  </ul><br/>
       See also DbLogSelectionMode-Attribute of DbLog-Device which takes influence on 
       on how DbLogExclude and DbLogInclude are handled
  <ul><b>DbLogInclude</b>
    <br>
    <ul>
      <code>
      set &lt;device&gt; DbLogInclude regex:MinInterval [regex:MinInterval] ...
      </code>
    </ul>
    A new Attribute DbLogInclude will be propagated
    to all Devices if DBLog is used. DbLogInclude works just like DbLogExclude but 
       to include matching readings.
       See also DbLogSelectionMode-Attribute of DbLog-Device which takes influence on 
       on how DbLogExclude and DbLogInclude are handled
    <br>
    <b>Example</b>
    <ul>
      <code>attr MyDevice1 DbLogInclude .*</code>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300,battery:3600</code>
    </ul>
  </ul><br>
  <ul><b>DbLogExclude</b>
    <br>
    <ul>
      <code>
      set &lt;device&gt; DbLogExclude regex:MinInterval [regex:MinInterval] ...
      </code>
    </ul>
    A new Attribute DbLogExclude will be propagated
    to all Devices if DBLog is used. DbLogExclude will work as regexp to exclude 
    defined readings to log. Each individual regexp-group are separated by comma. 
    If a MinInterval is set, the logentry is dropped if the 
    defined interval is not reached and value vs. lastvalue is eqal .
    <br>
    <b>Example</b>
    <ul>
      <code>attr MyDevice1 DbLogExclude .*</code>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300,battery:3600</code>
    </ul>
  </ul><br>
    <ul><b>suppressUndef</b>
      <ul><code>attr &lt;device&gt; ignoreUndef <n></code><br/>
        suppresses all undef values when returning data from the DB via get<br/>
      </ul>
      <b>Example</b>
      <ul>
        <code>#DbLog eMeter:power:::$val=($val>1500)?undef:$val</code>
      </ul>
  </ul><br/>
</ul>

=end html
=begin html_DE

<a name="DbLog"></a>
<h3>DbLog</h3>
<ul>
  <br>

  <a name="DbLogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; DbLog &lt;configfilename&gt; &lt;regexp&gt;</code>
    <br><br>

    Speichert Events in eine Datenbank. Die Datenbankverbindungsparameter werden
    definiert in <code>&lt;configfilename&gt;</code>. (Vergleiche
    Beipspielkonfigurationsdatei in <code>contrib/dblog/db.conf</code>).<br>
    Die Konfiguration ist in einer sparaten Datei abgelegt um das Datenbankpasswort
    nicht in Klartext in der FHEM-Haupt-Konfigurationsdatei speichern zu m&ouml;ssen.
    Ansonsten w&auml;re es mittels des <a href="../docs/commandref.html#list">list</a>
    Befehls einfach auslesbar.
    <br><br>

    Die Perl-Module <code>DBI</code> and <code>DBD::&lt;dbtype&gt;</code>
    m&ouml;ssen installiert werden (use <code>cpan -i &lt;module&gt;</code>
    falls die eigene Distribution diese nicht schon mitbringt).
    <br><br>

    <code>&lt;regexp&gt;</code> ist identisch wie <a href="../docs/commandref.html#FileLog">FileLog</a>.
    <br><br>
    Ein Beispielcode zum Erstellen einer MySQL/PostGreSQL Datenbak ist in
    <code>contrib/dblog/&lt;DBType&gt;_create.sql</code> zu finden.
    Die Datenbank beinhaltet 2 Tabellen: <code>current</code> und
    <code>history</code>. Die Tabelle <code>current</code> enth&auml;lt den letzten Stand
    pro Device und Reading. In der Tabelle <code>history</code> sind alle
    Events historisch gespeichert.

    Die Tabellenspalten haben folgende Bedeutung:
    <ol>
      <li>TIMESTAMP: Zeitpunkt des Events, z.B. <code>2007-12-30 21:45:22</code></li>
      <li>DEVICE: name des Devices, z.B. <code>Wetterstation</code></li>
      <li>TYPE: Type des Devices, z.B. <code>KS300</code></li>
      <li>EVENT: das auftretende Event als volle Zeichenkette
                                          z.B. <code>humidity: 71 (%)</code></li>
      <li>READING: Name des Readings, ermittelt aus dem Event,
                      z.B. <code>humidity</code></li>

      <li>VALUE: aktueller Wert des Readings, ermittelt aus dem Event,
                      z.B. <code>71</code></li>
      <li>UNIT: Einheit, ermittelt aus dem Event, z.B. <code>%</code></li>
    </ol>
    Der Wert des Readings ist optimiert f&ouml;r eine automatisierte Nachverarbeitung
    z.B. <code>yes</code> ist transformiert nach <code>1</code>
    <br><br>
    Die gespeicherten Werte k&ouml;nnen mittels GET Funktion angezeigt werden:
    <ul>
      <code>get myDbLog - - 2012-11-10 2012-11-10 KS300:temperature</code>
    </ul>
    <br><br>
    <b>Beispiel:</b>
    <ul>
        <code>Speichert alles in der Datenbank</code><br>
        <code>define myDbLog DbLog /etc/fhem/db.conf .*:.*</code>
    </ul>
  </ul>


  <a name="DbLogset"></a>
  <b>Set</b> 
  <ul>
    <code>set &lt;name&gt; reopen </code><br/><br/>
      <ul>Schlie&szlig;t die Datenbank und &ouml;ffnet sie danach sofort wieder. Dabei wird die Journaldatei geleert und neu angelegt.<br/>
      Verbessert den Datendurchsatz und vermeidet Speicherplatzprobleme.</ul><br/>

    <code>set &lt;name&gt; rereadcfg </code><br/><br/>
      <ul>Schlie&szlig;t die Datenbank und &ouml;ffnet sie danach sofort wieder. Dabei wird die Journaldatei geleert und neu angelegt.<br/>
      Verbessert den Datendurchsatz und vermeidet Speicherplatzprobleme.<br/>
      Zwischen dem Schlie&szlig;en der Verbindung und dem Neuverbinden werden die Konfigurationsdaten neu gelesen</ul><br/>

    <code>set &lt;name&gt; count </code><br/><br/>
      <ul>Z&auml;hlt die Datens&auml;tze in den Tabellen current und history und schreibt die Ergebnisse in die Readings countCurrent und countHistory.</ul><br/>

    <code>set &lt;name&gt; deleteOldDays &lt;n&gt;</code><br/><br/>
      <ul>L&ouml;scht Datens&auml;tze, die &auml;lter sind als &lt;n&gt; Tage. Die Anzahl der gel&ouml;schten Datens&auml;tze wird in das Reading lastRowsDeleted geschrieben.</ul><br/>

    <code>set &lt;name&gt; userCommand &lt;validSqlStatement&gt;</code><br/><br/>
      <ul><b>BENUTZE DIESE FUNKTION NUR, WENN DU WIRKLICH (WIRKLICH!) WEISST, WAS DU TUST!!!</b><br/><br/>
          F&uuml;hrt einen beliebigen (!!!) sql Befehl in der Datenbank aus. Der Befehl und ein zur&uuml;ckgeliefertes Ergebnis werden in entsprechende Readings geschrieben.<br/>
      </ul><br/>

  </ul><br>


  <a name="DbLogget"></a>
  <b>Get</b>
  <ul>
  <code>get &lt;name&gt; ReadingsVal&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; &lt;device&gt; &lt;reading&gt; &lt;default&gt;</code><br/>
  <code>get &lt;name&gt; ReadingsTimestamp &lt;device&gt; &lt;reading&gt; &lt;default&gt;</code><br/>
  <br/>
  Liest einen einzelnen Wert aus der Datenbank, Benutzung und Syntax sind weitgehend identisch zu ReadingsVal() und ReadingsTimestamp().<br/>
  </ul>
  <br/>
  <br/>
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;column_spec&gt; </code>
    <br><br>
    Liesst Daten aus der Datenbank. Wird durch die Frontends benutzt um Plots
    zu generieren ohne selbst auf die Datenank zugreifen zu m&ouml;ssen.
    <br>
    <ul>
      <li>&lt;in&gt;<br>
        Ein Parameter um eine Kompatibilit&auml;t zum Filelog herzustellen.
        Dieser Parameter ist per default immer auf <code>-</code> zu setzen.<br>
        Folgende Auspr&auml;gungen sind zugelassen:<br>
        <ul>
          <li>current: die aktuellen Werte aus der Tabelle "current" werden gelesen.</li>
          <li>history: die historischen Werte aus der Tabelle "history" werden gelesen.</li>
          <li>-: identisch wie "history"</li>
        </ul> 
      </li>
      <li>&lt;out&gt;<br>
        Ein Parameter um eine Kompatibilit&auml;t zum Filelog herzustellen.
        Dieser Parameter ist per default immer auf <code>-</code> zu setzen um die
        Ermittlung der Daten aus der Datenbank f&ouml;r die Plotgenerierung zu pr&ouml;fen.<br>
        Folgende Auspr&auml;gungen sind zugelassen:<br>
        <ul>
          <li>ALL: Es werden alle Spalten der Datenbank ausgegeben. Inclusive einer &Uuml;berschrift.</li>
          <li>Array: Es werden alle Spalten der Datenbank als Hash ausgegeben. Alle Datens&auml;tze als Array zusammengefasst.</li>
          <li>INT: intern zur Plotgenerierung verwendet</li>
          <li>-: default</li>
        </ul>
      </li>
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Wird benutzt um den Zeitraum der Daten einzugrenzen. Es ist das folgende
        Zeitformat oder ein Teilstring davon zu benutzen:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <li>&lt;column_spec&gt;<br>
        F&ouml;r jede column_spec Gruppe wird ein Datenset zur&ouml;ckgegeben welches
        durch einen Kommentar getrennt wird. Dieser Kommentar repr&auml;sentiert
        die column_spec.<br>
        Syntax: &lt;device&gt;:&lt;reading&gt;:&lt;default&gt;:&lt;fn&gt;:&lt;regexp&gt;<br>
        <ul>
          <li>&lt;device&gt;<br>
            Der Name des Devices. Achtung: Gross/Kleinschreibung beachten!<br>
            Es kann ein % als Jokerzeichen angegeben werden.</li>
          <li>&lt;reading&gt;<br>
            Das Reading des angegebenen Devices zur Datenselektion.<br>
            Es kann ein % als Jokerzeichen angegeben werden.<br>
            Achtung: Gross/Kleinschreibung beachten!
          </li>
          <li>&lt;default&gt;<br>
            Zur Zeit noch nicht implementiert.
          </li>
          <li>&lt;fn&gt;
            Angabe einer speziellen Funktion:
            <ul>
              <li>int<br>
                Ermittelt den Zahlenwert ab dem Anfang der Zeichenkette aus der
                Spalte "VALUE". Benutzt z.B. f&ouml;r Auspr&auml;gungen wie 10%.
              </li>
              <li>int&lt;digit&gt;<br>
                Ermittelt den Zahlenwert ab dem Anfang der Zeichenkette aus der
                Spalte "VALUE", inclusive negativen Vorzeichen und Dezimaltrenner.
                Benutzt z.B. f&ouml;r Auspr&auml;gungen wie -5.7&deg;C.
              </li>
              <li>delta-h / delta-d<br>
                Ermittelt die relative Ver&auml;nderung eines Zahlenwertes pro Stunde
                oder pro Tag. Wird benutzt z.B. f&ouml;r Spalten die einen
                hochlaufenden Z&auml;hler enthalten wie im Falle f&ouml;r ein KS300 Regenz&auml;hler
                oder dem 1-wire Modul OWCOUNT.
              </li>
              <li>delta-ts<br>
                Ermittelt die vergangene Zeit zwischen dem letzten und dem aktuellen Logeintrag
                in Sekunden und ersetzt damit den originalen Wert.
              </li>
            </ul></li>
            <li>&lt;regexp&gt;<br>
              Diese Zeichenkette wird als Perl Befehl ausgewertet. Die regexp wird vor dem angegebenen &lt;fn&gt; Parameter ausgef&ouml;hrt.
              <br>
              Bitte zur Beachtung: Diese Zeichenkette darf keine Leerzeichen
              enthalten da diese sonst als &lt;column_spec&gt; Trennung
              interpretiert werden und alles nach dem Leerzeichen als neue
              &lt;column_spec&gt; gesehen wird.<br>
              <b>Schl&ouml;sselw&ouml;rter</b>
              <li>$val ist der aktuelle Wert die die Datenbank f&ouml;r ein Device/Reading ausgibt.</li>
              <li>$ts ist der aktuelle Timestamp des Logeintrages.</li>
              <li>Wird als $val das Schl&ouml;sselwort "hide" zur&ouml;ckgegeben, so wird dieser Logeintrag nicht
                  ausgegeben, trotzdem aber f&ouml;r die Zeitraumberechnung verwendet.</li>
              <li>Wird als $val das Schl&ouml;sselwort "ignore" zur&ouml;ckgegeben, so wird dieser Logeintrag
                  nicht f&ouml;r eine Folgeberechnung verwendet.</li>
            </li>
        </ul></li>
      </ul>
    <br><br>
    <b>Beispiele:</b>
      <ul>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature</code></li>
        <li><code>get myDbLog current ALL - - %:temperature</code></li><br>
            Damit erh?lt man alle aktuellen Readings "temperature" von allen in der DB geloggten Devices.
            Achtung: bei Nutzung von Jokerzeichen auf die historyTabelle kann man sein FHEM aufgrund langer Laufzeit lahmlegen!
        <li><code>get myDbLog - - 2012-11-10_10 2012-11-10_20 KS300:temperature::int1</code><br>
           gibt Daten aus von 10Uhr bis 20Uhr am 10.11.2012</li>
        <li><code>get myDbLog - all 2012-11-10 2012-11-20 KS300:temperature</code></li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature KS300:rain::delta-h KS300:rain::delta-d</code></li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 MyFS20:data:::$val=~s/(on|off).*/$1eq"on"?1:0/eg</code><br>
           gibt 1 zur&ouml;ck f&ouml;r alle Auspr&auml;gungen von on* (on|on-for-timer etc) und 0 f&ouml;r alle off*</li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 Bodenfeuchte:data:::$val=~s/.*B:\s([-\.\d]+).*/$1/eg</code><br>
           Beispiel von OWAD: Ein Wert wie z.B.: <code>"A: 49.527 % B: 66.647 % C: 9.797 % D: 0.097 V"</code><br>
           und die Ausgabe ist f&ouml;r das Reading B folgende: <code>2012-11-20_10:23:54 66.647</code></li>
        <li><code>get DbLog - - 2013-05-26 2013-05-28 Pumpe:data::delta-ts:$val=~s/on/hide/</code><br>
           Realisierung eines Betriebsstundenz&auml;hlers.Durch delta-ts wird die Zeit in Sek zwischen den Log-
           eintr&auml;gen ermittelt. Die Zeiten werden bei den on-Meldungen nicht ausgegeben welche einer Abschaltzeit 
           entsprechen w&ouml;rden.</li>
      </ul>
    <br><br>
  </ul>

  <b>Get</b> f&ouml;r die Nutzung von webcharts
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;device&gt; &lt;querytype&gt; &lt;xaxis&gt; &lt;yaxis&gt; &lt;savename&gt; </code>
    <br><br>
    Liest Daten aus der Datenbank aus und gibt diese in JSON formatiert aus. Wird f&ouml;r das Charting Frontend genutzt
    <br>

    <ul>
      <li>&lt;name&gt;<br>
        Der Name des definierten DbLogs, so wie er in der fhem.cfg angegeben wurde.</li>
      <li>&lt;in&gt;<br>
        Ein Dummy Parameter um eine Kompatibilit&auml;t zum Filelog herzustellen.
        Dieser Parameter ist immer auf <code>-</code> zu setzen.</li>
      <li>&lt;out&gt;<br>
        Ein Dummy Parameter um eine Kompatibilit&auml;t zum Filelog herzustellen. 
        Dieser Parameter ist auf <code>webchart</code> zu setzen um die Charting Get Funktion zu nutzen.
      </li>
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Wird benutzt um den Zeitraum der Daten einzugrenzen. Es ist das folgende
        Zeitformat zu benutzen:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <li>&lt;device&gt;<br>
        Ein String, der das abzufragende Device darstellt.</li>
      <li>&lt;querytype&gt;<br>
        Ein String, der die zu verwendende Abfragemethode darstellt. Zur Zeit unterst&ouml;tzte Werte sind: <br>
          <code>getreadings</code> um f&ouml;r ein bestimmtes device alle Readings zu erhalten<br>
          <code>getdevices</code> um alle verf&ouml;gbaren devices zu erhalten<br>
          <code>timerange</code> um Chart-Daten abzufragen. Es werden die Parameter 'xaxis', 'yaxis', 'device', 'to' und 'from' ben&ouml;tigt<br>
          <code>savechart</code> um einen Chart unter Angabe eines 'savename' und seiner zugeh&ouml;rigen Konfiguration abzuspeichern<br>
          <code>deletechart</code> um einen zuvor gespeicherten Chart unter Angabe einer id zu l&ouml;schen<br>
          <code>getcharts</code> um eine Liste aller gespeicherten Charts zu bekommen.<br>
          <code>getTableData</code> um Daten aus der Datenbank abzufragen und in einer Tabelle darzustellen. Ben&ouml;tigt paging Parameter wie start und limit.<br>
          <code>hourstats</code> um Statistiken f&ouml;r einen Wert (yaxis) f&ouml;r eine Stunde abzufragen.<br>
          <code>daystats</code> um Statistiken f&ouml;r einen Wert (yaxis) f&ouml;r einen Tag abzufragen.<br>
          <code>weekstats</code> um Statistiken f&ouml;r einen Wert (yaxis) f&ouml;r eine Woche abzufragen.<br>
          <code>monthstats</code> um Statistiken f&ouml;r einen Wert (yaxis) f&ouml;r einen Monat abzufragen.<br>
          <code>yearstats</code> um Statistiken f&ouml;r einen Wert (yaxis) f&ouml;r ein Jahr abzufragen.<br>
      </li>
      <li>&lt;xaxis&gt;<br>
        Ein String, der die X-Achse repr&auml;sentiert</li>
      <li>&lt;yaxis&gt;<br>
         Ein String, der die Y-Achse repr&auml;sentiert</li>
      <li>&lt;savename&gt;<br>
         Ein String, unter dem ein Chart in der Datenbank gespeichert werden soll</li>
      <li>&lt;chartconfig&gt;<br>
         Ein jsonstring der den zu speichernden Chart repr&auml;sentiert</li>
      <li>&lt;pagingstart&gt;<br>
         Ein Integer um den Startwert f&ouml;r die Abfrage 'getTableData' festzulegen</li>
      <li>&lt;paginglimit&gt;<br>
         Ein Integer um den Limitwert f&ouml;r die Abfrage 'getTableData' festzulegen</li>
      </ul>
    <br><br>
    Beispiele:
      <ul>
        <li><code>get logdb - webchart "" "" "" getcharts</code><br>
            Liefert alle gespeicherten Charts aus der Datenbank</li>
        <li><code>get logdb - webchart "" "" "" getdevices</code><br>
            Liefert alle verf&ouml;gbaren Devices aus der Datenbank</li>
        <li><code>get logdb - webchart "" "" ESA2000_LED_011e getreadings</code><br>
            Liefert alle verf&ouml;gbaren Readings aus der Datenbank unter Angabe eines Ger&auml;tes</li>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e timerange TIMESTAMP day_kwh</code><br>
            Liefert Chart-Daten, die auf folgenden Parametern basieren: 'xaxis', 'yaxis', 'device', 'to' und 'from'<br>
            Die Ausgabe erfolgt als JSON, z.B.: <code>[{'TIMESTAMP':'2013-02-11 00:10:10','VALUE':'0.22431388090756'},{'TIMESTAMP'.....}]</code></li>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e savechart TIMESTAMP day_kwh tageskwh</code><br>
            Speichert einen Chart unter Angabe eines 'savename' und seiner zugeh&ouml;rigen Konfiguration</li>
        <li><code>get logdb - webchart "" "" "" deletechart "" "" 7</code><br>
            L&ouml;scht einen zuvor gespeicherten Chart unter Angabe einer id</li>
      </ul>
    <br><br>
  </ul>

  <a name="DbLogattr"></a>
  <b>Attribute</b>
  <ul><b>shutdownWait</b>
     <ul><code>attr &lt;device&gt; shutdownWait <n></code><br/>
      fhem wartet waehrend des shutdowns fuer n Sekunden, um die Datenbank korrekt zu beenden<br/>
    </ul>
  </ul><br/>
  <ul><b>DbLogSelectionMode</b>
    <ul><code>attr &lt;device&gt; DbLogSelectionMode <Exclude|Include|Exclude/Include></code><br/>
      Dieses, fuer DbLog-Devices spezifische Attribut beeinflußt, wie die Device-spezifischen Attributes
         DbLogExclude und DbLogInclude (s.u.) ausgewertet werden.<br>
         Fehlt dieses Attribut wird dafuer "Exclude" als Default angenommen.<br>
   
         <ul>
               <li>Exclude: DbLog verhaelt sich wie bisher auch, alles was ueber die RegExp im DEF angegeben ist, wird geloggt, bis auf das,
               was ueber die RegExp in DbLogExclude ausgeschlossen wird<br>
               Das Attribut DbLogInclude wird in diesem Fall nicht beruecksichtigt</li>
               <li>Include: Es wird nur das geloggt was ueber die RegExp in DbLogInclude eingeschlossen wird.<br>
                       Das Attribut DbLogExclude wird in diesem Fall nicht beruecksichtigt, ebenso wenig, wie
                       die regex im DEF.
               </li>
               <li>Exclude/Include: Funktioniert im Wesentlichen, wie "Exclude", nur das sowohl DbLogExclude, als auch DbLogInclude
                       geprueft werden: Readings, die durch DbLogExclude zwar ausgeschlossen wurden, mit DbLogInclude aber wiederum eingeschlossen wwrden,
                       werden somit dennoch geloggt.
               </li>
         </ul>
         <br/>
    </ul>
  </ul><br/>
       Siehe dazu auch das DbLog-Device-Spezifische Attribut DbLogSelectionMode, das beeinflußt wie
       DbLogExclude und DbLogInclude ausgewertet werden.
  
  <ul><b>DbLogInclude</b>
    <ul>
      <code>
      set &lt;device&gt; DbLogInclude regex:MinInterval [regex:MinInterval] ...
      </code>
    </ul>
    <br>
    Wenn DbLog genutzt wird, wird in alle Devices das Attribut <i>DbLogInclude</i>
    propagiert. DbLogInclude funktioniert im Endeffekt genau wie DbLogExclude, ausser dass eben
       readings mit diesen RegExp in das Logging eingeschlossen werden koennen, statt ausgeschlossen.
       Siehe dazu auch das DbLog-Device-Spezifische Attribut DbLogSelectionMode, das beeinflußt wie
       DbLogExclude und DbLogInclude ausgewertet werden.
    <br>
    <b>Beispiele</b>
    <ul>
      <code>attr MyDevice1 DbLogInclude .*</code>
      <code>attr MyDevice2 DbLogInclude state,(floorplantext|MyUserReading):300,battery:3600</code>
    </ul>
  </ul><br>
  <ul><b>DbLogExclude</b>
    <ul>
      <code>
      set &lt;device&gt; DbLogExclude regex:MinInterval [regex:MinInterval] ...
      </code>
    </ul>
    <br>
    Wenn DbLog genutzt wird, wird in alle Devices das Attribut <i>DbLogExclude</i>
    propagiert. Der Wert des Attributes wird als Regexp ausgewertet und schliesst die 
    damit matchenden Readings von einem Logging aus. Einzelne Regexp werden durch 
    Kommata getrennt. Ist MinIntervall angegeben, so wird der Logeintrag nur
    dann nicht geloggt, wenn das Intervall noch nicht erreicht und der Wert des 
    Readings sich nicht ver&auml;ndert hat.
    <br>
    <b>Beispiele</b>
    <ul>
      <code>attr MyDevice1 DbLogExclude .*</code>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300,battery:3600</code>
    </ul>
  </ul><br>
  <ul><b>suppressUndef</b>
    <ul><code>attr &lt;device&gt; ignoreUndef <n></code><br/>
        Unterdrueckt alle undef Werte die durch eine Get-Anfrage zb. Plot aus der Datenbank selektiert werden<br/>
    </ul>
    <b>Beispiel</b>
    <ul>
      <code>#DbLog eMeter:power:::$val=($val>1500)?undef:$val</code>
    </ul>
  </ul><br/>
</ul>

=end html_DE
=cut
