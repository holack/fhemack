##############################################
# $Id: 00_ZWDongle.pm 8675 2015-06-01 07:23:48Z rudolfkoenig $
# TODO:
# - routing commands
# - one command to create a fhem device for all nodeList entries
# - inclusion mode active only for a given time (pairForSec)
# - use central readings functions
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub ZWDongle_Parse($$$);
sub ZWDongle_Read($@);
sub ZWDongle_ReadAnswer($$$);
sub ZWDongle_Ready($);
sub ZWDongle_Write($$$);
sub ZWave_ProcessSendStack($);


# See also:
# http://www.digiwave.dk/en/programming/an-introduction-to-the-z-wave-protocol/
# http://open-zwave.googlecode.com/svn-history/r426/trunk/cpp/src/Driver.cpp
# http://buzzdavidson.com/?p=68
# https://bitbucket.org/bradsjm/aeonzstickdriver
my %sets = (
  "addNode"          => { cmd => "4a%02x@",    # ZW_ADD_NODE_TO_NETWORK'
                        param => {nwOn=>0xc1, on=>0x81, off=>0x05 } },
  "removeNode"       => { cmd => "4b%02x@",    # ZW_REMOVE_NODE_FROM_NETWORK'
                        param => {nwOn=>0xc1, on=>0x81, off=>0x05 } },
  "createNode"       => { cmd => "60%02x" },   # ZW_REQUEST_NODE_INFO'
  "removeFailedNode" => { cmd => "61%02x" },   # ZW_REMOVE_FAILED_NODE_ID
  "replaceFailedNode"=> { cmd => "63%02x" },   # ZW_REPLACE_FAILED_NODE
  "neighborUpdate"   => { cmd => "48%02x" },   # ZW_REQUEST_NODE_NEIGHBOR_UPDATE
  "sendNIF"          => { cmd => "12%02x05@" },# ZW_SEND_NODE_INFORMATION
  "setNIF"           => { cmd => "03%02x%02x%02x%02x" },
                                              # SERIAL_API_APPL_NODE_INFORMATION
  "timeouts"         => { cmd => "06%02x%02x"},# SERIAL_API_SET_TIMEOUTS
  "reopen"           => { cmd => "" },
);

my %gets = (
  "caps"            => "07",      # SERIAL_API_GET_CAPABILITIES
  "ctrlCaps"        => "05",      # ZW_GET_CONTROLLER_CAPS
  "getVirtualNodes" => "a5",      # ZW_GET_VIRTUAL_NODES
  "homeId"          => "20",      # MEMORY_GET_ID
  "isFailedNode"    => "62%02x",  # ZW_IS_FAILED_NODE
  "neighborList" => "80%02x0101", # GET_ROUTING_TABLE_LINE include dead links,
                                  #              include non-routing neigbors
  "nodeInfo"        => "41%02x",  # ZW_GET_NODE_PROTOCOL_INFO
  "nodeList"        => "02",      # SERIAL_API_GET_INIT_DATA
  "random"          => "1c%02x",  # ZW_GET_RANDOM
  "version"         => "15",      # ZW_GET_VERSION

  "raw"             => "%s",            # hex
);

