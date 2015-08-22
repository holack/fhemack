##############################################
# $Id: 00_TCM.pm 8451 2015-04-18 19:41:07Z klaus-schauer $

# by r.koenig at koeniglich.de
#
# This modules handles the communication with a TCM 120 or TCM 310 / TCM 400J EnOcean
# transceiver chip. As the protocols are radically different, this is actually 2
# drivers in one.
# See also:
#  TCM_120_User_Manual_V1.53_02.pdf
#  EnOcean Serial Protocol 3 (ESP3) (for the TCM 310, TCM 400J)

# TODO:
# Check BSC Temp
# Check Stick Temp
# Check Stick WriteRadio
# Check Stick RSS

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday usleep);
if( $^O =~ /Win/ ) {
  require Win32::SerialPort;
} else {
  require Device::SerialPort;
}
sub TCM_Read($);
sub TCM_ReadAnswer($$);
sub TCM_Ready($);
sub TCM_Write($$$);

sub TCM_Parse120($$$);
sub TCM_Parse310($$$);
sub TCM_CRC8($);
sub TCM_CSUM($);

sub
TCM_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "TCM_Read";
  $hash->{WriteFn} = "TCM_Write";
  $hash->{ReadyFn} = "TCM_Ready";
  $hash->{Clients} = ":EnOcean:";
  my %matchList= (
    "1:EnOcean"   => "^EnOcean:",
  );
  $hash->{MatchList} = \%matchList;

# Normal devices
  $hash->{DefFn}    = "TCM_Define";
  $hash->{UndefFn}  = "TCM_Undef";
  $hash->{GetFn}    = "TCM_Get";
  $hash->{SetFn}    = "TCM_Set";
  $hash->{NotifyFn} = "TCM_Notify";
  $hash->{AttrFn}   = "TCM_Attr";
  $hash->{AttrList} = "baseID blockSenderID:own,no comType:TCM,RS485 do_not_notify:1,0 " .
                      "dummy:1,0 learningMode:always,demand,nearfield " .
                      "sendInterval:0,25,40,50,100,150,200,250";
}

# Define
sub
TCM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $a[0];
  my $model = $a[2];

  return "TCM: wrong syntax, correct is: define <name> TCM [ESP2|ESP3] ".
                        "{devicename[\@baudrate]|ip:port|none}"
    if(@a != 4 || $model !~ m/^(ESP2|ESP3|120|310)$/);

  $hash->{NOTIFYDEV} = "global";
  DevIo_CloseDev($hash);
  my $dev  = $a[3];
  $hash->{DeviceName} = $dev;
  # old model names replaced
  $model = "ESP2" if ($model eq "120");
  $model = "ESP3" if ($model eq "310");
  $hash->{MODEL} = $model;
  $hash->{BaseID} = "00000000";
  $hash->{LastID} = "00000000";
  if($dev eq "none") {
    Log3 undef, 1, "TCM $name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  my $ret = DevIo_OpenDev($hash, 0, undef);
  return $ret;
}

# Write
# Input is header and data (HEX), without CRC
sub
TCM_Write($$$)
{
  my ($hash,$fn,$msg) = @_;
  my $name = $hash->{NAME};

  return if(!defined($fn));

  my $bstring;
  if($hash->{MODEL} eq "ESP2") {
    # TCM 120 (ESP2)
    if (!$fn) {
      # command with ESP2 format
      $bstring = $msg;
    } else {
      # command with ESP3 format
      my $packetType = hex(substr($fn, 6, 2));
      if ($packetType != 1) {
        Log3 $name, 1, "TCM $name Packet Type not supported.";
        return;
      }
      my $odataLen = hex(substr($fn, 4, 2));
      if ($odataLen != 0) {
        Log3 $name, 1, "TCM $name Radio Telegram with optional Data not supported.";
        return;
      }
      #my $mdataLen = hex(substr($fn, 0, 4));
      my $rorg = substr ($msg, 0, 2);
      # translate the RORG to ORG
      my %rorgmap = ("F6"=>"05",
                     "D5"=>"06",
                     "A5"=>"07",
                    );
      if($rorgmap{$rorg}) {
        $rorg = $rorgmap{$rorg};
      } else {
        Log3 $name, 1, "TCM $name unknown RORG mapping for $rorg";
      }
      if ($rorg eq "05" || $rorg eq "06") {
        $bstring = "6B" . $rorg . substr ($msg, 2, 2) . "000000" . substr ($msg, 4);
      } else {
        $bstring = "6B" . $rorg . substr ($msg, 2);
      }
    }
    $bstring = "A55A" . $bstring . TCM_CSUM($bstring);
    Log3 $name, 5, "TCM $name sending ESP2: $bstring";
  } else {
    # TCM 310 (ESP3)
    $bstring = "55" . $fn . TCM_CRC8($fn) . $msg . TCM_CRC8($msg);
    Log3 $name, 5, "TCM $name sending ESP3: $bstring";
  }
  DevIo_SimpleWrite($hash, $bstring, 1);
  # next commands will be sent with a delay
  usleep(int(AttrVal($name, "sendInterval", 100)) * 1000);
}

# ESP2 CRC
# Used in the TCM120
sub
TCM_CSUM($)
{
  my $msg = shift;
  my $ml = length($msg);

  my @data;
  for(my $i = 0; $i < $ml; $i += 2) {
    push(@data, ord(pack('H*', substr($msg, $i, 2))));
  }
  my $sum = 0;
  map { $sum += $_; } @data;
  return sprintf("%02X", $sum & 0xFF);
}

