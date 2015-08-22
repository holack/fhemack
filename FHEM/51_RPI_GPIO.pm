##############################################################################
# $Id: 51_RPI_GPIO.pm 8570 2015-05-12 20:35:19Z klauswitt $
# 51_RPI_GPIO.pm
#
##############################################################################
# Modul for Raspberry Pi GPIO access
#
# define <name> RPI_GPIO <Pin>
# where <Pin> is one of RPi's GPIO 
#
# contributed by Klaus Wittstock (2013) email: klauswittstock bei gmail
#
##############################################################################

package main;
use strict;
use warnings;
use POSIX;
use Scalar::Util qw(looks_like_number);
use IO::File;
use SetExtensions;

sub RPI_GPIO_fileaccess($$;$);

sub RPI_GPIO_Initialize($) {
	my ($hash) = @_;
	$hash->{DefFn}    = "RPI_GPIO_Define";
	$hash->{GetFn}    = "RPI_GPIO_Get";
	$hash->{SetFn}    = "RPI_GPIO_Set";
	$hash->{StateFn}  = "RPI_GPIO_State";
	$hash->{AttrFn}   = "RPI_GPIO_Attr";
	$hash->{UndefFn}  = "RPI_GPIO_Undef";
	$hash->{ExceptFn} = "RPI_GPIO_Except";
	$hash->{AttrList} = "poll_interval" .
											" direction:input,output pud_resistor:off,up,down" .
											" interrupt:none,falling,rising,both" .
											" toggletostate:no,yes active_low:no,yes" .
											" debounce_in_ms restoreOnStartup:no,yes,on,off,last" .
											" longpressinterval " .
											"$readingFnAttributes";
}

my $gpiodir = "/sys/class/gpio";			#GPIO base directory
my $gpioprg = "/usr/local/bin/gpio";		#WiringPi GPIO utility

my %setsoutp = (
'on:noArg' => 0,
'off:noArg' => 0,
'toggle:noArg' => 0,
);

my %setsinpt = (
'readValue' => 0,
);

sub RPI_GPIO_Define($$) {
 my ($hash, $def) = @_;

 my @args = split("[ \t]+", $def);
 my $menge = int(@args);
 if (int(@args) < 3)
 {
	return "Define: to less arguments. Usage:\n" .
				 "define <name> RPI_GPIO <GPIO>";
 }

 #Pruefen, ob GPIO bereits verwendet
 foreach my $dev (devspec2array("TYPE=$hash->{TYPE}")) {
	if ($args[2] eq InternalVal($dev,"RPI_pin","")) {
		return "GPIO $args[2] already used by $dev";
  }
 }
 
 my $name = $args[0];
 $hash->{RPI_pin} = $args[2];
 $hash->{dir_not_set} = 1;
 
 if(-e "$gpiodir/gpio$hash->{RPI_pin}" && -w "$gpiodir/gpio$hash->{RPI_pin}/value" && -w "$gpiodir/gpio$hash->{RPI_pin}/direction") {			#GPIO bereits exportiert?
	Log3 $hash, 4, "$name: gpio$hash->{RPI_pin} already exists";
	#nix tun...ist ja schon da
 } elsif (-w "$gpiodir/export") {																																																					#gpio export Datei mit schreibrechten?
	Log3 $hash, 4, "$name: write access to file $gpiodir/export, use it to export GPIO";
	my $exp = IO::File->new("> $gpiodir/export");																																														#gpio ueber export anlegen 
	print $exp "$hash->{RPI_pin}";
	$exp->close;
 } else {
	if ( defined(my $ret = RPI_GPIO_CHECK_GPIO_UTIL($gpioprg)) ) {							#Abbbruch da kein gpio utility vorhanden
			Log3 $hash, 1, "$name: can't export gpio$hash->{RPI_pin}, no write access to $gpiodir/export and " . $ret;
			return "$name: can't export gpio$hash->{RPI_pin}, no write access to $gpiodir/export and " . $ret;
		} else {														#nutze GPIO Utility?
		Log3 $hash, 4, "$name: using gpio utility to export pin";
		RPI_GPIO_exuexpin($hash, "in");
		}
 }
 
	# wait for Pin export (max 5s)
	my $checkpath = qq($gpiodir/gpio$hash->{RPI_pin}/value);
	my $counter = 100;
	while( $counter ){
		last if( -e $checkpath && -w $checkpath );
		Time::HiRes::sleep( 0.05 );
		$counter --;
	}
	unless( $counter ) {																												#abbrechen wenn export fehlgeschlagen
		#nochmal probieren wenn keine Schreibrechte##########
		if ( defined(my $ret = RPI_GPIO_CHECK_GPIO_UTIL($gpioprg)) ) {							#Abbbruch da kein gpio utility vorhanden
			Log3 $hash, 1, "$name: can't export gpio$hash->{RPI_pin}, no write access to $gpiodir/export and " . $ret;
			Log3 $hash, 1, "$name: failed to export pin gpio$hash->{RPI_pin}";
        	return "$name: failed to export pin gpio$hash->{RPI_pin}";
		} else {														#nutze GPIO Utility?
			Log3 $hash, 4, "$name: using gpio utility to export pin (first export failed)";
			RPI_GPIO_exuexpin($hash, "in");
		}
		#####################################################
#		Log3 $hash, 1, "$name: failed to export pin gpio$hash->{RPI_pin}";
#       return "$name: failed to export pin gpio$hash->{RPI_pin}";
	}

 $hash->{fhem}{interfaces} = "switch";
 return undef;
}

sub RPI_GPIO_Get($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	#my $dir = $attr{$hash->{NAME}}{direction} || "output";
	my $dir = "";
	my $zustand = undef;
	my $val = RPI_GPIO_fileaccess($hash, "value");
	if ( defined ($val) ) {
		if ( $val == 1) {
			if ($dir eq "output") {$zustand = "on";} else {$zustand = "high";}
		} elsif ( $val == 0 ) {
			if ($dir eq "output") {$zustand = "off";} else {$zustand = "low";}
		}
	} else { 
		Log3 $hash, 1, "$hash->{NAME} GetFn: readout of Pinvalue fail"; 
	}
	$hash->{READINGS}{Pinlevel}{VAL} = $zustand;
	$hash->{READINGS}{Pinlevel}{TIME} = TimeNow();
	return "Current Value for $name: $zustand";
}

