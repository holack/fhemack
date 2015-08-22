##############################################
# $Id: 52_I2C_PCF8574.pm 8570 2015-05-12 20:35:19Z klauswitt $
package main;

use strict;
use warnings;
use SetExtensions;
use Scalar::Util qw(looks_like_number);

my %setsP = (
'off' => 0,
'on' => 1,
);

sub I2C_PCF8574_Initialize($) {
  my ($hash) = @_;

  #$hash->{Match}     = ".*";
  $hash->{DefFn}     = 	"I2C_PCF8574_Define";
	$hash->{InitFn}  	 =  'I2C_PCF8574_Init';
  $hash->{AttrFn}    = 	"I2C_PCF8574_Attr";
  $hash->{SetFn}     = 	"I2C_PCF8574_Set";
	$hash->{StateFn}   =  "I2C_PCF8574_State";
  $hash->{GetFn}     = 	"I2C_PCF8574_Get";
  $hash->{UndefFn}   = 	"I2C_PCF8574_Undef";
  $hash->{ParseFn}   = 	"I2C_PCF8574_Parse";
  $hash->{I2CRecFn}  = 	"I2C_PCF8574_I2CRec";
  $hash->{AttrList}  = 	"IODev do_not_notify:1,0 ignore:1,0 showtime:1,0 ".
												"poll_interval OnStartup ".
												"InputPorts:multiple-strict,0,1,2,3,4,5,6,7 ".
												"$readingFnAttributes";
}
###################################
sub I2C_PCF8574_Set($@) {					#
  my ($hash, @a) = @_;
	my $name =$a[0];
  my $cmd = $a[1];
  my $val = $a[2];
  my @inports = sort(split( " ",AttrVal($name, "InputPorts", "")));
	my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" );
	if ( $cmd && $cmd =~ m/^P(ort|)((0|)[0-7])(,(P|)(ort|)((0|)[0-7])){0,7}$/i) {
		return "wrong value: $val for \"set $name $cmd\" use one of: off, on" 
			unless(exists($setsP{$val}));
		my @scmd = split(",", $cmd);
		my $msg = undef;
		foreach (@scmd) {
			$_ =~ tr/[a-zA-Z]//d;			#Nummer aus String extrahieren
			$msg .= (defined $msg ? "," : "") . "Port" . $_ if ( $_ ~~ @inports );		#Pruefen ob entsprechender Port Input ist
		}
		return "$name error: $msg is defined as input" if $msg;
		my $sbyte = 0;
		foreach (0..7) {
			if ($_ ~~ @inports) {						#Port der als Input konfiguriert ist wird auf 1 gesetzt
				$sbyte += 1 << (1 * $_);
			} elsif( $_ ~~ @scmd ) {					#Port der geaendert werden soll
				$sbyte += $setsP{$val} << (1 * $_);
			} else {									#alle anderen Portwerte werden den Readings entnommen
				$sbyte += $setsP{ReadingsVal($name,'Port'.$_,"off")} << (1 * $_);		#->sonst aus dem Reading holen
			}
		}
		$sendpackage{data} = $sbyte;
	} elsif ( $cmd && $cmd eq "setfromreading" ) {
		my $sbyte = 0;
		foreach (0..7) {
			if ($_ ~~ @inports) {						#Port der als Input konfiguriert ist wird auf 1 gesetzt
				$sbyte += 1 << (1 * $_);
			} else {												#alle anderen Portwerte werden den Readings entnommen
				$sbyte += $setsP{ReadingsVal($name,'Port'.$_,"off")} << (1 * $_);	
			}
		}
		$sendpackage{data} = $sbyte;
	} else {
		my $list = undef;
		foreach (0..7) {
			next if ( $_ ~~ @inports );		#Inputs ueberspringen
			$list .= "Port" . $_ . ":" . join(',', (sort { $setsP{ $a } <=> $setsP{ $b } } keys %setsP) ) . " ";
    }
    return "Unknown argument $a[1], choose one of " . $list if defined $list;
		return "Unknown argument $a[1]";
	}
	return "$name: no IO device defined" unless ($hash->{IODev});
  my $phash = $hash->{IODev};
  my $pname = $phash->{NAME};
  CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
	##########################################################
	#	IOWrite($hash, \%sendpackage);
	##########################################################

  ##########################################################
  # Look for all devices with the same code, and set state, timestamp
  #my $code = "$hash->{I2C_Address} $hash->{BTN}";
  #my $code = "$hash->{NAME} $hash->{I2C_Address}";
  #my $tn = TimeNow();
  #my $defptr = $modules{I2C_PCF8574}{defptr}{$code};
  #foreach my $n (keys %{ $defptr }) {
  #	readingsSingleUpdate($defptr->{$n}, "state", $v, 1);
  #	}
	##########################################################
  return undef;
}
###################################
sub I2C_PCF8574_Get($@) {
  my ($hash, @a) = @_;
  my $name =$a[0];
	my %sendpackage = ();
	#%sendpackage = ( direction => "i2cread", id => (defined( $hash->{ID} )? $hash->{ID} : "00"), i2caddress => $hash->{I2C_Address});
	%sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cread");
	return "$name: no IO device defined" unless ($hash->{IODev});
	#neu: ueber CallFn auf eigene Funktion
	my $phash = $hash->{IODev};
  my $pname = $phash->{NAME};
	CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
	#alt: fuer IOWrite
	#IOWrite($hash, \%sendpackage); 
}
###################################
sub I2C_PCF8574_Attr(@) {					#
 my ($command, $name, $attr, $val) = @_;
 my $hash = $defs{$name};
 my $msg = '';
  if ($command && $command eq "set" && $attr && $attr eq "IODev") {
		if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
			main::AssignIoPort($hash,$val);
			my @def = split (' ',$hash->{DEF});
			I2C_PCF8574_Init($hash,\@def) if (defined ($hash->{IODev}));
		}
	}
  if ($attr eq 'poll_interval') {
    if ( defined($val) ) {
      if ( looks_like_number($val) && $val > 0) {
        RemoveInternalTimer($hash);
        InternalTimer(1, 'I2C_PCF8574_Poll', $hash, 0);
      } else {
        $msg = "$hash->{NAME}: Wrong poll intervall defined. poll_interval must be a number > 0";
      }    
    } else {
      RemoveInternalTimer($hash);
    }
  } elsif ($attr && $attr eq "InputPorts") {
		if ( defined($val) ) {
			my @inp = split(" ", $val);
			foreach (@inp) {
				$msg = "wrong value: $_ for \"set $name $attr\" use space separated numbers 0-7" unless ($_ >= 0 && $_ < 8);
			}
		}
	} elsif ($attr && $attr eq "OnStartup") {
		if (defined $val) {
			foreach (split (/,/,$val)) {
				my @pair = split (/=/,$_);
				$msg = "wrong value: $_ for \"attr $hash->{NAME} $attr\" use comma separated <port>=on|off|last where <port> = 0 - 7" 
				unless ( scalar(@pair) == 2 && ($pair[0] =~ m/^[0-7]$/i && ( $pair[1] eq "last" || exists($setsP{$pair[1]}) ) ) );		
			}
		}
	}
	return $msg
}
###################################
sub I2C_PCF8574_Define($$) {			#
 my ($hash, $def) = @_;
 my @a = split("[ \t]+", $def);
 $hash->{STATE} = 'defined';
 if ($main::init_done) {
    eval { I2C_PCF8574_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_PCF8574_Catch($@) if $@;
  }
  return undef;
}
###################################
sub I2C_PCF8574_Init($$) {				#
	my ( $hash, $args ) = @_;
	#my @a = split("[ \t]+", $args);
	my $name = $hash->{NAME}; 
	if (defined $args && int(@$args) != 1)	{
		return "Define: Wrong syntax. Usage:\n" .
		       "define <name> I2C_PCA9532 <i2caddress>";
	}
 
 if (defined (my $address = shift @$args)) {
   $hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address; 
 } else {
   return "$name I2C Address not valid";
 }
 
	#fuer die Nutzung von IOWrite
  #my $code = ( defined( $hash->{ID} )? $hash->{ID} : "00" ) . " " . $hash->{I2C_Address};
  #my $ncode = 1;
  #my $name = $a[0];
  #$hash->{CODE}{$ncode++} = $code;
  #$modules{I2C_PCF8574}{defptr}{$code}{$name}   = $hash;

  AssignIoPort($hash);
	$hash->{STATE} = 'Initialized';
	I2C_PCF8574_Set($hash, $name, "setfromreading");
	
	return;
}
###################################
sub I2C_PCF8574_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}
###################################
sub I2C_PCF8574_State($$$$) {			#reload readings at FHEM start
	my ($hash, $tim, $sname, $sval) = @_;
	Log3 $hash, 4, "$hash->{NAME}: $sname kann auf $sval wiederhergestellt werden $tim";
	if ($sname =~ m/^Port[0-7]$/i) {
		my $po = $sname; #noch �ndern 
		$po =~ tr/[a-zA-Z]//d;			#Nummer aus String extrahieren
		
		my @inports = sort(split(/ /,AttrVal($hash->{NAME}, "InputPorts", "")));
		unless ( $po ~~ @inports) {
			my %onstart = split /[,=]/, AttrVal($hash->{NAME}, "OnStartup", "");
			if ( exists($onstart{$po}) && exists($setsP{$onstart{$po}})) {
				Log3 $hash, 5, "$hash->{NAME}: $sname soll auf $onstart{$po} gesetzt werden";
				readingsSingleUpdate($hash,$sname, $onstart{$po}, 1);
			} else {
				Log3 $hash, 5, "$hash->{NAME}: $sname soll auf Altzustand: $sval gesetzt werden";
				$hash->{READINGS}{$sname}{VAL} = $sval;
				$hash->{READINGS}{$sname}{TIME} = $tim;
			}
			
		} else {
			Log3 $hash, 5, "$hash->{NAME}: $sname ist Eingang";
		}
	} 
	return undef;
}
###################################
sub I2C_PCF8574_Undef($$) {				#
  my ($hash, $name) = @_;
  if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ) {
    RemoveInternalTimer($hash);
  }
	#foreach my $c (keys %{ $hash->{CODE} } ) {
	#	$c = $hash->{CODE}{$c};
	#	my $c = ( defined( $hash->{ID} )? $hash->{ID} : "00" ) . " " . $hash->{I2C_Address};
    # As after a rename the $name my be different from the $defptr{$c}{$n}
    # we look for the hash.
  #	foreach my $dname (keys %{ $modules{I2C_PCF8574}{defptr}{$c} }) {
  #		delete($modules{I2C_PCF8574}{defptr}{$c}{$dname})
	#		if($modules{I2C_PCF8574}{defptr}{$c}{$dname} == $hash);
	#	}
	#	}
  return undef;
}
###################################
sub I2C_PCF8574_Poll($) {					#for attr poll_intervall -> readout pin values
  my ($hash) = @_;
  my $name = $hash->{NAME};
	# Read values
  I2C_PCF8574_Get($hash, $name);
  my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
  if ($pollInterval > 0) {
    InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_PCF8574_Poll', $hash, 0);
  }
} 
###################################
sub I2C_PCF8574_I2CRec($@) {			# ueber CallFn vom physical aufgerufen
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
  while ( my ( $k, $v ) = each %$clientmsg ) { 			#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
    $hash->{$k} = $v if $k =~ /^$pname/ ;
  } 
	my $sval;	
  if ($clientmsg->{direction} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok") {
		readingsBeginUpdate($hash);
		if ($clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received})) { # =~ m/^(0x|)[0-9A-F]{1,2}$/xi) {
			foreach (0..7) {
        #$sval = hex($clientmsg->{received}) & (1 << $_);
				$sval = $clientmsg->{received} & (1 << $_);
        $sval = $sval == 0 ? "off" :"on";
        readingsBulkUpdate($hash, 'Port'.$_ , $sval) if (ReadingsVal($name,'Port'.$_,"") ne $sval);
      }
	  readingsBulkUpdate($hash, 'state', $clientmsg->{received});
	} elsif ($clientmsg->{direction} eq "i2cwrite" && defined($clientmsg->{data})) { # =~ m/^(0x|)[0-9A-F]{1,2}$/xi) {
		my @inports = sort(split( " ",AttrVal($name, "InputPorts", "")));
	  foreach (0..7) {
			#$sval = hex($clientmsg->{data}) & (1 << $_);
			$sval = $clientmsg->{data} & (1 << $_);
			$sval = $sval == 0 ? "off" :"on";
			readingsBulkUpdate($hash, 'Port'.$_ , $sval) unless (ReadingsVal($name,'Port'.$_,"") eq $sval || $_ ~~ @inports );
      }
		readingsBulkUpdate($hash, 'state', $clientmsg->{data});
	}
	#readingsBulkUpdate($hash, 'state', join(" ", $clientmsg->{received}));
    readingsEndUpdate($hash, 1);
  }
}
###################################
sub I2C_PCF8574_Parse($$) {	#wird ueber dispatch vom physical device aufgerufen (dispatch wird im mom nicht verwendet)
  my ($hash, $msg) = @_;
  my($sid, $addr, @msg) = split(/ /,$msg);
  #Log3 $hash, 4, "Vom Netzerparse $hash->{NAME}: sid: $sid, Msg: @msg";
  
  my $def = $modules{I2C_PCF8574}{defptr}{"$sid $addr"};
  if($def) {
    my @list;
    foreach my $n (keys %{ $def }) {
      my $lh = $def->{$n};				# Hash bekommen
      $n = $lh->{NAME};        			# It may be renamed
      return "" if(IsIgnored($n));   	# Little strange.
	  ################################################
	  my $cde =  join(" ",@msg);
	  my $sval;
	  readingsBeginUpdate($lh);
      if ( int(@msg) == 1) {
        for (my $i = 0; $i < 8; $i++) {
           #$sval = hex($cde) & (1 << $i);
					 $sval = $cde & (1 << $i);
           $sval = $sval == 0 ? "0" :"1";
           readingsBulkUpdate($lh, 'P'.$i , $sval) if (ReadingsVal($n,'P'.$i,2) ne $sval);
        }
      } 
      readingsBulkUpdate($lh, 'state', join(" ", @msg));
      readingsEndUpdate($lh, 1);
	  ################################################
      Log3 $n, 4, "I2C_PCF8574 $n $cde";

      push(@list, $n);
    }
    return @list;

  } else {
    Log3 $hash, 3, "I2C_PCF8574 Unknown device $addr Id $sid";
    #return "UNDEFINED I2C_PCF8574_$addr$sid I2C_PCF8574 $addr $sid";
  }

}
###################################
1;