# ESP3 CRC-Table
my @u8CRC8Table = (
  0x00, 0x07, 0x0e, 0x09, 0x1c, 0x1b, 0x12, 0x15, 0x38, 0x3f, 0x36, 0x31, 0x24,
  0x23, 0x2a, 0x2d, 0x70, 0x77, 0x7e, 0x79, 0x6c, 0x6b, 0x62, 0x65, 0x48, 0x4f,
  0x46, 0x41, 0x54, 0x53, 0x5a, 0x5d, 0xe0, 0xe7, 0xee, 0xe9, 0xfc, 0xfb, 0xf2,
  0xf5, 0xd8, 0xdf, 0xd6, 0xd1, 0xc4, 0xc3, 0xca, 0xcd, 0x90, 0x97, 0x9e, 0x99,
  0x8c, 0x8b, 0x82, 0x85, 0xa8, 0xaf, 0xa6, 0xa1, 0xb4, 0xb3, 0xba, 0xbd, 0xc7,
  0xc0, 0xc9, 0xce, 0xdb, 0xdc, 0xd5, 0xd2, 0xff, 0xf8, 0xf1, 0xf6, 0xe3, 0xe4,
  0xed, 0xea, 0xb7, 0xb0, 0xb9, 0xbe, 0xab, 0xac, 0xa5, 0xa2, 0x8f, 0x88, 0x81,
  0x86, 0x93, 0x94, 0x9d, 0x9a, 0x27, 0x20, 0x29, 0x2e, 0x3b, 0x3c, 0x35, 0x32,
  0x1f, 0x18, 0x11, 0x16, 0x03, 0x04, 0x0d, 0x0a, 0x57, 0x50, 0x59, 0x5e, 0x4b,
  0x4c, 0x45, 0x42, 0x6f, 0x68, 0x61, 0x66, 0x73, 0x74, 0x7d, 0x7a, 0x89, 0x8e,
  0x87, 0x80, 0x95, 0x92, 0x9b, 0x9c, 0xb1, 0xb6, 0xbf, 0xb8, 0xad, 0xaa, 0xa3,
  0xa4, 0xf9, 0xfe, 0xf7, 0xf0, 0xe5, 0xe2, 0xeb, 0xec, 0xc1, 0xc6, 0xcf, 0xc8,
  0xdd, 0xda, 0xd3, 0xd4, 0x69, 0x6e, 0x67, 0x60, 0x75, 0x72, 0x7b, 0x7c, 0x51,
  0x56, 0x5f, 0x58, 0x4d, 0x4a, 0x43, 0x44, 0x19, 0x1e, 0x17, 0x10, 0x05, 0x02,
  0x0b, 0x0c, 0x21, 0x26, 0x2f, 0x28, 0x3d, 0x3a, 0x33, 0x34, 0x4e, 0x49, 0x40,
  0x47, 0x52, 0x55, 0x5c, 0x5b, 0x76, 0x71, 0x78, 0x7f, 0x6A, 0x6d, 0x64, 0x63,
  0x3e, 0x39, 0x30, 0x37, 0x22, 0x25, 0x2c, 0x2b, 0x06, 0x01, 0x08, 0x0f, 0x1a,
  0x1d, 0x14, 0x13, 0xae, 0xa9, 0xa0, 0xa7, 0xb2, 0xb5, 0xbc, 0xbb, 0x96, 0x91,
  0x98, 0x9f, 0x8a, 0x8D, 0x84, 0x83, 0xde, 0xd9, 0xd0, 0xd7, 0xc2, 0xc5, 0xcc,
  0xcb, 0xe6, 0xe1, 0xe8, 0xef, 0xfa, 0xfd, 0xf4, 0xf3 );

# ESP3 CRC
# Used in the TCM310
sub
TCM_CRC8($)
{
  my $msg = shift;
  my $ml = length($msg);

  my @data;
  for(my $i = 0; $i < $ml; $i += 2) {
    push(@data, ord(pack('H*', substr($msg, $i, 2))));
  }
  my $crc = 0;
  map { $crc = $u8CRC8Table[$crc ^ $_]; } @data;
  return sprintf("%02X", $crc);
}