# Known controller function. 
# Note: Known != implemented, see %sets & %gets for the implemented ones.
use vars qw(%zw_func_id);
use vars qw(%zw_type6);
%zw_func_id= (
  '02'  => 'SERIAL_API_GET_INIT_DATA',
  '03'  => 'SERIAL_API_APPL_NODE_INFORMATION',
  '04'  => 'APPLICATION_COMMAND_HANDLER',
  '05'  => 'ZW_GET_CONTROLLER_CAPABILITIES',
  '06'  => 'SERIAL_API_SET_TIMEOUTS',
  '07'  => 'SERIAL_API_GET_CAPABILITIES',
  '08'  => 'SERIAL_API_SOFT_RESET',
  '10'  => 'ZW_SET_R_F_RECEIVE_MODE',
  '11'  => 'ZW_SET_SLEEP_MODE',
  '12'  => 'ZW_SEND_NODE_INFORMATION',
  '13'  => 'ZW_SEND_DATA',
  '14'  => 'ZW_SEND_DATA_MULTI',
  '15'  => 'ZW_GET_VERSION',
  '16'  => 'ZW_SEND_DATA_ABORT',
  '17'  => 'ZW_R_F_POWER_LEVEL_SET',
  '18'  => 'ZW_SEND_DATA_META',
  '1c'  => 'ZW_GET_RANDOM',
  '20'  => 'MEMORY_GET_ID',
  '21'  => 'MEMORY_GET_BYTE',
  '22'  => 'MEMORY_PUT_BYTE',
  '23'  => 'MEMORY_GET_BUFFER',
  '24'  => 'MEMORY_PUT_BUFFER',
  '30'  => 'CLOCK_SET',
  '31'  => 'CLOCK_GET',
  '32'  => 'CLOCK_COMPARE',
  '33'  => 'RTC_TIMER_CREATE',
  '34'  => 'RTC_TIMER_READ',
  '35'  => 'RTC_TIMER_DELETE',
  '36'  => 'RTC_TIMER_CALL',
  '40'  => 'ZW_SET_LEARN_NODE_STATE',
  '41'  => 'ZW_GET_NODE_PROTOCOL_INFO',
  '42'  => 'ZW_SET_DEFAULT',
  '43'  => 'ZW_NEW_CONTROLLER',
  '44'  => 'ZW_REPLICATION_COMMAND_COMPLETE',
  '45'  => 'ZW_REPLICATION_SEND_DATA',
  '46'  => 'ZW_ASSIGN_RETURN_ROUTE',
  '47'  => 'ZW_DELETE_RETURN_ROUTE',
  '48'  => 'ZW_REQUEST_NODE_NEIGHBOR_UPDATE',
  '49'  => 'ZW_APPLICATION_UPDATE',
  '4a'  => 'ZW_ADD_NODE_TO_NETWORK',
  '4b'  => 'ZW_REMOVE_NODE_FROM_NETWORK',
  '4c'  => 'ZW_CREATE_NEW_PRIMARY',
  '4d'  => 'ZW_CONTROLLER_CHANGE',
  '50'  => 'ZW_SET_LEARN_MODE',
  '51'  => 'ZW_ASSIGN_SUC_RETURN_ROUTE',
  '52'  => 'ZW_ENABLE_SUC',
  '53'  => 'ZW_REQUEST_NETWORK_UPDATE',
  '54'  => 'ZW_SET_SUC_NODE_ID',
  '55'  => 'ZW_DELETE_SUC_RETURN_ROUTE',
  '56'  => 'ZW_GET_SUC_NODE_ID',
  '57'  => 'ZW_SEND_SUC_ID',
  '59'  => 'ZW_REDISCOVERY_NEEDED',
  '5e'  => 'ZW_EXPLORE_REQUEST_INCLUSION',
  '60'  => 'ZW_REQUEST_NODE_INFO',
  '61'  => 'ZW_REMOVE_FAILED_NODE_ID',
  '62'  => 'ZW_IS_FAILED_NODE',
  '63'  => 'ZW_REPLACE_FAILED_NODE',
  '70'  => 'TIMER_START',
  '71'  => 'TIMER_RESTART',
  '72'  => 'TIMER_CANCEL',
  '73'  => 'TIMER_CALL',
  '80'  => 'GET_ROUTING_TABLE_LINE',
  '81'  => 'GET_T_X_COUNTER',
  '82'  => 'RESET_T_X_COUNTER',
  '83'  => 'STORE_NODE_INFO',
  '84'  => 'STORE_HOME_ID',
  '90'  => 'LOCK_ROUTE_RESPONSE',
  '91'  => 'ZW_SEND_DATA_ROUTE_DEMO',
  '95'  => 'SERIAL_API_TEST',
  'a0'  => 'SERIAL_API_SLAVE_NODE_INFO',
  'a1'  => 'APPLICATION_SLAVE_COMMAND_HANDLER',
  'a2'  => 'ZW_SEND_SLAVE_NODE_INFO',
  'a3'  => 'ZW_SEND_SLAVE_DATA',
  'a4'  => 'ZW_SET_SLAVE_LEARN_MODE',
  'a5'  => 'ZW_GET_VIRTUAL_NODES',
  'a6'  => 'ZW_IS_VIRTUAL_NODE',
  'b6'  => 'ZW_WATCHDOG_ENABLE',
  'b7'  => 'ZW_WATCHDOG_DISABLE',
  'b8'  => 'ZW_WATCHDOG_CHECK',
  'b9'  => 'ZW_SET_EXT_INT_LEVEL',
  'ba'  => 'ZW_RF_POWERLEVEL_GET',
  'bb'  => 'ZW_GET_NEIGHBOR_COUNT',
  'bc'  => 'ZW_ARE_NODES_NEIGHBOURS',
  'bd'  => 'ZW_TYPE_LIBRARY',
  'be'  => 'ZW_SEND_TEST_FRAME',
  'bf'  => 'ZW_GET_PROTOCOL_STATUS',
  'd0'  => 'ZW_SET_PROMISCUOUS_MODE',
);

