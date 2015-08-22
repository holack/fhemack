##############################################
# $Id: 10_EIB.pm 8584 2015-05-15 18:46:52Z andi291 $
package main;

use strict;
use warnings;

# Open Tasks
#  - precision for model percent to 0,1
#  - allow defined groups that are only used for sending of data (no status shown)

my %eib_c2b = (
	"off" => "00",
	"on" => "01",
	"on-for-timer" => "01",
	"on-till" => "01",
	"raw" => "",
	"value" => "" #value must be last.. because of slider functionality in Set
);

my %codes = (
  "00" => "off",
  "01" => "on",
  "" => "value",
);

my %readonly = (
  "dummy" => 1,
);

my $eib_simple ="off on value on-for-timer on-till";
my %models = (
);

my %eib_dpttypes = (

  # 1-Octet unsigned value
  "dpt5" 		=> {"CODE"=>"dpt5", "UNIT"=>"",  "factor"=>1},
  "percent" 	=> {"CODE"=>"dpt5", "UNIT"=>"%", "factor"=>100/255, "slider"=>"0,1,100"},
  "dpt5.003" 	=> {"CODE"=>"dpt5", "UNIT"=>"&deg;", "factor"=>360/255},
  "angle" 		=> {"CODE"=>"dpt5", "UNIT"=>"&deg;", "factor"=>360/255}, # alias for dpt5.003
  "dpt5.004" 	=> {"CODE"=>"dpt5", "UNIT"=>"%", "factor"=>1},
  "percent255" 	=> {"CODE"=>"dpt5", "UNIT"=>"%", "factor"=>1 , "slider"=>"0,1,255"}, #alias for dpt5.004

  # 2-Octet unsigned Value (current, length, brightness)
  "dpt7" 		=> {"CODE"=>"dpt7", "UNIT"=>""},
  "length-mm" 		=> {"CODE"=>"dpt7", "UNIT"=>"mm"},
  "current-mA" 		=> {"CODE"=>"dpt7", "UNIT"=>"mA"},
  "brightness"		=> {"CODE"=>"dpt7", "UNIT"=>"lux"},
  "timeperiod-ms"		=> {"CODE"=>"dpt7", "UNIT"=>"ms"},
  "timeperiod-min"		=> {"CODE"=>"dpt7", "UNIT"=>"min"},
  "timeperiod-h"		=> {"CODE"=>"dpt7", "UNIT"=>"h"},

  # 2-Octet Float  Value (Temp / Light)
  "dpt9" 		=> {"CODE"=>"dpt9", "UNIT"=>""},
  "tempsensor"  => {"CODE"=>"dpt9", "UNIT"=>"&deg;C"},
  "lightsensor" => {"CODE"=>"dpt9", "UNIT"=>"Lux"},
  "speedsensor" => {"CODE"=>"dpt9", "UNIT"=>"m/s"},
  "speedsensor-km/h" => {"CODE"=>"dpt9", "UNIT"=>"km/h"},
  "pressuresensor" => {"CODE"=>"dpt9", "UNIT"=>"Pa"},
  "rainsensor" => {"CODE"=>"dpt9", "UNIT"=>"l/m�"},
  "time1sensor" => {"CODE"=>"dpt9", "UNIT"=>"s"},
  "time2sensor" => {"CODE"=>"dpt9", "UNIT"=>"ms"},
  "humiditysensor" => {"CODE"=>"dpt9", "UNIT"=>"%"},
  "airqualitysensor" => {"CODE"=>"dpt9", "UNIT"=>"ppm"},
  "voltage-mV" => {"CODE"=>"dpt9", "UNIT"=>"mV"},
  "current-mA2" => {"CODE"=>"dpt9", "UNIT"=>"mA"},
  "power" => {"CODE"=>"dpt9", "UNIT"=>"kW"},
  "powerdensity" => {"CODE"=>"dpt9", "UNIT"=>"W/m�"},
  
  # Time of Day
  "dpt10"		=> {"CODE"=>"dpt10", "UNIT"=>""},
  "dpt10_no_seconds" => {"CODE"=>"dpt10_ns", "UNIT"=>""},
  "time"		=> {"CODE"=>"dpt10", "UNIT"=>""},
  
  # Date
  "dpt11"		=> {"CODE"=>"dpt11", "UNIT"=>""},
  "date"		=> {"CODE"=>"dpt11", "UNIT"=>""},
  
  # 4-Octet unsigned value (handled as dpt7)
  "dpt12" 		=> {"CODE"=>"dpt12", "UNIT"=>""},
  
  # 4-Octet single precision float
  "dpt14"         => {"CODE"=>"dpt14", "UNIT"=>""},

  # 14-Octet String
  "dpt16"         => {"CODE"=>"dpt16", "UNIT"=>""},



  
);


