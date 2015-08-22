##############################################
package main;

use strict;
use warnings;

sub Lipo_Util_Initialize ();		# Initialisierung
sub entfHtmlTag ($);				# entfernt alle html tags aus einer Zeichenkette
sub xterTeil ($;$$);				# gibt x'ten Teil einer Zeichenkette zur�ck
sub TeilBisSuch ($$;$);				# l�st aus einer Zeichenkette Teil bis Suchkriterium heraus
sub addLog($$);						# Log-Abriss vermeiden
sub EigLesen ($$;$);				# lesen Wert aus Attribut 'Lipo_Eig', Rueckgabe Wert des Parameters oder 'not set' (wenn nicht gesetzt)
sub ParamS ($$$);					# setzt Parameter mit Wert in das Reading 'Lipo_Param'
sub ParamR ($$;$);					# lesen Wert aus Reading 'Lipo_Param', Rueckgabe Wert des Parameters oder 'not set' (wenn nicht gesetzt)
sub ParamD ($$);					# l�scht Parameter aus Reading 'Lipo_Param'
sub SecSinceReadingSet ($;$);		# R�ckgabe Sekunden seit leztem Schalten
sub MinutesSinceReadingSet ($;$);	# R�ckgabe Minuten seit leztem Schalten
sub SetOldEnough ($$;$);			# Wahr, wenn vorheriger Befehl mindestens angegebene Zeit (in Minuten) vorbei war, sonst falsch
sub DevExists ($);					# Testes, ob ein FHEM device mit entspr. Namen angelegt wurde


sub Lipo_Util_Initialize {
	return;
}

sub entfHtmlTag ($) {				# entfernt alle html tags aus einer Zeichenkette
	my $text	= $_[0];			# �bergabe Zeichenkette

	$text =~ s/<[^>]+?>//g;
	return $text
}

sub xterTeil ($;$$) {				# gibt x'ten Teil einer Zeichenkette zur�ck
	my $Zeichenkette	= $_[0];	# �bergabe Zeichenkette
	;
	my $TeilNummer		= $_[1];	# Optional: wievielter Teil zur�ckgegeben werden soll, Standard: 0
	my $Trennzeichen	= $_[2];	# Optional: Zeichen, bei welchem Zeichenkette geteilt werden soll, Standard: " +"

	if (!defined $TeilNummer) {		# wenn Trennzeichen nicht �bergeben wurde
		$TeilNummer = 0;			# Standard-Trennzeichen ist Leerzeichen
	}
	if (!defined $Trennzeichen) {	# wenn Trennzeichen nicht �bergeben wurde
		$Trennzeichen = " +";		# Standard-Trennzeichen ist ein oder mehrere Leerzeichen
	}

	my @Teil;
	@Teil	= split(/$Trennzeichen/,$Zeichenkette);
	return $Teil[$TeilNummer]
}

sub TeilBisSuch ($$;$) {			# l�st aus einer Zeichenkette Teil bis Suchkriterium heraus
	my $Zeichenkette	= $_[0];	# �bergabe Zeichenkette
	my $SuchString		= $_[1];	# �bergabe Suchstrin
	;
	my $StartAb			= $_[2];	# Optional: Startposition, ab welcher soll gesucht werden
	if (!defined $StartAb) {		# wenn Startposition nicht �bergeben wurde
		$StartAb = 0;
	}

	my $text	= "";
	$text	= substr($Zeichenkette,$StartAb,index($Zeichenkette,$SuchString)-$StartAb-1);
	return $text
}

#### Log-Abriss vermeiden
# called by
# define addLog notify addLog {addLog("ez_Aussensensor","state");addLog("ez_FHT","actuator");\
#               addLog("MunichWeather","humidity");addLog("MunichWeather","pressure");\
#               addLog("MunichWeather","temperature");addLog("MunichWeather","wind_chill");}
# define a_midnight1 at *23:59 trigger addLog
# define a_midnight2 at *00:01 trigger addLog
sub addLog($$) {	# Log-Abriss vermeiden
  my ($logdevice, $reading) = @_; # device and reading to be used
  my $logentry = ReadingsVal($logdevice,$reading,"addLog: invalid reading");
  if ($reading =~ m,state,i) {
    fhem "trigger $logdevice $logentry   << addLog";
  } else {
    fhem "trigger $logdevice $reading: $logentry   << addLog";
  }
}