%zw_type6 = (
  '01' => 'GENERIC_CONTROLLER',    '12' => 'SWITCH_REMOTE',
  '02' => 'STATIC_CONTROLLER',     '13' => 'SWITCH_TOGGLE',
  '03' => 'AV_CONTROL_POINT',      '20' => 'SENSOR_BINARY',
  '06' => 'DISPLAY',               '21' => 'SENSOR_MULTILEVEL',
  '07' => 'GARAGE_DOOR',           '22' => 'WATER_CONTROL',
  '08' => 'THERMOSTAT',            '30' => 'METER_PULSE',
  '09' => 'WINDOW_COVERING',       '40' => 'ENTRY_CONTROL',
  '0F' => 'REPEATER_SLAVE',        '50' => 'SEMI_INTEROPERABLE',
  '10' => 'SWITCH_BINARY',         'ff' => 'NON_INTEROPERABLE',
  '11' => 'SWITCH_MULTILEVEL',
);

my $serInit;

sub
ZWDongle_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "ZWDongle_Read";
  $hash->{WriteFn} = "ZWDongle_Write";
  $hash->{ReadyFn} = "ZWDongle_Ready";
  $hash->{ReadAnswerFn} = "ZWDongle_ReadAnswer";

# Normal devices
  $hash->{DefFn}   = "ZWDongle_Define";
  $hash->{SetFn}   = "ZWDongle_Set";
  $hash->{GetFn}   = "ZWDongle_Get";
  $hash->{AttrFn}  = "ZWDongle_Attr";
  $hash->{UndefFn} = "ZWDongle_Undef";
  $hash->{AttrList}=
    "do_not_notify:1,0 dummy:1,0 model:ZWDongle disable:0,1 homeId networkKey";
}

#####################################
sub
ZWDongle_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> ZWDongle {none[:homeId] | ".
                        "devicename[\@baudrate] | ".
                        "devicename\@directio | ".
                        "hostname:port}";
    return $msg;
  }

  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];

  $hash->{Clients} = ":ZWave:";
  my %matchList = ( "1:ZWave" => ".*" );
  $hash->{MatchList} = \%matchList;

  if($dev =~ m/none:(.*)/) {
    $hash->{homeId} = $1;
    Log3 $name, 1, 
        "$name device is none (homeId:$1), commands will be echoed only";
    $attr{$name}{dummy} = 1;
    $hash->{STATE} = "dummy";
    return undef;

  } elsif($dev !~ m/@/ && $dev !~ m/:/) {
    $def .= "\@115200";  # default baudrate

  }

  $hash->{DeviceName} = $dev;
  $hash->{CallbackNr} = 0;
  $hash->{nrNAck} = 0;
  $hash->{WaitForAck}=0;
  $hash->{SendRetrys}=0;
  $hash->{MaxSendRetrys}=3;
  my @empty;
  $hash->{SendStack} = \@empty;
  
  my $ret = DevIo_OpenDev($hash, 0, "ZWDongle_DoInit");
  return $ret;
}

#####################################
sub
ZWDongle_Undef($$) 
{
  my ($hash,$arg) = @_;
  DevIo_CloseDev($hash); 
  return undef;
}

#####################################
sub
ZWDongle_Set($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "\"set ZWDongle\" needs at least one parameter" if(@a < 1);
  my $type = shift @a;

  if(!defined($sets{$type})) {
    my @r;
    map { my $p = $sets{$_}{param};
          push @r,($p ? "$_:".join(",",sort keys %{$p}) : $_)} sort keys %sets;
    return "Unknown argument $type, choose one of " . join(" ",@r);
  }

  if($type eq "reopen") {
    return if(AttrVal($name, "dummy",undef) || AttrVal($name, "disable",undef));
    DevIo_CloseDev($hash);
    sleep(1);
    DevIo_OpenDev($hash, 0, "ZWDongle_DoInit");
    return;
  }

  my $cmd = $sets{$type}{cmd};
  my $fb = substr($cmd, 0, 2);
  if($fb =~ m/^[0-8A-F]+$/i &&
     ReadingsVal($name, "caps","") !~ m/\b$zw_func_id{$fb}\b/) {
    return "$type is unsupported by this controller";
  }

  my $par = $sets{$type}{param};
  if($par && !$par->{noArg}) {
    return "Unknown argument for $type, choose one of ".join(" ",keys %{$par})
      if(!defined($par->{$a[0]}));
    $a[0] = $par->{$a[0]};
  }

  if($cmd =~ m/\@/) {
    my $c = $hash->{CallbackNr}+1;
    $c = 1 if($c > 255);
    $hash->{CallbackNr} = $c;
    $c = sprintf("%02x", $c);
    $cmd =~ s/\@/$c/g;
  }

  my @ca = split("%", $cmd, -1);
  my $nargs = int(@ca)-1;
  return "set $name $type needs $nargs arguments" if($nargs != int(@a));

  ZWDongle_Write($hash,  "00", sprintf($cmd, @a));
  return undef;
}