sub
EIB_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^B.*";
  $hash->{GetFn}     = "EIB_Get";
  $hash->{SetFn}     = "EIB_Set";
  $hash->{StateFn}   = "EIB_SetState";
  $hash->{DefFn}     = "EIB_Define";
  $hash->{UndefFn}   = "EIB_Undef";
  $hash->{ParseFn}   = "EIB_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 dummy:1,0 showtime:1,0 loglevel:0,1,2,3,4,5,6 ".
						"$readingFnAttributes " .
  						"model:".join(",", keys %eib_dpttypes);					
}


#############################
sub
EIB_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> EIB <group name> [<read group names>*]";

  return $u if(int(@a) < 3);
  return "Define $a[0]: wrong group name format: specify as 0-15/0-15/0-255 or as hex"
  		if( ($a[2] !~ m/^[0-9]{1,2}\/[0-9]{1,2}\/[0-9]{1,3}$/i)  && (lc($a[2]) !~ m/^[0-9a-f]{4}$/i));

  my $groupname = eib_name2hex(lc($a[2]));

  $hash->{GROUP} = lc($groupname);

  my $code = "$groupname";
  my $ncode = 1;
  my $name = $a[0];

  $hash->{CODE}{$ncode++} = $code;
  # add read group names
  if(int(@a)>3) 
  {
  	for (my $count = 3; $count < int(@a); $count++) 
  	{
 	   $hash->{CODE}{$ncode++} = eib_name2hex(lc($a[$count]));;
 	}
  }
  $modules{EIB}{defptr}{$code}{$name}   = $hash;
  AssignIoPort($hash);
}

#############################
sub
EIB_Undef($$)
{
  my ($hash, $name) = @_;

  foreach my $c (keys %{ $hash->{CODE} } ) {
    $c = $hash->{CODE}{$c};

    # As after a rename the $name may be different from the $defptr{$c}{$n}
    # we look for the hash.
    foreach my $dname (keys %{ $modules{EIB}{defptr}{$c} }) {
      delete($modules{EIB}{defptr}{$c}{$dname})
        if($modules{EIB}{defptr}{$c}{$dname} == $hash);
    }
  }
  return undef;
}

#####################################
sub
EIB_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  Log(5,"EIB setState tim: $tim vt: $vt val: $val");

  $val = $1 if($val =~ m/^(.*) \d+$/);
  #return "Undefined value $val" if(!defined($eib_c2b{$val}));
  return undef;
}

###################################
sub
EIB_Get($@)
{
  my ($hash, @a) = @_;

  return "" if($a[1] && $a[1] eq "?");  # Temporary hack for FHEMWEB

  IOWrite($hash, "B", "r" . $hash->{GROUP});
  return "Current value for $hash->{NAME} ($hash->{GROUP}) requested.";	  
}