=pod
=begin html

<a name="I2C_PCF8574"></a>
<h3>I2C_PCF8574</h3>
(en | <a href="commandref_DE.html#I2C_PCF8574">de</a>)
<ul>
	<a name="I2C_PCF8574"></a>
		Provides an interface to the PCA9532 8 channel port extender IC. On Raspberry Pi the Interrupt Pin can be connected to an GPIO and <a href="#RPI_GPIO">RPI_GPIO</a> can be used to get the port values if an interrupt occurs.<br>
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br>         
	<a name="I2C_PCF8574Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_PCF8574 &lt;I2C Address&gt;</code><br>
		where <code>&lt;I2C Address&gt;</code> is without direction bit<br>
	</ul>

	<a name="I2C_PCF8574Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;port[,port[...]]&gt; &lt;value&gt;</code><br><br>
			<ul>
			<li><code>&lt;port&gt;</code> is one of Port0 to Port7 and <code>&lt;value&gt;</code> is one of:<br>
				<ul>
				<code>
					off<br>
					on<br>
				</code>
				</ul>
			</li>
			</ul>
		<br>
		Example:
		<ul>
			<code>set mod1 Port4 on</code><br>
			<code>set mod1 Port4,Port6 off</code><br>
			<code>set mod1 Port4,6 on</code><br>
		</ul><br>
	</ul>

	<a name="I2C_PCF8574Get"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt;</code>
		<br><br>
		refreshes all readings
	</ul><br>

	<a name="I2C_PCF8574Attr"></a>
	<b>Attributes</b>
	<ul>
		<li>poll_interval<br>
			Set the polling interval in minutes to query the GPIO's level<br>
			Default: -, valid values: decimal number<br><br>
		</li>
		<li>InputPorts<br>
			Space separated list of Portnumers that are used as Inputs<br>
			Ports in this list can't be written<br>
			Default: no, valid values: 0 1 2 .. 7<br><br>
		</li>
		<li>OnStartup<br>
			Comma separated list of output ports and their desired state after start<br>
			Without this atribut all output ports will set to last state<br>
			Default: -, valid values: &lt;port&gt;=on|off|last where &lt;port&gt; = 0 - 7<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#ignore">ignore</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul>
	<br>