# Read
# called from the global loop, when the select for hash->{FD} reports data
sub
TCM_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));

  my $name = $hash->{NAME};
  my $blockSenderID = AttrVal($name, "blockSenderID", "own");
  my $baseID = hex $hash->{BaseID};
  my $lastID = hex $hash->{LastID};

  my $data = $hash->{PARTIAL} . uc(unpack('H*', $buf));
  Log3 $name, 5, "TCM $name RAW: $data";

  if($hash->{MODEL} eq "ESP2") {
    # TCM 120

    while($data =~ m/^A55A(.B.{20})(..)/) {
      my ($net, $crc) = ($1, $2);
      my $mycrc = TCM_CSUM($net);
      my $rest = substr($data, 28);

      if($crc ne $mycrc) {
        Log3 $name, 2, "TCM $name wrong checksum: got $crc, computed $mycrc" ;
        $data = $rest;
        next;
      }

      if($net =~ m/^0B(..)(........)(........)(..)/) {
        # Receive Radio Telegram (RRT)
        my ($org, $d1,$id,$status) = ($1, $2, $3, $4);
        my $packetType = 1;
        # Re-translate the ORG to RadioORG / TCM310 equivalent
        my %orgmap = ("05"=>"F6", "06"=>"D5", "07"=>"A5", );
        if($orgmap{$org}) {
          $org = $orgmap{$org};
        } else {
          Log3 undef, 2, "TCM unknown ORG mapping for $org";
        }
        if ($org ne "A5") {
          # extract db_0
          $d1 = substr($d1, 0, 2);
        }
        if ($blockSenderID eq "own" && (hex $id) >= $baseID && (hex $id) <= $lastID) {
          Log3 $name, 4, "TCM $name Telegram from $id blocked.";
        } else {
          Dispatch($hash, "EnOcean:$packetType:$org:$d1:$id:$status:01FFFFFFFF0000", undef);
        }

      } else {
        # Receive Message Telegram (RMT)
        my $msg=TCM_Parse120($hash, $net, 1);
        if (($msg eq 'OK') && ($net =~ m/^8B(..)(........)(........)(..)/)){
          my ($org, $d1,$id,$status) = ($1, $2, $3, $4);
          my $packetType = 1;
          # Re-translate the ORG to RadioORG / TCM310 equivalent
          my %orgmap = ("05"=>"F6", "06"=>"D5", "07"=>"A5", );
          if($orgmap{$org}) {
            $org = $orgmap{$org};
          } else {
            Log3 undef, 2, "TCM unknown ORG mapping for $org";
          }
          if ($org ne "A5") {
            # extract db_0
            $d1 = substr($d1, 0, 2);
          }
          if ($blockSenderID eq "own" && (hex $id) >= $baseID && (hex $id) <= $lastID) {
            Log3 $name, 4, "TCM $name Telegram from $id blocked.";
          } else {
            Dispatch($hash, "EnOcean:$packetType:$org:$d1:$id:$status:01FFFFFFFF0000", undef);
          }
         }
      }
      $data = $rest;
    }

    if(length($data) >= 4) {
      $data =~ s/.*A55A/A55A/ if($data !~ m/^A55A/);
      $data = "" if($data !~ m/^A55A/);
    }

  } else {
    # TCM310 / ESP3

    while($data =~ m/^55(....)(..)(..)(..)/) {
      my ($l1, $l2, $packetType, $crc) = (hex($1), hex($2), hex($3), $4);

      my $tlen = 2*(7+$l1+$l2);
      last if(length($data) < $tlen);

      my $rest = substr($data, $tlen);
      $data = substr($data, 0, $tlen);

      my $hdr = substr($data, 2, 8);
      my $mdata = substr($data, 12, $l1*2);
      my $odata = substr($data, 12+$l1*2, $l2*2);

      my $mycrc = TCM_CRC8($hdr);
      if($mycrc ne $crc) {
        Log3 $name, 2, "TCM $name wrong header checksum: got $crc, computed $mycrc" ;
        $data = $rest;
        next;
      }
      $mycrc = TCM_CRC8($mdata . $odata);
      $crc  = substr($data, -2);
      if($mycrc ne $crc) {
        Log3 $name, 2, "TCM $name wrong data checksum: got $crc, computed $mycrc" ;
        $data = $rest;
        next;
      }

      if($packetType == 1) {
        # packet type RADIO
        $mdata =~ m/^(..)(.*)(........)(..)$/;
        my ($org, $d1, $id, $status) = ($1,$2,$3,$4);
        my $repeatingCounter = hex substr($status, 1, 1);
        $odata =~ m/^(..)(........)(..)(..)$/;
        my ($RSSI, $receivingQuality) = (hex($3), "excellent");
        if ($RSSI > 87) {
          $receivingQuality = "bad";
        } elsif ($RSSI > 75) {
          $receivingQuality = "good";
        }
        my %addvals = (
          PacketType       => $packetType,
          SubTelNum        => hex($1),
          DestinationID    => $2,
          RSSI             => -$RSSI,
          ReceivingQuality => $receivingQuality,
          RepeatingCounter => $repeatingCounter,
        );
        $hash->{RSSI} = -$RSSI;
        
        if ($blockSenderID eq "own" && (hex $id) >= $baseID && (hex $id) <= $lastID) {
          Log3 $name, 4, "TCM $name Telegram from $id blocked.";
        } else {
          Dispatch($hash, "EnOcean:$packetType:$org:$d1:$id:$status:$odata", \%addvals);
        }

      } elsif($packetType == 2) {
        # packet type RESPONSE
        my $rc = substr($mdata, 0, 2);
        my %codes = (
          "00" => "OK",
          "01" => "ERROR",
          "02" => "NOT_SUPPORTED",
          "03" => "WRONG_PARAM",
          "04" => "OPERATION_DENIED",
          "82" => "FLASH_HW_ERROR",
          "90" => "BASEID_OUT_OF_RANGE",
          "91" => "BASEID_MAX_REACHED",
        );
        $rc = $codes{$rc} if($codes{$rc});
        Log3 ($name, ($rc eq "OK") ? 5 : 2, "TCM $name RESPONSE: $rc");

      } elsif($packetType == 3) {
        # packet type RADIO_SUB_TEL
        Log3 $name, 2, "TCM $name packet type RADIO_SUB_TEL not supported: $data";

      } elsif($packetType == 4) {
        # packet type EVENT
        Log3 $name, 2, "TCM $name packet type EVENT not supported: $data";

      } elsif($packetType == 5) {
        # packet type COMMON_COMMAND
        Log3 $name, 2, "TCM $name packet type COMMON_COMMAND not supported: $data";

      } elsif($packetType == 6) {
        # packet type SMART_ACK_COMMAND
        Log3 $name, 2, "TCM $name packet type SMART_ACK_COMMAND not supported: $data";

      } elsif($packetType == 7) {
        # packet type REMOTE_MAN_COMMAND
        #Log3 $name, 2, "TCM: $name packet type REMOTE_MAN_COMMAND not supported: $data";
        $mdata =~ m/^(....)(....)(.*)$/;
        my ($function, $manufID, $messageData) = ($1,$2,$3);
        $odata =~ m/^(........)(........)(..)(..)$/;
        my ($RSSI, $receivingQuality) = ($3, "excellent");
        if (hex($RSSI) > 87) {
          $receivingQuality = "bad";
        } elsif (hex($RSSI) > 75) {
          $receivingQuality = "good";
        }
        my %addvals = (
          PacketType       => $packetType,
          DestinationID    => $1,
          RSSI             => -hex($RSSI),
          ReceivingQuality => $receivingQuality,
        );
        $hash->{RSSI} = -hex($RSSI);
        $packetType = sprintf "%01X", $packetType;
        
        if ($blockSenderID eq "own" && (hex $2) >= $baseID && (hex $2) <= $lastID) {
          Log3 $name, 4, "TCM $name Telegram from $2 blocked.";
        } else {
          #EnOcean:PacketType:RORG:MessageData:SourceID:DestinationID:FunctionNumber:ManufacturerID:RSSI:Delay
          Dispatch($hash, "EnOcean:$packetType:C5:$messageData:$2:$1:$function:$manufID:$RSSI:$4", \%addvals);
        }

      } elsif($packetType == 9) {
        # packet type RADIO_MESSAGE
        Log3 $name, 2, "TCM: $name packet type RADIO_MESSAGE not supported: $data";

      } elsif($packetType == 10) {
        # packet type RADIO_ADVANCED
        Log3 $name, 2, "TCM: $name packet type RADIO_ADVANCED not supported: $data";

      } else {
        Log3 $name, 2, "TCM $name unknown packet type $packetType: $data";

      }

      $data = $rest;
    }

    if(length($data) >= 4) {
      $data =~ s/.*55/55/ if($data !~ m/^55/);
      $data = "" if($data !~ m/^55/);
    }

  }
  $hash->{PARTIAL} = $data;
}