###################################
sub
EIB_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $na = int(@a);

  return "no set value specified" if($na < 2 || $na > 4);
  return "Readonly value $a[1]" if(defined($readonly{$a[1]}));
  return "No $a[1] for dummies" if(IsDummy($hash->{NAME}));

  my $name  = $a[0];
  my $value = $a[1];
  my $arg1  = undef;
  my $arg2  = undef;
  
  $arg1 = $a[2] if($na>2);
  $arg2 = $a[3] if($na>3);
  my $model = $attr{$name}{"model"};
  my $sliderdef = !defined($model)?undef:$eib_dpttypes{"$model"}{"slider"};

  my $c = $eib_c2b{$value};
  if(!defined($c)) {
  	my $resp = "Unknown argument $value, choose one of " . join(" ", sort keys %eib_c2b);
  	$resp = $resp . ":slider,$sliderdef" if(defined $sliderdef);
  	return $resp;
  }
  
  # the command can be send to any of the defined groups indexed starting by 1
  # optional last argument starting with g indicates the group
  my $groupnr = 1;
  $groupnr = $1 if($na>2 && $a[$na-1]=~ m/g([0-9]*)/);
  return "groupnr $groupnr not known." if(!$hash->{CODE}{$groupnr}); 

  my $v = join(" ", @a);
  #Log GetLogLevel($name,2), "EIB set $v";
  Log 5, "EIB set $v";
  (undef, $v) = split(" ", $v, 2);	# Not interested in the name...

  if($value eq "raw" && defined($arg1)) {                                
  	# complex value command.
  	# the additional argument is transfered alone.
    $c = $arg1;
  } elsif ($value eq "value" && defined($arg1)) {
  	# value to be translated according to datapoint type
  	$c = EIB_EncodeByDatapointType($hash,$name,$arg1);
  	
  	# set the value to the back translated value
  	$v = EIB_ParseByDatapointType($hash,$name,$c);
  }

  my $groupcode = $hash->{CODE}{$groupnr};
  #IOWrite($hash, "B", "w" . $groupcode . $c);
  my $model = $attr{$name}{"model"};
  my $code = $eib_dpttypes{"$model"}{"CODE"};
  if ($code eq 'dpt7') {
    IOWrite($hash, "B", "b" . $groupcode . $c);
  }
  else {
    IOWrite($hash, "B", "w" . $groupcode . $c);
  }

  ###########################################
  # Delete any timer for on-for_timer
  if($modules{EIB}{ldata}{$name}) {
    CommandDelete(undef, $name . "_timer");
    delete $modules{EIB}{ldata}{$name};
  }
   
  ###########################################
  # Add a timer if any for-timer command has been chosen
  if($value =~ m/for-timer/ && defined($arg1)) {
    my $dur = $arg1;
    my $to = sprintf("%02d:%02d:%02d", $dur/3600, ($dur%3600)/60, $dur%60);
    $modules{EIB}{ldata}{$name} = $to;
    Log 4, "Follow: +$to set $name off g$groupnr";
    CommandDefine(undef, $name . "_timer at +$to set $name off g$groupnr");
  }

  ###########################################
  # Delete any timer for on-till
  if($modules{EIB}{till}{$name}) {
    CommandDelete(undef, $name . "_till");
    delete $modules{EIB}{till}{$name};
  }
  
  ###########################################
  # Add a timer if on-till command has been chosen
  if($value =~ m/on-till/ && defined($arg1)) {
	  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($arg1);
	  if($err) {
	  	Log(2,"Error trying to parse timespec for $a[0] $a[1] $a[2] : $err");
	  }
	  else {
		  my @lt = localtime;
		  my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
		  my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
		  if($hms_now ge $hms_till) {
		    Log 4, "on-till: won't switch as now ($hms_now) is later than $hms_till";
		  }
		  else {
		    $modules{EIB}{till}{$name} = $hms_till;
		    Log 4, "Follow: $hms_till set $name off g$groupnr";
		    CommandDefine(undef, $name . "_till at $hms_till set $name off g$groupnr");
		  }
	  }
  }
  

  ##########################
  # Look for all devices with the same code, and set state, timestamp
  my $code = "$hash->{GROUP}";
  my $tn = TimeNow();
  #foreach my $n (keys %{ $modules{EIB}{defptr}{$code} }) {
  
  #  my $lh = $modules{EIB}{defptr}{$code}{$n};
  #  $lh->{CHANGED}[0] = $v;
  #  $lh->{STATE} = $v;
  #  $lh->{READINGS}{state}{TIME} = $tn;
  #  $lh->{READINGS}{state}{VAL} = $v;

  #	readingsSingleUpdate($lh,"state",$v,1);
  #}
  
  my $defptr = $modules{EIB}{defptr}{$code};
  foreach my $n (keys %{ $defptr }) {
    readingsSingleUpdate($defptr->{$n}, "state", $v, 1);
  }
  return $ret;
}