sub RPI_GPIO_Set($@) {
	my ($hash, @a) = @_;
	my $name =$a[0];
	my $cmd = $a[1];
	#my $val = $a[2];

	if(defined($attr{$name}) && defined($attr{$name}{"direction"})) {
		my $mt = $attr{$name}{"direction"};
		if($mt && $mt eq "output") {
			#if ($cmd eq 'toggle') {
			#	my $val = RPI_GPIO_fileaccess($hash, "value");     #alten Wert des GPIO direkt auslesen
			#	$cmd = $val eq "0" ? "on" :"off";
			#}
			if ($cmd eq 'on') {
				RPI_GPIO_fileaccess($hash, "value", "1");
				#$hash->{STATE} = 'on';
				readingsBeginUpdate($hash);
				#readingsBulkUpdate($hash, 'Pinlevel', $valalt);
				readingsBulkUpdate($hash, 'state', "on");
				readingsEndUpdate($hash, 1);
			} elsif ($cmd eq 'off') {
				RPI_GPIO_fileaccess($hash, "value", "0");
				#$hash->{STATE} = 'off';
				readingsBeginUpdate($hash);
				#readingsBulkUpdate($hash, 'Pinlevel', $valalt);
				readingsBulkUpdate($hash, 'state', "off");
				readingsEndUpdate($hash, 1);
			} else {
				my $slist = join(' ', keys %setsoutp);
                Log3 $hash, 5, "wird an setextensions gesendet: @a";
				return SetExtensions($hash, $slist, @a);
			}
		} else {
			if(!defined($setsinpt{$cmd})) {
				return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %setsinpt)
			} else {
			}
		}
	}
	if ($cmd eq 'readValue') { #noch bei input einpflegen
		RPI_GPIO_updatevalue($hash);
	} 
}

sub RPI_GPIO_State($$$$) {	#reload readings at FHEM start
	my ($hash, $tim, $sname, $sval) = @_;
	Log3 $hash, 4, "$hash->{NAME}: $sname kann auf $sval wiederhergestellt werden $tim";

	#if ( (AttrVal($hash->{NAME},"restoreOnStartup","yes") eq "yes") && ($sname ne "STATE") ) {
	if ( $sname ne "STATE" && AttrVal($hash->{NAME},"restoreOnStartup","last") ne "no") {
		if (AttrVal($hash->{NAME},"direction","") eq "output") {
			$hash->{READINGS}{$sname}{VAL} = $sval;
			$hash->{READINGS}{$sname}{TIME} = $tim;
			Log3 $hash, 4, "OUTPUT $hash->{NAME}: $sname wiederhergestellt auf $sval";
			if ($sname eq "state") {
				my $rval = AttrVal($hash->{NAME},"restoreOnStartup","last");
				$rval = "last" if ( $rval ne "on" && $rval ne "off" );
				$sval = $rval eq "last" ? $sval : $rval;
				#RPI_GPIO_Set($hash,$hash->{NAME},$sname,$sval);
				RPI_GPIO_Set($hash,$hash->{NAME},$sval);
				Log3 $hash, 4, "OUTPUT $hash->{NAME}: STATE wiederhergestellt auf $sval (restoreOnStartup=$rval)";
			} 
		} elsif ( AttrVal($hash->{NAME},"direction","") eq "input") {
			if ($sname eq "Toggle") {
        #wenn restoreOnStartup "on" oder "off" und der Wert mit dem im Statefile uebereinstimmt wird der Zeitstempel aus dem Statefile gesetzt
				my $rval = AttrVal($hash->{NAME},"restoreOnStartup","last");
				$rval = "last" if ( $rval ne "on" && $rval ne "off" );
				$tim  = gettimeofday() if $rval ne "last" && $rval ne $sval;
				$sval = $rval eq "last" ? $sval : $rval;
		
				$hash->{READINGS}{$sname}{VAL} = $sval;
				$hash->{READINGS}{$sname}{TIME} = $tim;
				Log3 $hash, 4, "INPUT $hash->{NAME}: $sname wiederhergestellt auf $sval";
				#RPI_GPIO_Set($hash,$hash->{NAME},$sval);
				if ((AttrVal($hash->{NAME},"toggletostate","") eq "yes")) {
					readingsBeginUpdate($hash);
					readingsBulkUpdate($hash, 'state', $sval);
					readingsEndUpdate($hash, 1);
					Log3 $hash, 4, "INPUT $hash->{NAME}: STATE wiederhergestellt auf $sval";
				}
			} elsif ($sname eq "Counter") {
          		$hash->{READINGS}{$sname}{VAL} = $sval;
          		$hash->{READINGS}{$sname}{TIME} = $tim;
          		Log3 $hash, 4, "INPUT $hash->{NAME}: $sname wiederhergestellt auf $sval";	
			} elsif ( ($sname eq "state") && (AttrVal($hash->{NAME},"toggletostate","") ne "yes") ) {
          		#my $rval = AttrVal($hash->{NAME},"restoreOnStartup","");
          		#if ($rval eq "" && (AttrVal($hash->{NAME},"toggletostate","") ne "yes") ) {
           		Log3 $hash, 4, "INPUT $hash->{NAME}: alter Pinwert war: $sval";
            	my $val = RPI_GPIO_fileaccess($hash, "value");
           		$val = $val eq "1" ? "on" :"off";
           		Log3 $hash, 4, "INPUT $hash->{NAME}: aktueller Pinwert ist: $val";
           		if ($val ne $sval) {
              		Log3 $hash, 4, "INPUT $hash->{NAME}: Pinwerte ungleich...Timer gesetzt";
              		InternalTimer(gettimeofday() + (10), 'RPI_GPIO_Poll', $hash, 0);
           		} else {
              		$hash->{READINGS}{$sname}{VAL} = $sval;
              		$hash->{READINGS}{$sname}{TIME} = $tim;
           		}
          		#}
      		}
		}
	}
	return;
}