# Parse Table TCM 120
my %parsetbl120 = (
  "8B05" => { msg=>"OK" },
  "8B06" => { msg=>"OK" },
  "8B07" => { msg=>"OK" },
  "8B08" => { msg=>"ERR_SYNTAX_H_SEQ" },
  "8B09" => { msg=>"ERR_SYNTAX_LENGTH" },
  "8B0A" => { msg=>"ERR_SYNTAX_CHKSUM" },
  "8B0B" => { msg=>"ERR_SYNTAX_ORG" },
  "8B0C" => { msg=>"ERR_MODEM_DUP_ID" },
  "8B19" => { msg=>"ERR" },
  "8B1A" => { msg=>"ERR_IDRANGE" },
  "8B22" => { msg=>"ERR_TX_IDRANGE" },
  "8B28" => { msg=>"ERR_MODEM_NOTWANTEDACK" },
  "8B29" => { msg=>"ERR_MODEM_NOTACK" },
  "8B58" => { msg=>"OK" },
  "8B8C" => { msg=>"INF_SW_VER", expr=>'"$a[2].$a[3].$a[4].$a[5]"' },
  "8B88" => { msg=>"INF_RX_SENSIVITY", expr=>'$a[2] ? "High (01)":"Low (00)"' },
  "8B89" => { msg=>"INFO", expr=>'substr($rawstr,2,9)' },
  "8B98" => { msg=>"INF_IDBASE",
              expr=>'sprintf("%02x%02x%02x%02x", $a[2], $a[3], $a[4], $a[5])' },
  "8BA8" => { msg=>"INF_MODEM_STATUS",
              expr=>'sprintf("%s, ID:%02x%02x", $a[2]?"on":"off", $a[3], $a[4])' },
);

# Parse TCM 120
sub
TCM_Parse120($$$)
{
  my ($hash,$rawmsg,$ret) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "TCM $name Parse $rawmsg";
  my $msg = "";
  my $cmd = $parsetbl120{substr($rawmsg, 0, 4)};
  if(!$cmd) {
    $msg ="Unknown command: $rawmsg";
  } else {
    if($cmd->{expr}) {
      $msg = $cmd->{msg}." " if(!$ret);
      my $rawstr = pack('H*', $rawmsg);
      $rawstr =~ s/[\r\n]//g;
      my @a = map { ord($_) } split("", $rawstr);
      $msg .= eval $cmd->{expr};
    } else {
      return "" if($cmd ->{msg} eq "OK" && !$ret); # SKIP Ok
      $msg = $cmd->{msg};
    }
  }
  Log3 $name, 2, "TCM $name RESPONSE: $msg" if(!$ret);
  return $msg;
}

# Parse Table TCM 310
my %rc310 = (
  "00" => "OK",
  "01" => "ERROR",
  "02" => "NOT_SUPPORTED",
  "03" => "WRONG_PARAM",
  "04" => "OPERATION_DENIED",
  "82" => "FLASH_HW_ERROR",
  "90" => "BASEID_OUT_OF_RANGE",
  "91" => "BASEID_MAX_REACHED",
);

# Parse TCM 310
sub
TCM_Parse310($$$)
{
  my ($hash,$rawmsg,$ptr) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "TCM Parse $rawmsg";
  my $rc = substr($rawmsg, 0, 2);
  my $msg = "";
  if($rc ne "00") {
    $msg = $rc310{$rc};
    $msg = "Unknown return code $rc" if(!$msg);
  } else {
    my @ans;
    foreach my $k (sort keys %{$ptr}) {
      next if($k eq "cmd" || $k eq "arg");
      my ($off, $len, $type) = split(",", $ptr->{$k});
      my $data = substr($rawmsg, $off*2, $len*2);
      if($type && $type eq "STR") {
        $data = pack('H*', $data);
        ####
        # remove trailing 0x00 
        #$data =~ s/[^A-Za-z0-9#\.\-_]//g;
        $data =~ tr/A-Za-z0-9#.-_//cd;
      }
      push @ans, "$k: $data";
    }
    $msg = join(" ", @ans);
  }
  if ($msg eq "") {
    Log3 $name, 2, "TCM $name RESPONSE: OK";
  } else {
    Log3 $name, 2, "TCM $name RESPONSE: $msg";
  }
  return $msg;
}

# Ready
sub
TCM_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, undef)
#    if($hash->{STATE} ne "opened");
    if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  return undef if(!$po);
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

# Get commands TCM 120
my %gets120 = (
  "sensitivity"  => "AB48",
  "baseID"       => "AB58",
  "modem_status" => "AB68",
  "version"      => "AB4B",
);

# Get commands TCM 310
my %gets310 = (
  "version"      => {cmd         => "03",
                     APPVersion  => "1,4",
                     APIVersion  => "5,4",
                     ChipID      => "9,4",
                     ChipVersion => "13,4",
                     Desc        => "17,16,STR",},
  "baseID"       => {cmd                  => "08",
                     BaseID               => "1,4",
                     RemainingWriteCycles => "5,1",},
  "repeater"     => {cmd       => "0A",
                     RepEnable => "1,1",
                     RepLevel  => "2,1",},
#  "secureDev"    => {cmd       => "1B01",
#                     SLF   => "1,1",
#                     devID => "2,4",},
  "numSecureDev" => {cmd    => "1D",
                     Number => "1,1",},
);