sub
EIB_Parse($$)
{
  my ($hash, $msg) = @_;

  # Msg format: 
  # B(w/r/p)<group><value> i.e. Bw00000101
  # we will also take reply telegrams into account, 
  # as they will be sent if the status is asked from bus 
  if($msg =~ m/^B(.{4})[w|p](.{4})(.*)$/)
  {
  	# only interested in write / reply group messages
  	my $src = $1;
  	my $dev = $2;
  	my $val = $3;

	my $v = $codes{$val};
    $v = "$val" if(!defined($v));
    my $rawv = $v;

	my @list;
	my $found = 0;
	
   	# check if the code is within the read groups
    # we will inform all definitions subsribed to this code	
   	foreach my $mod (keys %{$modules{EIB}{defptr}})
   	{
   		my $def = $modules{EIB}{defptr}{"$mod"};
	    if($def) {
		    foreach my $n (keys %{ $def }) {
		      my $lh = $def->{$n};
	          foreach my $c (keys %{ $lh->{CODE} } ) 
		      {
	    	    $c = $lh->{CODE}{$c};
	    	    if($c eq $dev)
	    	    {
			      $n = $lh->{NAME};        # It may be renamed
			
			      next if(IsIgnored($n));   # Little strange.
			
				  # parse/translate by datapoint type
			      $v = EIB_ParseByDatapointType($lh,$n,$rawv);
			
			      #$lh->{CHANGED}[0] = $v;
			      #$lh->{STATE} = $v;
			      $lh->{RAWSTATE} = $rawv;
			      $lh->{LASTGROUP} = $dev;
			      #$lh->{READINGS}{state}{TIME} = TimeNow();
			      #$lh->{READINGS}{state}{VAL} = $v;
				  
				  readingsSingleUpdate($lh,"state",$v,1);
				  
				  Log 5, "EIB $n $v";
				  
			      push(@list, $n);
			      $found = 1;
	    	    }
		    }}
	    }
   	}
   		
    	
  	return @list if $found>0;
    		
   	if($found==0)
   	{
	    my $dev_name = eib_hex2name($dev);
   		Log(3, "EIB Unknown device $dev ($dev_name), Value $val, please define it");
   		return "UNDEFINED EIB_$dev EIB $dev";
   	}
  }
}