#####################################
sub
ZWDongle_Get($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "\"get $name\" needs at least one parameter" if(@a < 1);
  my $type = shift @a;

  return "Unknown argument $type, choose one of " .
        join(" ", map { $gets{$_} =~ m/%/ ? $_ : "$_:noArg" } sort keys %gets)
        if(!defined($gets{$type}));

  my $fb = substr($gets{$type}, 0, 2);
  if($fb =~ m/^[0-8A-F]+$/i && !$serInit &&
     ReadingsVal($name, "caps","") !~ m/\b$zw_func_id{$fb}\b/) {
    return "$type is unsupported by this controller";
  }

  my @ga = split("%", $gets{$type}, -1);
  my $nargs = int(@ga)-1;
  return "get $name $type needs $nargs arguments" if($nargs != int(@a));

  return "No $type for dummies" if(IsDummy($name));

  my $out = sprintf($gets{$type}, @a);
  ZWDongle_Write($hash,  "00", $out);
  my $re = "^01".substr($out,0,2);  # Start with <01><len><01><CMD>
  my ($err, $ret) = ZWDongle_ReadAnswer($hash, $type, $re);
  return $err if($err);

  my $msg="";
  $msg = $ret if($ret);
  my @r = map { ord($_) } split("", pack('H*', $ret)) if(defined($ret));

  if($type eq "nodeList") {                     ############################
    return "$name: Bogus data received" if(int(@r) != 36);
    my @list;
    for my $byte (0..28) {
      my $bits = $r[5+$byte];
      for my $bit (0..7) {
        push @list, $byte*8+$bit+1 if($bits & (1<<$bit));
      }
    }
    $msg = join(",", @list);

  } elsif($type eq "caps") {                    ############################
    $msg  = sprintf("Vers:%d Rev:%d ",       $r[2], $r[3]);
    $msg .= sprintf("ManufID:%02x%02x ",     $r[4], $r[5]);
    $msg .= sprintf("ProductType:%02x%02x ", $r[6], $r[7]);
    $msg .= sprintf("ProductID:%02x%02x",    $r[8], $r[9]);
    my @list;
    for my $byte (0..31) {
      my $bits = $r[10+$byte];
      for my $bit (0..7) {
        my $id = sprintf("%02x", $byte*8+$bit+1);
        push @list, ($zw_func_id{$id} ? $zw_func_id{$id} : "UNKNOWN_$id")
                if($bits & (1<<$bit));
      }
    }
    $msg .= " ".join(" ",@list);

  } elsif($type eq "homeId") {                  ############################
    $msg = sprintf("HomeId:%s CtrlNodeId:%s", 
                substr($ret,4,8), substr($ret,12,2));
    $hash->{homeId} = substr($ret,4,8);
    $attr{NAME}{homeId} = substr($ret,4,8);

  } elsif($type eq "version") {                 ############################
    $msg = join("",  map { chr($_) } @r[2..13]);
    my @type = qw( STATIC_CONTROLLER CONTROLLER ENHANCED_SLAVE
                   SLAVE INSTALLER NO_INTELLIGENT_LIFE BRIDGE_CONTROLLER);
    my $idx = $r[14]-1;
    $msg .= " $type[$idx]" if($idx >= 0 && $idx <= $#type);

  } elsif($type eq "ctrlCaps") {                ############################
    my @type = qw(SECONDARY OTHER MEMBER PRIMARY SUC);
    my @list;
    for my $bit (0..7) {
      push @list, $type[$bit] if(($r[2] & (1<<$bit)) && $bit < @type);
    }
    $msg = join(" ", @list);

  } elsif($type eq "getVirtualNodes") {         ############################
    $msg = join(" ", @r);

  } elsif($type eq "nodeInfo") {                 ############################
    my $id = sprintf("%02x", $r[6]);
    if($id eq "00") {
      $msg = "node $a[0] is not present";
    } else {
      my @list;
      my @type5 = qw( CONTROLLER STATIC_CONTROLLER SLAVE ROUTING_SLAVE);
      push @list, $type5[$r[5]-1] if($r[5]>0 && $r[5] <= @type5);
      push @list, $zw_type6{$id} if($zw_type6{$id});
      push @list, ($r[2] & 0x80) ? "listening" : "sleeping";
      push @list, "frequentListening:" . ($r[3] & ( 0x20 | 0x40 ));
      push @list, "beaming:" . ($r[3] & 0x10);
      push @list, "routing"   if($r[2] & 0x40);
      push @list, "40kBaud"   if(($r[2] & 0x38) == 0x10);
      push @list, "Vers:" . (($r[2]&0x7)+1);
      push @list, "Security:" . ($r[3]&0x1);
      $msg = join(" ", @list);
    }

  } elsif($type eq "neighborList") {            ############################
    return "$name: Bogus data received" if(int(@r) != 31);
    my @list;
    for my $byte (0..28) {
      my $bits = $r[2+$byte];
      for my $bit (0..7) {
        push @list, $byte*8+$bit+1 if($bits & (1<<$bit));
      }
    }
    $msg = join(",", @list);

  } elsif($type eq "random") {                  ############################
    return "$name: Cannot generate" if($ret !~ m/^011c01(..)(.*)$/);
    $msg = $2; @a = ();

  }

  $type .= "_".join("_", @a) if(@a);
  $hash->{READINGS}{$type}{VAL} = $msg;
  $hash->{READINGS}{$type}{TIME} = TimeNow();

  return "$name $type => $msg";
}

#####################################
sub
ZWDongle_Clear($)
{
  my $hash = shift;

  # Clear the pipe
  $hash->{RA_Timeout} = 1.0;
  for(;;) {
    my ($err, undef) = ZWDongle_ReadAnswer($hash, "Clear", "wontmatch");
    last if($err && $err =~ m/^Timeout/);
  }
  delete($hash->{RA_Timeout});
  $hash->{PARTIAL} = "";
}

#####################################
sub
ZWDongle_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  $serInit = 1;

  DevIo_SetHwHandshake($hash) if($hash->{FD});
  $hash->{PARTIAL} = "";
  
  ZWDongle_Clear($hash);
  ZWDongle_Get($hash, $name, "caps");   $serInit = 0;
  ZWDongle_Get($hash, $name, "homeId");
  ZWDongle_Get($hash, $name, ("random", 32));         # Sec relevant
  ZWDongle_Set($hash, $name, ("timeouts", 100, 15));  # Sec relevant
  # NODEINFO_LISTENING, Generic Static controller, Specific Static Controller, 0
  ZWDongle_Set($hash, $name, ("setNIF", 1, 2, 1, 0)); # Sec relevant (?)
  ZWDongle_Clear($hash);                              # Wait, timeouts needs ack
  $hash->{STATE} = "Initialized";
  return undef;
}