sub EigLesen ($$;$) {			# lesen Wert aus Attribut 'Lipo_Eig', Rueckgabe Wert des Parameters oder 'not set' (wenn nicht gesetzt)
	my $ObjName		= $_[0];	# �bergabe Objektname
	my $ParaName	= $_[1];	# �bergabe Parameter-Name
	;
	my $StdWert		= $_[2];	# �bergabe R�ckgabewert, wenn nicht gesetzt

	my $Lipo_Eig ="";			# Inhalt vom Attribut 'Lipo_Eig'
	my @TeilString;				# Teilstrings
	my $ParaWert ="";			# Wert des gesuchten Parameters

	if (!defined $StdWert) {	# wenn Standard-R�ckgabewert nicht �bergeben wurde
		$StdWert = "not set";
	}

	$Lipo_Eig = AttrVal($ObjName,"Lipo_Eig","");		# Auslesen Wert von Attribut 'Parameter'
	if ($Lipo_Eig ne "") {								# wenn Objekt existiert und Attribut 'Lipo_Eig' gef�llt wurde
		if (index($Lipo_Eig, $ParaName) >= 0) {			# wenn Eigenschaft gesetzt wurde
			$ParaWert = substr($Lipo_Eig,index($Lipo_Eig, $ParaName));
#			@TeilString = split(/[=:; ]+/,$ParaWert);	# Trennzeichen '=:; ' ein oder mehrfach
#			@TeilString = split(/[=; ]+/,$ParaWert);	# Trennzeichen '=; ' ein oder mehrfach
			@TeilString = split(/[=;]+/,$ParaWert);		# Trennzeichen '=;' ein oder mehrfach
			if (defined $TeilString[1]) {
				$ParaWert = $TeilString[1];
			} else {
				$ParaWert = $StdWert;
			}
		} else {										# Parameter wurde nicht gesetzt
			$ParaWert = $StdWert;
		}
	} else {
		$ParaWert = $StdWert;
	}
	return $ParaWert;
}

sub ParamS ($$$) {				# setzt Parameter mit Wert in das Reading 'Lipo_Param'
	my $ObjName		= $_[0];	# �bergabe Objektname
	my $ParaName	= $_[1];	# �bergabe Parameter-Name
	my $ParaWert	= $_[2];	# �bergabe Parameter-Wert

	my $Lipo_Param;				# Inhalt vom Reading 'Lipo_Param'
	my $i;
	my @TeilString;				# Teilstrings

	if (ParamR($ObjName, $ParaName,"n/a") ne "n/a") {		# wenn zu setztender Parameter schon vorhanden ist
		ParamD($ObjName, $ParaName);						# loeschen des schon vorhandenen Parameters
	}
	$Lipo_Param = ReadingsVal($ObjName,"Lipo_Param","");	# Auslesen Wert von Reading 'Lipo_Param'
#	$ParaWert	=~ s/ %//g;		# Leerzeichen und % entfernen
	$Lipo_Param = $ParaName."=".$ParaWert.";".$Lipo_Param;
	$Lipo_Param	=~ s/;/;;/g;	# ; verdoppeln

	fhem("setreading ".$ObjName." Lipo_Param ".$Lipo_Param);	# Reading schreiben
	return $Lipo_Param;
}