sub RPI_GPIO_Attr(@) {
	my (undef, $name, $attr, $val) = @_;
	my $hash = $defs{$name};
	my $msg = '';
 
	if ($attr eq 'poll_interval') {
		if ( defined($val) ) {
			if ( looks_like_number($val) && $val > 0) {
				RemoveInternalTimer($hash);
				InternalTimer(1, 'RPI_GPIO_Poll', $hash, 0);
			} else {
			$msg = "$hash->{NAME}: Wrong poll intervall defined. poll_interval must be a number > 0";
			}
		} else { #wird auch aufgerufen wenn $val leer ist, aber der attribut wert wird auf 1 gesetzt
			RemoveInternalTimer($hash);
		}
	}
	if ($attr eq 'longpressinterval') {
		if ( defined($val) ) {
			unless ( looks_like_number($val) && $val >= 0.1 && $val <= 10 ) {
				$msg = "$hash->{NAME}: Wrong longpress time defined. Value must be a number between 0.1 and 10";
			}
		} 
	}
  if ($attr eq 'direction') {
		if (!$val) { #$val nicht definiert: Einstellungen loeschen
			$msg = "$hash->{NAME}: no direction value. Use input output";
		} elsif ($val eq "input") {
			delete($hash->{dir_not_set});
			RPI_GPIO_fileaccess($hash, "direction", "in");
			#RPI_GPIO_exuexpin($hash, "in");
			Log3 $hash, 5, "$hash->{NAME}: set attr direction: input"; 
		} elsif( ( AttrVal($hash->{NAME}, "interrupt", "none") ) ne ( "none" ) ) {
			$msg = "$hash->{NAME}: Delete attribute interrupt or set it to none for output direction"; 
		} elsif ($val eq "output") {
			unless ($hash->{dir_not_set}) {							#direction bei output noch nicht setzten (erfolgt bei erstem schreiben vom Wert um kurzes umschalten beim fhem start zu unterbinden)
				RPI_GPIO_fileaccess($hash, "direction", "out");
				#RPI_GPIO_exuexpin($hash, "out");
				Log3 $hash, 5, "$hash->{NAME}: set attr direction: output";
			} else {
				Log3 $hash, 5, "$hash->{NAME}: set attr direction: output vorerst NICHT";
			}
		} else {
			$msg = "$hash->{NAME}: Wrong $attr value. Use input output";
		}
	}
  if ($attr eq 'interrupt') {
    if ( !$val || ($val eq "none") ) {
      RPI_GPIO_fileaccess($hash, "edge", "none");
      RPI_GPIO_inthandling($hash, "stop");
      Log3 $hash, 5, "$hash->{NAME}: set attr interrupt: none"; 
    } elsif (( AttrVal($hash->{NAME}, "direction", "output") ) eq ( "output" )) {
      $msg = "$hash->{NAME}: Wrong direction value defined for interrupt. Use input";
    } elsif ($val eq "falling") {
      RPI_GPIO_fileaccess($hash, "edge", "falling");
      RPI_GPIO_inthandling($hash, "start");
      Log3 $hash, 5, "$hash->{NAME}: set attr interrupt: falling"; 
    } elsif ($val eq "rising") {
      RPI_GPIO_fileaccess($hash, "edge", "rising");
      RPI_GPIO_inthandling($hash, "start");
      Log3 $hash, 5, "$hash->{NAME}: set attr interrupt: rising";  
    } elsif ($val eq "both") {
      RPI_GPIO_fileaccess($hash, "edge", "both");
      RPI_GPIO_inthandling($hash, "start");
      Log3 $hash, 5, "$hash->{NAME}: set attr interrupt: both";  
    } else {
      $msg = "$hash->{NAME}: Wrong $attr value. Use none, falling, rising or both";
    }  
  }
#Tastfunktion: bei jedem Tastendruck wird State invertiert
  if ($attr eq 'toggletostate') {
    unless ( !$val || ($val eq ("yes" || "no") ) ) {
      $msg = "$hash->{NAME}: Wrong $attr value. Use yes or no";
    }
  }
#invertierte Logik 
  if ($attr eq 'active_low') {
    if ( !$val || ($val eq "no" ) ) {
      RPI_GPIO_fileaccess($hash, "active_low", "0");
      Log3 $hash, 5, "$hash->{NAME}: set attr active_low: no"; 
    } elsif ($val eq "yes") {
      RPI_GPIO_fileaccess($hash, "active_low", "1");
      Log3 $hash, 5, "$hash->{NAME}: set attr active_low: yes";
    } else {
      $msg = "$hash->{NAME}: Wrong $attr value. Use yes or no";
    }
  }
#Entprellzeit
  if ($attr eq 'debounce_in_ms') {
    if ( $val && ( ($val > 250) || ($val < 0) ) ) {
      $msg = "$hash->{NAME}: debounce_in_ms value to big. Use 0 to 250";
    }
  }
	if ($attr eq 'pud_resistor') {#nur fuer Raspberry (ueber gpio utility)
		my $pud;
		if ( defined(my $ret = RPI_GPIO_CHECK_GPIO_UTIL($gpioprg)) ) {
			Log3 $hash, 1, "$hash->{NAME}: unable to change pud resistor:" . $ret;
			return "$hash->{NAME}: " . $ret;
		} else {
			if ( !$val ) {
			} elsif ($val eq "off") {
				$pud = $gpioprg.' -g mode '.$hash->{RPI_pin}.' tri';
				$pud = `$pud`;
			} elsif ($val eq "up") {
				$pud = $gpioprg.' -g mode '.$hash->{RPI_pin}.' up';
				$pud = `$pud`;
			} elsif ($val eq "down") {
				$pud = $gpioprg.' -g mode '.$hash->{RPI_pin}.' down';
				$pud = `$pud`;
			} else {
				$msg = "$hash->{NAME}: Wrong $attr value. Use off, up or down";
			}
		}
	}
	return ($msg) ? $msg : undef; 
}

sub RPI_GPIO_Poll($) {		#for attr poll_intervall -> readout pin value
	my ($hash) = @_;
	my $name = $hash->{NAME};
	RPI_GPIO_updatevalue($hash);
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'RPI_GPIO_Poll', $hash, 0);
	}
	return;
} 

sub RPI_GPIO_Undef($$) {
	my ($hash, $arg) = @_;
	if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ) {
		RemoveInternalTimer($hash);
	}
	if ( ( AttrVal($hash->{NAME}, "interrupt", "none") ) ne ( "none" ) ) {
		delete $selectlist{$hash->{NAME}};
		close($hash->{filehandle});
	}
	if (-w "$gpiodir/unexport") {#unexport Pin alte Version
		my $uexp = IO::File->new("> $gpiodir/unexport");
		print $uexp "$hash->{RPI_pin}";
		$uexp->close;
	} else {#alternative unexport Pin:
		RPI_GPIO_exuexpin($hash, "unexport");
	}
	Log3 $hash, 1, "$hash->{NAME}: entfernt";
	return undef;
}