sub
EIB_EncodeByDatapointType($$$)
{
	my ($hash, $name, $value) = @_;
	my $model = $attr{$name}{"model"};
	
	# nothing to do if no model is given
	return $value if(!defined($model));
	
	my $dpt = $eib_dpttypes{"$model"};
	Log(4,"EIB encode $value for $name model: $model dpt: $dpt");
	return $value if(!defined($dpt));

	my $code = $eib_dpttypes{"$model"}{"CODE"};
	my $unit = $eib_dpttypes{"$model"}{"UNIT"};
	my $transval = undef;
	my $adjustment = $eib_dpttypes{"$model"}{"ADJUSTMENT"};
	
	Log(4,"EIB encode $value for $name model: $model dpt: $code unit: $unit");
	
	if ($code eq "dpt5") 
	{
		my $dpt5factor = $eib_dpttypes{"$model"}{"factor"};
		my $fullval = sprintf("00%.2x",($value/$dpt5factor));
		$transval = $fullval;
				
		Log(5,"EIB $code encode $value = $fullval factor = $dpt5factor translated: $transval");
		
	} elsif ($code eq "dpt7") 
	{
		my $fullval = sprintf("00%.2x",$value);
		$transval = $fullval;
		if($adjustment eq "255") {
			$transval = ($fullval / 2.55);
			$transval = sprintf("%.0f",$transval);
		} else {
			$transval = $fullval;
		}
				
		Log(5,"EIB $code encode $value = $fullval translated: $transval");
		
	} elsif($code eq "dpt9") 
	{
		#my $sign = $value<0?-1:1;
		#my $absval = abs($value);
		#my $exp = $absval==0?0:int(log($absval)/log(2));
		#my $mant = $absval / (2**$exp) *100;
		#$mant = ((~($mant+1))&0x07FF) if($sign<0);
		
		#my $fullval = $mant+2048*$exp;
		#$fullval |=0x8000 if($sign<0);
		
		#$transval = sprintf("00%.4x",$fullval);
		
		#Log(5,"EIB $code encode $value = $fullval sign: $sign mant: $mant exp: $exp translated: $transval");
		
		$transval = encode_dpt9($value);		
		Log(5,"EIB $code encode $value translated: $transval");	
		
	} elsif ($code eq "dpt10") 
	{
		# set current Time
		my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		$year+=1900;
		$mon++;
		
        # calculate offset for weekday
		if ($wday eq "0") {
			$wday = 7;
		}
		my $hoffset = 32*$wday;
 		
		#my $fullval = $secs + ($mins<<8) + ($hours<<16);
		my $fullval = $secs + ($mins<<8) + (($hoffset + $hours)<<16);

		$transval = sprintf("00%.6x",$fullval);
				
		Log(5,"EIB $code encode $value = $fullval hours: $hours mins: $mins secs: $secs translated: $transval");
		
	} elsif ($code eq "dpt10_ns") 
	{
		# set current Time
		my ($secs,$mins,$hours,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		my $secZero = 0;
		$year+=1900;
		$mon++;

        # calculate offset for weekday
		if ($wday eq "0") {
			$wday = 7;
		}
		my $hoffset = 32*$wday;
 		
		#my $fullval = $secs + ($mins<<8) + ($hours<<16);		
		my $fullval = $secZero + ($mins<<8) + (($hoffset + $hours)<<16);

		$transval = sprintf("00%.6x",$fullval);
				
		Log(5,"EIB $code encode $value = $fullval hours: $hours mins: $mins secs: $secs translated: $transval");
		
	} elsif ($code eq "dpt11") 
	{
		# set current Date
		my ($secs,$mins,$hours,$day,$month,$year,$wday,$yday,$isdst) = localtime(time);
		$year+=1900;
		$month++;
		
		my $fullval = ($year-2000) + ($month<<8) + ($day<<16);
		$transval = sprintf("00%.6x",$fullval);

		Log(5,"EIB $code encode $value = $fullval day: $day month: $month year: $year translated: $transval");
		
	} elsif ($code eq "dpt12") 
	{
		my $fullval = sprintf("00%.8x",$value);
		$transval = $fullval;
				
		Log(5,"EIB $code encode $value = $fullval translated: $transval");
		
	} elsif($code eq "dpt14") 
	{
		$transval = encode_dpt14($value);		
		Log(5,"EIB $code encode $value translated: $transval");	
		
	} elsif ($code eq "dptxx") {
		
	}
	
	
	# set state to translated value
	if(defined($transval))
	{
		Log(4,"EIB $name translated $value $unit to $transval");
		$value = "$transval";
	}
	else
	{
		Log(4,"EIB $name model $model value $value could not be translated/encoded. Just do a dec2hex translation");
		$value = sprintf("00%.2x",$value);
		
	}
	
	return $value;
}

sub
EIB_ParseByDatapointType($$$)
{
	my ($hash, $name, $value) = @_;
	my $model = $attr{$name}{"model"};
	
	# nothing to do if no model is given
	return $value if(!defined($model));
	
	my $dpt = $eib_dpttypes{"$model"};
	
	Log(4,"EIB parse $value for $name model: $model dpt: $dpt");
	return $value if(!defined($dpt));
	
	my $code = $eib_dpttypes{"$model"}{"CODE"};
	my $unit = $eib_dpttypes{"$model"}{"UNIT"};
	my $transval = undef;
	
	Log(4,"EIB parse $value for $name model: $model dpt: $code unit: $unit");
	
	if ($code eq "dpt5") 
	{
		if ($value eq "on") 
		{
		  $value = "1";
		}

		my $dpt5factor = $eib_dpttypes{"$model"}{"factor"};
		my $fullval = hex($value);
		$transval = $fullval;
		$transval = sprintf("%.0f",$transval * $dpt5factor) if($dpt5factor != 0);
				
		Log(5,"EIB $code parse $value = $fullval factor = $dpt5factor translated: $transval");
		
	} elsif ($code eq "dpt7") 
	{
		my $fullval = hex($value);
		$transval = $fullval;		
				
		Log(5,"EIB $code parse $value = $fullval translated: $transval");
		
	} elsif($code eq "dpt9") 
	{
		my $fullval = hex($value);
		my $sign = 1;
		$sign = -1 if(($fullval & 0x8000)>0);
		my $exp = ($fullval & 0x7800)>>11;
		my $mant = ($fullval & 0x07FF);
		$mant = -(~($mant-1)&0x07FF) if($sign==-1);
		
		$transval = (1<<$exp)*0.01*$mant;
		
		Log(5,"EIB $code parse $value = $fullval sign: $sign mant: $mant exp: $exp translated: $transval");	
		
		
	} elsif ($code eq "dpt10") 
	{
		# Time
		my $fullval = hex($value);
		my $hours = ($fullval & 0x1F0000)>>16;
		my $mins  = ($fullval & 0x3F00)>>8;
		my $secs  = ($fullval & 0x3F);
		$transval = sprintf("%02d:%02d:%02d",$hours,$mins,$secs);
				
		Log(5,"EIB $code parse $value = $fullval hours: $hours mins: $mins secs: $secs translated: $transval");
		
	} elsif ($code eq "dpt10_ns") 
	{
		# Time
		my $fullval = hex($value);
		my $hours = ($fullval & 0x1F0000)>>16;
		my $mins  = ($fullval & 0x3F00)>>8;
		my $secs  = ($fullval & 0x3F);
		$transval = sprintf("%02d:%02d",$hours,$mins);
				
		Log(5,"EIB $code parse $value = $fullval hours: $hours mins: $mins translated: $transval");
		
	} elsif ($code eq "dpt11") 
	{
		# Date
		my $fullval = hex($value);
		my $day = ($fullval & 0x1F0000)>>16;
		my $month  = ($fullval & 0x0F00)>>8;
		my $year  = ($fullval & 0x7F);
		#translate year (21st cent if <90 / else 20th century)
		$year += 1900 if($year>=90);
		$year += 2000 if($year<90);
		$transval = sprintf("%02d.%02d.%04d",$day,$month,$year);
				
		Log(5,"EIB $code parse $value = $fullval day: $day month: $month year: $year translated: $transval");
		
	} elsif ($code eq "dpt12") 
	{
		my $fullval = hex($value);
		$transval = $fullval;		
				
		Log(5,"EIB $code parse $value = $fullval translated: $transval");
		
	} elsif ($code eq "dpt14") # contributed by Olaf
    	{
        	# 4 byte single precision float
       	 	my $byte0 = hex(substr($value,0,2));
        	my $sign = ($byte0 & 0x80) ? -1 : 1;

        	my $bytee = hex(substr($value,0,4));
        	my $expo = (($bytee & 0x7F80) >> 7) - 127;

        	my $bytem = hex(substr($value,2,6));
        	my $mant = ($bytem & 0x7FFFFF | 0x800000);

        	$transval = $sign * (2 ** $expo) * ($mant / (1 <<23));
                
        	Log(5,"EIB $code parse $value translated: $transval");
	} elsif ($code eq "dpt16") {

	    $transval= decode_dpt16($value);

		Log(5,"EIB $code parse $value translated: $transval");
	} elsif ($code eq "dptxx") {
		
	}
	
	# set state to translated value
	if(defined($transval))
	{
		Log(4,"EIB $name translated to $transval $unit");
		$value = "$transval $unit";
	}
	else
	{
		Log(4,"EIB $name model $model value $value could not be translated.");
	}
	
	return $value;
}

#############################
sub decode_dpt16($)
{ 
  # 14byte char
  my $val = shift;
  my $res = "";  

  for (my $i=0;$i<14;$i++) {
    my $c = hex(substr($val,$i*2,2));
    if ($c eq 0) {
      $i = 14;
    } else {
      $res .=  sprintf("%c", $c);
    }
  }
  return sprintf("%s","$res");
}
#############################
sub
eib_hex2name($)
{
  my $v = shift;
  
  my $p1 = hex(substr($v,0,1));
  my $p2 = hex(substr($v,1,1));
  my $p3 = hex(substr($v,2,2));
  
  my $r = sprintf("%d/%d/%d", $p1,$p2,$p3);
  return $r;
}

#############################
sub
eib_name2hex($)
{
  my $v = shift;
  my $r = $v;
  Log(5, "name2hex: $v");
  if($v =~ /^([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{1,3})$/) {
  	$r = sprintf("%01x%01x%02x",$1,$2,$3);
  }
  elsif($v =~ /^([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,3})$/) {
  	$r = sprintf("%01x%01x%02x",$1,$2,$3);
  }  
    
  return $r;
}

#############################
# 2byte signed float
sub encode_dpt9 {
    my $state = shift;
    my $data;
	my $retVal;

    my $sign = ($state <0 ? 0x8000 : 0);
    my $exp  = 0;
    my $mant = 0;

    $mant = int($state * 100.0);
    while (abs($mant) > 2047) {
        $mant /= 2;
        $exp++;
    }
    $data = $sign | ($exp << 11) | ($mant & 0x07ff);
	
	#Log(1,"State: $state Sign: $sign Exp: $exp Mant: $mant Data: $data");	
	
	$retVal = sprintf("00%.4x",$data);
	
    return $retVal;
}

#############################
# 4byte signed float
sub encode_dpt14 {

	my $real = shift; 
	my $packed_float = pack "f", $real; 
	my $data  = sprintf("%04X", unpack("L",  pack("f", $real))); 

	#Log(1,"Shift: $real Value: $data");	

    return $data
}

1;

=pod
=begin html

<a name="EIB"></a>
<h3>EIB / KNX</h3>
<ul>
  EIB/KNX is a standard for building automation / home automation.
  It is mainly based on a twisted pair wiring, but also other mediums (ip, wireless) are specified.

  While the module <a href="#TUL">TUL</a> represents the connection to the EIB network,
  the EIB modules represent individual EIB devices. This module provides a basic set of operations (on, off, on-till, etc.)
  to switch on/off EIB devices. Sophisticated setups can be achieved by combining a number of
  EIB module instances or by sending raw hex values to the network (set <devname> raw <hexval>).

  EIB/KNX defines a series of Datapoint Type as standard data types used
  to allow general interpretation of values of devices manufactured by diferent companies.
  This datatypes are used to interpret the status of a device, so the state in FHEM will then
  show the correct value.

  <br><br>
  <a name="EIBdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EIB &lt;main group&gt; [&lt;additional group&gt; ..]</code>
    <br><br>

    Define an EIB device, connected via a <a href="#TUL">TUL</a>. The
    &lt;group&gt; parameters are either a group name notation (0-15/0-15/0-255) or the hex representation of the value (0-f0-f0-ff).
    The &lt;main group&gt;  is used for sending of commands to the EIB network.
    The state of the instance will be updated when a new state is received from the network for any of the given groups.
    This is usefull for example for toggle switches where a on command is send to one group and the real state (on or off) is
    responded back on a second group.

    For actors and sensors the
    <a href="#autocreate">autocreate</a> module may help.<br>

    Example:
    <ul>
      <code>define lamp1 EIB 0/10/12</code><br>
      <code>define lamp1 EIB 0/10/12 0/0/5</code><br>
      <code>define lamp1 EIB 0A0C</code><br>
    </ul>
  </ul>
  <br>

  <a name="EIBset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;time&gt; g&lt;groupnr&gt;]</code><br>
    where value one of:
	<li><b>on</b> switch on device</li>
	<li><b>off</b> switch off device</li>
	<li><b>on-for-timer</b> <secs> switch on the device for the given time. After the specified seconds a switch off command is sent.</li>
	<li><b>on-till</b> <time spec> switches the device on. The device will be switched off at the given time.</li>
    <li><b>raw</b> <hexvalue> sends the given value as raw data to the device.</li>
    <li><b>value</b> <decimal value> transforms the value according to the chosen model and send the result to the device.</li>

    <br>Example:
    <ul><code>
      set lamp1 on<br>
      set lamp1 off<br>
      set lamp1 on-for-timer 10<br>
      set lamp1 on-till 13:15:00<br>
      set lamp1 raw 234578<br>
      set lamp1 value 23.44<br>
    </code></ul>

	When as last argument a g&lt;groupnr&gt; is present, the command will be sent
	to the EIB group indexed by the groupnr (starting by 1, in the order as given in Define).
	<br>Example:
	<ul><code>
	   define lamp1 EIB 0/10/01 0/10/02<br>
	   set lamp1 on g2 (will send "on" to 0/10/02)
	</code></ul>

	A dimmer can be used with a slider as shown in following example:
	<br><ul><code>
		define dim1 EIB 0/0/5
		attr dim1 model percent
		attr dim1 webCmd value
	</code></ul>
	
	The current date and time can be sent to the bus by the following settings:
	<br><ul><code>
	
	define timedev EIB 0/0/7
	attr timedev model dpt10
	attr timedev eventMap /value now:now/
	attr timedev webCmd now
	
	define datedev EIB 0/0/8
	attr datedev model dpt11
	attr datedev eventMap /value now:now/
	attr datedev webCmd now
	
	# send every midnight the new date
	define dateset at *00:00:00 set datedev value now
	
	# send every hour the current time
	define timeset at +*01:00:00 set timedev value now
	</code></ul>	
	
  </ul>
  <br>

  <a name="EIBattr"></a>
  <b>Attributes</b>
  <ul>

    <li><a href="#IODev">IODev</a></li>
    <li><a href="#alias">alias</a></li>
    <li><a href="#comment">comment</a></li>
    <li><a href="#devStateIcon">devStateIcon</a></li>
    <li><a href="#devStateStyle">devStateStyle</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#event-aggregator">event-aggregator</a></li>
    <li><a href="#event-min-interval">event-min-interval</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#group">group</a></li>
    <li><a href="#icon">icon</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#room">room</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#sortby">sortby</a></li>
    <li><a href="#stateFormat">stateFormat</a></li>
    <li><a href="#userReadings">userReadings</a></li>
    <li><a href="#userattr">userattr</a></li>
    <li><a href="#verbose">verbose</a></li>
    <li><a href="#webCmd">webCmd</a></li>
    <li><a href="#widgetOverride">widgetOverride</a></li>
    <li><a href="#model">model</a>
      set the model according to the datapoint types defined by the (<a href="http://www.sti.uniurb.it/romanell/110504-Lez10a-KNX-Datapoint%20Types%20v1.5.00%20AS.pdf" target="_blank">EIB / KNX specifications</a>).<br>
      The device state in FHEM is interpreted and shown according to the specification.
      <ul>
      	<li>dpt5</li>
      	<li>dpt5.003</li>
      	<li>angle</li>
      	<li>percent</li>
      	<li>dpt5.004</li>
      	<li>percent255</li>
      	<li>dpt7</li>
      	<li>length-mm</li>
      	<li>current-mA</li>
      	<li>brightness</li>
      	<li>timeperiod-ms</li>
      	<li>timeperiod-min</li>
      	<li>timeperiod-h</li>
      	<li>dpt9</li>
      	<li>tempsensor</li>
      	<li>lightsensor</li>
      	<li>speedsensor</li>
      	<li>speedsensor-km/h</li>
      	<li>pressuresensor</li>
      	<li>rainsensor</li>
      	<li>time1sensor</li>
      	<li>time2sensor</li>
      	<li>humiditysensor</li>
      	<li>airqualitysensor</li>
      	<li>voltage-mV</li>
      	<li>current-mA2</li>
      	<li>current-mA2</li>
      	<li>power</li>
      	<li>powerdensity</li>
      	<li>dpt10</li>
		<li>dpt10_ns</li>
      	<li>time</li>
      	<li>dpt11</li>
      	<li>date</li>
      	<li>dpt12</li>
      	<li>dpt14</li>
      	<li>dpt16</li>
      </ul>
    </li>
  </ul>

  </ul>
  <br>


=end html
=cut