# Get
sub
TCM_Get($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  return if (AttrVal($name, "comType", "TCM") eq "RS485" || $hash->{DeviceName} eq "none");
  return "\"get $name\" needs one parameter" if(@a != 2);
  my $cmd = $a[1];
  my ($err, $msg);

  if($hash->{MODEL} eq "ESP2") {
    # TCM 120
    my $rawcmd = $gets120{$cmd};
    return "Unknown argument $cmd, choose one of " .
        join(" ", sort keys %gets120) if(!defined($rawcmd));
    Log3 $name, 3, "TCM get $name $cmd";
    $rawcmd .= "000000000000000000";
    TCM_Write($hash, "", $rawcmd);
    ($err, $msg) = TCM_ReadAnswer($hash, "get $cmd");

    $msg = TCM_Parse120($hash, $msg, 1) if(!$err);
  } else {
    # TCM 310
    my $cmdhash = $gets310{$cmd};
    return "Unknown argument $cmd, choose one of " .
        join(" ", sort keys %gets310) if(!defined($cmdhash));
    Log3 $name, 3, "TCM get $name $cmd";
    my $cmdHex = $cmdhash->{cmd};
    TCM_Write($hash, sprintf("%04X0005", length($cmdHex)/2), $cmdHex);
    ($err, $msg) = TCM_ReadAnswer($hash, "get $cmd");

    $msg = TCM_Parse310($hash, $msg, $cmdhash) if(!$err);
  }
  if($err) {
    Log3 undef, 2, "TCM $name $err";
    return $err;
  }
  readingsSingleUpdate($hash, $cmd, $msg, 1);
  return $msg;
}

# RemovePair
sub
TCM_RemovePair($)
{
  my $hash = shift;
  delete($hash->{Teach});
}

# Set commands TCM 120
my %sets120 = (    # Name, Data to send to the CUL, Regexp for the answer
  "teach"        => { cmd => "AB18", arg => "\\d+" },
  "baseID"       => { cmd => "AB18", arg => "FF[8-9A-F][0-9A-F]{5}" },
  "sensitivity"  => { cmd => "AB08", arg => "0[01]" },
  "sleep"        => { cmd => "AB09" },
  "wake"         => { cmd => "" }, # Special
  "reset"        => { cmd => "AB0A" },
  "modem_on"     => { cmd => "AB28", arg => "[0-9A-F]{4}" },
  "modem_off"    => { cmd => "AB2A" },
);

# Set commands TCM 310
my %sets310 = (
  "teach"        => { cmd => "AB18", arg=> "\\d+" },
  "sleep"        => { cmd => "01", arg => "00[0-9A-F]{6}" },
  "reset"        => { cmd => "02" },
  "bist"         => { cmd => "06", BIST_Result => "1,1", },
  "baseID"       => { cmd => "07", arg => "FF[8-9A-F][0-9A-F]{5}" },
  "repeater"     => { cmd => "09", arg => "0[0-1]0[0-2]" },
  "maturity"     => { cmd => "10", arg => "0[0-1]" },
  "subtel"       => { cmd => "11", arg => "0[0-1]" },
  "mode"         => { cmd => "1C", arg => "0[0-1]" },
);

# Set
sub
TCM_Set($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  return if (AttrVal($name, "comType", "TCM") eq "RS485" || $hash->{DeviceName} eq "none");
  return "\"set $name\" needs at least one parameter" if(@a < 2);
  my $cmd = $a[1];
  my $arg = $a[2];
  my ($err, $msg);
  my $chash = ($hash->{MODEL} eq "ESP2" ? \%sets120 : \%sets310);
  my $cmdhash = $chash->{$cmd};
  return "Unknown argument $cmd, choose one of ".join(" ",sort keys %{$chash})
          if(!defined($cmdhash));

  my $cmdHex = $cmdhash->{cmd};
  my $argre = $cmdhash->{arg};
  if($argre) {
    return "Argument needed for set $name $cmd ($argre)" if(!defined($arg));
    return "Argument does not match the regexp ($argre)"
      if($arg !~ m/$argre/i);
    $cmdHex .= $arg;
  }
  Log3 $name, 3, "TCM set $name $cmd $arg";

  if($cmd eq "teach") {
    $hash->{Teach} = 1;
    InternalTimer(gettimeofday()+$arg, "TCM_RemovePair", $hash, 1);
    return;
  }

  if($hash->{MODEL} eq "ESP2") {
    # TCM 120
    if($cmdHex eq "") {            # wake is very special
      DevIo_SimpleWrite($hash, "AA", 1);
      return "";
    }

    $cmdHex .= "0"x(22-length($cmdHex));  # Padding with 0
    TCM_Write($hash, "", $cmdHex);
    ($err, $msg) = TCM_ReadAnswer($hash, "get $cmd");
    $msg = TCM_Parse120($hash, $msg, 1) if(!$err);

  } else {
    # TCM310
    TCM_Write($hash, sprintf("%04X0005", length($cmdHex)/2), $cmdHex);
    ($err, $msg) = TCM_ReadAnswer($hash, "set $cmd");
    $msg = TCM_Parse310($hash, $msg, $cmdhash) if(!$err);

  }
  if($err) {
    Log3 undef, 2, "TCM $name $err";
    return $err;
  }
  
  my @setCmdReadingsUpdate = ("repeater", "maturity", "mode");
  foreach(@setCmdReadingsUpdate) {
    if ($_ eq $cmd && $msg eq "") {
      if ($_ eq "repeater") {
        $arg = "RepEnable: " . substr($arg, 0, 2) . " RepLevel: " . substr($arg, 2, 2);
      }
      readingsSingleUpdate($hash, $cmd, $arg, 1);
    }
  }
  return $msg;
}