sub RPI_GPIO_Except($) {	#called from main if an interrupt occured 
	my ($hash) = @_;
	#seek($hash->{filehandle},0,0);								#an Anfang der Datei springen (ist noetig falls vorher schon etwas gelesen wurde)
	#chomp ( my $firstval = $hash->{filehandle}->getline );		#aktuelle Zeile auslesen und Endezeichen entfernen
	#my $acttime = gettimeofday();
	my $eval = RPI_GPIO_fileaccess($hash, "edge");							#Eintstellung Flankensteuerung auslesen
	my ($valst, $valalt, $valto, $valcnt, $vallp) = undef;
	my $debounce_time = AttrVal($hash->{NAME}, "debounce_in_ms", "0"); #Wartezeit zum entprellen
	if( $debounce_time ne "0" ) {
		$debounce_time /= 1000;
		Log3 $hash, 4, "Wartezeit: $debounce_time ms"; 
		select(undef, undef, undef, $debounce_time);
	}

	seek($hash->{filehandle},0,0);								#an Anfang der Datei springen (ist noetig falls vorher schon etwas gelesen wurde)
	chomp ( my $val = $hash->{filehandle}->getline );				#aktuelle Zeile auslesen und Endezeichen entfernen

	if ( ( $val == 1) && ( $eval ne ("falling") ) ) {
		$valst = "on";
		$valalt = "high";
	} elsif ( ( $val == 0 ) && ($eval ne "rising" ) ) {
		$valst = "off";
		$valalt = "low";
	}
	if ( ( ($eval eq "rising") && ( $val == 1 ) ) || ( ($eval eq "falling") && ( $val == 0 ) ) ) {	#nur bei Trigger auf steigende / fallende Flanke
#Togglefunktion
		if (!defined($hash->{READINGS}{Toggle}{VAL})) {			#Togglewert existiert nicht -> anlegen
			Log3 $hash, 5, "Toggle war nicht def";
			$valto = "on";
		} elsif ( $hash->{READINGS}{Toggle}{VAL} eq "off" ) {		#Togglewert invertieren
			Log3 $hash, 5, "Toggle war auf $hash->{READINGS}{Toggle}{VAL}";
			$valto = "on";
		} else {
			Log3 $hash, 5, "Toggle war auf $hash->{READINGS}{Toggle}{VAL}";
			$valto = "off";
		}
		Log3 $hash, 5, "Toggle ist jetzt $valto";
		if (( AttrVal($hash->{NAME}, "toggletostate", "no") ) eq ( "yes" )) {	#wenn Attr "toggletostate" gesetzt auch die Variable fuer den STATE wert setzen
			$valst = $valto;
		}
#Zaehlfunktion
		if (!defined($hash->{READINGS}{Counter}{VAL})) {			#Zaehler existiert nicht -> anlegen
			Log3 $hash, 5, "Zaehler war nicht def";
			$valcnt = "1";
		} else {
		$valcnt = $hash->{READINGS}{Counter}{VAL} + 1;
		Log3 $hash, 5, "Zaehler ist jetzt $valcnt";
		}
#langer Testendruck
	} elsif ($eval eq "both") {
		if ( $val == 1 ) {
			my $lngpressInterval = AttrVal($hash->{NAME}, "longpressinterval", "1");
			InternalTimer(gettimeofday() + $lngpressInterval, 'RPI_GPIO_longpress', $hash, 0);
			#$hash->{Anzeit} = gettimeofday();
		} else {
			RemoveInternalTimer('RPI_GPIO_longpress');
			$vallp = 'off';
			#my $zeit = $acttime;
			#$zeit -= $hash->{Anzeit};
			#Log3 $hash, 5, "Anzeit: $zeit";
			#readingsBeginUpdate($hash);
			#readingsBulkUpdate($hash, 'Anzeit', $zeit);
			#readingsEndUpdate($hash, 1);
		}
	}

	delete ($hash->{READINGS}{Toggle})    if ($eval ne ("rising" || "falling"));		#Reading Toggle loeschen wenn Edge weder "rising" noch "falling"
	delete ($hash->{READINGS}{Longpress}) if ($eval ne "both");					#Reading Longpress loeschen wenn edge nicht "both"
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'Pinlevel',  $valalt);
	readingsBulkUpdate($hash, 'state',     $valst);
	readingsBulkUpdate($hash, 'Toggle',    $valto)  if ($valto);
	readingsBulkUpdate($hash, 'Counter',   $valcnt) if ($valcnt);
	readingsBulkUpdate($hash, 'Longpress', $vallp)  if ($vallp);
	readingsEndUpdate($hash, 1);
	#Log3 $hash, 5, "RPIGPIO: Except ausgeloest: $hash->{NAME}, Wert: $val, edge: $eval,vt: $valto, $debounce_time s: $firstval";
}

sub RPI_GPIO_longpress($) {			#for reading longpress
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $val = RPI_GPIO_fileaccess($hash, "value");
	if ($val == 1) {
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'Longpress', 'on');
		readingsEndUpdate($hash, 1);
	}
}

sub RPI_GPIO_dblclick($) {

}

sub RPI_GPIO_updatevalue($) {		#update value for Input devices
	my ($hash) = @_;
	my $val = RPI_GPIO_fileaccess($hash, "value");
	if ( defined ($val) ) {
		my ($valst, $valalt) = undef;
		if ( $val == 1) {
			$valst = "on";
			$valalt = "high";
		} elsif ( $val == 0 ) {
			$valst = "off";
			$valalt = "low";
		}
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'Pinlevel', $valalt);
		readingsBulkUpdate($hash, 'state', $valst) if (( AttrVal($hash->{NAME}, "toggletostate", "no") ) eq ( "no" ));
		readingsEndUpdate($hash, 1);
	} else {
	Log3 $hash, 1, "$hash->{NAME}: readout of Pinvalue fail";
	}
}

sub RPI_GPIO_fileaccess($$;$) {						#Fileaccess for GPIO base directory
 #my ($hash, $fname, $value) = @_;
	my ($hash, @args) = @_;
	my $fname = $args[0];
	my $pinroot = qq($gpiodir/gpio$hash->{RPI_pin});
	my $file =qq($pinroot/$fname);
	Log3 $hash, 5, "$hash->{NAME}, in fileaccess: $fname " . (defined($args[1])?$args[1]:"");

	if ($hash->{dir_not_set} && $fname eq "value") {			#direction setzen (bei output direkt status mit schreiben)
		delete($hash->{dir_not_set});
		my $dir = AttrVal($hash->{NAME},"direction","input");
		$dir = $dir eq "input" ? "in" : "out";
		if ($dir eq "out" && $fname eq "value" && defined($args[1])) {
			my $al = AttrVal($hash->{NAME},"active_low","no");
			my $lev = $al eq "yes" ? 0 : 1;
			$dir = ($args[1] == $lev ? "high" : "low")
		} 
		#$dir = ($args[1] == 1 ? "high" : "low") if ($dir eq "out" && $fname eq "value" && defined($args[1]));
		RPI_GPIO_fileaccess($hash, "direction", $dir);
		Log3 $hash, 4, "$hash->{NAME}: direction gesetzt auf $dir";
	}

	if (int(@args) < 2){
		my $fh = IO::File->new("< $file");
		if (defined $fh) {
			chomp ( my $pinvalue = $fh->getline );
			$fh->close;
			return $pinvalue;
		} else {
			Log3 $hash, 1, "Can't open file: $hash->{NAME}, $fname";
		}
	} else {
		my $value = $args[1];
		if ($fname eq "direction" && (not -w $file)) {		#wenn direction und diese nicht schreibbar mit gpio utility versuchen
			Log3 $hash, 4, "$hash->{NAME}: direction ueber gpio utility einstellen";
			RPI_GPIO_exuexpin($hash, $value);
			#if ( defined(my $ret = RPI_GPIO_CHECK_GPIO_UTIL($gpioprg)) ) {
			#	Log3 $hash, 1, "$hash->{NAME}: " . $ret;
			#} else {
				#my $exp = $gpioprg.' -g mode '.$hash->{RPI_pin}. ' '.$value;
				#$exp = `$exp`;
			#}
		} else {
			my $fh = IO::File->new("> $file");
			if (defined $fh) {
				print $fh "$value";
				$fh->close;
			} else {
				Log3 $hash, 1, "Can't open file: $hash->{NAME}, $fname";
			}
		}
	}
}
	