#####################################
sub
ZWDongle_CheckSum($)
{
  my ($data) = @_;
  my $cs = 0xff;
  map { $cs ^= ord($_) } split("", pack('H*', $data));
  return sprintf("%02x", $cs);
}


#####################################
sub
ZWDongle_Write($$$)
{
  my ($hash,$fn,$msg) = @_;

  Log3 $hash, 5, "ZWDongle_Write msg $msg";

  # assemble complete message
  $msg = "$fn$msg";
  $msg = sprintf("%02x%s", length($msg)/2+1, $msg);
  $msg = "01$msg" . ZWDongle_CheckSum($msg);
 
  # push message on stack
  my $ss = $hash->{SendStack};
  push @{$ss}, $msg;

  # assure that wakeupNoMoreInformation is the last message on the sendStack
  if($msg =~ m/^01....13(..)/) {
    my $wNMIre = '01....13..028408';
    my $wNMI;
    my $w1 = shift @{$ss} if($ss->[0] =~ m/$wNMIre/); # keep the first, #35126
    my @s = grep { /^$wNMIre/ ? ($wNMI=$_,0):1 } @{$ss};
    if($wNMI) {
      Log3 $hash, 5, "ZWDongle_Write reordered sendStack";
      push @s, $wNMI;       
      $hash->{SendStack} = \@s;
    }
    unshift($hash->{SendStack}, $w1) if($w1);
  }

  #send first message if not waiting for ACK
  ZWave_ProcessSendStack($hash);
}

