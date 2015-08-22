##############################################
# $Id: 10_EnOcean.pm 8474 2015-04-24 17:01:14Z klaus-schauer $

# EnOcean Security in Perl, teach-in, VAES, MAC and message handling
# Copyright: Jan Schneider (timberwolf at tec-observer dot de)
# License: GPL (v2) see http://www.gnu.org/licenses/gpl-2.0.html

package main;

use strict;
use warnings;
my $cryptFunc;
eval "use Crypt::Rijndael";
if ($@) {
  $cryptFunc = 0;  
} else {
  $cryptFunc = 1;
}
eval "use Crypt::Random qw(makerandom)";
if ($@) {
  $cryptFunc = 0;  
} else {
  $cryptFunc = $cryptFunc == 1 ? 1 : 0;
}

use SetExtensions;

sub EnOcean_Define($$);
sub EnOcean_Initialize($);
sub EnOcean_Parse($$);
sub EnOcean_Get($@);
sub EnOcean_Set($@);
sub EnOcean_hvac_01Cmd($$$);
sub EnOcean_roomCtrlPanel_00Snd($$$$$$$$);
sub EnOcean_CheckSenderID($$$);
sub EnOcean_SndRadio($$$$$$$$);
sub EnOcean_ReadingScaled($$$$);
sub EnOcean_TimerSet($);
sub EnOcean_Undef($$);

my %EnO_rorgname = (
  "F6" => "switch",  # RPS, org 05
  "D5" => "contact", # 1BS, org 06
  "A5" => "4BS",     # 4BS, org 07
  "A6" => "ADT",     # adressing destination telegram
  "C5" => "SYSEX",   # remote management
  "D1" => "MSC",     # MSC
  "D2" => "VLD",     # VLD
  "D4" => "UTE",     # UTE
  "30" => "SEC",     # secure telegram
  "31" => "ENC",     # secure telegram with encapsulation
  "32" => "SECD",    # decrypted secure telegram
  "35" => "STE",     # secure Teach-In
  "40" => "CDM",     # chained data message
  "B0" => "GPTI",    # GP teach-in request
  "B1" => "GPTR",    # GP teach-in response
  "B2" => "GPCD",    # GP complete data
  "B3" => "GPSD",    # GP selective data
);

# switch commands
my @EnO_ptm200btn = ("AI", "A0", "BI", "B0", "CI", "C0", "DI", "D0");
my %EnO_ptm200btn;

# switch.00 commands
my %EnO_switch_00Btn = (
  "A0"         => 14,
  "AI"         => 13,
  "B0"         => 12,
  "BI"         => 11,
  "A0,B0"      => 7,
  "A0,BI"      => 10,
  "AI,B0"      => 5,
  "AI,BI"      => 9,
  "pressed"    => 8,
  "pressed34"  => 6,
  "released"   => 15,
  "teachInSec" => 253,
  "teachOut"   => 254,
  "teachIn"    => 255
);

# gateway commands
my @EnO_gwCmd = ("switching", "dimming", "setpointShift", "setpointBasic", "controlVar", "fanStage", "blindCmd");
my %EnO_gwCmd = (
  "switching"     => 1,
  "dimming"       => 2,
  "setpointShift" => 3,
  "setpointBasic" => 4,
  "controlVar"    => 5,
  "fanStage"      => 6,
  "blindCmd"      => 7,
);

# Some Manufacturers (e.g. Jaeger Direkt) also sell EnOcean products without an entry in the table below.
my %EnO_manuf = (
  "000" => "Reserved",
  "001" => "Peha",
  "002" => "Thermokon",
  "003" => "Servodan",
  "004" => "EchoFlex Solutions",
  "005" => "AWAG Elektrotechnik AG (Omnio)",
  "006" => "Hardmeier electronics",
  "007" => "Regulvar Inc",
  "008" => "Ad Hoc Electronics",
  "009" => "Distech Controls",
  "00A" => "Kieback + Peter",
  "00B" => "EnOcean GmbH",
  "00C" => "Probare",
  "00D" => "Eltako",
  "00E" => "Leviton",
  "00F" => "Honeywell",
  "010" => "Spartan Peripheral Devices",
  "011" => "Siemens",
  "012" => "T-Mac",
  "013" => "Reliable Controls Corporation",
  "014" => "Elsner Elektronik GmbH",
  "015" => "Diehl Controls",
  "016" => "BSC Computer",
  "017" => "S+S Regeltechnik GmbH",
  "018" => "Masco Corporation",
  "019" => "Intesis Software SL",
  "01A" => "Viessmann",
  "01B" => "Lutuo Technology",
  "01C" => "Schneider Electric",
  "01D" => "Sauter",
  "01E" => "Boot-Up",
  "01F" => "Osram Sylvania",
  "020" => "Unotech",
  "021" => "Delta Controls Inc",
  "022" => "Unitronic AG",
  "023" => "NanoSense",
  "024" => "The S4 Group",
  "025" => "MSR Solutions",
  "026" => "GE",
  "027" => "Maico",
  "028" => "Ruskin Company",
  "029" => "Magnum Engery Solutions",
  "02A" => "KM Controls",
  "02B" => "Ecologix Controls",
  "02C" => "Trio 2 Sys",
  "02D" => "Afriso-Euro-Index",
  "030" => "NEC AccessTechnica Ltd",
  "031" => "ITEC Corporation",  
  "032" => "Simix Co Ltd",  
  "033" => "Permundo GmbH",  
  "034" => "Eurotronic Technology GmbH",
  "035" => "Art Japan Co Ltd",  
  "036" => "Tiansu Automation Control System Co Ltd",  
  "038" => "Gruppo Giordano Idea Spa",  
  "039" => "alphaEOS AG",
  "03A" => "Tag Technologies",  
  "03C" => "Cloud Buildings Ltd",  
  "03E" => "GIGA Concept",  
  "03F" => "Sensortec",  
  "040" => "Jaeger Direkt",  
  "041" => "Air System Components Inc",  
  "7FF" => "Multi user Manufacturer ID",
);

my %EnO_eepConfig = (
  "A5.02.01" => {attr => {subType => "tempSensor.01"}},
  "A5.02.02" => {attr => {subType => "tempSensor.02"}},
  "A5.02.03" => {attr => {subType => "tempSensor.03"}},
  "A5.02.04" => {attr => {subType => "tempSensor.04"}},
  "A5.02.05" => {attr => {subType => "tempSensor.05"}},
  "A5.02.06" => {attr => {subType => "tempSensor.06"}},
  "A5.02.07" => {attr => {subType => "tempSensor.07"}},
  "A5.02.08" => {attr => {subType => "tempSensor.08"}},
  "A5.02.09" => {attr => {subType => "tempSensor.09"}},
  "A5.02.0A" => {attr => {subType => "tempSensor.0A"}},
  "A5.02.0B" => {attr => {subType => "tempSensor.0B"}},
  "A5.02.10" => {attr => {subType => "tempSensor.10"}},
  "A5.02.11" => {attr => {subType => "tempSensor.11"}},
  "A5.02.12" => {attr => {subType => "tempSensor.12"}},
  "A5.02.13" => {attr => {subType => "tempSensor.13"}},
  "A5.02.14" => {attr => {subType => "tempSensor.14"}},
  "A5.02.15" => {attr => {subType => "tempSensor.15"}},
  "A5.02.16" => {attr => {subType => "tempSensor.16"}},
  "A5.02.17" => {attr => {subType => "tempSensor.17"}},
  "A5.02.18" => {attr => {subType => "tempSensor.18"}},
  "A5.02.19" => {attr => {subType => "tempSensor.19"}},
  "A5.02.1A" => {attr => {subType => "tempSensor.1A"}},
  "A5.02.1B" => {attr => {subType => "tempSensor.1B"}},
  "A5.02.20" => {attr => {subType => "tempSensor.20"}},
  "A5.02.30" => {attr => {subType => "tempSensor.30"}},
  "A5.04.01" => {attr => {subType => "roomSensorControl.01"}},
  "A5.04.02" => {attr => {subType => "tempHumiSensor.02"}},
  "A5.04.03" => {attr => {subType => "tempHumiSensor.03"}},
  "A5.05.01" => {attr => {subType => "baroSensor.01"}},
  "A5.06.01" => {attr => {subType => "lightSensor.01"}},
  "A5.06.02" => {attr => {subType => "lightSensor.02"}},
  "A5.06.03" => {attr => {subType => "lightSensor.03"}},
  "A5.07.01" => {attr => {subType => "occupSensor.01"}},
  "A5.07.02" => {attr => {subType => "occupSensor.02"}},
  "A5.07.03" => {attr => {subType => "occupSensor.03"}},
  "A5.08.01" => {attr => {subType => "lightTempOccupSensor.01"}},
  "A5.08.02" => {attr => {subType => "lightTempOccupSensor.02"}},
  "A5.08.03" => {attr => {subType => "lightTempOccupSensor.03"}},
  "A5.09.01" => {attr => {subType => "COSensor.01"}},
  "A5.09.02" => {attr => {subType => "COSensor.02"}},  
  "A5.09.04" => {attr => {subType => "tempHumiCO2Sensor.01"}},
  "A5.09.05" => {attr => {subType => "vocSensor.01"}},
  "A5.09.06" => {attr => {subType => "radonSensor.01"}},
  "A5.09.07" => {attr => {subType => "particlesSensor.01"}},
  "A5.09.08" => {attr => {subType => "CO2Sensor.01"}},
  "A5.09.09" => {attr => {subType => "CO2Sensor.01"}},
  "A5.10.01" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.02" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.03" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.04" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.05" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.06" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.07" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.08" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.09" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.0A" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.0B" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.0C" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.0D" => {attr => {subType => "roomSensorControl.05"}},
  "A5.10.10" => {attr => {subType => "roomSensorControl.01"}},
  "A5.10.11" => {attr => {subType => "roomSensorControl.01"}},
  "A5.10.12" => {attr => {subType => "roomSensorControl.01"}},
  "A5.10.13" => {attr => {subType => "roomSensorControl.01"}},
  "A5.10.14" => {attr => {subType => "roomSensorControl.01"}},
  "A5.10.15" => {attr => {subType => "roomSensorControl.02"}},
  "A5.10.16" => {attr => {subType => "roomSensorControl.02"}},
  "A5.10.17" => {attr => {subType => "roomSensorControl.02"}},
  "A5.10.18" => {attr => {subType => "roomSensorControl.18"}},
  "A5.10.19" => {attr => {subType => "roomSensorControl.19"}},
  "A5.10.1A" => {attr => {subType => "roomSensorControl.1A"}},
  "A5.10.1B" => {attr => {subType => "roomSensorControl.1B"}},
  "A5.10.1C" => {attr => {subType => "roomSensorControl.1C"}},
  "A5.10.1D" => {attr => {subType => "roomSensorControl.1D"}},
  "A5.10.1E" => {attr => {subType => "roomSensorControl.1B"}},
  "A5.10.1F" => {attr => {subType => "roomSensorControl.1F"}},
  "A5.10.20" => {attr => {subType => "roomSensorControl.20"}},
  "A5.10.21" => {attr => {subType => "roomSensorControl.20"}},  
  "A5.11.01" => {attr => {subType => "lightCtrlState.01"}},
  "A5.11.02" => {attr => {subType => "tempCtrlState.01"}},
  "A5.11.03" => {attr => {subType => "shutterCtrlState.01", subDef => "getNextID", subTypeSet => "gateway", gwCmd => "blindCmd"}},
  "A5.11.04" => {attr => {subType => "lightCtrlState.02", subDef => "getNextID", subTypeSet => "lightCtrl.01", webCmd => "on:off:dim:rgb"}},
  "A5.12.00" => {attr => {subType => "autoMeterReading.00"}},
  "A5.12.01" => {attr => {subType => "autoMeterReading.01"}},
  "A5.12.02" => {attr => {subType => "autoMeterReading.02"}},
  "A5.12.03" => {attr => {subType => "autoMeterReading.03"}},
  "A5.12.04" => {attr => {subType => "autoMeterReading.04"}},
  "A5.12.05" => {attr => {subType => "autoMeterReading.05"}},
  "A5.13.01" => {attr => {subType => "environmentApp"}},
  "A5.13.02" => {attr => {subType => "environmentApp"}},
  "A5.13.03" => {attr => {subType => "environmentApp"}},
  "A5.13.04" => {attr => {subType => "environmentApp"}},
  "A5.13.05" => {attr => {subType => "environmentApp"}},
  "A5.13.06" => {attr => {subType => "environmentApp"}},
  "A5.13.10" => {attr => {subType => "environmentApp"}},
  "A5.14.01" => {attr => {subType => "multiFuncSensor"}},
  "A5.14.02" => {attr => {subType => "multiFuncSensor"}},
  "A5.14.03" => {attr => {subType => "multiFuncSensor"}},
  "A5.14.04" => {attr => {subType => "multiFuncSensor"}},
  "A5.14.05" => {attr => {subType => "multiFuncSensor"}},
  "A5.14.06" => {attr => {subType => "multiFuncSensor"}},
  "A5.20.01" => {attr => {subType => "hvac.01", webCmd => "setpointTemp"}},
 #"A5.20.02" => {attr => {subType => "hvac.02"}},
 #"A5.20.03" => {attr => {subType => "hvac.03"}},
 #"A5.20.10" => {attr => {subType => "hvac.04"}},
 #"A5.20.11" => {attr => {subType => "hvac.11"}},
 #"A5.20.12" => {attr => {subType => "hvac.12"}},
  "A5.30.01" => {attr => {subType => "digitalInput.01"}},
  "A5.30.02" => {attr => {subType => "digitalInput.02"}},
  "A5.30.03" => {attr => {subType => "digitalInput.03"}},
  "A5.30.04" => {attr => {subType => "digitalInput.04"}},
  "A5.37.01" => {attr => {subType => "energyManagement.01", webCmd => "level:max"}},
  "A5.38.08" => {attr => {subType => "gateway"}},
  "A5.38.09" => {attr => {subType => "lightCtrl.01"}},
  "A5.3F.7F" => {attr => {subType => "manufProfile"}},
  "D2.01.00" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.01" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.02" => {attr => {subType => "actuator.01", defaultChannel => 0, webCmd => "on:off:dim"}},
  "D2.01.03" => {attr => {subType => "actuator.01", defaultChannel => 0, webCmd => "on:off:dim"}},
  "D2.01.04" => {attr => {subType => "actuator.01", defaultChannel => 0, webCmd => "on:off:dim"}},
  "D2.01.05" => {attr => {subType => "actuator.01", defaultChannel => 0, webCmd => "on:off:dim"}},
  "D2.01.06" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.07" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.08" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.09" => {attr => {subType => "actuator.01", defaultChannel => 0, webCmd => "on:off:dim"}},
  "D2.01.0A" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.0B" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.10" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.01.11" => {attr => {subType => "actuator.01", defaultChannel => 0}},
  "D2.03.00" => {attr => {subType => "switch.00"}},
  "D2.03.10" => {attr => {subType => "windowHandle.10"}},  
  "D2.05.00" => {attr => {subType => "blindsCtrl.00", webCmd => "opens:stop:closes:position"}},
  "D2.10.00" => {attr => {subType => "roomCtrlPanel.00", webCmd => "setpointTemp"}},  
  "D2.10.01" => {attr => {subType => "roomCtrlPanel.00", webCmd => "setpointTemp"}},  
  "D2.10.02" => {attr => {subType => "roomCtrlPanel.00", webCmd => "setpointTemp"}},
  "D2.20.00" => {attr => {subType => "fanCtrl.00", webCmd => "fanSpeed"}},  
  "D2.A0.01" => {attr => {subType => "valveCtrl.00", defaultChannel => 0, webCmd => "opens:closes"}},  
  "D5.00.01" => {attr => {subType => "contact"}},
  "F6.02.01" => {attr => {subType => "switch"}},
  "F6.02.02" => {attr => {subType => "switch"}},
  "F6.02.03" => {attr => {subType => "switch"}},
 #"F6.02.04" => {attr => {subType => "switch.04"}},
  "F6.03.01" => {attr => {subType => "switch"}},
  "F6.03.02" => {attr => {subType => "switch"}},
  "F6.04.01" => {attr => {subType => "keycard"}},
 #"F6.04.02" => {attr => {subType => "keycard.02"}},
  "F6.05.01" => {attr => {subType => "liquidLeakage"}},
  "F6.10.00" => {attr => {subType => "windowHandle"}},
 #"F6.10.01" => {attr => {subType => "windowHandle.01"}},
  "F6.3F.7F" => {attr => {subType => "switch.7F"}},
 #1          => {attr => {subType => "sensor"}},
  2          => {attr => {subType => "FRW"}},
  3          => {attr => {subType => "PM101"}},
  4          => {attr => {subType => "raw"}},
);

my %EnO_getRemoteFunctionCode = (
  4 => "id",
  6 => "ping",
  7 => "functionCommands",
  8 => "status"
);

my %EnO_setRemoteFunctionCode = (
  1 => "unlock",
  2 => "lock",
  3 => "setCode",
  5 => "action",
);

my @EnO_models = qw (
  other
  FAE14 FHK14 FHK61
  FSA12 FSB14 FSB61 FSB70
  FSM12 FSM61
  FT55
  FTS12
);

my @EnO_defaultChannel = ("all", "input", 0..29);

# Initialize
sub
EnOcean_Initialize($)
{
  my ($hash) = @_;
  my %subTypeList;
  my @subTypeList;
  foreach my $eep (keys %EnO_eepConfig){
    push @subTypeList, $EnO_eepConfig{$eep}{attr}{subType};
  }
  my $subTypeList = join(",", sort grep { !$subTypeList{$_}++ } @subTypeList);

  $hash->{Match}     = "^EnOcean:";
  $hash->{DefFn}     = "EnOcean_Define";
  $hash->{UndefFn}   = "EnOcean_Undef";
  $hash->{ParseFn}   = "EnOcean_Parse";
  $hash->{SetFn}     = "EnOcean_Set";
 #$hash->{StateFn}   = "EnOcean_State";
  $hash->{GetFn}     = "EnOcean_Get";
  $hash->{NotifyFn}  = "EnOcean_Notify";
  $hash->{AttrFn}    = "EnOcean_Attr";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 dummy:0,1 " .
                       "showtime:1,0 " .
                       "actualTemp angleMax:slider,-180,20,180 alarmAction:no,stop,opens,closes " .
                       "angleMin:slider,-180,20,180 " .
                       "angleTime setCmdTrigger:man,refDev blockUnknownMSC:no,yes blockMotion:no,yes " .
                       "blockTemp:no,yes blockDisplay:no,yes blockDateTime:no,yes " .
                       "blockTimeProgram:no,yes blockOccupancy:no,yes blockSetpointTemp:no,yes " .
                       "blockFanSpeed:no,yes blockKey:no,yes comMode:confirm,biDir,uniDir " .
                       "daylightSavingTime:supported,not_supported dataEnc:VAES,AES-CBC " .
                       "defaultChannel:" . join(",", @EnO_defaultChannel) . " " .
                       "demandRespAction demandRespRefDev demandRespMax:A0,AI,B0,BI,C0,CI,D0,DI ".
                       "demandRespMin:A0,AI,B0,BI,C0,CI,D0,DI demandRespRandomTime " .
                       "demandRespThreshold:slider,0,1,15 demandRespTimeoutLevel:max,last destinationID " .
                       "devChannel devMode:master,slave devUpdate:off,auto,demand,polling,interrupt " .
                       "dimMax dimMin dimValueOn disable:0,1 disabledForIntervals " .
                       "displayContent:default,humidity,off,setPointTemp,tempertureExtern,temperatureIntern,time,no_change " .
                       "eep gwCmd:" . join(",", sort @EnO_gwCmd) . " humitity humidityRefDev " .
                       "keyRcv keySnd macAlgo:no,3,4 " .
                       "manufID:" . join(",", sort keys %EnO_manuf) . " " . 
                       "model:" . join(",", @EnO_models) . " " .
                       "observe:on,off observeCmdRepetition:1,2,3,4,5 observeErrorAction observeLogic:and,or " .
                       #observeCmds observeExeptions
                       "observeRefDev " .
                       "pollInterval rampTime releasedChannel:A,B,C,D,I,0,auto repeatingAllowed:yes,no " .
                       "remoteManagement:off,on rlcAlgo:no,2++,3++ rlcRcv rlcSnd rlcTX:true,false " . 
                       "reposition:directly,opens,closes " .
                       "scaleDecimals:0,1,2,3,4,5,6,7,8,9 scaleMax scaleMin secMode:rcv,snd,bidir" .
                       "secCode secLevel:encapsulation,encryption,off sendDevStatus:no,yes sensorMode:switch,pushbutton " .
                       "serviceOn:no,yes shutTime shutTimeCloses subDef " .
                       "subDef0 subDefI subDefA subDefB subDefC subDefD " .
                       "subType:$subTypeList subTypeSet:$subTypeList subTypeReading:$subTypeList " .
                       "summerMode:off,on switchMode:switch,pushbutton " .
                       "switchHysteresis switchType:direction,universal,channel,central temperatureRefDev " .
                       "temperatureScale:C,F,default,no_change timeNotation:12,24,default,no_change " .
                       "timeProgram1 timeProgram2 timeProgram3 timeProgram4 updateState:default,yes,no " .
                       "uteResponseRequest:yes,no " .
                       $readingFnAttributes;

  for (my $i = 0; $i < @EnO_ptm200btn; $i++) {
    $EnO_ptm200btn{$EnO_ptm200btn[$i]} = "$i:30";
  }
  $EnO_ptm200btn{released} = "0:20";
  if ($cryptFunc == 1){
    Log3 undef, 2, "EnOcean Cryptographic functions available.";  
  } else {
    Log3 undef, 2, "EnOcean Cryptographic functions are not available.";  
  }  
  return undef;
}

# Define
sub
EnOcean_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};
  $def = "00000000";
  if(@a > 2 && @a < 5) {
    if ($a[2] eq "getNextID") {
      AssignIoPort($hash);
      $defs{$name}{DEF} = $def;
      $def = EnOcean_CheckSenderID("getNextID", $defs{$name}{IODev}{NAME}, "00000000");
      $defs{$name}{DEF} = $def;
      $modules{EnOcean}{defptr}{$def} = $hash;
    } elsif ($a[2] =~ m/^[A-Fa-f0-9]{8}$/i) {
      $def = uc($a[2]);
      $defs{$name}{DEF} = $def;
      $modules{EnOcean}{defptr}{$def} = $hash;
      AssignIoPort($hash);
    } else {
      return "wrong syntax: define <name> EnOcean 8-digit-hex-code";
    }
  } else {
    return "wrong syntax: define <name> EnOcean 8-digit-hex-code";
  }
  # Help FHEMWEB split up devices
  $attr{$name}{subType} = $1 if($name =~ m/EnO_(.*)_$def/);
  if (@a == 4) {
    # parse received device data
    $hash->{DEF} = $def;
    EnOcean_Parse($hash, $a[3]);
  }
  #$hash->{NOTIFYDEV} = "global";
  # polling
  # InternalAt();
  return undef;
}

# Get
sub EnOcean_Get($@)
{
  my ($hash, @a) = @_;
  return "no get value specified" if (@a < 2);
  my $name = $hash->{NAME};
  if (IsDisabled($name)) {
    Log3 $name, 4, "EnOcean $name get commands disabled.";  
    return;
  }
  my $cmdID;
  my $cmdList = "";
  my $data;
  my $destinationID = AttrVal($name, "destinationID", undef);
  if (AttrVal($name, "comMode", "uniDir") eq "biDir") {
    $destinationID = $hash->{DEF};
  } elsif (!defined $destinationID || $destinationID eq "multicast") {
    $destinationID = "FFFFFFFF";
  } elsif ($destinationID eq "unicast") {
    $destinationID = $hash->{DEF};
  } elsif ($destinationID !~ m/^[\dA-Fa-f]{8}$/) {
    return "DestinationID $destinationID wrong, choose <8-digit-hex-code>.";
  }
  $destinationID = uc($destinationID);
  my $eep = uc(AttrVal($name, "eep", "00-00-00"));
  $eep =~ m/^(..)(.)(..)(.)(..)$/;
  $eep = (((hex($1) << 6) | hex($3)) << 7) | hex($5);
  my $manufID = uc(AttrVal($name, "manufID", ""));
  my $model = AttrVal($name, "model", "");
  my $packetType = 1;
  $packetType = 0x0A if (ReadingsVal($hash->{IODev}, "mode", "00") eq "01");
  my $rorg;
  my $status = "00";
  my $st = AttrVal($name, "subType", "");
  my $stSet = AttrVal($name, "subTypeSet", undef);
  if (defined $stSet) {$st = $stSet;}
  my $subDef = uc(AttrVal($name, "subDef", $hash->{DEF}));
  if ($subDef !~ m/^[\dA-F]{8}$/) {return "SenderID $subDef wrong, choose <8-digit-hex-code>.";}
  my $tn = TimeNow();
  if (AttrVal($name, "remoteManagement", "off") eq "on") {
    # Remote Management
    $cmdList = "remoteCommands:noArg remoteID:noArg remotePing:noArg remoteStatus:noArg ";
  }
  # control set actions
  # $updateState = -1: no set commands available e. g. sensors
  #                 0: execute set commands
  #                 1: execute set commands and and update reading state
  #                 2: execute set commands delayed
  my $updateState = 1;
  Log3 $name, 5, "EnOcean $name EnOcean_Get command: " . join(" ", @a);
  shift @a;

  for (my $i = 0; $i < @a; $i++) {
    my $cmd = $a[$i];

    if ($cmd eq "remoteID") {
      $cmdID = 4;      
      $manufID = 0x7FF;
      #$packetType = 7;
      $rorg = "C5";
      my $seq = int(rand(2) + 1) << 6;
      shift(@a);
      my $cntr = (((3 << 11) | $manufID) << 12) | $cmdID;
      $data = sprintf "%02X%08X%06X00", $seq, $cntr, ($eep << 3) | 1;
      #$data = sprintf "0004%04X%06X", $manufID, ($eep << 3) | 1;
      $destinationID = "FFFFFFFF";
      Log3 $name, 3, "EnOcean get $name $cmd $data";
  
    } elsif ($cmd eq "remotePing") {
      $cmdID = 6;
      $manufID = 0x7FF;
      #$packetType = 7;
      $rorg = "C5";
      my $seq = int(rand(2) + 1) << 6;
      shift(@a);
      my $cntr = ($manufID << 12) | $cmdID;
      $data = sprintf "%02X%08X00000000", $seq, $cntr;
      #$data = sprintf "0006%04X", $manufID;
      $destinationID = $hash->{DEF};
      Log3 $name, 3, "EnOcean get $name $cmd $data";  
      #($rorg, $data) = EnOcean_Encapsulation($packetType, $rorg, $data, $destinationID);

    } elsif ($cmd eq "remoteCommands") {
      $cmdID = 7;
      $manufID = 0x7FF;
      #$packetType = 7;
      $rorg = "C5";
      my $seq = int(rand(2) + 1) << 6;
      shift(@a);
      my $cntr = ($manufID << 12) | $cmdID;
      $data = sprintf "%02X%08X00000000", $seq, $cntr;
      #$data = sprintf "0007%04X", $manufID;
      $destinationID = $hash->{DEF};
      Log3 $name, 3, "EnOcean get $name $cmd $data";  
      #($rorg, $data) = EnOcean_Encapsulation($packetType, $rorg, $data, $destinationID);

    } elsif ($cmd eq "remoteStatus") {
      $cmdID = 8;
      $manufID = 0x7FF;
      #$packetType = 7;
      $rorg = "C5";
      my $seq = int(rand(2) + 1) << 6;
      shift(@a);
      my $cntr = ($manufID << 12) | $cmdID;
      $data = sprintf "%02X%08X00000000", $seq, $cntr;
      #$data = "000807FF";
      $destinationID = $hash->{DEF};
      Log3 $name, 3, "EnOcean get $name $cmd $data";  
      #($rorg, $data) = EnOcean_Encapsulation($packetType, $rorg, $data, $destinationID);
 
    } elsif ($st eq "lightCtrl.01") {
      # Central Command, Extended Lighting-Control 
      # (A5-38-09)
      $rorg = "A5";
      shift(@a);
      $updateState = 0;
      if ($cmd eq "status") {
        # query state
        shift(@a);
        Log3 $name, 3, "EnOcean get $name $cmd";
        $data = "00000008";

      } else {
        $cmdList .= "status:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";      
      }
          
    } elsif ($st eq "actuator.01") {
      # Electronic switches and dimmers with Energy Measurement and Local Control
      # (D2-01-00 - D2-01-11)
      $rorg = "D2";
      shift(@a);
      my $channel = shift(@a);
      $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
      if (!defined $channel || $channel eq "all") {
        $channel = 30;
      } elsif ($channel eq "input" || $channel + 0 == 31) {
        $channel = 31;
      } elsif ($channel + 0 >= 30) {
        $channel = 30;
      } elsif ($channel + 0 >= 0 && $channel + 0 <= 29) {
      
      } else {
        return "$cmd <channel> wrong, choose 0...29|all|input.";
      }
      
      if ($cmd eq "state") {
        $cmdID = 3;      
        Log3 $name, 3, "EnOcean get $name $cmd $channel";  
        $data = sprintf "%02X%02X", $cmdID, $channel;
        
      } elsif ($cmd eq "measurement") {
        $cmdID = 6;
        my $query = shift(@a);
        Log3 $name, 3, "EnOcean get $name $cmd $channel $query";  
        if ($query eq "energy") {
          $query = 0;
        } elsif ($query eq "power") {
          $query = 1;
        } else {
          return "$cmd <channel> <query> wrong, choose 0...30|all|input energy|power.";
        }
        $data = sprintf "%02X%02X", $cmdID, $query << 5 | $channel;
        
      } elsif ($cmd eq "special" && $manufID eq "033") {
        $rorg = "D1";
        my $query = shift(@a);
        Log3 $name, 3, "EnOcean get $name $cmd $channel $query";  
        if ($query eq "health") {
          $query = 7;
        } elsif ($query eq "load") {
          $query = 8;
        } elsif ($query eq "voltage") {
          $query = 9;
        } elsif ($query eq "serialNumber") {
          $query = 0x81;
        } else {
          return "$cmd <channel> <query> wrong, choose health|load|voltage|serialNumber.";
        }
        $data = sprintf "0331%02X", $query;
        readingsSingleUpdate($hash, "getParam", $query, 0);
        
      } else {
        if ($manufID eq "033") {
          return "Unknown argument $cmd, choose one of $cmdList state measurement special";
        } else {
          return "Unknown argument $cmd, choose one of $cmdList state measurement";        
        }
      }

    } elsif ($st eq "blindsCtrl.00") {
      # Blinds Control for Position and Angle
      # (D2-05-00)
      $rorg = "D2";
      shift(@a);
      $updateState = 0;
      my $channel = 0;
      if ($cmd eq "position") {
        # query position and angle
        $cmdID = 3;
        shift(@a);
        Log3 $name, 3, "EnOcean get $name $cmd";
        $data = sprintf "%02X", $channel << 4 | $cmdID;

      } else {
        $cmdList .= "position:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";      
      }
      
    } elsif ($st eq "roomCtrlPanel.00") {
      # Room Control Panel
      # (D2-10-00 - D2-10-02)
      $rorg = "D2";
      shift(@a);
      $updateState = 2;
      if ($cmd eq "data") {
        # data request
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 1, 0);
        Log3 $name, 3, "EnOcean get $name $cmd";
        
      } elsif ($cmd eq "config") {
        # configuration request
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 32, 0);
        Log3 $name, 3, "EnOcean get $name $cmd";
        
      } elsif ($cmd eq "roomCtrl") {
        # room control setup request
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 128, 0);
        Log3 $name, 3, "EnOcean get $name $cmd";

      } elsif ($cmd eq "timeProgram") {
        # time program request
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 256, 0);
        Log3 $name, 3, "EnOcean get $name $cmd";

      } else {
        $cmdList .= "data:noArg config:noArg roomCtrl:noArg timeProgram:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";      
      }

    } elsif ($st eq "fanCtrl.00") {
      # Fan Control
      # (D2-20-00 - D2-20-02)
      $rorg = "D2";
      shift(@a);
      $updateState = 0;
      if ($cmd eq "state") {
        # query position and angle
        shift(@a);
        $data = "F6FFFFFF";
        Log3 $name, 3, "EnOcean get $name $cmd DATA: $data";

      } else {
        $cmdList .= "state:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";      
      }
      
    } elsif ($st eq "valveCtrl.00" && AttrVal($name, "devMode", "master") eq "master") {
      # Valve Control
      # (D2-A0-01)
      $rorg = "D2";
      shift(@a);
      $updateState = 0;
      if ($cmd eq "state") {
        # query switch state
        shift(@a);
        $data = "00";
        readingsSingleUpdate($hash, "state", $cmd, 1);
        Log3 $name, 3, "EnOcean get $name $cmd";

      } else {
        $cmdList .= "state:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";      
      }
      
    } else {
      # subtype does not support get commands
      if (AttrVal($name, "remoteManagement", "off") eq "on") {
        return "Unknown argument $cmd, choose one of $cmdList";
      } else {
        return;
      }
    }

    if($updateState != 2) {
      EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, $subDef, $status, $destinationID);
    }
  }
}  

# Set
sub EnOcean_Set($@)
{
  my ($hash, @a) = @_;
  return "no set value specified" if (@a < 2);
  my $name = $hash->{NAME};
  if (IsDisabled($name)) {
    Log3 $name, 4, "EnOcean $name set commands disabled.";  
    return;
  }
  my $cmdID;
  my $cmdList = "";
  my @cmdObserve = @a;
  my ($data, $err, $response, $logLevel);
  my $destinationID = AttrVal($name, "destinationID", undef);
  if (AttrVal($name, "comMode", "uniDir") eq "biDir") {
    $destinationID = $hash->{DEF};
  } elsif (!defined $destinationID || $destinationID eq "multicast") {
    $destinationID = "FFFFFFFF";
  } elsif ($destinationID eq "unicast") {
    $destinationID = $hash->{DEF};
  } elsif ($destinationID !~ m/^[\dA-Fa-f]{8}$/) {
    return "DestinationID $destinationID wrong, choose <8-digit-hex-code>.";
  }
  $destinationID = uc($destinationID);
  my $manufID = uc(AttrVal($name, "manufID", ""));
  my $model = AttrVal($name, "model", "");
  my $packetType = 1;
  $packetType = 0x0A if (ReadingsVal($hash->{IODev}, "mode", "00") eq "01");
  my $rorg;
  my $sendCmd = 1;
  my $status = "00";
  my $st = AttrVal($name, "subType", "");
  my $stSet = AttrVal($name, "subTypeSet", undef);
  if (defined $stSet) {$st = $stSet;}
  my $subDef = uc(AttrVal($name, "subDef", $hash->{DEF}));
  if ($subDef !~ m/^[\dA-F]{8}$/) {return "SenderID $subDef wrong, choose <8-digit-hex-code>.";}
  my $switchMode = AttrVal($name, "switchMode", "switch");
  my $tn = TimeNow();
  if (AttrVal($name, "remoteManagement", "off") eq "on") {
    # Remote Management
    $cmdList = "remoteAction:noArg remoteLock:noArg remote_teach-in:noArg remote_teach-out:noArg remoteSetCode:noArg remoteUnlock:noArg ";
  }
  # control set actions
  # $updateState = -1: no set commands available e. g. sensors
  #                 0: execute set commands
  #                 1: execute set commands and and update reading state
  #                 2: execute set commands delayed
  my $updateState = AttrVal($name, "comMode", "uniDir") eq "uniDir" ? 1 : 0;
  my $updateStateAttr = AttrVal($name, "updateState", "default");
  shift @a;

  for (my $i = 0; $i < @a; $i++) {
    my $cmd = $a[$i];
    my ($cmd1, $cmd2);

    if ($cmd eq "remoteUnlock") {
      $cmdID = 1;
      my $secCode = AttrVal($name, "secCode", undef);
      return "Security Code not defined, set attr $name secCode <00000001 ... FFFFFFFE>!" if (!defined($secCode)); 
      $manufID = 0x7FF;
      $rorg = "C5";
      my $seq = int(rand(2) + 1) << 6;
      #shift(@a);
      my $cntr = (((4 << 11) | $manufID) << 12) | $cmdID;
      $data = sprintf "%02X%08X%s", $seq, $cntr, uc($secCode);
      ####
      $destinationID = $hash->{DEF};
      Log3 $name, 3, "EnOcean set $name $cmd $data";
      $updateState = 0;

    } elsif ($cmd eq "remoteLock") {
      $cmdID = 2;
      my $secCode = AttrVal($name, "secCode", undef);
      return "Security Code not defined, set attr $name secCode <00000001 ... FFFFFFFE>!" if (!defined($secCode)); 
      $manufID = 0x7FF;
      $rorg = "C5";
      my $seq = int(rand(2) + 1) << 6;
      #shift(@a);
      my $cntr = (((4 << 11) | $manufID) << 12) | $cmdID;
      $data = sprintf "%02X%08X%s", $seq, $cntr, uc($secCode);
      ####
      $destinationID = $hash->{DEF};
      Log3 $name, 3, "EnOcean set $name $cmd $data";
      $updateState = 0;

    } elsif ($cmd eq "remoteSetCode") {
      $cmdID = 3;
      my $secCode = AttrVal($name, "secCode", undef);
      return "Security Code not defined, set attr $name secCode <00000001 ... FFFFFFFE>!" if (!defined($secCode)); 
      $manufID = 0x7FF;
      $rorg = "C5";
      my $seq = int(rand(2) + 1) << 6;
      #shift(@a);
      my $cntr = (((4 << 11) | $manufID) << 12) | $cmdID;
      $data = sprintf "%02X%08X%s", $seq, $cntr, uc($secCode);
      ####
      $destinationID = $hash->{DEF};
      Log3 $name, 3, "EnOcean set $name $cmd $data";
      $updateState = 0;

    } elsif ($cmd eq "remoteAction") {
      $cmdID = 5;
      $manufID = 0x7FF;
      $rorg = "C5";
      my $seq = int(rand(2) + 1) << 6;
      #shift(@a);
      my $cntr = ($manufID << 12) | $cmdID;
      ####
      $data = sprintf "%02X%08X00000000", $seq, $cntr;
      $destinationID = $hash->{DEF};
      Log3 $name, 3, "EnOcean set $name $cmd $data";
      $updateState = 0;

    } elsif ($cmd eq "remote_teach-in") {
      $cmdID = 0x201;
      $manufID = 0x7FF;
      $rorg = "C5";
      my $seq = int(rand(2) + 1) << 6;
      #shift(@a);
      my $cntr = (((4 << 11) | $manufID) << 12) | $cmdID;
      ####
      my $eep = AttrVal($name, "eep", undef);
      return "EEP not defined, set attr $name eep <rorg>-<function>-<type>" if (!defined($eep));
      $eep =~ m/^(..)(.)(..)(.)(..)$/;
      $data = sprintf "%02X%08X%s%s%s01", $seq, $cntr, $1, $3, $5;
      $destinationID = "FFFFFFFF";
      $destinationID = $hash->{DEF};
      Log3 $name, 3, "EnOcean set $name $cmd $data";
      $updateState = 0;

    } elsif ($cmd eq "remote_teach-out") {
      $cmdID = 0x201;
      $manufID = 0x7FF;
      $rorg = "C5";
      # SEQ = 0...3
      my $seq = int(rand(4)) << 6;
      #shift(@a);
      my $cntr = (((4 << 11) | $manufID) << 12) | $cmdID;
      ####
      my $eep = AttrVal($name, "eep", undef);
      return "EEP not defined, set attr $name eep <rorg>-<function>-<type>" if (!defined($eep));
      $eep =~ m/^(..)(.)(..)(.)(..)$/;
      $data = sprintf "%02X%08X%s%s%s03", $seq, $cntr, $1, $3, $5;
      #$destinationID = "FFFFFFFF";
      $destinationID = $hash->{DEF};
      #($rorg, $data) = EnOcean_Encapsulation($packetType, $rorg, $data, $destinationID);
      Log3 $name, 3, "EnOcean set $name $cmd $data";
      $updateState = 0;

    } elsif ($st eq "switch") {
      # Rocker Switch, simulate a PTM200 switch module
      # separate first and second action
      ($cmd1, $cmd2) = split(",", $cmd, 2);
      # check values
      if (!defined($EnO_ptm200btn{$cmd1}) || ($cmd2 && !defined($EnO_ptm200btn{$cmd2}))) {
        $cmdList .= join(":noArg ", sort keys %EnO_ptm200btn);
        return SetExtensions($hash, $cmdList, $name, @a);
      }
      my $channelA = ReadingsVal($name, "channelA", undef);
      my $channelB = ReadingsVal($name, "channelB", undef);
      my $channelC = ReadingsVal($name, "channelC", undef);
      my $channelD = ReadingsVal($name, "channelD", undef);
      my $lastChannel = ReadingsVal($name, ".lastChannel", "A");
      my $releasedChannel = AttrVal($name, "releasedChannel", "auto");
      my $subDefA = AttrVal($name, "subDefA", $subDef);
      my $subDefB = AttrVal($name, "subDefB", $subDef);
      my $subDefC = AttrVal($name, "subDefC", $subDef);
      my $subDefD = AttrVal($name, "subDefD", $subDef);
      my $subDefI = AttrVal($name, "subDefI", $subDef);
      my $subDef0 = AttrVal($name, "subDef0", $subDef);
      my $switchType = AttrVal($name, "switchType", "direction");
      
      # first action      
      if ($cmd1 eq "released") {
        if ($switchType eq "central") {
          if ($releasedChannel eq "auto") {
            if ($lastChannel =~ m/0|I/) {
              $releasedChannel = $lastChannel;
            } else {
              $releasedChannel = 0;
            }
          } elsif ($releasedChannel !~ m/0|I/) {
            $releasedChannel = 0;
          }
        } elsif ($switchType eq "channel") {
          if ($releasedChannel eq "auto") {
            if ($lastChannel =~ m/A|B|C|D/) {
              $releasedChannel = $lastChannel;
            } else {
              $releasedChannel = "A";
            }
          } elsif ($releasedChannel !~ m/A|B|C|D/) {
            $releasedChannel = "A";
          }
        }
        $subDef = AttrVal($name, "subDef" . $releasedChannel, $subDef);
      } elsif ($switchType eq "central") {
        if ($cmd1 =~ m/.0/) {
          $subDef = $subDef0;
          $lastChannel = 0;          
        } elsif ($cmd1 =~ m/.I/) {
          $subDef = $subDefI;
          $lastChannel = "I";
        }
      } elsif ($switchType eq "channel") {
        $lastChannel = substr($cmd1, 0, 1);
        $subDef = AttrVal($name, "subDef" . $lastChannel, $subDefA);
      } else {
        $lastChannel = substr($cmd1, 0, 1);
      }

      if ($switchType eq "universal") {
        if ($cmd1 =~ m/A./ && (!defined($channelA) || $cmd1 ne $channelA)) {
          $cmd1 = "A0";
        } elsif ($cmd1 =~ m/B./ && (!defined($channelB) || $cmd1 ne $channelB)) {
          $cmd1 = "B0";
        } elsif ($cmd1 =~ m/C./ && (!defined($channelC) || $cmd1 ne $channelC)) {
          $cmd1 = "C0";
        } elsif ($cmd1 =~ m/D./ && (!defined($channelD) || $cmd1 ne $channelD)) {
          $cmd1 = "D0";
        } elsif ($cmd1 eq "released") {

        } else {
          $sendCmd = undef;
        }
      }
      # second action
      if ($cmd2 && $switchType eq "universal") {
        if ($cmd2 =~ m/A./ && (!defined($channelA) || $cmd2 ne $channelA)) {
          $cmd2 = "A0";
        } elsif ($cmd2 =~ m/B./ && (!defined($channelB) || $cmd2 ne $channelB)) {
          $cmd2 = "B0";
        } elsif ($cmd2 =~ m/C./ && (!defined($channelC) || $cmd2 ne $channelC)) {
          $cmd2 = "C0";
        } elsif ($cmd2 =~ m/D./ && (!defined($channelD) || $cmd2 ne $channelD)) {
          $cmd2 = "D0";
        } else {
          $cmd2 = undef;
        }
        if ($cmd2 && undef($sendCmd)) {
          # only second action has changed, send as first action
          $cmd1 = $cmd2;
          $cmd2 = undef;
          $sendCmd = 1;
        }
      }
      # convert and send first and second command
      my $switchCmd;
      ($switchCmd, $status) = split(":", $EnO_ptm200btn{$cmd1}, 2);
      $switchCmd <<= 5;
      if ($cmd1 ne "released") {
        # set the pressed flag
        $switchCmd |= 0x10 ;
      }
      if($cmd2) {
        # execute second action
        if ($switchType =~ m/^central|channel$/) {
          # second action not supported
          $cmd = $cmd1;
        } else {
          my ($d2, undef) = split(":", $EnO_ptm200btn{$cmd2}, 2);
          $switchCmd |= ($d2 << 1) | 0x01;
        }
      }
      if (defined $sendCmd) {
        $data = sprintf "%02X", $switchCmd;
        $rorg = "F6";
        Log3 $name, 3, "EnOcean set $name $cmd";
        readingsSingleUpdate($hash, ".lastChannel", $lastChannel, 0);
      }
      
    } elsif ($st eq "switch.00") {
      my $switchCmd = join(",", sort split(",", $cmd, 2));
      ($cmd1, $cmd2) = split(",", $switchCmd, 2);
      $cmd = $switchCmd;
      if ((!defined($switchCmd)) || (!defined($EnO_switch_00Btn{$switchCmd}))) {
        # check values
        $cmdList .= join(":noArg ", keys %EnO_switch_00Btn);
        return SetExtensions($hash, $cmdList, $name, @a);
      } elsif ($switchCmd eq "teachIn") {
        ($err, $rorg, $data) = EnOcean_sndUTE(undef, $hash, AttrVal($name, "comMode", "uniDir"),
                                              AttrVal($name, "uteResponseRequest", "no"), "in", 0, "D2-03-00");
      } elsif ($switchCmd eq "teachInSec") {
        ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        ($err, $response, $logLevel) = EnOcean_sec_createTeachIn(undef, $hash, "uniDir", "VAES", "D2-03-00", 3,
                                                                 "2++", "false", "encryption", $subDef, $destinationID);
        if ($err) {
          Log3 $name, $logLevel, "EnOcean $name Error: $err";
          return $err;
        } else {
          CommandSave(undef, undef);      
          Log3 $name, $logLevel, "EnOcean $name $response";
          readingsSingleUpdate($hash, "state", "teachInSec", 1);
          return(undef);
        }
      } elsif ($switchCmd eq "teachOut") {
        ($err, $rorg, $data) = EnOcean_sndUTE(undef, $hash, AttrVal($name, "comMode", "uniDir"),
                                              AttrVal($name, "uteResponseRequest", "no"), "out", 0, "D2-03-00");
      } else {
        $data = sprintf "%02X", $EnO_switch_00Btn{$switchCmd};
        $rorg = "D2";
      }
      Log3 $name, 3, "EnOcean set $name $switchCmd";
      
    } elsif ($st eq "roomSensorControl.01") {
      # Room Sensor and Control Unit (EEP A5-04-01, A5-10-10 ... A5-10-14)
      # [Thermokon SR04 * rH, Thanus SR *, untested]
      # $db[3] is the setpoint where 0x00 = min ... 0xFF = max
      # $db[2] is the humidity where 0x00 = 0%rH ... 0xFA = 100%rH
      # $db[1] is the temperature where 0x00 = 0�C ... 0xFA = +40�C
      # $db[0] bit D0 is the occupy button, pushbutton or slide switch
      $rorg = "A5";
      # primarily temperature from the reference device then the attribute actualTemp is read
      my $temperatureRefDev = AttrVal($name, "temperatureRefDev", undef);
      my $actualTemp = AttrVal($name, "actualTemp", 20);
      $actualTemp = ReadingsVal($temperatureRefDev, "temperature", 20) if (defined $temperatureRefDev); 
      $actualTemp = 20 if ($actualTemp !~ m/^[+-]?\d+(\.\d+)?$/);
      $actualTemp = 0 if ($actualTemp < 0);
      $actualTemp = 40 if ($actualTemp > 40);
      $actualTemp = sprintf "%0.1f", $actualTemp;
      # primarily humidity from the reference device then the attribute humidity is read
      my $humidityRefDev = AttrVal($name, "humidityRefDev", undef);
      my $humidity = AttrVal($name, "humidity", 0);
      $humidity = ReadingsVal($humidityRefDev, "humidity", 0) if (defined $humidityRefDev); 
      $humidity = 0 if ($humidity !~ m/^\d+(\.\d+)?$/);
      $humidity = 0 if ($humidity < 0);
      $humidity = 100 if ($humidity > 100);
      $humidity = sprintf "%d", $humidity;
      my $setCmd = 8;
      my $setpoint = ReadingsVal($name, "setpoint", 125);
      my $setpointScaled = ReadingsVal($name, "setpointScaled", undef);
      my $switch = ReadingsVal($name, "switch", "off");
      $setCmd |= 1 if ($switch eq "on");
      if ($cmd eq "teach") {
        # teach-in EEP A5-10-10, Manufacturer "Multi user Manufacturer ID"
        $data = "4087FF80";
        $updateState = 1;
        CommandDeleteReading(undef, "$name .*");
        ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");

      } elsif ($cmd eq "setpoint") {
        #
        if (defined $a[1]) {
          if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 255)) {
            $setpoint = $a[1];
            shift(@a);
            if (defined $setpointScaled) {
              $setpointScaled = EnOcean_ReadingScaled($hash, $setpoint, 0, 255);
            }
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "temperature", $actualTemp);
        readingsBulkUpdate($hash, "humidity", $humidity);
        readingsBulkUpdate($hash, "setpointScaled", $setpointScaled) if (defined $setpointScaled);
        readingsBulkUpdate($hash, "setpoint", $setpoint);
        readingsBulkUpdate($hash, "switch", $switch);
        readingsBulkUpdate($hash, "state", "T: $actualTemp H: $humidity SP: $setpoint SW: $switch");
        readingsEndUpdate($hash, 1);
        $actualTemp = $actualTemp / 40 * 250;
        $humidity = $humidity / 100 * 250;
        $updateState = 0;
        $data = sprintf "%02X%02X%02X%02X", $setpoint, $humidity, $actualTemp, $setCmd;

      } elsif ($cmd eq "setpointScaled") {
        #
        if (defined $a[1]) {
          my $scaleMin = AttrVal($name, "scaleMin", undef);
          my $scaleMax = AttrVal($name, "scaleMax", undef);
          my ($rangeMin, $rangeMax);
          if (defined $scaleMax && defined $scaleMin &&
              $scaleMax =~ m/^[+-]?\d+(\.\d+)?$/ && $scaleMin =~ m/^[+-]?\d+(\.\d+)?$/) {
            if ($scaleMin > $scaleMax) {
              ($rangeMin, $rangeMax)= ($scaleMax, $scaleMin);
            } else {
              ($rangeMin, $rangeMax)= ($scaleMin, $scaleMax);
            }
          } else {
            return "Usage: Attributes scaleMin and/or scaleMax not defined or not numeric.";            
          }
          if ($a[1] =~ m/^[+-]?\d+(\.\d+)?$/ && $a[1] >= $rangeMin && $a[1] <= $rangeMax) {
            $setpointScaled = $a[1];
            shift(@a);
            $setpoint = sprintf "%d", 255 * $scaleMin/($scaleMin-$scaleMax) - 255/($scaleMin-$scaleMax) * $setpointScaled;
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "temperature", $actualTemp);
        readingsBulkUpdate($hash, "humidity", $humidity);
        readingsBulkUpdate($hash, "setpointScaled", $setpointScaled) if (defined $setpointScaled);
        readingsBulkUpdate($hash, "setpoint", $setpoint);
        readingsBulkUpdate($hash, "switch", $switch);
        readingsBulkUpdate($hash, "state", "T: $actualTemp H: $humidity SP: $setpoint SW: $switch");
        readingsEndUpdate($hash, 1);
        $actualTemp = $actualTemp / 40 * 250;
        $humidity = $humidity / 100 * 250;
        $updateState = 0;
        $data = sprintf "%02X%02X%02X%02X", $setpoint, $humidity, $actualTemp, $setCmd;

      } elsif ($cmd eq "switch") {
        #
        if (defined $a[1]) {
          if ($a[1] eq "on") {
            $switch = $a[1];
            $setCmd |= 1;    
            shift(@a);
          } elsif ($a[1] eq "off"){            
            $switch = $a[1];
            shift(@a);
          } else {
            return "Usage: $a[1] is unknown";
          }
        }
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "temperature", $actualTemp);
        readingsBulkUpdate($hash, "humidity", $humidity);
        readingsBulkUpdate($hash, "setpointScaled", $setpointScaled) if (defined $setpointScaled);
        readingsBulkUpdate($hash, "setpoint", $setpoint);
        readingsBulkUpdate($hash, "switch", $switch);
        readingsBulkUpdate($hash, "state", "T: $actualTemp H: $humidity SP: $setpoint SW: $switch");
        readingsEndUpdate($hash, 1);
        $actualTemp = $actualTemp / 40 * 250;
        $humidity = $humidity / 100 * 250;
        $updateState = 0;
        $data = sprintf "%02X%02X%02X%02X", $setpoint, $humidity, $actualTemp, $setCmd;

      } else {
        return "Unknown argument " . $cmd . ", choose one of " . $cmdList . " setpoint:slider,0,1,255 setpointScaled switch:on,off teach:noArg"
      }
      
      Log3 $name, 3, "EnOcean set $name $cmd";
    
    } elsif ($st eq "roomSensorControl.05") {
      # Room Sensor and Control Unit (EEP A5-10-01 ... A5-10-0D)
      # [Eltako FTR55D, FTR55H, Thermokon SR04 *, Thanos SR *, untested]
      # $db[3] is the fan speed or night reduction for Eltako
      # $db[2] is the setpoint where 0x00 = min ... 0xFF = max or
      # reference temperature for Eltako where 0x00 = 0�C ... 0xFF = 40�C
      # $db[1] is the temperature where 0x00 = +40�C ... 0xFF = 0�C
      # $db[1]_bit_1 is blocking the aditional Room Sensor and Control Unit for Eltako FVS
      # $db[0]_bit_0 is the slide switch
      $rorg = "A5";
      # primarily temperature from the reference device then the attribute actualTemp is read
      my $temperatureRefDev = AttrVal($name, "temperatureRefDev", undef);
      my $actualTemp = AttrVal($name, "actualTemp", 20);
      $actualTemp = ReadingsVal($temperatureRefDev, "temperature", 20) if (defined $temperatureRefDev); 
      $actualTemp = 20 if ($actualTemp !~ m/^[+-]?\d+(\.\d+)?$/);
      $actualTemp = 0 if ($actualTemp < 0);
      $actualTemp = 40 if ($actualTemp > 40);
      $actualTemp = sprintf "%0.1f", $actualTemp;
      my $setCmd = 8;
      if ($manufID eq "00D") {
        # EEP A5-10-06 plus DB3 [Eltako FVS]
        my $setpointTemp = ReadingsVal($name, "setpointTemp", 20);
        my $nightReduction = ReadingsVal($name, "nightReduction", 0);
        my $block = ReadingsVal($name, "block", "unlock");
        if ($cmd eq "teach") {
          # teach-in EEP A5-10-06 plus "FVS", Manufacturer "Eltako"
          $data = "40300D85";
          $updateState = 1;
          CommandDeleteReading(undef, "$name .*");
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($cmd eq "desired-temp" || $cmd eq "setpointTemp") {
          #
          if (defined $a[1]) {
            if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 40)) {
              $setpointTemp = sprintf "%0.1f", $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          }
          if (defined $a[1]) {
            if (($a[1] =~ m/^(lock|unlock)$/) ) {
              $block = $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is unknown";
            }
          }
          readingsSingleUpdate($hash, "temperature", $actualTemp, 1);
          readingsSingleUpdate($hash, "setpointTemp", $setpointTemp, 1);
          readingsSingleUpdate($hash, "nightReduction", $nightReduction, 1);
          readingsSingleUpdate($hash, "block", $block, 1);
          readingsSingleUpdate($hash, "state", "T: $actualTemp SPT: $setpointTemp NR: $nightReduction", 1);
          if ($nightReduction == 5) {
            $nightReduction = 31;
          } elsif ($nightReduction == 4) {
            $nightReduction = 25;
          } elsif ($nightReduction == 3) {
            $nightReduction = 19;
          } elsif ($nightReduction == 2) {
            $nightReduction = 12;
          } elsif ($nightReduction == 1) {
            $nightReduction = 6;
          } else {
            $nightReduction = 0;
          }
          $actualTemp = (40 - $actualTemp) / 40 * 255;
          $setpointTemp = $setpointTemp * 255 / 40;
          # control of the aditional Room Sensor and Control Unit
          if ($block eq "lock") {
            # temperature setting is locked
            $setCmd = 0x0D;
          } else {
            # setpointTemp may be subject to change at +/-3 K
            $setCmd = 0x0F;              
          }
          $updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", $nightReduction, $setpointTemp, $actualTemp, $setCmd;
          
        } elsif ($cmd eq "nightReduction") {
          # 
          if (defined $a[1]) {
            if ($a[1] =~ m/^[0-5]$/) {
              $nightReduction = $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          }
          if (defined $a[1]) {
            if (($a[1] =~ m/^(lock|unlock)$/) ) {
              $block = $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is unknown";
            }
          }          
          readingsSingleUpdate($hash, "temperature", $actualTemp, 1);
          readingsSingleUpdate($hash, "setpointTemp", $setpointTemp, 1);
          readingsSingleUpdate($hash, "nightReduction", $nightReduction, 1);
          readingsSingleUpdate($hash, "block", $block, 1);
          readingsSingleUpdate($hash, "state", "T: $actualTemp SPT: $setpointTemp NR: $nightReduction", 1);
          if ($nightReduction == 5) {
            $nightReduction = 31;
          } elsif ($nightReduction == 4) {
            $nightReduction = 25;
          } elsif ($nightReduction == 3) {
            $nightReduction = 19;
          } elsif ($nightReduction == 2) {
            $nightReduction = 12;
          } elsif ($nightReduction == 1) {
            $nightReduction = 6;
          } else {
            $nightReduction = 0;
          }
          $actualTemp = (40 - $actualTemp) / 40 * 254;
          $setpointTemp = $setpointTemp * 254 / 40;
          # control of the aditional Room Sensor and Control Unit
          if ($block eq "lock") {
            # temperature setting is locked
            $setCmd = 0x0D;
          } else {
            # setpointTemp may be subject to change at +/-3 K
            $setCmd = 0x0F;              
          }
          $updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", $nightReduction, $setpointTemp, $actualTemp, $setCmd;
        
        } else {
          return "Unknown argument " . $cmd . ", choose one of setpointTemp:slider,0,1,40 desired-temp nightReduction:0,1,2,3,4,5 teach:noArg"
        }
        
      } else {
        # EEP A5-10-02
        my $setpoint = ReadingsVal($name, "setpoint", 128);
        my $setpointScaled = ReadingsVal($name, "setpointScaled", undef);
        my $fanStage = ReadingsVal($name, "fanStage", "auto");
        my $switch = ReadingsVal($name, "switch", "off");
        $setCmd |= 1 if ($switch eq "on");
        if ($cmd eq "teach") {
          # teach-in EEP A5-10-02, Manufacturer "Multi user Manufacturer ID"
          $data = "4017FF80";
          $updateState = 1;
          CommandDeleteReading(undef, "$name .*");
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($cmd eq "fanStage") {
          #
          if (defined $a[1] && ($a[1] =~ m/^[0-3]$/ || $a[1] eq "auto")) {
            $fanStage = $a[1];
            shift(@a);
            readingsSingleUpdate($hash, "temperature", $actualTemp, 1);
            readingsSingleUpdate($hash, "setpointScaled", $setpointScaled, 1) if (defined $setpointScaled);
            readingsSingleUpdate($hash, "setpoint", $setpoint, 1);
            readingsSingleUpdate($hash, "fanStage", $fanStage, 1);
            readingsSingleUpdate($hash, "switch", $switch, 1);
            readingsSingleUpdate($hash, "state", "T: $actualTemp SP: $setpoint F: $fanStage SW: $switch", 1);
            if ($fanStage eq "auto"){
              $fanStage = 255;
            } elsif ($fanStage == 0) {
              $fanStage = 209;            
            } elsif ($fanStage == 1) {
               $fanStage = 189;           
            } elsif ($fanStage == 2) {
              $fanStage = 164;            
            } else {
              $fanStage = 144;            
            }
          } else {
            return "Usage: $a[1] is not numeric, out of range or unknown";
          }
          $actualTemp = (40 - $actualTemp) / 40 * 254;
          $updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", $fanStage, $setpoint, $actualTemp, $setCmd;
          
        } elsif ($cmd eq "setpoint") {
          #
          if (defined $a[1]) {
            if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 255)) {
              $setpoint = $a[1];
              shift(@a);
              if (defined $setpointScaled) {
                $setpointScaled = EnOcean_ReadingScaled($hash, $setpoint, 0, 255);
              }
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }

          }
          readingsSingleUpdate($hash, "temperature", $actualTemp, 1);
          readingsSingleUpdate($hash, "setpointScaled", $setpointScaled, 1) if (defined $setpointScaled);
          readingsSingleUpdate($hash, "setpoint", $setpoint, 1);
          readingsSingleUpdate($hash, "fanStage", $fanStage, 1);
          readingsSingleUpdate($hash, "switch", $switch, 1);
          readingsSingleUpdate($hash, "state", "T: $actualTemp SP: $setpoint F: $fanStage SW: $switch", 1);
          if ($fanStage eq "auto"){
            $fanStage = 255;
          } elsif ($fanStage == 0) {
            $fanStage = 209;            
          } elsif ($fanStage == 1) {
            $fanStage = 189;           
          } elsif ($fanStage == 2) {
            $fanStage = 164;            
          } else {
            $fanStage = 144;            
          }
          $actualTemp = (40 - $actualTemp) / 40 * 255;
          $updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", $fanStage, $setpoint, $actualTemp, $setCmd;
          
        } elsif ($cmd eq "setpointScaled") {
          #
          if (defined $a[1]) {
            my $scaleMin = AttrVal($name, "scaleMin", undef);
            my $scaleMax = AttrVal($name, "scaleMax", undef);
            my ($rangeMin, $rangeMax);
            if (defined $scaleMax && defined $scaleMin &&
                $scaleMax =~ m/^[+-]?\d+(\.\d+)?$/ && $scaleMin =~ m/^[+-]?\d+(\.\d+)?$/) {
              if ($scaleMin > $scaleMax) {
                ($rangeMin, $rangeMax)= ($scaleMax, $scaleMin);
              } else {
                ($rangeMin, $rangeMax)= ($scaleMin, $scaleMax);
              }
            } else {
              return "Usage: Attributes scaleMin and/or scaleMax not defined or not numeric.";            
            }
            if ($a[1] =~ m/^[+-]?\d+(\.\d+)?$/ && $a[1] >= $rangeMin && $a[1] <= $rangeMax) {
              $setpointScaled = $a[1];
              shift(@a);
              $setpoint = sprintf "%d", 255 * $scaleMin/($scaleMin-$scaleMax) - 255/($scaleMin-$scaleMax) * $setpointScaled;
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          }
          readingsSingleUpdate($hash, "temperature", $actualTemp, 1);
          readingsSingleUpdate($hash, "setpointScaled", $setpointScaled, 1);
          readingsSingleUpdate($hash, "setpoint", $setpoint, 1);
          readingsSingleUpdate($hash, "fanStage", $fanStage, 1);
          readingsSingleUpdate($hash, "switch", $switch, 1);
          readingsSingleUpdate($hash, "state", "T: $actualTemp SP: $setpoint F: $fanStage SW: $switch", 1);
          if ($fanStage eq "auto"){
            $fanStage = 255;
          } elsif ($fanStage == 0) {
            $fanStage = 209;            
          } elsif ($fanStage == 1) {
            $fanStage = 189;           
          } elsif ($fanStage == 2) {
            $fanStage = 164;            
          } else {
            $fanStage = 144;            
          }
          $actualTemp = (40 - $actualTemp) / 40 * 255;
          $updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", $fanStage, $setpoint, $actualTemp, $setCmd;
          
        } elsif ($cmd eq "switch") {
          #
          if (defined $a[1]) {
            if ($a[1] eq "on") {
              $switch = $a[1];
              $setCmd |= 1;    
              shift(@a);
            } elsif ($a[1] eq "off"){            
              $switch = $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is unknown";
            }
          }
          readingsSingleUpdate($hash, "temperature", $actualTemp, 1);
          readingsSingleUpdate($hash, "setpointScaled", $setpointScaled, 1) if (defined $setpointScaled);
          readingsSingleUpdate($hash, "setpoint", $setpoint, 1);
          readingsSingleUpdate($hash, "fanStage", $fanStage, 1);
          readingsSingleUpdate($hash, "switch", $switch, 1);
          readingsSingleUpdate($hash, "state", "T: $actualTemp SP: $setpoint F: $fanStage SW: $switch", 1);
          if ($fanStage eq "auto"){
            $fanStage = 255;
          } elsif ($fanStage == 0) {
            $fanStage = 209;            
          } elsif ($fanStage == 1) {
            $fanStage = 189;           
          } elsif ($fanStage == 2) {
            $fanStage = 164;            
          } else {
            $fanStage = 144;            
          }
          $actualTemp = (40 - $actualTemp) / 40 * 255;
          $updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", $fanStage, $setpoint, $actualTemp, $setCmd;
          
        } else {
          return "Unknown argument " . $cmd . ", choose one of " . $cmdList . "setpoint:slider,0,1,255 fanStage:auto,0,1,2,3 setpointScaled switch:on,off teach:noArg"
        }
        
      }
      Log3 $name, 3, "EnOcean set $name $cmd";
    
    } elsif ($st eq "hvac.01" || $st eq "MD15") {
      # Battery Powered Actuator (EEP A5-20-01)
      # [Kieback&Peter MD15-FTL-xx]
      # See also http://www.oscat.de/community/index.php/topic,985.30.html
      # Maintenance commands (runInit, liftSet, valveOpen, valveClosed)
      $rorg = "A5";
      my %sets = (
        "desired-temp" => "\\d+(\\.\\d)?",
        "setpointTemp" => "\\d+(\\.\\d)?",
        "setpoint"     => "\\d+",
        "actuator"     => "\\d+",
        "unattended"   => "",
        "runInit"      => "",
        "liftSet"      => "",
        "valveOpen"    => "",
        "valveClosed"  => "",
      );
      my $re = $sets{$a[0]};
      $cmdList .= "setpointTemp:slider,0,1,40 setpoint:slider,0,5,100 desired-temp actuator liftSet:noArg runInit:noArg valveOpen:noArg valveClosed:noArg unattended:noArg"; 
      #return "Unknown argument $cmd, choose one of " . $cmdList . join(" ", sort keys %sets);
      return "Unknown argument $cmd, choose one of $cmdList" if (!defined($re));
      return "Need a parameter" if ($re && @a < 2);
      return "Argument $a[1] is incorrect (expect $re)" if ($re && $a[1] !~ m/^$re$/);

      $updateState = 2;
      $hash->{CMD} = $cmd;
      readingsSingleUpdate($hash, "CMD", $cmd, 1);

      my $arg = "true";
      if ($re) {
        $arg = $a[1];
        shift(@a);
      }
      readingsSingleUpdate($hash, $cmd, $arg, 1);

    } elsif ($st eq "gateway") {
      # Gateway (EEP A5-38-08)
      # select Command from attribute gwCmd or command line
      my $gwCmd = AttrVal($name, "gwCmd", undef);
      if ($gwCmd && $EnO_gwCmd{$gwCmd}) {
        # command from attribute gwCmd
        if ($EnO_gwCmd{$cmd}) {
          # shift $cmd
          $cmd = $a[1];
          shift(@a);
        }
      } elsif ($EnO_gwCmd{$cmd}) {
        # command from command line
        $gwCmd = $cmd;
        $cmd = $a[1];
        shift(@a);
      } else {
        return "Unknown Gateway command " . $cmd . ", choose one of " . $cmdList . join(" ", sort keys %EnO_gwCmd);
      }
      my $gwCmdID;
      $rorg = "A5";
      my $setCmd = 0;
      my $time = 0;
      if ($gwCmd eq "switching") {
        # Switching
        $gwCmdID = 1;
        if($cmd eq "teach") {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          #$data = sprintf "%02X000000", $gwCmdID;
          $data = "E047FF80";
          $updateState = 1;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($cmd eq "on") {
          $setCmd = 9;
          readingsSingleUpdate($hash, "block", "unlock", 1);
          if ($a[1]) {
            return "Usage: $cmd [lock|unlock]" if (($a[1] ne "lock") && ($a[1] ne "unlock"));
            if ($a[1] eq "lock") {
              $setCmd = $setCmd | 4 ;
              readingsSingleUpdate($hash, "block", "lock", 1);
            }
            shift(@a);
          }
          #$updateState = 0;
          $data = sprintf "%02X%04X%02X", $gwCmdID, $time, $setCmd;
        } elsif ($cmd eq "off") {
          if ($model eq "FSA12") {
            $setCmd = 0x0E;
          } else {
            $setCmd = 8;
          }
          readingsSingleUpdate($hash, "block", "unlock", 1);
          if ($a[1]) {
            return "Usage: $cmd [lock|unlock]" if (($a[1] ne "lock") && ($a[1] ne "unlock"));
            if ($a[1] eq "lock") {
              $setCmd = $setCmd | 4 ;
              readingsSingleUpdate($hash, "block", "lock", 1);
            }
            shift(@a);
          }
          #$updateState = 0;
          $data = sprintf "%02X%04X%02X", $gwCmdID, $time, $setCmd;
        } else {
          my $cmdList = "on:noArg off:noArg teach:noArg";
          return SetExtensions ($hash, $cmdList, $name, @a);
        }

      } elsif ($gwCmd eq "dimming") {
        # Dimming
        $gwCmdID = 2;
        my $dimMax = AttrVal($name, "dimMax", 255);
        my $dimMin = AttrVal($name, "dimMin", "off");
        if ($dimMax =~ m/^\d+$/ && $dimMin =~ m/^\d+$/ && $dimMin > $dimMax) {
          ($dimMax, $dimMin) = ($dimMin , $dimMax);
        }
        my $dimVal = ReadingsVal($name, "dim", undef);
        my $rampTime = AttrVal($name, "rampTime", 1);
        my $sendDimCmd = 0;
        $setCmd = 9;
        if ($cmd eq "teach") {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          #$data = "E047FF80";
          # teach-in Eltako
          $data = "02000000";
          $updateState = 1;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($cmd eq "dim") {
          return "Usage: $cmd dim/% [rampTime/s lock|unlock]"
            if(@a < 2 || $a[1] < 0 || $a[1] > 100 || $a[1] !~ m/^[+-]?\d+$/);
          # for eltako relative (0-100) (but not compliant to EEP because DB0.2 is 0)
          # >> if manufID needed: set DB2.0
          $dimVal = $a[1];
	  if ($dimVal > 0) {
	    readingsSingleUpdate ($hash, "dimValueStored", $dimVal, 1);
	  }
          shift(@a);
          if (defined($a[1])) {
            return "Usage: $cmd dim/% [rampTime/s lock|unlock]" if ($a[1] !~ m/^[+-]?\d+$/);
            $rampTime = $a[1];
            shift(@a);
          }
          $sendDimCmd = 1;

        } elsif ($cmd eq "dimup") {
          return "Usage: $cmd dim/% [rampTime/s lock|unlock]"
            if(@a < 2 || $a[1] < 0 || $a[1] > 100 || $a[1] !~ m/^[+-]?\d+$/);
          $dimVal += $a[1];
	  if ($dimVal > 0) {
	    readingsSingleUpdate ($hash, "dimValueStored", $dimVal, 1);
	  }
          shift(@a);
          if (defined($a[1])) {
            return "Usage: $cmd dim/% [rampTime/s lock|unlock]" if ($a[1] !~ m/^[+-]?\d+$/);
            $rampTime = $a[1];
            shift(@a);
          }
          $sendDimCmd = 1;

        } elsif ($cmd eq "dimdown") {
          return "Usage: $cmd dim/% [rampTime/s lock|unlock]"
            if(@a < 2 || $a[1] < 0 || $a[1] > 100 || $a[1] !~ m/^[+-]?\d+$/);
          $dimVal -= $a[1];
	  if ($dimVal > 0) {
	    readingsSingleUpdate ($hash, "dimValueStored", $dimVal, 1);
	  }
          shift(@a);
          if (defined($a[1])) {
            return "Usage: $cmd dim/% [rampTime/s lock|unlock]" if ($a[1] !~ m/^[+-]?\d+$/);
            $rampTime = $a[1];
            shift(@a);
          }
          $sendDimCmd = 1;

        } elsif ($cmd eq "on") {
          $rampTime = 1;
          my $dimValueOn = AttrVal($name, "dimValueOn", 100);
          if ($dimValueOn eq "stored") {
            $dimVal = ReadingsVal($name, "dimValueStored", 100);
            if ($dimVal < 1) {
              $dimVal = 100;
              readingsSingleUpdate ($hash, "dimValueStored", $dimVal, 1);
            }
          } elsif ($dimValueOn eq "last") {
            $dimVal = ReadingsVal ($name, "dimValueLast", 100);
            if ($dimVal < 1) { $dimVal = 100; }
          } else {
            if ($dimValueOn !~ m/^\d+$/) {
              $dimVal = 100;
            } elsif ($dimValueOn > 100) {
              $dimVal = 100;
            } elsif ($dimValueOn < 1) {
              $dimVal = 1;
            } else {
              $dimVal = $dimValueOn;
            }
          }
          $sendDimCmd = 1;

        } elsif ($cmd eq "off") {
          $dimVal = 0;
          $rampTime = 1;
          $setCmd = 8;
          $sendDimCmd = 1;

        } else {
          my $cmdList = "dim:slider,0,1,100 on:noArg off:noArg teach:noArg";
          return SetExtensions ($hash, $cmdList, $name, @a);
        }
        if ($sendDimCmd) {
          readingsSingleUpdate($hash, "block", "unlock", 1);
          if (defined $a[1]) {
            return "Usage: $cmd dim/% [rampTime/s lock|unlock]" if ($a[1] ne "lock" && $a[1] ne "unlock");
            # Eltako devices: lock dimming value
            if ($manufID eq "00D" && $a[1] eq "lock" ) {
              $setCmd = $setCmd | 4;
              readingsSingleUpdate($hash, "block", "lock", 1);
            }
            shift(@a);
          } else {
            # Dimming value relative
            if ($manufID ne "00D") {$setCmd = $setCmd | 4;}
          }
          if ($cmd eq "off" && $dimMin =~ m/^\d+$/ && $dimMin == 0) {
            # switch off
          
          } elsif ($cmd eq "off" && $dimMin =~ m/^\d+$/) {
            $dimVal = $dimMin;
            $setCmd = 9;          
          } elsif ($dimMax eq "off" || $dimVal == 0 && $dimMin eq "off" || $dimVal < 0) {
            # switch off
            $dimVal = 0;
            $setCmd = 8;
          } elsif ($dimMin eq "off") {
          
          } elsif ($dimVal < $dimMin) {
            $dimVal = $dimMin;
          }
          $dimVal = $dimMax if ($dimVal > $dimMax);
          $dimVal = 100 if ($dimVal > 100);
          $rampTime = 0 if ($rampTime < 0);
          $rampTime = 255 if ($rampTime > 255);
          #$updateState = 0;
          readingsSingleUpdate ($hash, "dim", $dimVal, 1);
          $data = sprintf "%02X%02X%02X%02X", $gwCmdID, $dimVal, $rampTime, $setCmd;
        }

      } elsif ($gwCmd eq "setpointShift") {
        $gwCmdID = 3;
        if ($cmd eq "teach") {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          $data = "E047FF80";
          $updateState = 1;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($cmd eq "shift") {
          if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= -12.7) && ($a[1] <= 12.8)) {
            #$updateState = 0;
            $data = sprintf "%02X00%02X08", $gwCmdID, ($a[1] + 12.7) * 10;
            shift(@a);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        } else {
          return "Unknown argument $cmd, choose one of teach:noArg shift";        
        }

      } elsif ($gwCmd eq "setpointBasic") {
        $gwCmdID = 4;
        if($cmd eq "teach") {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          $data = "E047FF80";
          $updateState = 1;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($cmd eq "basic") {
          if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 51.2)) {
            #$updateState = 0;
            $data = sprintf "%02X00%02X08", $gwCmdID, $a[1] * 5;
            shift(@a);
          } else {
            return "Usage: $cmd parameter is not numeric or out of range.";
          }
        } else {
          return "Unknown argument $cmd, choose one of teach:noArg basic";        
        }

      } elsif ($gwCmd eq "controlVar") {
        $gwCmdID = 5;
        my $controlVar = ReadingsVal($name, "controlVar", 0);
        if($cmd eq "teach") {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          $data = "E047FF80";
          $updateState = 1;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($cmd eq "presence") {
          if ($a[1] eq "standby") {
            $setCmd = 0x0A;
          } elsif ($a[1] eq "absent") {
            $setCmd = 9;
          } elsif ($a[1] eq "present") {
            $setCmd = 8;
          } else {
            return "Usage: $cmd parameter unknown.";
          }
          shift(@a);
          $data = sprintf "%02X00%02X%02X", $gwCmdID, $controlVar, $setCmd;
        } elsif ($cmd eq "energyHoldOff") {
          if ($a[1] eq "normal") {
            $setCmd = 8;
          } elsif ($a[1] eq "holdoff") {
            $setCmd = 0x0C;
          } else {
            return "Usage: $cmd parameter unknown.";
          }
          shift(@a);
          $data = sprintf "%02X00%02X%02X", $gwCmdID, $controlVar, $setCmd;
        } elsif ($cmd eq "controllerMode") {
          if ($a[1] eq "auto") {
            $setCmd = 8;
          } elsif ($a[1] eq "heating") {
            $setCmd = 0x28;
          } elsif ($a[1] eq "cooling") {
            $setCmd = 0x48;
          } elsif ($a[1] eq "off" || $a[1] eq "BI") {
            $setCmd = 0x68;
          } else {
            return "Usage: $cmd parameter unknown.";
          }
          shift(@a);
          $data = sprintf "%02X00%02X%02X", $gwCmdID, $controlVar, $setCmd;
        } elsif ($cmd eq "controllerState") {
          if ($a[1] eq "auto") {
            $setCmd = 8;
          } elsif ($a[1] eq "override") {
            $setCmd = 0x18;
            if (defined $a[2] && ($a[2] =~ m/^[+-]?\d+$/) && ($a[2] >= 0) && ($a[2] <= 100) ) {
              $controlVar = $a[2] * 255;
              shift(@a);
            } else {
              return "Usage: Control Variable Override is not numeric or out of range.";
            }
          } else {
            return "Usage: $cmd parameter unknown.";
          }
          shift(@a);
          #$updateState = 0;
          $data = sprintf "%02X00%02X%02X", $gwCmdID, $controlVar, $setCmd;
        } else {
          return "Unknown argument, choose one of teach:noArg presence:absent,present,standby energyHoldOff:holdoff,normal controllerMode:cooling,heating,off controllerState:auto,override";
        }

      } elsif ($gwCmd eq "fanStage") {
        $gwCmdID = 6;
        if($cmd eq "teach") {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          $data = "E047FF80";
          $updateState = 1;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($cmd eq "stage") {
          if ($a[1] eq "auto") {
            #$updateState = 0;
            $data = sprintf "%02X00%02X08", $gwCmdID, 255;
          } elsif ($a[1] && $a[1] =~ m/^[0-3]$/) {
            #$updateState = 0;
            $data = sprintf "%02X00%02X08", $gwCmdID, $a[1];
          } else {
            return "Usage: $cmd parameter is not numeric or out of range"
          }
          shift(@a);          
        } else {
          return "Unknown argument, choose one of teach:noArg stage:auto,0,1,2,3";
        }

      } elsif ($gwCmd eq "blindCmd") {
        $gwCmdID = 7;
        my %blindFunc = (
          "status"         => 0,
          "stop"           => 1,
          "opens"          => 2,
          "closes"         => 3,
          "position"       => 4,
          "up"             => 5,
          "down"           => 6,
          "runtimeSet"     => 7,
          "angleSet"       => 8,
          "positionMinMax" => 9,
          "angleMinMax"    => 10,
          "positionLogic"  => 11,
          "teach"          => 255,
        );
        my $blindFuncID;
        if (defined $blindFunc {$cmd}) {
          $blindFuncID = $blindFunc {$cmd};
        } else {
          return "Unknown Gateway Blind Central Function " . $cmd . ", choose one of ". join(" ", sort keys %blindFunc);
        }
        my $blindParam1 = 0;
        my $blindParam2 = 0;
        $setCmd = $blindFuncID << 4 | 8;

        if($blindFuncID == 255) {
          # teach-in EEP A5-38-08, Manufacturer "Multi user Manufacturer ID"
          $gwCmdID = 0xE0;
          $blindParam1 = 0x47;
          $blindParam2 = 0xFF;
          $setCmd = 0x80;
          $updateState = 1;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($blindFuncID == 0) {
          # status
          $updateState = 0;
        } elsif ($blindFuncID == 1) {
          # stop
          $updateState = 0;
        } elsif ($blindFuncID == 2) {
          # opens
          $updateState = 0;
        } elsif ($blindFuncID == 3) {
          # closes
          $updateState = 0;
        } elsif ($blindFuncID == 4) {
          # position
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
            $blindParam1 = $a[1];
            if (defined $a[2] && $a[2] =~ m/^[+-]?\d+$/ && $a[2] >= -180 && $a[2] <= 180) {
              $blindParam2 = abs($a[2]) / 2;
              if ($a[2] < 0) {$blindParam2 |= 0x80;}
              shift(@a);
            } else {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            # angle und position value available
            $setCmd |= 2;            
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          $updateState = 0;
        } elsif ($blindFuncID == 5 || $blindFuncID == 6) {
          # up / down
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
            $blindParam1 = $a[1];
            if (defined $a[2] && $a[2] =~ m/^[+-]?\d+(\.\d+)?$/ && $a[2] >= 0 && $a[2] <= 25.5) {
              $blindParam2 = $a[2] * 10;
              shift(@a);
            } else {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          $updateState = 0;
        } elsif ($blindFuncID == 7) {
          # runtimeSet
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
            $blindParam1 = $a[1];
            if (defined $a[2] && $a[2] =~ m/^[+-]?\d+$/ && $a[2] >= 0 && $a[2] <= 255) {
              $blindParam2 = $a[2];
              shift(@a);
            } else {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          readingsSingleUpdate($hash, "runTimeUp", $blindParam1, 1);
          readingsSingleUpdate($hash, "runTimeDown", $blindParam2, 1);
          $updateState = 0;
        } elsif ($blindFuncID == 8) {
          # angleSet
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+(\.\d+)?$/ && $a[1] >= 0 && $a[1] <= 25.5) {
            $blindParam1 = $a[1] * 10;
            ##
            readingsSingleUpdate($hash, "angleTime", (sprintf "%0.1f", $a[1]), 1);
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          $updateState = 0;
        } elsif ($blindFuncID == 9) {
          # positionMinMax
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
            $blindParam1 = $a[1];
            if (defined $a[2] && $a[2] =~ m/^[+-]?\d+$/ && $a[2] >= 0 && $a[2] <= 100) {
              $blindParam2 = $a[2];
              shift(@a);
            } else {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            # angle und position value available
            $setCmd |= 2;            
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          if ($blindParam1 > $blindParam2) {($blindParam1, $blindParam2) = ($blindParam2, $blindParam1);}
          readingsSingleUpdate($hash, "positionMin", $blindParam1, 1);
          readingsSingleUpdate($hash, "positionMax", $blindParam2, 1);
          $updateState = 0;
        } elsif ($blindFuncID == 10) {
          # angleMinMax
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= -180 && $a[1] <= 180) {
            if (!defined $a[2] || $a[2] !~ m/^[+-]?\d+$/ || $a[2] < -180 || $a[2] > 180) {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            if ($a[1] > $a[2]) {($a[1], $a[2]) = ($a[2], $a[1]);}
            $blindParam1 = abs($a[1]) / 2;
            if ($a[1] < 0) {$blindParam1 |= 0x80;}
            $blindParam2 = abs($a[2]) / 2;
            if ($a[2] < 0) {$blindParam2 |= 0x80;}
            # angle und position value available
            $setCmd |= 2;            
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          readingsSingleUpdate($hash, "angleMin", $a[1], 1);
          readingsSingleUpdate($hash, "angleMax", $a[2], 1);
          splice (@a, 0, 2);
          shift(@a);
          $updateState = 0;
        } elsif ($blindFuncID == 11) {
          # positionLogic
          if ($a[1] eq "normal") {
            $blindParam1 = 0;
          } elsif ($a[1] eq "inverse") {
            $blindParam1 = 1;
          } else {
            return "Usage: $cmd variable is unknown.";
          }
          shift(@a);
          $updateState = 0;
        } else {
        }
        ####
        $setCmd |= 4 if (AttrVal($name, "sendDevStatus", "no") eq "yes");
        $setCmd |= 1 if (AttrVal($name, "serviceOn", "no") eq "yes");
        $data = sprintf "%02X%02X%02X%02X", $gwCmdID, $blindParam1, $blindParam2, $setCmd;

      } else {
        return "Unknown Gateway command " . $cmd . ", choose one of ". $cmdList . join(" ", sort keys %EnO_gwCmd);
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "energyManagement.01") {
      # Energy Management, Demand Response
      # (A5-37-01)
      $rorg = "A5";
      $updateState = 0;
      my $drLevel = 15;
      my $powerUsage = 100;
      my $powerUsageLevel = 1;
      my $powerUsageScale = 0;
      my $randomStart = 0;
      my $randomEnd = 0;
      my $randomTime = rand(AttrVal($name, "demandRespRandomTime", 1));
      my $setpoint = 255;
      my $timeout = 0;
      my $threshold = AttrVal($name, "demandRespThreshold", 8);
      
      if($cmd eq "teach") {
        # teach-in EEP A5-37-01, Manufacturer "Multi user Manufacturer ID"
        $data = "DC0FFF80";
        $updateState = 1;
        ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        readingsSingleUpdate($hash, "state", "teach", 1);
        Log3 $name, 3, "EnOcean set $name $cmd";

      } elsif ($cmd eq "level") {
        return "Usage: $cmd 0...15 [max|rel [yes|no [yes|no [timeout/min]]]]"
          if(@a < 2 || $a[1] !~ m/^\d+$/ || $a[1] < 0 || $a[1] > 15 );
        $drLevel = $a[1];
        $powerUsage = $a[1] / 15 * 100;
        $powerUsageLevel = $drLevel >= $threshold ? 1 : 0;
        $setpoint = $a[1] * 17;
        shift(@a);
      
      } elsif ($cmd eq "max") {

      } elsif ($cmd eq "min") {
        $drLevel = 0;
        $powerUsage = 0;
        $powerUsageLevel = 0;
        $setpoint = 0;
     
      } elsif ($cmd eq "power") {
        return "Usage: $cmd 0...100 [max|rel [yes|no [yes|no [timeout/min]]]]"
          if(@a < 2 || $a[1] !~ m/^\d+$/ || $a[1] < 0 || $a[1] > 100);
        $drLevel = $a[1] / 100 * 15;
        $powerUsage = $a[1];
        $powerUsageLevel = $drLevel >= $threshold ? 1 : 0;
        $setpoint = $a[1] * 2.55;
        shift(@a);
      
      } elsif ($cmd eq "setpoint") {
        return "Usage: $cmd 0...255 [max|rel [yes|no [yes|no [timeout/min]]]]"
          if(@a < 2 || $a[1] !~ m/^\d+$/ || $a[1] < 0 || $a[1] > 255 );
        $drLevel = $a[1] / 255 * 15 ;
        $powerUsage = $a[1] / 255 * 100;
        $powerUsageLevel = $drLevel >= $threshold ? 1 : 0;
        $setpoint = $a[1];
        shift(@a);
      
      } else {
        return "Unknown argument " . $cmd . ", choose one of " . $cmdList . "level:slider,0,1,15 max:noArg min:noArg power:slider,0,5,100 setpoint:slider,0,5,255 teach:noArg"
      }

      if ($cmd ne "teach") {
        if (@a > 1) {
          return "Usage: $cmd [<cmdValue>] [max|rel [yes|no [yes|no [timeout/min]]]]" if($a[1] !~ m/^max|rel$/);
          $powerUsageScale = $a[1] eq "rel" ? 0x80 : 0;
          shift(@a);
        }
        if (@a > 1) {
          return "Usage: $cmd [<cmdValue>] [max|rel [yes|no [yes|no [timeout/min]]]]" if($a[1] !~ m/^yes|no$/);
          $randomStart = $a[1] eq "yes" ? 4 : 0;
          shift(@a);
        }
        if (@a > 1) {
          return "Usage: $cmd [<cmdValue>] [max|rel [yes|no [yes|no [timeout/min]]]]" if($a[1] !~ m/^yes|no$/);
          $randomEnd = $a[1] eq "yes" ? 2 : 0;
          shift(@a);
        }
        if (@a > 1) {
          return "Usage: $cmd [<cmdValue>] [max|rel [yes|no [yes|no [timeout/min]]]]"
            if($a[1] !~ m/^\d+$/ || $a[1] < 0 || $a[1] > 3825);
          $timeout = int($a[1] / 15);
          shift(@a);
        }
        $data = sprintf "%02X%02X%02X%02X", $setpoint, $powerUsageScale | $powerUsage, $timeout,
                                            $drLevel << 4 | $randomStart | $randomEnd | $powerUsageLevel | 8;
        my @db = ($drLevel << 4 | $randomStart | $randomEnd | $powerUsageLevel | 8,
                  $timeout, $powerUsageScale | $powerUsage, $setpoint);
        EnOcean_energyManagement_01Parse($hash, @db);
      }
      #shift(@a);
      Log3 $name, 3, "EnOcean set $name $cmd";
    
    } elsif ($st eq "lightCtrl.01") {
      # Central Command, Extended Lighting-Control 
      # (A5-38-09)
      $rorg = "A5";      
      my %ctrlFunc = (
        "off"            => 1,
        "on"             => 2,
        "dimup"          => 3,
        "dimdown"        => 4,
        "stop"           => 5,
        "dim"            => 6,
        "rgb"            => 7,
        "scene"          => 8,
        "dimMinMax"      => 9,
        "lampOpHours"    => 10,
        "block"          => 11,
        "meteringValue"  => 12,
        "teach"          => 255,
      );
      my $ctrlFuncID;
      if (defined $ctrlFunc{$cmd}) {
        $ctrlFuncID = $ctrlFunc{$cmd};
      } else {
        $cmdList .= "dim:slider,0,5,255 dimup:noArg dimdown:noArg on:noArg off:noArg stop:noArg rgb:colorpicker,RGB scene dimMinMax lampOpHours block meteringValue teach:noArg";
        return SetExtensions ($hash, $cmdList, $name, @a);
      }
      my ($ctrlParam1, $ctrlParam2, $ctrlParam3) = (0, 0, 0);
      my $setCmd = $ctrlFuncID << 4 | 8;

      if($ctrlFuncID == 255) {
        # teach-in EEP A5-38-09, Manufacturer "Multi user Manufacturer ID"
        $ctrlParam1 = 0xE1;
        $ctrlParam2 = 0xC7;
        $ctrlParam3 = 0xFF;
        $setCmd = 0x80;
        ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        readingsSingleUpdate($hash, "state", $cmd, 1);
        $updateState = 0;
      } elsif ($ctrlFuncID == 1) {
        # off
        CommandDeleteReading(undef, "$name scene");
        $updateState = 0;
      } elsif ($ctrlFuncID == 2) {
        # on
        CommandDeleteReading(undef, "$name scene");
        $updateState = 0;
      } elsif ($ctrlFuncID == 3 || $ctrlFuncID == 4) {
        # dimup / dimdown
        my $rampTime = $a[1];
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+?$/ && $a[1] >= 0 && $a[1] <= 65535) {
            shift(@a);
          } else {
            return "Usage: $cmd ramping time value is not numeric or out of range.";
          }
        } else {
          $rampTime = AttrVal($name, "rampTime", 1);
        }
        $ctrlParam3 = $rampTime & 0xFF;
        $ctrlParam2 = ($rampTime & 0xFF00) >> 8;
        readingsSingleUpdate($hash, "rampTime", $rampTime, 1);
        CommandDeleteReading(undef, "$name scene");
        $updateState = 0;
      } elsif ($ctrlFuncID == 5) {
        # stop
        CommandDeleteReading(undef, "$name scene");
        $updateState = 0;
      } elsif ($ctrlFuncID == 6) {
        # dim
        if (defined $a[1] && $a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
          $ctrlParam1 = $a[1];
          shift(@a);
        } else {
          return "Usage: $cmd dimming value is not numeric or out of range.";
        }
        my $rampTime = $a[1];
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+?$/ && $a[1] >= 0 && $a[1] <= 65535) {
            shift(@a);
          } else {
            return "Usage: $cmd ramping time value is not numeric or out of range.";
          }
        } else {
          $rampTime = AttrVal($name, "rampTime", 1);
        }
        $ctrlParam3 = $rampTime & 0xFF;
        $ctrlParam2 = ($rampTime & 0xFF00) >> 8;
        CommandDeleteReading(undef, "$name scene");
        readingsSingleUpdate($hash, "rampTime", $rampTime, 1);
        $updateState = 0;
      } elsif ($ctrlFuncID == 7) {
        # RGB
        if (@a > 1) {
          if ($a[1] =~ m/^[\dA-Fa-f]{6}$/) {
            # red
            $ctrlParam1 = hex substr($a[1], 0, 2);
            # green
            $ctrlParam2 = hex substr($a[1], 2, 2);
            # blue
            $ctrlParam3 = hex substr($a[1], 4, 2);
            readingsSingleUpdate($hash, "rgb", uc($a[1]), 1);
            shift(@a);
          } else {
            return "Usage: $cmd value is not hexadecimal or out of range.";
          }
        } else {
          return "Usage: $cmd values are missing";
        }
        $updateState = 0;
      } elsif ($ctrlFuncID == 8) {
        # scene
          if (@a > 2) {
          if ($a[2] =~ m/^\d+?$/ && $a[2] >= 0 && $a[2] <= 15) {
            $ctrlParam3 = $a[2];
          } else {
            return "Usage: $cmd number is not numeric or out of range.";
          }
          if ($a[1] eq "drive") {
            readingsSingleUpdate($hash, "scene", $ctrlParam3, 1);
            splice(@a, 0, 2);
          } elsif ($a[1] eq "store") {
            $ctrlParam3 |= 0x80;
            splice(@a, 0, 2);
          } else {
            return "Usage: $cmd parameter is wrong.";            
          }

        } else {
          return "Usage: $cmd values are missing";
        }
        $updateState = 0;
      } elsif ($ctrlFuncID == 9) {
        # dimMinMax
        if (@a > 2) {
          if ($a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
            # dimming limit min
            $ctrlParam1 = $a[1];
            shift(@a);
          } else {
            return "Usage: $cmd value is not numeric or out of range.";
          }
          if ($a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
            # dimming limit max
            $ctrlParam2 = $a[1];
            shift(@a);
          } else {
            return "Usage: $cmd value is not numeric or out of range.";
          }
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "dimMin", $ctrlParam1);
          readingsBulkUpdate($hash, "dimMax", $ctrlParam2);
          readingsEndUpdate($hash, 1);
        } else {
          return "Usage: $cmd values are missing";
        }
          $updateState = 0;
        } elsif ($ctrlFuncID == 10) {
          # set operating hours of the lamp
          if (defined $a[1] && $a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 65535) {
            $ctrlParam2 = $a[1] & 0xFF;
            $ctrlParam1 = ($a[1] & 0xFF00) >> 8;
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          $updateState = 0;
      } elsif ($ctrlFuncID == 11) {
          # block
          if (!defined $a[1]) {
            return "Usage: $cmd values are missing";
          } elsif ($a[1] eq "unlock") {
          $ctrlParam3 = 0;
          } elsif ($a[1] eq "on") {
            $ctrlParam3 = 1;
          } elsif ($a[1] eq "off") {
            $ctrlParam3 = 2;
          } elsif ($a[1] eq "local") {
            $ctrlParam3 = 3;
          } else {
            return "Usage: $cmd variable is unknown.";
          }
          readingsSingleUpdate($hash, "block", $a[1], 1);
          shift(@a);
          $updateState = 0;
      } elsif ($ctrlFuncID == 12) {
          # meteringValues
          if (@a > 2) {
            my %unitEnum = (
              "mW"  => 0,
              "W"   => 1,
              "kW"  => 2,
              "MW"  => 3,
              "Wh"  => 4,
              "kWh" => 5,
              "MWh" => 6,
              "GWh" => 7,
              "mA"  => 8,
              "A"   => 9,
              "mV"  => 10,
              "V"   => 11,
            );
            if (defined $unitEnum{$a[2]}) {
              $ctrlParam3 = $unitEnum{$a[2]};
            } else {
              return "Unknown metering value choose one of " . join(" ", sort keys %unitEnum);
            }

            if ($ctrlParam3 == 9 || $ctrlParam3 == 11) {
              if ($a[1] =~ m/^\d+(\.\d+)?$/ && $a[1] >= 0 && $a[1] <= 6553.5) {
                $ctrlParam2 = int($a[1] * 10) & 0xFF;
                $ctrlParam1 = (int($a[1] * 10) & 0xFF00) >> 8;
              } else {
                return "Usage: $cmd value is not numeric or out of range.";
              }
            } else {
              if ($a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 65535) {
                $ctrlParam2 = $a[1] & 0xFF;
                $ctrlParam1 = ($a[1] & 0xFF00) >> 8;
              } else {
                return "Usage: $cmd value is not numeric or out of range.";
              }
            }
            splice(@a, 0, 2);

          } else {
            return "Usage: $cmd values are missing";
          }          
          $updateState = 0;
      }
      ####
      $setCmd |= 4 if (AttrVal($name, "sendDevStatus", "yes") eq "no");
      $setCmd |= 1 if (AttrVal($name, "serviceOn", "no") eq "yes");
      $data = sprintf "%02X%02X%02X%02X", $ctrlParam1, $ctrlParam2, $ctrlParam3, $setCmd;
      #shift(@a);
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "manufProfile") {
      if ($manufID eq "00D") {
        # Eltako Shutter
        my $angleMax = AttrVal($name, "angleMax", 90);
        my $angleMin = AttrVal($name, "angleMin", -90);
        my $anglePos = ReadingsVal($name, "anglePos", undef);
        my $anglePosStart;
        my $angleTime = AttrVal($name, "angleTime", 0);
        my $position = ReadingsVal($name, "position", undef);
        my $positionStart;
        if ($cmd eq "?" || $cmd eq "stop") {
        
        } else {
          # check actual shutter position
	  my $actualState = ReadingsVal($name, "state", undef);
	  if (defined $actualState) {
	    if ($actualState eq "open") {
	      $position = 0;
	      $anglePos = 0;              
	    } elsif ($actualState eq "closed") {
	      $position = 100;
	      $anglePos = $angleMax;
	    }
	  }
          $anglePosStart = $anglePos;
          $positionStart = $position;        
          readingsSingleUpdate($hash, ".anglePosStart", $anglePosStart, 0);          
          readingsSingleUpdate($hash, ".positionStart", $positionStart, 0);
        }
        $rorg = "A5";
        my $shutTime = AttrVal($name, "shutTime", 255);
        my $shutTimeCloses = AttrVal($name, "shutTimeCloses", $shutTime);
        $shutTimeCloses = $shutTime if ($shutTimeCloses < $shutTime);
        my $shutCmd = 0;
        $angleMax = 90 if ($angleMax !~ m/^[+-]?\d+$/);
        $angleMax = 180 if ($angleMax > 180);
        $angleMax = -180 if ($angleMax < -180);
        $angleMin = -90 if ($angleMin !~ m/^[+-]?\d+$/);
        $angleMin = 180 if ($angleMin > 180);
        $angleMin = -180 if ($angleMin < -180);
        ($angleMax, $angleMin) = ($angleMin, $angleMax) if ($angleMin > $angleMax);
        $angleMax ++ if ($angleMin == $angleMax);
        $angleTime = 6 if ($angleTime !~ m/^[+-]?\d+$/);
        $angleTime = 6 if ($angleTime > 6);
        $angleTime = 0 if ($angleTime < 0);
        $shutTime = 255 if ($shutTime !~ m/^[+-]?\d+$/);
        $shutTime = 255 if ($shutTime > 255);
        $shutTime = 1 if ($shutTime < 1);
        if ($cmd eq "teach") {
          # teach-in EEP A5-3F-7F, Manufacturer "Eltako"
          CommandDeleteReading(undef, "$name .*");
          $data = "FFF80D80";
          $updateState = 1;
          ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "confirm");
        } elsif ($cmd eq "stop") {
          # stop
          # delete readings, as they are undefined
          CommandDeleteReading(undef, "$name anglePos");
          CommandDeleteReading(undef, "$name position");
          readingsSingleUpdate($hash, "endPosition", "not_reached", 1);
          readingsSingleUpdate($hash, "state", "stop", 1);
          $shutCmd = 0;
        } elsif ($cmd eq "opens") {
          # opens >> B0
          $anglePos = 0;
          $position = 0;
          readingsSingleUpdate($hash, "anglePos", $anglePos, 1);
          readingsSingleUpdate($hash, "position", $position, 1);
          readingsSingleUpdate($hash, "endPosition", "open", 1);
          $cmd = "open";
          $shutTime = $shutTimeCloses;
          $shutCmd = 1;
          #$updateState = 0;
        } elsif ($cmd eq "closes") {
          # closes >> BI
          $anglePos = $angleMax;
          $position = 100;
          readingsSingleUpdate($hash, "anglePos", $anglePos, 1);
      	  readingsSingleUpdate($hash, "position", $position, 1);
          readingsSingleUpdate($hash, "endPosition", "closed", 1);
          $cmd = "closed";
          $shutTime = $shutTimeCloses;
          $shutCmd = 2;
          #$updateState = 0;
        } elsif ($cmd eq "up") {
          # up
          if (defined $a[1]) {
            if ($a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
              $position = $positionStart - $a[1] / $shutTime * 100;
              if ($angleTime) {
                $anglePos = $anglePosStart - ($angleMax - $angleMin) * $a[1] / $angleTime;
                if ($anglePos < $angleMin) {
                  $anglePos = $angleMin;
                }
              } else {
                $anglePos = $angleMin;                
              }
              if ($position <= 0) {
                $anglePos = 0;
                $position = 0;
                readingsSingleUpdate($hash, "endPosition", "open", 1);
                $cmd = "open";
              } else {
                readingsSingleUpdate($hash, "endPosition", "not_reached", 1);
                $cmd = "not_reached";
              }
              $shutTime = $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          } else {
            $anglePos = 0;
            $position = 0;
            readingsSingleUpdate($hash, "endPosition", "open", 1);
            $cmd = "open";
          }
          readingsSingleUpdate($hash, "anglePos", sprintf("%d", $anglePos), 1);
      	  readingsSingleUpdate($hash, "position", sprintf("%d", $position), 1);
          $shutCmd = 1;
        } elsif ($cmd eq "down") {
          # down
          if (defined $a[1]) {
            if ($a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] < 255) {
              $position = $positionStart + $a[1] / $shutTime * 100;
              if ($angleTime) {              
                $anglePos = $anglePosStart + ($angleMax - $angleMin) * $a[1] / $angleTime;              
                if ($anglePos > $angleMax) {
                  $anglePos = $angleMax;
                }
              } else {
                $anglePos = $angleMax;                
              }
              if($position >= 100) { 
                $anglePos = $angleMax;
                $position = 100;
                readingsSingleUpdate($hash, "endPosition", "closed", 1);
                $cmd = "closed";
              } else {
                readingsSingleUpdate($hash, "endPosition", "not_reached", 1);
                $cmd = "not_reached";
              }
              $shutTime = $a[1];
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          } else {
            $anglePos = $angleMax;
            $position = 100;
            readingsSingleUpdate($hash, "endPosition", "closed", 1);
            $cmd = "closed";
          }
          readingsSingleUpdate($hash, "anglePos", sprintf("%d", $anglePos), 1);
          readingsSingleUpdate($hash, "position", sprintf("%d", $position), 1);
          $shutCmd = 2;
        } elsif ($cmd eq "position") {
          if (!defined $positionStart) {
            return "Position unknown, please first opens the blinds completely."
          } elsif ($angleTime > 0 && !defined $anglePosStart){
            return "Slats angle position unknown, please first opens the blinds completely."
          } else {
            my $shutTimeSet = $shutTime;
            if (defined $a[2]) {
              if ($a[2] =~ m/^[+-]?\d+$/ && $a[2] >= $angleMin && $a[2] <= $angleMax) {
                $anglePos = $a[2];
              } else {
                return "Usage: $a[1] $a[2] is not numeric or out of range";
              }
              splice(@a,2,1);
            } else {
              $anglePos = $angleMax;              
            }
            if ($positionStart <= $angleTime * $angleMax / ($angleMax - $angleMin) / $shutTimeSet * 100) {
              $anglePosStart = $angleMax;
            }
            if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
              if ($positionStart < $a[1]) {
                # down
                $angleTime = $angleTime * ($angleMax - $anglePos) / ($angleMax - $angleMin);                
                $shutTime = $shutTime  * ($a[1] - $positionStart) / 100 + $angleTime;
                # round up
                $angleTime = int($angleTime) + 1 if ($angleTime > int($angleTime));
                $shutTime = int($shutTime) + 1 if ($shutTime > int($shutTime));
                $position = $a[1] + $angleTime / $shutTimeSet * 100;
                if ($position >= 100) {
                  $position = 100;
                }
                $shutCmd = 2;
                if ($angleTime) {
                  my @timerCmd = ($name, "up", $angleTime);
                  my %par = (hash => $hash, timerCmd => \@timerCmd);
                  InternalTimer(gettimeofday() + $shutTime + 1, "EnOcean_TimerSet", \%par, 0);
                }
              } elsif ($positionStart > $a[1]) {
                # up
                $angleTime = $angleTime * ($anglePos - $angleMin) /($angleMax - $angleMin);
                $shutTime = $shutTime * ($positionStart - $a[1]) / 100 + $angleTime;
                # round up
                $angleTime = int($angleTime) + 1 if ($angleTime > int($angleTime));
                $shutTime = int($shutTime) + 1 if ($shutTime > int($shutTime));
                $position = $a[1] - $angleTime / $shutTimeSet * 100;
                if ($position <= 0) {
                  $position = 0;
                  $anglePos = 0;
                }
                $shutCmd = 1;
                if ($angleTime && $a[1] > 0) {
                  my @timerCmd = ($name, "down", $angleTime);
                  my %par = (hash => $hash, timerCmd => \@timerCmd);
                  InternalTimer(gettimeofday() + $shutTime + 1, "EnOcean_TimerSet", \%par, 0);                
                }
              } else {
                if ($anglePosStart > $anglePos) {
                  # up >> reduce slats angle
                  $shutTime = $angleTime * ($anglePosStart - $anglePos)/($angleMax - $angleMin);
                  # round up
                  $shutTime = int($shutTime) + 1 if ($shutTime > int($shutTime));
                  $shutCmd = 1;
                } elsif ($anglePosStart < $anglePos) {
                  # down >> enlarge slats angle
                  $shutTime = $angleTime * ($anglePos - $anglePosStart) /($angleMax - $angleMin);
                  # round up
                  $shutTime = int($shutTime) + 1 if ($shutTime > int($shutTime));
                  $shutCmd = 2;
                } else {
                  # position and slats angle ok
                  $shutCmd = 0;
                }             
              }
              if ($position == 0) {
                readingsSingleUpdate($hash, "endPosition", "open", 1);
                $cmd = "open";
              } elsif ($position == 100) {
                readingsSingleUpdate($hash, "endPosition", "closed", 1);
                $cmd = "closed";
              } else {
                readingsSingleUpdate($hash, "endPosition", "not_reached", 1);
                $cmd = "not_reached";
              }
              readingsSingleUpdate($hash, "anglePos", sprintf("%d", $anglePos), 1);
              readingsSingleUpdate($hash, "position", sprintf("%d", $position), 1);
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          }
        } else {
          return "Unknown argument " . $cmd . ", choose one of " . $cmdList . "closes:noArg down opens:noArg position:slider,0,5,100 stop:noArg teach:noArg up"
        }
        if ($shutCmd || $cmd eq "stop") {
          #$updateState = 0;
          $data = sprintf "%02X%02X%02X%02X", 0, $shutTime, $shutCmd, 8;
        }
        Log3 $name, 3, "EnOcean set $name $cmd";
      }

    } elsif ($st eq "actuator.01") {
      # Electronic switches and dimmers with Energy Measurement and Local Control
      # (D2-01-00 - D2-01-11)
      $rorg = "D2";
      #$updateState = 0;
      my $cmdID;
      my $channel;
      my $dimValTimer = 0;
      my $outputVal;

      if ($cmd eq "on") {
        shift(@a);
        $cmdID = 1;
        my $dimValueOn = AttrVal($name, "dimValueOn", 100);
        if ($dimValueOn eq "stored") {
          $outputVal = ReadingsVal($name, "dimValueStored", 100);
          if ($outputVal < 1) {
            $outputVal = 100;
            readingsSingleUpdate ($hash, "dimValueStored", $outputVal, 1);
          }
        } elsif ($dimValueOn eq "last") {
          $outputVal = ReadingsVal ($name, "dimValueLast", 100);
          if ($outputVal < 1) { $outputVal = 100; }
        } else {
          if ($dimValueOn !~ m/^[+-]?\d+$/) {
            $outputVal = 100;
          } elsif ($dimValueOn > 100) {
            $outputVal = 100;
          } elsif ($dimValueOn < 1) {
            $outputVal = 1;
          } else {
            $outputVal = $dimValueOn;
          }
        }
        $channel = shift(@a);
        $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
        if (!defined $channel || $channel eq "all") {
          CommandDeleteReading(undef, "$name channel.*");          
          CommandDeleteReading(undef, "$name dim.*");          
          readingsSingleUpdate($hash, "channelAll", "on", 1);
          readingsSingleUpdate($hash, "dim", $outputVal, 1);
          $channel = 30;
        } elsif ($channel eq "input" || $channel + 0 == 31) {
          readingsSingleUpdate($hash, "channelInput", "on", 1);
          readingsSingleUpdate($hash, "dimInput", $outputVal, 1);
          $channel = 31;
        } elsif ($channel + 0 >= 30) {
          CommandDeleteReading(undef, "$name channel.*");          
          CommandDeleteReading(undef, "$name dim.*");          
          readingsSingleUpdate($hash, "channelAll", "on", 1);
          readingsSingleUpdate($hash, "dim", $outputVal, 1);
          $channel = 30;
        } elsif ($channel + 0 >= 0 && $channel + 0 <= 29) {
          readingsSingleUpdate($hash, "channel" . $channel, "on", 1);
          readingsSingleUpdate($hash, "dim" . $channel, $outputVal, 1);
        } else {
          return "$cmd $channel wrong, choose 0...29|all|input.";
        }     
        #readingsSingleUpdate($hash, "state", "on", 1);
        $data = sprintf "%02X%02X%02X", $cmdID, $dimValTimer << 5 | $channel, $outputVal;
        
      } elsif ($cmd eq "off") {
        shift(@a);
        $cmdID = 1;
        $outputVal = 0;
        $channel = shift(@a);
        $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
        if (!defined $channel || $channel eq "all") {
          CommandDeleteReading(undef, "$name channel.*");          
          CommandDeleteReading(undef, "$name dim.*");          
          readingsSingleUpdate($hash, "channelAll", "off", 1);
          readingsSingleUpdate($hash, "dim", $outputVal, 1);
          $channel = 30;
        } elsif ($channel eq "input" || $channel + 0 == 31) {
          readingsSingleUpdate($hash, "channelInput", "off", 1);
          readingsSingleUpdate($hash, "dimInput", $outputVal, 1);
          $channel = 31;
        } elsif ($channel + 0 >= 30) {
          CommandDeleteReading(undef, "$name channel.*");          
          CommandDeleteReading(undef, "$name dim.*");          
          readingsSingleUpdate($hash, "channelAll", "off", 1);
          readingsSingleUpdate($hash, "dim", $outputVal, 1);
          $channel = 30;
        } elsif ($channel >= 0 && $channel <= 29) {
          readingsSingleUpdate($hash, "channel" . $channel, "off", 1);
          readingsSingleUpdate($hash, "dim" . $channel, $outputVal, 1);
        } else {
          return "$cmd $channel wrong, choose 0...39|all|input.";
        }     
        #readingsSingleUpdate($hash, "state", "off", 1);
        $data = sprintf "%02X%02X%02X", $cmdID, $dimValTimer << 5 | $channel, $outputVal;
        
      } elsif ($cmd eq "dim") {
        shift(@a);
        $cmdID = 1;
        $outputVal = shift(@a);
        if (!defined $outputVal || $outputVal !~ m/^[+-]?\d+$/ || $outputVal < 0 || $outputVal > 100) {
          return "Usage: $cmd variable is not numeric or out of range.";
        }
        $channel = shift(@a);
        $channel = AttrVal($name, "defaultChannel", AttrVal($name, "devChannel", undef)) if (!defined $channel);
        if (!defined $channel) {
          CommandDeleteReading(undef, "$name channel.*");          
          CommandDeleteReading(undef, "$name dim.*");          
          if ($outputVal == 0) {
            readingsSingleUpdate($hash, "channelAll", "off", 1);
          } else {
            readingsSingleUpdate($hash, "channelAll", "on", 1);          
          }
          readingsSingleUpdate($hash, "dim", $outputVal, 1);
          $channel = 30;
        } else {
          if ($channel eq "all") {
            CommandDeleteReading(undef, "$name channel.*");          
            CommandDeleteReading(undef, "$name dim.*");          
            if ($outputVal == 0) {
              readingsSingleUpdate($hash, "channelAll", "off", 1);
            } else {
              readingsSingleUpdate($hash, "channelAll", "on", 1);          
            }
            readingsSingleUpdate($hash, "dim", $outputVal, 1);
            $channel = 30;
          } elsif ($channel eq "input" || $channel + 0 == 31) {
            if ($outputVal == 0) {
              readingsSingleUpdate($hash, "channelInput", "off", 1);
            } else {
              readingsSingleUpdate($hash, "channelInput", "on", 1);          
            }
            readingsSingleUpdate($hash, "dimInput", $outputVal, 1);
            $channel = 31;
          } elsif ($channel + 0 >= 30) {
            CommandDeleteReading(undef, "$name channel.*");          
            CommandDeleteReading(undef, "$name dim.*");          
            if ($outputVal == 0) {
              readingsSingleUpdate($hash, "channelAll", "off", 1);
            } else {
              readingsSingleUpdate($hash, "channelAll", "on", 1);          
            }
            readingsSingleUpdate($hash, "dim", $outputVal, 1);
            $channel = 30;
          } elsif ($channel >= 0 && $channel <= 29) {
            if ($outputVal == 0) {
              readingsSingleUpdate($hash, "channel" . $channel, "off", 1);
            } else {
              readingsSingleUpdate($hash, "channel" . $channel, "on", 1);          
            }
            readingsSingleUpdate($hash, "dim" . $channel, $outputVal, 1);
          } else {
            return "Usage: $cmd $channel wrong, choose 0...39|all|input.";
          }
          $dimValTimer = shift(@a);
          if (defined $dimValTimer) {
            if ($dimValTimer eq "switch") {
              $dimValTimer = 0;
            } elsif ($dimValTimer eq "stop") {
              $dimValTimer = 4;            
            } elsif ($dimValTimer =~ m/^[1-3]$/) {
            
            } else {
              return "Usage: $cmd <channel> $dimValTimer wrong, choose 1..3|switch|stop.";
            }
          } else {
            $dimValTimer = 0;
          }
        }
        if ($outputVal == 0) {
          $cmd = "off";     
          #readingsSingleUpdate($hash, "state", "off", 1);
        } else {
          $cmd = "on";
          #readingsSingleUpdate($hash, "state", "on", 1);          
        }
        $data = sprintf "%02X%02X%02X", $cmdID, $dimValTimer << 5 | $channel, $outputVal;
        
      } elsif ($cmd eq "local") {
        shift(@a);
        $updateState = 0;
        $cmdID = 2;
        # same configuration for all channels  
        $channel = 30;
        my $dayNight = ReadingsVal($name, "dayNight", "day");
        my $dayNightCmd = ($dayNight eq "night")? 1:0;
        my $defaultState = ReadingsVal($name, "defaultState", "off");
        my $defaultStateCmd;
        if ($defaultState eq "off") {
          $defaultStateCmd = 0;
        } elsif ($defaultState eq "on") {
          $defaultStateCmd = 1;
        } elsif ($defaultState eq "last") {
          $defaultStateCmd = 2;
        } else {
          $defaultStateCmd = 0;
        }
        my $localControl = ReadingsVal($name, "localControl", "disabled");
        my $localControlCmd = ($localControl eq "enabled")? 1:0;
        my $overCurrentShutdown = ReadingsVal($name, "overCurrentShutdown", "off");
        my $overCurrentShutdownCmd = ($overCurrentShutdown eq "restart")? 1:0;
        my $overCurrentShutdownReset = "not_active";
        my $overCurrentShutdownResetCmd = 0;
        my $rampTime1 = ReadingsVal($name, "rampTime1", 0);
        my $rampTime1Cmd = $rampTime1 * 2;
        if ($rampTime1Cmd <= 0) {
           $rampTime1Cmd = 0;
        } elsif ($rampTime1Cmd >= 15) {
           $rampTime1Cmd = 15;        
        }
        my $rampTime2 = ReadingsVal($name, "rampTime2", 0);
        my $rampTime2Cmd = $rampTime2 * 2;       
        if ($rampTime2Cmd <= 0) {
           $rampTime2Cmd = 0;
        } elsif ($rampTime2Cmd >= 15) {
           $rampTime2Cmd = 15;        
        }
        my $rampTime3 = ReadingsVal($name, "rampTime3", 0);
        my $rampTime3Cmd = $rampTime3 * 2;        
        if ($rampTime3Cmd <= 0) {
           $rampTime3Cmd = 0;
        } elsif ($rampTime3Cmd >= 15) {
           $rampTime3Cmd = 15;        
        }
        my $teachInDev = ReadingsVal($name, "teachInDev", "disabled");
        my $teachInDevCmd = ($teachInDev eq "enabled")? 1:0;
        my $localCmd = shift(@a);
        my $localCmdVal = shift(@a);
        if ($localCmd eq "dayNight") {
          if ($localCmdVal eq "day") {
            $dayNight = "day";        
            $dayNightCmd = 0;        
          } elsif ($localCmdVal eq "night") {
            $dayNight = "night";        
            $dayNightCmd = 1;          
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose day night.";
          }
        } elsif ($localCmd eq "defaultState"){
          if ($localCmdVal eq "off") {
            $defaultState = "off";        
            $defaultStateCmd = 0;        
          } elsif ($localCmdVal eq "on") {
            $defaultState = "on";        
            $defaultStateCmd = 1;          
          } elsif ($localCmdVal eq "last") {
            $defaultState = "last";        
            $defaultStateCmd = 2;          
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose on off last.";
          }
        } elsif ($localCmd eq "localControl"){
          if ($localCmdVal eq "disabled") {
            $localControl = "disabled";        
            $localControlCmd = 0;        
          } elsif ($localCmdVal eq "enabled") {
            $localControl = "enabled";        
            $localControlCmd = 1;          
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose disabled enabled.";
          }
        } elsif ($localCmd eq "overCurrentShutdown"){
          if ($localCmdVal eq "off") {
            $overCurrentShutdown = "off";        
            $overCurrentShutdownCmd = 0;        
          } elsif ($localCmdVal eq "restart") {
            $overCurrentShutdown = "restart";        
            $overCurrentShutdownCmd = 1;          
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose off restart.";
          }
        } elsif ($localCmd eq "overCurrentShutdownReset"){
          if ($localCmdVal eq "not_active") {
            $overCurrentShutdownReset = "not_active";        
            $overCurrentShutdownResetCmd = 0;        
          } elsif ($localCmdVal eq "trigger") {
            $overCurrentShutdownReset = "trigger";        
            $overCurrentShutdownResetCmd = 1;          
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose not_active trigger.";
          }
        } elsif ($localCmd eq "rampTime1"){
          if ($localCmdVal >= 0 || $localCmdVal <= 7.5) {
            $rampTime1 = $localCmdVal;        
            $rampTime1Cmd = $localCmdVal * 2;          
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose 0, 0.5, ..., 7, 7.5";
          }
        } elsif ($localCmd eq "rampTime2"){
          if ($localCmdVal >= 0 || $localCmdVal <= 7.5) {
            $rampTime2 = $localCmdVal;        
            $rampTime2Cmd = $localCmdVal * 2;          
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose 0, 0.5, ..., 7, 7.5";
          }
        } elsif ($localCmd eq "rampTime3"){
          if ($localCmdVal >= 0 || $localCmdVal <= 7.5) {
            $rampTime3 = $localCmdVal;        
            $rampTime3Cmd = $localCmdVal * 2;          
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose 0, 0.5, ..., 7, 7.5";
          }
        } elsif ($localCmd eq "teachInDev"){
          if ($localCmdVal eq "disabled") {
            $teachInDev = "disabled";        
            $teachInDevCmd = 0;        
          } elsif ($localCmdVal eq "enabled") {
            $teachInDev = "enabled";        
            $teachInDevCmd = 1;          
          } else {
            return "Usage: $cmd $localCmd <value> wrong, choose disabled enabled.";
          }
        } else {
          return "Usage: $cmd <localCmd> wrong, choose defaultState|localControl|" .
          "overCurrentShutdown|overCurrentShutdownReset|rampTime1|rampTime2|rampTime3|teachInDev.";
        }
        readingsSingleUpdate($hash, "dayNight", $dayNight, 1);
        readingsSingleUpdate($hash, "defaultState", $defaultState, 1);
        readingsSingleUpdate($hash, "localControl", $localControl, 1);
        readingsSingleUpdate($hash, "overCurrentShutdown", $overCurrentShutdown, 1);
        readingsSingleUpdate($hash, "overCurrentShutdownReset", $overCurrentShutdownReset, 1);
        readingsSingleUpdate($hash, "rampTime1", $rampTime1, 1);
        readingsSingleUpdate($hash, "rampTime2", $rampTime2, 1);
        readingsSingleUpdate($hash, "rampTime3", $rampTime3, 1);
        readingsSingleUpdate($hash, "teachInDev", $teachInDev, 1);  
        $data = sprintf "%02X%02X%02X%02X", $teachInDevCmd << 7 | $cmdID,
                  $overCurrentShutdownCmd << 7 | $overCurrentShutdownResetCmd << 6 | $localControlCmd << 5 | $channel,
                  int($rampTime2Cmd) << 4 | int($rampTime3Cmd),
                  $dayNightCmd << 7 | $defaultStateCmd << 4 | int($rampTime1Cmd);
        
      } elsif ($cmd eq "measurement") {
        shift(@a);
        $updateState = 0;
        $cmdID = 5;
        # same configuration for all channels  
        $channel = 30;
        my $measurementMode = ReadingsVal($name, "measurementMode", "energy");
        my $measurementModeCmd = ($measurementMode eq "power")? 0:1;
        my $measurementReport = ReadingsVal($name, "measurementReport", "query");
        my $measurementReportCmd = ($measurementReport eq "auto")? 0:1;
        my $measurementReset = "not_active";
        my $measurementResetCmd = 0;
        my $measurementDelta = int(ReadingsVal($name, "measurementDelta", 0));
        if ($measurementDelta <= 0) {
           $measurementDelta = 0;
        } elsif ($measurementDelta >= 4095) {
           $measurementDelta = 4095;        
        }        
        my $unit = ReadingsVal($name, "measurementUnit", "Ws");
        my $unitCmd;
        if ($unit eq "Ws") {
          $unitCmd = 0;
        } elsif ($unit eq "Wh") {
          $unitCmd = 1;
        } elsif ($unit eq "KWh") {
          $unitCmd = 2;
        } elsif ($unit eq "W") {
          $unitCmd = 3;
        } elsif ($unit eq "KW") {
          $unitCmd = 4;
        } else {
          $unitCmd = 0;
        }        
        my $responseTimeMax = ReadingsVal($name, "responseTimeMax", 10);
        my $responseTimeMaxCmd = $responseTimeMax / 10;
        if ($responseTimeMaxCmd <= 0) {
           $responseTimeMaxCmd = 0;
        } elsif ($responseTimeMaxCmd >= 255) {
           $responseTimeMaxCmd = 255;
        }        
        my $responseTimeMin = ReadingsVal($name, "responseTimeMin", 0);
        if ($responseTimeMin <= 0) {
           $responseTimeMin = 0;
        } elsif ($responseTimeMin >= 255) {
           $responseTimeMin = 255;
        }        
        my $measurementCmd = shift(@a);
        my $measurementCmdVal = shift(@a);
        if (!defined $measurementCmdVal) {
          return "Usage: $cmd $measurementCmd <value> needed.";
        }
        if (!defined $measurementCmd) {
          return "Usage: $cmd <measurementCmd> wrong, choose mode|report|" .
                 "reset|delta|unit|responseTimeMax|responseTimeMin.";
        } elsif ($measurementCmd eq "mode") {
          if ($measurementCmdVal eq "energy") {
            $measurementMode = "energy";        
            $measurementModeCmd = 0;        
          } elsif ($measurementCmdVal eq "power") {
            $measurementMode = "power";        
            $measurementModeCmd = 1;          
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose energy power.";
          }
        } elsif ($measurementCmd eq "report"){
          if ($measurementCmdVal eq "query") {
            $measurementReport = "query";        
            $measurementReportCmd = 0;        
          } elsif ($measurementCmdVal eq "auto") {
            $measurementReport = "auto";        
            $measurementReportCmd = 1;          
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose query auto.";
          }
        } elsif ($measurementCmd eq "reset"){
          if ($measurementCmdVal eq "not_active") {
            $measurementReset = "not_active";        
            $measurementResetCmd = 0;        
          } elsif ($measurementCmdVal eq "trigger") {
            $measurementReset = "trigger";        
            $measurementResetCmd = 1;          
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose not_active trigger.";
          }
        } elsif ($measurementCmd eq "unit"){
          if ($measurementCmdVal eq "Ws") {
            $unit = "Ws";        
            $unitCmd = 0;        
          } elsif ($measurementCmdVal eq "Wh") {
            $unit = "Wh";        
            $unitCmd = 1;          
          } elsif ($measurementCmdVal eq "KWh") {
            $unit = "KWh";        
            $unitCmd = 2;          
          } elsif ($measurementCmdVal eq "W") {
            $unit = "W";        
            $unitCmd = 3;          
          } elsif ($measurementCmdVal eq "KW") {
            $unit = "KW";        
            $unitCmd = 4;          
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose Ws Wh KWh W KW.";
          }
        } elsif ($measurementCmd eq "delta"){
          if ($measurementCmdVal >= 0 || $measurementCmdVal <= 4095) {
            $measurementDelta = int($measurementCmdVal);        
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose 0 ... 4095";
          }
        } elsif ($measurementCmd eq "responseTimeMax"){
          if ($measurementCmdVal >= 10 || $measurementCmdVal <= 2550) {
            $responseTimeMax = int($measurementCmdVal);        
            $responseTimeMaxCmd = int($measurementCmdVal) / 10;          
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose 10 ... 2550";
          }
        } elsif ($measurementCmd eq "responseTimeMin"){
          if ($measurementCmdVal >= 0 || $measurementCmdVal <= 255) {
            $responseTimeMin = int($measurementCmdVal);        
          } else {
            return "Usage: $cmd $measurementCmd <value> wrong, choose 0 ... 255";
          }
        } else {
          return "Usage: $cmd <measurementCmd> wrong, choose mode|report|" .
          "reset|delta|unit|responseTimeMax|responseTimeMin.";
        }
        readingsSingleUpdate($hash, "measurementMode", $measurementMode, 1);
        readingsSingleUpdate($hash, "measurementReport", $measurementReport, 1);
        readingsSingleUpdate($hash, "measurementReset", $measurementReset, 1);
        readingsSingleUpdate($hash, "measurementDelta", $measurementDelta, 1);
        readingsSingleUpdate($hash, "measurementUnit", $unit, 1);
        readingsSingleUpdate($hash, "responseTimeMax", $responseTimeMax, 1);
        readingsSingleUpdate($hash, "responseTimeMin", $responseTimeMin, 1);
        $data = sprintf "%02X%02X%02X%02X%02X%02X", $cmdID,
                  $measurementReportCmd << 7 | $measurementResetCmd << 6 | $measurementModeCmd << 5 | $channel,
                  ($measurementDelta | 0x0F) << 4 | $unitCmd, ($measurementDelta | 0xFF00) >> 8,
                  $responseTimeMax, $responseTimeMin;
      } else {
        $cmdList .= "dim:slider,0,1,100 on off local measurement";
        return SetExtensions ($hash, $cmdList, $name, @a);
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "blindsCtrl.00") {
      # Blinds Control for Position and Angle
      # (D2-05-00)
      $rorg = "D2";      
      $updateState = 0;
      my $cmdID;
      my $channel = 0;
      my $position = 127;
      my $angle = 127;
      my $repo = AttrVal($name, "reposition", "directly");
      if ($repo eq "directly") {
        $repo = 0;
      } elsif ($repo eq "opens") {
        $repo = 1;
      } elsif ($repo eq "closes") {
        $repo = 2;
      } else {
        $repo = 0;
      }        
      my $lock = 0;
      
      if ($cmd eq "position") {
        $cmdID = 1;
        shift(@a);
        if (ReadingsVal($name, "block", "unlock") ne "unlock") {
          return "Attention: Device locked";
        }
        if (defined $a[0]) {
          # position value
          if (($a[0] =~ m/^\d+$/) && ($a[0] >= 0) && ($a[0] <= 100)) {
            $position = shift(@a);
            if (defined $a[0]) {
            # angle value
              if (($a[0] =~ m/^\d+$/) && ($a[0] >= 0) && ($a[0] <= 100)) {
                $angle = shift(@a);
                if (defined $a[0]) {
                  # reposition value
                  $repo = shift(@a);
                  if ($repo eq "directly") {
                    $repo = 0;
                  } elsif ($repo eq "opens") {
                    $repo = 1;
                  } elsif ($repo eq "closes") {
                    $repo = 2;
                  } else {
                    return "Usage: $position $angle $repo argument unknown, choose one of directly opens closes";
                  }
                }
                readingsSingleUpdate($hash, "anglePos", $angle, 1);
              } else {
                return "Usage: $position $a[0] is not numeric or out of range";
              }
            }
            readingsSingleUpdate($hash, "position", $position, 1);
            readingsSingleUpdate($hash, "endPosition", "not_reached", 1);
            readingsSingleUpdate($hash, "state", "in_motion", 1);
          } else {
            return "Usage: $a[0] is not numeric or out of range";
          }
        } else {
          return "Usage: set <name> position <position> [<angle> [<repo>]]";
        }       
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } elsif ($cmd eq "angle") {
        $cmdID = 1;
        shift(@a);
        if (ReadingsVal($name, "block", "unlock") ne "unlock") {
          return "Attention: Device locked";
        }
        if (defined $a[0]) {
          if (($a[0] =~ m/^\d+$/) && ($a[0] >= 0) && ($a[0] <= 100)) {
            $angle = shift(@a);
            readingsSingleUpdate($hash, "anglePos", $angle, 1);
            readingsSingleUpdate($hash, "state", "in_motion", 1);
          } else {
            return "Usage: $a[0] is not numeric or out of range";
          }
        } else {
          return "Usage: set <name> angle <angle>";
        }
        $repo = 0;
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;
      
      } elsif ($cmd eq "stop") {
        $cmdID = 2;
        shift(@a);
        readingsSingleUpdate($hash, "state", "stoped", 1);
        $data = sprintf "%02X", $channel << 4 | $cmdID;

      } elsif ($cmd eq "opens") {
        $cmdID = 1;
        shift(@a);
        if (ReadingsVal($name, "block", "unlock") ne "unlock") {
          return "Attention: Device locked";
        }
        $position = 0;
        $repo = 0;
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } elsif ($cmd eq "closes") {
        $cmdID = 1;
        shift(@a);
        if (ReadingsVal($name, "block", "unlock") ne "unlock") {
          return "Attention: Device locked";
        }
        $position = 100;
        $repo = 0;
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } elsif ($cmd eq "unlock") {
        $cmdID = 1;
        shift(@a);
        $repo = 0;
        $lock = 7;
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } elsif ($cmd eq "lock") {
        $cmdID = 1;
        shift(@a);
        $repo = 0;
        $lock = 1;
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } elsif ($cmd eq "alarm") {
        $cmdID = 1;
        shift(@a);
        $repo = 0;
        $lock = 2;
        $data = sprintf "%02X%02X%02X%02X", $position, $angle, $repo << 4 | $lock, $channel << 4 | $cmdID;

      } else {
        $cmdList .= "position:slider,0,1,100 angle:slider,0,1,100 stop:noArg opens:noArg closes:noArg lock:noArg unlock:noArg alarm:noArg";
        return "Unknown argument $cmd, choose one of $cmdList";      
      }    
      Log3 $name, 3, "EnOcean set $name $cmd";
 
    } elsif ($st eq "roomCtrlPanel.00") {
      # Room Control Panel
      # (D2-10-00 - D2-10-02)
      $rorg = "D2";
      $updateState = 2;
      if ($cmd eq "desired-temp"|| $cmd eq "setpointTemp") {
        if (defined $a[1]) {
          if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 40)) {
            $a[1] = sprintf "%0.1f", $a[1];
            readingsSingleUpdate($hash, "setpointTemp", $a[1], 1);
            readingsSingleUpdate($hash, "setpointTempSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name setpointTemp $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
         } else {
           return "Usage: $a[1] is not numeric or out of range";
         }
        }          
        
      } elsif ($cmd eq "economyTemp" || $cmd eq "preComfortTemp" || $cmd eq "buildingProtectionTemp" || $cmd eq "comfortTemp") {
        if (defined $a[1]) {
          if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 40)) {
            Log3 $name, 3, "EnOcean set $name $cmd $a[1]";
            $cmd =~ s/(\b)([a-z])/$1\u$2/g;
            $a[1] = sprintf "%0.1f", $a[1];
            readingsSingleUpdate($hash, "setpoint" . $cmd, $a[1], 1);
            readingsSingleUpdate($hash, "setpoint" . $cmd . "Set", $a[1], 0);
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 8, 0);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        }          
        
      } elsif ($cmd eq "fanSpeed") {
        if (defined $a[1]) {
          if ($a[1] >= 0 && $a[1] <= 100) {
            readingsSingleUpdate($hash, "fanSpeed", $a[1], 1);
            readingsSingleUpdate($hash, "fanSpeedSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name fanSpeed $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
          } else {
            return "Usage: $a[1] is wrong.";
          }
        }
        
      } elsif ($cmd eq "fanSpeedMode") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^(central|local)$/) {
            readingsSingleUpdate($hash, "fanSpeedMode", $a[1], 1);
            readingsSingleUpdate($hash, "fanSpeedModeSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name fanSpeedMode $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        }          
        
      } elsif ($cmd eq "cooling") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^(on|off|auto|no_change)$/) {
            readingsSingleUpdate($hash, "cooling", $a[1], 1);
            readingsSingleUpdate($hash, "coolingSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name cooling $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        }          
        
      } elsif ($cmd eq "heating") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^(on|off|auto|no_change)$/) {
            readingsSingleUpdate($hash, "heating", $a[1], 1);
            readingsSingleUpdate($hash, "heatingSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name heating $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        }          
        
      } elsif ($cmd eq "roomCtrlMode") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^(comfort|preComfort|economy|buildingProtection)$/) {
            readingsSingleUpdate($hash, "roomCtrlMode", $a[1], 1);
            readingsSingleUpdate($hash, "roomCtrlModeSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name roomCtrlMode $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        }          
        
      } elsif ($cmd eq "config") {
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 64, 0);
        Log3 $name, 3, "EnOcean set $name $cmd";
        
      } elsif ($cmd eq "timeProgram") {
        # delete remote and send new time program
        delete $hash->{helper}{4}{telegramWait};
        for (my $messagePartCntr = 1; $messagePartCntr <= 4; $messagePartCntr ++) {
          if (defined AttrVal($name, "timeProgram" . $messagePartCntr, undef)) {
            $hash->{helper}{4}{telegramWait}{$messagePartCntr} = 1;
            Log3 $name, 3, "EnOcean $name EnOcean_Set timeProgram" . $messagePartCntr . " set";
          }
        }
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 528, 0);
        Log3 $name, 3, "EnOcean set $name $cmd";
        
      } elsif ($cmd eq "deleteTimeProgram") {
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 512, 0);
        Log3 $name, 3, "EnOcean set $name $cmd";

      } elsif ($cmd eq "time") {
        readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 4, 0);
        Log3 $name, 3, "EnOcean set $name $cmd";

      } elsif ($cmd eq "window") {
        if (defined $a[1]) {
          if ($a[1] =~ m/^closed|open$/) {
            readingsSingleUpdate($hash, "window", $a[1], 1);
            readingsSingleUpdate($hash, "windowSet", $a[1], 0);
            Log3 $name, 3, "EnOcean set $name window $a[1]";
            shift(@a);
            readingsSingleUpdate($hash, "waitingCmds", ReadingsVal($name, "waitingCmds", 0) | 2, 0);
         } else {
            return "Usage: $a[1] is wrong.";
          }
        }          
 
      } elsif ($cmd eq "clearCmds") {
        CommandDeleteReading(undef, "$name waitingCmds");
        Log3 $name, 3, "EnOcean set $name $cmd";

      } else {
        $cmdList .= "cooling:auto,off,on,no_change desired-temp setpointTemp:slider,0,1,40 " . 
                      "comfortTemp deleteTimeProgram:noArg " .
                      "economyTemp preComfortTemp buildingProtectionTemp config:noArg " .
                      "clearCmds:noArg fanSpeed:slider,0,1,100 heating:auto,off,on,no_change " .
                      "fanSpeedMode:central,local time:noArg " . 
                      "roomCtrlMode:comfort,economy,preComfort,buildingProtection timeProgram:noArg window:closed,open";
        return "Unknown argument $cmd, choose one of $cmdList";      
      }

    } elsif ($st eq "fanCtrl.00") {
      # Fan Control
      # (D2-20-00 - D2-20-02)
      $rorg = "D2";
      #$updateState = 0;
      my ($fanSpeed, $humiThreshold, $roomSize, $roomSizeRef, $humidityCtrl, $tempLevel, $opMode) =
         (255, 255, 15, 3, 3, 3, 15);
      my $messageType = 0;
      my @roomSizeTbl = (25, 50, 75, 100, 125, 150, 175, 200, 225, 250, 275, 300, 325, 350);      
      if ($cmd eq "fanSpeed") {
        $updateState = 0;
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
            $fanSpeed = $a[1];
            readingsSingleUpdate($hash, "fanSpeed", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name fanSpeed $a[1]";
            shift(@a);
          } elsif ($a[1] eq "auto") {
            $fanSpeed = 253;
            readingsSingleUpdate($hash, "fanSpeed", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name fanSpeed $a[1]";          
            shift(@a);
          } elsif ($a[1] eq "default") {
            $fanSpeed = 254;
            readingsSingleUpdate($hash, "fanSpeed", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name fanSpeed $a[1]";          
            shift(@a);
          } else {
            return "Usage: $a[1] is wrong.";
          }
        } else {
          return "Usage: set <name> fanspeed 0...100|auto|default";
        }
        shift(@a);
      
      } elsif ($cmd eq "on") {
        $opMode = 1;
        Log3 $name, 3, "EnOcean set $name $a[0]";          
      
      } elsif ($cmd eq "off") {
        $opMode = 0;
        Log3 $name, 3, "EnOcean set $name $a[0]";          
      
      } elsif ($cmd eq "desired-temp" || $cmd eq "setpointTemp") {
        $updateState = 0;
        my $temperatureRefDev = AttrVal($name, "temperatureRefDev", undef);
        return "Attention: attr $name temperatureRefDev <refDev> must be defined" if (!defined $temperatureRefDev);
        my $temperature = ReadingsVal($temperatureRefDev, "temperature", 20); 
        my $setpointTemp = ReadingsVal($name, "setpointTemp", 20);
        my $switchHysteresis = AttrVal($name, "switchHysteresis", 1);        
        if (defined $a[1] && $a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 40) {
          $setpointTemp = $a[1];
          shift(@a);
        }
        if ($setpointTemp > $temperature + $switchHysteresis / 2) {
          $tempLevel = 2;
        } elsif ($setpointTemp < $temperature - $switchHysteresis / 2) {
          $tempLevel = 0;
        } else {
          $tempLevel = 1;
        }
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "setpointTemp", sprintf("%.1f", $setpointTemp));
        readingsBulkUpdate($hash, "temperature", sprintf("%.1f", $temperature));
        readingsEndUpdate($hash, 1);
        Log3 $name, 3, "EnOcean set $name $cmd $setpointTemp";          
        shift(@a);
      
      } elsif ($cmd eq "humidityThreshold") {
        $updateState = 0;
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
            $humidityCtrl = 1;
            $humiThreshold = $a[1];
            readingsSingleUpdate($hash, "humidityThreshold", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name humidityThreshold $a[1]";
            shift(@a);
          } elsif ($a[1] eq "auto") {
            $humidityCtrl = 1;
            $humiThreshold = 253;
            readingsSingleUpdate($hash, "humidityThreshold", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name humidityThreshold $a[1]";          
            shift(@a);
          } elsif ($a[1] eq "default") {
            $humidityCtrl = 2;
            $humiThreshold = 254;
            readingsSingleUpdate($hash, "humidityThreshold", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name humidityThreshold $a[1]";          
            shift(@a);
          } elsif ($a[1] eq "disabled") {
            $humidityCtrl = 0;          
            $humiThreshold = 255;
            readingsSingleUpdate($hash, "humidityThreshold", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name humidityThreshold $a[1]";          
            shift(@a);
          } else {
            return "Usage: $a[1] is wrong.";
          }
        } else {
          return "Usage: set <name> humidityThreshold 0...100|auto|default|disabled";
        }      
        shift(@a);

      } elsif ($cmd eq "roomSize") {
        $updateState = 0;
        if (defined $a[1]) {
          if ($a[1] =~ m/^\d+$/) {
            readingsSingleUpdate($hash, "roomSize", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name roomSize $a[1]";
            $roomSize = 14;
            for (my $i = 0; $i < @roomSizeTbl; $i++) {
              if ($a[1] <= $roomSizeTbl[$i]) {
                $roomSize = $i;
                last;
              }
            }
            $roomSizeRef = 0;
            shift(@a);
          } elsif ($a[1] eq "not_used") {
            $roomSizeRef = 1;
            $roomSize = 15;
            readingsSingleUpdate($hash, "roomSize", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name roomSize $a[1]";          
            shift(@a);
          } elsif ($a[1] eq "default") {
            $roomSizeRef = 2;
            $roomSize = 15;
            readingsSingleUpdate($hash, "roomSize", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name roomSize $a[1]";          
            shift(@a);
          } elsif ($a[1] eq "max") {
            $roomSizeRef = 0;
            $roomSize = 14;
            readingsSingleUpdate($hash, "roomSize", $a[1], 1);
            Log3 $name, 3, "EnOcean set $name roomSize $a[1]";          
            shift(@a);
          } else {
            return "Usage: $a[1] is wrong.";
          }
        } else {
          return "Usage: set <name> roomSize 0...350|max|not_used|default";
        }      
        shift(@a);
    
      } else {
        $cmdList .= "off:noArg on:noArg desired-temp fanSpeed setpointTemp:slider,0,1,40 " . 
                      "humidityThreshold roomSize";
        return "Unknown argument $cmd, choose one of $cmdList";      
      }
      $data = sprintf "%02X%02X%02X%02X", ($opMode << 4) | ($tempLevel << 1),
                                          ($humidityCtrl << 6) | ($roomSizeRef << 4) | $roomSize,
                                          $humiThreshold, $fanSpeed;

    } elsif ($st eq "valveCtrl.00") {
      # Valve Control
      # (D2-A0-01)
      if (AttrVal($name, "devMode", "master") eq "slave") {
        # devNode slave
        if ($cmd eq "closed") {
          $rorg = "D2";
          $data = "01"
        } elsif ($cmd eq "open") {
          $rorg = "D2";
          $data = "02"
        } elsif ($cmd eq "teachIn") {
          ($err, $rorg, $data) = EnOcean_sndUTE(undef, $hash, "biDir",
                                                AttrVal($name, "uteResponseRequest", "yes"), "in", 0, "D2-A0-01");
        } elsif ($cmd eq "teachOut") {
          ($err, $rorg, $data) = EnOcean_sndUTE(undef, $hash, "biDir",
                                                AttrVal($name, "uteResponseRequest", "yes"), "out", 0, "D2-A0-01");
        } else {
          return "Unknown argument $cmd, choose one of " . $cmdList . "open:noArg closed:noArg teachIn:noArg teachOut:noArg";
        }
      } else {
      # devMode master
        if ($cmd eq "closes") {
          $rorg = "D2";
          $data = "01"
        } elsif ($cmd eq "opens") {
          $rorg = "D2";
          $data = "02"
        } else {
          return "Unknown argument $cmd, choose one of " . $cmdList . "opens:noArg closes:noArg";
        }
      }
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "contact") {
      # 1BS Telegram
      # Single Input Contact (EEP D5-00-01)
      $rorg = "D5";
      my $setCmd;
      if ($cmd eq "teach") {
        $setCmd = 0;
        $updateState = 1;
      } elsif ($cmd eq "closed") {
        $setCmd = 9;
      } elsif ($cmd eq "open") {
        $setCmd = 8;
      } else {
        return "Unknown argument $cmd, choose one of " . $cmdList . "open:noArg closed:noArg teach:noArg";
      }
      $data = sprintf "%02X", $setCmd;
      Log3 $name, 3, "EnOcean set $name $cmd";

    } elsif ($st eq "raw") {
      # sent raw data
      if ($cmd eq "4BS"){
        # 4BS Telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{8}$/) {
          $data = uc($a[1]);
          $rorg = "A5";
        } else {
          return "Wrong parameter, choose 4BS <data 4 Byte hex> [status 1 Byte hex]";
        }
      } elsif ($cmd eq "1BS") {
        # 1BS Telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2}$/) {
          $data = uc($a[1]);
          $rorg = "D5";
        } else {
          return "Wrong parameter, choose 1BS <data 1 Byte hex> [status 1 Byte hex]";
        }
      } elsif ($cmd eq "RPS") {
        # RPS Telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2}$/) {
          $data = uc($a[1]);
          $rorg = "F6";
        } else {
          return "Wrong parameter, choose RPS <data 1 Byte hex> [status 1 Byte hex]";
        }
      } elsif ($cmd eq "MSC") {
        # MSC Telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,28}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "D1";
        } else {
          return "Wrong parameter, choose MSC <data 1 ... 14 Byte hex> [status 1 Byte hex]";
        }
      } elsif ($cmd eq "UTE") {
        # UTE Telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{14}$/) {
          $data = uc($a[1]);
          $rorg = "D4";
        } else {
          return "Wrong parameter, choose UTE <data 7 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "VLD") {
        # VLD Telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,28}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "D2";
        } else {
          return "Wrong parameter, choose VLD <data 1 ... 14 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "GPTI") {
        # GP teach-in request telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,1024}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "B0";
        } else {
          return "Wrong parameter, choose GP <data 1 ... 512 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "GPTR") {
        # GP teach-in response telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,1024}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "B1";
        } else {
          return "Wrong parameter, choose GP <data 1 ... 512 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "GPCD") {
        # GP complete date telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,1024}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "B2";
        } else {
          return "Wrong parameter, choose GP <data 1 ... 512 Byte hex> [status 1 Byte hex]";
        }

      } elsif ($cmd eq "GPSD") {
        # GP selective data telegram
        if ($a[1] && $a[1] =~ m/^[\dA-Fa-f]{2,1024}$/ && !(length($a[1]) % 2)) {
          $data = uc($a[1]);
          $rorg = "B3";
        } else {
          return "Wrong parameter, choose GP <data 1 ... 512 Byte hex> [status 1 Byte hex]";
        }

      } else {
        return "Unknown argument $cmd, choose one of 1BS 4BS GPCD GPSD GPTI GPTR MSC RPS UTE VLD";
      }
      if ($a[2]) {
        if ($a[2] !~ m/^[\dA-Fa-f]{2}$/) {
          return "Wrong status parameter, choose $cmd $a[1] [status 1 Byte hex]";
        }
       $status = uc($a[2]);
       splice(@a,2,1);
      }
      $updateState = 0;
      readingsSingleUpdate($hash, "RORG", $cmd, 1);
      readingsSingleUpdate($hash, "dataSent", $data, 1);
      readingsSingleUpdate($hash, "statusSent", $status, 1);
      Log3 $name, 3, "EnOcean set $name $cmd $data $status";
      shift(@a);

    } else {
      # subtype does not support set commands
      $updateState = -1;
      if (AttrVal($name, "remoteManagement", "off") eq "on") {
        return "Unknown argument $cmd, choose one of $cmdList";
      } else {
        return;
      }      
    }

    # set reading state if confirmation telegram is not expected
    if($updateState == 1 && $updateStateAttr =~ m/^default|yes$/) {
      readingsSingleUpdate($hash, "state", $cmd, 1);
    } elsif ($updateState == 0 && $updateStateAttr eq "yes") {
      readingsSingleUpdate($hash, "state", $cmd, 1);
    } else {
      readingsSingleUpdate($hash, ".info", "await_confirm", 0);
    }

    # send commands
    if($updateState != 2) {
      EnOcean_SndCDM(undef, $hash, $packetType, $rorg, $data, $subDef, $status, $destinationID);
      EnOcean_observeInit(1, $hash, @cmdObserve);      
      if ($switchMode eq "pushbutton" && $cmd1 ne "released") {
        my @timerCmd = ($name, "released");
	my %par = (hash => $hash, timerCmd => \@timerCmd);
	InternalTimer(gettimeofday() + 0.1, "EnOcean_TimerSet", \%par, 0);                
      }
    }
  }
  
  return undef;
}

# parse and display the incoming telegrams
sub EnOcean_Parse($$)
{
  my ($iohash, $msg) = @_;
  my $IODev = $iohash->{NAME};
  my ($hash, $name, $rorgname);
  my ($err, $response);
  Log3 $IODev, 4, "EnOcean received via $IODev: $msg";
  my @msg = split(":", $msg);
  my ($rorg, $data, $id, $status, $odata, $subDef, $destinationID, $fnNumber, $manufID, $RSSI, $delay, $subTelNum);
  my $packetType = hex($msg[1]);
  
  if ($packetType == 1) {
    # packet type RADIO
    (undef, undef, $rorg, $data, $id, $status, $odata) = @msg;
    $hash = $modules{EnOcean}{defptr}{$id};
    $odata =~ m/^(..)(........)(..)(..)$/;
    ($subTelNum, $destinationID, $RSSI) = (hex($1), $2, hex($3));
    $rorgname = $EnO_rorgname{$rorg};
    if (!$rorgname) {
      Log3 undef, 2, "EnOcean RORG $rorg received from $id unknown.";
      return "";
    }
    if($hash) {
      $name = $hash->{NAME};
      #if ($IODev ne $hash->{IODev}{NAME}) {
        # transceiver wrong
      #  Log3 $name, 4, "EnOcean $name locked telegram via $IODev PacketType: $packetType RORG: $rorg DATA: $data SenderID: $id STATUS: $status";
      #  return "";
      #}
      Log3 $name, 5, "EnOcean $name received PacketType: $packetType RORG: $rorg DATA: $data SenderID: $id STATUS: $status";
      $manufID = uc(AttrVal($name, "manufID", ""));
      $subDef = uc(AttrVal($name, "subDef", $hash->{DEF}));
    } else {
      # SenderID unknown, created new device
      Log3 undef, 5, "EnOcean received PacketType: $packetType RORG: $rorg DATA: $data SenderID: $id STATUS: $status";
      my $learningMode = AttrVal($iohash->{NAME}, "learningMode", "demand");
      if ($learningMode eq "demand" && $iohash->{Teach}) {
        Log3 undef, 1, "EnOcean Unknown device with SenderID $id and RORG $rorg, please define it.";
        return "UNDEFINED EnO_${rorgname}_$id EnOcean $id $msg";
      } elsif ($learningMode eq "nearfield" && $iohash->{Teach} && $RSSI <= 60) {
        Log3 undef, 1, "EnOcean Unknown device with SenderID $id and RORG $rorg, please define it.";
        return "UNDEFINED EnO_${rorgname}_$id EnOcean $id $msg";
      } elsif ($learningMode eq "always") {    
        if ($rorgname eq "UTE") {
          if ($iohash->{Teach}) {
            Log3 undef, 1, "EnOcean Unknown device with SenderID $id and RORG $rorg, please define it.";
            return "UNDEFINED EnO_${rorgname}_$id EnOcean $id $msg";
          } else {
            Log3 undef, 1, "EnOcean Unknown device with SenderID $id and RORG $rorg, activate learning mode.";
            return "";
          }
        } else {
          Log3 undef, 1, "EnOcean Unknown device with SenderID $id and RORG $rorg, please define it.";
          return "UNDEFINED EnO_${rorgname}_$id EnOcean $id $msg";
        }    
      } else {
        Log3 undef, 4, "EnOcean Unknown device with SenderID $id and RORG $rorg, activate learning mode.";
        return "";
      }

    }

  } elsif ($packetType == 7) {
    # packet type REMOTE_MAN_COMMAND
    #EnOcean:PacketType:RORG:MessageData:SourceID:DestinationID:FunctionNumber:ManufacturerID:RSSI:Delay  
    (undef, undef, $rorg, $data, $id, $destinationID, $fnNumber, $manufID, $RSSI, $delay) = @msg;
    $hash = $modules{EnOcean}{defptr}{$id};
    $rorgname = $EnO_rorgname{$rorg};
    if($hash) {
      $name = $hash->{NAME};
      #if ($IODev ne $hash->{IODev}{NAME}) {
       # transceiver wrong
      #  Log3 $name, 4, "EnOcean $name locked telegram via $IODev PacketType: $packetType RORG: $rorg DATA: $data SenderID: $id STATUS: $status";
      #  return "";
      #}
      $subDef = uc(AttrVal($name, "subDef", $hash->{DEF}));
      Log3 $name, 2, "EnOcean $name received PacketType: $packetType RORG: $rorg DATA: $data SenderID: $id
                      DestinationID $destinationID Function Number: $fnNumber ManufacturerID: $manufID";
    } else {
      Log3 undef, 2, "EnOcean received PacketType: $packetType RORG: $rorg DATA: $data SenderID: $id
                      DestinationID $destinationID Function Number: $fnNumber ManufacturerID: $manufID";      
      return "";
    }
    $fnNumber = hex($fnNumber);
    $RSSI = hex($RSSI);
    $delay = hex($delay);  
  }

  my $eep = AttrVal($name, "eep", undef);
  my $teach = $defs{$name}{IODev}{Teach};
  my ($deleteDevice, $oldDevice);

  if (AttrVal($name, "secLevel", "off") =~ m/^encapsulation|encryption$/ &&
      AttrVal($name, "secMode", "") =~ m/^rcv|biDir$/) {
    if ($rorg eq "30" || $rorg eq "31") {
      Log3 $name, 5, "EnOcean $name secure data RORG: $rorg DATA: $data ID: $id STATUS: $status";    
      ($err, $rorg, $data) = EnOcean_sec_convertToNonsecure($hash, $rorg, $data);   
      if (defined $err) {
        Log3 $name, 2, "EnOcean $name security ERROR: $err"; 
        return "";
      }
    }
    if ($rorg eq "32") {
      if (defined $eep) {
        # reconstruct RORG
        $rorg = substr($eep, 0, 2);
        Log3 $name, 5, "EnOcean $name decrypted data RORG: 32 >> $rorg DATA: $data ID: $id STATUS: $status";
      } else {
        # UTE telegram expected
        if (length($data) == 14) {
          $rorg = "D4";
        } else {
          Log3 $name, 2, "EnOcean $name security teach-in failed, UTE message is missing"; 
          return "";          
        }
      }
    } elsif ($rorg eq "35") {
      # pass second teach-in telegram

    } else {
      Log3 $name, 2, "EnOcean $name unsecure telegram locked"; 
      return "";    
    }
  }

  if ($rorg eq "A6") {
    # addressing destination telegram (ADT)
    # reconstruct RORG, DATA
    $data =~ m/^(..)(.*)(........)$/;
    ($rorg, $data) = ($1, $2);
    $rorgname = $EnO_rorgname{$rorg};
    if (!$rorgname) {
      Log3 undef, 1, "EnOcean RORG $rorg received from $id unknown.";
      return "";
    }
    if ($destinationID ne $3) {
      Log3 $name, 1, "EnOcean $name ADT DestinationID wrong.";
      return "";
    }
    Log3 $name, 1, "EnOcean $name ADT decapsulation RORG: $rorg DATA: $data DestinationID: $3";
  }

  if ($rorg eq "40") {
    # chained data message (CDM)
    $data =~ m/^(..)(.*)$/;
    # SEQ evaluation?
    my ($seq, $idx) = (hex($1) & 0xC0, hex($1) & 0x3F);
    $data = $2;
    if ($idx == 0) {
      # first message part
      delete $hash->{helper}{cdm};
      $data =~ m/^(....)(..)(.*)$/;
      $hash->{helper}{cdm}{len} = hex($1);
      $hash->{helper}{cdm}{rorg} = $2;
      $hash->{helper}{cdm}{data}{$idx} = $3;
      $hash->{helper}{cdm}{lenCounter} = length($3) / 2;
      my %functionHash = (hash => $hash, function => "cdm");
      RemoveInternalTimer(\%functionHash);
      InternalTimer(gettimeofday() + 0.75, "EnOcean_cdmClear", \%functionHash, 0);
      Log3 $name, 3, "EnOcean $name CDM timer started";
    } else {
      $hash->{helper}{cdm}{data}{$idx} = $data;
      $hash->{helper}{cdm}{lenCounter} += length($data) / 2;
    }
    if ($hash->{helper}{cdm}{lenCounter} >= $hash->{helper}{cdm}{len}) {
      # data message complete
      # reconstruct RORG, DATA
      my ($idx, $dataPart, @data);
      while (($idx, $dataPart) = each(%{$hash->{helper}{cdm}{data}})) {
        $data[$idx] = $hash->{helper}{cdm}{data}{$idx};
      }
      $data = join('', @data);
      $rorg = $hash->{helper}{cdm}{rorg};
      delete $hash->{helper}{cdm};
      my %functionHash = (hash => $hash, function => "cdm");
      RemoveInternalTimer(\%functionHash);
      Log3 $name, 3, "EnOcean $name CDM concatenated";
    } else {
      # wait for next data message part
      return $name;
    }
  }

  # extract data bytes $db[x] ... $db[0]
  my @db;
  my $dbCntr = 0;
  for (my $strCntr = length($data) / 2 - 1; $strCntr >= 0; $strCntr --) {
    $db[$dbCntr] = hex substr($data, $strCntr * 2, 2);
    $dbCntr ++;
  }  

  my @event;
  my $model = AttrVal($name, "model", "");
  my $st = AttrVal($name, "subType", "");
  my $subtypeReading = AttrVal($name, "subTypeReading", undef);
  $st = $subtypeReading if (defined $subtypeReading);

  if ($rorg eq "F6") {
    # RPS Telegram (PTM200)
    # Rocker Switch (EEP F6-02-01 ... F6-03-02)
    # Position Switch, Home and Office Application (EEP F6-04-01)
    # Mechanical Handle (EEP F6-10-00)
    my $event = "state";
    my $nu =  ((hex($status) & 0x10) >> 4);
    # unused flags (AFAIK)
    #push @event, "1:T21:".((hex($status) & 0x20) >> 5);
    #push @event, "1:NU:$nu";

    if ($st eq "FRW") {
      # smoke detector Eltako FRW
      if ($db[0] == 0x30) {
        push @event, "3:battery:low";
      } elsif ($db[0] == 0x10) {
        push @event, "3:alarm:smoke-alarm";
        $msg = "smoke-alarm";
      } elsif ($db[0] == 0) {
        push @event, "3:alarm:off";
        push @event, "3:battery:ok";
        $msg = "off";
      }
      push @event, "3:$event:$msg";

    } elsif ($model eq "FAE14" || $model eq "FHK14" || $model eq "FHK61") {
      # heating/cooling relay FAE14, FHK14, untested
      $event = "controllerMode";
      if ($db[0] == 0x30) {
        # night reduction 2 K
        push @event, "3:energyHoldOff:holdoff";
        $msg = "auto";
      } elsif ($db[0] == 0x10) {
        # off
        push @event, "3:energyHoldOff:normal";
        $msg = "off";
      } elsif ($db[0] == 0x70) {
        # on
        push @event, "3:energyHoldOff:normal";
        $msg = "auto";
      } elsif ($db[0] == 0x50) {
        # night reduction 4 K
        push @event, "3:energyHoldOff:holdoff";
        $msg = "auto";
      }
      push @event, "3:$event:$msg";

    } elsif ($st eq "gateway") {
      # Eltako switching, dimming
      if ($db[0] == 0x70) {
        # on
        $msg = "on";
      } elsif ($db[0] == 0x50) {
        # off
        $msg = "off";
      }
      push @event, "3:$event:$msg";

    } elsif ($st eq "manufProfile" && $manufID eq "00D") {
      # Eltako shutter
      if ($db[0] == 0x70) {
        # open
        push @event, "3:endPosition:open_ack";
        $msg = "open_ack";
      } elsif ($db[0] == 0x50) {
        # closed
        push @event, "3:position:100";
        push @event, "3:anglePos:" . AttrVal($name, "angleMax", 90);
        push @event, "3:endPosition:closed";
        $msg = "closed";
      } elsif ($db[0] == 0) {
        # not reached or not available
        push @event, "3:endPosition:not_reached";
        $msg = "not_reached";
      } elsif ($db[0] == 1) {
        # up
        push @event, "3:endPosition:not_reached";
        $msg = "up";
      } elsif ($db[0] == 2) {
        # down
        push @event, "3:endPosition:not_reached";
        $msg = "down";
      }
      push @event, "3:$event:$msg";

    } elsif ($st eq "switch.7F" && $manufID eq "00D") {
      $msg  = $EnO_ptm200btn[($db[0] & 0xE0) >> 5];
      $msg .= "," . $EnO_ptm200btn[($db[0] & 0x0E) >> 1] if ($db[0] & 1);
      $msg .= " released" if (!($db[0] & 0x10));
      push @event, "3:buttons:" . ($db[0] & 0x10 ? "pressed" : "released");
      if ($msg =~ m/A0/) {push @event, "3:channelA:A0";}
      if ($msg =~ m/AI/) {push @event, "3:channelA:AI";}
      if ($msg =~ m/B0/) {push @event, "3:channelB:B0";}
      if ($msg =~ m/BI/) {push @event, "3:channelB:BI";}
      if ($msg =~ m/C0/) {push @event, "3:channelC:C0";}
      if ($msg =~ m/CI/) {push @event, "3:channelC:CI";}
      if ($msg =~ m/D0/) {push @event, "3:channelD:D0";}
      if ($msg =~ m/DI/) {push @event, "3:channelD:DI";}
      push @event, "3:$event:$msg";

    } else {
      if ($nu) {
        if ($st eq "keycard") {
          # Key Card, not tested
          $msg = "keycard_inserted" if ($db[0] == 112);
        } elsif ($st eq "liquidLeakage") {
          # liquid leakage sensor, not tested
          $msg = "wet" if ($db[0] == 0x11);          
        } else {
          # Theoretically there can be a released event with some of the A0, BI
          # pins set, but with the plastic cover on this wont happen.
          $msg  = $EnO_ptm200btn[($db[0] & 0xE0) >> 5];
          $msg .= "," . $EnO_ptm200btn[($db[0] & 0x0E) >> 1] if ($db[0] & 1);
          $msg .= " released" if (!($db[0] & 0x10));
          push @event, "3:buttons:" . ($db[0] & 0x10 ? "pressed" : "released");
          if ($msg =~ m/A0/) {push @event, "3:channelA:A0";}
          if ($msg =~ m/AI/) {push @event, "3:channelA:AI";}
          if ($msg =~ m/B0/) {push @event, "3:channelB:B0";}
          if ($msg =~ m/BI/) {push @event, "3:channelB:BI";}
          if ($msg =~ m/C0/) {push @event, "3:channelC:C0";}
          if ($msg =~ m/CI/) {push @event, "3:channelC:CI";}
          if ($msg =~ m/D0/) {push @event, "3:channelD:D0";}
          if ($msg =~ m/DI/) {push @event, "3:channelD:DI";}
        }
      } else {
        if ($db[0] & 0xC0) {
          # Only a Mechanical Handle is setting these bits when NU = 0
          $msg = "closed"           if ($db[0] == 0xF0);
          $msg = "open"             if ($db[0] == 0xE0);
          $msg = "tilted"           if ($db[0] == 0xD0);
          $msg = "open_from_tilted" if ($db[0] == 0xC0);
        } elsif ($st eq "keycard") {
          $msg = "keycard_removed";          
        } elsif ($st eq "liquidLeakage") {
          $msg = "dry";          
        } else {
          $msg = (($db[0] & 0x10) ? "pressed" : "released");
          push @event, "3:buttons:" . ($db[0] & 0x10 ? "pressed" : "released");          
        }
      }    
      # released events are disturbing when using a remote, since it overwrites
      # the "real" state immediately. In the case of an Eltako FSB14, FSB61 ...
      # the state should remain released. (by Thomas)
      if ($msg =~ m/released$/ &&
          AttrVal($name, "sensorMode", "switch") ne "pushbutton" &&
          $model ne "FT55" && $model ne "FSB14" &&
          $model ne "FSB61" && $model ne "FSB70" &&
          $model ne "FSM12" && $model ne "FSM61" &&
          $model ne "FTS12") {
        $event = "buttons"; 
        $msg = "released";            
      } else {
        push @event, "3:$event:$msg";
      }
    }

  } elsif ($rorg eq "D5") {
  # 1BS telegram
  # Single Input Contact (EEP D5-00-01)
  # [Eltako FTK, STM-250]
    push @event, "3:state:" . ($db[0] & 1 ? "closed" : "open");
    if (!($db[0] & 8)) {
      $attr{$name}{eep} = "D5-00-01";
      push @event, "3:teach-in:EEP D5-00-01 Manufacturer: no ID";
      Log3 $name, 2, "EnOcean $name teach-in EEP D5-00-01 Manufacturer: no ID";
    }

  } elsif ($rorg eq "A5") {
  # 4BS telegram
    if (($db[0] & 0x08) == 0) {
    # Teach-In telegram
      if ($teach || AttrVal($defs{$name}{IODev}{NAME}, "learningMode", "demand") eq "always") {
      
        if ($db[0] & 0x80) {
          # Teach-In telegram with EEP and Manufacturer ID
          my $fn = sprintf "%02X", ($db[3] >> 2);
          my $tp = sprintf "%02X", ((($db[3] & 3) << 5) | ($db[2] >> 3));
          my $mf = sprintf "%03X", ((($db[2] & 7) << 8) | $db[1]);
          # manufID to account for vendor-specific features
          $attr{$name}{manufID} = $mf;
          $mf = $EnO_manuf{$mf} if($EnO_manuf{$mf});
          my $st = "A5.$fn.$tp";
          $attr{$name}{eep} = "A5-$fn-$tp";
          if($EnO_eepConfig{$st}{attr}) {
            push @event, "3:teach-in:EEP A5-$fn-$tp Manufacturer: $mf";          
            Log3 $name, 2, "EnOcean $name teach-in EEP A5-$fn-$tp Manufacturer: $mf";
            foreach my $attrCntr (keys %{$EnO_eepConfig{$st}{attr}}) {
              if ($attrCntr eq "subDef") {
                if (!defined AttrVal($name, $attrCntr, undef)) {              
                  CommandAttr(undef, "$name $attrCntr " . EnOcean_CheckSenderID($EnO_eepConfig{$st}{attr}{$attrCntr}, $defs{$name}{IODev}{NAME}, "00000000"));
                }
              } else {            
                CommandAttr(undef, "$name $attrCntr $EnO_eepConfig{$st}{attr}{$attrCntr}");
              }
            }
            $st = $EnO_eepConfig{$st}{attr}{subType};
          } else {
            push @event, "3:teach-in:EEP A5-$fn-$tp Manufacturer: $mf not supported";          
            Log3 $name, 2, "EnOcean $name teach-in EEP A5-$fn-$tp Manufacturer: $mf not supported";
            $attr{$name}{subType} = "raw";        
            $st = "raw";        
          }

          if ($teach) {
            # bidirectional 4BS Teach-In 
            if ($st eq "hvac.01" || $st eq "MD15") {
              # EEP A5-20-01
              $attr{$name}{comMode} = "biDir";          
              $attr{$name}{destinationID} = "unicast";
              ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "biDir");
              # teach-in response
              EnOcean_SndRadio(undef, $hash, $packetType, $rorg, "800FFFF0", $subDef, "00", $hash->{DEF});
              EnOcean_hvac_01Cmd($hash, $packetType, 128); # 128 == 20 degree C

            } elsif ($st eq "hvac.02") {

            } elsif ($st eq "hvac.03") {

            } elsif ($st eq "hvac.10") {

            } elsif ($st eq "hvac.11") {

            }

          }
          # store attr subType, manufID ...
          CommandSave(undef, undef);
          # delete standard readings
          CommandDeleteReading(undef, "$name sensor[0-9]");
          CommandDeleteReading(undef, "$name D[0-9]");

        } else {
          push @event, "3:teach-in:No EEP profile identifier and no Manufacturer ID";
          Log3 $name, 2, "EnOcean $name teach-in No EEP profile identifier and no Manufacturer ID";
          $attr{$name}{subType} = "raw";        
          $st = "raw";        
        }
      
      } else {
        Log3 $name, 4, "EnOcean $name teach-in with subType $st locked, set transceiver in teach mode.";
        return ""
      }        

    } elsif ($st eq "hvac.01" || $st eq "MD15") {
      # Battery Powered Actuator (EEP A5-20-01)
      # [Kieback&Peter MD15-FTL-xx]
      push @event, "3:state:$db[3]";
      push @event, "3:currentValue:$db[3]";
      push @event, "3:setpoint:$db[3]";
      push @event, "3:serviceOn:"    . (($db[2] & 0x80) ? "yes" : "no");
      push @event, "3:energyInput:"  . (($db[2] & 0x40) ? "enabled":"disabled");
      push @event, "3:energyStorage:". (($db[2] & 0x20) ? "charged":"empty");
      push @event, "3:battery:"      . (($db[2] & 0x10) ? "ok" : "low");
      push @event, "3:cover:"        . (($db[2] & 0x08) ? "open" : "closed");
      push @event, "3:tempSensor:"   . (($db[2] & 0x04) ? "failed" : "ok");
      push @event, "3:window:"       . (($db[2] & 0x02) ? "open" : "closed");
      push @event, "3:actuatorStatus:".(($db[2] & 0x01) ? "obstructed" : "ok");
      push @event, "3:measured-temp:". sprintf "%0.1f", ($db[1]*40/255);
      push @event, "3:selfCtl:"      . (($db[0] & 0x04) ? "on" : "off");
      EnOcean_hvac_01Cmd($hash, $packetType, $db[1]);

    } elsif ($st eq "PM101") {
      # Light and Presence Sensor [Omnio Ratio eagle-PM101]
      # The sensor also sends switching commands (RORG F6) with the senderID-1
      # $db[2] is the illuminance where 0x00 = 0 lx ... 0xFF = 1000 lx
      my $channel2 = $db[0] & 2 ? "yes" : "no";
      push @event, "3:brightness:" . $db[2] << 2;
      push @event, "3:channel1:" . ($db[0] & 1 ? "yes" : "no");
      push @event, "3:channel2:" . $channel2;
      push @event, "3:motion:" . $channel2;
      push @event, "3:state:" . $channel2;

    } elsif ($st =~ m/^tempSensor/) {
      # Temperature Sensor with with different ranges (EEP A5-02-01 ... A5-02-1B)
      # $db[1] is the temperature where 0x00 = max �C ... 0xFF = min �C
      my $temp;
      $temp = sprintf "%0.1f",   0 - $db[1] / 6.375 if ($st eq "tempSensor.01");
      $temp = sprintf "%0.1f",  10 - $db[1] / 6.375 if ($st eq "tempSensor.02");
      $temp = sprintf "%0.1f",  20 - $db[1] / 6.375 if ($st eq "tempSensor.03");
      $temp = sprintf "%0.1f",  30 - $db[1] / 6.375 if ($st eq "tempSensor.04");
      $temp = sprintf "%0.1f",  40 - $db[1] / 6.375 if ($st eq "tempSensor.05");
      $temp = sprintf "%0.1f",  50 - $db[1] / 6.375 if ($st eq "tempSensor.06");
      $temp = sprintf "%0.1f",  60 - $db[1] / 6.375 if ($st eq "tempSensor.07");
      $temp = sprintf "%0.1f",  70 - $db[1] / 6.375 if ($st eq "tempSensor.08");
      $temp = sprintf "%0.1f",  80 - $db[1] / 6.375 if ($st eq "tempSensor.09");
      $temp = sprintf "%0.1f",  90 - $db[1] / 6.375 if ($st eq "tempSensor.0A");
      $temp = sprintf "%0.1f", 100 - $db[1] / 6.375 if ($st eq "tempSensor.0B");
      $temp = sprintf "%0.1f",  20 - $db[1] / 3.1875 if ($st eq "tempSensor.10");
      $temp = sprintf "%0.1f",  30 - $db[1] / 3.1875 if ($st eq "tempSensor.11");
      $temp = sprintf "%0.1f",  40 - $db[1] / 3.1875 if ($st eq "tempSensor.12");
      $temp = sprintf "%0.1f",  50 - $db[1] / 3.1875 if ($st eq "tempSensor.13");
      $temp = sprintf "%0.1f",  60 - $db[1] / 3.1875 if ($st eq "tempSensor.14");
      $temp = sprintf "%0.1f",  70 - $db[1] / 3.1875 if ($st eq "tempSensor.15");
      $temp = sprintf "%0.1f",  80 - $db[1] / 3.1875 if ($st eq "tempSensor.16");
      $temp = sprintf "%0.1f",  90 - $db[1] / 3.1875 if ($st eq "tempSensor.17");
      $temp = sprintf "%0.1f", 100 - $db[1] / 3.1875 if ($st eq "tempSensor.18");
      $temp = sprintf "%0.1f", 110 - $db[1] / 3.1875 if ($st eq "tempSensor.19");
      $temp = sprintf "%0.1f", 120 - $db[1] / 3.1875 if ($st eq "tempSensor.1A");
      $temp = sprintf "%0.1f", 130 - $db[1] / 3.1875 if ($st eq "tempSensor.1B");
      $temp = sprintf "%0.2f", 41.2 - (($db[2] << 8) | $db[1]) / 20 if ($st eq "tempSensor.20");
      $temp = sprintf "%0.1f", 62.3 - (($db[2] << 8) | $db[1]) / 10 if ($st eq "tempSensor.30");
      push @event, "3:temperature:$temp";
      push @event, "3:state:$temp";

    } elsif ($st eq "COSensor.01") {
      # Gas Sensor, CO Sensor (EEP A5-09-01)
      # [untested]
      # $db[3] is the CO concentration where 0x00 = 0 ppm ... 0xFF = 255 ppm
      # $db[1] is the temperature where 0x00 = 0 �C ... 0xFF = 255 �C
      # $db[0] bit D1 temperature sensor available 0 = no, 1 = yes
      my $coChannel1 = $db[3];
      push @event, "3:CO:$coChannel1";
      if ($db[0] & 2) {
        my $temp = $db[1];
        push @event, "3:temperature:$temp";
      }
      push @event, "3:state:$coChannel1";

    } elsif ($st eq "COSensor.02") {
      # Gas Sensor, CO Sensor (EEP A5-09-02)
      # [untested]
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db[2] is the CO concentration where 0x00 = 0 ppm ... 0xFF = 1020 ppm
      # $db[1] is the temperature where 0x00 = 0 �C ... 0xFF = 51 �C
      # $db[0]_bit_1 temperature sensor available 0 = no, 1 = yes
      my $coChannel1 = $db[2] << 2;
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      push @event, "3:CO:$coChannel1";
      if ($db[0] & 2) {
        my $temp = sprintf "%0.1f", $db[1] * 0.2;
        push @event, "3:temperature:$temp";
      }
      push @event, "3:voltage:$voltage";
      push @event, "3:state:$coChannel1";

    } elsif ($st eq "tempHumiCO2Sensor.01") {
      # Gas Sensor, CO2 Sensor (EEP A5-09-04)
      # [Thermokon SR04 CO2 *, Eltako FCOTF63, untested]
      # $db[3] is the humidity where 0x00 = 0 %rH ... 0xC8 = 100 %rH
      # $db[2] is the CO2 concentration where 0x00 = 0 ppm ... 0xFF = 2500 ppm
      # $db[1] is the temperature where 0x00 = 0�C ... 0xFF = +51 �C
      # $db[0] bit D2 humidity sensor available 0 = no, 1 = yes
      # $db[0] bit D1 temperature sensor available 0 = no, 1 = yes
      my $humi = "unknown";
      my $temp = "unknown";
      my $airQuality;
      if ($db[0] & 4) {
        $humi = $db[3] >> 1;
      push @event, "3:humidity:$humi";
      }
      my $co2 = sprintf "%d", $db[2] * 10;
      push @event, "3:CO2:$co2";
      if ($db[0] & 2) {
        $temp = sprintf "%0.1f", $db[1] * 51 / 255 ;
        push @event, "3:temperature:$temp";
      }
      if ($co2 <= 400) {
        $airQuality = "high";
      } elsif ($co2 <= 600) {
        $airQuality = "mean";
      }  elsif ($co2 <= 1000) {
        $airQuality = "moderate";
      } else {
        $airQuality = "low";
      }
      push @event, "3:airQuality:$airQuality";
      push @event, "3:state:CO2: $co2 AQ: $airQuality T: $temp H: $humi";

    } elsif ($st eq "radonSensor.01") {
      # Gas Sensor, Radon Sensor (EEP A5-09-06)
      # [untested]
      # $db[3]_bit_7 ... $db[2]_bit_6 is the radon activity where 0 = 0 Bq/m3 ... 1023 = 1023 Bq/m3
      my $rn = $db[3] << 2 | $db[2] >> 6;
      push @event, "3:Rn:$rn";
      push @event, "3:state:$rn";

    } elsif ($st eq "vocSensor.01") {
      # Gas Sensor, VOC Sensor (EEP A5-09-05)
      # [untested]
      # $db[3]_bit_7 ... $db[2]_bit_0 is the VOC concentration where 0 = 0 ppb ... 65535 = 65535 ppb
      # $db[1] is the VOC identification
      # $db[0]_bit_1 ... $db[0]_bit_0 is the scale multiplier
      my $vocSCM = $db[0] & 3;
      if ($vocSCM == 3) {
        $vocSCM = 10;
      } elsif ($vocSCM == 2) {
        $vocSCM = 1;
      } elsif ($vocSCM == 1) {
        $vocSCM = 0.1;
      } else {
        $vocSCM = 0.01;
      }
      my $vocConc = sprintf "%f", ($db[3] << 8 | $db[2]) * $vocSCM;
      my %vocID = (
        0 => "VOCT",
        1 => "Formaldehyde",
        2 => "Benzene",
        3 => "Styrene",
        4 => "Toluene",
        5 => "Tetrachloroethylene",
        6 => "Xylene",
        7 => "n-Hexane",
        8 => "n-Octane",
        9 => "Cyclopentane",
        10 => "Methanol",
        11 => "Ethanol",
        12 => "1-Pentanol",
        13 => "Acetone",
        14 => "Ethylene Oxide",
        15 => "Acetaldehyde ue",
        16 => "Acetic Acid",
        17 => "Propionice Acid",
        18 => "Valeric Acid",
        19 => "Butyric Acid",
        20 => "Ammoniac",
        22 => "Hydrogen Sulfide",
        23 => "Dimethylsulfide",
        24 => "2-Butanol",
        25 => "2-Methylpropanol",
        26 => "Diethyl Ether",
        255 => "Ozone",
      );
      if ($vocID{$db[1]}) {
        push @event, "3:vocName:$vocID{$db[1]}";
      } else {
        push @event, "3:vocName:unknown";
      }
      push @event, "3:concentration:$vocConc";
      push @event, "3:state:$vocConc";

    } elsif ($st eq "CO2Sensor.01") {
      # CO2 Sensor (EEP A5-09-08, A5-09-09)
      # [untested]
      # $db[1] is the CO2 concentration where 0x00 = 0 ppm ... 0xFF = 2000 ppm
      # $db[0]_bit_2 is power failure detection
      my $co2 = $db[1] / 255 * 2000;     
      push @event, "3:powerFailureDetection:" . ($db[0] & 4 ? "detected":"not_detected");
      push @event, "3:CO2:$co2";
      push @event, "3:state:$co2";

    } elsif ($st eq "particlesSensor.01") {
      # Gas Sensor, Particles Sensor (EEP A5-09-07)
      # [untested]
      # $db[3]_bit_7 ... $db[2]_bit_7 is the particle concentration < 10 �m
      # where 0 = 0 �g/m3 ... 511 = 511 �g/m3
      # $db[2]_bit_6 ... $db[1]_bit_6 is the particle concentration < 2.5 �m
      # where 0 = 0 �g/m3 ... 511 = 511 �g/m3
      # $db[1]_bit_5 ... $db[0]_bit_5 is the particle concentration < 1 �m
      # where 0 = 0 �g/m3 ... 511 = 511 �g/m3
      # $db[0]_bit_2 = 1 = Sensor PM10 active
      # $db[0]_bit_1 = 1 = Sensor PM2_5 active
      # $db[0]_bit_0 = 1 = Sensor PM1 active
      my $pm_10 = "inactive";
      my $pm_2_5 = "inactive";
      my $pm_1 = "inactive";
      if ($db[0] & 4) {$pm_10 = $db[3] << 1 | $db[2] >> 7;}
      if ($db[0] & 2) {$pm_2_5 = ($db[2] & 0x7F) << 1 | $db[1] >> 7;}
      if ($db[0] & 1) {$pm_1 = ($db[1] & 0x3F) << 3 | $db[0] >> 5;}
      push @event, "3:particles_10:$pm_10";
      push @event, "3:particles_2_5:$pm_2_5";
      push @event, "3:particles_1:$pm_1";
      push @event, "3:state:PM10: $pm_10 PM2_5: $pm_2_5 PM1: $pm_1";

    } elsif ($st eq "roomSensorControl.05") {
      # Room Sensor and Control Unit (EEP A5-10-01 ... A5-10-0D)
      # [Eltako FTR55D, FTR55H, Thermokon SR04 *, Thanos SR *, untested]
      # $db[3] is the fan speed or night reduction for Eltako
      # $db[2] is the setpoint where 0x00 = min ... 0xFF = max or
      # reference temperature for Eltako where 0x00 = 0�C ... 0xFF = 40�C
      # $db[1] is the temperature where 0x00 = +40�C ... 0xFF = 0�C
      # $db[0]_bit_0 is the occupy button, pushbutton or slide switch
      my $temp = sprintf "%0.1f", 40 - $db[1] / 6.375;
      if ($manufID eq "00D") {
        my $nightReduction = 0;
        $nightReduction = 1 if ($db[3] == 0x06);
        $nightReduction = 2 if ($db[3] == 0x0C);
        $nightReduction = 3 if ($db[3] == 0x13);
        $nightReduction = 4 if ($db[3] == 0x19);
        $nightReduction = 5 if ($db[3] == 0x1F);
        my $setpointTemp = sprintf "%0.1f", $db[2] / 6.375;
        push @event, "3:state:T: $temp SPT: $setpointTemp NR: $nightReduction";
        push @event, "3:nightReduction:$nightReduction";
        push @event, "3:setpointTemp:$setpointTemp";
      } else {
        my $fspeed = 3;
        $fspeed = 2      if ($db[3] >= 145);
        $fspeed = 1      if ($db[3] >= 165);
        $fspeed = 0      if ($db[3] >= 190);
        $fspeed = "auto" if ($db[3] >= 210);
        my $switch = $db[0] & 1;
        push @event, "3:state:T: $temp SP: $db[2] F: $fspeed SW: $switch";
        push @event, "3:fanStage:$fspeed";
        push @event, "3:switch:$switch";
        push @event, "3:setpoint:$db[2]";
        my $setpointScaled = EnOcean_ReadingScaled($hash, $db[2], 0, 255);
        if (defined $setpointScaled) {
          push @event, "3:setpointScaled:" . $setpointScaled;
        }
      }
      push @event, "3:temperature:$temp";

    } elsif ($st eq "roomSensorControl.01") {
      # Room Sensor and Control Unit (EEP A5-04-01, A5-10-10 ... A5-10-14)
      # [Thermokon SR04 * rH, Thanus SR *, untested]
      # $db[3] is the setpoint where 0x00 = min ... 0xFF = max
      # $db[2] is the humidity where 0x00 = 0%rH ... 0xFA = 100%rH
      # $db[1] is the temperature where 0x00 = 0�C ... 0xFA = +40�C
      # $db[0] bit D0 is the occupy button, pushbutton or slide switch
      my $temp = sprintf "%0.1f", $db[1] * 40 / 250;
      my $humi = sprintf "%d", $db[2] / 2.5;
      my $switch = $db[0] & 1;
      push @event, "3:humidity:$humi";
      push @event, "3:temperature:$temp";
      if ($manufID eq "039") {
        my $brightness = sprintf "%d", $db[3] * 117;
        push @event, "3:brightness:$brightness";      
        push @event, "3:state:T: $temp H: $humi B: $brightness";
      } else {
        push @event, "3:setpoint:$db[3]";
        push @event, "3:state:T: $temp H: $humi SP: $db[3] SW: $switch";
        push @event, "3:switch:$switch";
        my $setpointScaled = EnOcean_ReadingScaled($hash, $db[3], 0, 255);
        if (defined $setpointScaled) {
          push @event, "3:setpointScaled:" . $setpointScaled;
        }
      }

    } elsif ($st eq "roomSensorControl.02") {
      # Room Sensor and Control Unit (A5-10-15 ... A5-10-17)
      # [untested]
      # $db[2] bit D7 ... D2 is the setpoint where 0 = min ... 63 = max
      # $db[2] bit D1 ... $db[1] bit D0 is the temperature where 0 = -10�C ... 1023 = +41.2�C
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $temp = sprintf "%0.2f", -10 + ((($db[2] & 3) << 8) | $db[1]) / 19.98;
      my $setpoint = ($db[2] & 0xFC) >> 2;
      my $presence = $db[0] & 1 ? "absent" : "present";
      push @event, "3:state:T: $temp SP: $setpoint P: $presence";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      my $setpointScaled = EnOcean_ReadingScaled($hash, $db[2], 0, 255);
      if (defined $setpointScaled) {
        push @event, "3:setpointScaled:" . $setpointScaled;
      }

    } elsif ($st eq "roomSensorControl.18") {
      # Room Sensor and Control Unit (A5-10-18)
      # [untested]
      # $db[3] is the illuminance where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db[2] is the setpoint where 250 = 0 �C ... 0 = 40 �C
      # $db[1] is the temperature where 250 = 0 �C ... 0 = 40 �C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $lux = $db[3] << 2;
      if ($db[3] == 251) {$lux = "over range";}
      my $setpoint = sprintf "%0.1f", 40 - $db[2] * 40 / 250;
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db[0] & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db[0] & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db[0] & 2) {
        $presence = "disabled";
      } else {
        $presence = $db[0] & 1 ? "absent" : "present";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp B: $lux F: $fanSpeed SP: $setpoint P: $presence";

    } elsif ($st eq "roomSensorControl.19") {
      # Room Sensor and Control Unit (A5-10-19)
      # [untested]
      # $db[3] is the humidity where min 0x00 = 0 %rH, max 0xFA = 10 %rH
      # $db[2] is the setpoint where 250 = 0 �C ... 0 = 40 �C
      # $db[1] is the temperature where 250 = 0 �C ... 0 = 40 �C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_1 is Occupany Button where 0 = pressed, 1 = released
      # $db[0]_bit_0 is Occupany enable where 0 = enabled, 1 = disabled
      my $humi = $db[3] / 2.5;
      my $setpoint = sprintf "%0.1f", 40 - $db[2] * 40 / 250;
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db[0] & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db[0] & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db[0] & 1) {
        $presence = "disabled";
      } else {
        $presence = $db[0] & 2 ? "absent" : "present";
      }
      push @event, "3:fan:$fanSpeed";
      push @event, "3:humidity:$humi";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp H: $humi F: $fanSpeed SP: $setpoint P: $presence";

    } elsif ($st eq "roomSensorControl.1A") {
      # Room Sensor and Control Unit (A5-10-1A)
      # [untested]
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[2] is the setpoint where 250 = 0 �C ... 0 = 40 �C
      # $db[1] is the temperature where 250 = 0 �C ... 0 = 40 �C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      my $setpoint = sprintf "%0.1f", 40 - $db[2] * 40 / 250;
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db[0] & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db[0] & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db[0] & 2) {
        $presence = "disabled";
      } else {
        $presence = $db[0] & 1 ? "absent" : "present";
      }
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:voltage:$voltage";
      push @event, "3:state:T: $temp F: $fanSpeed SP: $setpoint P: $presence U: $voltage";

    } elsif ($st eq "roomSensorControl.1B") {
      # Room Sensor and Control Unit (A5-10-1B)
      # [untested]
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[2] is the illuminance where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db[1] is the temperature where 250 = 0 �C ... 0 = 40 �C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      my $lux = $db[2] << 2;
      if ($db[2] == 251) {$lux = "over range";}
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db[0] & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db[0] & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db[0] & 2) {
        $presence = "disabled";
      } else {
        $presence = $db[0] & 1 ? "absent" : "present";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:temperature:$temp";
      push @event, "3:voltage:$voltage";
      push @event, "3:state:T: $temp B: $lux F: $fanSpeed P: $presence U: $voltage";

    } elsif ($st eq "roomSensorControl.1C") {
      # Room Sensor and Control Unit (A5-10-1C)
      # [untested]
      # $db[3] is the illuminance where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db[2] is the illuminance setpoint where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db[1] is the temperature where 250 = 0 �C ... 0 = 40 �C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $lux = $db[3] << 2;
      if ($db[3] == 251) {$lux = "over range";}
      my $setpoint = $db[2] << 2;
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db[0] & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db[0] & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db[0] & 2) {
        $presence = "disabled";
      } else {
        $presence = $db[0] & 1 ? "absent" : "present";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp B: $lux F: $fanSpeed SP: $setpoint P: $presence";

    } elsif ($st eq "roomSensorControl.1D") {
      # Room Sensor and Control Unit (A5-10-1D)
      # [untested]
      # $db[3] is the humidity where min 0x00 = 0 %rH, max 0xFA = 10 %rH
      # $db[2] is the humidity setpoint where min 0x00 = 0 %rH, max 0xFA = 10 %rH
      # $db[1] is the temperature where 250 = 0 �C ... 0 = 40 �C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $humi = sprintf "%d", $db[3] / 2.5;
      my $setpoint = $db[2] / 2.5;
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $fanSpeed;
      if ((($db[0] & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db[0] & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db[0] & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db[0] & 2) {
        $presence = "disabled";
      } else {
        $presence = $db[0] & 1 ? "absent" : "present";
      }
      push @event, "3:fan:$fanSpeed";
      push @event, "3:humidity:$humi";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp H: $humi F: $fanSpeed SP: $setpoint P: $presence";

    } elsif ($st eq "roomSensorControl.1F") {
      # Room Sensor and Control Unit (A5-10-1F)
      # [untested]
      # $db[3] is the fan speed
      # $db[2] is the setpoint where 0 = 0 ... 255 = 255
      # $db[1] is the temperature where 250 = 0 �C ... 0 = 40 �C
      # $db[0]_bit_6 ... $db[0]_bit_4 is the fan speed
      # $db[0]_bit_6 ... $db[0]_bit_4 are flags
      # $db[0]_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $fanSpeed = "unknown";
      if ($db[0] & 0x10) {
        $fanSpeed = 3;
        $fanSpeed = 2      if ($db[3] >= 145);
        $fanSpeed = 1      if ($db[3] >= 165);
        $fanSpeed = 0      if ($db[3] >= 190);
        $fanSpeed = "auto" if ($db[3] >= 210);
      }
      my $setpoint = "unknown";
      $setpoint = $db[2] if ($db[0] & 0x20);
      my $temp = "unknown";
      $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250 if ($db[0] & 0x40);
      my $presence = "unknown";
      $presence = "absent" if (!($db[0] & 2));
      $presence = "present" if (!($db[0] & 1));
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp F: $fanSpeed SP: $setpoint P: $presence";
      my $setpointScaled = EnOcean_ReadingScaled($hash, $db[2], 0, 255);
      if (defined $setpointScaled) {
        push @event, "3:setpointScaled:" . $setpointScaled;
      }

    } elsif ($st eq "roomSensorControl.20") {
      # Room Operation Panel (A5-10-20, A5-10-21)
      # [untested]
      # $db[3] is the setpoint where 0 = 0 ... 255 = 255
      # $db[2] is the humidity setpoint where min 0x00 = 0 %rH, max 0xFA = 10 %rH
      # $db[1] is the temperature where 250 = 0 �C ... 0 = 40 �C
      # $db[0]_bit_6 ... $db[0]_bit_5 is setpoint mode
      # $db[0]_bit_4 is battery state 0 = ok, 1 = low
      # $db[0]_bit_0 is user activity where 0 = no, 1 = yes
      my $humi = sprintf "%d", $db[2] / 2.5;
      my $setpoint = $db[3];
      my $temp = sprintf "%0.1f", 40 - $db[1] * 40 / 250;
      my $setpointMode;
      if ((($db[0] & 0x60) >> 5) == 3) {
        $setpointMode = "reserved";
      } elsif ((($db[0] & 0x60) >> 5) == 2) {
        $setpointMode = "auto";
      } elsif ((($db[0] & 0x60) >> 1) == 1){
        $setpointMode = "frostProtection";
      } else {
        $setpointMode = "setpoint";
      }
      my $battery = ($db[0] & 0x10) ? "low" : "ok";
      push @event, "3:activity:" . (($db[0] & 1) ? "yes" : "no");
      push @event, "3:battery:$battery";    
      push @event, "3:humidity:$humi";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:setpointMode:$setpointMode";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp H: $humi SP: $setpoint B: $battery";
      my $setpointScaled = EnOcean_ReadingScaled($hash, $db[3], 0, 255);
      if (defined $setpointScaled) {
        push @event, "3:setpointScaled:" . $setpointScaled;
      }

    } elsif ($st eq "tempHumiSensor.02") {
      # Temperatur and Humidity Sensor(EEP A5-04-02)
      # [Eltako FAFT60, FIFT63AP]
      # $db[3] is the voltage where 0x59 = 2.5V ... 0x9B = 4V, only at Eltako
      # $db[2] is the humidity where 0x00 = 0%rH ... 0xFA = 100%rH
      # $db[1] is the temperature where 0x00 = -20�C ... 0xFA = +60�C
      my $humi = sprintf "%d", $db[2] / 2.5;
      my $temp = sprintf "%0.1f", -20 + $db[1] * 80 / 250;
      my $battery = "unknown";
      if ($manufID eq "00D") {
        # Eltako sensor
        my $voltage = sprintf "%0.1f", $db[3] * 6.58 / 255;
        my $energyStorage = "unknown";
        if ($db[3] <= 0x58) {
          $energyStorage = "empty";
          $battery = "low";
        }
        elsif ($db[3] <= 0xDC) {
          $energyStorage = "charged";
          $battery = "ok";
        }
        else {
          $energyStorage = "full";
          $battery = "ok";
        }
        push @event, "3:battery:$battery";
        push @event, "3:energyStorage:$energyStorage";
        push @event, "3:voltage:$voltage";
      }
      push @event, "3:state:T: $temp H: $humi B: $battery";
      push @event, "3:humidity:$humi";
      push @event, "3:temperature:$temp";

    } elsif ($st eq "tempHumiSensor.03") {
      # Temperatur and Humidity Sensor(EEP A5-04-03)
      # [untested]
      # $db[3] is the humidity where 0x00 = 0%rH ... 0xFF = 100%rH
      # $db[2] .. $db[1] is the temperature where 0x00 = -20�C ... 0x3FF = +60�C
      my $humi = sprintf "%d", $db[3] / 2.55;
      my $temp = sprintf "%0.1f", -20 + ($db[2] << 8 | $db[1]) * 80 / 1023;
      push @event, "3:state:T: $temp H: $humi";
      push @event, "3:humidity:$humi";
      push @event, "3:temperature:$temp";
      push @event, "3:telegramType:" . ($db[0] & 1 ? "event" : "heartbeat");

    } elsif ($st eq "baroSensor.01") {
      # Barometric Sensor(EEP A5-04-03)
      # [untested]
      # $db[3] is the humidity where 0x00 = 0%rH ... 0xFF = 100%rH
      # $db[3] .. $db[2] is the barometric  where 0x00 = 500 hPa ... 0x3FF = 1150 hPa
      my $baro = sprintf "%d", 500 + ($db[2] << 8 | $db[1]) * 650 / 1023;
      push @event, "3:state:$baro";
      push @event, "3:airPressure:$baro";
      push @event, "3:telegramType:" . ($db[0] & 1 ? "event" : "heartbeat");

    } elsif ($st eq "lightSensor.01") {
      # Light Sensor (EEP A5-06-01)
      # [Eltako FAH60, FAH63, FIH63, Thermokon SR65 LI, untested]
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db[3] is the low illuminance for Eltako devices where
      # min 0x00 = 0 lx, max 0xFF = 100 lx, if $db[2] = 0
      # $db[2] is the illuminance (ILL2) where min 0x00 = 300 lx, max 0xFF = 30000 lx
      # $db[1] is the illuminance (ILL1) where min 0x00 = 600 lx, max 0xFF = 60000 lx
      # $db[0]_bit_0 is Range select where 0 = ILL1, 1 = ILL2
      my $lux;
      my $voltage = "unknown";
      if ($manufID eq "00D") {
        if($db[2] == 0) {
          $lux = sprintf "%d", $db[3] * 100 / 255;
        } else {
          $lux = sprintf "%d", $db[2] * 116.48 + 300;
        }
      } else {
        $voltage = sprintf "%0.1f", $db[3] * 0.02;
        if($db[0] & 1) {
          $lux = sprintf "%d", $db[2] * 116.48 + 300;
        } else {
          $lux = sprintf "%d", $db[1] * 232.94 + 600;
        }
        push @event, "3:voltage:$voltage";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:state:$lux";

    } elsif ($st eq "lightSensor.02") {
      # Light Sensor (EEP A5-06-02)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db[2] is the illuminance (ILL2) where min 0x00 = 0 lx, max 0xFF = 510 lx
      # $db[1] is the illuminance (ILL1) where min 0x00 = 0 lx, max 0xFF = 1020 lx
      # $db[0]_bit_0 is Range select where 0 = ILL1, 1 = ILL2
      my $lux;
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      if($db[0] & 1) {
        $lux = $db[2] << 1;
      } else {
        $lux = $db[1] << 2;
      }
      push @event, "3:voltage:$voltage";
      push @event, "3:brightness:$lux";
      push @event, "3:state:$lux";

    } elsif ($st eq "lightSensor.03") {
      # Light Sensor (EEP A5-06-03)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[2]_bit_7 ... $db[1]_bit_6 is the illuminance where min 0x000 = 0 lx, max 0x3E8 = 1000 lx
      my $lux = $db[2] << 2 | $db[1] >> 6;
      if ($lux == 1001) {$lux = "over range";}
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      push @event, "3:voltage:$voltage";
      push @event, "3:brightness:$lux";
      push @event, "3:state:$lux";

    } elsif ($st eq "occupSensor.01") {
      # Occupancy Sensor (EEP A5-07-01)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[2] is solar panel current where =0 uA ... 0xFF = 127 uA      
      # $db[1] is PIR Status (motion) where 0 ... 127 = off, 128 ... 255 = on
      my $motion = "off";
      if ($db[1] >= 128) {$motion = "on";}
      if ($db[0] & 1) {push @event, "3:voltage:" . sprintf "%0.1f", $db[3] * 0.02;}
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      if ($manufID eq "00B") {
        push @event, "3:current:" . sprintf "%0.1f", $db[2] / 2;
        if ($db[0] & 2) {          
          push @event, "3:sensorType:ceiling";
        } else {
          push @event, "3:sensorType:wall";        
        }
      }
      push @event, "3:motion:$motion";
      push @event, "3:state:$motion";

    } elsif ($st eq "occupSensor.02") {
      # Occupancy Sensor (EEP A5-07-02)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[0]_bit_7 is PIR Status (motion) where 0 = off, 1 = on
      my $motion = $db[0] >> 7 ? "on" : "off";
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      push @event, "3:motion:$motion";
      push @event, "3:voltage:" . sprintf "%0.1f", $db[3] * 0.02;
      push @event, "3:state:$motion";

    } elsif ($st eq "occupSensor.03") {
      # Occupancy Sensor (EEP A5-07-03)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[2]_bit_7 ... $db[1]_bit_6 is the illuminance where min 0x000 = 0 lx, max 0x3E8 = 1000 lx
      # $db[0]_bit_7 is PIR Status (motion) where 0 = off, 1 = on
      my $motion = $db[0] >> 7 ? "on" : "off";
      my $lux = $db[2] << 2 | $db[1] >> 6;
      if ($lux == 1001) {$lux = "over range";}
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      push @event, "3:brightness:$lux";
      push @event, "3:motion:$motion";
      push @event, "3:voltage:$voltage";
      push @event, "3:state:M: $motion E: $lux U: $voltage";

    } elsif ($st =~ m/^lightTempOccupSensor/) {
      # Light, Temperatur and Occupancy Sensor (EEP A5-08-01 ... A5-08-03)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db[2] is the illuminance where min 0x00 = 0 lx, max 0xFF = 510 lx, 1020 lx, (2048 lx)
      # $db[1] is the temperature whrere 0x00 = 0 �C ... 0xFF = 51 �C or -30 �C ... 50�C
      # $db[0]_bit_1 is PIR Status (motion) where 0 = on, 1 = off
      # $db[0]_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $lux;
      my $temp;
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      my $motion = $db[0] & 2 ? "off" : "on";
      my $presence = $db[0] & 1 ? "absent" : "present";

      if ($st eq "lightTempOccupSensor.01") {
        # Light, Temperatur and Occupancy Sensor (EEP A5-08-01)
        # [Eltako FABH63, FBH55, FBH63, FIBH63]
        if ($manufID eq "00D") {
          $lux = sprintf "%d", $db[2] * 2048 / 255;
          push @event, "3:state:M: $motion E: $lux";
        } else {
          $lux = $db[2] << 1;
          $temp = sprintf "%0.1f", $db[1] * 0.2;
          push @event, "3:state:M: $motion E: $lux P: $presence T: $temp U: $voltage";
          push @event, "3:presence:$presence";
          push @event, "3:temperature:$temp";
          push @event, "3:voltage:$voltage";
        }
      } elsif ($st eq "lightTempOccupSensor.02") {
        # Light, Temperatur and Occupancy Sensor (EEP A5-08-02)
        $lux = $db[2] << 2;
        $temp = sprintf "%0.1f", $db[1] * 0.2;
        push @event, "3:state:M: $motion E: $lux P: $presence T: $temp U: $voltage";
        push @event, "3:presence:$presence";
        push @event, "3:temperature:$temp";
        push @event, "3:voltage:$voltage";
      } elsif ($st eq "lightTempOccupSensor.03") {
        # Light, Temperatur and Occupancy Sensor (EEP A5-08-03)
        $lux = $db[2] * 6;
        $temp = sprintf "%0.1f", -30 + $db[1] * 80 / 255;
        push @event, "3:state:M: $motion E: $lux P: $presence T: $temp U: $voltage";
        push @event, "3:presence:$presence";
        push @event, "3:temperature:$temp";
        push @event, "3:voltage:$voltage";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:motion:$motion";

    } elsif ($st eq "lightCtrlState.01") {
      # Lighting Controller State (EEP A5-11-01)
      # $db[3] is the illumination where 0x00 = 0 lx ... 0xFF = 510 lx
      # $db[2] is the illumination Setpoint where 0x00 = 0 ... 0xFF = 255
      # $db[1] is the Dimming Output Level where 0x00 = 0 ... 0xFF = 255
      # $db[0]_bit_7 is the Repeater state where 0 = disabled, 1 = enabled
      # $db[0]_bit_6 is the Power Relay Timer state where 0 = disabled, 1 = enabled
      # $db[0]_bit_5 is the Daylight Harvesting state where 0 = disabled, 1 = enabled
      # $db[0]_bit_4 is the Dimming mode where 0 = switching, 1 = dimming
      # $db[0]_bit_2 is the Magnet Contact state where 0 = open, 1 = closed
      # $db[0]_bit_1 is the Occupancy (prensence) state where 0 = absent, 1 = present
      # $db[0]_bit_0 is the Power Relay state where 0 = off, 1 = on
      push @event, "3:brightness:" . ($db[3] << 1);
      push @event, "3:illum:$db[2]";
      push @event, "3:dim:$db[1]";
      push @event, "3:powerRelayTimer:" . ($db[0] & 0x80 ? "enabled" : "disabled");
      push @event, "3:repeater:" . ($db[0] & 0x40 ? "enabled" : "disabled");
      push @event, "3:daylightHarvesting:" . ($db[0] & 0x20 ? "enabled" : "disabled");
      push @event, "3:mode:" . ($db[0] & 0x10 ? "dimming" : "switching");
      push @event, "3:contact:" . ($db[0] & 4 ? "closed" : "open");
      push @event, "3:presence:" . ($db[0] & 2 ? "present" : "absent");
      push @event, "3:powerSwitch:" . ($db[0] & 1 ? "on" : "off");
      push @event, "3:state:" . ($db[0] & 1 ? "on" : "off");

    } elsif ($st eq "tempCtrlState.01") {
      # Temperature Controller Output (EEP A5-11-02)
      # $db[3] is the Control Variable where 0x00 = 0 % ... 0xFF = 100 %
      # $db[2] is the Fan Stage
      # $db[1] is the Actual Setpoint where 0x00 = 0 �C ... 0xFF = 51.2 �C
      # $db[0]_bit_7 is the Alarm state where 0 = no, 1 = yes
      # $db[0]_bit_6 ... $db[0]_bit_5 is the Controller Mode
      # $db[0]_bit_4 is the Controller State where 0 = auto, 1 = override
      # $db[0]_bit_2 is the Energy hold-off where 0 = normal, 1 = hold-off
      # $db[0]_bit_1 ... $db[0]_bit_0is the Occupancy (prensence) state where 0 = present
      # 1 = absent, 3 = standby, 4 = frost
      push @event, "3:controlVar:" . sprintf "%d", $db[3] * 100 / 255;
      if (($db[2] & 3) == 0) {
        push @event, "3:fan:0";
      } elsif (($db[2] & 3) == 1){
        push @event, "3:fan:1";
      } elsif (($db[2] & 3) == 2){
        push @event, "3:fan:2";
      } elsif (($db[2] & 3) == 3){
        push @event, "3:fan:3";
      } elsif ($db[2] == 255){
        push @event, "3:fan:unknown";
      }
      push @event, "3:fanMode:" . ($db[2] & 0x10 ? "auto" : "manual");
      my $setpointTemp = sprintf "%0.1f", $db[1] * 0.2;
      push @event, "3:setpointTemp:$setpointTemp";
      push @event, "3:alarm:" . ($db[0] & 1 ? "on" : "off");
      my $controllerMode = ($db[0] & 0x60) >> 5;
      if ($controllerMode == 0) {
        push @event, "3:controllerMode:auto";
      } elsif ($controllerMode == 1) {
        push @event, "3:controllerMode:heating";
      } elsif ($controllerMode == 2) {
        push @event, "3:controllerMode:cooling";
      } elsif ($controllerMode == 3) {
        push @event, "3:controllerMode:off";
      }
      push @event, "3:controllerState:" . ($db[0] & 0x10 ? "override" : "auto");
      push @event, "3:energyHoldOff:" . ($db[0] & 4 ? "holdoff" : "normal");
      if (($db[0] & 3) == 0) {
        push @event, "3:presence:present";
      } elsif (($db[0] & 3) == 1){
        push @event, "3:presence:absent";
      } elsif (($db[0] & 3) == 2){
        push @event, "3:presence:standby";
      } elsif (($db[0] & 3) == 3){
        push @event, "3:presence:frost";
      }
      push @event, "3:state:$setpointTemp";

    } elsif ($st eq "shutterCtrlState.01") {
      # Blind Status (EEP A5-11-03)
      # $db[3] is the Shutter Position where 0 = 0 % ... 100 = 100 %
      # $db[2]_bit_7 is the Angle sign where 0 = positive, 1 = negative
      # $db[2]_bit_6 ... $db[2]_bit_0 where 0 = 0� ... 90 = 180�
      # $db[1]_bit_7 is the Position Value Flag where 0 = no available, 1 = available
      # $db[1]_bit_6 is the Angle Value Flag where 0 = no available, 1 = available
      # $db[1]_bit_5 ... $db[1]_bit_4 is the Error State (alarm)
      # $db[1]_bit_3 ... $db[1]_bit_2 is the End-position State
      # $db[1]_bit_1 ... $db[1]_bit_0 is the Shutter State
      # $db[0]_bit_7 is the Service Mode where 0 = no, 1 = yes
      # $db[0]_bit_6 is the Position Mode where 0 = normal, 1 = inverse
      if ($db[1] & 0x80) {
        push @event, "3:position:" . $db[3];
      }
      my $anglePos = ($db[2] & 0x7F) << 1;
      if ($db[2] & 0x80) {$anglePos *= -1;}
      if ($db[1] & 0x40) {
        push @event, "3:anglePos:" . $anglePos;
      }
      my $alarm = ($db[1] & 0x30) >> 4;
      if ($alarm == 0) {
        push @event, "3:alarm:off";
      } elsif ($alarm == 1){
        push @event, "3:alarm:no_endpoints_defined";
      } elsif ($alarm == 2){
        push @event, "3:alarm:on";
      } elsif ($alarm == 3){
        push @event, "3:alarm:not_used";
      }
      my $endPosition = ($db[1] & 0x0C) >> 2;
      if ($endPosition == 0) {
        push @event, "3:endPosition:not_available";
        push @event, "3:state:not_available";
      } elsif ($endPosition == 1) {
        push @event, "3:endPosition:not_reached";
        push @event, "3:state:not_reached";
      } elsif ($endPosition == 2) {
        push @event, "3:endPosition:open";
        push @event, "3:state:open";
      } elsif ($endPosition == 3){
        push @event, "3:endPosition:closed";
        push @event, "3:state:closed";
      }
      my $shutterState = $db[1] & 3;
      if (($db[1] & 3) == 0) {
        push @event, "3:shutterState:not_available";
      } elsif (($db[1] & 3) == 1) {
        push @event, "3:shutterState:stopped";
      } elsif (($db[1] & 3) == 2){
        push @event, "3:shutterState:opens";
      } elsif (($db[1] & 3) == 3){
        push @event, "3:shutterState:closes";
      }
      push @event, "3:serviceOn:" . ($db[0] & 0x80 ? "yes" : "no");
      push @event, "3:positionMode:" . ($db[0] & 0x40 ? "inverse" : "normal");

    } elsif ($st eq "lightCtrlState.02") {
      # Extended Lighting Status (EEP A5-11-04)
      # $db[3] the contents of the variable depends on the parameter mode
      # $db[2] the contents of the variable depends on the parameter mode
      # $db[1] the contents of the variable depends on the parameter mode
      # $db[0]_bit_7 is the Service Mode where 0 = no, 1 = yes
      # $db[0]_bit_6 is the operating hours flag where 0 = not_available, 1 = available
      # $db[0]_bit_5 ... $db[0]_bit_4 is the Error State (alarm)
      # $db[0]_bit_2 ... $db[0]_bit_1 is the parameter mode
      # $db[0]_bit_0 is the lighting status where 0 = off, 1 = on
      push @event, "3:serviceOn:" . ($db[1] & 0x80 ? "yes" : "no");
      my $alarm = ($db[0] & 0x30) >> 4;
      if ($alarm == 0) {
        push @event, "3:alarm:off";
      } elsif ($alarm == 1){
        push @event, "3:alarm:lamp_failure";
      } elsif ($alarm == 2){
        push @event, "3:alarm:internal_failure";
      } elsif ($alarm == 3){
        push @event, "3:alarm:external_periphery_failure";
      }
      my $mode = ($db[0] & 6) >> 1;
      if ($mode == 0) {
        # dimmer value and lamp operating hours
        push @event, "3:dim:$db[3]";
        if ($db[0] & 40) {
          push @event, "3:lampOpHours:" . ($db[2] << 8 | $db[1]);
        } else {
          push @event, "3:lampOpHours:unknown";
        }
      } elsif ($mode == 1){
        # RGB value
        #push @event, "3:rgb:$db[3] $db[2] $db[1]";
        push @event, "3:rgb:" . substr($data, 0, 6);
      } elsif ($mode == 2){
        # energy metering value
        my @measureUnit = ("mW", "W", "kW", "MW", "Wh", "kWh", "MWh", "GWh",
                           "mA", "A", "mV", "V");
        if ($db[1] < 4) {
          push @event, "3:power:" . ($db[3] << 8 | $db[2]);
          push @event, "3:powerUnit:" . $measureUnit[$db[1]];
        } elsif ($db[1] < 8) {
          push @event, "3:energy:" . ($db[3] << 8 | $db[2]);
          push @event, "3:energyUnit:" . $measureUnit[$db[1]];
        } elsif ($db[1] == 8) {
          push @event, "3:current:" . ($db[3] << 8 | $db[2]);
          push @event, "3:currentUnit:" . $measureUnit[$db[1]];
        } elsif ($db[1] == 9) {
          push @event, "3:current:" . sprintf "%0.1f", ($db[3] << 8 | $db[2]) / 10;
          push @event, "3:currentUnit:" . $measureUnit[$db[1]];
        } elsif ($db[1] == 10) {
          push @event, "3:voltage:" . ($db[3] << 8 | $db[2]);
          push @event, "3:voltageUnit:" . $measureUnit[$db[1]];
        } elsif ($db[1] == 11) {
          push @event, "3:voltage:" . sprintf "%0.1f", ($db[3] << 8 | $db[2]) / 10;
          push @event, "3:voltageUnit:" . $measureUnit[$db[1]];
        } else {
          push @event, "3:measuredValue:" . ($db[3] << 8 | $db[2]);
          push @event, "3:measureUnit:unknown";
        }
      } elsif ($mode == 3){
        # not used
      }
      push @event, "3:powerSwitch:" . ($db[0] & 1 ? "on" : "off");
      push @event, "3:state:" . ($db[0] & 1 ? "on" : "off");

    } elsif ($st =~ m/^autoMeterReading\.0[0-3]$/ || $st eq "actuator.01" && $manufID eq "033") {
      # Automated meter reading (AMR) (EEP A5-12-00 ... A5-12-03)
      # $db[3] (MSB) + $db[2] + $db[1] (LSB) is the Meter reading
      # $db[0]_bit_7 ... $db[0]_bit_4 is the Measurement channel
      # $db[0]_bit_2 is the Data type where 0 = cumulative value, 1 = current value
      # $db[0]_bit_1 ... $db[0]_bit_0 is the Divisor where 0 = x/1, 1 = x/10,
      # 2 = x/100, 3 = x/1000
      my $dataType = ($db[0] & 4) >> 2;
      my $divisor = $db[0] & 3;
      my $meterReading;
      if ($divisor == 3) {
        $meterReading = sprintf "%.3f", ($db[3] << 16 | $db[2] << 8 | $db[1]) / 1000;
      } elsif ($divisor == 2) {
        $meterReading = sprintf "%.2f", ($db[3] << 16 | $db[2] << 8 | $db[1]) / 100;
      } elsif ($divisor == 1) {
        $meterReading = sprintf "%.1f", ($db[3] << 16 | $db[2] << 8 | $db[1]) / 10;
      } else {
        $meterReading = $db[3] << 16 | $db[2] << 8 | $db[1];
      }
      my $channel = $db[0] >> 4;

      if ($st eq "autoMeterReading.00") {
        # Automated meter reading (AMR), Counter (EEP A5-12-01)
        # [Thermokon SR-MI-HS, untested]
        if ($dataType == 1) {
          # current value
          push @event, "3:currentValue:$meterReading";
          push @event, "3:state:$meterReading";
        } else {
          # cumulative counter
          push @event, "3:counter$channel:$meterReading";
        }
      } elsif ($st eq "autoMeterReading.01" || $st eq "actuator.01" && $manufID eq "033") {
        # Automated meter reading (AMR), Electricity (EEP A5-12-01)
        # [Eltako FSS12, FWZ12, DSZ14DRS, DSZ14WDRS, DWZ61]
        # $db[0]_bit_7 ... $db[0]_bit_4 is the Tariff info
        # $db[0]_bit_2 is the Data type where 0 = cumulative value kWh,
        # 1 = current value W
        if ($db[0] == 0x8F && $manufID eq "00D") {
          # Eltako, read meter serial number
          my $serialNumber;
          if ($db[1] == 0) {
            # first 2 digits of the serial number
            $serialNumber = substr(ReadingsVal($name, "serialNumber", "S-------"), 4, 4);
            $serialNumber = sprintf "S-%01x%01x%4s", $db[3] >> 4, $db[3] & 0x0F, $serialNumber;
          } else {
            # last 4 digits of the serial number
            $serialNumber = substr(ReadingsVal($name, "serialNumber", "S---"), 0, 4);
            $serialNumber = sprintf "%4s%01x%01x%01x%01x", $serialNumber,
                            $db[2] >> 4, $db[2] & 0x0F, $db[3] >> 4, $db[3] & 0x0F;
          }
          push @event, "3:serialNumber:$serialNumber";        
        } elsif ($dataType == 1) {
          # momentary power
          push @event, "3:power:$meterReading";
          if (!($st eq "actuator.01" && $manufID eq "033")) {
	    push @event, "3:state:$meterReading";
          }
        } else {
          # power consumption
          push @event, "3:energy$channel:$meterReading";
          push @event, "3:currentTariff:$channel";
        }
      } elsif ($st eq "autoMeterReading.02" || $st eq "autoMeterReading.03") {
        # Automated meter reading (AMR), Gas, Water (EEP A5-12-02, A5-12-03)
        if ($dataType == 1) {
          # current value
          push @event, "3:flowrate:$meterReading";
          push @event, "3:state:$meterReading";
        } else {
          # cumulative counter
          push @event, "3:consumption$channel:$meterReading";
          push @event, "3:currentTariff:$channel";
        }
      }
      
    } elsif ($st =~ m/^autoMeterReading\.0[45]$/) {
      # $db[1] is the temperature 0 .. 0xFF >> -40 ... 40
      # $db[0]_bit_1 ... $db[0]_bit_0 is the battery level
      my $temperature = sprintf "%0.1f", ($db[1] / 255 * 80) - 40;
      my $battery = $db[0] & 3;
      if ($battery == 3) {
        $battery = "empty";
      } elsif ($battery == 2) {
        $battery = "low";
      } elsif ($battery == 1) {
        $battery = "ok";
      } else {
        $battery = "full";
      }
      push @event, "3:battery:$battery";
      push @event, "3:temperature:$temperature";
      
      if ($st eq "autoMeterReading.04") {
        # Automated meter reading (AMR), Temperature, Load (EEP A5-12-04)
        # $db[3] ... $db[2]_bit_2 is the Current Value in gram
        my $weight = $db[3] << 6 | $db[2];
        push @event, "3:weight:$weight";
        push @event, "3:state:T: $temperature W: $weight B: $battery";
        
        
      } elsif ($st eq "autoMeterReading.05") {
        # Automated meter reading (AMR), Temperature, Container (EEP A5-12-05)
        # $db[3] ... $db[2]_bit_6 is position sensor
        my @sp;
        $sp[0] = ($db[3] & 128) >> 7;
        $sp[1] = ($db[3] & 64) >> 6;
        $sp[2] = ($db[3] & 32) >> 5;
        $sp[3] = ($db[3] & 16) >> 4;
        $sp[4] = ($db[3] & 8) >> 3;
        $sp[5] = ($db[3] & 4) >> 2;
        $sp[6] = ($db[3] & 2) >> 1;
        $sp[7] = $db[3] & 1;
        $sp[8] = ($db[2] & 128) >> 7;
        $sp[9] = ($db[2] & 64) >> 6;
        my $amount = 0;
        for (my $spCntr = 0; $spCntr <= 9; $spCntr ++) {
          push @event, "3:location" . $spCntr . ":" . ($sp[$spCntr] ? "possessed" : "not_possessed");
          $amount += $sp[$spCntr];
        }
        push @event, "3:amount:$amount";        
        push @event, "3:state:T: $temperature L: " . $sp[0] . $sp[1] . " " . $sp[2] . $sp[3] .
                        " " . $sp[4] . $sp[5] . " " . $sp[6] . $sp[7] . " " . $sp[8] . $sp[9] . " B: $battery";
      }

    } elsif ($st eq "environmentApp") {
      # Environmental Applications (EEP A5-13-01 ... EEP A5-13-06, EEP A5-13-10)
      # [Eltako FWS61]
      # $db[0]_bit_7 ... $db[0]_bit_4 is the Identifier
      my $identifier = $db[0] >> 4;
      if ($identifier == 1) {
        # Weather Station (EEP A5-13-01)
        # $db[3] is the dawn sensor where 0x00 = 0 lx ... 0xFF = 999 lx
        # $db[2] is the temperature where 0x00 = -40 �C ... 0xFF = 80 �C
        # $db[1] is the wind speed where 0x00 = 0 m/s ... 0xFF = 70 m/s
        # $db[0]_bit_2 is day / night where 0 = day, 1 = night
        # $db[0]_bit_1 is rain indication where 0 = no (no rain), 1 = yes (rain)
        my $dawn = sprintf "%d", $db[3] * 999 / 255;
        my $temp = sprintf "%0.1f", -40 + $db[2] * 120 / 255;
        my $windSpeed = sprintf "%0.1f", $db[1] * 70 / 255;
        my $dayNight = $db[0] & 4 ? "night" : "day";
        my $isRaining = $db[0] & 2 ? "yes" : "no";
        push @event, "3:brightness:$dawn";
        push @event, "3:dayNight:$dayNight";
        push @event, "3:isRaining:$isRaining";
        push @event, "3:temperature:$temp";
        push @event, "3:windSpeed:$windSpeed";
        push @event, "3:state:T: $temp B: $dawn W: $windSpeed IR: $isRaining";
      } elsif ($identifier == 2) {
        # Sun Intensity (EEP A5-13-02)
        # $db[3] is the sun exposure west where 0x00 = 1 lx ... 0xFF = 150 klx
        # $db[2] is the sun exposure south where 0x00 = 1 lx ... 0xFF = 150 klx
        # $db[1] is the sun exposure east where 0x00 = 1 lx ... 0xFF = 150 klx
        # $db[0]_bit_2 is hemisphere where 0 = north, 1 = south
        push @event, "3:hemisphere:" . ($db[0] & 4 ? "south" : "north");
        push @event, "3:sunWest:" . sprintf "%d", 1 + $db[3] * 149999 / 255;
        push @event, "3:sunSouth:" . sprintf "%d", 1 + $db[2] * 149999 / 255;
        push @event, "3:sunEast:" . sprintf "%d", 1 + $db[1] * 149999 / 255;
      } elsif ($identifier == 7) {
        # Sun Position and Radiation (EEP A5-13-10)
        # $db[3]_bit_7 ... $db[3]_bit_1 is Sun Elevation where 0 = 0 � ... 90 = 90 �
        # $db[3]_bit_0 is day / night where 0 = day, 1 = night
        # $db[2] is Sun Azimuth where 0 = -90 � ... 180 = 90 �
        # $db[1] and $db[0]_bit_2 ... $db[0]_bit_0 is Solar Radiation where
        # 0 = 0 W/m2 ... 2000 = 2000 W/m2
        my $sunElev = $db[3] >> 1;
        my $sunAzim = $db[2] - 90;
        my $solarRad = $db[1] << 3 | $db[0] & 7;
        push @event, "3:dayNight:" . ($db[3] & 1 ? "night" : "day");
        push @event, "3:solarRadiation:$solarRad";
        push @event, "3:sunAzimuth:$sunAzim";
        push @event, "3:sunElevation:$sunElev";
        push @event, "3:state:SRA: $solarRad SNA: $sunAzim SNE: $sunElev";
      } else {
        # EEP A5-13-03 ... EEP A5-13-06 not implemented
      }

    } elsif ($st eq "multiFuncSensor") {
      # Multi-Func Sensor (EEP A5-14-01 ... A5-14-06)
      # $db[3] is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db[3] > 0xFA is error code
      # $db[2] is the illuminance where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db[0]_bit_1 is Vibration where 0 = off, 1 = on
      # $db[0]_bit_0 is Contact where 0 = closed, 1 = open
      my $lux = $db[2] << 2;
      if ($db[2] == 251) {$lux = "over range";}
      my $voltage = sprintf "%0.1f", $db[3] * 0.02;
      if ($db[3] > 250) {push @event, "3:errorCode:$db[3]";}
      my $vibration = $db[0] & 2 ? "on" : "off";
      my $contact = $db[0] & 1 ? "open" : "closed";
      push @event, "3:brightness:$lux";
      push @event, "3:contact:$contact";
      push @event, "3:vibration:$vibration";
      push @event, "3:voltage:$voltage";
      push @event, "3:state:C: $contact V: $vibration E: $lux U: $voltage";

    } elsif ($st =~ m/^digitalInput\.0[12]$/) {
      # Digital Input (EEP A5-30-01, A5-30-02)
      my $contact;
      if ($st eq "digitalInput.01") {
        # Single Input Contact, Batterie Monitor (EEP A5-30-01)
        # [Thermokon SR65 DI, untested]
        # $db[2] is the supply voltage, if >= 121 = battery ok
        # $db[1] is the input state, if <= 195 = contact closed
        my $battery = $db[2] >= 121 ? "ok" : "low";
        $contact = $db[1] <= 195 ? "closed" : "open";
        push @event, "3:battery:$battery";
      } else {
        # Single Input Contact (EEP A5-30-02)
        # $db[0]_bit_0 is the input state where 0 = closed, 1 = open
        $contact = $db[0] & 1 ? "open" : "closed";
      }
      push @event, "3:contact:$contact";
      push @event, "3:state:$contact";

    } elsif ($st eq "digitalInput.03") {
      # 4 digital inputs, wake, temperature (EEP A5-30-03)
      my $in0 = $db[1] & 1;
      my $in1 = ($db[1] & 2) > 1;
      my $in2 = ($db[1] & 4) > 2;
      my $in3 = ($db[1] & 8) > 3;
      my $wake = ($db[1] & 16) > 4;
      my $temperature = 40 - $db[2] * 40 / 255;
      push @event, "3:in0:$in0";
      push @event, "3:in1:$in1";
      push @event, "3:in2:$in2";
      push @event, "3:in3:$in3";
      push @event, "3:wake:$wake";
      push @event, "3:temperature:$temperature";
      push @event, "3:state:T: $temperature I: " . $in0 . $in1 . $in2 . $in3 . " W: " . $wake;
    
    } elsif ($st eq "digitalInput.04") {
      # 3 digital inputs, 1 digital input 8 bit (EEP A5-30-04)
      my $in0 = $db[0] & 1;
      my $in1 = ($db[0] & 2) > 1;
      my $in2 = ($db[0] & 4) > 2;
      my $in3 = $db[1];
      push @event, "3:in0:$in0";
      push @event, "3:in1:$in1";
      push @event, "3:in2:$in2";
      push @event, "3:in3:$in3";
      push @event, "3:state:" . $in0 . $in1 . $in2 . " " . $in3;
    
    } elsif ($st eq "gateway") {
      # Gateway (EEP A5-38-08)
      # $db[3] is the command ID ($gwCmdID)
      # Eltako devices not send teach-in telegrams
      if(($db[0] & 8) == 0) {
        # teach-in, identify and store command type in attr gwCmd
        my $gwCmd = AttrVal($name, "gwCmd", undef);
        if (!$gwCmd) {
          $gwCmd = $EnO_gwCmd[$db[3] - 1];
          $attr{$name}{gwCmd} = $gwCmd;
        }
      }
      if ($db[3] == 1) {
        # Switching
        # Eltako devices not send A5 telegrams
        push @event, "3:executeTime:" . sprintf "%0.1f", (($db[2] << 8) | $db[1]) / 10;
        push @event, "3:block:" . ($db[0] & 4 ? "lock" : "unlock");
        push @event, "3:executeType" . ($db[0] & 2 ? "delay" : "duration");
        push @event, "3:state:" . ($db[0] & 1 ? "on" : "off");
      } elsif ($db[3] == 2) {
        # Dimming
        # $db[0]_bit_2 is store final value, not used, because
        # dimming value is always stored
        push @event, "3:rampTime:$db[1]";
        push @event, "3:state:" . ($db[0] & 0x01 ? "on" : "off");
        if ($db[0] & 4) {
          # Relative Dimming Range
          push @event, "3:dim:" . sprintf "%d", $db[2] * 100 / 255;
        } else {
          push @event, "3:dim:$db[2]";
        }
        push @event, "3:dimValueLast:$db[2]" if ($db[2] > 0);
      } elsif ($db[3] == 3) {
        # Setpoint shift
        # $db1 is setpoint shift where 0 = -12.7 K ... 255 = 12.8 K
        my $setpointShift = sprintf "%0.1f", -12.7 + $db[1] / 10;
        push @event, "3:setpointShift:$setpointShift";
        push @event, "3:state:$setpointShift";
      } elsif ($db[3] == 4) {
        # Basic Setpoint
        # $db1 is setpoint where 0 = 0 �C ... 255 = 51.2 �C
        my $setpoint = sprintf "%0.1f", $db[1] / 5;
        push @event, "3:setpoint:$setpoint";
        push @event, "3:state:$setpoint";
      } elsif ($db[3] == 5) {
        # Control variable
        # $db1 is control variable override where 0 = 0 % ... 255 = 100 %
        push @event, "3:controlVar:" . sprintf "%d", $db[1] * 100 / 255;
        my $controllerMode = ($db[0] & 0x60) >> 5;
        if ($controllerMode == 0) {
          push @event, "3:controllerMode:auto";
          push @event, "3:state:auto";
        } elsif ($controllerMode == 1) {
          push @event, "3:controllerMode:heating";
          push @event, "3:state:heating";
        } elsif ($controllerMode == 2){
          push @event, "3:controllerMode:cooling";
          push @event, "3:state:cooling";
        } elsif ($controllerMode == 3){
          push @event, "3:controllerMode:off";
          push @event, "3:state:off";
        }
        push @event, "3:controllerState:" . ($db[0] & 0x10 ? "override" : "auto");
        push @event, "3:energyHoldOff:" . ($db[0] & 4 ? "holdoff" : "normal");
        my $occupancy = $db[0] & 3;
        if ($occupancy == 0) {
          push @event, "3:presence:present";
        } elsif ($occupancy == 1){
          push @event, "3:presence:absent";
        } elsif ($occupancy == 2){
          push @event, "3:presence:standby";
        }
      } elsif ($db[3] == 6) {
        # Fan stage
        if ($db[1] == 0) {
          push @event, "3:fan:0";
          push @event, "3:state:0";
        } elsif ($db[1] == 1) {
          push @event, "3:fan:1";
          push @event, "3:state:1";
        } elsif ($db[1] == 2) {
          push @event, "3:fan:2";
          push @event, "3:state:2";
        } elsif ($db[1] == 3) {
          push @event, "3:fan:3";
          push @event, "3:state:3";
        } elsif ($db[1] == 255) {
          push @event, "3:fan:auto";
          push @event, "3:state:auto";
        }
      } else {
        push @event, "3:state:Gateway Command ID $db[3] unknown.";
      }

    } elsif ($st eq "energyManagement.01") {
      # Energy Management, Demand Response
      # (A5-37-01)
      EnOcean_energyManagement_01Parse($hash, @db);

    } elsif ($st eq "manufProfile") {
      # Manufacturer Specific Applications (EEP A5-3F-7F)
      if ($manufID eq "002") {
        # [Thermokon SR65 3AI, untested]
        # $db[3] is the input 3 where 0x00 = 0 V ... 0xFF = 10 V
        # $db[2] is the input 2 where 0x00 = 0 V ... 0xFF = 10 V
        # $db[1] is the input 1 where 0x00 = 0 V ... 0xFF = 10 V
        my $input3 = sprintf "%0.2f", $db[3] * 10 / 255;
        my $input2 = sprintf "%0.2f", $db[2] * 10 / 255;
        my $input1 = sprintf "%0.2f", $db[1] * 10 / 255;
        push @event, "3:input1:$input1";
        push @event, "3:input2:$input2";
        push @event, "3:input3:$input3";
        push @event, "3:state:I1: $input1 I2: $input2 I3: $input3";
        
      } elsif ($manufID eq "005") {
        # omnio
        if ($db[0] == 0x0C) {
          # omnio UPH 2330/1x
          my $channel = ($db[1] & 0xF0) > 4;
          my $emergencyMode = $db[1] & 8 ? "on" : "off";
          my $window = $db[1] & 4 ? "open" : "closed";
          my $nightReduction = $db[1] & 2 ? "on" : "off";
          my $state = $db[1] & 1 ? "on" : "off";
          my $temperature = sprintf "%0.1f", $db[2] * 40 / 250;
          my $setpointTemp = sprintf "%0.1f", $db[3] * 40 / 250;
          push @event, "3:emergencyMode" . $channel . ":$emergencyMode";
          push @event, "3:window" . $channel . ":$window";
          push @event, "3:nightReduction" . $channel . ":$nightReduction";
          push @event, "3:temperature" . $channel . ":$temperature";
          push @event, "3:setpointTemp" . $channel . ":$setpointTemp";
          push @event, "3:state:$state";          
        }
      
      } elsif ($manufID eq "00D") {
        # [Eltako shutters, untested]
        my $angleMax = AttrVal($name, "angleMax", 90);
	my $angleMin = AttrVal($name, "angleMin", -90);
	my $anglePos = ReadingsVal($name, ".anglePosStart", undef);
	my $angleTime = AttrVal($name, "angleTime", 0);
	my $position = ReadingsVal($name, ".positionStart", undef);
        my $shutTime = AttrVal($name, "shutTime", 255);
        my $shutTimeStop = ($db[3] << 8 | $db[2]) * 0.1;
        my $state;
        $angleMax = 90 if ($angleMax !~ m/^[+-]?\d+$/);
        $angleMax = 180 if ($angleMax > 180);
        $angleMax = -180 if ($angleMax < -180);
        $angleMin = -90 if ($angleMin !~ m/^[+-]?\d+$/);
        $angleMin = 180 if ($angleMin > 180);
        $angleMin = -180 if ($angleMin < -180);
        ($angleMax, $angleMin) = ($angleMin, $angleMax) if ($angleMin > $angleMax);
        $angleMax ++ if ($angleMin == $angleMax);
        $angleTime = 0 if ($angleTime !~ m/^[+-]?\d+$/);
        $angleTime = 6 if ($angleTime > 6);
        $angleTime = 0 if ($angleTime < 0);
        $shutTime = 255 if ($shutTime !~ m/^[+-]?\d+$/);
        $shutTime = 255 if ($shutTime > 255);
        $shutTime = 1 if ($shutTime < 1);

        if ($db[0] == 0x0A) {
          push @event, "3:block:unlock";
        } elsif ($db[0] == 0x0E) {
          push @event, "3:block:lock";        
        }
        if (defined $position) {
          if ($db[1] == 1) {
            # up
            $position -= $shutTimeStop / $shutTime * 100;
            if ($angleTime) {
              $anglePos -= ($angleMax - $angleMin) * $shutTimeStop / $angleTime;
              if ($anglePos < $angleMin) {
                $anglePos = $angleMin;
              }
            } else {
              $anglePos = $angleMin;                
            }
            if ($position <= 0) {
              $anglePos = 0;
              $position = 0;
              push @event, "3:endPosition:open";
              $state = "open";
            } else {
              push @event, "3:endPosition:not_reached";
              $state = "stop";            
            }
            push @event, "3:anglePos:" . sprintf("%d", $anglePos);        
            push @event, "3:position:" . sprintf("%d", $position);        
          } elsif ($db[1] == 2) {
          # down
            $position += $shutTimeStop / $shutTime * 100;
            if ($angleTime) {              
              $anglePos += ($angleMax - $angleMin) * $shutTimeStop / $angleTime;              
              if ($anglePos > $angleMax) {
                $anglePos = $angleMax;
              }
            } else {
              $anglePos = $angleMax;                
            }
            if($position > 100) { 
              $anglePos = $angleMax;
              $position = 100;
              push @event, "3:endPosition:closed";
              $state = "closed";
            } else {
              push @event, "3:endPosition:not_reached";
              $state = "stop";            
            }
            push @event, "3:anglePos:" . sprintf("%d", $anglePos);        
            push @event, "3:position:" . sprintf("%d", $position);        
          } else {
            $state = "not_reached";
          }
        push @event, "3:state:$state";
        }
      
      } else {
        # Unknown Application
        push @event, "3:state:Manufacturer Specific Application unknown";
      }

    } elsif ($st eq "raw") {
      # raw
      push @event, "3:state:RORG: $rorg DATA: $data STATUS: $status ODATA: $odata";
    
    } else {
      # unknown devices
      push @event, "3:state:$db[3]";
      push @event, "3:sensor1:$db[3]";
      push @event, "3:sensor2:$db[2]";
      push @event, "3:sensor3:$db[1]";
      push @event, "3:D3:".(($db[0] & 8) ? 1:0);
      push @event, "3:D2:".(($db[0] & 4) ? 1:0);
      push @event, "3:D1:".(($db[0] & 2) ? 1:0);
      push @event, "3:D0:".(($db[0] & 1) ? 1:0);
    }

  } elsif ($rorg eq "D1") {
    # MSC telegram
    if ($st eq "actuator.01" && $manufID eq "033") {
      if (substr($data, 3, 1) == 4) {
        my $getParam = ReadingsVal($name, "getParam", 0);
        if ($getParam == 8) {
          push @event, "3:loadClassification:no";
          push @event, "3:loadLink:" . (($db[1] & 16) ? "connected":"disconnected");
          push @event, "3:loadOperation:3-wire";
          push @event, "3:loadState:" . (($db[1] & 64) ? "on":"off");
          CommandDeleteReading(undef, "$name getParam");        
        } elsif ($getParam == 7) {
          if ($db[0] & 4) {
            push @event, "3:devTempState:warning";
          } elsif ($db[0] & 2) {
            push @event, "3:devTempState:max";
          } else {
            push @event, "3:devTempState:ok";
          }
          push @event, "3:mainsPower:" . (($db[1] & 8) ? "failure":"ok");
          if ($db[1] == 0xFF) {
          push @event, "3:devTemp:invalid";
          } else {
          push @event, "3:devTemp:" . $db[1];
          }
          CommandDeleteReading(undef, "$name getParam");        
        } elsif ($getParam == 9) {
          push @event, "3:voltage:" . sprintf("%.2f", (hex(substr($data, 4, 4)) * 0.01));        
          CommandDeleteReading(undef, "$name getParam");        
        } elsif ($getParam == 0x81) {
          $hash->{READINGS}{serialNumber}{VAL} = substr($data, 4, 4);
          $hash->{READINGS}{getParam}{VAL} = 0x82;          
          EnOcean_SndRadio(undef, $hash, $packetType, "D1", "033182", AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});        
        } elsif ($getParam == 0x82) {
          push @event, "3:serialNumber:" . $hash->{READINGS}{serialNumber}{VAL} . substr($data, 4, 4);        
          CommandDeleteReading(undef, "$name getParam");        
        }
      }
 
    } elsif ($st eq "raw") {
      # raw
      push @event, "3:state:RORG: $rorg DATA: $data STATUS: $status ODATA: $odata";
      push @event, "3:manufID:" . substr($data, 0, 3);
      # display data bytes $db[0] ... $db[x]
      for (my $dbCntr = 0; $dbCntr <= $#db; $dbCntr++) {
        push @event, "3:DB_" . $dbCntr . ":" . $db[$dbCntr];
      }  
    } else {
      # unknown devices
      if(AttrVal($name, "blockUnknownMSC", "no") eq "yes") {
        push @event, "3:MSC:$data";
      }
    }
    
  } elsif ($rorg eq "D2") {
    # VLD telegram
    if ($st eq "test") {
      ### Test
      push @event, "3:state:RORG: $rorg DATA: $data STATUS: $status ODATA: $odata";
    
    } elsif ($st eq "actuator.01") {
      # Electronic switches and dimmers with Energy Measurement and Local Control
      # (D2-01-00 - D2-01-11)
      my $channel = (hex substr($data, 2, 2)) & 0x1F;
      if ($channel == 31) {$channel = "Input";}
      my $cmd = hex substr($data, 1, 1);

      if ($cmd == 4) {
        # actuator status response
        my $overCurrentOff;
        my $error;
        my $localControl;
        my $dim;
        push @event, "3:powerFailure" . $channel . ":" . 
                      (($db[2] & 0x80) ? "enabled":"disabled");
        push @event, "3:powerFailureDetection" . $channel . ":" .
                      (($db[2] & 0x40) ? "detected":"not_detected");
        if (($db[1] & 0x80) == 0) {
          $overCurrentOff = "ready";       
        } else {
          $overCurrentOff = "executed";
        }
        push @event, "3:overCurrentOff" . $channel . ":" . $overCurrentOff;
        if ((($db[1] & 0x60) >> 5) == 1) {
          $error = "warning";
        } elsif ((($db[1] & 0x60) >> 5) == 2) {
          $error = "failure";
        } elsif ((($db[1] & 0x60) >> 5) == 3) {
          $error = "not_supported";
        } else {
          $error = "ok";       
        }
        push @event, "3:error" . $channel . ":" . $error;
        if (($db[0] & 0x80) == 0) {
          $localControl = "disabled";       
        } else {
          $localControl = "enabled";
        }
        push @event, "3:localControl" . $channel . ":" . $localControl;
        my $dimValue = $db[0] & 0x7F;
        if ($dimValue == 0) {
          push @event, "3:channel" . $channel . ":off";
          push @event, "3:state:off";
        } else {
          push @event, "3:channel" . $channel . ":on";
          push @event, "3:state:on";
        }
        if ($channel ne "Input") {
          push @event, "3:dim:" . $dimValue;
          push @event, "3:dim" . $channel . ":" . $dimValue;
        } else {
          push @event, "3:dim" . $channel . ":" . $dimValue;
        }
      
      } elsif ($cmd == 7) {
        # actuator measurement response
        my $unit = $db[4] >> 5;
        if ($unit == 1) {
          #$unit = "Wh";
          $unit = "KWh";
          push @event, "3:energyUnit" . $channel . ":" . $unit;
          push @event, "3:energy" . $channel . ":" . sprintf("%.3f", (hex substr($data, 4, 8)) / 1000);
        } elsif ($unit == 2) {
          $unit = "KWh";
          push @event, "3:energyUnit" . $channel . ":" . $unit;
          push @event, "3:energy" . $channel . ":" . hex substr($data, 4, 8);
        } elsif ($unit == 3) {
          $unit = "W";
          push @event, "3:powerUnit" . $channel . ":" . $unit;
          push @event, "3:power" . $channel . ":" . hex substr($data, 4, 8);
        } elsif ($unit == 4) {
          $unit = "KW";
          push @event, "3:powerUnit" . $channel . ":" . $unit;
          push @event, "3:power" . $channel . ":" . hex substr($data, 4, 8);
        } else {
          $unit = "Ws";
          push @event, "3:engergyUnit" . $channel . ":" . $unit;
          push @event, "3:energy" . $channel . ":" . hex substr($data, 4, 8);
        }        
      
      } else {
        # unknown response
      }
      
    } elsif ($st eq "switch.00" || $st eq "windowHandle.10") {
      if ($db[0] == 1) {
        push @event, "3:state:open_from_tilted";      
      } elsif ($db[0] == 2) {
        push @event, "3:state:closed";      
      } elsif ($db[0] == 3) {
        push @event, "3:state:open";      
      } elsif ($db[0] == 4) {
        push @event, "3:state:tilted";      
      } elsif ($db[0] == 5) {
        push @event, "3:state:AI,B0";      
        push @event, "3:channelA:AI";      
        push @event, "3:channelB:B0";      
        push @event, "3:energyBow:pressed";      
      } elsif ($db[0] == 6) {
        CommandDeleteReading(undef, "$name channel.*");
        push @event, "3:state:pressed34";      
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 7) {
        push @event, "3:state:A0,B0";      
        push @event, "3:channelA:A0";      
        push @event, "3:channelB:B0";      
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 8) {
        if (AttrVal($name, "sensorMode", "switch") eq "pushbutton") {
          push @event, "3:state:pressed";      
        }
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 9) {
        push @event, "3:state:AI,BI";      
        push @event, "3:channelA:AI";      
        push @event, "3:channelB:BI";      
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 10) {
        push @event, "3:state:A0,BI";      
        push @event, "3:channelA:A0";      
        push @event, "3:channelB:BI";      
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 11) {
        push @event, "3:state:BI";      
        push @event, "3:channelB:BI";      
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 12) {
        push @event, "3:state:B0";      
        push @event, "3:channelB:B0";      
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 13) {
        push @event, "3:state:AI";      
        push @event, "3:channelA:AI";      
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 14) {
        push @event, "3:state:A0";      
        push @event, "3:channelA:A0";      
        push @event, "3:energyBow:pressed";
      } elsif ($db[0] == 15) {
        if (AttrVal($name, "sensorMode", "switch") eq "pushbutton") {
          push @event, "3:state:released";      
        }
        push @event, "3:energyBow:released";
      }
      
    } elsif ($st eq "blindsCtrl.00") {
      # EEP D2-05-00
      my $channel = ($db[0] & 0xF0) >> 4;
      my $cmd = $db[0] & 0x0F;
      if ($cmd == 4) {
        # actuator status response
        if ($db[3] == 0) {
          push @event, "3:state:open";
          push @event, "3:endPosition:open";
          push @event, "3:position:" . $db[3];
        } elsif ($db[3] == 100) {
          push @event, "3:state:closed";
          push @event, "3:endPosition:closed";
          push @event, "3:position:" . $db[3];       
        } elsif ($db[3] == 127) {
          push @event, "3:state:unknown";
          push @event, "3:endPosition:unknown";
          push @event, "3:position:unknown";
        } else {
          push @event, "3:state:" . $db[3];
          push @event, "3:endPosition:not_reached";
          push @event, "3:position:" . $db[3];
        }
        if ($db[2] == 127) {
          push @event, "3:anglePos:unknown";
        } else {
          push @event, "3:anglePos:" . $db[2];
        }
        if ($db[1] == 0) {
          push @event, "3:block:unlock";
        } elsif ($db[1] == 1) {
          push @event, "3:block:lock";       
        } elsif ($db[1] == 2) {
          push @event, "3:block:alarm";
        } else {
          push @event, "3:block:reserved";
        }
        
      } else {
        # unknown response
      }

    } elsif ($st eq "roomCtrlPanel.00") {
      # EEP D2-10-01 - D2-10-03
      my ($key, $val);
      # message identifier
      my $mid = hex(substr($data, 0, 2)) >> 5;
      # message continuation flag
      my $mcf = hex(substr($data, 0, 2)) & 3;
      my ($irc, $fbc, $gmt);

      if ($mcf == 0) {
        # message complete
        # read stored telegrams
        if (!defined($hash->{helper}{$mid}{messagePart})) {
          $hash->{helper}{$mid}{messagePart} = 1;
          $hash->{helper}{$mid}{data}{1} = $data;
        } else {
          $hash->{helper}{$mid}{messagePart} += 1;
          $hash->{helper}{$mid}{data}{$hash->{helper}{$mid}{messagePart}} = $data;
        }
        
        if ($mid == 4) {
          CommandDeleteAttr(undef, "$name timeProgram1");        
          CommandDeleteAttr(undef, "$name timeProgram2");        
          CommandDeleteAttr(undef, "$name timeProgram3");        
          CommandDeleteAttr(undef, "$name timeProgram4");        
        }

        for (my $partCntr = $hash->{helper}{$mid}{messagePart}; $partCntr > 0; $partCntr --) {
          $data = $hash->{helper}{$mid}{data}{$partCntr};        
          delete $hash->{helper}{$mid}{data}{$partCntr};
          if ($partCntr == 1) {
            delete $hash->{helper}{$mid}{messagePart};
          } else {
            $hash->{helper}{$mid}{messagePart} --;
          }
          $dbCntr = 0;
          for (my $strCntr = length($data) / 2 - 1; $strCntr >= 0; $strCntr --) {
            $db[$dbCntr] = hex substr($data, $strCntr * 2, 2);
            $dbCntr++;
          }
        
        #Log3 $name, 2, "EnOcean $name EnOcean_Parse write MID $mid DATA $data to part $partCntr";
        #Log3 $name, 2, "EnOcean $name EnOcean_Parse write 1 MID $mid DATA $data to " . sprintf "%02X%02X%02X%02X%02X%02X", $db[5], $db[4], $db[3], $db[2], $db[1], $db[0];
        
          if ($mid == 0) {
            # general message
            $irc = ($db[0] & 56) >> 3;
            $fbc = ($db[0] & 6) >> 1;
            $gmt = $db[0] & 1;
            #push @event, "3:general:$data";
        
          } elsif ($mid == 1) {
            # data message
            my $temperature = "-";
            $temperature = sprintf "%.1f", $db[0] / 254 * 40 if ($db[2] & 1);
            push @event, "3:temperature:$temperature";        
            my $setpointTemp = "-";
            $setpointTemp = sprintf "%.1f", $db[1] / 254 * 40 if ($db[2] & 2);
            push @event, "3:setpointTemp:$setpointTemp";        
            my $roomCtrlMode = ($db[2] & 12) >> 2;
            if ($roomCtrlMode == 3) {
              $roomCtrlMode = "buildingProtection";
            } elsif ($roomCtrlMode == 2) {
              $roomCtrlMode = "preComfort";
            } elsif ($roomCtrlMode == 1) {
              $roomCtrlMode = "economy";
            } else{
              $roomCtrlMode = "comfort";       
            }
            push @event, "3:roomCtrlMode:$roomCtrlMode";        
            my $heating = ($db[2] & 48) >> 4;
            if ($heating == 3) {
              $heating = "auto";
            } elsif ($heating == 2) {
              $heating = "off";
            } elsif ($heating == 1) {
              $heating = "on";
            } else{
              $heating = "-";       
            }
            if ($heating ne "-") {
              push @event, "3:heating:$heating";
            }
            my $cooling = ($db[2] & 192) >> 6;
            if ($cooling == 3) {
              $cooling = "auto";
            } elsif ($cooling == 2) {
              $cooling = "off";
            } elsif ($cooling == 1) {
              $cooling = "on";
            } else{
              $cooling = "-";       
            }
            if ($cooling ne "-") {
              push @event, "3:cooling:$cooling";
            }
            my $occupancy = $db[3] & 3;
            if ($occupancy == 3) {
              $occupancy = "reserved";
            } elsif ($occupancy == 2) {
              $occupancy = "absent";
            } elsif ($occupancy == 1) {
              $occupancy = "present";
            } else{
              $occupancy = "-";       
            }
            if ($occupancy eq "-") {
              $occupancy = ReadingsVal($name, "occupancy", "-")
            } else {
              push @event, "3:occupancy:$occupancy";
            }
            my $motion = ($db[3] & 12) >> 2;
            if ($motion == 3) {
              $motion = "reserved";
            } elsif ($motion == 2) {
              $motion = "on";
            } elsif ($motion == 1) {
              $motion = "off";
            } else{
              $motion = "-";       
            }
            if ($motion eq "-") {
              $motion = ReadingsVal($name, "motion", "-");
            } else {
              push @event, "3:motion:$motion";        
            }
            push @event, "3:solarPowered:" . ($db[3] & 16 ? "no" : "yes");        
            my $battery = ($db[3] & 96) >> 5;
            if ($battery == 3) {
              $battery = "empty";
            } elsif ($battery == 2) {
              $battery = "low";
            } elsif ($battery == 1) {
              $battery = "ok";
            } else{
              $battery = "-";       
            }
            if ($battery ne "-") {
              push @event, "3:battery:$battery";
            }
            my $window = $db[4] & 3;
            if ($window == 3) {
              $window = "reserved";
            } elsif ($window == 2) {
              $window = "open";
            } elsif ($window == 1) {
              $window = "closed";
            } else{
              $window = "-";       
            }
            if ($window ne "-") {
              push @event, "3:window:$window";
            }
            push @event, "3:moldWarning:" . ($db[4] & 4 ? "on" : "off");       
            push @event, "3:customWarning1:" . ($db[4] & 8 ? "on" : "off");        
            push @event, "3:customWarning2:" . ($db[4] & 16 ? "on" : "off");
            push @event, "3:fanSpeedMode:" . ($db[4] & 64 ? "local" : "central");
            my $fanSpeed = 0;
            $fanSpeed = sprintf "%d", $db[5] & 127 if ($db[4] & 128);
            push @event, "3:fanSpeed:$fanSpeed";
            my $humi = "-";
            $humi = sprintf "%d", $db[6] / 2.55 if ($db[5] & 128);
            push @event, "3:humidity:$humi";        
            push @event, "3:state:T: $temperature H: $humi F: $fanSpeed SPT: $setpointTemp O: $occupancy M: $motion";
      
          } elsif ($mid == 2) {
            # configuration message
            $attr{$name}{blockFanSpeed} = $db[6] & 1 ? "no" : "yes";
            $attr{$name}{blockSetpointTemp} = $db[6] & 2 ? "no" : "yes";
            $attr{$name}{blockOccupancy} = $db[6] & 4 ? "no" : "yes";
            $attr{$name}{blockTimeProgram} = $db[6] & 8 ? "no" : "yes";
            $attr{$name}{blockDateTime} = $db[6] & 16 ? "no" : "yes";
            $attr{$name}{blockDisplay} = $db[6] & 32 ? "no" : "yes";
            $attr{$name}{blockTemp} = $db[6] & 64 ? "no" : "yes";
            $attr{$name}{blockMotion} = $db[6] & 128 ? "no" : "yes";
            my $pollInterval = $db[5] >> 2;
            if ($pollInterval == 63) {
              $attr{$name}{pollInterval} = 1440;
            } elsif ($pollInterval == 62) {
              $attr{$name}{pollInterval} = 720;      
            } elsif ($pollInterval == 61) {
              $attr{$name}{pollInterval} = 180;
            } else {
              $attr{$name}{pollInterval} = $pollInterval;
            }
            $attr{$name}{blockKey} = $db[5] & 2 ? "no" : "yes";
            my $displayContent = $db[4] >> 5;
            my %displayContent = (7 => "humidity",
                                  6 => "off",
                                  5 => "setPointTemp",
                                  4 => "tempertureExtern",
                                  3 => "temperatureIntern",
                                  2 => "time",
                                  1 => "default",
                                  0 => "no_change"
                                 );
            while (($key, $val) = each(%displayContent)) {
              $attr{$name}{displayContent} = $val if ($key == $displayContent);
            }
            my $temperatureScale = ($db[4] & 24) >> 3;
            my %temperatureScale = (3 => "F",
                                    2 => "C",
                                    1 => "default",
                                    0 => "no_change"
                                   );
            while (($key, $val) = each(%temperatureScale)) {
              $attr{$name}{temperatureScale} = $val if ($key == $temperatureScale);
            }
            $attr{$name}{daylightSavingTime} = $db[4] & 4 ? "not_supported" : "supported";
            my $timeNotation = $db[4] & 3;
            if ($timeNotation == 0) {
              $attr{$name}{timeNotation} = "no_change";
            } elsif ($timeNotation == 1) {
              $attr{$name}{timeNotation} = "default";
            } elsif ($timeNotation == 2) {
              $attr{$name}{timeNotation} = 24;
            } elsif ($timeNotation == 3) {
              $attr{$name}{timeNotation} = 12;
            }
            CommandSave(undef, undef);
       
          } elsif ($mid == 3) {
            # room control setup
            my $setpointComfort = "-";
            $setpointComfort = sprintf "%.1f", $db[1] / 254 * 40 if ($db[0] & 1);
            push @event, "3:setpointComfortTemp:$setpointComfort";        
            my $setpointEconomy = "-";
            $setpointEconomy = sprintf "%.1f", $db[2] / 254 * 40 if ($db[0] & 2);
            push @event, "3:setpointEconomyTemp:$setpointEconomy";        
            my $setpointPreComfort = "-";
            $setpointPreComfort = sprintf "%.1f", $db[3] / 254 * 40 if ($db[0] & 4);
            push @event, "3:setpointPreComfortTemp:$setpointPreComfort";        
            my $setpointBuildingProtection = "-";
            $setpointBuildingProtection = sprintf "%.1f", $db[3] / 254 * 40 if ($db[0] & 8);
            push @event, "3:setpointBuildingProtectionTemp:$setpointBuildingProtection";        
      
          } elsif ($mid == 4) {
            # time program setup
            my $timeProgram = "timeProgram" . $partCntr; 
            my $period = $db[0] >> 4;
            my $periodVal = "";
            my %period = (15 => "FrMo",
                          14 => "FrSu",
                          13 => "ThFr",
                          12 => "WeFr",
                          11 => "TuTh",
                          10 => "MoWe",
                           9 => "Su",
                           8 => "Sa",
                           7 => "Fr",
                           6 => "Th",
                           5 => "We",
                           4 => "Tu",
                           3 => "Mo",
                           2 => "SaSu",
                           1 => "MoFr",
                           0 => "MoSu"
                          );
            while (($key, $val) = each(%period)) {
              $periodVal = $val if ($key == $period);
            }
            my $roomCtrlMode = ($db[0] & 12) >> 2;
            if ($roomCtrlMode == 3) {
              $roomCtrlMode = "buildingProtection";
            } elsif ($roomCtrlMode == 2) {
              $roomCtrlMode = "preComfort";
            } elsif ($roomCtrlMode == 1) {
              $roomCtrlMode = "economy";
            } else{
              $roomCtrlMode = "comfort";       
            }
            my ($startHour, $startMinute, $endHour, $endMinute) = ($db[1], $db[2], $db[3], $db[4]);
            $startHour = $startHour < 10 ? $startHour = "0" . $startHour : $startHour;
            $startMinute = $startMinute < 10 ? $startMinute = "0" . $startMinute : $startMinute;
            $endHour = $endHour < 10 ? $endHour = "0" . $endHour : $endHour;
            $endMinute = $endMinute < 10 ? $endMinute = "0" . $endMinute : $endMinute;

          #Log3 $name, 2, "EnOcean $name EnOcean_Parse write 2 MID $mid DATA $data to " . sprintf "%02X%02X%02X%02X%02X%02X", $db[5], $db[4], $db[3], $db[2], $db[1], $db[0];
          #Log3 $name, 2, "EnOcean $name EnOcean_Parse write 3 MID $mid DATA $data to $timeProgram VAL: $periodVal $startHour:$startMinute $endHour:$endMinute $roomCtrlMode";

            $attr{$name}{$timeProgram} = "$periodVal $startHour:$startMinute $endHour:$endMinute $roomCtrlMode";        

          #Log3 $name, 2, "EnOcean $name EnOcean_Parse write 4 MID $mid DATA $data to $timeProgram VAL: $attr{$name}{$timeProgram}";

            CommandSave(undef, undef);
          }
        }
        ($err, $response) = EnOcean_roomCtrlPanel_00Snd(undef, $hash, $packetType, $mid, $mcf, $irc, $fbc, $gmt);

      } elsif ($mcf == 1) {
        # message incomplete
        if (!defined($hash->{helper}{$mid}{messagePart})) {
          $hash->{helper}{$mid}{messagePart} = 1;
        } elsif ($hash->{helper}{$mid}{messagePart} >= 4) {
          # max 4 message parts stored
          for (my $partCntr = 1; $partCntr < $hash->{helper}{$mid}{messagePart}; $partCntr ++) {
            $hash->{helper}{$mid}{data}{$partCntr} = $hash->{helper}{$mid}{data}{$partCntr + 1};
          }
        } else {
          $hash->{helper}{$mid}{messagePart} += 1;
        }
        $hash->{helper}{$mid}{data}{$hash->{helper}{$mid}{messagePart}} = $data;
        #Log3 $name, 2, "EnOcean $name EnOcean_Parse store MID $mid DATA $data to messagePart $hash->{helper}{$mid}{messagePart}";
        ($err, $response) = EnOcean_roomCtrlPanel_00Snd(undef, $hash, $packetType, $mid, $mcf, undef, undef, undef);        
      }

    } elsif ($st eq "fanCtrl.00") {
      # Fan Control
      # (D2-20-00 - D2-20-02)
      if ($db[3] & 1) {
        # fan status message
        my $fanSpeed = $db[0];
        my $humidity = $db[1];
        my $roomSize = $db[2] & 15;
        my $roomSizeRef = ($db[2] & 0x30) >> 4;
        my $humidityCtrl = ($db[2] & 0xC0) >> 6;
        my $serviceInfo = ($db[3] & 14) >> 1;
        my $opMode = ($db[3] & 0xF0) >> 4;
        my %roomSizeTbl = (
           0 => 25,
           1 => 50,
           2 => 75,
           3 => 100,
           4 => 125,
           5 => 150,
           6 => 175,
           7 => 200,
           8 => 225,
           9 => 250,
          10 => 275,
          11 => 300,
          12 => 325,
          13 => 350,
          14 => "max",
          15 => "no_change"          
        );
        if ($opMode == 0) {
          push @event, "3:state:off";
        } elsif ($opMode == 1) {
          push @event, "3:state:on";
        } elsif ($opMode == 15) {
          push @event, "3:state:not_supported";
        }
        if ($serviceInfo == 0) {
          push @event, "3:error:ok";
        } elsif ($serviceInfo == 1) {
          push @event, "3:error:air_filter";
        } elsif ($serviceInfo == 2) {
          push @event, "3:error:hardware";
        } elsif ($serviceInfo == 7) {
          push @event, "3:error:not_supported";
        }
        if ($humidityCtrl == 0) {
          push @event, "3:humidityCtrl:disabled";
        } elsif ($humidityCtrl == 1) {
          push @event, "3:humidityCtrl:enabled";
        } elsif ($humidityCtrl == 3) {
          push @event, "3:humidityCtrl:not_supported";
        }
        if ($roomSizeRef == 0) {
          push @event, "3:roomSizeRef:used";
        } elsif ($roomSizeRef == 1) {
          push @event, "3:roomSizeRef:not_used";
        } elsif ($roomSizeRef == 3) {
          push @event, "3:roomSizeRef:not_supported";
        }
        if ($roomSize < 15) {
          push @event, "3:roomSize:" . $roomSizeTbl{$roomSize};
        }
        if ($humidity >= 0 && $humidity <= 100) {
          push @event, "3:humidity:$humidity";
        } elsif ($humidity == 255) {
          push @event, "3:humidity:not_supported";
        }
        if ($fanSpeed >= 0 && $fanSpeed <= 100) {
          push @event, "3:fanSpeed:$fanSpeed";
        } elsif ($fanSpeed == 255) {
          push @event, "3:fanSpeed:not_supported";
        }
      }

    } elsif ($st eq "valveCtrl.00") {
      # Valve Control
      # (D2-A0-01)
      $db[0] &= 3;
      if (AttrVal($name, "devMode", "master") eq "slave") {
        # devMode slave
        if ($db[0] == 1 || $db[0] == 3) {
          push @event, "3:state:closes";
        } elsif ($db[0] == 2) {
          push @event, "3:state:opens";
        } elsif ($db[0] == 0) {
          my $state = ReadingsVal($name, "state", "-");
          if ($state eq "closed" || $state eq "closes") {
            $state = "01";
          } elsif ($state eq "open" || $state eq "opens") {
            $state = "02";        
          } else {
            $state = "00";        
          }
          EnOcean_SndRadio(undef, $hash, 1, "D2", $state, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});      
        } 
      } else {
        #devMode master
        if ($db[0] == 1) {
          push @event, "3:state:closed";
        } elsif ($db[0] == 2) {
          push @event, "3:state:open";
        } elsif ($db[0] == 0 || $db[0] == 3) {
          push @event, "3:state:-";
        }
      }

    } elsif ($st eq "raw") {
      # raw
      push @event, "3:state:RORG: $rorg DATA: $data STATUS: $status ODATA: $odata";    
      # display data bytes $db[0] ... $db[x]
      for (my $dbCntr = 0; $dbCntr <= $#db; $dbCntr++) {
        push @event, "3:DB_" . $dbCntr . ":" . $db[$dbCntr];
      }    
    } else {
      # unknown devices
      push @event, "3:state:$data";
    }
  
  } elsif ($rorg eq "B2") {
    # GP complete data (GPCD)
    #
    my $channelName = "channelI0";
    my ($header, $channel, $channelParam) = (1, 0, AttrVal($name, $channelName, undef));
    my ($channelType, $signalType, $valType);
    $data = unpack('B*', hex $data);
    while (defined $channelParam) {
      ($err, $response, $channelType, $signalType, $valType ,$data) = EnOcean_GPCalcInboundVal($channelName, $data);
      $channel ++;
      $channelName = "channelI" . $channel;
      $channelParam = AttrVal($name, $channelName, undef);
    }

  } elsif ($rorg eq "B3") {
    # GP selective data (GPSD)
    #
    #my $dataBits = unpack('B*', hex $data);
    #$dataBits =~ m/^(....)(......)(.*)$/;
    #my $header = pack('B4', $1);
    #my $channel = pack('B6', $2);
    #$dataBits = $3;
    my ($header, $channel);
    ($header, $channel, $data) = pack('B4B6B*', unpack('B*', hex $data));
    push @event, "3:header:$header";
    push @event, "3:channel:$channel";
    push @event, "3:data:$data";
    

  } elsif ($rorg eq "B0" && $teach) {
    # GP teach in request
    #
    $data =~ m/^(....)(.*)$/;
    my $header = hex($1);
    $data = $2;
    my $purpose = ($header & 12) >> 2;
    if ($purpose == 0 || ($purpose == 2 && AttrVal($name, "subType", "") ne "GP")) {
      # teach-in request
      $attr{$name}{comMode} = $header & 16 ? "biDir" : "uniDir";
      $attr{$name}{manufID} = sprintf "%03X", ($header & 0xFFE0) >> 5;
      $attr{$name}{subType} = "GP";
      my $channel = 0;
      my $channelDir = "I";
      my $channelName;
      my $channelType;
      my $dataOutboundDefLen = 0;
      my $dataPart1;
      my $dataPart2;
      my $signalType;      
      while (length($data) > 0) {      
        $data =~ m/^(...)(.*)$/;
        $dataPart1 = $1;
        $dataPart2 = $2;
        $channelName = "channel" . $channelDir . $channel;
        $channelType = (hex($dataPart1) & 0xC00) >> 10;
        $signalType = (hex($dataPart1) & 0x3FC) >> 2;
        if ($channelType == 0) {
          # teach-in information
          if ($signalType == 1) {
            # outbound channel description
            # 2 LSB '00' added
            $data =~ m/^(....)(.)(.*)$/;
            $dataOutboundDefLen = (hex($1 . $2) & 0x3FC) >> 2;
            $channelDir = "O";
            $data = pack('H*', unpack('B4', hex($2) & 3) . unpack('B*', hex($3)) . "00");
            
          } elsif ($signalType == 2) {
            # produkt ID
            # 2 LSB '00' added
            $data =~ m/^(..)(.)(.*)$/;
            $data = pack('H*', unpack('B4', hex($2) & 3) . unpack('B*', hex($3)) . "00");
            $data =~ m/^(........)(.*)$/;
            $attr{$name}{productID} = $1;
            $data = $2;
          }
          
        } elsif ($channelType == 1) {
          # data
          $data =~ m/^(..........)(.*)$/;
          $attr{$name}{$channelName} = $1;
          $data = $2;
          $channel ++;
          
        } elsif ($channelType == 2) {
          # flag
          $attr{$name}{$channelName} = $dataPart1;
          $data = $dataPart2;
          $channel ++;
          
        } elsif ($channelType == 3) {
          # enumeration
          $data =~ m/^(....)(.*)$/;
          $attr{$name}{$channelName} = $1;
          $data = $2;
          $channel ++;
        } 
      }

      if (AttrVal($name, "comMode", "uniDir") eq "biDir") {
        # send GP Teach-In Response message
        ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", "biDir");
        $data = sprintf "%04X", (hex(AttrVal($name, "manufID", "7FF")) << 5) | 8;
        EnOcean_SndCDM(undef, $hash, $packetType, "B1", $data, $subDef, "00", $id);
        Log3 $name, 2, "EnOcean $name GP teach-in response send to $id";
      }
      Log3 $name, 2, "EnOcean $name GP teach-in EEP Manufacturer: " . $attr{$name}{manufID};
      # store attr subType, manufID ...
      CommandSave(undef, undef);          
      
    } elsif ($purpose == 1 || ($purpose == 2 && AttrVal($name, "subType", "") eq "GP")) {
      # teach-in deletion dequest
      $deleteDevice = $name;
      if (AttrVal($name, "comMode", "uniDir") eq "biDir") {
        # send GP Teach-In Deletion Response message
        $data = sprintf "%04X", (hex(AttrVal($name, "manufID", "7FF")) << 5) | 16;
        EnOcean_SndCDM(undef, $hash, $packetType, "B1", $data, AttrVal($name, "subDef", "00000000"), "00", $id);
        Log3 $name, 2, "EnOcean $name GP teach-in deletion response send to $id";
      }
      Log3 $name, 2, "EnOcean $name GP teach-in delete request executed";
      
    }

  } elsif ($rorg eq "B1" && $teach) {
    # GP teach in response
    # 

  } elsif ($rorg eq "D4" && $teach) {
    # UTE - Universal Uni- and Bidirectional Teach-In / Teach-Out
    # 
    my $rorg = sprintf "%02X", $db[0];
    my $func = sprintf "%02X", $db[1];
    my $type = sprintf "%02X", $db[2];
    my $mid = sprintf "%03X", ((($db[3] & 7) << 8) | $db[4]);
    #my $devChannel = sprintf "%02X", $db[5];
    my $devChannel = $db[5];
    my $comMode = $db[6] & 0x80 ? "biDir" : "uniDir";
    my $subType = "$rorg.$func.$type";
    if (($db[6] & 1) == 0) {
      # Teach-In Query telegram received
      my $teachInReq = ($db[6] & 0x30) >> 4;
      if ($teachInReq == 0 || $teachInReq == 2) {
      # Teach-In Request
        if($EnO_eepConfig{$subType}) {
          # EEP Teach-In
          foreach my $attrCntr (keys %{$EnO_eepConfig{$subType}{attr}}) {
            $attr{$name}{$attrCntr} = $EnO_eepConfig{$subType}{attr}{$attrCntr};
          }
          $subType = $EnO_eepConfig{$subType}{attr}{subType};
          #$attr{$name}{subType} = $subType;
          $attr{$name}{manufID} = $mid;
          $attr{$name}{devChannel} = $devChannel;
          $attr{$name}{comMode} = $comMode;
          $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
          $attr{$name}{eep} = "$rorg-$func-$type";
          push @event, "3:teach-in:EEP $rorg-$func-$type Manufacturer: $mid";
          if (!($db[6] & 0x40)) {
            # UTE Teach-In-Response expected
            # send UTE Teach-In Response message
            $data = (sprintf "%02X", $db[6] & 0x80 | 0x11) . substr($data, 2, 12);
            if ($comMode eq "biDir") {
              ($err, $subDef) = EnOcean_AssignSenderID(undef, $hash, "subDef", $comMode);
            } else {
              $subDef = "00000000";
            }
            EnOcean_SndRadio(undef, $hash, $packetType, "D4", $data, $subDef, "00", $id);
            Log3 $name, 2, "EnOcean $name UTE teach-in response send to $id";
          }
          Log3 $name, 2, "EnOcean $name UTE teach-in EEP $rorg-$func-$type Manufacturer: $mid";
          # store attr subType, manufID ...
          CommandSave(undef, undef);          
        } else {
          # EEP type not supported
          $attr{$name}{subType} = "raw";
          $attr{$name}{manufID} = $mid;
          $attr{$name}{devChannel} = $devChannel;
          $attr{$name}{comMode} = $comMode;
          $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
          push @event, "3:teach-in:EEP $rorg-$func-$type Manufacturer: $mid not supported";          
          # send EEP Teach-In Response message
          if (!($db[6] & 0x40)) {
            # UTE Teach-In-Response expected
	    # send UTE Teach-In Response message
            $data = (sprintf "%02X", $db[6] & 0x80 | 0x31) . substr($data, 2, 12);
            EnOcean_SndRadio(undef, $hash, $packetType, "D4", $data, "00000000", "00", $id);        
          }
          Log3 $name, 2, "EnOcean $name EEP $rorg-$func-$type not supported";
          # store attr subType, manufID ...
          CommandSave(undef, undef);          
        }
      } elsif ($teachInReq == 1) {
        # Teach-In Deletion Request
        $deleteDevice = $name;
        if (!($db[6] & 0x40)) {
          # UTE Teach-In Deletion Response expected
          # send UTE Teach-In Deletion Response message
          $data = (sprintf "%02X", $db[6] & 0x80 | 0x21) . substr($data, 2, 12);
          EnOcean_SndRadio(undef, $hash, $packetType, "D4", $data, AttrVal($name, "subDef", "00000000"), "00", $id);
          Log3 $name, 2, "EnOcean $name UTE teach-in deletion response send to $id";
        }
        Log3 $name, 2, "EnOcean $name UTE teach-in delete request executed";        
      }      
    } else {
      # Teach-In Respose telegram received
      #my $IODev = $iohash->{NAME};
      my $teachInAccepted = ($db[6] & 0x30) >> 4;
      my $IODev = $defs{$name}{IODev}{NAME};
      my $IOHash = $defs{$IODev};
      Log3 $name, 2, "EnOcean $name UTE teach-in response message to $destinationID received";
      
      if (exists $IOHash->{helper}{UTERespWait}{$destinationID}) {
        my $destinationHash = $IOHash->{helper}{UTERespWait}{$destinationID}{hash};
        my $destinationName = $destinationHash->{NAME};
        if ($comMode eq "uniDir") {
          $attr{$destinationName}{manufID} = $mid;
          if ($teachInAccepted == 0) {
            $teachInAccepted = "request not accepted";
          } elsif ($teachInAccepted == 1){
            $teachInAccepted = "teach-in accepted";
          } elsif ($teachInAccepted == 2){
            $teachInAccepted = "teach-out accepted";
          } else {
            $teachInAccepted = "EEP not supported";
          }
          $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
          readingsSingleUpdate($destinationHash, "teach-in", "EEP $rorg-$func-$type Manufacturer: $mid UTE $teachInAccepted", 1);
          #$deleteDevice = $name;
        } else {
          if ($IOHash->{helper}{UTERespWait}{$destinationID}{teachInReq} eq "in") {
            # Teach-In Request
            if ($teachInAccepted == 0) {
              $teachInAccepted = "request not accepted";
            } elsif ($teachInAccepted == 1){
              $teachInAccepted = "teach-in accepted";
              $attr{$destinationName}{subDef} = $destinationHash->{DEF};
              $attr{$destinationName}{manufID} = $mid;
              ($destinationHash->{DEF}, $hash->{DEF}) = ($hash->{DEF}, $destinationHash->{DEF});
              #$deleteDevice = $name;
            } elsif ($teachInAccepted == 2){
              $teachInAccepted = "teach-out accepted";
            } else {
              $teachInAccepted = "EEP not supported";
            }
            $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
            readingsSingleUpdate($destinationHash, "teach-in", "EEP $rorg-$func-$type Manufacturer: $mid UTE $teachInAccepted", 1);
            
          } elsif ($IOHash->{helper}{UTERespWait}{$destinationID}{teachInReq} eq "out") {
            # Teach-In Deletion Request
            if ($teachInAccepted == 0) {
              $teachInAccepted = "request not accepted";
            } elsif ($teachInAccepted == 1){
              $teachInAccepted = "teach-in accepted";
            } elsif ($teachInAccepted == 2){
              $teachInAccepted = "teach-out accepted";
              if (defined $attr{$destinationName}{subDef}) {
                $destinationHash->{DEF} = $attr{$destinationName}{subDef};
                delete $attr{$destinationName}{subDef};            
              }
            } else {
              $teachInAccepted = "EEP not supported";
            }
            $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
            readingsSingleUpdate($destinationHash, "teach-in", "EEP $rorg-$func-$type Manufacturer: $mid UTE $teachInAccepted", 1);
          }
        }
        # clear teach-in request
        delete $IOHash->{helper}{UTERespWait}{$destinationID};
        # set flag for delete the temporary teach-in device
        $IOHash->{helper}{UTERespWaitDel}{$destinationName} = 1;

      } else {
        # teach-in request unknown, delete response device, no action
        #$deleteDevice = $name;
      }
    }
    
  } elsif ($rorg eq "35" && $teach) {
    # Secure Teach-In
    ($err, $msg) = EnOcean_sec_parseTeachIn($hash, $data, $subDef, $destinationID);
    if (defined $err) {
      Log3 $name, 2, "EnOcean $name secure teach-in ERROR: $err"; 
      return "";
    }
    Log3 $name, 3, "EnOcean $name secure teach-in $msg";    
    CommandSave(undef, undef);
    return "";
    
  } elsif ($rorg eq "C5" && $packetType == 1) {
    # remote management
    ###
    $data =~ m/^(..)(.*)$/;
    my $seq = (hex($1) & 192) >> 6;
    my $idx = hex($1) & 63;
    $data = $2;
    # save telegrams of the message
    if ($idx == 0) {
      $data =~ m/^(........)(........)$/;
      delete $hash->{helper}{sysEx}{$seq};
      $hash->{helper}{sysEx}{$seq}{dataLength} = (hex($1) & 0xFF800000) >> 23;
      $hash->{helper}{sysEx}{$seq}{dataLengthCntr} = 4;
      $hash->{helper}{sysEx}{$seq}{manufID} = (hex($1) & 0x7FF000) >> 12;
      $hash->{helper}{sysEx}{$seq}{fnNumber} = (hex($1) & 0xFFF);
      $hash->{helper}{sysEx}{$seq}{data}{$idx} = $2;  
    } else {
      if (defined $hash->{helper}{sysEx}{data}{$idx}) {
        # receiving error > delete all massage parts
        Log3 $name, 2, "EnOcean $name RMCC/RPC message SEQ: " . $hash->{helper}{sysEx}{$seq} . " wrong.";
        delete $hash->{helper}{sysEx}{$seq};
      } else {
        $hash->{helper}{sysEx}{$seq}{dataLengthCntr} += 8;
        $hash->{helper}{sysEx}{$seq}{data}{$idx} = $data;
      }
    }
    # merge telegrams and decode messsage 
    if (defined($hash->{helper}{sysEx}{$seq}{dataLength}) &&
        $hash->{helper}{sysEx}{$seq}{dataLengthCntr} >= $hash->{helper}{sysEx}{$seq}{dataLength}) {
      $data = undef;
      for (my $cntr = 0; $cntr < int($hash->{helper}{sysEx}{$seq}{dataLength} / 8) + 1; $cntr++) {
        $data .= $hash->{helper}{sysEx}{$seq}{data}{$cntr};
      }
      $data = substr($data, 0, $hash->{helper}{sysEx}{$seq}{dataLength} * 2);

      if ($hash->{helper}{sysEx}{$seq}{fnNumber} == 0x604 || $hash->{helper}{sysEx}{$seq}{fnNumber} == 0x606) {
        # query ID answer, Ping answer
        my $eep = hex(substr($data, 0, 6)) >> 3;
        my $rorg = sprintf "%02X", ($eep >> 13);
        my $func = sprintf "%02X", (($eep & 0x1F80) >> 7);
        my $type = sprintf "%02X", ($eep & 127);
        my $mid = $hash->{helper}{sysEx}{$seq}{manufID};
        $attr{$name}{manufID} = $mid;
        $mid = $EnO_manuf{$mid} if($EnO_manuf{$mid});
        $attr{$name}{eep} = "$rorg-$func-$type";
        my $subType = "$rorg.$func.$type";
        $attr{$name}{subType} = $EnO_eepConfig{$subType}{attr}{subType} if($EnO_manuf{$subType});
        if ($hash->{helper}{sysEx}{$seq}{fnNumber} == 0x606) {
          $hash->{RSSI} = - substr($data, 6, 2);
        }
        push @event, "3:teach-in:EEP $rorg-$func-$type Manufacturer: $mid";
        Log3 $name, 2, "EnOcean $name RMCC Answer EEP $rorg-$func-$type Manufacturer: $mid";
        CommandSave(undef, undef);
     
      } elsif ($hash->{helper}{sysEx}{$seq}{fnNumber} == 0x607) {
        # functions list answer
        my ($fnList, $mid);
        for (my $cntr = 0; $cntr < $hash->{helper}{sysEx}{$seq}{dataLength} / 4; $cntr++) {
          $fnNumber = substr($data, $cntr * 4, 2);
          $mid = sprintf "%02X", substr($data, $cntr * 4 + 4, 2);
          $fnList .= "$fnNumber:$mid "; 
        }
        chop($fnList);
        push @event, "3:remoteFunct:$fnList";
        Log3 $name, 2, "EnOcean $name RMCC Answer Remote Functions: $fnList";
        
      } elsif ($hash->{helper}{sysEx}{$seq}{fnNumber} == 0x608) {
        # last function
        $data =~ m/^(.)(.)(.)(...)(..)$/;
        my $codeSetFlag = $1 >> 3;
        my $seqLast = $2;
        my $fnNumberLast = $4;
        my $fnRetCode = $5;
        Log3 $name, 2, "EnOcean $name RMCC Answer Status: Code Set Flag: $codeSetFlag 
                        SEQ: $seqLast Function Number: $fnNumberLast Return Code $fnRetCode";    
      } else {
        Log3 $name, 2, "EnOcean $name RMCC/RPC Function Number " .
                        sprintf ("%04X", $hash->{helper}{sysEx}{$seq}{fnNumber}) . " not supported.";      
      }
      delete $hash->{helper}{sysEx}{$seq};
    }
  } elsif ($packetType == 7) {
    if ($fnNumber == 1) {
      Log3 $name, 2, "EnOcean $name RMCC Unlock Request with ManufacturerID: $manufID";
      
    } elsif ($fnNumber == 2) {
      Log3 $name, 2, "EnOcean $name RMCC Lock Request with ManufacturerID: $manufID";
    
    } elsif ($fnNumber == 3) {
      Log3 $name, 2, "EnOcean $name RMCC Set code Request with ManufacturerID: $manufID";
    
    } elsif ($fnNumber == 4) {
      my $eep = hex(substr($data, 0, 6)) >> 3;
      my $rorg = sprintf "%02X", ($eep >> 13);
      my $func = sprintf "%02X", (($eep & 0x1F80) >> 7);
      my $type = sprintf "%02X", ($eep & 127);
      Log3 $name, 2, "EnOcean $name RMCC Query ID with EEP $rorg-$func-$type ManufacturerID: $manufID";
    
    } elsif ($fnNumber == 5) {
      Log3 $name, 2, "EnOcean $name RMCC Action Request with ManufacturerID: $manufID";
    
    } elsif ($fnNumber == 6) {
      Log3 $name, 2, "EnOcean $name RMCC Ping Request with ManufacturerID: $manufID";
    
    } elsif ($fnNumber == 7) {
      Log3 $name, 2, "EnOcean $name RMCC Query remote functions with ManufacturerID: $manufID";
    
    } elsif ($fnNumber == 8) {
      Log3 $name, 2, "EnOcean $name RMCC Query status with ManufacturerID: $manufID";
    
    } elsif ($fnNumber == 0x201) {
      $data =~ m/^(..)(..)(..)(..)$/;
      my ($rorg, $func, $type, $flag) = ($1, $2, $3, hex($4));
      Log3 $name, 2, "EnOcean $name RPC Remote Learn with EEP $rorg-$func-$type ManufacturerID: $manufID Flag: $flag";
    
    } elsif ($fnNumber == 0x604 || $fnNumber == 0x606) {
      my $eep = hex(substr($data, 0, 6)) >> 3;
      my $rorg = sprintf "%02X", ($eep >> 13);
      my $func = sprintf "%02X", (($eep & 0x1F80) >> 7);
      my $type = sprintf "%02X", ($eep & 127);
      $attr{$name}{manufID} = $manufID;
      $manufID = $EnO_manuf{$manufID} if($EnO_manuf{$manufID});
      $attr{$name}{eep} = "$rorg-$func-$type";
      my $subType = "$rorg.$func.$type";
      $attr{$name}{subType} = $EnO_eepConfig{$subType}{attr}{subType} if($EnO_manuf{$subType});
      if ($fnNumber == 0x606) {
        $hash->{RSSI} = - substr($data, 6, 2);
      }
      push @event, "3:teach-in:EEP $rorg-$func-$type Manufacturer: $manufID";
      Log3 $name, 2, "EnOcean $name RMCC Answer EEP $rorg-$func-$type Manufacturer: $manufID";
      CommandSave(undef, undef);

    } else {    
      Log3 $name, 2, "EnOcean $name RMCC/RPC Function Number " . sprintf("%04X", $fnNumber) . " not supported.";
    }
  }

  readingsBeginUpdate($hash);
  for(my $i = 0; $i < int(@event); $i++) {
    # Flag & 1: reading, Flag & 2: changed. Currently ignored.
    my ($flag, $vn, $vv) = split(":", $event[$i], 3);
    readingsBulkUpdate($hash, $vn, $vv);
    my @cmdObserve = ($name, $vn, $vv);
    EnOcean_observeParse(2, $hash, @cmdObserve);      
  }
  readingsEndUpdate($hash, 1);
  
  if (defined $deleteDevice) {
    # delete device and save config 
    CommandDelete(undef, $deleteDevice);
    CommandDelete(undef, "FileLog_" . $deleteDevice);
    if (defined $oldDevice) {
      Log3 $name, 2, "EnOcean $name renamed $oldDevice to $deleteDevice";
      CommandRename(undef, "$oldDevice $deleteDevice");
      CommandSave(undef, undef);
      return $deleteDevice;    
    } else {
      CommandSave(undef, undef);
      return "";
    }
  }
  #readingsSingleUpdate($hash, "log", "parse_end", 1);
  return $name;
}

sub EnOcean_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};
  # return if attribute list is incomplete
  return undef if (!$init_done);
  my $waitingCmds = AttrVal($name, "waitingCmds", 0);
  
  if ($attrName eq "angleTime") {
    my $data;
    if (!defined $attrVal) {
      if (AttrVal($name, "subType", "") eq "blindsCtrl.00") {
        # no rotation
        $data = "7FFF000705";
        EnOcean_SndRadio(undef, $hash, 1, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
      }
    } elsif (AttrVal($name, "subType", "") eq "blindsCtrl.00" && $attrVal =~ m/^[+-]?\d+(\.\d+)?$/ && $attrVal >= 0 && $attrVal <= 2.54) {
      if ($attrVal < 1) {
        $attrVal = 0;
      } else {
        $attrVal = int($attrVal * 10);
      } 
      $data = sprintf "7FFF%02X0705", $attrVal;        
      #EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, $subDef, $status, $destinationID);
      EnOcean_SndRadio(undef, $hash, 1, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});   
    } elsif (AttrVal($name, "subType", "") eq "manufProfile" && AttrVal($name, "manufID", "") eq "00D" &&
             $attrVal =~ m/^[+-]?\d+?$/ && $attrVal >= 1 && $attrVal <= 6) {

    } else {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }
    
  } elsif ($attrName eq "alarmAction") {
    my $data;
    if (!defined $attrVal) {
      if (AttrVal($name, "subType", "") eq "blindsCtrl.00") {
        # no alarm action
        $data = "7FFFFF0005";
        EnOcean_SndRadio(undef, $hash, 1, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
      }
    } elsif ($attrVal =~ m/(no|stop|opens|closes)$/) {
      if (AttrVal($name, "subType", "") eq "blindsCtrl.00") {
        my $alarmAction;
        if ($attrVal eq "no") {
          $alarmAction = 0;
        } elsif ($attrVal eq "stop") {
          $alarmAction = 1;
        } elsif ($attrVal eq "opens") {
          $alarmAction = 2;
        } elsif ($attrVal eq "closes") {
          $alarmAction = 3;
        }
        $data = sprintf "7FFFFF%02X05", $alarmAction;        
        #EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, $subDef, $status, $destinationID);
        EnOcean_SndRadio(undef, $hash, 1, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
      }    
    } else {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }
    
  } elsif ($attrName =~ m/^block.*/) {
    if (!defined $attrVal){
    
    } elsif ($attrVal =~ m/^(no|yes)$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        $waitingCmds |= 64;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }
    } else {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "comMode") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^biDir|uniDir|confirm$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "dataEnc") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^VAES|AES-CBC$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "daylightSavingTime") {
    if (!defined $attrVal){
    
    } elsif ($attrVal =~ m/^(supported|not_supported)$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        $waitingCmds |= 64;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }    
    } else {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "demandRespRandomTime") {
    if (!defined $attrVal) {
    
    } elsif ($attrVal !~ m/^\d+?$/ || $attrVal < 1) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal is not a integer number or not valid";
      CommandDeleteAttr(undef, "$name $attrName");
    }
    
  } elsif ($attrName =~ m/^(demandRespMax|demandRespMin)$/) {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^(A0|AI|B0|BI|C0|CI|D0|DI)$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "demandRespThreshold") {
    if (!defined $attrVal) {
    
    } elsif ($attrVal !~ m/^\d+?$/ || $attrVal < 0 || $attrVal > 15) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal is not a integer number or not valid";
      CommandDeleteAttr(undef, "$name $attrName");
    }
    
  } elsif ($attrName eq "devChannel") {
    if (!defined $attrVal){
    
    } elsif ($attrVal =~ m/^[\dA-Fa-f]{2}$/) {
      # convert old format
      #$attr{$name}{$attrName} = hex $attrVal;
      CommandAttr(undef, "$name $attrName " .  hex $attrVal);
      CommandSave(undef, undef);

    } elsif ($attrVal =~ m/^\d+$/ && $attrVal >= 0 && $attrVal <= 255) {

    } else {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "devMode") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^master|slave$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "devUpdate") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^(off|auto|demand|polling|interrupt)$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName =~ m/^dimMax|dimMin$/) {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^off|[\d+]$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "displayContent") {
    if (!defined $attrVal){
    
    } elsif ($attrVal =~ m/^(humidity|off|setPointTemp|tempertureExtern|temperatureIntern|time|default|no_change)$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        $waitingCmds |= 64;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }    
    } else {													      
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "eep") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^[\dA-Fa-f]{2}-[0-3][\dA-Fa-f]-[0-7][\dA-Fa-f]$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "humidity") {
    if (!defined $attrVal) {
    
    } elsif ($attrVal =~ m/^\d+$/ && $attrVal >= 0 && $attrVal <= 100) {

    } else {
      #RemoveInternalTimer($hash);    
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal is not a valid number";
      CommandDeleteAttr(undef, "$name $attrName");
    }
 
  } elsif ($attrName =~ m/^key/) {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^[\dA-Fa-f]{32}$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "macAlgo") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^no|[3-4]$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "manufID") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^[0-7][\dA-Fa-f]{2}$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "observe") {
    if (!defined $attrVal){
    
    } elsif (lc($attrVal) !~ m/^(off|on)$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "observeCmdRepetition") {
    if (!defined $attrVal){
    
    } elsif (lc($attrVal) !~ m/^[1-5]$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "observeLogic") {
    if (!defined $attrVal){
    
    } elsif (lc($attrVal) !~ m/^(and|or)$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "pollInterval") {
    if (!defined $attrVal) {
    
    } elsif ($attrVal =~ m/^\d+?$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        $waitingCmds |= 64;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }    
    } else {
      #RemoveInternalTimer($hash);    
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal is not a integer number";
      CommandDeleteAttr(undef, "$name $attrName");
    }
 
  } elsif ($attrName eq "rampTime") {
    if (!defined $attrVal){
    
    } elsif ($attrVal =~ m/^\d+?$/) {
      if (AttrVal($name, "subType", "") eq "gateway") {
        if ($attrVal < 0 || $attrVal > 255) { 
          Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
          CommandDeleteAttr(undef, "$name $attrName");
        } 
      } elsif (AttrVal($name, "subType", "") eq "lightCtrl.01") {
        if ($attrVal < 0 || $attrVal > 65535) { 
          Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
          CommandDeleteAttr(undef, "$name $attrName");
        }
      } else {
        Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
        CommandDeleteAttr(undef, "$name $attrName");      
      }
    } else {
      Log3 $name, 2, "EnOcean $name attribute $attrName not supported for subType " . AttrVal($name, "subType", "");
      CommandDeleteAttr(undef, "$name $attrName");
    }
   
  } elsif ($attrName eq "releasedChannel") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^A|B|C|D|I|0|auto$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "remoteManagement") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^(off|on)$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "reposition") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^(directly|opens|closes)$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName =~ m/^rlcRcv|rlcSnd$/) {
    if (!defined $attrVal){
    
    } elsif (AttrVal($name, "rlcAlgo", "") eq "2++" && $attrVal =~ m/^[\dA-Fa-f]{4}$/) {
    
    } elsif (AttrVal($name, "rlcAlgo", "") eq "3++" && $attrVal =~ m/^[\dA-Fa-f]{6}$/) {

    } else {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "rlcAlgo") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^no|2++|3++$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "rlcTX") {
    if (!defined $attrVal){
    
    } elsif (lc($attrVal) !~ m/^true|false$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "secCode") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^[\dA-Fa-f]{8}$/ || $attrVal eq "00000000" || uc($attrVal) eq "FFFFFFFF") {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "secLevel") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^encapsulation|encryption|off$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "secMode") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^rcv|snd|bidir$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "sendDevStatus") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^no|yes$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "serviceOn") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^(no|yes)$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "setCmdTrigger") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^man|refDev$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "shutTime") {
    my $data;
    if (!defined $attrVal) {
      if (AttrVal($name, "subType", "") eq "blindsCtrl.00") {
        # set shutTime to max
        $data = "7530FF0705";
        EnOcean_SndRadio(undef, $hash, 1, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
      }
    } elsif (AttrVal($name, "subType", "") eq "blindsCtrl.00" && $attrVal =~ m/^[+-]?\d+$/ && $attrVal >= 5 && $attrVal <= 300) {
      $attrVal = int($attrVal * 100);
      $data = sprintf "%04XFF0705", $attrVal;        
      #EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, $subDef, $status, $destinationID);
      EnOcean_SndRadio(undef, $hash, 1, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});   
    } elsif (AttrVal($name, "subType", "") eq "manufProfile" && AttrVal($name, "manufID", "") eq "00D" &&
             $attrVal =~ m/^[+-]?\d+$/ && $attrVal >= 1 && $attrVal <= 255) {

    } else {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }
    
  } elsif ($attrName eq "summerMode") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^(off|on)$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName =~ m/^subDef.?/) {
    if (!defined $attrVal){
    
    } elsif ($attrVal eq "getNextID") {    
      $attr{$name}{$attrName} = EnOcean_CheckSenderID("getNextID", $defs{$name}{IODev}{NAME}, "00000000");
      #CommandAttr(undef, "$name $attrName " . EnOcean_CheckSenderID("getNextID", $defs{$name}{IODev}{NAME}, "00000000"));
      CommandSave(undef, undef);
      #CommandRereadCfg(undef, "");
    } elsif ($attrVal !~ m/^[\dA-Fa-f]{8}$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "switchHysteresis") {
    if (!defined $attrVal) {
    
    } elsif ($attrVal =~ m/^\d+(\.\d+)?$/ && $attrVal >= 0.1) {

    } else {
      #RemoveInternalTimer($hash);    
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal is not a valid number";
      CommandDeleteAttr(undef, "$name $attrName");
    }
 
  } elsif ($attrName eq "temperatureScale") {
    if (!defined $attrVal){
    
    } elsif ($attrVal =~ m/^(C|F|default|no_change)$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        $waitingCmds |= 64;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }    
    } else {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "timeNotation") {
    if (!defined $attrVal){
    
    } elsif ($attrVal =~ m/^(12|24|default|no_change)$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        $waitingCmds |= 64;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }    
    } else {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName =~ m/^timeProgram[1-4]$/) {
    if (!defined $attrVal){
    
    } elsif ($attrVal =~ m/^(FrMo|FrSu|ThFr|WeFr|TuTh|MoWe|SaSu|MoFr|MoSu|Su|Sa|Fr|Th|We|Tu|Mo)\s+(\d*?):(00|15|30|45)\s+(\d*?):(00|15|30|45)\s+(comfort|economy|preComfort|buildingProtection)$/) {
      if (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
        # delete remote and send new time program
        delete $hash->{helper}{4}{telegramWait};
        $hash->{helper}{4}{telegramWait}{substr($attrName,-1,1) + 0} = 1;
        for (my $messagePartCntr = 1; $messagePartCntr <= 4; $messagePartCntr ++) {
          if (defined AttrVal($name, "timeProgram" . $messagePartCntr, undef)) {
            $hash->{helper}{4}{telegramWait}{$messagePartCntr} = 1;
          }
        }
        $waitingCmds |= 528;
        readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
      }
    } else {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "updateState") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^default|yes|no$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "uteResponseRequest") {
    if (!defined $attrVal){
    
    } elsif ($attrVal !~ m/^(yes|no)$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  }
#  if (defined $attrVal) {
#    Log3 $name, 2, "EnOcean $name [$attrName] = $attrVal";
#  }
  return undef;
}

sub EnOcean_Notify(@)
{
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};
  my $devName = $dev->{NAME};
  return undef if (AttrVal($name ,"disable", 0) > 0);
  return undef if ($devName eq $name);

  my $max = int(@{$dev->{CHANGED}});
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));

    if ($devName eq "global" && $s =~ m/^RENAMED ([^ ]*) ([^ ]*)$/) {
      if (defined AttrVal($name, "temperatureRefDev", undef)) {
        if (AttrVal($name, "temperatureRefDev", undef) eq $1) {
          CommandAttr(undef, "$name temperatureRefDev $2");
        }
      } elsif (defined AttrVal($name, "humidityRefDev", undef)) {
        if (AttrVal($name, "humidityRefDev", undef) eq $1) {
          CommandAttr(undef, "$name humidityRefDev $2");
        }
      } elsif (defined AttrVal($name, "observeRefDev", undef)) {
        if (AttrVal($name, "observeRefDev", undef) eq $1) {
          CommandAttr(undef, "$name observeRefDev $2");
        }
      } elsif (defined AttrVal($name, "demandRespRefDev", undef)) {
        if (AttrVal($name, "demandRespRefDev", undef) eq $1) {
          CommandAttr(undef, "$name demandRespRefDev $2");
        }
      }      
      #Log3($name, 5, "EnOcean $name <notify> RENAMED old: $1 new: $2");
      
    } elsif ($devName eq "global" && $s =~ m/^DELETED ([^ ]*)$/) {
      # delete attribute *RefDev
      if (defined AttrVal($name, "temperatureRefDev", undef)) {
        if (AttrVal($name, "temperatureRefDev", undef) eq $1) {
          CommandDeleteAttr(undef, "$name temperatureRefDev");        
        }
      } elsif (defined AttrVal($name, "humidityRefDev", undef)) {
        if (AttrVal($name, "humidityRefDev", undef) eq $1) {
          CommandDeleteAttr(undef, "$name humidityRefDev");        
        }
      } elsif (defined AttrVal($name, "observeRefDev", undef)) {
        if (AttrVal($name, "observeRefDev", undef) eq $1) {
          CommandDeleteAttr(undef, "$name observeRefDev");        
        }
      } elsif (defined AttrVal($name, "demandRespRefDev", undef)) {
        if (AttrVal($name, "demandRespRefDev", undef) eq $1) {
          CommandDeleteAttr(undef, "$name demandRespRefDev");        
        }
      }      
      #Log3($name, 5, "EnOcean $name <notify> DELETED $1");
      
    } elsif ($devName eq "global" && $s =~ m/^DEFINED ([^ ]*)$/) {
      my $definedName = $1;
      if ($definedName =~ m/FileLog_EnO_(.*)_(.*)/) {
        # UTE teach-in response actions
        # delete temporary teach-in response device
        my $IODev = $defs{$name}{IODev}{NAME};
        my $IOHash = $defs{$IODev};
        my $rorgName = $1;
        if (defined $IOHash->{helper}{UTERespWaitDel}{$name} && $rorgName eq "UTE") {
          CommandDelete(undef, substr($definedName, 8));
          delete $IOHash->{helper}{UTERespWaitDel}{$name};
          Log3 $name, 2, "EnOcean $name UTE temporary teach-in response device " . substr($definedName, 8) . " deleted";  
        }  
      }
      #Log3($name, 5, "EnOcean $name <notify> DEFINED $definedName");

    } elsif ($devName eq "global" && $s =~ m/^INITIALIZED$/) {
      if (AttrVal($name ,"subType", "") eq "roomCtrlPanel.00") {
        CommandDeleteReading(undef, "$name waitingCmds");
      } 
      Log3($name, 5, "EnOcean $name <notify> INITIALIZED");

    } elsif ($devName eq "global" && $s =~ m/^REREADCFG$/) {
      if (AttrVal($name ,"subType", "") eq "roomCtrlPanel.00") {
        CommandDeleteReading(undef, "$name waitingCmds");
      } 
      #Log3($name, 5, "EnOcean $name <notify> REREADCFG");

    } elsif ($devName eq "global" && $s =~ m/^ATTR ([^ ]*) ([^ ]*) ([^ ]*)$/) {
      #Log3($name, 5, "EnOcean $name <notify> ATTR $1 $2 $3");
 
    } elsif ($devName eq "global" && $s =~ m/^DELETEATTR ([^ ]*)$/) {
      #Log3($name, 5, "EnOcean $name <notify> DELETEATTR $1");

    } elsif ($devName eq "global" && $s =~ m/^MODIFIED ([^ ]*)$/) {
      #Log3($name, 5, "EnOcean $name <notify> MODIFIED $1");

    } elsif ($devName eq "global" && $s =~ m/^SAVE$/) {
      #Log3($name, 5, "EnOcean $name <notify> SAVE");

    } elsif ($devName eq "global" && $s =~ m/^SHUTDOWN$/) {
      #Log3($name, 5, "EnOcean $name <notify> SHUTDOWN");

    } else {
      my @parts = split(/: | /, $s);
      
      if (defined AttrVal($name, "observeRefDev", undef)) {
        my @observeRefDev = split("[ \t][ \t]*", AttrVal($name, "observeRefDev", undef));       
        if (grep /^$devName$/, @observeRefDev) {
          my ($reading, $value) = ("", "");
          $reading = shift @parts;
          if (!defined($parts[0]) || @parts > 1) {
            $value = $s;
            $reading = "state";
          } else {
            $value = $parts[0];
          }
          my @cmdObserve = ($devName, $reading, $value);
          EnOcean_observeParse(2, $hash, @cmdObserve);      
          #Log3($name, 5, "EnOcean $name <notify> observeRefDev: $devName $reading: $value");
        }
      }
      
      if (defined AttrVal($name, "demandRespRefDev", undef)) {
        my @demandRespRefDev = split("[ \t][ \t]*", AttrVal($name, "demandRespRefDev", undef));       
        if (grep /^$devName$/, @demandRespRefDev) {
          my @cmdDemandResponse;
          my $actionCmd = AttrVal($name, "demandRespAction", undef);          
          if (defined $actionCmd) {
            if ($parts[0] =~ m/^on|off$/) {
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set $parts[0]");
              my %specials= ("%TARGETNAME" => $name,
                             "%NAME" => $devName,
                             "%TARGETTYPE" => $hash->{TYPE},
                             "%TYPE" => $dev->{TYPE},
                             "%LEVEL" => ReadingsVal($devName, "level", 15),                   
                             "%SETPOINT"  => ReadingsVal($devName, "setpoint", 255),
                             "%POWERUSAGE"  => ReadingsVal($devName, "powerUsage", 100),
                             "%POWERUSAGESCALE"  => ReadingsVal($devName, "powerUsageScale", "max"),
                             "%POWERUSAGELEVEL"  => ReadingsVal($devName, "powerUsageLevel", "max"),
                             "%TARGETSTATE" => ReadingsVal($name, "state", ""),
                             "%STATE" => ReadingsVal($devName, "state", "off")
                            );
              # action exec
              $actionCmd = EvalSpecials($actionCmd, %specials);
              my $ret = AnalyzeCommandChain(undef, $actionCmd);
              Log3 $name, 2, "$name: $ret" if($ret);
            }
          
          } elsif (AttrVal($name, "subType", "") =~ m/^switch.*$/ || AttrVal($name, "subTypeSet", "") =~ m/^switch.*$/) {
            if ($parts[0] eq "powerUsageLevel" && $parts[1] eq "max") {
              @cmdDemandResponse = ($name, AttrVal($name, "demandRespMax", "B0"));
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);      
            } elsif ($parts[0] eq "powerUsageLevel" && $parts[1] eq "min") {
              @cmdDemandResponse = ($name, AttrVal($name, "demandRespMin", "BI"));           
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);      
            }
            
          } elsif (AttrVal($name, "subType", "") eq "gateway" && AttrVal($name, "gwCmd", "") eq "switching") {
            if ($parts[0] eq "powerUsageLevel" && $parts[1] eq "max") {
              @cmdDemandResponse = ($name, "on");
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);      
            } elsif ($parts[0] eq "powerUsageLevel" && $parts[1] eq "min") {
              @cmdDemandResponse = ($name, "off");           
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);      
            }
            
          } elsif ((AttrVal($name, "subType", "") eq "gateway" && AttrVal($name, "gwCmd", "") eq "dimming")
                   || AttrVal($name, "subType", "") eq "actuator.01") {
            if ($parts[0] eq "powerUsage") {
              if (ReadingsVal($devName, "powerUsageScale", "max") eq "rel") {
                @cmdDemandResponse = ($name, "dim", $parts[1] * ReadingsVal($name, "dimValueLast", 100) / 100);
              } else {
                @cmdDemandResponse = ($name, "dim", $parts[1]);
              }
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);      
            }
          
          } elsif ((AttrVal($name, "subType", "") eq "roomSensorControl.05" && AttrVal($name, "manufID", "") eq "00D")) {
            if ($parts[0] eq "level") {
              @cmdDemandResponse = ($name, "nightReduction", int(5 - 1/3 * $parts[1]));
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);      
            }
          
          } elsif (AttrVal($name, "subType", "") eq "lightCtrl.01") {
            if ($parts[0] eq "setpoint") {
              @cmdDemandResponse = ($name, "dim", $parts[1]);
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);      
            }

          } elsif (AttrVal($name, "subType", "") eq "roomSensorControl.01") {
            if ($parts[0] eq "setpoint") {
              @cmdDemandResponse = ($name, "setpoint", $parts[1]);
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);      
            }

          } elsif (AttrVal($name, "subType", "") eq "roomSensorControl.05") {
            if ($parts[0] eq "setpoint") {            
              @cmdDemandResponse = ($name, $parts[0], $parts[1]);
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);      
            }
          
          } elsif (AttrVal($name, "subType", "") eq "roomCtrlPanel.00") {
            if ($parts[0] eq "powerUsageLevel" && $parts[1] eq "max") {
              @cmdDemandResponse = ($name, "roomCtrlMode", "comfort");
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);      
            } elsif ($parts[0] eq "powerUsageLevel" && $parts[1] eq "min") {
              @cmdDemandResponse = ($name, "roomCtrlMode", "economy");           
              #Log3($name, 3, "EnOcean $name <notify> demandRespRefDev: $devName Cmd: set " . join(" ", @cmdDemandResponse));
              EnOcean_Set($hash, @cmdDemandResponse);      
            }
          }
        }
      }

      if (defined(AttrVal($name, "humidityRefDev", undef)) && AttrVal($name, "setCmdTrigger", "man") eq "refDev") {
        if ($devName eq AttrVal($name, "humidityRefDev", "")) {
          if ($parts[0] eq "humidity") {         
            if (AttrVal($name, "subType", "") eq "roomSensorControl.01") {
              my @setCmd = ($name, "setpoint");           
              EnOcean_Set($hash, @setCmd);
            }
          }
        }
      #Log3 $name, 2, "EnOcean $name <notify> $devName $s";
      }
      
      if (defined(AttrVal($name, "temperatureRefDev", undef)) && AttrVal($name, "setCmdTrigger", "man") eq "refDev") {
        if ($devName eq AttrVal($name, "temperatureRefDev", "")) {
          if ($parts[0] eq "temperature") {         
            if (AttrVal($name, "subType", "") eq "roomSensorControl.05" && AttrVal($name, "manufID", "") eq "00D") {
              my @setCmd = ($name, "setpointTemp");           
              EnOcean_Set($hash, @setCmd);      
            } elsif (AttrVal($name, "subType", "") eq "fanCtrl.00") {
              my @setCmd = ($name, "setpointTemp");           
              EnOcean_Set($hash, @setCmd);      
            } elsif (AttrVal($name, "subType", "") eq "roomSensorControl.01") {
              my @setCmd = ($name, "setpoint");           
              EnOcean_Set($hash, @setCmd);      
            } elsif (AttrVal($name, "subType", "") eq "roomSensorControl.05") {
              my @setCmd = ($name, "setpoint");           
              EnOcean_Set($hash, @setCmd);      
            }
          }
        }
      #Log3 $name, 2, "EnOcean $name <notify> $devName $s";
      }
    }
  }
  return undef;
}

# ADT encapsulation
sub
EnOcean_Encapsulation($$$$)
{
  my ($packetType, $rorg, $data, $destinationID) = @_;
  if ($destinationID eq "FFFFFFFF") {
    return ($rorg, $data);  
  } else {
    $data = $rorg . $data;  
    return ("A6", $data);
  }
}

# sent message to the actuator (EEP A5-20-01)
sub
EnOcean_hvac_01Cmd($$$)
{
  my ($hash, $packetType, $db_1) = @_;
  my $name = $hash->{NAME}; 
  my $cmd = ReadingsVal($name, "CMD", undef);
  my $subDef = AttrVal($name, "subDef", "00000000");
  if($cmd) {
    my $msg;
    my $arg1 = ReadingsVal($name, $cmd, 0); # Command-Argument
    # primarily temperature from the reference device, secondly the attribute actualTemp
    # and thirdly from the MD15 measured temperature device is read
    my $temperatureRefDev = AttrVal($name, "temperatureRefDev", undef);
    my $actualTemp = AttrVal($name, "actualTemp", $db_1 * 40 / 255);
    $actualTemp = ReadingsVal($temperatureRefDev, "temperature", 20) if (defined $temperatureRefDev); 
    $actualTemp = 20 if ($actualTemp !~ m/^[+-]?\d+(\.\d+)?$/);
    $actualTemp = 0 if ($actualTemp < 0);
    $actualTemp = 40 if ($actualTemp > 40);
    my $summerMode = AttrVal($name, "summerMode", "off");
    readingsSingleUpdate($hash, "temperature", (sprintf "%0.1f", $actualTemp), 1);
    if($cmd eq "actuator" || $cmd eq "setpoint") {
      CommandDeleteReading(undef, "$name setpointTemp");
      $msg = sprintf "%02X00%02X08", $arg1, ($summerMode eq "on" ? 8 : 0);      
    } elsif($cmd eq "desired-temp" || $cmd eq "setpointTemp") {
      readingsSingleUpdate($hash, "setpointTemp", (sprintf "%0.1f", $arg1), 1);    
      $msg = sprintf "%02X%02X%02X08", $arg1 * 255 / 40, (40 - $actualTemp) * 255 / 40, ($summerMode eq "on" ? 12 : 4);      
    # Maintenance commands
    } elsif($cmd eq "runInit") {
      $msg = "00008108";
    } elsif($cmd eq "liftSet") {
      $msg = "00004108";
    } elsif($cmd eq "valveOpen") {
      $msg = "00002108";
    } elsif($cmd eq "valveClosed") {
      $msg = "00001108";
    }
    if($msg) {
      EnOcean_SndRadio(undef, $hash, $packetType, "A5", $msg, $subDef, "00", $hash->{DEF});
    }
  }
}

# sent message to Room Control Panel (EEP D2-10-xx)
sub
EnOcean_roomCtrlPanel_00Snd($$$$$$$$)
{
  my ($crtl, $hash, $packetType, $mid, $mcf, $irc, $fbc, $gmt) = @_;
  my $name = $hash->{NAME};
  my ($data, $err, $response, $logLevel);
  my $messagePart = 1;

  if ($mid == 0) {
    # general massage
    ($err, $response, $data, $logLevel) = EnOcean_roomCtrlPanel_00Cmd(undef, $hash, $mcf, $messagePart);
    EnOcean_SndRadio(undef, $hash, $packetType, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
    if ($err) {
      Log3 $name, $logLevel, "EnOcean $name Error: $err";
    } else {
      Log3 $name, $logLevel, "EnOcean $name $response";
    }
    
    if (!defined($irc)) {
    
    } elsif ($irc == 0) {
      # acknowledge request

    } elsif ($irc == 1) {
      # data request

    } elsif ($irc == 2) {
      # configuration request
  
    } elsif ($irc == 3) {
      # room control request
    
    } elsif ($irc == 4) {
      # time program request
    
    }

    if (!defined($fbc)) {
  
    } elsif ($fbc == 0) {
      # acknowledge / heartbeat
  
    } elsif ($fbc == 1) {
      # telegram repetition request
 
    } elsif ($fbc == 2) {
      # message repetition request

    } elsif ($fbc == 3) {
      # reserved
    
    }

    if (!defined($gmt)) {
  
    } elsif ($gmt == 0) {
      # information request
  
    } elsif ($gmt == 1) {
      # feetback

    } 


  } elsif ($mid == 1) {
    # data message
    ($err, $response, $data, $logLevel) = EnOcean_roomCtrlPanel_00Cmd(undef, $hash, $mcf, $messagePart);
    EnOcean_SndRadio(undef, $hash, $packetType, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
    if ($err) {
      Log3 $name, $logLevel, "EnOcean $name Error: $err";
    } else {
      Log3 $name, $logLevel, "EnOcean $name $response";
    }

  } elsif ($mid == 2) {
    # configuration message
    ($err, $response, $data, $logLevel) = EnOcean_roomCtrlPanel_00Cmd(undef, $hash, $mcf, $messagePart);
    EnOcean_SndRadio(undef, $hash, $packetType, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
    if ($err) {
      Log3 $name, $logLevel, "EnOcean $name Error: $err";
    } else {
      Log3 $name, $logLevel, "EnOcean $name $response";
    }
    
  } elsif ($mid == 3) {
    # room control setup
    ($err, $response, $data, $logLevel) = EnOcean_roomCtrlPanel_00Cmd(undef, $hash, $mcf, $messagePart);
    EnOcean_SndRadio(undef, $hash, $packetType, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
    if ($err) {
      Log3 $name, $logLevel, "EnOcean $name Error: $err";
    } else {
      Log3 $name, $logLevel, "EnOcean $name $response";
    }

  } elsif ($mid == 4) {
    # time program setup
    ($err, $response, $data, $logLevel) = EnOcean_roomCtrlPanel_00Cmd(undef, $hash, $mcf, $messagePart);
    EnOcean_SndRadio(undef, $hash, $packetType, "D2", $data, AttrVal($name, "subDef", "00000000"), "00", $hash->{DEF});
    if ($err) {
      Log3 $name, $logLevel, "EnOcean $name Error: $err";
    } else {
      Log3 $name, $logLevel, "EnOcean $name $response";
    }

  }

  return ($err, $response);
}

# generate command to Room Control Panel (EEP D2-10-xx)
sub
EnOcean_roomCtrlPanel_00Cmd($$$$)
{
  my ($crtl, $hash, $mcf, $messagePart) = @_;
  my $name = $hash->{NAME};
  my $data = "0000";
  my $err;
  my $response = "acknowledge send";
  my $logLevel = 4;
  # Waitings Commands (waitingCmds)
  # 1 = sent data request
  # 2 = sent data message
  # 4 = sent configuration message (time)
  # 8 = sent room control setup
  # 16 = sent time program setup
  # 32 = sent configuration request
  # 64 = sent configuration message
  # 128 = sent room control setup request 
  # 256 = sent time program request
  # 512 = sent delete time program
  my $waitingCmds = ReadingsVal($name, "waitingCmds", 0);
  if ($mcf == 0) {
    # message complete
    if ($waitingCmds & 8) {
      # room control setup waiting
      my ($db5, $db4, $db3, $db2, $db1, $db0) = (96, 0, 0, 0, 0, 0, 0);
      if (defined ReadingsVal($name, "setpointComfortTempSet", undef)) {
        $db1 = ReadingsVal($name, "setpointComfortTempSet", 0) * 255 / 40;
        $db0 = $db0 | 1;
        CommandDeleteReading(undef, "$name setpointComfortTempSet");
      }
      if (defined ReadingsVal($name, "setpointEconomyTempSet", undef)) {
        $db2 = ReadingsVal($name, "setpointEconomyTempSet", 0) * 255 / 40;
        $db0 = $db0 | 2;
        CommandDeleteReading(undef, "$name setpointEconomyTempSet");
      }
      if (defined ReadingsVal($name, "setpointPreComfortTempSet", undef)) {
        $db3 = ReadingsVal($name, "setpointPreComfortTempSet", 0) * 255 / 40;
        $db0 = $db0 | 4;
        CommandDeleteReading(undef, "$name setpointPreComfortTempSet");
      }
      if (defined ReadingsVal($name, "setpointBuildingProtectionTempSet", undef)) {
        $db4 = ReadingsVal($name, "setpointBuildingProtectionTempSet", 0) * 255 / 40;
        $db0 = $db0 | 8;
        CommandDeleteReading(undef, "$name setpointBuildingProtectionTempSet");
      }
      $data = sprintf "%02X%02X%02X%02X%02X%02X", $db5, $db4, $db3, $db2, $db1, $db0;
      # clear command
      $waitingCmds = $waitingCmds & 247 + 0xFF00;
      $response = "room control setup send $data";
      $logLevel = 2;
    
    } elsif ($waitingCmds & 64 || $waitingCmds & 4) {
      # configuration message waiting
      my ($sec, $min, $hour, $day, $month, $year) = localtime();
      my ($key, $val);
      $month += 1;
      $year += 1900;
      my ($db7, $db6, $db5, $db4, $db1, $db0) = (64, 0, 0, 0, $min << 2, $hour << 3);
      $db6 |= 1 if (AttrVal($name, "blockFanSpeed", "no") ne "yes" );
      $db6 |= 2 if (AttrVal($name, "blockSetpointTemp", "no") ne "yes" );
      $db6 |= 4 if (AttrVal($name, "blockOccupancy", "no") ne "yes" );
      $db6 |= 8 if (AttrVal($name, "blockTimeProgram", "no") ne "yes" );
      $db6 |= 16 if (AttrVal($name, "blockDateTime", "no") ne "yes" );
      $db6 |= 32 if (AttrVal($name, "blockDisplay", "no") ne "yes" );
      $db6 |= 64 if (AttrVal($name, "blockTemp", "no") ne "yes" );
      $db6 |= 128 if (AttrVal($name, "blockMotion", "no") ne "yes" );
      $db5 = AttrVal($name, "pollInterval", 10);
      if ($db5 > 60 && $db5 <= 180) {
        $db5 = 61;
      } elsif ($db5 > 180 && $db5 <= 720) {
        $db5 = 62;      
      } elsif ($db5 > 720) {
        $db5 = 63;
      }
      $db5 = $db5 << 2;
      $db5 |= 2 if (AttrVal($name, "blockKey", "no") ne "yes" );
      my $displayContent = AttrVal($name, "displayContent", "no_change");
      my $displayContentVal = 0;
      my %displayContent = ("humidity" => 7,
                            "off" => 6,
                            "setPointTemp" => 5,
                            "tempertureExtern" => 4,
                            "temperatureIntern" => 3,
                            "time" => 2,
                            "default" => 1,
                            "no_change" => 0
                           );
      while (($key, $val) = each(%displayContent)) {
        $displayContentVal = $val if ($key eq $displayContent);
      }
      my $temperatureScale = AttrVal($name, "temperatureScale", "no_change");
      my $temperatureScaleVal = 0;
      my %temperatureScale = ("F" => 3,
                              "C" => 2,
                              "default" => 1,
                              "no_change" => 0
                             );
      while (($key, $val) = each(%temperatureScale)) {
        $temperatureScaleVal = $val if ($key eq $temperatureScale);
      }
      my $daylightSavingTimeVal = 0;
      $daylightSavingTimeVal = 1 if (AttrVal($name, "daylightSavingTime", "supported") eq "not_supported");
      my $timeNotation = AttrVal($name, "timeNotation", "no_change");
      my $timeNotationVal = 0;     
      if ($timeNotation eq "no_change") {
        $timeNotationVal = 0;
      } elsif ($timeNotation eq "default") {
        $timeNotationVal = 1;
      } elsif ($timeNotation == 24) {
        $timeNotationVal = 2;
      } elsif ($timeNotation == 12) {
        $timeNotationVal = 3;
      }
      $db4 = (($displayContentVal << 2 | $temperatureScaleVal) << 1 | $daylightSavingTimeVal) << 2 | $timeNotationVal;
      my $db32 = ($day << 4 | $month) << 7 | $year - 2000;
      if ($waitingCmds & 4) {
        $db0 |= 1;
        # clear time command
        $waitingCmds &= 251 + 0xFF00;
      }
      if ($waitingCmds & 64) {
        # clear config command
        $waitingCmds &= 191 + 0xFF00;
      }
      $data = sprintf "%02X%02X%02X%02X%04X%02X%02X", $db7, $db6, $db5, $db4, $db32, $db1, $db0;
      $response = "configuration message send $data";
      $logLevel = 2;

    } elsif ($waitingCmds & 2) {
      # data message waiting
      my ($db7, $db6, $db5, $db4, $db3, $db2, $db1, $db0) = (32, 0, 0, 0, 0, 0, 0, 0, 0);

      if (defined ReadingsVal($name, "setpointTempSet", undef)) {
        $db1 = ReadingsVal($name, "setpointTempSet", 0) * 255 / 40;
        $db2 |= 2;
        CommandDeleteReading(undef, "$name setpointTempSet");
      }

      my $heatingSet;
      if (defined ReadingsVal($name, "heatingSet", undef)) {
        $heatingSet = ReadingsVal($name, "heatingSet", 0);
      } else {
        $heatingSet = ReadingsVal($name, "heating", 0);      
      }
      if ($heatingSet eq "no_change") {
        $heatingSet = 0;
      } elsif ($heatingSet eq "on") {
        $heatingSet = 1;
      } elsif ($heatingSet eq "off") {
        $heatingSet = 2;
      } elsif ($heatingSet eq "auto") {
        $heatingSet = 3;
      }
      $db2 |= $heatingSet << 4;      
      CommandDeleteReading(undef, "$name heatingSet");

      my $coolingSet;
      if (defined ReadingsVal($name, "coolingSet", undef)) {
        $coolingSet = ReadingsVal($name, "coolingSet", 0);
      } else {
        $coolingSet = ReadingsVal($name, "cooling", 0);      
      }
      if ($coolingSet eq "no_change") {
        $coolingSet = 0;
      } elsif ($coolingSet eq "on") {
        $coolingSet = 1;
      } elsif ($coolingSet eq "off") {
        $coolingSet = 2;
      } elsif ($coolingSet eq "auto") {
        $coolingSet = 3;
      }
      $db2 |= $coolingSet << 6;      
      CommandDeleteReading(undef, "$name coolingSet");

      my $roomCtrlModeSet;
      if (defined ReadingsVal($name, "roomCtrlModeSet", undef)) {
        $roomCtrlModeSet = ReadingsVal($name, "roomCtrlModeSet", 0);
      } else {
        $roomCtrlModeSet = ReadingsVal($name, "roomCtrlMode", 0);      
      }
      if ($roomCtrlModeSet eq "comfort") {
        $roomCtrlModeSet = 0;
      } elsif ($roomCtrlModeSet eq "economy") {
        $roomCtrlModeSet = 1;
      } elsif ($roomCtrlModeSet eq "preComfort") {
        $roomCtrlModeSet = 2;
      } elsif ($roomCtrlModeSet eq "buildingProtection") {
        $roomCtrlModeSet = 3;
      }
      $db2 |= $roomCtrlModeSet << 2;
      CommandDeleteReading(undef, "$name roomCtrlModeSet");

      my $windowSet;
      if (defined ReadingsVal($name, "windowSet", undef)) {
        $windowSet = ReadingsVal($name, "windowSet", 0);
      } else {
        $windowSet = ReadingsVal($name, "window", 0);      
      }
      if ($windowSet eq "no_change") {
        $windowSet = 0;
      } elsif ($windowSet eq "closed") {
        $windowSet = 1;
      } elsif ($windowSet eq "open") {
        $windowSet = 2;
      } elsif ($windowSet eq "reserved") {
        $windowSet = 3;
      }
      $db4 |= $windowSet;      
      CommandDeleteReading(undef, "$name windowSet");

      my $fanSpeedModeSet;
      if (defined ReadingsVal($name, "fanSpeedModeSet", undef)) {
        $fanSpeedModeSet = ReadingsVal($name, "fanSpeedModeSet", 0);
      } else {
        $fanSpeedModeSet = ReadingsVal($name, "fanSpeedMode", 0);      
      }
      $db4 |= 64 if ($fanSpeedModeSet eq "local");      
      CommandDeleteReading(undef, "$name fanSpeedModeSet");

      if (defined ReadingsVal($name, "fanSpeedSet", undef)) {
        $db5 = ReadingsVal($name, "fanSpeedSet", 0);
        $db4 |= 128;
        CommandDeleteReading(undef, "$name fanSpeedSet");
      }
      
      $data = sprintf "%02X%02X%02X%02X%02X%02X%02X%02X", $db7, $db6, $db5, $db4, $db3, $db2, $db1, $db0;
      # clear command
      $waitingCmds = $waitingCmds & 253 + 0xFF00;
      $response = "data message send";
      $logLevel = 2;

    } elsif ($waitingCmds & 512) {
      # delete time program command waiting
      $data = "800000000001";
      # clear command
      $waitingCmds = $waitingCmds & 0xFDFF;
      $response = "delete time program send";
      $logLevel = 2;

    } elsif ($waitingCmds & 16) {
      # time program setup waiting
      my ($db5, $endMinute, $endHour, $startMinute, $startHour, $db0) = (128, 0, 0, 0, 0, 0, 0);
      my ($key, $val);
      my $messagePartCntr;
      for ($messagePartCntr = 4; $messagePartCntr >= 1; $messagePartCntr --) {
        if ($hash->{helper}{4}{telegramWait}{$messagePartCntr}) {
          $hash->{helper}{4}{telegramWait}{$messagePartCntr} = 0;
          my $timeProgram = AttrVal($name, "timeProgram" . $messagePartCntr, undef);
          my @timeProgram = split("[ \t][ \t]*", $timeProgram);
          my ($period, $roomCtrlMode) = ($timeProgram[0], $timeProgram[3]);
          ($startHour, $startMinute) = split(":", $timeProgram[1]);
          ($endHour, $endMinute) = split(":", $timeProgram[2]);
          my $periodVal = 0;
          my %period = ("FrMo" => 15,
                        "FrSu" => 14,
                        "ThFr" => 13,
                        "WeFr" => 12,
                        "TuTh" => 11,
                        "MoWe" => 10,
                        "Su" => 9,
                        "Sa" => 8,
                        "Fr" => 7,
                        "Th" => 6,
                        "We" => 5,
                        "Tu" => 4,
                        "Mo" => 3,
                        "SaSu" => 2,
                        "MoFr" => 1,
                        "MoSu" => 0
                        );
          while (($key, $val) = each(%period)) {
            $periodVal = $val if ($key eq $period);
          }
          if ($roomCtrlMode eq "buildingProtection") {
            $roomCtrlMode = 3;
          } elsif ($roomCtrlMode eq "preComfort") {
            $roomCtrlMode = 2;
          } elsif ($roomCtrlMode eq "economy") {
            $roomCtrlMode = 1;
          } else{
            $roomCtrlMode = 0;       
          }      
          if ($messagePartCntr > 1) {
            # set mcf flag
            $db5 |= 1;
          } else {
            # clear command
            $waitingCmds = $waitingCmds & 239 + 0xFF00;
          }
          $data = sprintf "%02X%02X%02X%02X%02X%02X", $db5, $endMinute, $endHour, $startMinute, $startHour, $periodVal << 4 | $roomCtrlMode << 2;
          $response = "time program setup send";
          $logLevel = 2;
          last;
        }
      }

    } elsif ($waitingCmds & 1) {
      # data request waiting
      $data = "0009";
      # clear command
      $waitingCmds = $waitingCmds & 254 + 0xFF00;
      $response = "data request send";
      $logLevel = 2;

    } elsif ($waitingCmds & 32) {
      # configuration request waiting
      $data = "0011";
      # clear command
      $waitingCmds = $waitingCmds & 223 + 0xFF00;
      $response = "configuration request send";
      $logLevel = 2;

    } elsif ($waitingCmds & 128) {
      # room control setup request waiting
      $data = "0019";
      # clear command
      $waitingCmds = $waitingCmds & 127 + 0xFF00;
      $response = "room control setup request send";
      $logLevel = 2;

    } elsif ($waitingCmds & 256) {
      # time program request waiting
      $data = "0021";
      # clear command
      $waitingCmds = $waitingCmds & 0xFEFF;
      $response = "time program request send";
      $logLevel = 2;

    }

    if ($waitingCmds == 0) {
      CommandDeleteReading(undef, "$name waitingCmds");
    } else {
      readingsSingleUpdate($hash, "waitingCmds", $waitingCmds, 0);
    }

  } elsif ($mcf == 1) {
    # message incomplete
    $response = "acknowledge send, wating for next part of the message";
    $logLevel = 2;

  } elsif ($mcf == 2) {
    # automatic message control
    $response = "acknowledge send, automatic message control";
    $logLevel = 2;

  } elsif ($mcf == 3) {
    # reserved
  }

  return ($err, $response, $data, $logLevel);
}

# Check SenderIDs
sub EnOcean_CheckSenderID($$$)
{
  my ($ctrl, $IODev, $senderID) = @_;
  if (!defined $IODev) {
    my (@listIODev, %listIODev);
    foreach my $dev (keys %defs) {
      next if ($defs{$dev}{TYPE} ne "EnOcean");
      push(@listIODev, $defs{$dev}{IODev}{NAME});
    }
    @listIODev = sort grep(!$listIODev{$_}++, @listIODev);    
    if (@listIODev == 1) {
      $IODev = $listIODev[0];
    }
  }
  my $unusedID = 0;
  $unusedID = hex($defs{$IODev}{BaseID}) if ($defs{$IODev}{BaseID});
  my $IDCntr1;
  my $IDCntr2;
  if ($unusedID == 0) {
    $IDCntr1 = 0;
    $IDCntr2 = 0;
  } else {
    $IDCntr1 = $unusedID + 1;
    $IDCntr2 = $unusedID + 127;  
  }

  if ($ctrl eq "getBaseID") {
    # get TCM BaseID of the EnOcean device 
    if ($defs{$IODev}{BaseID}) {
      $senderID = $defs{$IODev}{BaseID}
    } else {
      $senderID = "0" x 8;
    }

  } elsif ($ctrl eq "getUsedID") {
    # find and sort used SenderIDs
    my @listID;
    my %listID;
    foreach my $dev (keys %defs) {
      next if ($defs{$dev}{TYPE} ne "EnOcean");
      push(@listID, grep(hex($_) >= $IDCntr1 && hex($_) <= $IDCntr2, $defs{$dev}{DEF}));
      push(@listID, $attr{$dev}{subDef}) if ($attr{$dev}{subDef});
      push(@listID, $attr{$dev}{subDefA}) if ($attr{$dev}{subDefA});
      push(@listID, $attr{$dev}{subDefB}) if ($attr{$dev}{subDefB});
      push(@listID, $attr{$dev}{subDefC}) if ($attr{$dev}{subDefC});
      push(@listID, $attr{$dev}{subDefD}) if ($attr{$dev}{subDefD});
      push(@listID, $attr{$dev}{subDefI}) if ($attr{$dev}{subDefI});
      push(@listID, $attr{$dev}{subDef0}) if ($attr{$dev}{subDef0});
    }
    $senderID = join(" ", sort grep(!$listID{$_}++, @listID));    
    
  } elsif ($ctrl eq "getFreeID") {
    # find and sort free SenderIDs
    my (@freeID, @listID, %listID, @intersection, @difference, %count, $element);
    for (my $IDCntr = $IDCntr1; $IDCntr <= $IDCntr2; $IDCntr++) {
      push(@freeID, sprintf "%08X", $IDCntr);
    }
    foreach my $dev (keys %defs) {
      next if ($defs{$dev}{TYPE} ne "EnOcean");
      push(@listID, grep(hex($_) >= $IDCntr1 && hex($_) <= $IDCntr2, $defs{$dev}{DEF}));
      push(@listID, $attr{$dev}{subDef}) if ($attr{$dev}{subDef} && $attr{$dev}{subDef} ne "00000000");
      push(@listID, $attr{$dev}{subDefA}) if ($attr{$dev}{subDefA} && $attr{$dev}{subDefA} ne "00000000");
      push(@listID, $attr{$dev}{subDefB}) if ($attr{$dev}{subDefB} && $attr{$dev}{subDefB} ne "00000000");
      push(@listID, $attr{$dev}{subDefC}) if ($attr{$dev}{subDefC} && $attr{$dev}{subDefC} ne "00000000");
      push(@listID, $attr{$dev}{subDefD}) if ($attr{$dev}{subDefD} && $attr{$dev}{subDefD} ne "00000000");
      push(@listID, $attr{$dev}{subDefI}) if ($attr{$dev}{subDefI} && $attr{$dev}{subDefI} ne "00000000");
      push(@listID, $attr{$dev}{subDef0}) if ($attr{$dev}{subDef0} && $attr{$dev}{subDef0} ne "00000000");
    }
    @listID = sort grep(!$listID{$_}++, @listID);
    foreach $element (@listID, @freeID) {
      $count{$element}++
    }
    foreach $element (keys %count) {
      push @{$count{$element} > 1 ? \@intersection : \@difference }, $element;
    }
    $senderID = ":" . join(" ", sort @difference);
    
  } elsif ($ctrl eq "getNextID") {
    # get next free SenderID
    my (@freeID, @listID, %listID, @intersection, @difference, %count, $element);
    for (my $IDCntr = $IDCntr1; $IDCntr <= $IDCntr2; $IDCntr++) {
      push(@freeID, sprintf "%08X", $IDCntr);
    }
    foreach my $dev (keys %defs) {
      next if ($defs{$dev}{TYPE} ne "EnOcean");
      push(@listID, grep(hex($_) >= $IDCntr1 && hex($_) <= $IDCntr2, $defs{$dev}{DEF}));
      push(@listID, $attr{$dev}{subDef}) if ($attr{$dev}{subDef} && $attr{$dev}{subDef} ne "00000000");
      push(@listID, $attr{$dev}{subDefA}) if ($attr{$dev}{subDefA} && $attr{$dev}{subDefA} ne "00000000");
      push(@listID, $attr{$dev}{subDefB}) if ($attr{$dev}{subDefB} && $attr{$dev}{subDefB} ne "00000000");
      push(@listID, $attr{$dev}{subDefC}) if ($attr{$dev}{subDefC} && $attr{$dev}{subDefC} ne "00000000");
      push(@listID, $attr{$dev}{subDefD}) if ($attr{$dev}{subDefD} && $attr{$dev}{subDefD} ne "00000000");
      push(@listID, $attr{$dev}{subDefI}) if ($attr{$dev}{subDefI} && $attr{$dev}{subDefI} ne "00000000");
      push(@listID, $attr{$dev}{subDef0}) if ($attr{$dev}{subDef0} && $attr{$dev}{subDef0} ne "00000000");
    }
    @listID = sort grep(!$listID{$_}++, @listID);
    foreach $element (@listID, @freeID) {
      $count{$element}++
    }
    foreach $element (keys %count) {
      push @{$count{$element} > 1 ? \@intersection : \@difference }, $element;
    }
    @difference = sort @difference;
    if (defined $difference[0]) {
      $senderID = $difference[0];
    } else {
      $senderID = "0" x 8;
      Log3 $IODev, 2, "EnOcean $IODev no free senderIDs available";      
    }
  
  } else {
  
  }
  return $senderID;
}

# assign next free SenderID
sub EnOcean_AssignSenderID($$$$)
{
  my ($ctrl, $hash, $attrName, $comMode) = @_;
  my $def = $hash->{DEF};
  my $err;
  my $name = $hash->{NAME};
  my $IODev = $defs{$name}{IODev}{NAME};
  my $senderID = AttrVal($name, $attrName, "");
  # SenderID valid
  return ($err, $senderID) if ($senderID =~ m/^[\dA-Fa-f]{8}$/);
  return ("no IODev", $def) if (!defined $IODev);
  # DEF is SenderID
  if (hex($def) >= hex($defs{$IODev}{BaseID}) && hex($def) <= hex($defs{$IODev}{BaseID}) + 127) {
    $attr{$name}{comMode} = "uniDir";
    return ($err, $def);
  } else {
    if ($comMode eq "biDir") {
      $attr{$name}{comMode} = $comMode;
    } else {
      $attr{$name}{comMode} = "confirm";
    }
    $senderID = EnOcean_CheckSenderID("getNextID", $IODev, "00000000");
  }
  Log3 $name, 2, "EnOcean $name SenderID: $senderID assigned";      
  CommandAttr(undef, "$name $attrName $senderID");
  return ($err, $senderID);
}

# split chained data message
sub EnOcean_SndCDM($$$$$$$$)
{
  my ($ctrl, $hash, $packetType, $rorg, $data, $senderID, $status, $destinationID) = @_;
  my ($seq, $idx, $len, $dataPart, $dataPartLen) = (0, 0, length($data) / 2, undef, 14);
  # split telelegram with optional data
  $dataPartLen = 9 if ($destinationID ne "FFFFFFFF"); 
  if ($len > $dataPartLen) {
    # first CDM telegram
    if ($dataPartLen == 14) {
      $data =~ m/^(....................)(.*)$/;
      $dataPart = (sprintf "%02X", $seq << 6 | $idx) . (sprintf "%04X", $len) . $rorg . $1;
      $data = $2;
    } else {
      $data =~ m/^(..........)(.*)$/;
      $dataPart = (sprintf "%02X", $seq << 6 | $idx) . (sprintf "%04X", $len) . $rorg . $1;
      $data = $2;
    }
    $idx ++;
    $len -= $dataPartLen - 5;
    EnOcean_SndRadio($ctrl, $hash, $packetType, "40", $dataPart, $senderID, $status, $destinationID);
    while ($len > 0) {
      if ($len > $dataPartLen - 1) {
        if ($dataPartLen == 14) {
          $data =~ m/^(..........................)(.*)$/;
          $dataPart = (sprintf "%02X", $seq << 6 | $idx) . $1;
          $data = $2;
        } else {
          $data =~ m/^(................)(.*)$/;
          $dataPart = (sprintf "%02X", $seq << 6 | $idx) . $1;
          $data = $2;
        }
        $idx ++;
        $len -= $dataPartLen - 1;
      } else {
        $dataPart = (sprintf "%02X", $seq << 6 | $idx) . $data;
        $len = 0;
      }
      EnOcean_SndRadio($ctrl, $hash, $packetType, "40", $dataPart, $senderID, $status, $destinationID);
    }
  } else {
    # not necessary to split
    EnOcean_SndRadio($ctrl, $hash, $packetType, $rorg, $data, $senderID, $status, $destinationID);
  }
  return;
}

# send ESP3 Packet Type Radio
sub EnOcean_SndRadio($$$$$$$$)
{
  my ($ctrl, $hash, $packetType, $rorg, $data, $senderID, $status, $destinationID) = @_;
  my ($err, $response, $loglevel);
  my $header;
  my $odata = "";
  my $odataLength = 0;
  if ($packetType == 1) {
    ($err, $rorg, $data, $response, $loglevel) = EnOcean_sec_convertToSecure($hash, $packetType, $rorg, $data);
    if (defined $err) {
      Log3 $hash->{NAME}, $loglevel, "EnOcean $hash->{NAME} Error: $err";
      return "";
    }
    if (AttrVal($hash->{NAME}, "repeatingAllowed", "yes") eq "no") {
      $status = substr($status, 0, 1) . "F";
    }
    if ($rorg eq "A6") {
      # ADT telegram
      $data .= $destinationID;
    } elsif ($destinationID ne "FFFFFFFF") {
      # SubTelNum = 03, DestinationID:8, RSSI = FF, secLevel = 00
      $odata = sprintf "03%sFF00", $destinationID;
      $odataLength = 7;    
    }
    # Data Length:4 Optional Length:2 Packet Type:2
    $header = sprintf "%04X%02X%02X", (length($data) / 2 + 6), $odataLength, $packetType;    
    Log3 $hash->{NAME}, 5, "EnOcean $hash->{NAME} sent PacketType: $packetType RORG: $rorg DATA: $data SenderID: $senderID STATUS: $status ODATA: $odata";
    $data = $rorg . $data . $senderID . $status . $odata;
  } elsif ($packetType == 7) {
    my $delay = 0;
    $delay = 1 if ($destinationID eq "FFFFFFFF");
    $senderID = "00000000";
    #$senderID = "00000000" if ($destinationID eq "FFFFFFFF");
    $odata = sprintf "%s%sFF%02X", $destinationID, $senderID, $delay;
    $odataLength = 10;    
    # Data Length:4 Optional Length:2 Packet Type:2
    $header = sprintf "%04X%02X%02X", (length($data) / 2), $odataLength, $packetType;
    Log3 $hash->{NAME}, 3, "EnOcean $hash->{NAME} sent PacketType: $packetType DATA: $data ODATA: $odata";
    $data .= $odata;  
  }  
  IOWrite($hash, $header, $data);
  return;
}

# Scale Readings
sub EnOcean_ReadingScaled($$$$)
{
  my ($hash, $readingVal, $readingMin, $readingMax) = @_;
  my $name = $hash->{NAME};
  my $valScaled;
  my $scaleDecimals = AttrVal($name, "scaleDecimals", undef);
  my $scaleMin = AttrVal($name, "scaleMin", undef);
  my $scaleMax = AttrVal($name, "scaleMax", undef);
  if (defined $scaleMax && defined $scaleMin &&
      $scaleMax =~ m/^[+-]?\d+(\.\d+)?$/ && $scaleMin =~ m/^[+-]?\d+(\.\d+)?$/) {
    $valScaled = ($readingMin*$scaleMax-$scaleMin*$readingMax)/
                 ($readingMin-$readingMax)+
                 ($scaleMin-$scaleMax)/($readingMin-$readingMax)*$readingVal;
  }
  if (defined $scaleDecimals && $scaleDecimals =~ m/^[0-9]?$/) {
    $scaleDecimals = "%0." . $scaleDecimals . "f";
    $valScaled = sprintf "$scaleDecimals", $valScaled;
  }
  return $valScaled;  
}

# Reorganize Strings
sub EnOcean_ReorgList($)
{
  my ($list) = @_;
  my @list = split("[ \t][ \t]*", $list);
  my %list;
  @list = sort grep(!$list{$_}++, @list);
  $list = join(" ", @list) . " ";
  return $list;
}

# EnOcean_Set called from sub InternalTimer()
sub EnOcean_TimerSet($)
{
  my ($par) = @_;
  EnOcean_Set($par->{hash}, @{$par->{timerCmd}});
}

#
sub EnOcean_InternalTimer($$$$$)
{
  my ($modifier, $tim, $callback, $hash, $waitIfInitNotDone) = @_;
  my $mHash = {};
  my $timerName = "$hash->{NAME}_$modifier";
  if ($modifier eq "") {
    $mHash = $hash;
  } else {
    if (exists ($hash->{helper}{TIMER}{$timerName})) {
      $mHash = $hash->{helper}{TIMER}{$timerName};
      Log3 $hash->{NAME}, 5, "EnOcean_InternalTimer setting mHash with stored $timerName";
   } else {
      $mHash = {HASH => $hash, NAME => $timerName, MODIFIER => $modifier};
      $hash->{helper}{TIMER}{$timerName} = $mHash;
      Log3 $hash->{NAME}, 5, "EnOcean_InternalTimer setting mHash with $timerName";
    }
  }
  InternalTimer($tim, $callback, $mHash, $waitIfInitNotDone);
  Log3 $hash->{NAME}, 5, "EnOcean setting timer $timerName at " . strftime("%Y-%m-%d %H:%M:%S", localtime($tim));
  return;
}

#
sub EnOcean_RemoveInternalTimer($$)
{
  my ($modifier, $hash) = @_;
  my $mHash = {};
  my $timerName = "$hash->{NAME}_$modifier";
  if ($modifier eq "") {
    RemoveInternalTimer($hash);
  } else {
    $mHash = $hash->{helper}{TIMER}{$timerName};
    if (defined($mHash)) {
      delete $hash->{helper}{TIMER}{$timerName};
      RemoveInternalTimer($mHash);
    }
  }
  Log3 $hash->{NAME}, 5, "EnOcean removing timer $timerName";
  return;
}

#
sub EnOcean_observeInit($$@)
{
  #init observe
  my ($ctrl, $hash, @cmdValue) = @_;
  my ($err, $name) = (undef, $hash->{NAME});
  return (undef, $ctrl) if (lc(AttrVal($name, "observe", "off")) eq "off");
  return (undef, $ctrl) if (defined($hash->{helper}{observeCntr}) && $hash->{helper}{observeCntr} > 0);
  $hash->{helper}{observeCntr} = 1;  
  #my @observeExeptions = split("[ \t][ \t]*", AttrVal($name, "observeExeptions", ""));
  my @observeRefDev = split("[ \t][ \t]*", AttrVal($name, "observeRefDev", $name));
  $hash->{helper}{observeRefDev} = \@observeRefDev;
  Log3 $name, 4, "EnOcean $name < observeRefDev " . join(" ", @{$hash->{helper}{observeRefDev}}) . " (init)";    
  $hash->{helper}{lastCmdFunction} = "set";
  # @cmdValue = (<name>, <cmd>, <param1>, <param2>, ...)
  $hash->{helper}{lastCmdValue} = \@cmdValue;
  my $observeCmds = AttrVal($name, "observeCmds", undef);
  my @observeCmds;
  #my %observeCmds;
  my ($cmdPair, $cmdSent, $cmdReceived);
  if (defined $observeCmds) {
    @observeCmds = split("[ \t][ \t]*", $observeCmds);
    foreach my $cmdPair (@observeCmds) {
      ($cmdSent, $cmdReceived) = split(":", $cmdPair);
      $hash->{helper}{observeCmds}{$cmdSent} = $cmdReceived;
    }
  } else {
    $hash->{helper}{observeCmds}{$cmdValue[1]} = $cmdValue[1];
  }
  $hash->{helper}{observeCntr} = 1;
  #CommandDeleteReading(undef, "$name observeFailedDev");
  readingsSingleUpdate($hash, "observeFailedDev", "", 0);
  my %functionHash = (hash => $hash, function => "observe");
  RemoveInternalTimer(\%functionHash);
  InternalTimer(gettimeofday() + 1, "EnOcean_observeRepeat", \%functionHash, 0);
  Log3 $name, 4, "EnOcean set " . join(" ", @cmdValue) . " observing started";
  return ($err, $ctrl);
}
  
#
sub EnOcean_observeParse($$@)
{
  # observe acknowledge
  my ($ctrl, $hash, @cmdValue) = @_;
  my ($err, $name) = (undef, $hash->{NAME});
  return (undef, $ctrl) if (lc(AttrVal($name, "observe", "off")) eq "off");
  # observing disabled or ignore second and following acknowledgment telegrams
  return (undef, $ctrl) if (!exists($hash->{helper}{observeRefDev}) || @{$hash->{helper}{observeRefDev}} == 0);
  my $devName = shift @cmdValue;
  my $cmd = shift @cmdValue;
  $cmd = shift @cmdValue if ($cmd eq "state");
  my ($observeRefDevIdx) = grep{$hash->{helper}{observeRefDev}[$_] eq $devName} 0..$#{$hash->{helper}{observeRefDev}};
  # device not observed
  return (undef, $ctrl) if (!defined $observeRefDevIdx);
  Log3 $name, 4, "EnOcean $name < observeRefDev " . join(" ", @{$hash->{helper}{observeRefDev}}) . " parsed";    
  Log3 $name, 4, "EnOcean $name < $devName $cmd " . join(" ", @cmdValue) . " received";

  if (@{$hash->{helper}{observeRefDev}} == 1) {
    # last acknowledgment telegram stops observing
    delete $hash->{helper}{observeCmds};
    delete $hash->{helper}{observeCntr};
    delete $hash->{helper}{observeRefDev};
    delete $hash->{helper}{lastCmdFunction};
    delete $hash->{helper}{lastCmdValue};
    my %functionHash = (hash => $hash, function => "observe");
    RemoveInternalTimer(\%functionHash);
    Log3 $name, 4, "EnOcean $name < $devName $cmd " . join(" ", @cmdValue) . " observing stoped";
  } else {
    # remove the device that has sent a telegram
    Log3 $name, 4, "EnOcean $name < observeRefDev " . $hash->{helper}{observeRefDev}[$observeRefDevIdx] . " removed";    
    splice(@{$hash->{helper}{observeRefDev}}, $observeRefDevIdx, 1);

    if (lc(AttrVal($name, "observeLogic", "or")) eq "and") {    
      # AND logic: remove the device that has sent a telegram and await further telegrams  
      Log3 $name, 4, "EnOcean $name < observeRefDev " . join(" ", @{$hash->{helper}{observeRefDev}}) . " observing continued";    

    } else {
    # OR logic: last acknowledgment telegram stops observing
      #shift @{$hash->{helper}{observeRefDev}};
      delete $hash->{helper}{observeCmds};
      delete $hash->{helper}{observeCntr};
      delete $hash->{helper}{observeRefDev};
      delete $hash->{helper}{lastCmdFunction};
      delete $hash->{helper}{lastCmdValue};
      my %functionHash = (hash => $hash, function => "observe");
      RemoveInternalTimer(\%functionHash);
      Log3 $name, 4, "EnOcean $name < $devName $cmd " . join(" ", @cmdValue) . " observing stoped";
    }
  }

#  if (defined($hash->{helper}{lastCmdValue}[1]) && $hash->{helper}{lastCmdValue}[1] eq $cmd) {
    # acknowledgment telegram ok, cancel the repetition of the command
    
#  } else {
    # acknowledgment telegram does not match the telegram sent, cancel the repetition of the command

#  }    
  return ($err, $ctrl);
}

#    
sub EnOcean_observeRepeat($)
{
  #timer expires without acknowledgment telegram, repeat command
  my ($functionHash) = @_;
  my $hash = $functionHash->{hash};
  my $name = $hash->{NAME}; 
  return if (AttrVal($name, "observe", "off") eq "off" || !defined($hash->{helper}{observeCntr}));
  
  #my @observeExeptions = split("[ \t][ \t]*", AttrVal($name, "observeExeptions", ""));
  if ($hash->{helper}{observeCntr} <= AttrVal($name, "observeCmdRepetition", 2)) {
    #repeat last command
    $hash->{helper}{observeCntr} += 1;
    Log3 $name, 4, "EnOcean set " . join(" ", @{$hash->{helper}{lastCmdValue}}) . " repeated";
    EnOcean_Set($hash, @{$hash->{helper}{lastCmdValue}});
    RemoveInternalTimer($functionHash);
    InternalTimer(gettimeofday() + 1, "EnOcean_observeRepeat", $functionHash, 0);
  } else {
    # reached the maximum number of retries, clear last command
    Log3 $name, 2, "EnOcean set " . join(" ", @{$hash->{helper}{lastCmdValue}}) .
                   " observing " . join(" ", @{$hash->{helper}{observeRefDev}}) . " failed";
    #splice(@{$hash->{helper}{observeRefDev}}, 0);
    my $actionCmd = AttrVal($name, "observeErrorAction", undef);    
    if (defined $actionCmd) {
      # error action exec
      my %specials= (
                "%NAME" => shift(@{$hash->{helper}{lastCmdValue}}),
                "%FAILEDDEV" => join(" ", @{$hash->{helper}{observeRefDev}}),
                "%TYPE"  => $hash->{TYPE},
                "%EVENT" => ReplaceEventMap($name, join(" ", @{$hash->{helper}{lastCmdValue}}), 1)
      );
      $actionCmd = EvalSpecials($actionCmd, %specials);
      my $ret = AnalyzeCommandChain(undef, $actionCmd);
      Log3 $name, 2, "$name: $ret" if($ret);
    }
    readingsSingleUpdate($hash, "observeFailedDev", join(" ", @{$hash->{helper}{observeRefDev}}), 1);
    delete $hash->{helper}{observeCmds};
    delete $hash->{helper}{observeCntr};
    delete $hash->{helper}{observeRefDev};
    delete $hash->{helper}{lastCmdFunction};
    delete $hash->{helper}{lastCmdValue};
    RemoveInternalTimer($functionHash);
  }
  return;
}
#
sub EnOcean_energyManagement_01Parse($@)
{
  my ($hash, @db) = @_;
  my $name = $hash->{NAME};
  # [drLevel] = 15 : no requests for reduction in power consumptions
  my $drLevel = ($db[0] & 0xF0) >> 4;
  my $powerUsage = $db[2] & 0x7F;
  my $powerUsageLevel = $db[0] & 1 ? "max" : "min";
  my $powerUsageScale = $db[2] & 0x80 ? "rel" : "max";
  my $randomStart = $db[0] & 4 ? "yes" : "no";
  my $randomEnd = $db[0] & 2 ? "yes" : "no";
  my $randomTime = rand(AttrVal($name, "demandRespRandomTime", 1));
  my $setpoint = $db[3];
  my $timeout = $db[1] * 15 * 60;
  $randomTime = $randomTime > $timeout && $timeout > 0 ? rand($timeout) : rand($randomTime);
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "randomEnd", $randomEnd);
  readingsBulkUpdate($hash, "randomStart", $randomStart);
  my %timeoutHash = (hash => $hash, function => "demandResponseTimeout");
  my %functionHash = (hash            => $hash,
                      function        => "demandResponseExec",
                      drLevel         => $drLevel,
                      powerUsage      => $powerUsage,
                      powerUsageLevel => $powerUsageLevel,
                      powerUsageScale => $powerUsageScale,
                      setpoint        => $setpoint
                     );      
  RemoveInternalTimer(\%timeoutHash);
  RemoveInternalTimer(\%functionHash);
  if ($timeout > 0 && $drLevel < 15) {
    # timeout timer
    InternalTimer(gettimeofday() + $timeout, "EnOcean_demandResponseTimeout", \%timeoutHash, 0);
    my ($sec, $min, $hour, $day, $month, $year) = localtime(time + $timeout);
    $month += 1;
    $year += 1900;
    $min = $min < 10 ? $min = "0" . $min : $min;
    $hour = $hour < 10 ? $hour = "0" . $hour : $hour;
    $day = $day < 10 ? $day = "0" . $day : $day;
    $month = $month < 10 ? $ month = "0". $month : $month;
    readingsBulkUpdate($hash, "timeout", "$year-$month-$day $hour:$min:$sec");
  } else {
    CommandDeleteReading(undef, "$name timeout");    
  }
  if ($randomStart eq "yes" && ReadingsVal($name, "level", 15) == 15) {
    readingsBulkUpdate($hash, "state", "waiting_for_start");
    Log3 $name, 3, "EnOcean set $name demand response waiting for start";
    InternalTimer(gettimeofday() + $randomTime, "EnOcean_demandResponseExec", \%functionHash, 0);      
  } elsif ($randomEnd eq "yes" && ReadingsVal($name, "level", 15) < 15) {
    readingsBulkUpdate($hash, "state", "waiting_for_stop");
    Log3 $name, 3, "EnOcean set $name demand response waiting for stop";
    InternalTimer(gettimeofday() + $randomTime, "EnOcean_demandResponseExec", \%functionHash, 0);        
  } else {
    EnOcean_demandResponseExec(\%functionHash);
  }
  readingsEndUpdate($hash, 1);
  return;
}

#
sub EnOcean_demandResponseExec($)
{
  my ($functionHash) = @_;
  my $function = $functionHash->{function};
  my $hash = $functionHash->{hash};
  my $drLevel = $functionHash->{drLevel};
  my $powerUsage = $functionHash->{powerUsage};
  my $powerUsageLevel = $functionHash->{powerUsageLevel};  
  my $powerUsageScale = $functionHash->{powerUsageScale};
  my $setpoint = $functionHash->{setpoint};
  my $name = $hash->{NAME}; 
  my $actionCmd = AttrVal($name, "demandRespAction", undef);
  # save old values
  $hash->{helper}{drLevel} = ReadingsVal($name, "level", 15);
  $hash->{helper}{powerUsage} = ReadingsVal($name, "powerUsage", 100);
  $hash->{helper}{powerUsageLevel} = ReadingsVal($name, "powerUsageLevel", "max");
  $hash->{helper}{powerUsageScale} = ReadingsVal($name, "powerUsageScale", "max");
  $hash->{helper}{setpoint} = ReadingsVal($name, "setpoint", 255); 
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "level", $drLevel);
  readingsBulkUpdate($hash, "powerUsage", $powerUsage);
  readingsBulkUpdate($hash, "powerUsageLevel", $powerUsageLevel);
  readingsBulkUpdate($hash, "powerUsageScale", $powerUsageScale);
  readingsBulkUpdate($hash, "setpoint", $setpoint);
  if ($drLevel == 15) {
    readingsBulkUpdate($hash, "state", "off");
    Log3 $name, 3, "EnOcean set $name demand response off";
  } else {
    readingsBulkUpdate($hash, "state", "on");
    Log3 $name, 3, "EnOcean set $name demand response on";
  }
  readingsEndUpdate($hash, 1);
  if (defined $actionCmd) {
    # action exec
#    my %specials= ("%NAME"  => $name,
#                   "%TYPE"  => $hash->{TYPE},
#                   "%EVENT" => "$drLevel $setpoint $powerUsage $powerUsageScale $powerUsageLevel"
#                  );
    my %specials= ("%NAME"  => $name,
                   "%TYPE"  => $hash->{TYPE},
                   "%LEVEL"  => $drLevel,                   
                   "%SETPOINT"  => $setpoint,
                   "%POWERUSAGE"  => $powerUsage,
                   "%POWERUSAGESCALE"  => $powerUsageScale,
                   "%POWERUSAGELEVEL"  => $powerUsageLevel,
                   "%STATE" => ReadingsVal($name, "state", "off")
                  );
    $actionCmd = EvalSpecials($actionCmd, %specials);
    my $ret = AnalyzeCommandChain(undef, $actionCmd);
    Log3 $name, 2, "$name: $ret" if($ret);
  }
  return;
}

#
sub EnOcean_demandResponseTimeout($)
{
  my ($functionHash) = @_;
  my $function = $functionHash->{function};
  my $hash = $functionHash->{hash};
  my $name = $hash->{NAME};
  my $actionCmd = AttrVal($name, "demandRespAction", undef);
  my $data;
  my $timeoutLevel = AttrVal($name, "demandRespTimeoutLevel", "max");
  RemoveInternalTimer($functionHash);
  CommandDeleteReading(undef, "$name timeout");
  my $drLevel = 15;
  my $powerUsage = 100;
  my $powerUsageLevel = "max";
  my $powerUsageScale = "max";
  my $setpoint = 255;
  my $timeout = 0;
  if ($timeoutLevel eq "last" && defined($hash->{helper}{drLevel})) {
    # restore old values
    $drLevel = $hash->{helper}{drLevel};
    $powerUsage = $hash->{helper}{powerUsage};
    $powerUsageScale = $hash->{helper}{powerUsageLevel};
    $powerUsageLevel = $hash->{helper}{powerUsageScale};
    $setpoint = $hash->{helper}{setpoint}; 
  }
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "level", $drLevel);
  readingsBulkUpdate($hash, "powerUsage", $powerUsage);
  readingsBulkUpdate($hash, "powerUsageLevel", $powerUsageLevel);
  readingsBulkUpdate($hash, "powerUsageScale", $powerUsageScale);
  readingsBulkUpdate($hash, "setpoint", $setpoint);
  if ($drLevel == 15) {
    readingsBulkUpdate($hash, "state", "off");
    Log3 $name, 3, "EnOcean set $name demand response off";
  } else {
    readingsBulkUpdate($hash, "state", "on");
    Log3 $name, 3, "EnOcean set $name demand response on";
  }
  readingsEndUpdate($hash, 1);
  #my %specials= ("%NAME"  => $name,
  #               "%TYPE"  => $hash->{TYPE},
  #               "%EVENT" => "$drLevel $setpoint $powerUsage $powerUsageScale $powerUsageLevel"
  #              );
    my %specials= ("%NAME"  => $name,
                   "%TYPE"  => $hash->{TYPE},
                   "%LEVEL"  => $drLevel,                   
                   "%SETPOINT"  => $setpoint,
                   "%POWERUSAGE"  => $powerUsage,
                   "%POWERUSAGESCALE"  => $powerUsageScale,
                   "%POWERUSAGELEVEL"  => $powerUsageLevel,
                   "%STATE" => ReadingsVal($name, "state", "off")
                  );
  $powerUsageLevel = $powerUsageLevel eq "max" ? 1 : 0;
  $powerUsageScale = $powerUsageScale eq "rel" ? 0x80 : 0;
  my $randomStart = ReadingsVal($name, "randomStart", "no") eq "yes" ? 4 : 0;
  my $randomEnd = ReadingsVal($name, "randomEnd", "no") eq "yes" ? 2 : 0;
  $data = sprintf "%02X%02X%02X%02X", $setpoint, $powerUsageScale | $powerUsage, $timeout,
                                      $drLevel << 4 | $randomStart | $randomEnd | $powerUsageLevel | 8;
  #EnOcean_SndRadio(undef, $hash, $packetType, $rorg, $data, $subDef, $status, $destinationID);
  EnOcean_SndRadio(undef, $hash, 1, "A5", $data, AttrVal($name, "subDef", $hash->{DEF}), "00", "FFFFFFFF");

  if (defined $actionCmd) {
    # action exec
    $actionCmd = EvalSpecials($actionCmd, %specials);
    my $ret = AnalyzeCommandChain(undef, $actionCmd);
    Log3 $name, 2, "$name: $ret" if($ret);
  }
  return;
}

# Send UTE Teach-In Telegrams
sub EnOcean_sndUTE($$$$$$$) {
  my ($ctrl, $hash, $comMode, $responseRequest, $teachInReq, $devChannel, $eep) = @_;
  my $name = $hash->{NAME};
  my ($err, $data) = (undef, "");
  my $IODev = $defs{$name}{IODev}{NAME};
  my $IOHash = $defs{$IODev};
  my @db = (undef, undef, undef, "07", "FF", $devChannel);
  if ($eep =~ m/^(..)-(..)-(..)$/) {
    ($db[0], $db[1], $db[2]) = ($1, $2, $3);
  } else {
    return (1, undef, undef);
  }
  # set unidir/bidir operation
  $db[6] |= $comMode eq "biDir" ? 0x80 : 0;
  CommandAttr(undef, "$name comMode $comMode");
  # set teach mode
  if ($teachInReq eq "out") {
    $db[6] |= 0x10;
  } elsif ($teachInReq eq "inout") {
    $db[6] |= 0x20;  
  }
  # set response message mode
  if ($responseRequest eq "no") {
    $db[6] |= 0x40;
    readingsSingleUpdate($hash, "teach-in", "EEP $eep UTE query sent", 1);
  } else {
    # set flag for response request, 
    if ($teachInReq eq "in") {
      $IOHash->{helper}{UTERespWait}{$hash->{DEF}}{teachInReq} = $teachInReq;
      $IOHash->{helper}{UTERespWait}{$hash->{DEF}}{hash} = $hash;
    } elsif ($teachInReq eq "out") {
      $IOHash->{helper}{UTERespWait}{AttrVal($name, "subDef", $hash->{DEF})}{teachInReq} = $teachInReq;
      $IOHash->{helper}{UTERespWait}{AttrVal($name, "subDef", $hash->{DEF})}{hash} = $hash;
    } elsif ($teachInReq eq "inout") {
      $IOHash->{helper}{UTERespWait}{$hash->{DEF}}{teachInReq} = $teachInReq;
      $IOHash->{helper}{UTERespWait}{$hash->{DEF}}{hash} = $hash;
    }
    readingsSingleUpdate($hash, "teach-in", "EEP $eep UTE query sent, response requested", 1);
    if (!exists($IOHash->{Teach})) {
      # enable teach-in receiving for 3 sec
      $IOHash->{Teach} = 1;
      my %timeoutHash = (hash => $IOHash, function => "UTERespTimeout");
      RemoveInternalTimer(\%timeoutHash);
      InternalTimer(gettimeofday() + 3, "EnOcean_UTERespTimeout", \%timeoutHash, 0);
    }
  }
  CommandAttr(undef, "$name devChannel $devChannel");
  CommandAttr(undef, "$name eep $eep");
  CommandAttr(undef, "$name manufID 7FF");  
  $data = sprintf "%02X%s%s%s%s%s%s", $db[6], $db[5], $db[4], $db[3], $db[2], $db[1], $db[0];
  return ($err, "D4", $data);
}

#
sub EnOcean_UTERespTimeout($)
{
  my ($functionHash) = @_;
  my $function = $functionHash->{function};
  my $hash = $functionHash->{hash};
  my $name = $hash->{NAME};
  delete $hash->{Teach};
  return;
}

#
sub EnOcean_cdmClear($)
{
  my ($functionHash) = @_;
  my $function = $functionHash->{function};
  my $hash = $functionHash->{hash};
  delete $hash->{helper}{cdm};
  return;
}

# Parse Secure Teach-In Telegrams
sub EnOcean_sec_parseTeachIn($$$$) {
  my ($hash, $telegram, $subDef, $destinationID) = @_;
  my $name = $hash->{NAME};
  my ($err, $response, $logLevel);    
  my $rlc; # Rolling code
  my $key1; # First part of private key
  my $key2; # Second part of private key

	# Extract byte fields from telegram
	# TEACH_IN_INFO, SLF, RLC/KEY/variable
	$telegram =~ /^(..)(..)(.*)/;	# TODO Parse error handling?
	my $teach_bin = unpack('B8',pack('H2', $1));	# Parse as ASCII HEX, unpack to bitstring
	my $slf_bin = unpack('B8',pack('H2', $2));	# Parse as ASCII HEX, unpack to bitstring
	my $crypt = $3;
    
	# Extract bit fields from teach-in info field
	# IDX, CNT, PSK, TYPE, INFO
	$teach_bin =~ /(..)(..)(.)(.)(..)/;	# TODO Parse error handling?
	my $idx = unpack('C',pack('B8', '000000'.$1));	# Padd to byte, parse as unsigned char
	my $cnt = unpack('C',pack('B8', '000000'.$2));  # Padd to byte, parse as unsigned char
	my $psk = $3;
	my $type = $4;
	my $info = unpack('C',pack('B8', '000000'.$5)); # Padd to byte, parse as unsigned char
    
	# Extract bit fields from SLF field
	# RLC_ALGO, RLC_TX, MAC_ALGO, DATA_ENC
	$slf_bin =~ /(..)(.)(..)(...)/;	# TODO Parse error handling?
	my $rlc_algo = unpack('C',pack('B8', '000000'.$1));	# Padd to byte, parse as unsigned char
	my $rlc_tx = $2;
	my $mac_algo = unpack('C',pack('B8', '000000'.$3));	# Padd to byte, parse as unsigned char
	my $data_enc = unpack('C',pack('B8', '00000'.$4));	# Padd to byte, parse as unsigned char
    
	#print "IDX: $idx, CNT: $cnt, PSK: $psk, TYPE: $type, INFO: $info\n";
	
	# The teach-in information is split in two telegrams due to the ERP1 limitations on telegram length
	# So we should get a telegram with index 0 and count 2 with the first half of the infos needed
	if ($idx == 0 && $cnt == 2) {
	  # First part of the teach in message
	  #print "First part of 2 part teach in message received\n";
          #print "RLC_ALGO: $rlc_algo, RLC_TX: $rlc_tx, MAC_ALGO: $mac_algo, DATA_ENC: $data_enc\n";
	  #print "RLC and KEY are ". ($psk == 1 ? "" : "not") . " encrypted\n";
	  #print "Application is ". ($type == 1 ? "a PTM" : "non-specfic") . "\n";
        
	  # Decode teach in type
	  if ($type == 0) {
	    # UTE teach-in expected
            if ($info == 0) {
              $attr{$name}{comMode} = "uniDir";
    	      $attr{$name}{secMode} = "rcv";  
            } else {
              $attr{$name}{comMode} = "biDir";
              $attr{$name}{secMode} = "biDir";
            }
	  } else {
	    # switch teach-in
            if ($info == 0) {
              $attr{$name}{comMode} = "uniDir";
              $attr{$name}{eep} = "D2-03-00";
              $attr{$name}{manufID} = "7FF";
    	      $attr{$name}{secMode} = "rcv";  
              foreach my $attrCntr (keys %{$EnO_eepConfig{"D2.03.00"}{attr}}) {
                $attr{$name}{$attrCntr} = $EnO_eepConfig{"D2.03.00"}{attr}{$attrCntr};
	      }
              readingsSingleUpdate($hash, "teach-in", "EEP D2-03-00 Manufacturer: " . $EnO_manuf{"7FF"}, 1);
              Log3 $name, 2, "EnOcean $name teach-in EEP D2-03-00 Rocker A Manufacturer: " . $EnO_manuf{"7FF"};                         
            } else {
              $attr{$name}{comMode} = "uniDir";
              $attr{$name}{eep} = "D2-03-00";
              $attr{$name}{manufID} = "7FF";
    	      $attr{$name}{secMode} = "rcv";  
              foreach my $attrCntr (keys %{$EnO_eepConfig{"D2.03.00"}{attr}}) {
                $attr{$name}{$attrCntr} = $EnO_eepConfig{"D2.03.00"}{attr}{$attrCntr};
              }
              readingsSingleUpdate($hash, "teach-in", "EEP D2-03-00 Manufacturer: " . $EnO_manuf{"7FF"}, 1);
              Log3 $name, 2, "EnOcean $name teach-in EEP D2-03-00 Rocker B Manufacturer: " . $EnO_manuf{"7FF"};                         
            }
	  }
        
		# Decode RLC algorithm and extract RLC and private key (only first part most likely)
		if ($rlc_algo == 0) {
			# No RLC used in telegram or internally in memory, use case untested
			return ("Secure modes without RLC not tested or supported", undef);
		} elsif ($rlc_algo == 1) {
			# "RLC= 2-byte long. RLC algorithm consists on incrementing in +1 the previous RLC value
            
			# Extract RLC and KEY fields from data trailing SLF field
			# RLC, KEY, ID, STATUS
			$crypt =~ /^(....)(.*)$/;
			$rlc = $1;
			$key1 = $2;
            
			#print "RLC: $rlc\n";
			#print "Part 1 of KEY: $key1\n";
			
			# Store in device hash
			$attr{$name}{rlcAlgo} = '2++';
                        readingsSingleUpdate($hash, ".rlcRcv", $rlc, 0);
			# storing backup copy
			$attr{$name}{rlcRcv} = $rlc;
			$attr{$name}{keyRcv} = $key1;
            
		} elsif ($rlc_algo == 2) {
			# RLC= 3-byte long. RLC algorithm consists on incrementing in +1 the previous RLC value

			# Extract RLC and KEY fields from data trailing SLF field
			# RLC, KEY, ID, STATUS
			$crypt =~ /^(......)(.*)$/;
			$rlc = $1;
			$key1 = $2;
            
			#print "RLC: $rlc\n";
			#print "Part 1 of KEY: $key1\n";

			# Store in device hash            
			$attr{$name}{rlcAlgo} = '3++';
                        readingsSingleUpdate($hash, ".rlcRcv", $rlc, 0);
			# storing backup copy
			$attr{$name}{rlcRcv} = $rlc;
			$attr{$name}{keyRcv} = $key1;
		} else {
			# Undefined RLC algorithm
			return ("Undefined RLC algorithm $rlc_algo", undef);
		}
        
		# RLC Transmission
		if ($rlc_tx == 0 ) {
			# Secure operation mode telegrams do not contain RLC, we store and track it ourself
			$attr{$name}{rlcTX} = 'false';
		} else {
			# Secure operation mode messages contain RLC, CAUTION untested
			$attr{$name}{rlcTX} = 'true';
		}
        
		# Decode MAC Algorithm
		if ($mac_algo == 0) {
			# No MAC included in the secure telegram
			# Doesn't make sense for RLC senders like the PTM215, as we can't verify the RLC then...
			#$attr{$name}{macAlgo} = 'no';
			return ("Secure mode without MAC algorithm unsupported", undef);
		} elsif ($mac_algo == 1) {
			# CMAC is a 3-byte-long code
			$attr{$name}{macAlgo} = '3';
		} elsif ($mac_algo == 2) {
			# MAC is a 4-byte-long code
			$attr{$name}{macAlgo} = '4';
		} else {
			# Undefined MAC algorith;
			# Nothing we can do either...
			#$attr{$name}{macAlgo} = 'no';
			return ("Undefined MAC algorithm $mac_algo", undef);
		}
        
		# Decode data encryption algorithm
		if ($data_enc == 0) {
			# Data not encrypted? Right now we will handle this like an error, concrete use case untested
			#$attr{$name}{secLevel} = 'encapsulation';
			return ("Secure mode message without data encryption unsupported", undef);
		} elsif ($data_enc == 1) {
			# Unspecified
			return ("Undefined data encryption algorithm $data_enc", undef);
		} elsif ($data_enc == 2) {
			# Unspecified
			return ("Undefined data encryption algorithm $data_enc", undef);
		} elsif ($data_enc == 3) {
			# Data will be encrypted/decrypted XORing with a string obtained from a AES128 encryption
			$attr{$name}{dataEnc} = 'VAES';
			$attr{$name}{secLevel} = 'encryption';
		} elsif ($data_enc == 4) {
			# Data will be encrypted/decrypted using the AES128 algorithm in CBC mode
			# Might be used in the future right now untested
			#$attr{$name}{dataEnc} = 'AES-CBC';
			#$attr{$name}{secLevel} = 'encryption';
			return ("Secure mode message with AES-CBC data encryption unsupported", undef);
		} else {
			# Something went horribly wrong
			return ("Could not parse data encryption information, $data_enc", undef);
		}
        
		# Ok we got a lots of infos and the first part of the private key
		return (undef, "part1: $name");
	} elsif ($idx == 1 && $cnt == 0) {
	  # Second part of the teach-in telegrams

	  # Extract byte fields from telegram
	  # Don't care about info fields, KEY, ID, don't care about status
	  $telegram =~ /^..(.*)$/;	# TODO Parse error handling?
	  $key2 = $1;

	  # We already should have gathered the infos from the first teach-in telegram
	  if (!defined($attr{$name}{keyRcv})) {
	    # We have missed the first telegram
	    return ("Missing first teach-in telegram", undef);
	  }

	  # Append second part of private key to first part of private key
	  $attr{$name}{keyRcv} .= $key2;
	  
	  if ($attr{$name}{secMode} eq "biDir") {
            # bidirectional secure teach-in
            if (!defined $subDef) {
              $subDef = EnOcean_CheckSenderID("getNextID", $defs{$name}{IODev}{NAME}, "00000000");
              $attr{$name}{subDef} = $subDef;
            }
            ($err, $response, $logLevel) = EnOcean_sec_createTeachIn(undef, $hash, $attr{$name}{comMode},
                                                                     $attr{$name}{dataEnc}, $attr{$name}{eep},
                                                                     $attr{$name}{macAlgo}, $attr{$name}{rlcAlgo},
                                                                     $attr{$name}{rlcTX}, $attr{$name}{secLevel},
                                                                     $subDef, $destinationID);
            if ($err) {
              Log3 $name, $logLevel, "EnOcean $name Error: $err";
              return $err;
            } else {
              Log3 $name, $logLevel, "EnOcean $name $response";
            }
          }
          # We're done
	  return (undef, "part2: $name");
	}

	# Sequence error?
	return ("teach-in sequence error IDC: $idx CNT: $cnt", undef);
}

# Do VAES decyrption
# All parameters need to be passed as byte strings
#
# Parameter 1: Current rolling code, 16 bytes
# Parameter 2: Private key, 16bytes
# Paremeter 3: Encrypted data, 16bytes
#
# Returns: Decrypted data, 16 bytes
#
# Decryption of more than 16bytes of data is currently unsupported 
#
sub EnOcean_sec_decodeVAES($$$) {
	my $rlc = $_[0];
	my $private_key = $_[1];
	my $data_enc = $_[2];
	# Public key according to EnOcean Security specification
	my $public_key = pack('H32', '3410de8f1aba3eff9f5a117172eacabd');

        # Input for VAES
        my $aes_in = $public_key ^ $rlc;

	#print "--\n";
        #print "Public Key  ".unpack('H32', $public_key)."\n";
        #print "RLC         ".unpack('H32', $rlc)."\n";
        #print "AES input   ".unpack('H32', $aes_in)."\n";
	#print "--\n";
        #print "Private Key ".unpack('H32', $private_key)."\n";

        my $cipher = Crypt::Rijndael->new( $private_key );
        my $aes_out = $cipher->encrypt($aes_in);

        #print "AES output  ".unpack('H32', $aes_out)."\n";
        #print "Data_enc:   ".unpack('H32', $data_enc)."\n";

        my $data_dec = $data_enc ^ $aes_out;

        #print "Data_dec:   ".unpack('H32', $data_dec)."\n";
	return $data_dec;
}

# Returns current RLC in hex format and increments the stored RLC
# Checks the boundaries of the RLC for roll-over
# 
# Parameter 1: Sender ID in hexadecimal format for lookup in receivers hash
#
# Affects: receivers hash
#
# Returns: RLC in hexadecimal format
#
sub EnOcean_sec_getRLC($$) {
	my $hash = $_[0];
	my $rlcVar = $_[1];
        my $name = $hash->{NAME};

	# Fetch newest RLC from receiver hash
	my $old_rlc = ReadingsVal($name, "." . $rlcVar, $attr{$name}{$rlcVar});
	if (hex($old_rlc) < hex($attr{$name}{$rlcVar})) {
	  $old_rlc = $attr{$name}{$rlcVar};
	}

	#print "RLC old: $old_rlc\n";
	Log3 $name, 5, "EnOcean $name EnOcean_sec_getRLC RLC old: $old_rlc";

	# Advance RLC by one
	my $new_rlc = hex($old_rlc) + 1;

	# Boundary check
	if ($attr{$name}{rlcAlgo} eq '2++') {
		if ($new_rlc > 65535) {
			#print "RLC rollover\n";
			Log3 $name, 5, "EnOcean $name EnOcean_sec_getRLC RLC rollover";
			$new_rlc = 0;
		        $attr{$name}{$rlcVar} = "0000";
                        CommandSave(undef, undef);
		}
		readingsSingleUpdate($hash, "." . $rlcVar, uc(unpack('H4',pack('n', $new_rlc))), 0);
		$attr{$name}{$rlcVar} = uc(unpack('H4',pack('n', $new_rlc)));
	} elsif ($attr{$name}{rlcAlgo} eq '3++') {
		if ($new_rlc > 16777215) {
			#print "RLC rollover\n";
			Log3 $name, 5, "EnOcean $name EnOcean_sec_getRLC RLC rollover";
			$new_rlc = 0;
		        $attr{$name}{$rlcVar} = "000000";
                        CommandSave(undef, undef);			
		}
                readingsSingleUpdate($hash, "." . $rlcVar, uc(unpack('H6',pack('N', $new_rlc))), 0);
		$attr{$name}{$rlcVar} = uc(unpack('H6',pack('N', $new_rlc)));
	}
	
	#print "RLC new: ".$attr{$name}{rlc}."\n";
	Log3 $name, 5, "EnOcean $name EnOcean_sec_getRLC RLC new: ". $attr{$name}{$rlcVar};
	return $old_rlc;
}

# Generate MAC of data
# 
# Parameter 1: private key as byte string, 16bytes
# Parameter 2: data fro which mac should be calculated in hexadecimal format, len variable
# Parameter 3: length of MAC to be generated in bytes
#
# Returns: MAC in hexadecimal format
#
# This function currently supports data with lentgh of less then 16bytes, 
# MAC for longer data is untested but specified
#
sub EnOcean_sec_generateMAC($$$) {
	my $private_key = $_[0];
	my $data = $_[1];
	my $cmac_len = $_[2];

	#print "Calculating MAC for data $data\n";
        Log3 undef, 5, "EnOcean_sec_generateMAC Calculating MAC for data $data";                         
	Log3 undef, 5, "EnOcean_sec_generateMAC private key ".unpack('H32', $private_key);
	
	# Pack data to 16byte byte string, padd with 10..0 binary
	my $data_expanded = pack('H32', $data.'80');

	#print "Exp. data  ".unpack('H32', $data_expanded)."\n";
	
	# Constants according to specification
	my $const_zero = pack('H32','00');
	my $const_rb = pack('H32', '00000000000000000000000000000087');
	
	# Encrypt zero data with private key to get L
	my $cipher = Crypt::Rijndael->new($private_key);
        my $l = $cipher->encrypt($const_zero);
	#print "L          ".unpack('H32', $l)."\n";
	#print "L          ".unpack('B128', $l)."\n";
	
	# Expand L to 128bit string
	my $l_bit = unpack('B128', $l);
	
	# K1 and K2 stored as 128bit string
	my $k1_bit;
	my $k2_bit;
	
	# K1 and K2 as binary 
	my $k1;
	my $k2;
	
	# Store L << 1 in K1
	$l_bit =~ /^.(.{127})/;
	$k1_bit = $1.'0';
	$k1 = pack('B128', $k1_bit);

	# If MSB of L == 1, K1 = K1 XOR const_Rb
	if($l_bit =~ m/^1/) {
		#print "MSB of L is set\n";
		$k1 = $k1 ^ $const_rb;
		$k1_bit = unpack('B128', $k1);
	} else {
		#print "MSB of L is unset\n";
	}

	# Store K1 << 1 in K2
	$k1_bit =~ /^.(.{127})/;
	$k2_bit = $1.'0';
	$k2 = pack('B128', $k2_bit);

	# If MSB of K1 == 1, K2 = K2 XOR const_Rb
	if($k1_bit =~ m/^1/) {
		#print "MSB of K1 is set\n";
		$k2 = $k2 ^ $const_rb;
	} else {
		#print "MSB of K1 is unset\n";
	}
	
	# XOR data with K2
	$data_expanded ^= $k2;

	# Encrypt data
	my $cmac = $cipher->encrypt($data_expanded);

	#print "CMAC ".unpack('H32', $cmac)."\n";
        Log3 undef, 5, "EnOcean_sec_generateMAC CMAC ".unpack('H32', $cmac);                         
	
	# Extract specified len of MAC
	my $cmac_pattern = '^(.{'.($cmac_len * 2).'})';
	unpack('H32', $cmac) =~ /$cmac_pattern/;
	Log3 undef, 5, "EnOcean_sec_generateMAC cutted CMAC ".unpack('H32', $1);
	
	# Return MAC in hexadecimal format
	return uc($1);
}

# Verify (MAC) and decode/decrypt secure mode message
#
# Parameter 1: content of radio telegram in hexadecimal format
# 
# Returns: "ERROR-" + error description, "OK-" + EEP D2-03-00 telegram in hexadecimal format
#
# Right now we only decode PTM215 telegrams which are transmitted as RORG 30 and without
# encapsulation. Encapsulation of other telegrams is possible and specified but untested due to the
# lack of hardware suporting this. 
#
sub EnOcean_sec_convertToNonsecure($$$) {
	my ($hash, $rorg, $crypt_data) = @_;
        my $name = $hash->{NAME};
        if ($cryptFunc == 0) {
	  return ("Cryptographic functions are not available", undef, undef);        
        }
        my $private_key;
        
	# Prefix of pattern to extract the different cryptographic infos
	my $crypt_pattern = "^(.*)";;
	
	# Flags and infos for fields to expect
	my $expect_rlc = 0;
	my $expect_mac = 0;
	my $mac_len;
	my $expect_enc = 0;

    # Check if the RORG is supported
    if ($rorg ne '30') {
        return ("RORG $rorg unsupported", undef, undef);
    }
	#$attr{$name}{rlcAlgo} = '2++';
	# Check if RLC is transmitted and when, which length to expect
	if($attr{$name}{rlcTX} eq 'true') {
		# Message should contain RLC
		if ($attr{$name}{rlcAlgo} eq '2++') {
			$crypt_pattern .= "(....)";
			$expect_rlc = 1;
		} elsif ($attr{$name}{rlcAlgo} eq '3++') {
			$crypt_pattern .= "(......)";
			$expect_rlc = 1; 
		} else {
			# RLC_TX but no info on RLC length
			return ("RLC_TX and RLC_ALGO inconsistent", undef, undef);
		}
	}

	# Check what length of MAC to expect
	if($attr{$name}{macAlgo} eq '3') {
		$crypt_pattern .= "(......)";
		$mac_len = 3;
		$expect_mac = 1;
	} elsif ($attr{$name}{macAlgo} eq '4') {
		$crypt_pattern .= "(........)";
		$mac_len = 4;
		$expect_mac = 1;
	} else {
		# According to the specification it's possible to transmit no MAC, bt we don't implement this for now
		return ("Secure mode messages without MAC unsupported", undef, undef);
	}
	
	# Suffix for crypt pattern
	$crypt_pattern .= '$';

	#print "Crypt_pattern: $crypt_pattern\n";
	
	# Extract byte fields from message payload
	$crypt_data =~ /$crypt_pattern/;
	my $data_enc = $1;
	my $rlc;
	my $mac;
	if ($expect_rlc == 1 && $expect_mac == 1) {
		$rlc = $2;
		$mac = $3;
	} elsif ($expect_rlc == 0 && $expect_mac == 1) {
		$mac = $2;
	}
	
	#print "DATA: $data_enc\n";
        Log3 $name, 5, "EnOcean $name EnOcean_sec_convertToNonsecure DATA: $data_enc";                         
	#if ($expect_rlc == 1) { print "RLC: $rlc\n";};
	if ($expect_rlc == 1) { Log3 $name, 5, "EnOcean $name EnOcean_sec_convertToNonsecure RLC: $rlc";};
	#print "MAC: $mac\n";
        Log3 $name, 5, "EnOcean $name EnOcean_sec_convertToNonsecure MAC: $mac";                         

	# TODO RLC could be transmitted with data, could not test this
	#if(!defined($rlc)) {
	#	print "No RLC in message, using stored value\n";
	#	$rlc = getRLC($id);
	#}
	
	# Maximum RLC search window is 128
	foreach my $rlc_window (0..128) {
		#print "Trying RLC offset $rlc_window\n";		

		# Fetch stored RLC		
		$rlc = EnOcean_sec_getRLC($hash, "rlcRcv");

		# Fetch private Key for VAES
		
		if ($attr{$name}{keyRcv} =~ /[\dA-F]{32}/) {
		  $private_key = pack('H32',$attr{$name}{keyRcv});
		} else {
	          return ("private key wrong, please teach-in the device new", undef, undef);
		}

		# Generate and check MAC over RORG+DATA+RLC fields
		if($mac eq EnOcean_sec_generateMAC($private_key, $rorg.$data_enc.$rlc, $mac_len)) {
			#print "RLC verfified\n";
			
			# Expand RLC to 16byte
			my $rlc_expanded = pack('H32',$rlc);

			# Expand data to 16byte
			my $data_expanded = pack('H32',$data_enc);
		
			# Decode data using VAES
			my $data_dec = EnOcean_sec_decodeVAES($rlc_expanded, $private_key, $data_expanded);
		
			# Extract one nibble of data
			my $data_end = unpack('H32', $data_dec);
			$data_end =~ /^.(.)/;
		
			#print "MSG: $1\n";
			return (undef, '32', "0" . uc($1));
		}
	}
	# Couldn't verify or decrypt message in RLC window
	return ("Can't verify or decrypt telegram", undef, undef);
}


#
sub EnOcean_sec_createTeachIn($$$$$$$$$$$)
{
  my ($ctrl, $hash, $comMode, $dataEnc, $eep, $macAlgo, $rlcAlgo, $rlcTX, $secLevel, $subDef, $destinationID) = @_;
  my $name = $hash->{NAME};
  my ($data, $err, $response, $loglevel);

  # THIS IS A BASIC IMPLEMENTATION WITH HARDCODED VALUES FOR
  # THE SECURITY PARAMETERS, WILL BE CUSTOMIZABLE IN FUTURE

  if ($cryptFunc == 0) {
    return ("Cryptographic functions are not available", undef, 2);        
  }
  # generate random private key
  my $pKey;
  for (my $i = 1; $i < 5; $i++) {
    $pKey .= uc(unpack('H8', pack('L', makerandom(Size => 32, Strength => 1))));
  }
  $attr{$name}{keySnd} = AttrVal($name, "keySnd", $pKey);

  #generate random rlc, save to fhem.cfg and update readings
  my $rlc = ReadingsVal($name, ".rlcSnd", uc(unpack('H4', pack('n', makerandom(Size => 16, Strength => 1)))));
  readingsSingleUpdate($hash, ".rlcSnd", $rlc, 0);
  $attr{$name}{rlcSnd} = $rlc;

  $attr{$name}{comMode} = AttrVal($name, "comMode", $comMode);
  $attr{$name}{dataEnc} = AttrVal($name, "dataEnc", $dataEnc);
  $attr{$name}{eep} = $eep;
  $attr{$name}{macAlgo} = AttrVal($name, "macAlgo", $macAlgo);
  $attr{$name}{manufID} = "7FF";
  $attr{$name}{rlcAlgo} = AttrVal($name, "rlcAlgo", $rlcAlgo);
  $attr{$name}{rlcTX} = AttrVal($name, "rlcTX", $rlcTX);
  $attr{$name}{secLevel} = AttrVal($name, "secLevel", $secLevel);
  if (AttrVal($name, "secMode", "") =~ m/^rcv|bidir$/) {
    $attr{$name}{secMode} = "biDir";
  } else {
    $attr{$name}{secMode} = "snd";
  }
  
  # prepare 1st telegram

  #RORG = 35, TEACH_IN_INFO_0, SLF, RLC, KEY, ID, STATUS as defined in Security_of_EnOcean_Radio_Networks.pdf page 17
  #set TEACH_IN_INFO = 25 -> 0001.0101 -> IDX =0, CNT = 2, PSK = 0, TYPE = 1, INFO = 1
  #set SLF = 4B -> 0100.1011 -> RLC_ALGO=16bit, RLC-TX=0, MAC-ALGO = AES3BYTE, DATA_ENC = VAES128
  #save the fixed security parameters to fhem.cfg

  #get first 5 bytes of private key
  #data 1: 25 4B r1 r2 k1 k2 k3 k4 k5
  $data = "254B" . $rlc . substr($attr{$name}{keySnd}, 0, 5*2);
  EnOcean_SndRadio(undef, $hash, 1, "35", $data, $subDef, "00", $destinationID);

  # prepare 2nd telegram

  #RORG = 35, TEACH_IN_INFO_1, KEY, ID, STATUS as defined in Security_of_EnOcean_Radio_Networks.pdf page 17
  #set TEACH_IN_INFO = 40 -> 0100.0000 -> IDX =1, CNT = 0, PSK = 0, TYPE = 0, INFO = 0

  #get 2nd 11 bytes of private key
  #data 2: 40 k6 k7 k8 k9 k10 k11 k12 k13 k14 k15 k16
  $data = "40" . substr($attr{$name}{keySnd}, 10, 11*2);
  EnOcean_SndRadio(undef, $hash, 1, "35", $data, $subDef, "00", $destinationID);

  return (undef, "secure teach-in", 2);
}


#
sub EnOcean_sec_convertToSecure($$$$)
{
  my ($hash, $packetType, $rorg, $data) = @_;
  my ($err, $response, $loglevel);
  my $name = $hash->{NAME};
  my $secLevel = AttrVal($name, "secLevel", "off");
  # encryption needed?
  return ($err, $rorg, $data, $response, 5) if ($rorg =~ m/^F6|35$/ || $secLevel !~ m/^encapsulation|encryption$/);
  return ("Cryptographic functions are not available", undef, undef, $response, 2) if ($cryptFunc == 0);
  my $dataEnc = AttrVal($name, "dataEnc", undef);
  my $subType = AttrVal($name, "subType", "");

  # subType specific actions
  if ($subType eq "switch.00" || $subType eq "windowHandle.10") {
    # securemode for D2-03-00 and D2-03-10
    if (hex($data) > 15) {
      return("wrong data byte", $rorg, $data, $response, 2);
    }

    # set rorg to secure telegram
    $rorg = "30";

  } else {
    return("Cryptographic functions for $subType not available", $rorg, $data, $response, 2);
  }

  #Get and update RLC
  my $rlc = EnOcean_sec_getRLC($hash, "rlcSnd");
  #Log3 $hash->{NAME}, 5, "EnOcean_sec_convertToSecure: Got actual RLC: $rlc";

  #Get key of device
  my $pKey = AttrVal($name, "keySnd", undef);
  return("private key not defined", $rorg, $data, $response, 2) if (!defined $pKey);
  $pKey = pack('H32', $pKey);
  #Log3 $hash->{NAME}, 5, "EnOcean_sec_convertToSecure: key: " . AttrVal($name, "keySnd", "");
  #prepare data
  my $rlc_expanded = pack('H32', $rlc);
  my $data_expanded = pack('H32', $data);
  my $data_dec;
  if ($dataEnc eq "VAES") {
    $data_dec = EnOcean_sec_decodeVAES($rlc_expanded, $pKey, $data_expanded);
  } else {
    return("Cryptographic functions not available", $rorg, $data, $response, 2);
  }
  my $data_end = unpack('H32', $data_dec);
  #get the correct nibble
  $data_end =~ /^.(.)/;
  $data_end = uc("0$1");
  #Log3 $hash->{NAME}, 5, "EnOcean_sec_convertToSecure: Crypted Data: $data_end";
  # calc MAC
  my $macAlgo = AttrVal($name, "macAlgo", undef);
  return("MAC Algorithm not defined", $rorg, $data, $response, 2) if (!defined $macAlgo);
  my $mac = EnOcean_sec_generateMAC($pKey, $rorg . $data_end . $rlc, $macAlgo);
  # combine message
  $data = $data_end . uc($mac);
  #Log3 $hash->{NAME}, 5, "EnOcean_sec_convertToSecure: Crypted Payload: $data";
  return(undef, $rorg, $data, $response, 5);
}

#
sub
EnOcean_NumericSort
{
  if ($a < $b) {
    return -1;
  } elsif ($a == $b) {
    return 0;
  } else {
    return 1;
  }
}

# Undef
sub
EnOcean_Undef($$)
{
  my ($hash, $arg) = @_;
  delete $modules{EnOcean}{defptr}{uc($hash->{DEF})};
  return undef;
}

1;

=pod
=begin html

<a name="EnOcean"></a>
<h3>EnOcean</h3>
<ul>
  EnOcean devices are sold by numerous hardware vendors (e.g. Eltako, Peha, etc),
  using the RF Protocol provided by the EnOcean Alliance. Depending on the
  function of the device an specific device profile is used, called EnOcean
  Equipment Profile (EEP). Basically three profiles will be differed, e. g.
  switches, contacts, sensors. Some manufacturers use additional proprietary
  extensions. Further technical information can be found at the
  <a href="http://www.enocean-alliance.org/de/enocean_standard/">EnOcean Alliance</a>,
  see in particular the
  <a href="http://www.enocean-alliance.org/eep/">EnOcean Equipment Profiles (EEP)</a>
  <br><br>
  Fhem recognizes a number of devices automatically. In order to teach-in, for
  some devices the sending of confirmation telegrams has to be turned on.
  Some equipment types and/or device models must be manually specified.
  Do so using the <a href="#EnOceanattr">attributes</a>
  <a href="#subType">subType</a> and <a href="#model">model</a>, see chapter
  <a href="#EnOceanset">Set</a> and
  <a href="#EnOceanevents">Generated events</a>. With the help of additional
  <a href="#EnOceanattr">attributes</a>, the behavior of the devices can be
  changed separately.
  <br><br>
  Fhem and the EnOcean devices must be trained with each other. To this, Fhem
  must be in the learning mode, see <a href="#EnOcean_teach-in">Teach-In / Teach-Out</a>
  and <a href="#TCM_learningMode">learningMode</a>.<br>
  The teach-in procedure depends on the type of the devices. Switches (EEP RPS)
  and contacts (EEP 1BS) are recognized when receiving the first message.
  Contacts can also send a teach-in telegram. Fhem not need this telegram.
  Sensors (EEP 4BS) has to send a teach-in telegram. The profile-less
  4BS teach-in procedure transfers no EEP profile identifier and no manufacturer
  ID. In this case Fhem does not recognize the device automatically. The proper
  device type must be set manually, use the <a href="#EnOceanattr">attributes</a>
  <a href="#subType">subType</a>, <a href="#manufID">manufID</a> and/or
  <a href="#model">model</a>. If the EEP profile identifier and the manufacturer
  ID are sent the device is clearly identifiable. Fhem automatically assigns
  these devices to the correct profile. Some 4BS, VLD or MSC devices must be paired
  bidirectional, see <a href="#EnOcean_teach-in">Teach-In / Teach-Out</a>.<br><br>
  Fhem supports many of most common EnOcean profiles and manufacturer-specific
  devices. Additional profiles and devices can be added if required.
  <br><br>
  In order to enable communication with EnOcean remote stations a
  <a href="#TCM">TCM</a> module is necessary.
  <br><br>
  Please note that EnOcean repeaters also send Fhem data telegrams again.
  Use the TCM <code>attr &lt;name&gt; <a href="#blockSenderID">blockSenderID</a> own</code>
  to block receiving telegrams with a TCM SenderIDs.
  <br><br>
  
  <b>EnOcean Observing Functions</b><br>
  <ul>
    Interference or overloading of the radio transmission can prevent the reception of Fhem
    commands at the receiver. With the help of the observing function Fhem checks the reception
    of the acknowledgment telegrams of the actuator. If within one second no acknowledgment
    telegram is received, the last set command is sent again.
    The set command is repeated a maximum of 5 times. The maximum number can be specified in the attribute
    <a href="#EnOcean_observeCmdRepetition">observeCmdRepetition</a><br>.
    The function can only be used if the actuator immediately after the reception of
    the set command sends an acknowledgment message.<br>
    The observing function is turned on by the Attribute <a href="#EnOcean_observe">observe.</a>
    In addition, further devices can be monitored. The names of this devices can be entered in the
    <a href="#EnOcean_observeRefDev">observeRefDev</a> attribute. If additional device are specified,
    the monitoring is stopped as soon as the first acknowledgment telegram of one of the devices was received (OR logic).
    If the <a href="#EnOcean_observeLogic">observeLogic</a> attribute is set to "and", the monitoring is stopped when a telegram 
    was received by all devices (AND logic). Please note that the name of the own device has also to be entered in the
    <a href="#EnOcean_observeRefDev">observeRefDev</a> if required.<br>
    If the maximum number of retries is reached and still no all acknowledgment telegrams has been received, the reading
    "observeFailedDev" shows the faulty devices and the command can be executed, that is stored in the
    <a href="#EnOcean_observeErrorAction">observeErrorAction</a> attribute.    
    <br><br>
  </ul>

  <b>EnOcean Energy Management</b><br>
  <ul>
    <li><a href="#demand_response">Demand Response</a> (EEP A5-37-01)</li>
    Demand Response (DR) is a standard to allow utility companies to send requests for reduction in power
    consumption during peak usage times. It is also used as a means to allow users to reduce overall power
    comsumption as energy prices increase. The EEP was designed with a very flexible setting for the level
    (0...15) as well as a default level whereby the transmitter can specify a specific level for all
    controllers to use (0...100 % of either maximum or current power output, depending on the load type).
    The profile also includes a timeout setting to indicate how long the DR event should last if the
    DR transmitting device does not send heartbeats or subsequent new DR levels.<br>
    The DR actor controls the target actuators such as switches, dimmers etc. The DR actor
    is linked to the FHEM target actors via the attribute <a href="#EnOcean_demandRespRefDev">demandRespRefDev</a>.<br>
    <ul>
    <li>Standard actions are available for the following profiles:</li>
    <ul>
    <li>switch (setting the switching command for min, max by the attribute <a href="#EnOcean_demandRespMin">demandRespMin</a>,
    <a href="#EnOcean_demandRespMax">demandRespMax</a>)</li>
    <li>gateway/switching (on, off)</li>
    <li>gateway/dimming (dim 0...100, relative to the max or current set value)</li>
    <li>lightCtrl.01 (dim 0...255)</li>
    <li>actuator.01 (dim 0...100)</li>
    <li>roomSensorControl.01 (setpoint 0...255)</li>
    <li>roomSensorControl.05 (setpoint 0...255 and nightReduction 0...5 for Eltako devices)</li>
    <li>roomCtrlPanel.00 (roomCtrlMode comfort|economy)</li>
    </ul>
    <li>On the target actuator can be specified alternatively a freely definable command.
    The command sequence is stored in the attribute <a href="#EnOcean_demandRespAction">demandRespAction</a>.
    The command sequence can be designed similar to "notify". For the command sequence predefined variables can be used,
    eg. $LEVEL. This actions can be executed very flexible depending on the given energy
    reduction levels.
    </li>
    <li>Alternatively or additionally, a custom command sequence in the DR profile itself
    can be stored.
    </li>
    </ul>
    The profile has a master and slave mode.
    <ul>
    <li>In slave mode, demand response data telegrams received eg a control unit of the power utility,
    evaluated and the corresponding commands triggered on the linked target actuators. The behavior in
    slave mode can be changed by multiple attributes.
    </li>
    <li>In master mode, the demand response level is set by set commands and thus sends a corresponding
    data telegram and the associated target actuators are controlled. The demand response control
    value are specified by "level", "power", "setpoint" "max" or "min". Each other settings are
    calculated proportionally. In normal operation, ie without power reduction, the control value (level)
    is 15. Through the optional parameters "powerUsageScale", "randomStart", "randomEnd" and "timeout"
    the control behavior can be customized. The threshold at which the reading "powerUsageLevel"
    between "min" and "max" switch is specified with the attribute
    <a href="#EnOcean_demandRespThreshold">demandRespThreshold</a>.
    </li>
    </ul>
    Additional information about the profile itself can be found in the EnOcean EEP documentation.
  <br><br>
  </ul>
  
  <b>EnOcean Security features</b><br>
  <ul>
    The receiving and sending of encrypted messages is supported. This module currently allows the secure operating mode of PTM 215
    based switches.<br>
    To receive secured telegrams, you first have to start the teach in mode via<br><br>
    <code>set &lt;IODev&gt; teach &lt;t/s&gt;</code><br><br>
    and then doing the following on the PTM 215 module:<br>
    <li>Remove the switch cover of the module</li>
    <li>Press both buttons of one rocker side (A0 & A1 or B0 & B1)</li>
    <li>While keeping the buttons pressed actuate the energy bow twice.</li><br>
    This generates two teach-in telegrams which create a Fhem device with the subType "switch.00" and synchronize the Fhem with
    the PTM 215. Both the Fhem and the PTM 215 now maintain a counter which is used to generate a rolling code encryption scheme.
    Also during teach-in, a private key is transmitted to the Fhem. The counter value is allowed to desynchronize for a maximum of
    128 counts, to allow compensating for missed telegrams, if this value is crossed you need to teach-in the PTM 215 again. Also
    if your Fhem installation gets erased including the state information, you need to teach in the PTM 215 modules again (which
    you would need to do anyway).<br><br>
    
    To send secured telegrams, you first have send a secure teach-in to the remode device<br><br>
    <code>set &lt;name&gt; teachInSec</code><br><br>
    As for the security of this solution, if someone manages to capture the teach-in telegrams, he can extract the private key,
    so the added security isn't perfect but relies on the fact, that none listens to you setting up your installation.
    <br><br>
    The cryptographic functions need the additional Perl modules Crypt/Rijndael and Crypt/Random. The module must be installed manually.
    With the help of CPAN at the operating system level, for example,<br><br>
    <code>/usr/bin/perl -MCPAN -e 'install Crypt::Rijndael'</code><br>
    <code>/usr/bin/perl -MCPAN -e 'install Crypt::Random'</code>
  <br><br>
  </ul>

  <a name="EnOceandefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EnOcean &lt;DEF&gt;|getNextID</code>
    <br><br>

    Define an EnOcean device, connected via a <a href="#TCM">TCM</a> modul. The
    &lt;DEF&gt; is the SenderID/DestinationID of the device (8 digit hex number), for example
    <ul><br>
      <code>define switch1 EnOcean FFC54500</code><br>
    </ul><br>
    In order to control devices, you cannot reuse the SenderIDs/
    DestinationID of other devices (like remotes), instead you have to create
    your own, which must be in the allowed SenderID range of the underlying Fhem
    IO device, see <a href="#TCM">TCM</a> BaseID, LastID. For this first query the
    <a href="#TCM">TCM</a> with the <code>get &lt;tcm&gt; baseID</code> command
    for the BaseID. You can use up to 128 IDs starting with the BaseID shown there.
    If you are using an Fhem SenderID outside of the allowed range, you will see an
    ERR_ID_RANGE message in the Fhem log.<br>
    FHEM can assign a free SenderID alternatively, for example
    <ul><br>
      <code>define switch1 EnOcean getNextID</code><br>
    </ul><br>    
    The <a href="#autocreate">autocreate</a> module may help you if the actor or sensor send
    acknowledge messages or teach-in telegrams. In order to control this devices e. g. switches with
    additional SenderIDs you can use the attributes <a href="#subDef">subDef</a>,
    <a href="#subDef0">subDef0</a> and <a href="#subDefI">subDefI</a>.<br>
    Fhem communicates unicast, if bidirectional 4BS or UTE teach-in is used, see 
    <a href="#EnOcean_teach-in"> Bidirectional Teach-In / Teach-Out</a>. In this case
    Fhem send unicast telegrams with its SenderID and the DestinationID of the device.
    <br><br>
  </ul>
  
  <a name="EnOceaninternals"></a>
  <b>Internals</b>
  <ul>
    <li>&lt;IODev&gt;_DestinationID: 0000000 ... FFFFFFFF<br>
      Received destination address, Broadcast radio: FFFFFFFF<br>
    </li>
    <li>&lt;IODev&gt;_RSSI: LP/dBm<br>
      Received signal strength indication (best value of all received subtelegrams)<br>
    </li>
    <li>&lt;IODev&gt;_ReceivingQuality: excellent|good|bad<br>
      excellent: RSSI >= -76 dBm (internal standard antenna sufficiently)<br>
      good: RSSI < -76 dBm and RSSI >= -87 dBm (good antenna necessary)<br>
      bad: RSSI < -87 dBm (repeater required)<br>
    </li>
    <li>&lt;IODev&gt;_RepeatingCounter: 0...2<br>
      Number of forwardings by repeaters<br>
    </li>
    <br><br>
  </ul>

  <a name="EnOceanset"></a>
  <b>Set</b>
  <ul>
    <li><a name="EnOcean_teach-in">Teach-In / Teach-Out</a>
    <ul>
      <li>Teach-in remote devices</li>
      <br>
      <code>set &lt;IODev&gt; teach &lt;t/s&gt;</code>
      <br><br>
      Set Fhem in the learning mode.<br>
      A device, which is then also put in this state is to paired with
      Fhem. Bidirectional Teach-In / Teach-Out is used for some 4BS, VLD and MSC devices,
      e. g. EEP 4BS, RORG A5-20-01 (Battery Powered Actuator).<br>
      Bidirectional 4BS Teach-In and UTE - Universal Uni- and Bidirectional
      Teach-In are supported. 
      <br>
      <code>IODev</code> is the name of the TCM Module.<br>
      <code>t/s</code> is the time for the learning period.
      <br><br>
      Types of learning modes see <a href="#TCM_learningMode">learningMode</a>
      <br><br>
      Example:
      <ul><code>set TCM_0 teach 600</code></ul>
      <br>
      <li>Teach-in RPS profiles (switches)</li>
      <br>
      <code>set &lt;name&gt; A0|AI|B0|BI|C0|CI|D0|DI</code>
      <br><br>
      Send teach-in telegram to remote device.
      <br><br>
      <li>Teach-in 1BS profiles (contact)</li>
      <br>
      <code>set &lt;name&gt; teach</code>
      <br><br>
      Send teach-in telegram to remote device.
      <br><br>
      <li>Teach-in 4BS profiles (sensors, dimmer, room controller etc.)</li>
      <br>
      <code>set &lt;name&gt; teach</code>
      <br><br>
      Send teach-in telegram to remote device.<br>    
      If no SenderID (attr subDef) was assigned before a learning telegram is sent for the first time, a free SenderID
      is assigned automatically.
      <br><br>
    </ul>
    </li>

    <li>Switch, Pushbutton Switch (EEP F6-02-01 ... F6-03-02)<br>
    RORG RPS [default subType]
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of A0, AI, B0, BI, C0, CI, D0, DI,
    combinations of these and released.  First and second action can be sent
    simultaneously. Separate first and second action with a comma.<br>
    In fact we are trying to emulate a PT200 type remote.<br>
    If you define an <a href="#eventMap">eventMap</a> attribute with on/off,
    then you will be able to easily set the device from the <a
    href="#FHEMWEB">WEB</a> frontend.<br>
    <a href="#setExtensions">set extensions</a> are supported, if the corresponding
    <a href="#eventMap">eventMap</a> specifies the <code>on</code> and <code>off</code>
    mappings, for example <code>attr <name> eventMap on-till:on-till AI:on A0:off</code>.<br>
    With the help of additional <a href="#EnOceanattr">attributes</a>, the
    behavior of the devices can be adapt.<br>
    The attr subType must be switch. This is done if the device was created by autocreate. 
    <br><br>
    Example:
    <ul><code>
      set switch1 BI<br>
      set switch1 B0,CI<br>
      attr eventMap BI:on B0:off<br>
      set switch1 on<br>
    </code></ul><br>
    </ul>
    </li>

    <li>Staircase off-delay timer (EEP F6-02-01 ... F6-02-02)<br>
        RORG RPS [Eltako FTN14, tested with Eltako FTN14 only]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>on<br>
        issue switch on command</li>
      <li>released<br>
        start timer</li>
    </ul><br>
    Set attr eventMap to B0:on BI:off, attr subType to switch, attr
    webCmd to on:released and if needed attr switchMode to pushbutton manually.<br>
    The attr subType must be switch. This is done if the device was created by autocreate.<br>
    Use the sensor type "Schalter" for Eltako devices. The Staircase
    off-delay timer is switched on when pressing "on" and the time will be started
    when pressing "released". "released" immediately after "on" is sent if
    the attr switchMode is set to "pushbutton".
    </li>
    <br><br>

    <li>Pushbutton Switch (EEP D2-03-00)<br>
         RORG VLD [EnOcean PTM 215 Modul]
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
       <li>teachIn<br>
          initiate UTE teach-in</li>
       <li>teachInSec<br>
          initiate secure teach-in</li>
       <li>teachOut<br>
          initiate UTE teach-out</li>
        <li>A0|AI|B0|BI<br>
          issue switch command</li>
        <li>A0,B0|A0,AI|AI,B0|AI,BI<br>
          issue switch command</li>
       <li>pressed<br>
          energy bow pressed</li>
        <li>pressed34<br>
          3 or 4 buttons and energy bow pressed</li>
       <li>released<br>
          energy bow released</li><br>
   
    </ul>
    First and second action can be sent simultaneously. Separate first and second action with a comma.<br>
    If you define an <a href="#eventMap">eventMap</a> attribute with on/off,
    then you will be able to easily set the device from the <a href="#FHEMWEB">WEB</a> frontend.<br>
    <a href="#setExtensions">set extensions</a> are supported, if the corresponding
    <a href="#eventMap">eventMap</a> specifies the <code>on</code> and <code>off</code>
    mappings, for example <code>attr <name> eventMap on-till:on-till AI:on A0:off</code>.<br>
    If <a href="#comMode">comMode</a> is set to biDir the device can be controlled bidirectionally.<br>
    With the help of additional <a href="#EnOceanattr">attributes</a>, the behavior of the devices can be adapt.<br>
    The attr subType must be switch.00. This is done if the device was created by autocreate. 
    <br><br>
    <ul>
    Example:
    <ul><code>
      set switch1 BI<br>
      set switch1 B0,CI<br>
      attr eventMap BI:on B0:off<br>
      set switch1 on<br>
    </code></ul><br>
    </ul>
    </li>

    <li>Single Input Contact, Door/Window Contact (EEP D5-00-01)<br>
        RORG 1BS [tested with Eltako FSR14]
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
        <li>closed<br>
          issue closed command</li>
         <li>open<br>
          issue open command</li>
        <li>teach<br>
          initiate teach-in</li>
    </ul></li><br>
        The attr subType must be contact. The attribute must be set manually.
    <br><br>

    <li>Room Sensor and Control Unit (EEP A5-10-02)<br>
        [Thermokon SR04 PTS]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>teach<br>
          initiate teach-in</li>
      <li>setpoint [0 ... 255]<br>
          Set the actuator to the specifed setpoint.</li>
      <li>setpointScaled [&lt;floating-point number&gt;]<br>
          Set the actuator to the scaled setpoint.</li>
      <li>fanStage [auto|0|1|2|3]<br>
          Set fan stage</li>
      <li>switch [on|off]<br>
          Set switch</li>
    </ul><br>
      The actual temperature will be taken from the temperature reported by
      a temperature reference device <a href="#temperatureRefDev">temperatureRefDev</a>
      primarily or from the attribute <a href="#actualTemp">actualTemp</a> if it is set.<br>
      If the attribute <a href="#EnOcean_setCmdTrigger">setCmdTrigger</a> is set to "refDev", a setpoint
      command is sent when the reference device is updated.<br>
      The scaling of the setpoint adjustment is device- and vendor-specific. Set the
      attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
      <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled setting
      setpointScaled.<br>
      The attr subType must be roomSensorControl.05. The attribute must be set manually. 
    </li>
    <br><br>

    <li>Room Sensor and Control Unit (A5-10-06 plus night reduction)<br>
        [Eltako FVS]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>teach<br>
          initiate teach-in</li>
      <li>desired-temp [t/&#176C [lock|unlock]]<br>
          Set the desired temperature.</li>
      <li>nightReduction [t/K [lock|unlock]]<br>
          Set night reduction</li>
      <li>setpointTemp [t/&#176C [lock|unlock]]<br>
          Set the desired temperature</li>
    </ul><br>
      The actual temperature will be taken from the temperature reported by
      a temperature reference device <a href="#temperatureRefDev">temperatureRefDev</a>
      primarily or from the attribute <a href="#actualTemp">actualTemp</a> if it is set.<br>
      If the attribute <a href="#EnOcean_setCmdTrigger">setCmdTrigger</a> is set to "refDev", a setpoint
      command is sent when the reference device is updated.<br>
      This profil can be used with a further Room Sensor and Control Unit Eltako FTR55*
      to control a heating/cooling relay FHK12, FHK14 or FHK61. If Fhem and FTR55*
      is teached in, the temperature control of the FTR55* can be either blocked
      or to a setpoint deviation of +/- 3 K be limited. For this use the optional parameter
      [block] = lock|unlock, unlock is default.<br>
      The attr subType must be roomSensorControl.05 and attr manufID must be 00D.
      The attributes must be set manually. 
    </li>
    <br><br>

    <li>Room Sensor and Control Unit (EEP A5-10-10)<br>
        [Thermokon SR04 * rH, Thanos SR *]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>teach<br>
          initiate teach-in</li>
      <li>setpoint [0 ... 255]<br>
          Set the actuator to the specifed setpoint.</li>
      <li>setpointScaled [&lt;floating-point number&gt;]<br>
          Set the actuator to the scaled setpoint.</li>
      <li>switch [on|off]<br>
          Set switch</li>
    </ul><br>
      The actual temperature will be taken from the temperature reported by
      a temperature reference device <a href="#temperatureRefDev">temperatureRefDev</a>
      primarily or from the attribute <a href="#actualTemp">actualTemp</a> if it is set.<br>
      The actual humidity will be taken from the humidity reported by
      a humidity reference device <a href="#EnOcean_humidityRefDev">humidityRefDev</a>
      primarily or from the attribute <a href="#EnOcean_humidity">humidity</a> if it is set.<br>
      If the attribute <a href="#EnOcean_setCmdTrigger">setCmdTrigger</a> is set to "refDev", a setpoint
      command is sent when the reference device is updated.<br>
      The scaling of the setpoint adjustment is device- and vendor-specific. Set the
      attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
      <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled setting
      setpointScaled.<br>
      The attr subType must be roomSensorControl.01. The attribute must be set manually. 
    </li>
    <br><br>

    <li>Battery Powered Actuator (EEP A5-20-01)<br>
        [Kieback&Peter MD15-FTL-xx]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>actuator setpoint/%<br>
          Set the actuator to the specifed setpoint (0...100)</li>
      <li>desired-temp t/&#176C<br>
          Use the builtin PI regulator, and set the desired temperature to the
          specified degree. The actual value will be taken from the temperature
          reported by the Battery Powered Actuator, the <a href="#temperatureRefDev">temperatureRefDev</a>
          or from the attribute <a href="#actualTemp">actualTemp</a> if it is set.</li>
      <li>setpoint setpoint/%<br>
          Set the actuator to the specifed setpoint (0...100)</li>
      <li>setpointTemp t/&#176C<br>
          Use the builtin PI regulator, and set the desired temperature to the
          specified degree. The actual value will be taken from the temperature
          reported by the Battery Powered Actuator, the <a href="#temperatureRefDev">temperatureRefDev</a>
          or from the attribute <a href="#actualTemp">actualTemp</a> if it is set.</li>
      <li>runInit<br>
          Maintenance Mode (service on): Run init sequence.</li>
      <li>liftSet<br>
          Maintenance Mode (service on): Lift set</li>
      <li>valveOpen<br>
          Maintenance Mode (service on): Valve open</li>
      <li>valveClosed<br>
          Maintenance Mode (service on): Valve closed</li>
      <li>unattended<br>
          Do not regulate the actuator.</li>
    </ul><br>
    The attr subType must be hvac.01. This is done if the device was
    created by autocreate. To control the device, it must be bidirectional paired,
    see <a href="#EnOcean_teach-in">Teach-In / Teach-Out</a>.<br>
    The command is not sent until the device wakes up and sends a mesage, usually
    every 10 minutes.
    </li>
    <br><br>

    <li>Energy management, <a name="demand_response">demand response</a> (EEP A5-37-01)<br>
      demand response master commands<br>
      <ul>
        <code>set &lt;name&gt; &lt;value&gt;</code>
        <br><br>
        where <code>value</code> is
          <li>level 0...15 [&lt;powerUsageScale&gt; [&lt;randomStart&gt; [&lt;randomEnd&gt; [timeout]]]]<br>
            set demand response level</li>
          <li>max [&lt;powerUsageScale&gt; [&lt;randomStart&gt; [&lt;randomEnd&gt; [timeout]]]]<br>
            set power usage level to max</li>
          <li>min [&lt;powerUsageScale&gt; [&lt;randomStart&gt; [&lt;randomEnd&gt; [timeout]]]]<br>
            set power usage level to min</li>
          <li>power power/% [&lt;powerUsageScale&gt; [&lt;randomStart&gt; [&lt;randomEnd&gt; [timeout]]]]<br>
            set power</li>
          <li>setpoint 0...255 [&lt;powerUsageScale&gt; [&lt;randomStart&gt; [&lt;randomEnd&gt; [timeout]]]]<br>
            set setpoint</li>
          <li>teach<br>
            initiate teach-in</li>
      </ul><br>
        [&lt;powerUsageScale&gt;] = max|rel, [&lt;powerUsageScale&gt;] = max is default<br>
        [&lt;randomStart&gt;] = yes|no, [&lt;randomStart&gt;] = no is default<br>
        [&lt;randomEnd&gt;] = yes|no, [&lt;randomEnd&gt;] = no is default<br>
        [timeout] = 0/min | 15/min ... 3825/min, [timeout] = 0 is default<br>
        The attr subType must be energyManagement.01.<br>
        This is done if the device was created by autocreate.<br>
      </li>
      <br><br>
 
      <li><a name="Gateway">Gateway</a> (EEP A5-38-08)<br>
        The Gateway profile include 7 different commands (Switching, Dimming,
        Setpoint Shift, Basic Setpoint, Control variable, Fan stage, Blind Central Command).
        The commands can be selected by the attribute gwCmd or command line. The attribute
        entry has priority.<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>&lt;gwCmd&gt; &lt;cmd&gt; [subCmd]<br>
          initiate Gateway commands by command line</li>
        <li>&lt;cmd&gt; [subCmd]<br>
          initiate Gateway commands if attribute gwCmd is set.</li>
     </ul><br>
       The attr subType must be gateway. Attribute gwCmd can also be set to
       switching|dimming|setpointShift|setpointBasic|controlVar|fanStage|blindCmd.<br>
       This is done if the device was created by autocreate.<br>
       For Eltako devices attributes must be set manually.
    </li>
    <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Switching<br>
         [Eltako FLC61, FSA12, FSR14]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>on [lock|unlock]<br>
          issue switch on command</li>
        <li>off [lock|unlock]<br>
          issue switch off command</li>
        <li><a href="#setExtensions">set extensions</a> are supported.</li>
     </ul><br>
        The attr subType must be gateway and gwCmd must be switching. This is done if the device was
        created by autocreate.<br>
        For Eltako devices attributes must be set manually. For Eltako FSA12 attribute model must be set 
        to FSA12.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Dimming<br>
         [Eltako FUD12, FUD14, FUD61, FUD70, FSG14, ...]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>on [lock|unlock]<br>
          issue switch on command</li>
        <li>off [lock|unlock]<br>
          issue switch off command</li>
        <li>dim dim/% [rampTime/s [lock|unlock]]<br>
          issue dim command</li>
        <li>dimup dim/% [rampTime/s [lock|unlock]]<br>
          issue dim command</li>
        <li>dimdown dim/% [rampTime/s [lock|unlock]]<br>
          issue dim command</li>
        <li><a href="#setExtensions">set extensions</a> are supported.</li>
     </ul><br>
        rampTime Range: t = 1 s ... 255 s or 0 if no time specified,
        for Eltako: t = 1 = fast dimming ... 255 = slow dimming or 0 = dimming speed on the dimmer used<br>
        The attr subType must be gateway and gwCmd must be dimming. This is done if the device was
        created by autocreate.<br>
        For Eltako devices attributes must be set manually. Use the sensor type "PC/FVS" for Eltako devices.
     </li>
     <br><br>

    <li>Gateway (EEP A5-38-08)<br>
        Dimming of fluorescent lamps<br>
        [Eltako FSG70, tested with Eltako FSG70 only]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>on<br>
        issue switch on command</li>
      <li>off<br>
        issue switch off command</li>
      <li><a href="#setExtensions">set extensions</a> are supported.</li>
    </ul><br>
    The attr subType must be gateway and gwCmd must be dimming. Set attr eventMap to B0:on BI:off,
    attr subTypeSet to switch and attr switchMode to pushbutton manually.<br>
    Use the sensor type "Richtungstaster" for Eltako devices.
    </li>
    <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Setpoint shift<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>shift 1/K <br>
          issue Setpoint shift</li>
     </ul><br>
        Shift Range: T = -12.7 K ... 12.8 K<br>
        The attr subType must be gateway and gwCmd must be setpointShift.
        This is done if the device was created by autocreate.<br>
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Basic Setpoint<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>basic t/&#176C<br>
          issue Basic Setpoint</li>
     </ul><br>
        Setpoint Range: t = 0 &#176C ... 51.2 &#176C<br>
        The attr subType must be gateway and gwCmd must be setpointBasic.
        This is done if the device was created by autocreate.<br>
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Control variable<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>presence present|absent|standby<br>
          issue Room occupancy</li>
        <li>energyHoldOff normal|holdoff<br>
          issue Energy hold off</li>
        <li>controllerMode auto|heating|cooling|off<br>
          issue Controller mode</li>
        <li>controllerState auto|override <0 ... 100> <br>
          issue Control variable override</li>
     </ul><br>
        Override Range: cvov = 0 % ... 100 %<br>
        The attr subType must be gateway and gwCmd must be controlVar.
        This is done if the device was created by autocreate.<br>
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Fan stage<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>stage 0 ... 3|auto<br>
          issue Fan Stage override</li>
     </ul><br>
        The attr subType must be gateway and gwCmd must be fanStage.
        This is done if the device was created by autocreate.<br>
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         <a name="Blind Command Central">Blind Command Central</a><br>
         [not fully tested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>status<br>
          Status request</li>
        <li>opens<br>
          issue blinds opens command</li>
        <li>up tu/s ta/s<br>
          issue roll up command</li>
        <li>closes<br>
          issue blinds closes command</li>
        <li>down td/s ta/s<br>
          issue roll down command</li>
        <li>position position/% &alpha;/&#176<br>
          drive blinds to position with angle value</li>
        <li>stop<br>
          issue blinds stops command</li>
        <li>runtimeSet tu/s td/s<br>
          set runtime parameter</li>
        <li>angleSet ta/s<br>
          set angle configuration</li>
        <li>positionMinMax positionMin/% positionMax/%<br>
          set min, max values for position</li>
        <li>angleMinMax &alpha;o/&#176 &alpha;s/&#176<br>
          set slat angle for open and shut position</li>
        <li>positionLogic normal|inverse<br>
          set position logic</li>
     </ul><br>
        Runtime Range: tu|td = 0 s ... 255 s<br>
        Select a runtime up and a runtime down that is at least as long as the
        shading element or roller shutter needs to move from its end position to
        the other position.<br>
        Position Range: position = 0 % ... 100 %<br>
        Angle Time Range: ta = 0 s ... 25.5 s<br>
        Runtime value for the sunblind reversion time. Select the time to revolve
        the sunblind from one slat angle end position to the other end position.<br>
        Slat Angle: &alpha;|&alpha;o|&alpha;s = -180 &#176 ... 180 &#176<br>
        Position Logic, normal: Blinds fully opens corresponds to Position = 0 %<br>
        Position Logic, inverse: Blinds fully opens corresponds to Position = 100 %<br>
        The attr subType must be gateway and gwCmd must be blindCmd.<br>
        See also attributes <a href="#EnOcean_sendDevStatus">sendDevStatus and <a href="#EnOcean_serviceOn">serviceOn</a></a><br>
        The profile is linked with controller profile, see <a href="#Blind Status">Blind Status</a>.<br>
     </li>
     <br><br>

     <li>Extended Lighting Control (EEP A5-38-09)<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate remote teach-in</li>
        <li>on<br>
          issue switch on command</li>
        <li>off<br>
          issue switch off command</li>
        <li>dim dim [rampTime/s]<br>
          issue dim command</li>
        <li>dimup rampTime/s<br>
          issue dim command</li>
        <li>dimdown rampTime/s<br>
          issue dim command</li>
        <li>stop<br>
          stop dimming</li>
        <li>rgb &lt;red color value&gt&lt;green color value&gt&lt;blue color value&gt<br>
          issue color value command</li>
        <li>scene drive|store 0..15<br>
          store actual value in the scene or drive to scene value</li>
        <li>dimMinMax &lt;min value&gt &lt;max value&gt<br>
          set minimal and maximal dimmer value</li>
        <li>lampOpHours 0..65535<br>
          set the operation hours of the lamp</li>
        <li>block unlock|on|off|local<br>
          locking local operations</li>
        <li>meteringValues 0..65535 mW|W|kW|MW|Wh|kWh|MWh|GWh|mA|mV<br>
          set a new value for the energy metering (overwrite the actual value with the selected unit)</li>
        <li>meteringValues 0..6553.5 A|V<br>
          set a new value for the energy metering (overwrite the actual value with the selected unit)</li>
        <li><a href="#setExtensions">set extensions</a> are supported.</li>
     </ul><br>
        color values: 00 ... FF hexadecimal<br>
        rampTime Range: t = 1 s ... 65535 s or 1 if no time specified, ramping time can be set by attribute 
        <a href="#EnOcean_rampTime">rampTime</a><br>
        The attr subType or subTypSet must be lightCtrl.01. This is done if the device was created by autocreate.<br>
        The subType is associated with the subtype lightCtrlState.02.
     </li>
     <br><br>

    <li><a name="Manufacturer Specific Applications">Manufacturer Specific Applications</a> (EEP A5-3F-7F)<br>
        Shutter<br>
        [Eltako FSB12, FSB14, FSB61, FSB70, tested with Eltako devices only]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>teach<br>
        initiate teach-in mode</li>
      <li>opens<br>
        issue blinds opens command</li>
      <li>up tu/s<br>
        issue roll up command</li>
      <li>closes<br>
        issue blinds closes command</li>
      <li>down td/s<br>
        issue roll down command</li>
      <li>position position/% [&alpha;/&#176]<br>
        drive blinds to position with angle value</li>
      <li>stop<br>
        issue stop command</li>
    </ul><br>
      Runtime Range: tu|td = 1 s ... 255 s<br>
      Position Range: position = 0 % ... 100 %<br>
      Slat Angle Range: &alpha; = -180 &#176 ... 180 &#176<br>
      Angle Time Range: ta = 0 s ... 6 s<br>
      The devive can only fully controlled if the attributes <a href="#angleMax">angleMax</a>,
      <a href="#angleMin">angleMin</a>, <a href="#angleTime">angleTime</a>,
      <a href="#shutTime">shutTime</a> and <a href="#shutTimeCloses">shutTimeCloses</a>,
      are set correctly.
      Set attr subType to manufProfile, manufID to 00D and attr model to
      FSB14|FSB61|FSB70 manually.<br>
      Use the sensor type "Szenentaster/PC" for Eltako devices.
    </li>
    <br><br>
    
    <li>Electronic switches and dimmers with Energy Measurement and Local Control (D2-01-00 - D2-01-11)<br>
        [Telefunken Funktionsstecker, PEHA Easyclick, AWAG Elektrotechnik AG Omnio UPS 230/xx,UPD 230/xx]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>on [&lt;channel&gt;]<br>
        issue switch on command</li>
      <li>off [&lt;channel&gt;]<br>
        issue switch off command</li>
      <li>dim dim/% [&lt;channel&gt; [&lt;rampTime&gt;]]<br>
        issue dimming command</li>
      <li>local dayNight day|night, day is default<br>
        set the user interface indication</li>
      <li>local defaultState on|off|last, off is default<br>
        set the default setting of the output channels when switch on</li>
      <li>local localControl enabled|disabled, disabled is default<br> 
        enable the local control of the device</li>
      <li>local overCurrentShutdown off|restart, off is default<br>
        set the behavior after a shutdown due to an overcurrent</li>
      <li>local overCurrentShutdownReset not_active|trigger, not_active is default<br>
        trigger a reset after an overcurrent</li>
      <li>local rampTime&lt;1...3&gt; 0/s, 0.5/s ... 7/s, 7.5/s, 0 is default<br>
        set the dimming time of timer 1 ... 3</li>
      <li>local teachInDev enabled|disabled, disabled is default<br>
        enable the taught-in devices with different EEP</li>
      <li>measurement delta 0/s ... 4095/s, 0 is default<br>
        define the difference between two displayed measurements </li>
      <li>measurement mode energy|power, energy is default<br>
        define the measurand</li>
      <li>measurement report query|auto, query is default<br>
        specify the measurement method</li>
      <li>measurement reset not_active|trigger, not_active is default<br>
        resetting the measured values</li>
      <li>measurement responseTimeMax 10/s ... 2550/s, 10 is default<br>
        set the maximum time between two outputs of measured values</li>
      <li>measurement responseTimeMin 0/s ... 255/s, 0 is default<br>
        set the minimum time between two outputs of measured values</li>
      <li>measurement unit Ws|Wh|KWh|W|KW, Ws is default<br>
        specify the measurement unit</li>
    </ul><br>
       [channel] = 0...29|all|input, all is default<br>
       The default channel can be specified with the attr <a href="#EnOcean_defaultChannel">defaultChannel</a>.<br>     
       [rampTime] = 1..3|switch|stop, switch is default<br>
       The attr subType must be actuator.01. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Blind Control for Position and Angle (D2-05-00)<br>
        [AWAG Elektrotechnik AG OMNIO UPJ 230/12]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>opens<br>
        issue blinds opens command</li>
      <li>closes<br>
        issue blinds closes command</li>
      <li>position position/% [[&alpha;/%] [directly|opens|closes]]<br>
        drive blinds to position with angle value</li>
      <li>angle &alpha;/%<br>
        drive blinds to angle value</li>
      <li>stop<br>
        issue stop command</li>
      <li>alarm<br>
        set actuator to the "alarm" mode. When the actuator ist set to the "alarm" mode neither local
        nor central positioning and configuration commands will be executed. Before entering the "alarm"
        mode, the actuator will execute the "alarm action" as configured by the attribute <a href="#EnOcean_alarmAction">alarmAction</a>
      </li>
      <li>lock<br>
        set actuator to the "blockade" mode. When the actuator ist set to the "blockade" mode neither local
        nor central positioning and configuration commands will be executed.
      </li>
      <li>unlock<br>
        issue unlock command</li>
    </ul><br>
      Position Range: position = 0 % ... 100 %<br>
      Slat Angle Range: &alpha; = 0 % ... 100 %<br>
      The devive can only fully controlled if the attributes <a href="#EnOcean_alarmAction">alarmAction</a>,
      <a href="#angleTime">angleTime</a>, <a href="#EnOcean_reposition">reposition</a> and <a href="#shutTime">shutTime</a>
      are set correctly.<br>
      The attr subType must be blindsCtrl.00. This is done if the device was
      created by autocreate. To control the device, it must be bidirectional paired,
      see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>
      
    <li>Room Control Panels (D2-10-00 - D2-10-02)<br>
        [Kieback & Peter RBW322-FTL]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>buildingProtectionTemp t/&#176C<br>
        set building protection temperature</li>
      <li>clearCmds [&lt;channel&gt;]<br>
        clear waiting commands</li>
      <li>comfortTemp t/&#176C<br>
        set comfort temperature</li>
      <li>config<br>
        Setting the configuration of the room controller, the configuration parameters are set using attributes.</li>
      <li>cooling auto|off|on|no_change<br>
        switch cooling</li>
      <li>deleteTimeProgram<br> 
        delete time programs of the room controller</li>
      <li>desired-temp t/&#176C<br>
        set setpoint temperature</li>
      <li>economyTemp t/&#176C<br>
        set economy temperature</li>
      <li>fanSpeed fanspeed/%<br>
        set fan speed</li>
      <li>fanSpeedMode central|local<br>
        set fan speed mode</li>
      <li>heating auto|off|on|no_change<br>
        switch heating</li>
      <li>preComfortTemp t/&#176C<br>
        set pre comfort temperature</li>
      <li>roomCtrlMode buildingProtectionTemp|comfortTemp|economyTemp|preComfortTemp<br>
        select setpoint temperature</li>
      <li>setPointTemp t/&#176C<br>
        set current setpoint temperature</li>
      <li>time<br>
        set time and date of the room controller </li>
      <li>timeProgram<br>
        set time programms of the room contoller</li>
      <li>window closed|open<br>
        put the window state</li>
    </ul><br>
       Setpoint Range: t = 0 &#176C ... 40 &#176C<br>
       The room controller is configured using the following attributes:<br>
       <ul>
       <li><a href="#EnOcean_blockDateTime">blockDateTime</a></li>
       <li><a href="#EnOcean_blockDisplay">blockDisplay</a></li>
       <li><a href="#EnOcean_blockFanSpeed">blockFanSpeed</a></li>
       <li><a href="#EnOcean_blockMotion">blockMotion</a></li>
       <li><a href="#EnOcean_blockProgram">blockProgram</a></li>
       <li><a href="#EnOcean_blockOccupany">blockOccupancy</a></li>
       <li><a href="#EnOcean_blockTemp">blockTemp</a></li>
       <li><a href="#EnOcean_blockTimeProgram">blockTimeProgram</a></li>
       <li><a href="#EnOcean_blockSetpointTemp">blockSetpointTemp</a></li>
       <li><a href="#EnOcean_daylightSavingTime">daylightSavingTime</a></li>
       <li><a href="#EnOcean_displayContent">displayContent</a></li>
       <li><a href="#EnOcean_pollInterval">pollInterval</a></li>
       <li><a href="#EnOcean_temperatureScale">temperatureScale</a></li>
       <li><a href="#EnOcean_timeNotation">timeNotation</a></li>
       <li><a href="#EnOcean_timeProgram[1-4]">timeProgram[1-4]</a></li>
       </ul>
       The attr subType must be roomCtrlPanel.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>
  
    <li>Fan Control (D2-20-00 - D2-20-02)<br>
        [Maico ECA x RC/RCH, ER 100 RC, untested]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>on<br>
        fan on</li>
      <li>off<br>
        fan off</li>
      <li>desired-temp [t/&#176C]<br>
        set setpoint temperature</li>
      <li>fanSpeed fanspeed/%|auto|default<br>
        set fan speed</li>
      <li>humidityThreshold rH/%<br> 
        set humidity threshold</li>
      <li>roomSize 0...350/m<sup>2</sup>|default|not_used<br>
        set room size</li>
      <li>setPointTemp [t/&#176C]<br>
        set current setpoint temperature</li>
    </ul><br>
       Setpoint Range: t = 0 &#176C ... 40 &#176C<br>
       The fan controller is configured using the following attributes:<br>
       <ul>
       <li><a href="#EnOcean_setCmdTrigger">setCmdTrigger</a></li>
       <li><a href="#EnOcean_switchHysteresis">switchHysteresis</a></li>
       <li><a href="#temperatureRefDev">temperatureRefDev</a></li>
       </ul>
       The attr subType must be fanCtrl.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>. The profile
       behaves like a master. Only one fan can be taught as a slave.
    </li>
    <br><br>
  
    <li>Valve Control (EEP D2-A0-01)<br>        
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
         <li>closes<br>
          issue closes command (master)</li>
         <li>opens<br>
          issue opens command (master)</li>
         <li>closed<br>
          issue closed command (slave)</li>
         <li>open<br>
          issue open command (slave)</li>
         <li>teachIn<br>
          initiate UTE teach-in (slave)</li>
         <li>teachOut<br>
          initiate UTE teach-out (slave)</li>
    </ul><br>
       The valve controller is configured using the following attributes:<br>
       <ul>
       <li><a href="#EnOcean_devMode">devMode</a></li>
       </ul>
       The attr subType must be valveCtrl.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>. The profile
       behaves like a master or slave, see <a href="#EnOcean_devMode">devMode</a>. 
    </li>
    <br><br>
 
    <li>RAW Command<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>1BS|4BS|GPCD|GPSD|GPTI|GPTR|MSC|RPS|UTE|VLD data [status]<br>
        sent data telegram</li>
    </ul><br>
    [data] = &lt;1-byte hex ... 512-byte hex&gt;<br>
    [status] = 0x00 ... 0xFF<br>
    With the help of this command data messages in hexadecimal format can be sent.
    Telegram types (RORG) 1BS, 4BS, RPS, MSC, UTE, VLD, GPCD, GPSD, GPTI and GPTR are supported.
    For further information, see <a href="http://www.enocean-alliance.org/eep/">EnOcean Equipment Profiles (EEP)</a> and
    Generic Profiles. 
    </li>
    <br><br>
  </ul></ul>
  
  <a name="EnOceanget"></a>
  <b>Get</b>
  <ul>
    <li>Electronic switches and dimmers with Energy Measurement and Local Control (D2-01-00 - D2-01-11)<br>
        [Telefunken Funktionsstecker, PEHA Easyclick, AWAG Elektrotechnik AG Omnio UPS 230/xx,UPD 230/xx]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
       <li>state [&lt;channel&gt;]<br>
       </li>
       <li>measurement &lt;channel&gt; energy|power<br>
       </li>
       <li>special &lt;channel&gt; health|load|voltage|serialNumber<br>
       additional Permondo SmartPlug PSC234 commands
       </li>

    </ul><br>
       The default channel can be specified with the attr <a href="#EnOcean_defaultChannel">defaultChannel</a>.<br>     
       The attr subType must be actuator.01. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>
    
    <li>Extended Lighting Control (EEP A5-38-09)<br>
         [untested]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>status<br>
        status request</li>
    </ul><br>
        The attr subType or subTypSet must be lightCtrl.01. This is done if the device was created by autocreate.<br>
        The subType is associated with the subtype lightCtrlState.02.
    </li>
    <br><br>

    <li>Blind Control for Position and Angle (D2-05-00)<br>
        [AWAG Elektrotechnik AG OMNIO UPJ 230/12]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>position<br>
        query position and angle value</li>
    </ul><br>
      The devive can only fully controlled if the attributes <a href="#EnOcean_alarmAction">alarmAction</a>,
      <a href="#angleTime">angleTime</a>, <a href="#EnOcean_reposition">reposition</a> and <a href="#shutTime">shutTime</a>
      are set correctly.<br>
      The attr subType must be blindsCtrl.00. This is done if the device was
      created by autocreate. To control the device, it must be bidirectional paired,
      see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Room Control Panels (D2-10-00 - D2-10-02)<br>
        [Kieback & Peter RBW322-FTL]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
       <li>config<br>
         get the configuration of the room controler</li>
       <li>data<br>
         get data</li>
       <li>roomCtrl<br>
         get the parameter of the room controler</li>
       <li>timeProgram<br>
         get the time program</li>
    </ul><br>
       The attr subType must be roomCtrlPanel.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>
  
    <li>Fan Control (D2-20-00 - D2-20-02)<br>
        [Maico ECA x RC/RCH, ER 100 RC, untested]<br>
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
       <li>state<br>
         get the state of the room controler</li>
    </ul><br>
       The attr subType must be fanCtrl.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <br><br>

    <li>Valve Control (EEP D2-A0-01)<br>        
    <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
        <li>state<br>
         get the state of the valve controler (master)</li>
    </ul><br>
      The attr subType must be valveCtrl.00. This is done if the device was
      created by autocreate. To control the device, it must be bidirectional paired,
      see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>. The profile
      behaves like a master or slave, see <a href="#EnOcean_devMode">devMode</a>. 
    </li>
    <br><br>
 
  </ul><br>

  <a name="EnOceanattr"></a>
  <b>Attributes</b>
  <ul>
    <ul>
    <li><a name="actualTemp">actualTemp</a> t/&#176C<br>
      The value of the actual temperature, used by a Room Sensor and Control Unit
      or when controlling HVAC components e. g. Battery Powered Actuators (MD15 devices). Should by
      filled via a notify from a distinct temperature sensor.<br>
      If absent, the reported temperature from the HVAC components is used.
    </li>
    <li><a name="EnOcean_alarmAction">alarmAction</a> no|stop|opens|closes<br>
      Action that is executed before the actuator is entering the "alarm" mode.<br>
      Notice subType blindsCrtl.00: The attribute can only be set while the actuator is online.    </li>
    <li><a name="angleMax">angleMax</a> &alpha;s/&#176, [&alpha;s] = -180 ... 180, 90 is default.<br>
      Slat angle end position maximum.<br>
      angleMax is supported for shutter.
    </li>
    <li><a name="angleMin">angleMin</a> &alpha;o/&#176, [&alpha;o] = -180 ... 180, -90 is default.<br>
      Slat angle end position minimum.<br>
      angleMin is supported for shutter.
    </li>
    <li><a name="angleTime">angleTime</a> t/s,<br>
      subType blindsCtrl.00: [angleTime] = 0|0.01 .. 2.54, 0 is default.<br>
      subType manufProfile: [angleTime] = 0 ... 6, 0 is default.<br>
      Runtime value for the sunblind reversion time. Select the time to revolve
      the sunblind from one slat angle end position to the other end position.<br>
      Notice subType blindsCrtl.00: The attribute can only be set while the actuator is online.
    </li>
    <li><a name="EnOcean_blockDateTime">blockDateTime</a> yes|no, [blockDateTime] = no is default.<br>
      blockDateTime is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockDisplay">blockDisplay</a> yes|no, [blockDisplay] = no is default.<br>
      blockDisplay is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockFanSpeed">blockFanSpeed</a> yes|no, [blockFanSpeed] = no is default.<br>
      blockFanSpeed is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockKey">blockKey</a> yes|no, [blockKey] = no is default.<br>
      blockKey is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockMotion">blockMotion</a> yes|no, [blockMotion] = no is default.<br>
      blockMotion is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockOccupany">blockOccupancy</a> yes|no, [blockOccupancy] = no is default.<br>
      blockOccupancy is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockTemp">blockTemp</a> yes|no, [blockTemp] = no is default.<br>
      blockTemp is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockTimeProgram">blockTimeProgram</a> yes|no, [blockTimeProgram] = no is default.<br>
      blockTimeProgram is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockSetpointTemp">blockSetpointTemp</a> yes|no, [blockSetpointTemp] = no is default.<br>
      blockSetPointTemp is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_blockUnknownMSC">blockUnknownMSC</a> yes|no,
      [blockUnknownMSC] = no is default.<br>
      If the structure of the MSC telegrams can not interpret the raw data to be output. Setting this attribute to yes,
      the output can be suppressed.
    </li>
    <li><a name="comMode">comMode</a> biDir|confirm|uniDir, [comMode] = uniDir is default.<br>
      Communication Mode between an enabled EnOcean device and Fhem.<br>
      Unidirectional communication means a point-to-multipoint communication
      relationship. The EnOcean device e. g. sensors does not know the unique
      Fhem SenderID.<br>
      If the attribute is set to confirm Fhem awaits confirmation telegrams from the remote device.<br>
      Bidirectional communication means a point-to-point communication
      relationship between an enabled EnOcean device and Fhem. It requires all parties
      involved to know the unique Sender ID of their partners. Bidirectional communication
      needs a teach-in / teach-out process, see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
    </li>
    <li><a name="EnOcean_dataEnc">dataEnc</a> VAES|AES-CBC, [dataEnc] = VAES is default<br>
      Data encryption algorithm
    </li>
    <li><a name="EnOcean_defaultChannel">defaultChannel</a> all|input|0 ... 29, [defaultChannel] = all is default<br>
      Default device channel
    </li>
    <li><a name="EnOcean_daylightSavingTime">daylightSavingTime</a> supported|not_supported, [daylightSavingTime] = supported is default.<br>
      daylightSavingTime is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_demandRespAction">demandRespAction</a> &lt;command&gt;<br>
      Command being executed after an demand response command is set.  If &lt;command&gt; is enclosed in {},
      then it is a perl expression, if it is enclosed in "", then it is a shell command,
      else it is a "plain" fhem.pl command (chain). In the &lt;command&gt; you can access the demand response 
      readings $TYPE, $NAME, $LEVEL, $SETPOINT, $POWERUSAGE, $POWERUSAGESCALE, $POWERUSAGELEVEL, $STATE. In addition,
      the variables $TARGETNAME, $TARGETTYPE, $TARGETSTATE can be used if the action is executed
      on the target device. This data is available as a local variable in perl, as environment variable for shell
      scripts, and will be textually replaced for Fhem commands.
    </li>
    <li><a name="EnOcean_demandRespMax">demandRespMax</a> A0|AI|B0|BI|C0|CI|D0|DI, [demandRespMax] = B0 is default<br>
      Switch command which is executed if the demand response switches to a maximum.
    </li>
    <li><a name="EnOcean_demandRespMin">demandRespMin</a> A0|AI|B0|BI|C0|CI|D0|DI, [demandRespMax] = BI is default<br>
      Switch command which is executed if the demand response switches to a minimum.
    </li>
    <li><a name="EnOcean_demandRespRefDev">demandRespRefDev</a> &lt;name&gt;<br>
    </li>
    <li><a name="EnOcean_demandRespRandomTime">demandRespRandomTime</a> t/s [demandRespRandomTime] = 1 is default<br>
      Maximum length of the random delay at the start or end of a demand respose event in slave mode.
    </li>
    <li><a name="EnOcean_demandRespThreshold">demandRespThreshold</a> 0...15 [demandRespTheshold] = 8 is default<br>
      Threshold for switching the power usage level between minimum and maximum in the master mode.
    </li>
    <li><a name="EnOcean_demandRespTimeoutLevel">demandRespTimeoutLevel</a> max|last [demandRespTimeoutLevel] = max is default<br>
      Demand response timeout level in slave mode.
    </li>
    <li><a name="devChannel">devChannel</a> 00 ... FF, [devChannel] = FF is default<br>
      Number of the individual device channel, FF = all channels supported by the device 
    </li>
    <li><a name="destinationID">destinationID</a> multicast|unicast|00000001 ... FFFFFFFF,
      [destinationID] = multicast is default<br>
      Destination ID, special values: multicast = FFFFFFFF, unicast = [DEF]
    </li>
    <li><a name="EnOcean_devMode">devMode</a> master|slave, [devMode] = master is default.<br>
      device operation mode.
    </li>
    <li><a href="#devStateIcon">devStateIcon</a></li>
    <li><a name="EnOcean_dimMax">dimMax</a> dim/%|off, [dimMax] = 255 is default.<br>
      maximum brightness value<br>
      dimMax is supported for the profile gateway/dimming.
      </li>
    <li><a name="EnOcean_dimMin">dimMin</a> dim/%|off, [dimMax] = off is default.<br>
      minimum brightness value<br>
      If [dimMax] = off, then the actuator takes down the ramp time set there.
      dimMin is supported for the profile gateway/dimming.
      </li>
    <li><a name="dimValueOn">dimValueOn</a> dim/%|last|stored,
      [dimValueOn] = 100 is default.<br>
      Dim value for the command "on".<br>
      The dimmer switched on with the value 1 % ... 100 % if [dimValueOn] =
      1 ... 100.<br>
      The dimmer switched to the last dim value received from the
      bidirectional dimmer if [dimValueOn] = last.<br>
      The dimmer switched to the last Fhem dim value if [dimValueOn] =
      stored.<br>
      dimValueOn is supported for the profile gateway/dimming.
      </li>
    <li><a href="#EnOcean_disable">disable</a> 0|1<br>
      If applied set commands will not be executed.
    </li>
    <li><a href="#EnOcean_disabledForIntervals">disabledForIntervals</a> HH:MM-HH:MM HH:MM-HH-MM...<br>
      Space separated list of HH:MM tupels. If the current time is between
      the two time specifications, set commands will not be executed. Instead of
      HH:MM you can also specify HH or HH:MM:SS. To specify an interval
      spawning midnight, you have to specify two intervals, e.g.:
      <ul>
        23:00-24:00 00:00-01:00
      </ul>
    </li>
    <li><a name="EnOcean_displayContent">displayContent</a>
      humidity|off|setPointTemp|temperatureExtern|temperatureIntern|time|default|no_change, [displayContent] = no_change is default.<br>
      displayContent is supported for roomCtrlPanel.00.
    </li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a name="EnOcean_eep">eep</a> [00...FF].[00...3F].[00...7F]<br>
      EnOcean Equipment Profile (EEP)
      </li>
    <li><a name="gwCmd">gwCmd</a> switching|dimming|setpointShift|setpointBasic|controlVar|fanStage|blindCmd<br>
      Gateway Command Type, see <a href="#Gateway">Gateway</a> profile
      </li>
    <li><a name="EnOcean_humidity">humidity</a> t/&#176C<br>
      The value of the actual humidity, used by a Room Sensor and Control Unit. Should by
      filled via a notify from a distinct humidity sensor.
    </li>
    <li><a name="EnOcean_humidityRefDev">humidityRefDev</a> &lt;name&gt;<br>
      Name of the device whose reference value is read. The reference values is
      the reading humidity.
    </li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a name="EnOcean_keyRcv">keyRcv</a> &lt;private key 16 byte hex&gt;<br>
      Private Key for receive direction
    </li>
    <li><a name="EnOcean_keySnd">keySnd</a> &lt;private key 16 byte hex&gt;<br>
      Private Key for send direction
    </li>
    <li><a name="EnOcean_macAlgo">macAlgo</a> no|3|4<br>
      MAC Algorithm
    </li>
    <li><a href="#model">model</a></li>
    <li><a name="EnOcean_observe">observe</a> off|on, [observe] = off is default.<br>
      Observing and repeating the execution of set commands
    </li>
    <li><a name="EnOcean_observeCmdRepetition">observeCmdRepetition</a> 1..5, [observeCmdRepetition] = 2 is default.<br>
      Maximum number of command retries
    </li>
    <li><a name="EnOcean_observeErrorAction">observeErrorAction</a> &lt;command&gt;<br>
      Command being executed after an error.  If &lt;command&gt; is enclosed in {},
      then it is a perl expression, if it is enclosed in "", then it is a shell command,
      else it is a "plain" fhem.pl command (chain). In the &lt;command&gt; you can access the set
      command. $TYPE, $NAME, $FAILEDDEV, $EVENT, $EVTPART0, $EVTPART1, $EVTPART2, etc. contains the space separated
      set parts. The <a href="#eventMap">eventMap</a> replacements are taken into account. This data
      is available as a local variable in perl, as environment variable for shell
      scripts, and will be textually replaced for Fhem commands.
    </li>
    <li><a name="EnOcean_observeLogic">observeLogic</a> and|or, [observeLogic] = or is default.<br>
      Observe logic
    </li>
    <li><a name="EnOcean_observeRefDev">observeRefDev</a> &lt;name&gt; [&lt;name&gt; [&lt;name&gt;]],
      [observeRefDev] = &lt;name of the own device&gt; is default<br>
      Names of the devices to be observed. The list must be separated by spaces.
    </li>
    <li><a name="EnOcean_pollInterval">pollInterval</a> t/s, [pollInterval] = 10 is default.<br>
      [pollInterval] = 1 ... 1440.<br>
      pollInterval is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_rampTime">rampTime</a> t/s or relative, [rampTime] = 1 is default.<br>
      No ramping or for Eltako dimming speed set on the dimmer if [rampTime] = 0.<br>
      Gateway/dimmung: Ramping time 1 s to 255 s or relative fast to low dimming speed if [rampTime] = 1 ... 255.<br>
      lightCtrl.01: Ramping time 1 s to 65535 s<br>
      rampTime is supported for gateway, command dimming and lightCtrl.01.
      </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a name="EnOcean_remoteManagement">remoteManagement</a> off|on,
      [remoteManagement] = off is default.<br>
      Enable Remote Management for the device.
    </li>
    <li><a name="repeatingAllowed">repeatingAllowed</a> yes|no,
      [repeatingAllowed] = yes is default.<br>
      EnOcean Repeater in the transmission range of Fhem may forward data messages
      of the device, if the attribute is set to yes.
    </li>
    <li><a name="EnOcean_releasedChannel">releasedChannel</a> A|B|C|D|I|0|auto, [releasedChannel] = auto is default.<br>
      Attribute releasedChannel determines via which SenderID (subDefA ... subDef0) the command released is sent.
      If [releasedChannel] = auto, the SenderID the last command A0, AI, B0, BI, C0, CI, D0 or DI is used.
      Attribute releasedChannel is supported for attr switchType = central and attr switchType = channel. 
      </li>
    <li><a name="EnOcean_reposition">reposition</a> directly|opens|closes, [reposition] = directly is default.<br>
      Attribute reposition specifies how to adjust the internal positioning tracker before going to the new position.
      </li>
    <li><a name="EnOcean_rlcAlgo">rlcAlgo</a> 2++|3++<br>
      RLC Algorithm
    </li>
    <li><a name="EnOcean_rlcRcv">rlcRcv</a> &lt;rolling code 2 or 3 byte hex&gt;<br>
      Rolling Code for receive direction
    </li>
    <li><a name="EnOcean_rlcSnd">rlcSnd</a> &lt;rolling code 2 or 3 byte hex&gt;<br>
      Rolling Code for send direction
    </li>
    <li><a name="EnOcean_rlcTX">rlcTX</a> false|true<br>
      Rolling Code is expected in the received telegram
    </li>
    <li><a name="scaleDecimals">scaleDecimals</a> 0 ... 9<br>
      Decimal rounding with x digits of the scaled reading setpoint
    </li>
    <li><a name="scaleMax">scaleMax</a> &lt;floating-point number&gt;<br>
      Scaled maximum value of the reading setpoint
    </li>
    <li><a name="scaleMin">scaleMin</a> &lt;floating-point number&gt;<br>
      Scaled minimum value of the reading setpoint
    </li>
    <li><a name="EnOcean_secLevel">secLevel</a> encapsulation|encryption|off, [secLevel] = off is default<br>
      Security level of the data
    </li>
    <li><a name="EnOcean_secMode">secMode</a> rcv|snd|bidir<br>
      Telegram direction, which is secured
    </li>
    <li><a name="EnOcean_sendDevStatus">sendDevStatus</a> no|yes, [sendDevStatus] = no is default.<br>
      Send new status of the device.
    </li>
    <li><a name="EnOcean_serviceOn">serviceOn</a> no|yes,
      [serviceOn] = no is default.<br>
      Device in Service Mode.
    </li>
    <li><a name="sensorMode">switchMode</a> switch|pushbutton,
      [sensorMode] = switch is default.<br>
      The status "released" will be shown in the reading state if the
      attribute is set to "pushbutton".
    </li>
    <li><a name="EnOcean_setCmdTrigger">setCmdTrigger</a> man|refDev, [setCmdTrigger] = man is default.<br>
      Operation mode to send set commands<br>
      If the attribute is set to "refDev", a device-specific set command is sent when the reference device is updated.
      For the subType "roomSensorControl.05" and "fanCrtl.00"  the reference "temperatureRefDev" is supported.<br>
      For the subType "roomSensorControl.01" the references "humidityRefDev" and "temperatureRefDev" are supported.<br>
      </li>
    <li><a href="#showtime">showtime</a></li>
    <li><a name="shutTime">shutTime</a> t/s<br>
      subType blindsCtrl.00: [shutTime] = 5 ... 300, 300 is default.<br>
      subType manufProfile: [shutTime] = 1 ... 255, 255 is default.<br>
      Use the attr shutTime to set the time delay to the position "Halt" in
      seconds. Select a delay time that is at least as long as the shading element
      or roller shutter needs to move from its end position to the other position.<br>
      Notice subType blindsCrtl.00: The attribute can only be set while the actuator is online.
      </li>
    <li><a name="shutTimeCloses">shutTimeCloses</a> t/s, [shutTimeCloses] = 1 ... 255,
      [shutTimeCloses] = [shutTime] is default.<br>
      Set the attr shutTimeCloses to define the runtime used by the commands opens and closes.
      Select a runtime that is at least as long as the value set by the delay switch of the actuator.
      <br>
      shutTimeCloses is supported for shutter.
      </li>
    <li><a name="subDef">subDef</a> &lt;EnOcean SenderID&gt;,
      [subDef] = [DEF] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) to control a bidirectional switch or actor.<br>
      In order to control devices that send acknowledge telegrams, you cannot reuse the ID of this
      devices, instead you have to create your own, which must be in the
      allowed ID-Range of the underlying IO device. For this first query the
      <a href="#TCM">TCM</a> with the "<code>get &lt;tcm&gt; idbase</code>" command. You can use
      up to 128 IDs starting with the base shown there.<br>
      If [subDef] = getNextID FHEM can assign a free SenderID alternatively. The system configuration
      needs to be reloaded. The assigned SenderID will only displayed after the system configuration
      has been reloaded, e.g. Fhem command rereadcfg.
      </li>
    <li><a name="subDefA">subDefA</a> &lt;EnOcean SenderID&gt;,
      [subDefA] = [subDef] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = A0|AI|released<br>
      Used with switch type "channel". Set attr switchType to channel.<br>
      subDefA is supported for switches.<br>
      Second action is not sent.<br>
      If [subDefA] = getNextID FHEM can assign a free SenderID alternatively. The assigned SenderID will only
      displayed after the system configuration has been reloaded, e.g. Fhem command rereadcfg.
      </li>
    <li><a name="subDefB">subDefB</a> &lt;EnOcean SenderID&gt;,
      [subDefB] = [subDef] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = B0|BI|released<br>
      Used with switch type "channel". Set attr switchType to channel.<br>
      subDefB is supported for switches.<br>
      Second action is not sent.<br>
      If [subDefB] = getNextID FHEM can assign a free SenderID alternatively. The assigned SenderID will only
      displayed after the system configuration has been reloaded, e.g. Fhem command rereadcfg.
      </li>
    <li><a name="subDefC">subDefC</a> &lt;EnOcean SenderID&gt;,
      [subDefC] = [subDef] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = C0|CI|released<br>
      Used with switch type "channel". Set attr switchType to channel.<br>
      subDefC is supported for switches.<br>
      Second action is not sent.<br>
      If [subDefC] = getNextID FHEM can assign a free SenderID alternatively. The assigned SenderID will only
      displayed after the system configuration has been reloaded, e.g. Fhem command rereadcfg.
      </li>
    <li><a name="subDefD">subDefD</a> &lt;EnOcean SenderID&gt;,
      [subDefD] = [subDef] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = D0|DI|released<br>
      Used with switch type "channel". Set attr switchType to channel.<br>
      subDefD is supported for switches.<br>
      Second action is not sent.<br>
      If [subDefD] = getNextID FHEM can assign a free SenderID alternatively. The assigned SenderID will only
      displayed after the system configuration has been reloaded, e.g. Fhem command rereadcfg.
      </li>
    <li><a name="subDef0">subDef0</a> &lt;EnOcean SenderID&gt;,
      [subDef0] = [subDef] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = A0|B0|C0|D0|released<br>
      Used with switch type "central". Set attr switchType to central.<br>
      Use the sensor type "zentral aus/ein" for Eltako devices.<br>
      subDef0 is supported for switches.<br>
      Second action is not sent.<br>
      If [subDef0] = getNextID FHEM can assign a free SenderID alternatively. The assigned SenderID will only
      displayed after the system configuration has been reloaded, e.g. Fhem command rereadcfg.
      </li>
    <li><a name="subDefI">subDefI</a> &lt;EnOcean SenderID&gt;,
      [subDefI] = [subDef] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = AI|BI|CI|DI<br>
      Used with switch type "central". Set attr switchType to central.<br>
      Use the sensor type "zentral aus/ein" for Eltako devices.<br>
      subDefI is supported for switches.<br>
      Second action is not sent.<br>
      If [subDefI] = getNextID FHEM can assign a free SenderID alternatively. The assigned SenderID will only
      displayed after the system configuration has been reloaded, e.g. Fhem command rereadcfg.
      </li>
    <li><a href="#subType">subType</a></li>
    <li><a name="subTypeSet">subTypeSet</a> &lt;type of device&gt;, [subTypeSet] = [subType] is default.<br>
      Type of device (EEP Profile) used for sending commands. Set the Attribute manually.
      The profile has to fit their basic profile. More information can be found in the basic profiles.
    </li>
    <li><a name="EnOcean_summerMode">summerMode</a> off|on,
      [summerMode] = off is default.<br>
      Put Battery Powered Actuator (hvac.01) in summer operation to reduce energy consumption.
    </li>
    <li><a name="EnOcean_switchHysteresis">switchHysteresis</a> &lt;value&gt;,
      [switchHysteresis] = 1 is default.<br>
      Switch Hysteresis
    </li>
    <li><a name="switchMode">switchMode</a> switch|pushbutton,
      [switchMode] = switch is default.<br>
      The set command "released" immediately after &lt;value&gt; is sent if the
      attribute is set to "pushbutton".
    </li>
    <li><a name="switchType">switchType</a> direction|universal|central|channel,
      [switchType] = direction is default.<br>
      EnOcean Devices support different types of sensors, e. g. direction
      switch, universal switch or pushbutton, central on/off.<br>
      For Eltako devices these are the sensor types "Richtungstaster",
      "Universalschalter" or "Universaltaster", "Zentral aus/ein".<br>
      With the sensor type <code>direction</code> switch on/off commands are
      accepted, e. g. B0, BI, released. Fhem can control an device with this
      sensor type unique. This is the default function and should be
      preferred.<br>
      Some devices only support the <code>universal switch
      </code> or <code>pushbutton</code>. With a Fhem command, for example,
      B0 or BI is switched between two states. In this case Fhem cannot
      control this device unique. But if the Attribute <code>switchType
      </code> is set to <code>universal</code> Fhem synchronized with
      a bidirectional device and normal on/off commands can be used.
      If the bidirectional device response with the channel B
      confirmation telegrams also B0 and BI commands are to be sent,
      e g. channel A with A0 and AI. Also note that confirmation telegrams
      needs to be sent.<br>
      Partly for the switchType <code>central</code> two different SenderID
      are required. In this case set the Attribute <code>switchType</code> to
      <code>central</code> and define the Attributes
      <a href="#subDef0">subDef0</a> and <a href="#subDefI">subDefI</a>.<br>
      Furthermore, SenderIDs can be used depending on the channel A, B, C or D.
      In this case set the Attribute switchType to <code>channel</code> and define
      the Attributes <a href="#subDefA">subDefA</a>, <a href="#subDefB">subDefB</a>,
      <a href="#subDefC">subDefC</a>, or <a href="#subDefD">subDefD</a>. 
      </li>
    <li><a name="temperatureRefDev">temperatureRefDev</a> &lt;name&gt;<br>
      Name of the device whose reference value is read. The reference values is
      the reading temperature.
    </li>
    <li><a name="EnOcean_temperatureScale">temperatureScale</a> F|C|default|no_change, [temperatureScale] = no_change is default.<br>
      temperatureScale is supported for roomCtrlPanel.00.
      </li>      
    <li><a name="EnOcean_timeNotation">timeNotation</a> 12|24|default|no_change, [timeNotation] = no_change is default.<br>
      timeNotation is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_timeProgram[1-4]">timeProgram[1-4]</a> &lt;period&gt; &lt;starttime&gt; &lt;endtime&gt; &lt;roomCtrlMode&gt;, [timeProgam[1-4]] = &lt;none&gt; is default.<br>
      [period] = FrMo|FrSu|ThFr|WeFr|TuTh|MoWe|SaSu|MoFr|MoSu|Su|Sa|Fr|Th|We|Tu|Mo<br>
      [starttime] = [00..23]:[00|15|30|45]<br>
      [endtime] = [00..23]:[00|15|30|45]<br>
      [roomCtrlMode] = buildingProtection|comfort|economy|preComfort<br>
      The Room Control Panel Kieback & Peter RBW322-FTL supports only [roomCtrlMode] = comfort.<br>    
      timeProgram is supported for roomCtrlPanel.00.
      </li>
    <li><a name="EnOcean_updateState">updateState</a> default|yes|no, [updateState] = default is default.<br>
      update reading state after set commands
      </li>
    <li><a name="EnOcean_uteResponseRequest">uteResponseRequest</a> yes|no<br>
      request UTE teach-in/teach-out response message, the standard value depends on the EEP profil
      </li>
    <li><a href="#verbose">verbose</a></li>
    <li><a href="#webCmd">webCmd</a></li>
    </ul>
  </ul>
  <br>

  <a name="EnOceanevents"></a>
  <b>Generated events</b>
  <ul>
    <ul>
     <li>Switch (EEP F6-02-01 ... F6-03-02)<br>
     <ul>
         <li>A0</li>
         <li>AI</li>
         <li>B0</li>
         <li>BI</li>
         <li>C0</li>
         <li>CI</li>
         <li>D0</li>
         <li>DI</li>
         <li>&lt;BtnX,BtnY&gt; First and second action where BtnX and BtnY is
             one of the above, e.g. A0 BI or D0 CI</li>
         <li>buttons: pressed|released</li>
         <li>state: &lt;BtnX&gt;[,&lt;BtnY&gt;]</li>
     </ul><br>
         Switches (remote controls) or actors with more than one
         (pair) keys may have multiple channels e. g. B0/BI, A0/AI with one
         SenderID or with separate addresses.
     </li>
     <br><br>

     <li>Pushbutton Switch, Pushbutton Input Module (EEP F6-02-01 ... F6-02-02)<br>
         [Eltako FT55, FSM12, FSM61, FTS12]<br>
     <ul>
         <li>A0</li>
         <li>AI</li>
         <li>B0</li>
         <li>BI</li>
         <li>C0</li>
         <li>CI</li>
         <li>D0</li>
         <li>DI</li>
         <li>&lt;BtnX,BtnY&gt; First and second action where BtnX and BtnY is
             one of the above, e.g. A0,BI or D0,CI</li>
         <li>released</li>
         <li>buttons: pressed|released</li>         
         <li>state: &lt;BtnX&gt;[,&lt;BtnY&gt;] [released]</li>
     </ul><br>
         The status of the device may become "released", this is not the case for a normal switch.<br>
         Set attr model to FT55|FSM12|FSM61|FTS12 or attr sensorMode to pushbutton manually.
     </li>
     <br><br>

     <li>Pushbutton Switch (EEP F6-3F-7F)<br>
         [Eltako FGW14/FAM14 with internal decryption and RS-485 communication]<br>
     <ul>
         <li>A0</li>
         <li>AI</li>
         <li>B0</li>
         <li>BI</li>
         <li>C0</li>
         <li>CI</li>
         <li>D0</li>
         <li>DI</li>
         <li>&lt;BtnX,BtnY&gt; First and second action where BtnX and BtnY is
             one of the above, e.g. A0,BI or D0,CI</li>
         <li>released</li>
         <li>buttons: pressed|released</li>         
         <li>state: &lt;BtnX&gt;[,&lt;BtnY&gt;] [released]</li>
     </ul><br>
         Set attr subType to switch.7F and manufID to 00D.<br>
         The status of the device may become "released", this is not the case for
         a normal switch. Set attr sensorMode to pushbutton manually.
     </li>
     <br><br>

     <li>Pushbutton Switch (EEP D2-03-00)<br>
         [EnOcean PTM 215 Modul]<br>
     <ul>
         <li>A0</li>
         <li>AI</li>
         <li>B0</li>
         <li>BI</li>
         <li>&lt;BtnX,BtnY&gt; First and second action where BtnX and BtnY is
             one of the above, e.g. A0,BI</li>
         <li>pressed</li>
         <li>released</li>
         <li>teachIn</li>
         <li>teachOut</li>
         <li>energyBow: pressed|released</li>         
         <li>state: &lt;BtnX&gt;|&lt;BtnX&gt;,&lt;BtnY&gt;|released|pressed|teachIn|teachOut</li>
     </ul><br>
        The attr subType must be switch.00. This is done if the device was
        created by autocreate. Set attr sensorMode to pushbutton manually if needed.
     </li>
     <br><br>

     <li>Smoke Detector (EEP F6-02-01 ... F6-02-02)<br>
         [Eltako FRW]<br>
     <ul>
         <li>smoke-alarm</li>
         <li>off</li>
         <li>alarm: smoke-alarm|off</li>
         <li>battery: low|ok</li>
         <li>buttons: pressed|released</li>         
         <li>state: smoke-alarm|off</li>
     </ul><br>
        Set attr subType to FRW manually.
     </li>
     <br><br>

     <li>Heating/Cooling Relay (EEP F6-02-01 ... F6-02-02)<br>
         [Eltako FAE14, FHK14, untested]<br>
     <ul>
         <li>controllerMode: auto|off</li>
         <li>energyHoldOff: normal|holdoff</li>
         <li>buttons: pressed|released</li>         
     </ul><br>
        Set attr subType to switch and model to FAE14|FHK14 manually. In addition
        every telegram received from a teached-in temperature sensor (e.g. FTR55H)
        is repeated as a confirmation telegram from the Heating/Cooling Relay
        FAE14, FHK14. In this case set attr subType to e. g. roomSensorControl.05
        and attr manufID to 00D.
     </li>
     <br><br>

     <li>Key Card Activated Switch (EEP F6-04-01)<br>
         [Eltako FKC, FKF, FZS, untested]<br>
     <ul>
         <li>keycard_inserted</li>
         <li>keycard_removed</li>
         <li>state: keycard_inserted|keycard_removed</li>
     </ul><br>
         Set attr subType to keycard manually.
     </li>
     <br><br>

     <li>Liquid Leakage Sensor (EEP F6-05-01)<br>
         [untested]<br>
     <ul>
         <li>dry</li>
         <li>wet</li>
         <li>state: dry|wet</li>
     </ul><br>
         Set attr subType to liquidLeakage manually.
     </li>
     <br><br>

     <li>Window Handle (EEP F6-10-00, D2-03-10)<br>
         [HOPPE SecuSignal, Eltako FHF, Eltako FTKE]<br>
     <ul>
         <li>closed</li>
         <li>open</li>
         <li>tilted</li>
         <li>open_from_tilted</li>
         <li>state: closed|open|tilted|open_from_tilted</li>
     </ul><br>
        The device windowHandle or windowHandle.10 should be created by autocreate.
     </li>
     <br><br>

     <li>Single Input Contact, Door/Window Contact<br>
         1BS Telegram (EEP D5-00-01)<br>
         [EnOcean STM 320, STM 329, STM 250, Eltako FTK, Peha D 450 FU, STM-250, BSC ?]
     <ul>
         <li>closed</li>
         <li>open</li>
         <li>state: open|closed</li>
     </ul></li>
        The device should be created by autocreate.
     <br><br>

     <li>Temperature Sensors with with different ranges (EEP A5-02-01 ... A5-02-30)<br>
         [EnOcean STM 330, Eltako FTF55, Thermokon SR65 ...]<br>
     <ul>
       <li>t/&#176C</li>
       <li>temperature: t/&#176C (Sensor Range: t = &lt;t min&gt; &#176C ... &lt;t max&gt; &#176C)</li>
       <li>state: t/&#176C</li>
     </ul><br>
        The attr subType must be tempSensor.01 ... tempSensor.30. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Temperatur and Humidity Sensor (EEP A5-04-02)<br>
         [Eltako FAFT60, FIFT63AP]<br>
     <ul>
       <li>T: t/&#176C H: rH/% B: unknown|low|ok</li>
       <li>battery: unknown|low|ok</li>
       <li>energyStorage: unknown|empty|charged|full</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>temperature: t/&#176C (Sensor Range: t = -20 &#176C ... 60 &#176C)</li>
       <li>voltage: U/V</li> (Sensor Range: U = 0 V ... 6.6 V)
       <li>state: T: t/&#176C H: rH/% B: unknown|low|ok</li>
     </ul><br>
        The attr subType must be tempHumiSensor.02 and attr
        manufID must be 00D for Eltako Devices. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Temperatur and Humidity Sensor (EEP A5-04-03)<br>
         [untsted]<br>
     <ul>
       <li>T: t/&#176C H: rH/%</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>telegramType: heartbeat|event</li>
       <li>temperature: t/&#176C (Sensor Range: t = -20 &#176C ... 60 &#176C)</li>
       <li>state: T: t/&#176C H: rH/%</li>
     </ul><br>
        The attr subType must be tempHumiSensor.03. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Barometric Sensor (EEP A5-05-01)<br>
         [untested]<br>
     <ul>
       <li>P/hPa</li>
       <li>airPressure: P/hPa (Sensor Range: P = 500 hPa ... 1150 hPa</li>
       <li>telegramType: heartbeat|event</li>
       <li>state: P/hPa</li>
     </ul><br>
        The attr subType must be baroSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Light Sensor (EEP A5-06-01)<br>
         [Eltako FAH60, FAH63, FIH63, Thermokon SR65 LI]<br>
     <ul>
       <li>E/lx</li>
       <li>brightness: E/lx (Sensor Range: 300 lx ... 30 klx, 600 lx ... 60 klx
       , Sensor Range for Eltako: E = 0 lx ... 100 lx, 300 lx ... 30 klx)</li>
       <li>voltage: U/V</li> (Sensor Range: U = 0 V ... 5.1 V)
       <li>state: E/lx</li>
     </ul><br>
        Eltako devices only support Brightness.<br>
        The attr subType must be lightSensor.01 and attr manufID must be 00D
        for Eltako Devices. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

     <li>Light Sensor (EEP A5-06-02)<br>
         [untested]<br>
     <ul>
       <li>E/lx</li>
       <li>brightness: E/lx (Sensor Range: 0 lx ... 1020 lx</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.1 V)</li>
       <li>state: E/lx</li>
     </ul><br>
        The attr subType must be lightSensor.02. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Light Sensor (EEP A5-06-03)<br>
         [untested]<br>
     <ul>
       <li>E/lx</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>errorCode: 251 ... 255</li>
       <li>state: E/lx</li>
     </ul><br>
        The attr subType must be lightSensor.03. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

      <li>Occupancy Sensor (EEP A5-07-01, A5-07-02)<br>
         [EnOcean EOSW]<br>
     <ul>
       <li>on|off</li>
       <li>current: I/&#181;A (Sensor Range: I = 0 V ... 127.0 &#181;A)</li>
       <li>errorCode: 251 ... 255</li>
       <li>motion: on|off</li>
       <li>sensorType: ceiling|wall</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be occupSensor.<01|02>. This is done if the device was
        created by autocreate. Current is the solar panel current. Some values are
        displayed only for certain types of devices.
     </li>
     <br><br>

      <li>Occupancy Sensor (EEP A5-07-03)<br>
         [untested]<br>
     <ul>
       <li>M: on|off E: E/lx U: U/V</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>errorCode: 251 ... 255</li>
       <li>motion: on|off</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: M: on|off E: E/lx U: U/V</li>
     </ul><br>
        The attr subType must be occupSensor.03. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Light, Temperatur and Occupancy Sensor (EEP A5-08-01 ... A5-08-03)<br>
         [Eltako FABH63, FBH55, FBH63, FIBH63, Thermokon SR-MDS, PEHA 482 FU-BM DE]<br>
     <ul>
       <li>M: on|off E: E/lx P: absent|present T: t/&#176C U: U/V</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 510, 1020, 1530 or 2048 lx)</li>
       <li>motion: on|off</li>
       <li>presence: absent|present</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 51 &#176C or -30 &#176C ... 50 &#176C)</li>
       <li>voltage: U/V</li> (Sensor Range: U = 0 V ... 5.1 V)
       <li>state: M: on|off E: E/lx P: absent|present T: t/&#176C U: U/V</li>
     </ul><br>
        Eltako and PEHA devices only support Brightness and Motion.<br>
        The attr subType must be lightTempOccupSensor.<01|02|03> and attr
        manufID must be 00D for Eltako Devices. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, CO Sensor (EEP A5-09-01)<br>
         [untested]<br>
     <ul>
       <li>CO: c/ppm (Sensor Range: c = 0 ppm ... 255 ppm)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 255 &#176C)</li>
       <li>state: c/ppm</li>
     </ul><br>
        The attr subType must be COSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, CO Sensor (EEP A5-09-02)<br>
         [untested]<br>
     <ul>
       <li>CO: c/ppm (Sensor Range: c = 0 ppm ... 1020 ppm)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 51.0 &#176C)</li>
       <li>voltage: U/V</li> (Sensor Range: U = 0 V ... 5.1 V)
       <li>state: c/ppm</li>
     </ul><br>
        The attr subType must be COSensor.02. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, CO2 Sensor (EEP A5-09-04)<br>
         [Thermokon SR04 CO2 *, Eltako FCOTF63, untested]<br>
     <ul>
       <li>airQuality: high|mean|moderate|low (Air Quality Classes DIN EN 13779)</li>
       <li>CO2: c/ppm (Sensor Range: c = 0 ppm ... 2550 ppm)</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 51 &#176C)</li>
       <li>state: CO2: c/ppm AQ: high|mean|moderate|low T: t/&#176C  H: rH/%</li>
     </ul><br>
        The attr subType must be tempHumiCO2Sensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, Volatile organic compounds (VOC) Sensor (EEP A5-09-05)<br>
         [untested]<br>
     <ul>
       <li>concentration: c/ppb (Sensor Range: c = 0 ppb ...  655350 ppb)</li>
       <li>vocName: Name of last measured VOC</li>
       <li>state: c/ppb</li>
     </ul><br>
        The attr subType must be vocSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, Radon Sensor (EEP A5-09-06)<br>
         [untested]<br>
     <ul>
       <li>Rn: A m3/Bq (Sensor Range: A = 0 Bq/m3 ... 1023 Bq/m3)</li>
       <li>state: A m3/Bq</li>
     </ul><br>
        The attr subType must be radonSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, Particles Sensor (EEP A5-09-07)<br>
         [untested]<br>
         Three channels with particle sizes of up to 10 &mu;m, 2.5 &mu;m and 1 &mu;m are supported<br>.
     <ul>
       <li>particles_10: p m3/&mu;g | inactive (Sensor Range: p = 0 &mu;g/m3 ... 511 &mu;g/m3)</li>
       <li>particles_2_5: p m3/&mu;g | inactive (Sensor Range: p = 0 &mu;g/m3 ... 511 &mu;g/m3)</li>
       <li>particles_1: p m3/&mu;g | inactive (Sensor Range: p = 0 &mu;g/m3 ... 511 &mu;g/m3)</li>
       <li>state: PM10: p m3/&mu;g PM2_5: p m3/&mu;g PM1: p m3/&mu;g</li>
     </ul><br>
        The attr subType must be particlesSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>CO2 Sensor (EEP A5-09-08, A5-09-09)<br>
         [untested]<br>
     <ul>
       <li>CO2: c/ppm (Sensor Range: c = 0 ppm ... 2000 ppm)</li>
       <li>powerFailureDetection: detected|not_detected</li>
       <li>state: c/ppm</li>
     </ul><br>
        The attr subType must be CO2Sensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

    <li>Room Sensor and Control Unit (EEP A5-10-01 ... A5-10-0D)<br>
         [Eltako FTR55*, Thermokon SR04 *, Thanos SR *]<br>
     <ul>
       <li>T: t/&#176C SP: 0 ... 255 F: 0|1|2|3|auto SW: 0|1</li>
       <li>fanStage: 0|1|2|3|auto</li>
       <li>switch: 0|1</li>
       <li>setpoint: 0 ... 255</li>
       <li>setpointScaled: &lt;floating-point number&gt;</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C SP: 0 ... 255 F: 0|1|2|3|auto SW: 0|1</li><br>
       Alternatively for Eltako devices
       <li>T: t/&#176C SPT: t/&#176C NR: t/&#176C</li>
       <li>block: lock|unlock</li>
       <li>nightReduction: t/K</li>
       <li>setpointTemp: t/&#176C</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C SPT: t/&#176C NR: t/K</li><br>
     </ul><br>
       The scaling of the setpoint adjustment is device- and vendor-specific. Set the
       attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
       <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled reading
       setpointScaled. Use attribut <a href="#userReadings">userReadings</a> to
       adjust the scaling alternatively.<br>
       The attr subType must be roomSensorControl.05 and attr
       manufID must be 00D for Eltako Devices. This is done if the device was
       created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-04-01, A5-10-10 ... A5-10-14)<br>
         [Thermokon SR04 * rH, Thanos SR *]<br>
     <ul>
       <li>T: t/&#176C H: rH/% SP: 0 ... 255 SW: 0|1</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>switch: 0|1</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpoint: 0 ... 255</li>
       <li>setpointScaled: &lt;floating-point number&gt;</li>
       <li>state: T: t/&#176C H: rH/% SP: 0 ... 255 SW: 0|1</li>
     </ul><br>
       The scaling of the setpoint adjustment is device- and vendor-specific. Set the
       attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
       <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled reading
       setpointScaled. Use attribut <a href="#userReadings">userReadings</a> to
       adjust the scaling alternatively.<br>
       The attr subType must be roomSensorControl.01. This is
       done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-15 ... A5-10-17)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C SP: 0 ... 63 P: absent|present</li>
       <li>presence: absent|present</li>
       <li>temperature: t/&#176C (Sensor Range: t = -10 &#176C ... 41.2 &#176C)</li>
       <li>setpoint: 0 ... 63</li>
       <li>setpointScaled: &lt;floating-point number&gt;</li>
       <li>state: T: t/&#176C SP: 0 ... 63 P: absent|present</li>
     </ul><br>
       The scaling of the setpoint adjustment is device- and vendor-specific. Set the
       attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
       <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled reading
       setpointScaled. Use attribut <a href="#userReadings">userReadings</a> to
       adjust the scaling alternatively.<br>
       The attr subType must be roomSensorControl.02. This is done if the device was
       created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-18)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpoint: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.18. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-19)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C H: rH/% F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C H: rH/% F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.19. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-1A)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled U: U/V</li>
       <li>errorCode: 251 ... 255</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: T: t/&#176C F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled U: U/V</li>
     </ul><br>
        The attr subType must be roomSensorControl.1A. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-1B, A5-10-1D)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off P: absent|present|disabled U: U/V</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>errorCode: 251 ... 255</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off P: absent|present|disabled U: U/V</li>
     </ul><br>
        The attr subType must be roomSensorControl.1B. This is done if the device was
        created by autocreate.
     </li>
     <br><br>
     <li>Room Sensor and Control Unit (EEP A5-10-1C)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off SP: E/lx P: absent|present|disabled</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off SP: E/lx P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.1C. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-1D)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C H: rH/% F: 0|1|2|3|4|5|auto|off SP: rH/% P: absent|present|disabled</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C H: rH/% F: 0|1|2|3|4|5|auto|off SP: rH/% P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.1D. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-1F)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C F: 0|1|2|3|auto SP: 0 ... 255 P: absent|present|disabled</li>
       <li>fan: 0|1|2|3|auto</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: 0 ... 255</li>
       <li>setpointScaled: &lt;floating-point number&gt;</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C F: 0|1|2|3|auto SP: 0 ... 255 P: absent|present|disabled</li>
     </ul><br>
       The scaling of the setpoint adjustment is device- and vendor-specific. Set the
       attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
       <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled reading
       setpointScaled. Use attribut <a href="#userReadings">userReadings</a> to
       adjust the scaling alternatively.<br>
       The attr subType must be roomSensorControl.1F. This is done if the device was
       created by autocreate.
     </li>
     <br><br>

     <li>Room Operation Panel (EEP A5-10-20, A5-10-21)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C H: rH/% SP: 0 ... 255 B: ok|low</li>
       <li>activity: yes|no</li>
       <li>battery: ok|low</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>setpoint: 0 ... 255</li>
       <li>setpointMode: auto|frostProtect|setpoint</li>
       <li>setpointScaled: &lt;floating-point number&gt;</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: t/&#176C H: rH/% SP: 0 ... 255 B: ok|low</li>
     </ul><br>
       The scaling of the setpoint adjustment is device- and vendor-specific. Set the
       attributes <a href="#scaleMax">scaleMax</a>, <a href="#scaleMin">scaleMin</a> and
       <a href="#scaleDecimals">scaleDecimals</a> for the additional scaled reading
       setpointScaled. Use attribut <a href="#userReadings">userReadings</a> to
       adjust the scaling alternatively.<br>
       The attr subType must be roomSensorControl.20 or roomSensorControl.21.
       This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Room Control Panels (D2-10-00 - D2-10-02)<br>
         [Kieback & Peter RBW322-FTL]<br>
     <ul>
       <li>T: t/&#176C H: -|rH/% F: 0 ... 100/% SPT: t/&#176C O: -|absent|present M: -|on|off</li>
       <li>battery: ok|low|empty|-</li>
       <li>cooling: auto|on|off|-</li>
       <li>customWarning[1|2]: on|off</li>
       <li>fanSpeed: 0 ... 100/%</li>
       <li>fanSpeedMode: central|local</li>
       <li>heating: auto|on|off|-</li>
       <li>humidity: -|rH/%</li>
       <li>moldWarning: on|off</li>
       <li>motion: on|off|-</li>
       <li>occupancy: -|absent|present</li>
       <li>roomCtrlMode: buildingProtection|comfort|economy|preComfort</li>
       <li>setpointBuildingProtectionTemp: -|t/&#176C (Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpointComfortTemp: -|t/&#176C (Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpointEconomyTemp: -|t/&#176C (Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpointPreComfortTemp: -|t/&#176C (Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpointTemp: t/&#176C (Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>solarPowered: yes|no</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>window: closed|open</li>
       <li>state: T: t/&#176C H: -|rH/% F: 0 ... 100/% SPT: t/&#176C O: -|absent|present M: -|on|off</li>
     </ul><br>
       The attr subType must be roomCtrlPanel.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>

     <li>Lighting Controller State (EEP A5-11-01)<br>
         [untested]<br>
     <ul>
       <li>on|off</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 510 lx)</li>
       <li>contact: open|closed</li>
       <li>daylightHarvesting: enabled|disabled</li>
       <li>dim: 0 ... 255</li>
       <li>presence: absent|present</li>
       <li>illum: 0 ... 255</li>
       <li>mode: switching|dimming</li>
       <li>powerRelayTimer: enabled|disabled</li>
       <li>powerSwitch: on|off</li>
       <li>repeater: enabled|disabled</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be lightCtrlState.01 This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Temperature Controller Output (EEP A5-11-02)<br>
         [untested]<br>
     <ul>
       <li>t/&#176C</li>
       <li>alarm: on|off</li>
       <li>controlVar: cvar (Sensor Range: cvar = 0 % ... 100 %)</li>
       <li>controllerMode: auto|heating|cooling|off</li>
       <li>controllerState: auto|override</li>
       <li>energyHoldOff: normal|holdoff</li>
       <li>fan: 0 ... 3|auto</li>
       <li>presence: present|absent|standby|frost</li>
       <li>setpointTemp: t/&#176C (Sensor Range: t = 0 &#176C ... 51.2 &#176C)</li>
       <li>state: t/&#176C</li>
     </ul><br>
        The attr subType must be tempCtrlState.01 This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li><a name="Blind Status">Blind Status</a> (EEP A5-11-03)<br>
         [untested, experimental status]<br>
     <ul>
       <li>open|closed|not_reached|not_available</li>
       <li>alarm: on|off|no endpoints defined|not used</li>
       <li>anglePos: &alpha;/&#176 (Sensor Range: &alpha; = -360 &#176 ... 360 &#176)</li>
       <li>endPosition: open|closed|not_reached|not_available</li>
       <li>position: pos/% (Sensor Range: pos = 0 % ... 100 %)</li>
       <li>positionMode: normal|inverse</li>
       <li>serviceOn: yes|no</li>
       <li>shutterState: opens|closes|stopped|not_available</li>
       <li>state: open|closed|not_reached|not_available</li>
     </ul><br>
        The attr subType must be shutterCtrlState.01 This is done if the device was
        created by autocreate.<br>
        The profile is linked with <a href="#Blind Command Central">Blind Command Central</a>.
        The profile <a href="#Blind Command Central">Blind Command Central</a>
        controls the devices centrally. For that the attributes subDef, subTypeSet
        and gwCmd have to be set manually.
     </li>
     <br><br>

     <li>Extended Lighting Status (EEP A5-11-04)<br>
         [untested]<br>
     <ul>
       <li>on|off</li>
       <li>alarm: off|lamp_failure|internal_failure|external_periphery_failure</li>
       <li>current: &lt;formula symbol&gt;/&lt;unit&gt; (Sensor range: &lt;formula symbol&gt; = 0 ... 65535 &lt;unit&gt;</li>
       <li>currentUnit: mA|A</li>
       <li>dim: 0 ... 255</li>
       <li>energy: &lt;formula symbol&gt;/&lt;unit&gt; (Sensor range: &lt;formula symbol&gt; = 0 ... 65535 &lt;unit&gt;</li>
       <li>energyUnit: Wh|kWh|MWh|GWh</li>
       <li>measuredValue: &lt;formula symbol&gt;/&lt;unit&gt; (Sensor range: &lt;formula symbol&gt; = 0 ... 65535 &lt;unit&gt;</li>
       <li>measureUnit: unknown</li>
       <li>lampOpHours: t/h |unknown (Sensor range: t = 0 h ... 65535 h)</li>
       <li>power: &lt;formula symbol&gt;/&lt;unit&gt; (Sensor range: &lt;formula symbol&gt; = 0 ... 65535 &lt;unit&gt;</li>
       <li>powerSwitch: on|off</li>
       <li>powerUnit: mW|W|kW|MW</li>
       <li>rgb: RRGGBB (red (R), green (G) or blue (B) color component values: 00 ... FF)</li>
       <li>serviceOn: yes|no</li>
       <li>voltage: &lt;formula symbol&gt;/&lt;unit&gt; (Sensor range: &lt;formula symbol&gt; = 0 ... 65535 &lt;unit&gt;</li>
       <li>voltageUnit: mV|V</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be lightCtrlState.02 This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Counter (EEP A5-12-00)<br>
         [Thermokon SR-MI-HS, untested]<br>
     <ul>
       <li>1/s</li>
       <li>currentValue: 1/s</li>
       <li>counter<0 ... 15>: 0 ... 16777215</li>
       <li>channel: 0 ... 15</li>
      <li>state: 1/s</li>
     </ul><br>
        The attr subType must be autoMeterReading.00. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Electricity (EEP A5-12-01)<br>
         [Eltako FSS12, DSZ14DRS, DSZ14WDRS, Thermokon SR-MI-HS, untested]<br>
         [Eltako FWZ12-16A tested]<br>
     <ul>
       <li>P/W</li>
       <li>power: P/W</li>
       <li>energy<0 ... 15>: E/kWh</li>
       <li>currentTariff: 0 ... 15</li>
       <li>serialNumber: S-&lt;nnnnnn&gt;</li>
      <li>state: P/W</li>
     </ul><br>
        The attr subType must be autoMeterReading.01 and attr
        manufID must be 00D for Eltako Devices. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Gas, Water (EEP A5-12-02, A5-12-03)<br>
         [untested]<br>
     <ul>
       <li>Vs/l</li>
       <li>flowrate: Vs/l</li>
       <li>consumption<0 ... 15>: V/m3</li>
       <li>currentTariff: 0 ... 15</li>
      <li>state: Vs/l</li>
     </ul><br>
        The attr subType must be autoMeterReading.02|autoMeterReading.03.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Temperatur, Load (EEP A5-12-04)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C W: m/g B: full|ok|low|empty</li>
       <li>battery: full|ok|low|empty</li>
       <li>temperature: t/&#176C (Sensor Range: t = -40 &#176C ... 40 &#176C)</li>
       <li>weight: m/g</li>
       <li>state: T: t/&#176C W: m/g B: full|ok|low|empty</li>
     </ul><br>
        The attr subType must be autoMeterReading.04.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Temperatur, Container Sensor (EEP A5-12-05)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C L: <location0 ... location9> B: full|ok|low|empty</li>
       <li>amount: 0 ... 10</li>
       <li>battery: full|ok|low|empty</li>
       <li>location<0 ... 9>: possessed|not_possessed</li>       
       <li>temperature: t/&#176C (Sensor Range: t = -40 &#176C ... 40 &#176C)</li>
       <li>weight: m/g</li>
       <li>state: T: t/&#176C L: <location0 ... location9> B: full|ok|low|empty</li>
     </ul><br>
        The attr subType must be autoMeterReading.05.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Environmental Applications<br>
         Weather Station (EEP A5-13-01)<br>
         Sun Intensity (EEP A5-13-02)<br>
         [Eltako FWS61]<br>
     <ul>
       <li>T: t/&#176C B: E/lx W: Vs/m IR: yes|no</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 999 lx)</li>
       <li>dayNight: day|night</li>
       <li>hemisphere: north|south</li>
       <li>isRaining: yes|no</li>
       <li>sunEast: E/lx (Sensor Range: E = 1 lx ... 150 klx)</li>
       <li>sunSouth: E/lx (Sensor Range: E = 1 lx ... 150 klx)</li>
       <li>sunWest: E/lx (Sensor Range: E = 1 lx ... 150 klx)</li>
       <li>temperature: t/&#176C (Sensor Range: t = -40 &#176C ... 80 &#176C)</li>
       <li>windSpeed: Vs/m (Sensor Range: V = 0 m/s ... 70 m/s)</li>
       <li>state:T: t/&#176C B: E/lx W: Vs/m IR: yes|no</li>
     </ul><br>
        Brightness is the strength of the dawn light. SunEast,
        sunSouth and sunWest are the solar radiation from the respective
        compass direction. IsRaining is the rain indicator.<br>
        The attr subType must be environmentApp and attr manufID must be 00D
        for Eltako Devices. This is done if the device was created by
        autocreate.<br>
        The Eltako Weather Station FWS61 supports not the day/night indicator
        (dayNight).<br>
     </li>
     <br><br>

     <li>Environmental Applications<br>
         EEP A5-13-03 ... EEP A5-13-06 are not implemented.
     </li>
     <br><br>

     <li>Environmental Applications<br>
         Sun Position and Radiation (EEP A5-13-10)<br>
         [untested]<br>
     <ul>
       <li>SRA: E m2/W SNA: &alpha;/&deg; SNE: &beta;/&deg;</li>
       <li>dayNight: day|night</li>
       <li>solarRadiation: E m2/W (Sensor Range: E = 0 W/m2 ... 2000 W/m2)</li>
       <li>sunAzimuth: &alpha;/&deg; (Sensor Range: &alpha; = -90 &deg; ... 90 &deg;)</li>
       <li>sunElevation: &beta;/&deg; (Sensor Range: &beta; = 0 &deg; ... 90 &deg;)</li>
       <li>state:SRA: E m2/W SNA: &alpha;/&deg; SNE: &beta;/&deg;</li>
     </ul><br>
        The attr subType must be environmentApp. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

      <li>Multi-Func Sensor (EEP A5-14-01 ... A5-14-06)<br>
         [untested]<br>
     <ul>
       <li>C: open|closed V: on|off E: E/lx U: U/V</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>contact: open|closed</li>
       <li>errorCode: 251 ... 255</li>
       <li>vibration: on|off</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: C: open|closed V: on|off E: E/lx U: U/V</li>
     </ul><br>
        The attr subType must be multiFuncSensor. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Battery Powered Actuator (EEP A5-20-01)<br>
         [Kieback&Peter MD15-FTL-xx]<br>
     <ul>
       <li>setpoint/%</li>
       <li>actuator: ok|obstructed</li>
       <li>battery: ok|low</li>
       <li>currentValue: setpoint/%</li>
       <li>cover: open|closed</li>
       <li>energyInput: enabled|disabled</li>
       <li>energyStorage: charged|empty</li>
       <li>selfCtl: on|off</li>
       <li>serviceOn: yes|no</li>
       <li>setpoint: setpoint/%</li>
       <li>setpointTemp: t/&#176C</li>
       <li>temperature: t/&#176C</li>
       <li>tempSensor: failed|ok</li>
       <li>window: open|closed</li>
       <li>state: setpoint/%</li>
     </ul><br>
        The attr subType must be hvac.01. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

     <li>Digital Input (EEP A5-30-01, A5-30-02)<br>
         [Thermokon SR65 DI, untested]<br>
     <ul>
       <li>open|closed</li>
       <li>battery: ok|low (only EEP A5-30-01)</li>
       <li>contact: open|closed</li>
       <li>state: open|closed</li>
     </ul><br>
        The attr subType must be digitalInput.01 or digitalInput.02. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Digital Input (EEP A5-30-03)<br>
         4 digital Inputs, Wake, Temperature [untested]<br>
     <ul>
       <li>T: t/&#176C I: 0|1 0|1 0|1 0|1 W: 0|1</li>
       <li>in0: 0|1</li>
       <li>in1: 0|1</li>
       <li>in2: 0|1</li>
       <li>in3: 0|1</li>
       <li>wake: 0|1</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C I: 0|1 0|1 0|1 0|1 W: 0|1</li>
     </ul><br>
        The attr subType must be digitalInput.03. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Digital Input (EEP A5-30-04)<br>
         3 digital Inputs, 1 digital Input 8 bits [untested]<br>
     <ul>
       <li>0|1 0|1 0|1 0...255</li>
       <li>in0: 0|1</li>
       <li>in1: 0|1</li>
       <li>in2: 0|1</li>
       <li>in3: 0...255</li>
       <li>state: 0|1 0|1 0|1 0...255</li>
     </ul><br>
        The attr subType must be digitalInput.04. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Energy management, demand response (EEP A5-37-01)<br>
       <br> 
     <ul>
       <li>on|off|waiting_for_start|waiting_for_stop</li>
       <li>level: 0...15</li>
       <li>powerUsage: powerUsage/%</li>
       <li>powerUsageLevel: max|min</li>
       <li>powerUsageScale: rel|max</li>
       <li>randomEnd: yes|no</li>
       <li>randomStart: yes|no</li>
       <li>setpoint: 0...255</li>
       <li>timeout: yyyy-mm-dd hh:mm:ss</li>
       <li>state: on|off|waiting_for_start|waiting_for_stop</li>
     </ul><br>
        The attr subType must be energyManagement.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Switching<br>
         [Eltako FLC61, FSA12, FSR14]<br>
     <ul>
       <li>on</li>
       <li>off</li>
       <li>executeTime: t/s (Sensor Range: t = 0.1 s ... 6553.5 s or 0 if no time specified)</li>
       <li>executeType: duration|delay</li>
       <li>block: lock|unlock</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be gateway and gwCmd must be switching. This is done if the device was
        created by autocreate.<br>
        For Eltako devices attributes must be set manually. Eltako devices only send on/off.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Dimming<br>
         [Eltako FUD14, FUD61, FUD70, FSG14, ...]<br>
     <ul>
       <li>on</li>
       <li>off</li>
       <li>block: lock|unlock</li>
       <li>dim: dim/% (Sensor Range: dim = 0 % ... 100 %)</li>
       <li>dimValueLast: dim/%<br>
           Last value received from the bidirectional dimmer.</li>
       <li>dimValueStored: dim/%<br>
           Last value saved by <code>set &lt;name&gt; dim &lt;value&gt;</code>.</li>
       <li>rampTime: t/s (Sensor Range: t = 1 s ... 255 s or 0 if no time specified,
           for Eltako: t = 1 = fast dimming ... 255 = slow dimming or 0 = dimming speed on the dimmer used)</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be dimming and attr manufID must be 00D
        for Eltako Devices. This is done if the device was created by autocreate.<br>
        For Eltako devices attributes must be set manually. Eltako devices only send on/off and dim.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Setpoint shift<br>
         [untested]<br>
     <ul>
       <li>1/K</li>
       <li>setpointShift: 1/K (Sensor Range: T = -12.7 K ... 12.8 K)</li>
       <li>state: 1/K</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be setpointShift.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Basic Setpoint<br>
         [untested]<br>
     <ul>
       <li>t/&#176C</li>
       <li>setpoint: t/&#176C (Sensor Range: t = 0 &#176C ... 51.2 &#176C)</li>
       <li>state: t/&#176C</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be setpointBasic.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Control variable<br>
         [untested]<br>
     <ul>
       <li>auto|heating|cooling|off</li>
       <li>controlVar: cvov (Sensor Range: cvov = 0 % ... 100 %)</li>
       <li>controllerMode: auto|heating|cooling|off</li>
       <li>controllerState: auto|override</li>
       <li>energyHoldOff: normal|holdoff</li>
       <li>presence: present|absent|standby</li>
       <li>state: auto|heating|cooling|off</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be controlVar.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Fan stage<br>
         [untested]<br>
     <ul>
       <li>0 ... 3|auto</li>
       <li>state: 0 ... 3|auto</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be fanStage.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Extended Lighting Control (EEP A5-38-09)<br>
         [untested]<br>
     <ul>
       <li>on</li>
       <li>off</li>
       <li>teach</li>
       <li>block: unlock|on|off|local</li>
       <li>dimMax: &lt;maximum dimming value&gt; (Range: dim = 0  ... 255)</li>
       <li>dimMin: &lt;minimum dimming value&gt; (Range: dim = 0  ... 255)</li>
       <li>rampTime: t/s (Range: t = 0 s ... 65535 s)</li>
       <li>rgb RRGGBB (red (R), green (G) or blue (B) color component values: 00 ... FF)</li>
       <li>state: on|off|teach</li>
     </ul><br>
        Another readings, see subtype lightCtrlState.02.<br>
        The attr subType or subTypSet must be lightCtrl.01. This is done if the device was created by autocreate.<br>
        The subType is associated with the subtype lightCtrlState.02.
     </li>
     <br><br>

     <li>Manufacturer Specific Applications (EEP A5-3F-7F)<br><br>
         Wireless Analog Input Module<br>
         [Thermokon SR65 3AI, untested]<br>
     <ul>
       <li>I1: U/V I2: U/V I3: U/V</li>
       <li>input1: U/V (Sensor Range: U = 0 V ... 10 V)</li>
       <li>input2: U/V (Sensor Range: U = 0 V ... 10 V)</li>
       <li>input3: U/V (Sensor Range: U = 0 V ... 10 V)</li>
       <li>state: I1: U/V I2: U/V I3: U/V</li>
     </ul><br>
        The attr subType must be manufProfile and attr manufID must be 002
        for Thermokon Devices. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Manufacturer Specific Applications (EEP A5-3F-7F)<br><br>
         Thermostat Actuator<br>
         [AWAG omnio UPH230/1x]<br>
     <ul>
       <li>on</li>
       <li>off</li>
       <li>emergencyMode&lt;channel&gt;: on|off</li>
       <li>nightReduction&lt;channel&gt;: on|off</li>
       <li>setpointTemp&lt;channel&gt;: t/&#176C</li>
       <li>temperature&lt;channel&gt;: t/&#176C</li>
       <li>window&lt;channel&gt;: on|off</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be manufProfile and attr manufID must be 005
        for AWAG omnio Devices. This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Manufacturer Specific Applications (EEP A5-3F-7F)<br><br>
         Shutter (EEP F6-02-01 ... F6-02-02)<br>
         [Eltako FSB12, FSB14, FSB61, FSB70]<br>
     <ul>
        <li>teach<br>
            Teach-In is sent</li>
        <li>open|open_ack<br>
            The status of the device will become "open" after the TOP endpoint is
            reached, or it has finished an "opens" or "position 0" command.</li>
        <li>closed<br>
            The status of the device will become "closed" if the BOTTOM endpoint is
            reached</li>
        <li>stop<br>
            The status of the device become "stop" if stop command is sent.</li>
        <li>not_reached<br>
            The status of the device become "not_reached" between one of the endpoints.</li>
        <li>anglePos: &alpha;/&#176 (Sensor Range: &alpha; = -180 &#176 ... 180 &#176)</li>
        <li>endPosition: open|open_ack|closed|not_reached|not_available</li>
        <li>position: pos/% (Sensor Range: pos = 0 % ... 100 %)</li>
        <li>state: open|open_ack|closed|not_reached|stop|teach</li>
     </ul><br>
        The values of the reading position and anglePos are updated automatically,
        if the command position is sent or the reading state was changed
        manually to open or closed.<br>
        Set attr subType file, attr manufID to 00D and attr model to
        FSB14|FSB61|FSB70 manually.
     </li>
     <br><br>

     <li>Electronic switches and dimmers with Energy Measurement and Local Control (D2-01-00 - D2-01-11)<br>
        [Telefunken Funktionsstecker, PEHA Easyclick, AWAG Elektrotechnik AG Omnio UPS 230/xx,UPD 230/xx]<br>
     <ul>
        <li>on</li>
        <li>off</li>
        <li>channel&lt;0...29|All|Input&gt;: on|off</li>
        <li>dayNight: day|night</li>        
        <li>defaultState: on|off|last</li>        
        <li>devTemp: t/&#176C|invalid</li>
        <li>devTempState: ok|max|warning</li>
        <li>dim&lt;0...29|Input&gt;: dim/% (Sensor Range: dim = 0 % ... 100 %)</li>
        <li>energy&lt;channel&gt;: 1/[Ws|Wh|KWh]</li>
        <li>energyUnit&lt;channel&gt;: Ws|Wh|KWh</li>
        <li>error&lt;channel&gt;: ok|warning|failure|not_supported</li>
        <li>loadClassification: no</li>        
        <li>localControl&lt;channel&gt;: enabled|disabled</li>
        <li>loadLink: connected|disconnected</li>
        <li>loadOperation: 3-wire</li>
        <li>loadState: on|off</li>
        <li>measurementMode: energy|power</li>        
        <li>measurementReport: auto|query</li>        
        <li>measurementReset: not_active|trigger</li>        
        <li>measurementDelta: 1/[Ws|Wh|KWh|W|KW]</li>        
        <li>measurementUnit: Ws|Wh|KWh|W|KW</li>        
        <li>overCurrentOff&lt;channel&gt;: executed|ready</li>
        <li>overCurrentShutdown&lt;channel&gt;: off|restart</li>
        <li>overCurrentShutdownReset&lt;channel&gt;: not_active|trigger</li>
        <li>power&lt;channel&gt;: 1/[W|KW]</li>
        <li>powerFailure&lt;channel&gt;: enabled|disabled</li>
        <li>powerFailureDetection&lt;channel&gt;: detected|not_detected</li>
        <li>powerUnit&lt;channel&gt;: W|KW</li>        
        <li>rampTime&lt;1...3l&gt;: 1/s</li>
        <li>responseTimeMax: 1/s</li>
        <li>responseTimeMin: 1/s</li>
        <li>serialNumber: [00000000 ... FFFFFFFF]</li>
        <li>teachInDev: enabled|disabled</li>
        <li>state: on|off</li>
     </ul>
        <br>
        The attr subType must be actuator.01. This is done if the device was
        created by autocreate. To control the device, it must be bidirectional paired,
        see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>

     <li>Blind Control for Position and Angle (D2-05-00)<br>
         [AWAG Elektrotechnik AG OMNIO UPJ 230/12]<br>
     <ul>
        <li>open<br>
            The status of the device will become "open" after the TOP endpoint is
            reached, or it has finished an "opens" or "position 0" command.</li>
        <li>closed<br>
            The status of the device will become "closed" if the BOTTOM endpoint is
            reached</li>
        <li>stop<br>
            The status of the device become "stop" if stop command is sent.</li>
        <li>not_reached<br>
            The status of the device become "not_reached" between one of the endpoints.</li>
        <li>pos/% (Sensor Range: pos = 0 % ... 100 %)</li>
        <li>anglePos: &alpha;/% (Sensor Range: &alpha; = 0 % ... 100 %)</li>
        <li>block: unlock|lock|alarm</li>
        <li>endPosition: open|closed|not_reached|unknown</li>
        <li>position: unknown|pos/% (Sensor Range: pos = 0 % ... 100 %)</li>
        <li>state: open|closed|in_motion|stoped|pos/% (Sensor Range: pos = 0 % ... 100 %)</li>
     </ul>
        <br>
        The attr subType must be blindsCtrl.00. This is done if the device was
        created by autocreate. To control the device, it must be bidirectional paired,
        see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>

     <li>Fan Control (D2-20-00 - D2-20-02)<br>
        [Maico ECA x RC/RCH, ER 100 RC, untested]<br>
     <ul>
       <li>on|off|not_supported</li>
       <li>fanSpeed: 0 ... 100/%</li>
       <li>error: ok|air_filter|hardware|not_supported</li>
       <li>humidity: rH/%|not_supported</li>
       <li>humidityCtrl: disabled|enabled|not_supported</li>
       <li>roomSize: 0...350/m<sup>2</sup>|max</li>
       <li>roomSizeRef: unsed|not_used|not_supported</li>
       <li>setpointTemp: t/&#176C (Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: on|off|not_supported</li>
     </ul><br>
       The attr subType must be fanCtrl.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>

     <li>Valve Control (EEP D2-A0-01)<br> 
     <ul>
       <li>opens</li>
       <li>open</li>
       <li>closes</li>
       <li>closed</li>
       <li>teachIn</li>
       <li>teachOut</li>
       <li>state: opens|open|closes|closed|teachIn|teachOut</li>
     </ul><br>
       The attr subType must be valveCtrl.00. This is done if the device was
       created by autocreate. To control the device, it must be bidirectional paired,
       see <a href="#EnOcean_teach-in">Bidirectional Teach-In / Teach-Out</a>.
     </li>
     <br><br>

    <li>RAW Command<br>
    <ul>
       <li>RORG: 1BS|4BS|MCS|RPS|UTE|VLD</li>
       <li>dataSent: data (Range: 1-byte hex ... 28-byte hex)</li>
       <li>statusSent: status (Range: 0x00 ... 0xFF)</li>
       <li>state: RORG: rorg DATA: data STATUS: status ODATA: odata</li>
    </ul><br>
    With the help of this command data messages in hexadecimal format can be sent and received.
    The telegram types (RORG) 1BS and RPS are always received protocol-specific.
    For further information, see
    <a href="http://www.enocean-alliance.org/eep/">EnOcean Equipment Profiles (EEP)</a>. 
    <br>
    Set attr subType to raw manually.
    </li>
    <br><br>

    <li>Light and Presence Sensor<br>
        [Omnio Ratio eagle-PM101]<br>
    <ul>
      <li>yes</li>
      <li>no</li>
      <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx)</li>
      <li>channel1: yes|no<br>
      Motion message in depending on the brightness threshold</li>
      <li>channel2: yes|no<br>
      Motion message</li>
      <li>motion: yes|no<br>
      Channel 2</li>
      <li>state: yes|no<br>
      Channel 2</li>
    </ul><br>
    The sensor also sends switching commands (RORG F6) with the SenderID-1.<br>
    Set attr subType to PM101 manually. Automatic teach-in is not possible,
    since no EEP and manufacturer ID are sent.
    </li>
  </ul>
</ul>

=end html
=cut
           