sub RPI_GPIO_exuexpin($$) {			#export, unexport and direction Pin via GPIO utility
	my ($hash, $dir) = @_;
	my $sw;
	if ($dir eq "unexport") {
		$sw = $dir;
		$dir = "";
	} else {
		$sw = "export";
        $dir = "out" if ( $dir eq "high" || $dir eq "low" );		#auf out zurueck, da gpio tool dies nicht unterst?tzt
		$dir = " ".$dir;
	}
	if ( defined(my $ret = RPI_GPIO_CHECK_GPIO_UTIL($gpioprg)) ) {
		Log3 $hash, 1, "$hash->{NAME}: " . $ret;
	} else {
		my $exp = $gpioprg.' '.$sw.' '.$hash->{RPI_pin}.$dir;
		$exp = `$exp`;
	}
 #######################
}

sub RPI_GPIO_CHECK_GPIO_UTIL {
	my ($gpioprg) = @_;
	my $ret = undef;
	#unless (defined($hash->{gpio_util_exists})) {
	if(-e $gpioprg) {
		if(-x $gpioprg) {
			unless(-u $gpioprg) {
				$ret = "file $gpioprg is not setuid"; 
			}
		} else {
			$ret = "file $gpioprg is not executable"; 
		}
	} else {
		$ret = "file $gpioprg doesnt exist"; 
	}
	return $ret;
}

sub RPI_GPIO_inthandling($$) {		#start/stop Interrupthandling
	my ($hash, $arg) = @_;
	my $msg = '';
	if ( $arg eq "start") {
		#FH fuer value-datei
		my $pinroot = qq($gpiodir/gpio$hash->{RPI_pin});
		my $valfile = qq($pinroot/value);
		$hash->{filehandle} = IO::File->new("< $valfile"); 
		if (!defined $hash->{filehandle}) {
			$msg = "Can't open file: $hash->{NAME}, $valfile";
		} else {
			$selectlist{$hash->{NAME}} = $hash;
			$hash->{EXCEPT_FD} = fileno($hash->{filehandle});
			my $pinvalue = $hash->{filehandle}->getline;
			Log3 $hash, 5, "Datei: $valfile, FH: $hash->{filehandle}, EXCEPT_FD: $hash->{EXCEPT_FD}, akt. Wert: $pinvalue";
		}
	} else {
		delete $selectlist{$hash->{NAME}};
		close($hash->{filehandle});
	}
}

1;

=pod
=begin html