sub
ZWave_ProcessSendStack($)
{
  my ($hash) = @_;
    
  Log3 $hash, 5, "ZWave_ProcessSendStack: ".@{$hash->{SendStack}}.
                        " items on stack, waitForAck ".$hash->{WaitForAck};
  
  RemoveInternalTimer($hash); 
    
  my $ts = gettimeofday();  
  if($hash->{WaitForAck}){
    if($ts-$hash->{SendTime} > 1){
      Log3 $hash, 2,
        "ZWave_ProcessSendStack: timeout sending message -> trigger resend";
      $hash->{SendRetrys}++;
      $hash->{WaitForAck} = 0;

    } else {
      Log3 $hash, 5, "ZWave_ProcessSendStack: waiting for ACK -> check again";
      InternalTimer($ts+1, "ZWave_ProcessSendStack", $hash, 0);
      return;

    }
}

  if($hash->{SendRetrys} > $hash->{MaxSendRetrys}){
    Log3 $hash, 1,
        "ZWave_ProcessSendStack: max send retrys reached -> cancel sending";
    shift @{$hash->{SendStack}};
    $hash->{WaitForAck} = 0;
    $hash->{SendRetrys} = 0;
    $hash->{MaxSendRetrys} = 3;
  }
  
  return if(!@{$hash->{SendStack}} || $hash->{WaitForAck});
  
  my $msg = $hash->{SendStack}->[0];
  Log3 $hash, 5, "ZWave_ProcessSendStack: sending msg ".$msg;

  DevIo_SimpleWrite($hash, $msg, 1);
  $hash->{WaitForAck} = 1;
  $hash->{SendTime} = $ts;
  InternalTimer($ts+1, "ZWave_ProcessSendStack", $hash, 0);
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
ZWDongle_Read($@)
{
  my ($hash, $local, $regexp) = @_;

  my $buf = (defined($local) ? $local : DevIo_SimpleRead($hash));
  return "" if(!defined($buf));

  my $name = $hash->{NAME};

  $buf = unpack('H*', $buf);
  # The dongle looses data over USB for some commands(?), and dropping the old
  # buffer after a timeout is my only idea of solving this problem.
  my $ts   = gettimeofday();
  my $data = ($hash->{ReadTime} && $ts-$hash->{ReadTime} > 1) ?
                        $buf : $hash->{PARTIAL}.$buf;
  $hash->{ReadTime} = $ts;


  Log3 $name, 5, "ZWDongle RAW buffer: $data";

  my $msg;
  while(length($data) > 0) {
    my $fb = substr($data, 0, 2);

    if($fb eq "06") {   # ACK
      Log3 $name, 5, "$name: ACK received";
      $data = substr($data, 2);
      # ZWDongle messages are removed if ZW_SEND_DATA:OK is received
      if(!@{$hash->{SendStack}} || $hash->{SendStack}->[0] !~ m/^01....13/) {
        shift @{$hash->{SendStack}};
        $hash->{WaitForAck} = 0;
        $hash->{SendRetrys} = 0;
        $hash->{MaxSendRetrys} = 3;
      }
      next;
    }

    if($fb eq "15") {   # NACK
      Log3 $name, 4, "$name: NACK received, resending the message";
      $hash->{WaitForAck} = 0;
      $hash->{SendRetrys}++;
      $data = substr($data, 2);
      next;
    }

    if($fb eq "18") {   # CAN
      Log3 $name, 4, "$name: CAN received, resending the message";
      $hash->{WaitForAck} = 0;
      $hash->{SendRetrys}++;
      $hash->{MaxSendRetrys}++ if($hash->{MaxSendRetrys}<7);
      $data = substr($data, 2);
      next;
    }

    if($fb ne "01") {   # SOF
      Log3 $name, 1, "$name: SOF missing (got $fb instead of 01)";
      if(++$hash->{nrNAck} < 5){
        Log3 $name, 5, "ZWDongle_Read SOF Error -> sending NACK";
        DevIo_SimpleWrite($hash, "15", 1);         # Send NACK
      }
      $data="";
      last;
    }

    my $len = substr($data, 2, 2);
    my $l = hex($len)*2;
    last if(!$l || length($data) < $l+4);       # Message not yet complete

    $msg = substr($data, 4, $l-2);
    my $rcs  = substr($data, $l+2, 2);          # Received Checksum
    $data = substr($data, $l+4);

    my $ccs = ZWDongle_CheckSum("$len$msg");    # Computed Checksum
    if($rcs ne $ccs) {
      Log3 $name, 1,
           "$name: wrong checksum: received $rcs, computed $ccs for $len$msg";
      if(++$hash->{nrNAck} < 5) {
        Log3 $name, 5, "ZWDongle_Read wrong checksum -> sending NACK";
        DevIo_SimpleWrite($hash, "15", 1);
      }
      $msg = undef;
      $data="";
      next;
    }
    $hash->{nrNAck} = 0;
    Log3 $name, 5, "ZWDongle_Read -> sending ACK";
    DevIo_SimpleWrite($hash, "06", 1);          # Send ACK
    Log3 $name, 5, "ZWDongle_Read $name: processing $msg";
    
    # SEND_DATA OK: remove message from SendStack. TODO: check the callbackId
    if($msg =~ m/^0013..00/ ){
      Log3 $name, 5,
        "ZWDongle_Read $name: ZW_SEND_DATA:OK received -> removing message";
      shift @{$hash->{SendStack}};
      $hash->{WaitForAck} = 0;
      $hash->{SendRetrys} = 0;
      $hash->{MaxSendRetrys} = 3;    
    }
    
    last if(defined($local) && (!defined($regexp) || ($msg =~ m/$regexp/)));
    $hash->{PARTIAL} = $data;	 # Recursive call by ZWave get, Forum #37418
    ZWDongle_Parse($hash, $name, $msg);
    $data = $hash->{PARTIAL};
    $msg = undef;
  }

  $hash->{PARTIAL} = $data;
  
  # trigger sending of next message
  ZWave_ProcessSendStack($hash) if(length($data) == 0);
  
  if(defined($local)){
    Log3 $name, 5, "ZWDongle_Read returning local msg ".
        ($msg ? $msg:"undef")." hash PARTIAL: ".$hash->{PARTIAL};
    return $msg;
  }
  return undef;
}

#####################################
# This is a direct read for commands like get
sub
ZWDongle_ReadAnswer($$$)
{
  my ($hash, $arg, $regexp) = @_;
  return ("No FD (dummy device?)", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));
  my $to = ($hash->{RA_Timeout} ? $hash->{RA_Timeout} : 3);
  Log3 $hash, 4, "ZWDongle_ReadAnswer arg:$arg regexp:".($regexp ? $regexp:"");

  for(;;) {

    my $buf;
    if($^O =~ m/Win/ && $hash->{USBDev}) {
      $hash->{USBDev}->read_const_time($to*1000); # set timeout (ms)
      # Read anstatt input sonst funzt read_const_time nicht.
      $buf = $hash->{USBDev}->read(999);
      return ("Timeout reading answer for get $arg", undef)
        if(length($buf) == 0);

    } else {
      if(!$hash->{FD}) {
        Log3 $hash, 1, "ZWDongle_ReadAnswer: device lost";
        return ("Device lost when reading answer for get $arg", undef);
      }

      my $rin = '';
      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        my $err = $!;
        Log3 $hash, 5, "ZWDongle_ReadAnswer: nfound < 0 / err:$err";
        next if ($err == EAGAIN() || $err == EINTR() || $err == 0);
        DevIo_Disconnected($hash);
        return("ZWDongle_ReadAnswer $arg: $err", undef);
      }

      if($nfound == 0){
        Log3 $hash, 5, "ZWDongle_ReadAnswer: select timeout";
        return ("Timeout reading answer for get $arg", undef);
      }

      $buf = DevIo_SimpleRead($hash);
      if(!defined($buf)){
        Log3 $hash, 1,"ZWDongle_ReadAnswer: no data read";
        return ("No data", undef);
      }
      Log3 $hash, 5, "ZWDongle_ReadAnswer: read ".length($buf)." bytes";
    }

    my $ret = ZWDongle_Read($hash, $buf, $regexp);
    if(defined($ret)){
      Log3 $hash, 5, "ZWDongle_ReadAnswer: returning $ret";
      return (undef, $ret);
    }
  }
}

