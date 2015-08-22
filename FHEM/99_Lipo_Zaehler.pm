##############################################
package main;

use strict;
use warnings;

sub Lipo_Zaehler_Initialize ();	# Initialisierung
sub ZaehlerSet ($$;$);			# aktualisieren Dummy-Z�hler-Objekt


sub Lipo_Zaehler_Initialize {
	return;
}

sub ZaehlerSet ($$;$) {				# aktualisieren Dummy-Z�hler-Objekt
	my $ObjNameZaehler	= $_[0];	# �bergabe Objektname f�r Z�hler Device
	my $ObjNameHT		= $_[1];	# �bergabe Objektname f�r Dummy-Wert Device HT
	my $ObjNameNT		= $_[2];	# �bergabe Objektname f�r Dummy-Wert Device NT
	
	my $ObjNameDummy;
	my $ZaehlerStand;				# Stand des installieren Strom- oder Gas-Z�hlers
	my $StandFS20;					# Stand des FS20 Ger�tes

	
	my ($sec,$min,$hour,$heutetag,$heutemonat,$heutejahr,$wday,$yday,$isdst) = localtime(time);

	if (!defined $ObjNameNT) {		# wenn 3. Parameter f�r Device NT nicht �bergeben wurde
		$ObjNameNT = "";
	}

	$heutemonat++;
	$heutejahr+=1900;
	$wday--;
	if ($wday eq '-1'){$wday=6;}
	$hour="0$hour" if (length($hour) == 1);
	$min="0$min" if (length($min) == 1);
	$sec="0$sec" if (length($sec) == 1);
	
	if ($ObjNameNT eq "") {			# wenn kein NT Dummy-Device-Name �bergeben wurde
		$ObjNameNT = $ObjNameHT;
	}
	
	if ($hour>6 and $hour<21) {		# Tag-Tarif
		$ObjNameDummy = $ObjNameHT;
	} else {						# Nacht-Tarif
		$ObjNameDummy = $ObjNameNT;
	}
	
	$StandFS20 = ReadingsVal($ObjNameZaehler,"current","");		# Auslesen Wert von Attribut 'current'
	$StandFS20 = $StandFS20 / 12;								# /12 da nur 5' Wert und nicht auf Stunde hochgerechnet
	$StandFS20 = sprintf "%.3f", $StandFS20;					# auf 3 Nachkommastellen runden

	$ZaehlerStand = Value($ObjNameDummy);
	
	if ($StandFS20>0) {											# nur wenn auch was zu addieren ist, sonst unn�tiger Log-Eintrag durch SET Kommando
		$ZaehlerStand = $ZaehlerStand + $StandFS20;
		fhem("set ".$ObjNameDummy." ".$ZaehlerStand);			# aktuelle Zeit merken
	}
	fhem("attr ".$ObjNameDummy." lastStateTime ".$heutetag.".".$heutemonat.".".$heutejahr." ".$hour.":".$min.":".$sec);	# aktuelle Zeit merken
	fhem("attr ".$ObjNameDummy." Parameter 5min=".$StandFS20);	# wieviel kW wurden addiert
	
	return "Zaehler:".$ObjNameDummy.", 5min:".$StandFS20.", Summe:".$ZaehlerStand;
}

1;