<a name="RPI_GPIO"></a>
<h3>RPI_GPIO</h3>
(en | <a href="commandref_DE.html#RPI_GPIO">de</a>)
<ul>
	<a name="RPI_GPIO"></a>
		Raspberry Pi offers direct access to several GPIO via header P1 (and P5 on V2). The Pinout is shown in table under define. 
		With this module you are able to access these GPIO's directly as output or input. For input you can use either polling or interrupt mode<br>
		In addition to the Raspberry Pi, also BBB, Cubie, Banana Pi and almost every linux system which provides gpio access in userspace is supported.<br>
		<b>Warning: Never apply any external voltage to an output configured pin! GPIO's internal logic operate with 3,3V. Don't exceed this Voltage!</b><br><br>
		<b>preliminary:</b><br>
		GPIO Pins accessed by sysfs. The files are located in folder <code>/system/class/gpio</code> and belong to the gpio group (on actual Raspbian distributions since jan 2014).<br>
		After execution of following commands, GPIO's are usable whithin PRI_GPIO:<br>
		<ul><code>
			sudo adduser fhem gpio<br>
			sudo reboot
		</code></ul><br>
		If attribute <code>pud_resistor</code> shall be used and on older Raspbian distributions, aditionally gpio utility from <a href="http://wiringpi.com/download-and-install/">WiringPi</a>
		library must be installed to set the internal pullup/down resistor or export and change access rights of GPIO's (for the second case active_low does <b>not</b> work).<br>
		Installation WiringPi:<br>
		<ul><code>
			sudo apt-get update<br>
			sudo apt-get upgrade<br>
			sudo apt-get install git-core<br>
			git clone git://git.drogon.net/wiringPi<br>
			cd wiringPi
			./build
		</code></ul><br>
	On Linux systeme where <code>/system/class/gpio</code> can only accessed as root, GPIO's must exported and their access rights changed before FHEM starts.<br>
	This can be done in <code>/etc/rc.local</code> (Examole for GPIO22 and 23):<br>
	<ul><code>
		echo 22 > /sys/class/gpio/export<br>
		echo 23 > /sys/class/gpio/export<br>
		chown -R fhem:root /sys/devices/virtual/gpio/* (or chown -R fhem:gpio /sys/devices/platform/gpio-sunxi/gpio/* for Banana Pi)<br>
		chown -R fhem:root /sys/class/gpio/*<br>
	</code></ul><br> 
	<a name="RPI_GPIODefine"></a>
	<b>Define</b>
	<ul>
		<code>define <name> RPI_GPIO &lt;GPIO number&gt;</code><br><br>
		all usable <code>GPIO number</code> are in the following tables<br><br>
		
	<table border="0" cellspacing="0" cellpadding="0">
      <td> 
        PCB Revision 1 P1 pin header
        <table border="2" cellspacing="0" cellpadding="4" rules="all" style="margin:1em 1em 1em 0; border:solid 1px #000000; border-collapse:collapse; font-size:80%; empty-cells:show;">
		<tr><td>Function</td>			 <td>Pin</td><td></td><td>Pin</td>	<td>Function</td></tr>
		<tr><td>3,3V</td>    			 <td>1</td>  <td></td><td>2</td>  	<td>5V</td></tr>
		<tr><td><b>GPIO 0 (SDA0)</b></td><td>3</td>  <td></td><td>4</td>	<td></td></tr>
		<tr><td><b>GPIO 1 (SCL0)</b></td><td>5</td>  <td></td><td>6</td>	<td>GND</td></tr>
		<tr><td>GPIO 4 (GPCLK0)</td>	 <td>7</td>  <td></td><td>8</td>	<td>GPIO 14 (TxD)</td></tr>
		<tr><td></td>					 <td>9</td>  <td></td><td>10</td>	<td>GPIO 15 (RxD)</td></tr>
		<tr><td>GPIO 17</td>			 <td>11</td> <td></td><td>12</td>	<td>GPIO 18 (PCM_CLK)</td></tr>
		<tr><td><b>GPIO 21</b></td>	 	 <td>13</td> <td></td><td>14</td>	<td></td></tr>
		<tr><td>GPIO 22</td>			 <td>15</td> <td></td><td>16</td>	<td>GPIO 23</td></tr>
		<tr><td></td>					 <td>17</td> <td></td><td>18</td>	<td>GPIO 24</td></tr>
		<tr><td>GPIO 10 (MOSI)</td>	 	 <td>19</td> <td></td><td>20</td>	<td></td></tr>
		<tr><td>GPIO 9 (MISO)</td>		 <td>21</td> <td></td><td>22</td>	<td>GPIO 25</td></tr>
		<tr><td>GPIO 11 (SCLK)</td>	 	 <td>23</td> <td></td><td>24</td>	<td>GPIO 8 (CE0)</td></tr>
		<tr><td></td>					 <td>25</td> <td></td><td>26</td>	<td>GPIO 7 (CE1)</td></tr></table>
	  </td>
	  <td>
	    PCB Revision 2 P1 pin header
		<table border="2" cellspacing="0" cellpadding="4" rules="all" style="margin:1em 1em 1em 0; border:solid 1px #000000; border-collapse:collapse; font-size:80%; empty-cells:show;">
		<tr><td>Function</td>			 <td>Pin</td><td></td><td>Pin</td>	<td>Function</td></tr>
		<tr><td>3,3V</td>    			 <td>1</td>  <td></td><td>2</td>  	<td>5V</td></tr>
		<tr><td><b>GPIO 2 (SDA1)</b></td><td>3</td>  <td></td><td>4</td>	<td></td></tr>
		<tr><td><b>GPIO 3 (SCL1)</b></td><td>5</td>  <td></td><td>6</td>	<td>GND</td></tr>
		<tr><td>GPIO 4 (GPCLK0)</td>	 <td>7</td>  <td></td><td>8</td>	<td>GPIO 14 (TxD)</td></tr>
		<tr><td></td>					 <td>9</td>  <td></td><td>10</td>	<td>GPIO 15 (RxD)</td></tr>
		<tr><td>GPIO 17</td>			 <td>11</td> <td></td><td>12</td>	<td>GPIO 18 (PCM_CLK)</td></tr>
		<tr><td><b>GPIO 27</b></td>	 	 <td>13</td> <td></td><td>14</td>	<td></td></tr>
		<tr><td>GPIO 22</td>			 <td>15</td> <td></td><td>16</td>	<td>GPIO 23</td></tr>
		<tr><td></td>					 <td>17</td> <td></td><td>18</td>	<td>GPIO 24</td></tr>
		<tr><td>GPIO 10 (MOSI)</td>	 	 <td>19</td> <td></td><td>20</td>	<td></td></tr>
		<tr><td>GPIO 9 (MISO)</td>		 <td>21</td> <td></td><td>22</td>	<td>GPIO 25</td></tr>
		<tr><td>GPIO 11 (SCLK)</td>	 	 <td>23</td> <td></td><td>24</td>	<td>GPIO 8 (CE0)</td></tr>
		<tr><td></td>					 <td>25</td> <td></td><td>26</td>	<td>GPIO 7 (CE1)</td></tr></table>	
	  </td>
	  <td>
	    PCB Revision 2 P5 pin header
		<table border="2" cellspacing="0" cellpadding="4" rules="all" style="margin:1em 1em 1em 0; border:solid 1px #000000; border-collapse:collapse; font-size:80%; empty-cells:show;">
		<tr><td>Function</td>	   <td>Pin</td><td></td><td>Pin</td><td>Function</td></tr>
		<tr><td>5V</td>    		   <td>1</td>  <td></td><td>2</td>  <td>3,3V</td></tr>
		<tr><td>GPIO 28 (SDA0)</td><td>3</td>  <td></td><td>4</td>	<td>GPIO 29 (SCL0)</td></tr>
		<tr><td>GPIO 30</td>	   <td>5</td>  <td></td><td>6</td>	<td>GPOI 31</td></tr> 
		<tr><td>GND</td>	 	   <td>7</td>  <td></td><td>8</td>	<td>GND</td></tr></table>
	  </td>
	</table>
    
    Examples:
    <pre>
      define Pin12 RPI_GPIO 18
      attr Pin12 poll_interval 5
    </pre>
  </ul>

  <a name="RPI_GPIOSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <ul><li>for output configured GPIO
      <ul><code>
        off<br>
        on<br>
        toggle<br>		
        </code>
      </ul>
      The <a href="#setExtensions"> set extensions</a> are also supported.<br>
      </li>
      <li>for input configured GPIO
      <ul><code>
        readval		
      </code></ul>
      readval refreshes the reading Pinlevel and, if attr toggletostate not set, the state value
    </ul>   
    </li><br>
     Examples:
    <ul>
      <code>set Pin12 off</code><br>
      <code>set Pin11,Pin12 on</code><br>
    </ul><br>
  </ul>

  <a name="RPI_GPIOGet"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt;</code>
    <br><br>
    returns "high" or "low" regarding the actual status of the pin and writes this value to reading <b>Pinlevel</b>
  </ul><br>

  <a name="RPI_GPIOAttr"></a>
  <b>Attributes</b>
  <ul>
    <li>direction<br>
      Sets the GPIO direction to input or output.<br>
      Default: input, valid values: input, output<br><br>
    </li>
    <li>active_low<br>
      Inverts logical value<br>
      Default: off, valid values: on, off<br><br>
    </li>    
    <li>interrupt<br>
      <b>can only be used with GPIO configured as input</b><br>
      enables edge detection for GPIO pin<br>
      on each interrupt event readings Pinlevel and state will be updated<br>
      Default: none, valid values: none, falling, rising, both<br>
	  For "both" the reading Longpress will be added and set to on as long as kes hold down longer than 1s<br>
	  For "falling" and "rising" the reading Toggle will be added an will be toggled at every interrupt and the reading Counter that increments at every interrupt<br><br>
    </li>
    <li>poll_interval<br>
      Set the polling interval in minutes to query the GPIO's level<br>
      Default: -, valid values: decimal number<br><br>
    </li>
    <li>toggletostate<br>
      <b>works with interrupt set to falling or rising only</b><br>
      if yes, state will be toggled at each interrupt event<br>
      Default: no, valid values: yes, no<br><br>
    </li>
    <li>pud_resistor<br>
      Sets the internal pullup/pulldown resistor<br>
	  <b>Works only with installed gpio urility from <a href="http://wiringpi.com/download-and-install/">WiringPi</a> Library.</b><br>
      Default: -, valid values: off, up, down<br><br>
    </li>
    <li>debounce_in_ms<br>
      readout of pin value x ms after an interrupt occured. Can be used for switch debouncing<br>
      Default: 0, valid values: decimal number<br><br>
    </li>
    <li>restoreOnStartup<br>
      Restore Readings and sets after reboot<br>
      Default: last, valid values: last, on, off, no<br><br>
    </li>
	<li>longpressinterval<br>
	  <b>works with interrupt set to both only</b><br>
      time in seconds, a port need to be high to set reading longpress to on<br>
      Default: 1, valid values: 0.1 - 10<br><br>
    </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>


=end html

=begin html_DE

<a name="RPI_GPIO"></a>
<h3>RPI_GPIO</h3>
(<a href="commandref.html#RPI_GPIO">en</a> | de)
<ul>
  <a name="RPI_GPIO"></a>
    Das Raspberry Pi erm&ouml;glicht direkten Zugriff zu einigen GPIO's &uuml;ber den Pfostenstecker P1 (und P5 bei V2). Die Steckerbelegung ist in den Tabellen unter Define zu finden.
    Dieses Modul erm&ouml;glicht es, die herausgef&uuml;hrten GPIO's direkt als Ein- und Ausgang zu benutzen. Die Eing&auml;nge k&ouml;nnen zyklisch abgefragt werden oder auch sofort bei Pegelwechsel gesetzt werden.<br>
		Neben dem Raspberry Pi k&ouml;nnen auch die GPIO's von BBB, Cubie, Banana Pi und jedem Linuxsystem, das diese im Userspace zug&auml;gig macht, genutzt werden.<br>
    <b>Wichtig: Niemals Spannung an einen GPIO anlegen, der als Ausgang eingestellt ist! Die interne Logik der GPIO's arbeitet mit 3,3V. Ein &uuml;berschreiten der 3,3V zerst&ouml;rt den GPIO und vielleicht auch den ganzen Prozessor!</b><br><br>
    <b>Vorbereitung:</b><br>
		Auf GPIO Pins wird im Modul &uuml;ber sysfs zugegriffen. Die Dateien befinden sich unter <code>/system/class/gpio</code> und sind in der aktuellen Raspbian Distribution (ab Jan 2014) in der Gruppe gpio.<br>
		Nach dem ausf&uuml;hren folgender Befehle sind die GPIO's von PRI_GPIO aus nutzbar:<br>
		<ul><code>
			sudo adduser fhem gpio<br>
			sudo reboot
		</code></ul><br>
		Wenn das Attribut <code>pud_resistor</code> verwendet werden soll und f&uuml;r &auml;ltere Raspbian Distributionen, muss zus&auml;tzlich das gpio Tool der <a href="http://wiringpi.com/download-and-install/">WiringPi</a>
		Bibliothek installiert werden, um den internen Pullup/down Widerstand zu aktivieren, bzw. GPIO's zu exportieren und die korrekten Nutzerrechte zu setzen (f&uuml;r den zweiten Fall funktioniert das active_low Attribut <b>nicht</b>).<br>
		Installation WiringPi:<br>
		<ul><code>
			sudo apt-get update<br>
			sudo apt-get upgrade<br>
			sudo apt-get install git-core<br>
			git clone git://git.drogon.net/wiringPi<br>
			cd wiringPi
			./build
  	</code></ul><br>
		F&uuml;r Linux Systeme bei denen der Zugriff auf <code>/system/class/gpio</code> nur mit root Rechten erfolgen kann, m&uuml;ssen die GPIO's vor FHEM start exportiert und von den Rechten her angepasst werden.<br>
		Dazu in die <code>/etc/rc.local</code> folgendes einf&uuml;gen (Beispiel f&uuml;r GPIO22 und 23):<br>
		<ul><code>
			echo 22 > /sys/class/gpio/export<br>
			echo 23 > /sys/class/gpio/export<br>
			chown -R fhem:root /sys/devices/virtual/gpio/* (oder chown -R fhem:gpio /sys/devices/platform/gpio-sunxi/gpio/* f&uuml;r Banana Pi)<br>
			chown -R fhem:root /sys/class/gpio/*<br>
		</code></ul><br>
	<a name="RPI_GPIODefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; RPI_GPIO &lt;GPIO number&gt;</code><br><br>
    Alle verf&uuml;gbaren <code>GPIO number</code> sind in den folgenden Tabellen zu finden<br><br>
    
	<table border="0" cellspacing="0" cellpadding="0">    
    <td> 
    PCB Revision 1 P1 pin header
    <table border="2" cellspacing="0" cellpadding="4" rules="all" style="margin:1em 1em 1em 0; border:solid 1px #000000; border-collapse:collapse; font-size:80%; empty-cells:show;">
		<tr><td>Function</td>			 <td>Pin</td><td></td><td>Pin</td>	<td>Function</td></tr>
		<tr><td>3,3V</td>    			 <td>1</td>  <td></td><td>2</td>  	<td>5V</td></tr>
		<tr><td><b>GPIO 0 (SDA0)</b></td><td>3</td>  <td></td><td>4</td>	<td></td></tr>
		<tr><td><b>GPIO 1 (SCL0)</b></td><td>5</td>  <td></td><td>6</td>	<td>GND</td></tr>
		<tr><td>GPIO 4 (GPCLK0)</td>	 <td>7</td>  <td></td><td>8</td>	<td>GPIO 14 (TxD)</td></tr>
		<tr><td></td>					 <td>9</td>  <td></td><td>10</td>	<td>GPIO 15 (RxD)</td></tr>
		<tr><td>GPIO 17</td>			 <td>11</td> <td></td><td>12</td>	<td>GPIO 18 (PCM_CLK)</td></tr>
		<tr><td><b>GPIO 21</b></td>	 	 <td>13</td> <td></td><td>14</td>	<td></td></tr>
		<tr><td>GPIO 22</td>			 <td>15</td> <td></td><td>16</td>	<td>GPIO 23</td></tr>
		<tr><td></td>					 <td>17</td> <td></td><td>18</td>	<td>GPIO 24</td></tr>
		<tr><td>GPIO 10 (MOSI)</td>	 	 <td>19</td> <td></td><td>20</td>	<td></td></tr>
		<tr><td>GPIO 9 (MISO)</td>		 <td>21</td> <td></td><td>22</td>	<td>GPIO 25</td></tr>
		<tr><td>GPIO 11 (SCLK)</td>	 	 <td>23</td> <td></td><td>24</td>	<td>GPIO 8 (CE0)</td></tr>
		<tr><td></td>					 <td>25</td> <td></td><td>26</td>	<td>GPIO 7 (CE1)</td></tr></table>
	  </td>
	  <td>
	    PCB Revision 2 P1 pin header
		<table border="2" cellspacing="0" cellpadding="4" rules="all" style="margin:1em 1em 1em 0; border:solid 1px #000000; border-collapse:collapse; font-size:80%; empty-cells:show;">
		<tr><td>Function</td>			 <td>Pin</td><td></td><td>Pin</td>	<td>Function</td></tr>
		<tr><td>3,3V</td>    			 <td>1</td>  <td></td><td>2</td>  	<td>5V</td></tr>
		<tr><td><b>GPIO 2 (SDA1)</b></td><td>3</td>  <td></td><td>4</td>	<td></td></tr>
		<tr><td><b>GPIO 3 (SCL1)</b></td><td>5</td>  <td></td><td>6</td>	<td>GND</td></tr>
		<tr><td>GPIO 4 (GPCLK0)</td>	 <td>7</td>  <td></td><td>8</td>	<td>GPIO 14 (TxD)</td></tr>
		<tr><td></td>					 <td>9</td>  <td></td><td>10</td>	<td>GPIO 15 (RxD)</td></tr>
		<tr><td>GPIO 17</td>			 <td>11</td> <td></td><td>12</td>	<td>GPIO 18 (PCM_CLK)</td></tr>
		<tr><td><b>GPIO 27</b></td>	 	 <td>13</td> <td></td><td>14</td>	<td></td></tr>
		<tr><td>GPIO 22</td>			 <td>15</td> <td></td><td>16</td>	<td>GPIO 23</td></tr>
		<tr><td></td>					 <td>17</td> <td></td><td>18</td>	<td>GPIO 24</td></tr>
		<tr><td>GPIO 10 (MOSI)</td>	 	 <td>19</td> <td></td><td>20</td>	<td></td></tr>
		<tr><td>GPIO 9 (MISO)</td>		 <td>21</td> <td></td><td>22</td>	<td>GPIO 25</td></tr>
		<tr><td>GPIO 11 (SCLK)</td>	 	 <td>23</td> <td></td><td>24</td>	<td>GPIO 8 (CE0)</td></tr>
		<tr><td></td>					 <td>25</td> <td></td><td>26</td>	<td>GPIO 7 (CE1)</td></tr></table>	
	  </td>
	  <td>
	    PCB Revision 2 P5 pin header
		<table border="2" cellspacing="0" cellpadding="4" rules="all" style="margin:1em 1em 1em 0; border:solid 1px #000000; border-collapse:collapse; font-size:80%; empty-cells:show;">
		<tr><td>Function</td>	   <td>Pin</td><td></td><td>Pin</td><td>Function</td></tr>
		<tr><td>5V</td>    		   <td>1</td>  <td></td><td>2</td>  <td>3,3V</td></tr>
		<tr><td>GPIO 28 (SDA0)</td><td>3</td>  <td></td><td>4</td>	<td>GPIO 29 (SCL0)</td></tr>
		<tr><td>GPIO 30</td>	   <td>5</td>  <td></td><td>6</td>	<td>GPOI 31</td></tr> 
		<tr><td>GND</td>	 	   <td>7</td>  <td></td><td>8</td>	<td>GND</td></tr></table>
	  </td>
	</table>
    
    Beispiele:
    <pre>
      define Pin12 RPI_GPIO 18
      attr Pin12 poll_interval 5
    </pre>
  </ul>

  <a name="RPI_GPIOSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    <code>value</code> ist dabei einer der folgenden Werte:<br>
    <ul><li>F&uuml;r GPIO der als output konfiguriert ist
      <ul><code>
        off<br>
        on<br>
        toggle<br>		
        </code>
      </ul>
      Die <a href="#setExtensions"> set extensions</a> werden auch unterst&uuml;tzt.<br>
      </li>
      <li>F&uuml;r GPIO der als input konfiguriert ist
      <ul><code>
        readval		
      </code></ul>
      readval aktualisiert das reading Pinlevel und, wenn attr toggletostate nicht gesetzt ist, auch state
    </ul>   
    </li><br>
     Beispiele:
    <ul>
      <code>set Pin12 off</code><br>
      <code>set Pin11,Pin12 on</code><br>
    </ul><br>
  </ul>

  <a name="RPI_GPIOGet"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt;</code>
    <br><br>
    Gibt "high" oder "low" entsprechend dem aktuellen Pinstatus zur&uuml;ck und schreibt den Wert auch in das reading <b>Pinlevel</b>
  </ul><br>

  <a name="RPI_GPIOAttr"></a>
  <b>Attributes</b>
  <ul>
    <li>direction<br>
      Setzt den GPIO auf Ein- oder Ausgang.<br>
      Standard: input, g&uuml;ltige Werte: input, output<br><br>
    </li>
    <li>active_low<br>
      Invertieren des logischen Wertes<br>
      Standard: off, g&uuml;ltige Werte: on, off<br><br>
    </li>  
    <li>interrupt<br>
      <b>kann nur gew&auml;hlt werden, wenn der GPIO als Eingang konfiguriert ist</b><br>
      Aktiviert Flankenerkennung f&uuml;r den GPIO<br>
      bei jedem interrupt Ereignis werden die readings Pinlevel und state aktualisiert<br>
      Standard: none, g&uuml;ltige Werte: none, falling, rising, both<br><br>
	  Bei "both" wird ein reading Longpress angelegt, welches auf on gesetzt wird solange der Pin l&auml;nger als 1s gedr&uuml;ckt wird<br>
	  Bei "falling" und "rising" wird ein reading Toggle angelegt, das bei jedem Interruptereignis toggelt und das Reading Counter, das bei jedem Ereignis um 1 hochz&auml;hlt<br><br>

    </li>
    <li>poll_interval<br>
      Fragt den Zustand des GPIO regelm&auml;&szlig;ig ensprechend des eingestellten Wertes in Minuten ab<br>
      Standard: -, g&uuml;ltige Werte: Dezimalzahl<br><br>
    </li>
    <li>toggletostate<br>
      <b>Funktioniert nur bei auf falling oder rising gesetztem Attribut interrupt</b><br>
      Wenn auf "yes" gestellt wird bei jedem Triggerereignis das <b>state</b> reading invertiert<br>
      Standard: no, g&uuml;ltige Werte: yes, no<br><br>
    </li>
    <li>pud_resistor<br>
      Interner Pullup/down Widerstand<br>
	  <b>Funktioniert ausslie&szlig;lich mit installiertem gpio Tool der <a href="http://wiringpi.com/download-and-install/">WiringPi</a> Bibliothek.</b><br>
      Standard: -, g&uuml;ltige Werte: off, up, down<br><br>
    </li>
    <li>debounce_in_ms<br>
      Wartezeit in ms bis nach ausgel&ouml;stem Interrupt der entsprechende Pin abgefragt wird. Kann zum entprellen von mechanischen Schaltern verwendet werden<br>
      Standard: 0, g&uuml;ltige Werte: Dezimalzahl<br><br>
    </li>
    <li>restoreOnStartup<br>
      Wiederherstellen der Portzust&auml;nde nach Neustart<br>
      Standard: last, g&uuml;ltige Werte: last, on, off, no<br><br>
    </li>
	<li>longpressinterval<br>
	  <b>Funktioniert nur bei auf both gesetztem Attribut interrupt</b><br>
      Zeit in Sekunden, die ein GPIO auf high verweilen muss, bevor das Reading longpress auf on gesetzt wird <br>
      Standard: 1, g&uuml;ltige Werte: 0.1 - 10<br><br>
    </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE

=cut 