sub
ZWDongle_Parse($$$)
{
  my ($hash, $name, $rmsg) = @_;

  if(!defined($hash->{STATE}) || $hash->{STATE} ne "Initialized"){
    Log3 $hash, 4,"ZWDongle_Parse dongle not initialized";
    return;
  }

  $hash->{"${name}_MSGCNT"}++;
  $hash->{"${name}_TIME"} = TimeNow();
  $hash->{RAWMSG} = $rmsg;

  my %addvals = (RAWMSG => $rmsg);

  Dispatch($hash, $rmsg, \%addvals);
}

#####################################
sub
ZWDongle_Attr($$$$)
{
  my ($cmd, $name, $attr, $value) = @_;
  my $hash = $defs{$name};
  
  if($attr eq "disable") {
    if($cmd eq "set" && ($value || !defined($value))) {
      DevIo_CloseDev($hash) if(!AttrVal($name,"dummy",undef));
      $hash->{STATE} = "disabled";

    } else {
      if(AttrVal($name,"dummy",undef)) {
        $hash->{STATE} = "dummy";
        return;
      }
      DevIo_OpenDev($hash, 0, "ZWDongle_DoInit");

    }

  } elsif($attr eq "homeId") {
    $hash->{homeId} = $value;

  } elsif($attr eq "networkKey") {
    if(!$value || $value !~ m/^[0-9A-F]{32}$/i) {
      return "attr $name networkKey: not a hex string with a length of 32";
    }
    return;
  }

  return undef;  
  
}