</ul>

=end html

=begin html_DE

<a name="I2C_PCF8574"></a>
<h3>I2C_PCF8574</h3>
(<a href="commandref.html#I2C_PCF8574">en</a> | de)
<ul>
	<a name="I2C_PCF8574"></a>
		Erm&ouml;glicht die Verwendung eines PCF8574 I2C 8 Bit Portexenders. 
		Auf einem Raspberry Pi kann der Interrupt Pin des PCF8574 mit einem GPIO verbunden werden und &uml;ber die Interrupt Funktionen von <a href="#RPI_GPIO">RPI_GPIO</a> l&aml;sst sich dann ein get f&uuml;r den PCF8574 bei Pegel&aml;nderung ausl&oml;sen.<br>
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br>
	<a name="I2C_PCF8574Define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_PCF8574 &lt;I2C Address&gt;</code><br>
		Der Wert <code>&lt;I2C Address&gt;</code> ist ohne das Richtungsbit<br>
	</ul>

	<a name="I2C_PCF8574Set"></a>
	<b>Set</b>
	<ul>
		<code>set &lt;name&gt; &lt;port[,port[...]]&gt; &lt;value&gt;</code><br><br>
			<ul>
			<li><code>&lt;port&gt;</code> kann Port0 bis Port7 annehmen und <code>&lt;value&gt;</code> folgende Werte:<br>
				<ul>
				<code>
					off<br>
					on<br>
				</code>
				</ul>
			</li>
			</ul>
		<br>
		Beispiel:
		<ul>
			<code>set mod1 Port4 on</code><br>
			<code>set mod1 Port4,Port6 off</code><br>
			<code>set mod1 Port4,6 on</code><br>
		</ul><br>
	</ul>

	<a name="I2C_PCF8574Get"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt;</code>
		<br><br>
		Aktualisierung aller Werte
	</ul><br>

	<a name="I2C_PCF8574Attr"></a>
	<b>Attribute</b>
	<ul>
		<li>poll_interval<br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: -, g&uuml;ltige Werte: Dezimalzahl<br><br>
		</li>
		<li>InputPorts<br>
			Durch Leerzeichen getrennte Portnummern die als Inputs genutzt werden.<br>
			Ports in dieser Liste k&ouml;nnen nicht geschrieben werden.<br>
			Standard: no, g&uuml;ltige Werte: 0 1 2 .. 7<br><br>
		</li>
		<li>OnStartup<br>
			Durch Komma getrennte Output Ports und ihr gew&uuml;nschter Status nach dem Start.<br>
			Ohne dieses Attribut werden alle Ausg&auml;nge nach dem Start auf den letzten Status gesetzt.<br>
			Standard: -, g&uuml;ltige Werte: &lt;port&gt;=on|off|last wobei &lt;port&gt; = 0 - 7<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#ignore">ignore</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul>
	<br>
</ul>

=end html_DE

=cut