# ReadAnswer
sub
TCM_ReadAnswer($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  return ("No FD", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));

  my ($data, $rin, $buf) = ("", "", "");
  my $to = 3;                                         # 3 seconds timeout
  for(;;) {
    if($^O =~ m/Win/ && $hash->{USBDev}) {
      $hash->{USBDev}->read_const_time($to*1000); # set timeout (ms)
      # Read anstatt input sonst funzt read_const_time nicht.
      $buf = $hash->{USBDev}->read(999);
      return ("$name Timeout reading answer for $arg", undef)
        if(length($buf) == 0);

    } else {
      return ("Device lost when reading answer for $arg", undef)
        if(!$hash->{FD});

      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        my $err = $!;
        DevIo_Disconnected($hash);
        return("TCM_ReadAnswer $err", undef);
      }
      return ("Timeout reading answer for $arg", undef)
        if($nfound == 0);
      $buf = DevIo_SimpleRead($hash);
      return ("No data", undef) if(!defined($buf));

    }

    if(defined($buf)) {
      $data .= uc(unpack('H*', $buf));
      Log3 $name, 5, "TCM $name RAW ReadAnswer: $data";

      if($hash->{MODEL} eq "ESP2") {
        # TCM 120
        if(length($data) >= 28) {
          return ("$arg: Bogus answer received: $data", undef)
                if($data !~ m/^A55A(.B.{20})(..)/);
          my ($net, $crc) = ($1, $2);
          my $mycrc = TCM_CSUM($net);
          $hash->{PARTIAL} = substr($data, 28);

          return ("wrong checksum: got $crc, computed $mycrc", undef)
            if($crc ne $mycrc);
          return (undef, $net);
        }

      } else {
        # TCM 310
        if(length($data) >= 14) {
          return ("$arg: Bogus answer received: $data", undef)
                if($data !~ m/^55(....)(..)(..)(..)(.*)(..)$/);
          my ($dlen, $olen, $ptype, $hcrc, $data, $dcrc) = ($1,$2,$3,$4,$5,$6);
          ### ???
          # next if(length($data) < hex($dlen)+hex($olen)+6);
          # next if(length($data) < 2 * hex($dlen) + 2 * hex($olen) + 6);
          next if(length($data) < 2*hex($dlen));
          
          my $myhcrc = TCM_CRC8("$dlen$olen$ptype");
          return ("wrong header checksum: got $hcrc, computed $myhcrc", undef)
            if($hcrc ne $myhcrc);

          my $mydcrc = TCM_CRC8($data);
          return ("wrong data checksum: got $dcrc, computed $mydcrc", undef)
            if($dcrc ne $mydcrc);
          return (undef, $data);
        }

      }
    }
  }
}

sub
TCM_Attr(@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};
  
  if ($attrName eq "blockSenderID") {
    if (!defined $attrVal) {
    
    } elsif ($attrVal !~ m/^(own|no)$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }
    
  } elsif ($attrName eq "baseID") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^[Ff]{2}[\dA-Fa-f]{6}$/) {        
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    } else {
      $hash->{BaseID} = $attrVal;
      $hash->{LastID} = sprintf "%08X", (hex $attrVal) + 127;      
    }

  } elsif ($attrName eq "comType") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^(TCM|RS485)$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "learningMode") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^(always|demand|nearfield)$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "sendInterval") {
    if (!defined $attrVal){
    
    } elsif (($attrVal + 0) < 0 || ($attrVal + 0) > 250) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong or out of range";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  }
  return undef;
}

sub TCM_Notify(@) {
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};
  if ($dev->{NAME} eq "global" && grep (m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}})){
    if ($hash->{STATE} eq "disconnected") {
      Log3 $name, 2, "TCM $name not initialized";
      return undef;
    }
    my $attrVal;
    my $comType = AttrVal($name, "comType", "TCM");
    my $setCmdVal = "";
    my @setCmd = ("set", "reset", $setCmdVal);
    # read and discard receive buffer, modem reset
    if ($hash->{MODEL} eq "ESP2") {
      if ($comType eq "TCM") {
        TCM_ReadAnswer($hash, "set reset");
        TCM_Set($hash, @setCmd);
      }
    } else {
      TCM_ReadAnswer($hash, "set reset");
      TCM_Set($hash, @setCmd);
    }
    # default attributes
    my %setAttrInit;
    if ($comType eq "RS485" || $hash->{DeviceName} eq "none") {
      %setAttrInit = ("sendInterval" => {ESP2 => 100, ESP3 => 0},
                      "learningMode" => {ESP2 => "always", ESP3 => "always"}      
                     );
    }else {
      %setAttrInit = ("sendInterval" => {ESP2 => 100, ESP3 => 0});
    }
    foreach(keys %setAttrInit) {
      $attrVal = AttrVal($name, $_, undef);
      if(!defined $attrVal && defined $setAttrInit{$_}{$hash->{MODEL}}) {
        $attr{$name}{$_} = $setAttrInit{$_}{$hash->{MODEL}};
        Log3 $name, 2, "TCM $name Attribute $_ $setAttrInit{$_}{$hash->{MODEL}} initialized";
      }
    }
    # default transceiver parameter
    if ($comType ne "RS485" && $hash->{DeviceName} ne "none") {
      my %setCmdRestore = ("mode"     => "00",
                           "maturity" => "01",
                           "repeater" => "RepEnable: 00 RepLevel: 00"
                          );
      foreach(keys %setCmdRestore) {
        $setCmdVal = ReadingsVal($name, $_, undef);
        if (defined $setCmdVal) {
          if ($_ eq "repeater") {
            $setCmdVal = substr($setCmdVal, 11, 2) . substr($setCmdVal, 24, 2);
            $setCmdVal = "0000" if ($setCmdVal eq "0001");
          }
          @setCmd = ("set", $_, $setCmdVal);
          TCM_Set($hash, @setCmd);
          Log3 $name, 2, "TCM $name $_ $setCmdVal restored";
        } else {
          if ($hash->{MODEL} eq "ESP2") {
        
          } else {
            if ($_ eq "repeater") {
              $setCmdVal = substr($setCmdRestore{$_}, 11, 2) . substr($setCmdRestore{$_}, 24, 2);
            } else {
              $setCmdVal = $setCmdRestore{$_};
            }
            @setCmd = ("set", $_, $setCmdVal);
            my $msg = TCM_Set($hash, @setCmd);
            Log3 $name, 2, "TCM $name $_ $setCmdVal initialized" if ($msg eq "");
          }
        }
      }
    }
    my $baseID = AttrVal($name, "baseID", undef);
    if (defined($baseID)) {
      $hash->{BaseID} = $baseID;
      $hash->{LastID} = sprintf "%08X", (hex $baseID) + 127;    
    } elsif ($comType ne "RS485" && $hash->{DeviceName} ne "none") {
      my @getBaseID = ("get", "baseID");
      if (TCM_Get($hash, @getBaseID) =~ /[Ff]{2}[\dA-Fa-f]{6}/ ) {
        $hash->{BaseID} = sprintf "%08X", hex $&;
        $hash->{LastID} = sprintf "%08X", (hex $&) + 127;
      } else {
        $hash->{BaseID} = "00000000";
        $hash->{LastID} = "00000000";
      }
    }
    CommandSave(undef, undef);
    readingsSingleUpdate($hash, "state", "initialized", 1);
    Log3 $name, 2, "TCM $name initialized";
  }
  return undef;
}