sub ParamR ($$;$) {				# lesen Wert aus Reading 'Lipo_Param', Rueckgabe Wert des Parameters oder 'not set' (wenn nicht gesetzt)
	my $ObjName		= $_[0];	# �bergabe Objektname
	my $ParaName	= $_[1];	# �bergabe Parameter-Name
	;
	my $StdWert		= $_[2];	# �bergabe R�ckgabewert, wenn nicht gesetzt

	my $Lipo_Param ="";			# Inhalt vom Reading 'Lipo_Param'
	my @TeilString;				# Teilstrings
	my $ParaWert ="";			# Wert des gesuchten Parameters

	if (!defined $StdWert) {	# wenn Standard-R�ckgabewert nicht �bergeben wurde
		$StdWert = "not set";
	}

	$Lipo_Param = ReadingsVal($ObjName,"Lipo_Param","");	# Auslesen Inhalt von Reading 'Lipo_Param'
	if ($Lipo_Param ne "") {	# wenn Objekt existiert und Attribut 'Parameter' gef�llt wurde
		if (index($Lipo_Param, $ParaName) >= 0) {			# wenn Parameter gesetzt wurde
			$ParaWert = substr($Lipo_Param,index($Lipo_Param, $ParaName));	# String kuerzen
#			@TeilString = split(/[=:; ]+/,$ParaWert);		# Trennzeichen '=:; ' ein oder mehrfach
#			@TeilString = split(/[=; ]+/,$ParaWert);		# Trennzeichen '=; ' ein oder mehrfach
			@TeilString = split(/[=;]+/,$ParaWert);			# Trennzeichen '=;' ein oder mehrfach
			if (defined $TeilString[1]) {
				$ParaWert = $TeilString[1];
			} else {
				$ParaWert = $StdWert;
			}
		} else {				# Parameter wurde nicht gesetzt
			$ParaWert = $StdWert;
		}
	} else {					# Reading oder Objekt existiert nicht
		$ParaWert = $StdWert;
	}
	return $ParaWert;
}

sub ParamD ($$) {				# l�scht Parameter aus Reading 'Lipo_Param'
	my $ObjName		= $_[0];	# �bergabe Objektname
	my $ParaName	= $_[1];	# �bergabe Parameter-Name

	my $Lipo_Param;				# Inhalt vom Reading 'Lipo_Param'
	my $i;
	my @TeilString;				# Teilstrings

	$Lipo_Param = ReadingsVal($ObjName,"Lipo_Param","");		# Auslesen Wert von Reading 'Lipo_Param'
	if ($Lipo_Param ne "") {							# wenn Objekt existiert und Reading 'Lipo_Param' gef�llt wurde
		if (index($Lipo_Param, $ParaName) >= 0) {		# wenn Parameter gesetzt wurde
#			@TeilString = split(/[=:; ]+/,$Lipo_Param);	# Trennzeichen '=:; ' ein oder mehrfach
#			@TeilString = split(/[=; ]+/,$Lipo_Param);	# Trennzeichen '=; ' ein oder mehrfach
			@TeilString = split(/[=;]+/,$Lipo_Param);	# Trennzeichen '=;' ein oder mehrfach
			$Lipo_Param = "";	# Zeichenkette l�schen
			for($i=0; $i<=$#TeilString; $i=$i+2) {
				if ($TeilString[$i] ne $ParaName) {		# nicht der zu l�schende Parameter
					$Lipo_Param = $Lipo_Param.$TeilString[$i]."=".$TeilString[$i+1].";;";
				}
			}
			if ($Lipo_Param ne "") {
				fhem("setreading "   .$ObjName." Lipo_Param ".$Lipo_Param);	# Reading schreiben
			} else {
				fhem("deletereading ".$ObjName." Lipo_Param");				# Reading l�schen
			}
		} else {
			$Lipo_Param = $ParaName." nicht geloescht:".$Lipo_Param;
		}
	} else {
		$Lipo_Param = "fuer ".$ObjName." Reading 'Lipo_Param' nicht gesetzt";
	}
	return $Lipo_Param;
}