#####################################
sub
ZWDongle_Ready($)
{
  my ($hash) = @_;

  return undef if (IsDisabled($hash->{NAME}));

  return DevIo_OpenDev($hash, 1, "ZWDongle_DoInit")
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  if($po) {
    my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
    return ($InBytes>0);
  }
  return 0;
}

1;

=pod
=begin html

<a name="ZWDongle"></a>
<h3>ZWDongle</h3>
<ul>
  This module serves a ZWave dongle, which is attached via USB or TCP/IP, and
  enables the use of ZWave devices (see also the <a href="#ZWave">ZWave</a>
  module). It was tested wit a Goodway WD6001, but since the protocol is
  standardized, it should work with other devices too. A notable exception is
  the USB device from Merten.
  <br><br>
  <a name="ZWDongledefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ZWDongle &lt;device&gt;</code>
  <br>
  <br>
  Upon initial connection the module will get the homeId of the attached
  device. Since the DevIo module is used to open the device, you can also use
  devices connected via  TCP/IP. See <a href="#CULdefine">this</a> paragraph on
  device naming details.
  <br>
  Example:
  <ul>
    <code>define zwdongle_1 ZWDongle /dev/cu.PL2303-000014FA@115200</code><br>
  </ul>
  </ul>
  <br>

  <a name="ZWDongleset"></a>
  <b>Set</b>
  <ul>

  <li>addNode [nwOn|on|off]<br>
    Activate (or deactivate) inclusion mode. The controller (i.e. the dongle)
    will accept inclusion (i.e. pairing/learning) requests only while in this
    mode. After activating inclusion mode usually you have to press a switch
    three times within 1.5 seconds on the node to be included into the network
    of the controller. If autocreate is active, a fhem device will be created
    after inclusion. "on" activates standard inclusion. "nwOn" activates network 
    wide inclusion (only SDK 4.5-4.9, SDK 6.x and above).</li>

  <li>removeNode [nwOn|on|off]<br>
    Activate (or deactivate) exclusion mode. "on" activates standard exclusion. 
    "nwOn" activates network wide exclusion (only SDK 4.5-4.9, SDK 6.x and above). 
    Note: the corresponding fhem device have to be deleted manually.</li>

  <li>createNode id<br>
    Request the class information for the specified node, and create a fhem
    device upon reception of the answer. Used for previously included nodes,
    see the nodeList get command below.</li>

  <li>neighborUpdate<br>
    Requests controller to update his routing table which is based on
    slave's neighbor list. The update may take significant time to complete.
    With the event "done" or "failed" ZWDongle will notify the end of the
    update process.  To read node's neighbor list see neighborList get
    below.</li>

  <li>reopen<br>
    First close and then open the device. Used for debugging purposes.
    </li>

  </ul>
  <br>

  <a name="ZWDongleget"></a>
  <b>Get</b>
  <ul>
  <li>nodeList<br>
    return the list of included nodeIds. Can be used to recreate fhem-nodes
    with the createNode command.</li>

  <li>homeId<br>
    return the six hex-digit homeId of the controller.</li>

  <li>caps, ctrlCaps, version<br>
    return different controller specific information. Needed by developers
    only.  </li>

  <li>nodeInfo<br>
    return node specific information. Needed by developers only.</li>

  <li>neighborList id<br>
    returns the list of neighbor nodeIds of specified node.
    Provides insights to actual network topology.
    List includes dead links and non-routing neighbors</li>

  <li>random N<br>
    request N random bytes from the controller.
    </li>

  <li>raw<br>
    Send raw data to the controller. Developer only.</li>
  </ul>
  <br>

  <a name="ZWDongleattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#model">model</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#homeId">homeId</a><br>
      Stores the homeId of the dongle. Is a workaround for some buggy dongles,
      wich sometimes report a wrong/nonexisten homeId (Forum #35126)</li>
  </ul>
  <br>

  <a name="ZWDongleevents"></a>
  <b>Generated events:</b>
  <ul>
  <li>ZW_ADD_NODE_TO_NETWORK [learnReady|nodeFound|controller|done|failed]
    </li>
  <li>ZW_REMOVE_NODE_FROM_NETWORK 
                        [learnReady|nodeFound|slave|controller|done|failed]
    </li>
  <li>UNDEFINED ZWave_${type6}_$id ZWave $homeId $id $classes"
    </li>
  <li>ZW_REQUEST_NODE_NEIGHBOR_UPDATE [started|done|failed]
    </li>
  </ul>

</ul>


=end html
=cut