# Undef
sub
TCM_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log3 $name, $lev, "TCM deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }
  DevIo_CloseDev($hash);
  return undef;
}

1;

=pod
=begin html

<a name="TCM"></a>
<h3>TCM</h3>
<ul>
  The TCM module serves an USB or TCP/IP connected TCM 120 or TCM 310x, TCM 410J
  EnOcean Transceiver module. These are mostly packaged together with a serial to USB
  chip and an antenna, e.g. the BSC BOR contains the TCM 120, the <a
  href="http://www.enocean.com/de/enocean_module/usb-300-oem/">USB 300</a> from
  EnOcean and the EUL from busware contains a TCM 310. See also the datasheet
  available from <a href="http://www.enocean.com">www.enocean.com</a>.
  <br>
  As the TCM 120 and the TCM 310, TCM 410J speak completely different protocols, this
  module implements 2 drivers in one. It is the "physical" part for the <a
  href="#EnOcean">EnOcean</a> module.<br><br>
  Please note that EnOcean repeaters also send Fhem data telegrams again. Use
  <code>attr &lt;name&gt; <a href="#blockSenderID">blockSenderID</a> own</code>
  to block receiving telegrams with TCM SenderIDs.<br>
  The address range used by your transceiver module, can be found in the
  parameters BaseID and LastID.
  <br><br>
  The transceiver moduls do not always support all commands. The supported range
  of commands depends on the hardware and the firmware version. A firmware update
  is usually not provided.
  <br><br>
  The TCM module enables also a wired connection to Eltako actuators over the
  Eltako RS485 bus in the switchboard or distribution box via Eltako FGW14 RS232-RS485
  gateway modules. These actuators are linked to an associated wireless antenna module
  (FAM14) on the bus. The FAM14 device frequently polls the actuator status of all
  associated devices if the FAM14 operating mode rotary switch is on position 4.
  Therefore, actuator states can be retrieved more reliable, even after any fhem downtime,
  when switch events or actuator confirmations could not have been tracked during the
  downtime. As all actuators are polled approx. every 1-2 seconds, it should be avoided to
  use event-on-update-reading. Use instead either event-on-change-reading or
  event-min-interval.
  The Eltako bus uses the EnOcean Serial Protocol version 2 (ESP2). For this reason,
  a FGW14 can be configured as a ESP2. The attribute <a href="#TCM_comType">comType</a>
  must be set to RS485.<br><br>
  
  <a name="TCMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TCM [ESP2|ESP3] &lt;device&gt;</code> <br>
    <br>
    First you have to specify the type of the EnOcean Transceiver Chip, i.e
    either ESP2 for the TCM 120 or ESP3 for the TCM 310x, TCM 410J, USB 300, USB400J.<br><br>
    <code>device</code> can take the same parameters (@baudrate, @directio,
    TCP/IP, none) like the <a href="#CULdefine">CUL</a>, but you probably have
    to specify the baudrate: the TCM 120 should be opened with 9600 Baud, the
    TCM 310 with 57600 baud. For Eltako FGW14 devices, type has to be set to 120 and 
    the baudrate has to be set to 57600 baud if the FGW14 operating mode
    rotary switch is on position 6.<br><br>
    
    Example:
    <ul><code>
      define BscBor TCM ESP2 /dev/ttyACM0@9600<br>
      define FGW14 TCM ESP2 /dev/ttyS3@57600<br>
      define TCM310 TCM ESP3 /dev/ttyACM0@57600<br>
      define TCM310 TCM ESP3 COM1@57600 (Windows)<br>
    </code></ul>
  </ul>
  <br>

  <a name="TCMset"></a>
  <b>Set</b><br>
  <ul><b>ESP2 (TCM 120)</b><br>
    <li>baseID [FF800000 ... FFFFFF80]<br>
      Set the BaseID.<br>
      Note: The firmware executes this command only up to then times to prevent misuse.</li>
    <li>modem_off<br>
      Deactivates TCM modem functionality</li>
    <li>modem_on [0000 ... FFFF]<br>
      Activates TCM modem functionality and sets the modem ID</li>
    <li>teach &lt;t/s&gt;<br>
      Set Fhem in learning mode, see <a href="#TCM_learningMode">learningMode</a>.<br>
      The command is always required for UTE and to teach-in bidirectional actuators
      e. g. EEP 4BS (RORG A5-20-XX),
      see <a href="#EnOcean_teach-in">Teach-In / Teach-Out</a>.</li>
    <li>reset<br>
      Reset the device</li>
    <li>sensitivity [00|01]<br>
      Set the TCM radio sensitivity: low = 00, high = 01</li>
    <li>sleep<br>
      Enter the energy saving mode</li>
    <li>wake<br>
      Wakes up from sleep mode</li>
    <br>
    For details see the TCM 120 User Manual available from <a href="http://www.enocean.com">www.enocean.com</a>.
  <br><br>
  </ul>
  <ul><b>ESP3 (TCM 310x, TCM 410J, USB 300, USB400J)</b><br>
    <li>baseID [FF800000 ... FFFFFF80]<br>
      Set the BaseID.<br>
      Note: The firmware executes this command only up to then times to prevent misuse.</li>
    <li>bist<br>
      Perform Flash BIST operation (Built-in-self-test).</li>
    <li>maturity [00|01]<br>
      Waiting till end of maturity time before received radio telegrams will transmit:
      radio telegrams are send immediately = 00, after the maturity time is elapsed = 01</li>
    <li>mode [00|01]<br>
      mode = 00: Compatible mode - ERP1 - gateway uses Packet Type 1 to transmit and receive radio telegrams<br>
      mode = 01: Advanced mode � ERP2 - gateway uses Packet Type 10 to transmit and receive radio telegrams
      (for FSK products with advanced protocol)</li>
    <li>teach &lt;t/s&gt;<br>
      Set Fhem in learning mode, see <a href="#TCM_learningMode">learningMode</a>.<br>
      The command is always required for UTE and to teach-in bidirectional actuators
      e. g. EEP 4BS (RORG A5-20-XX)</li>
    <li>reset<br>
      Reset the device</li>
    <li>repeater [0000|0101|0102]<br>
      Set Repeater Level: off = 0000, 1 = 0101, 2 = 0102.</li>
    <li>sleep &lt;t/10 ms&gt; (Range: 00000000 ... 00FFFFFF)<br>
      Enter the energy saving mode</li>
    <li>subtel [00|01]<br>
      Transmitting additional subtelegram info: Enable = 01, Disable = 00</li>
    <br>
    For details see the EnOcean Serial Protocol 3 (ESP3) available from
    <a href="http://www.enocean.com">www.enocean.com</a>.
    <br><br>
  </ul>

  <a name="TCMget"></a>
  <b>Get</b><br>
  <ul><b>TCM 120</b><br>
    <li>baseID<br>
      Get the BaseID. You need this command in order to control EnOcean devices,
      see the <a href="#EnOceandefine">EnOcean</a> paragraph.
      </li>
    <li>modem_status<br>
      Requests the current modem status.</li>
    <li>sensitivity<br>
      Get the TCM radio sensitivity, low = 00, high = 01</li>
    <li>version<br>
      Read the device SW version / HW version, chip-ID, etc.</li>
    <br>
    For details see the TCM 120 User Manual available from <a href="http://www.enocean.com">www.enocean.com</a>.
    <br><br>
  </ul>
  <ul><b>TCM 310</b><br>
    <li>baseID<br>
      Get the BaseID. You need this command in order to control EnOcean devices,
      see the <a href="#EnOceandefine">EnOcean</a> paragraph.</li>
    <li>numSecureDev<br>
      Read number of teached in secure devices.</li>
    <li>repeater<br>
      Read Repeater Level: off = 0000, 1 = 0101, 2 = 0102.</li>
    <li>version<br>
      Read the device SW version / HW version, chip-ID, etc.</li>
    <br>
    For details see the EnOcean Serial Protocol 3 (ESP3) available from
    <a href="http://www.enocean.com">www.enocean.com</a>.
    <br><br>
  </ul>

  <a name="TCMattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="TCM_blockSenderID">blockSenderID</a> &lt;own|no&gt;,
      [blockSenderID] = own is default.<br>
      Block receiving telegrams with a TCM SenderID sent by repeaters.      
      </li>
    <li><a href="#attrdummy">dummy</a></li>
    <li><a name="TCM_baseID">baseID</a> &lt;FF800000 ... FFFFFF80&gt;,
      [baseID] = <none> is default.<br>
      Set Transceiver baseID and override automatic allocation. Use this attribute only if the IODev does not allow automatic allocation.
    </li>
    <li><a name="TCM_comType">comType</a> &lt;TCM|RS485&gt;,
      [comType] = TCM is default.<br>
      Type of communication device
    </li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a name="TCM_learningMode">learningMode</a> &lt;always|demand|nearfield&gt;,
      [learningMode] = demand is default.<br>
      Learning method for automatic setup of EnOcean devices:<br>    
      [learningMode] = always: Teach-In/Teach-Out telegrams always accepted, with the exception of bidirectional devices<br>
      [learningMode] = demand: Teach-In/Teach-Out telegrams accepted if Fhem is in learning mode, see also <code>set &lt;IODev&gt; teach &lt;t/s&gt;</code><br>
      [learningMode] = nearfield: Teach-In/Teach-Out telegrams accepted if Fhem is in learning mode and the signal strength RSSI >= -60 dBm.<be>
    </li>
    <li><a name="TCM_sendInterval">sendInterval</a> &lt;0 ... 250&gt;<br>
      ESP2: [sendInterval] = 100 ms is default.<br>
      ESP3: [sendInterval] = 0 ms is default.<br>
      Smallest interval between two sending telegrams
    </li>
    <li><a href="#verbose">verbose</a></li>
    <br><br>
  </ul>

  <a name="TCMevents"></a>
  <b>Generated events</b>
  <ul>
    <li>baseID &lt;transceiver response&gt;</li>
    <li>maturity 00|01</li>
    <li>modem_status &lt;transceiver response&gt;</li>
    <li>numSecureDev &lt;transceiver response&gt;</li>
    <li>repeater 0000|0101|0102</li>
    <li>sensitivity 00|01</li>
    <li>version &lt;transceiver response&gt;</li>
    <li>state: opend|initialized</li>
    <br><br>
  </ul>
</ul>

=end html
=cut