#sub SecLastSet ($;$) {			# R�ckgabe Sekunden seit leztem Schalten
sub SecSinceReadingSet ($;$) {	# R�ckgabe Sekunden seit leztem Schalten
	my $ObjName		= $_[0];	# �bergabe Objektname
	my $AttrName	= $_[1];	# �bergabe Attibutname f�r zeitvergleich (optional, Standard="state")
	
	my $time_last	= 0;		# Zeitpunkt letztes schalten
	my $time_diff	= 0;		# Zeitdifferenz zum letztes schalten

	if (!defined $AttrName ) {	# Attributname wurde nicht �bergeben
		$AttrName = "state";	# Standardattribut setzten
	}
	
	$time_last = ReadingsTimestamp($ObjName,$AttrName,-1);	# Auslesen Timestamp vom letztem Schalten
	if ($time_last eq -1) {		# Objekt oder Reading nicht gefunden
		Log 2,"SecSinceReadingSet f�r Objekt:".$ObjName." und Reading:".$AttrName.", Objekt oder Reading nicht gefunden";		# in FHEM Log schreiben
	} else {
		$time_last	= time() - time_str2num($time_last);	# Zeitdifferenz zum letzten Schalten in Sekunden
#		system("echo SetOldEnough fuer :".$ObjName.", time_last:".$time_last." >>./log/99_Lipo.txt");
	}
	return $time_last;			# R�ckgabe Sekunden seit leztem Schalten
}

#sub MinLastSet ($;$) {				# R�ckgabe Minuten seit leztem Schalten
sub MinutesSinceReadingSet ($;$) {	# R�ckgabe Minuten seit leztem Schalten
	my $ObjName		= $_[0];		# �bergabe Objektname
	my $AttrName	= $_[1];		# �bergabe Attibutname f�r zeitvergleich (optional, Standard="state")
	
	my $time_diff	= 0;			# Zeitdifferenz zum letztes schalten

	if (!defined $AttrName ) {		# Attributname wurde nicht �bergeben
		$AttrName = "state";		# Standardattribut setzten
	}
	$time_diff = SecSinceReadingSet($ObjName,$AttrName);	# R�ckgabe Sekunden seit leztem Schalten
	if ($time_diff ne -1) {				# Objekt und Reading gefunden
		$time_diff =int($time_diff/60);	# Umrechnung in Minuten
	}
	return $time_diff;				# R�ckgabe Minuten seit leztem Schalten
}

sub SetOldEnough ($$;$) {			# Wahr, wenn vorheriger Befehl mindestens angegebene Zeit (in Minuten) vorbei war, sonst falsch
	my $ObjName		= $_[0];		# �bergabe Objektname
	my $TimeMinDiff	= $_[1];		# �bergabe Mindest-Zeitdifferenz in Minuten
	my $AttrName	= $_[2];		# �bergabe Attibutname f�r zeitvergleich (optional, Standsd="state")
	
	my $time_last	= 0;			# Zeitpunkt letztes schalten
	my $time_diff	= 0;			# Zeitdifferenz zum letztes schalten

	if (!defined $AttrName ) {		# Attributname wurde nicht �bergeben
		$AttrName = "state";		# Standardattribut setzten
	}
	$time_last = ReadingsTimestamp($ObjName,"state",0);	# Auslesen Timestamp vom letztem Schalten
#	system("echo SetOldEnough >>./log/99_Lipo.txt");
#	system("echo SetOldEnough fuer :".$ObjName.", time_last:".$time_last." >>./log/99_Lipo.txt");

	$time_last	= MinutesSinceReadingSet($ObjName,$AttrName);	# Zeitdifferenz zum letzten Schalten in Minuten
#	system("echo SetOldEnough fuer :".$ObjName.", time_last:".$time_last." >>./log/99_Lipo.txt");

	return ($TimeMinDiff < $time_last); # falsch, wenn schalten nicht lange genug zur�ck lag
}

sub DevExists ($) {			# Testes, ob ein FHEM device mit entspr. Namen angelegt wurde
	my $DevName = $_[0];	# �bergabe Fenstername

	if (fhem("list ".$DevName) eq  "No device named ".$DevName." found") {	# wenn Device nicht existiert
		return 0;			# nein
	} else {
		return 1;			# ja
	}
}

1;
