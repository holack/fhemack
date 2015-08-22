##############################################
package main;

use strict;
use warnings;

sub Lipo_FileLog_Initialize ();						# Initialisierung
sub Statistik_Gestern_Sum ($$$;$$$$$);				# Rückgabe einiger Werte aus Statistik-FLog für Gestern aufbereitet für 'Sum'
sub Statistik_Gestern_Max ($$$;$$$$$);				# Rückgabe einiger Werte aus Statistik-FLog für Gestern aufbereitet für 'Max'
sub Statistik_Gestern_Last ($$$;$$$$$);				# Rückgabe einiger Werte aus Statistik-FLog für Gestern aufbereitet für 'Last'
sub Statistik_Gestern_Avr ($$$;$$$$$);				# Rückgabe einer Zeile aus Statistik-FLog für Gestern
sub Statistik_Gestern_Write ($$$);					# Schreiben einer Zeile aus einer Statistik-Datei in eine ander Statistik-Datei (so wie sie ist)
sub StatistikZeile_Datum ($$$);						# Rückgabe einer Zeile aus Statistik-FLog für Gestern
sub StatistikZeile_Gestern ($$);					# Rückgabe einer Zeile aus Statistik-FLog für Gestern
sub LogFile_Gestern_Sum ($$$$;$$$);					# Rückgabe Summe aus Log-File für Gestern
sub LogFile_Gestern_Avr ($$$$;$$$);					# Rückgabe Durchschnitt aus Log-File für Gestern
sub TSuche_VonBis ($$;$);							# Rückgabe Text
sub LogFile_Statistik_Gestern ($$$$;$$$);			# Rückgabe Statistik (min, max, avg,...) aus Log-File für Gestern
sub LogFile_Statistik_FileOut_Datum ($$$$$$;$$$);	# Ausgabe Statistik (min, max, avg,...) aus Log-File für bestimmtes Datum in Datei schreiben
sub LogFile_Statistik_FileOut_Gestern ($$$$$;$$$);	# Ausgabe Statistik (min, max, avg,...) aus Log-File für Gestern in Datei schreiben
sub LogFile_Statistik_Datum ($$$$$;$$$);			# Rückgabe Statistik (min, max, avg,...) aus Log-File für best. Datum
sub LogFile_Statistik ($$$$$$;$$$);					# Rückgabe Statistik (min, max, avg,...) aus Log-File für best Zeitraum
sub File_Statistik_vonbis_Day ($$$$$$$;$$$);		# Rückgabe Statistik (min, max, avg,...) aus File für jeden Tag von-bis
sub File_Statistik_Day ($$$$$;$$$);					# Rückgabe Statistik (min, max, avg,...) aus File für einen Tag
sub File_Statistik ($$$$$$;$$$);					# Rückgabe Statistik (min, max, avg,...) aus File für best Zeitraum
sub FileLogName_Datum ($$);							# Rückgabe FileName von einem FileLog für bestimmtes Datum (Beachtung neuer Filename bei z.B. Monatswechsel)
sub FileLogName_gestern ($);						# Rückgabe FileName von einem FileLog für gestern (Beachtung neuer Filename bei z.B. Monatswechsel)
sub FileLog_FileName ($);							# Rückgabe aktuellen Filenamen von FileLog
sub Datum1Tag ($);									# Rückgabe Datum + 1 tag


sub Lipo_FileLog_Initialize {
	return;
}

sub Statistik_Gestern_Sum ($$$;$$$$$) {	# Rückgabe einiger Werte aus Statistik-FLog für Gestern aufbereitet für 'Sum'
	my $Comment			= $_[0];		# Übergabe Beschreibung
	my $FileLogName		= $_[1];		# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $ZeilenFilter	= $_[2];		# Übergabe Filter, nur passende Zeilen werden (von Gestern) betrachtet
	;
	my $Bedingung		= $_[3];		# Übergabe Bedingung für Textformatierung
	my $FormatJaStart	= $_[4];		# Übergabe Format, welches bei erfüllter Bedingung vor den Text gesetzt wird	(Standard: rot & fett)
	my $FormatJaEnde	= $_[5];		# Übergabe Format, welches bei erfüllter Bedingung nach dem Text angehängt wird
	my $FormatNeinStart	= $_[6];		# Übergabe Format, welches bei nicht erfüllter Bedingung vor den Text gesetzt wird
	my $FormatNeinEnde	= $_[7];		# Übergabe Format, welches bei nicht erfüllter Bedingung nach dem Text angehängt wird

	if (!defined $Bedingung) {			# wenn keine Bedingung übergeben wurde
		$Bedingung	= "";
	}

	my $Zeile 		= "";			# Zeile aus Datei
	$Zeile = StatistikZeile_Gestern($FileLogName, $ZeilenFilter); # suchen Zeile von gestern, welche Filter entspricht
#	print "Zeile:".$Zeile."\n";

	my $Min			= "";		# Wert für Minimum
	my $Max			= "";		# Wert für Maximum
	my $Sum			= "";		# Wert für Summe
	my $Avr			= "";		# Wert für Durchschnitt
	my $Anz			= "";		# Wert für Anzahl-Werte
	$Min	= TSuche_VonBis($Zeile,"Min:","Max:");		# Wert für 'Min' heraussuchen
	$Max	= TSuche_VonBis($Zeile,"Max:","Last:");		# Wert für 'Max' heraussuchen
	$Sum	= TSuche_VonBis($Zeile,"Sum:","Avr:");		# Wert für 'Summe' heraussuchen
	$Avr	= TSuche_VonBis($Zeile,"Avr:","Anz:");		# Wert für 'Avr' heraussuchen
	$Anz	= TSuche_VonBis($Zeile,"Anz:");				# Werteanzahl herraussuchen

	if ($Anz eq "") {			# wenn genau eine Zeile ausgewertet wurde (Datum +Filter)
		return $Zeile;
	}

#	print "Min       :".$Min."\n";
#	print "Max       :".$Max."\n";
#	print "Summe     :".$Sum."\n";
#	print "Mittelwert:".$Avr."\n";
#	print "WerteAnz  :".$Anz."\n";

	my $Text	= "";			# Textfeld zur Speicherung der Rückgabe-Zeichenkette
	if ($Bedingung ne "") {		# wenn Bedingung übergeben wurde
		$Zeile	= $Sum;				# Summe merken (inkl. Einheit)
		$Text	= $Sum+0;			# Summe merken (inkl. Einheit)
		$Sum	= FormatWenn($Text, $Bedingung, $FormatJaStart, $FormatJaEnde, $FormatNeinStart, $FormatNeinEnde);
		$Sum	=~ s/$Text/$Zeile/;	# Einheit wieder einbauen
	} else {
		$Sum	= "<b>".$Sum."</b>";
	}
	$Text	= $Comment." ".$Sum ." (Werte: ".$Anz.")";						# Rückgabe-Text für Summe zusammenbauen
#	$Text	= $Comment." ".$Avr ." [".$Min."|+".$Max."] (Werte: ".$Anz.")";	# Rückgabe-Text für Durchschnitt zusammenbauen
#	$Text	= $Comment." ".$Max ." (Werte: ".$Anz.")";						# Rückgabe-Text für Maximalwert zusammenbauen
#	$Text	= $Comment." ".$Last." (Werte: ".$Anz.")";						# Rückgabe-Text für letzten Wert zusammenbauen
	
	return $Text;
}

sub Statistik_Gestern_Max ($$$;$$$$$) {	# Rückgabe einiger Werte aus Statistik-FLog für Gestern aufbereitet für 'Max'
	my $Comment			= $_[0];		# Übergabe Beschreibung
	my $FileLogName		= $_[1];		# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $ZeilenFilter	= $_[2];		# Übergabe Filter, nur passende Zeilen werden (von Gestern) betrachtet
	;
	my $Bedingung		= $_[3];		# Übergabe Bedingung für Textformatierung
	my $FormatJaStart	= $_[4];		# Übergabe Format, welches bei erfüllter Bedingung vor den Text gesetzt wird	(Standard: rot & fett)
	my $FormatJaEnde	= $_[5];		# Übergabe Format, welches bei erfüllter Bedingung nach dem Text angehängt wird
	my $FormatNeinStart	= $_[6];		# Übergabe Format, welches bei nicht erfüllter Bedingung vor den Text gesetzt wird
	my $FormatNeinEnde	= $_[7];		# Übergabe Format, welches bei nicht erfüllter Bedingung nach dem Text angehängt wird

	if (!defined $Bedingung) {			# wenn keine Bedingung übergeben wurde
		$Bedingung	= "";
	}

	my $Zeile 		= "";			# Zeile aus Datei
	$Zeile = StatistikZeile_Gestern($FileLogName, $ZeilenFilter); # suchen Zeile von gestern, welche Filter entspricht
#	print "Zeile:".$Zeile."\n";

	my $Min			= "";		# Wert für Minimum
	my $Max			= "";		# Wert für Maximum
	my $Sum			= "";		# Wert für Summe
	my $Avr			= "";		# Wert für Durchschnitt
	my $Anz			= "";		# Wert für Anzahl-Werte
	$Min	= TSuche_VonBis($Zeile,"Min:","Max:");		# Wert für 'Min' heraussuchen
	$Max	= TSuche_VonBis($Zeile,"Max:","Last:");		# Wert für 'Max' heraussuchen
	$Sum	= TSuche_VonBis($Zeile,"Sum:","Avr:");		# Wert für 'Summe' heraussuchen
	$Avr	= TSuche_VonBis($Zeile,"Avr:","Anz:");		# Wert für 'Avr' heraussuchen
	$Anz	= TSuche_VonBis($Zeile,"Anz:");				# Werteanzahl herraussuchen

	if ($Anz eq "") {			# wenn genau eine Zeile ausgewertet wurde (Datum +Filter)
		return $Zeile;
	}

#	print "Min       :".$Min."\n";
#	print "Max       :".$Max."\n";
#	print "Summe     :".$Sum."\n";
#	print "Mittelwert:".$Avr."\n";
#	print "WerteAnz  :".$Anz."\n";

	my $Text	= "";			# Textfeld zur Speicherung der Rückgabe-Zeichenkette
	if ($Bedingung ne "") {		# wenn Bedingung übergeben wurde
		$Zeile	= $Max;				# Summe merken (inkl. Einheit)
		$Text	= $Max+0;			# Summe merken (inkl. Einheit)
		$Max	= FormatWenn($Text, $Bedingung, $FormatJaStart, $FormatJaEnde, $FormatNeinStart, $FormatNeinEnde);
		$Max	=~ s/$Text/$Zeile/;	# Einheit wieder einbauen
	} else {
		$Max	= "<b>".$Max."</b>";
	}

#	$Text	= $Comment." ".$Sum ." (Werte: ".$Anz.")";						# Rückgabe-Text für Summe zusammenbauen
#	$Text	= $Comment." ".$Avr ." [".$Min."|+".$Max."] (Werte: ".$Anz.")";	# Rückgabe-Text für Durchschnitt zusammenbauen
	$Text	= $Comment." ".$Max ." (Werte: ".$Anz.")";						# Rückgabe-Text für Maximalwert zusammenbauen
#	$Text	= $Comment." ".$Last." (Werte: ".$Anz.")";						# Rückgabe-Text für letzten Wert zusammenbauen
	
	return $Text;
}

sub Statistik_Gestern_Last ($$$;$$$$$) {	# Rückgabe einiger Werte aus Statistik-FLog für Gestern aufbereitet für 'Last'
	my $Comment			= $_[0];		# Übergabe Beschreibung
	my $FileLogName		= $_[1];		# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $ZeilenFilter	= $_[2];		# Übergabe Filter, nur passende Zeilen werden (von Gestern) betrachtet
	;
	my $Bedingung		= $_[3];		# Übergabe Bedingung für Textformatierung
	my $FormatJaStart	= $_[4];		# Übergabe Format, welches bei erfüllter Bedingung vor den Text gesetzt wird	(Standard: rot & fett)
	my $FormatJaEnde	= $_[5];		# Übergabe Format, welches bei erfüllter Bedingung nach dem Text angehängt wird
	my $FormatNeinStart	= $_[6];		# Übergabe Format, welches bei nicht erfüllter Bedingung vor den Text gesetzt wird
	my $FormatNeinEnde	= $_[7];		# Übergabe Format, welches bei nicht erfüllter Bedingung nach dem Text angehängt wird

	if (!defined $Bedingung) {			# wenn keine Bedingung übergeben wurde
		$Bedingung	= "";
	}

	my $Zeile 		= "";			# Zeile aus Datei
	$Zeile = StatistikZeile_Gestern($FileLogName, $ZeilenFilter); # suchen Zeile von gestern, welche Filter entspricht
#	print "Zeile:".$Zeile."\n";

	my $Min			= "";		# Wert für Minimum
	my $Max			= "";		# Wert für Maximum
	my $Last		= "";		# Wert für Maximum
	my $Sum			= "";		# Wert für Summe
	my $Avr			= "";		# Wert für Durchschnitt
	my $Anz			= "";		# Wert für Anzahl-Werte
	$Min	= TSuche_VonBis($Zeile,"Min:" ,"Max:");		# Wert für 'Min'   heraussuchen
	$Max	= TSuche_VonBis($Zeile,"Max:" ,"Last:");	# Wert für 'Max'   heraussuchen
	$Last	= TSuche_VonBis($Zeile,"Last:","Sum:");		# Wert für 'Last'  heraussuchen
	$Sum	= TSuche_VonBis($Zeile,"Sum:" ,"Avr:");		# Wert für 'Summe' heraussuchen
	$Avr	= TSuche_VonBis($Zeile,"Avr:" ,"Anz:");		# Wert für 'Avr'   heraussuchen
	$Anz	= TSuche_VonBis($Zeile,"Anz:");				# Werteanzahl      herraussuchen

	if ($Anz eq "") {			# wenn genau eine Zeile ausgewertet wurde (Datum +Filter)
		return $Zeile;
	}

#	print "Min       :".$Min."\n";
#	print "Max       :".$Max."\n";
#	print "Summe     :".$Sum."\n";
#	print "Mittelwert:".$Avr."\n";
#	print "WerteAnz  :".$Anz."\n";

	my $Text	= "";			# Textfeld zur Speicherung der Rückgabe-Zeichenkette
	if ($Bedingung ne "") {		# wenn Bedingung übergeben wurde
		$Zeile	= $Last;			# Summe merken (inkl. Einheit)
		$Text	= $Last+0;			# Summe merken (inkl. Einheit)
		$Last	= FormatWenn($Text, $Bedingung, $FormatJaStart, $FormatJaEnde, $FormatNeinStart, $FormatNeinEnde);
		$Last	=~ s/$Text/$Zeile/;	# Einheit wieder einbauen
	} else {
		$Last	= "<b>".$Last."</b>";
	}

#	$Text	= $Comment." ".$Sum ." (Werte: ".$Anz.")";						# Rückgabe-Text für Summe        zusammenbauen
#	$Text	= $Comment." ".$Avr ." [".$Min."|+".$Max."] (Werte: ".$Anz.")";	# Rückgabe-Text für Durchschnitt zusammenbauen
#	$Text	= $Comment." ".$Max ." (Werte: ".$Anz.")";						# Rückgabe-Text für Maximalwert  zusammenbauen
	$Text	= $Comment." ".$Last." (Werte: ".$Anz.")";						# Rückgabe-Text für letzten Wert zusammenbauen
	
	return $Text;
}

sub Statistik_Gestern_Avr ($$$;$$$$$) {	# Rückgabe einer Zeile aus Statistik-FLog für Gestern
	my $Comment			= $_[0];		# Übergabe Beschreibung
	my $FileLogName		= $_[1];		# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $ZeilenFilter	= $_[2];		# Übergabe Filter, nur passende Zeilen werden (von Gestern) betrachtet
	;
	my $Bedingung		= $_[3];		# Übergabe Bedingung für Textformatierung
	my $FormatJaStart	= $_[4];		# Übergabe Format, welches bei erfüllter Bedingung vor den Text gesetzt wird	(Standard: rot & fett)
	my $FormatJaEnde	= $_[5];		# Übergabe Format, welches bei erfüllter Bedingung nach dem Text angehängt wird
	my $FormatNeinStart	= $_[6];		# Übergabe Format, welches bei nicht erfüllter Bedingung vor den Text gesetzt wird
	my $FormatNeinEnde	= $_[7];		# Übergabe Format, welches bei nicht erfüllter Bedingung nach dem Text angehängt wird

	if (!defined $Bedingung) {			# wenn keine Bedingung übergeben wurde
		$Bedingung	= "";
	}

	my $Zeile 		= "";		# Zeile aus Datei
	$Zeile = StatistikZeile_Gestern($FileLogName, $ZeilenFilter); # suchen Zeile von gestern, welche Filter entspricht
#	print "Zeile:".$Zeile."\n";

	my $Min			= "";		# Wert für Minimum
	my $Max			= "";		# Wert für Maximum
	my $Sum			= "";		# Wert für Summe
	my $Avr			= "";		# Wert für Durchschnitt
	my $Anz			= "";		# Wert für Anzahl-Werte
	$Min	= TSuche_VonBis($Zeile,"Min:","Max:");		# Wert für 'Min' heraussuchen
	$Max	= TSuche_VonBis($Zeile,"Max:","Last:");		# Wert für 'Max' heraussuchen
	$Sum	= TSuche_VonBis($Zeile,"Sum:","Avr:");		# Wert für 'Summe' heraussuchen
	$Avr	= TSuche_VonBis($Zeile,"Avr:","Anz:");		# Wert für 'Avr' heraussuchen
	$Anz	= TSuche_VonBis($Zeile,"Anz:");				# Werteanzahl herraussuchen

	if ($Anz eq "") {			# wenn genau eine Zeile ausgewertet wurde (Datum +Filter)
		return $Zeile;
	}

#	print "Min       :".$Min."\n";
#	print "Max       :".$Max."\n";
#	print "Summe     :".$Sum."\n";
#	print "Mittelwert:".$Avr."\n";
#	print "WerteAnz  :".$Anz."\n";

	my $Text	= "";			# Textfeld zur Speicherung der Rückgabe-Zeichenkette
	if ($Bedingung ne "") {		# wenn Bedingung übergeben wurde
		$Zeile	= $Avr;				# Summe merken (inkl. Einheit)
		$Text	= $Avr+0;			# Summe merken (inkl. Einheit)
		$Avr	= FormatWenn($Text, $Bedingung, $FormatJaStart, $FormatJaEnde, $FormatNeinStart, $FormatNeinEnde);
		$Avr	=~ s/$Text/$Zeile/;	# Einheit wieder einbauen
	} else {
		$Avr	= "<b>".$Avr."</b>";
	}

#	$Text	= $Comment." ".$Sum ." (Werte: ".$Anz.")";						# Rückgabe-Text für Summe zusammenbauen
	$Text	= $Comment." ".$Avr ." [".$Min."|+".$Max."] (Werte: ".$Anz.")";	# Rückgabe-Text für Durchschnitt zusammenbauen
#	$Text	= $Comment." ".$Max ." (Werte: ".$Anz.")";						# Rückgabe-Text für Maximalwert zusammenbauen
#	$Text	= $Comment." ".$Last." (Werte: ".$Anz.")";						# Rückgabe-Text für letzten Wert zusammenbauen

	return $Text;
}

sub Statistik_Gestern_Write ($$$) {	# Schreiben einer Zeile aus einer Statistik-Datei in eine ander Statistik-Datei (so wie sie ist)
	my $FileLogName		= $_[0];	# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $ZeilenFilter	= $_[1];	# Übergabe Filter, nur passende Zeilen werden (von Gestern) betrachtet
	my $FileLogNameOut	= $_[2];	# Übergabe Name Filelog für AusgabeDatei

	my $Zeile 		= "keine Zeile gefunden";				# Zeile aus Datei
	$Zeile = StatistikZeile_Gestern($FileLogName, $ZeilenFilter); # suchen Zeile von gestern, welche Filter entspricht
#	print "Zeile:".$Zeile."\n";

	my $FileNameOut	= "";									# Filename Ausgabe-Datei
	$FileNameOut	= FileLogName_gestern($FileLogNameOut);	# Ermitteln LogFileName vom FileLog (so wie es gestern hieß)
	if ($FileNameOut eq "") {
		return "Datei von LogFile:".$FileLogNameOut." nicht gefunden";
	}
	
	my $FileHandle	= "";									# File-Handle Ausgabe-Datei
	$FileHandle = open SCHREIBEN ,">>".$FileNameOut;		# Datei zum Schreiben (append) öffnen
	if (not defined($FileHandle)) {
		return "Fehler beim Schreiben in Datei:".$FileNameOut;
	}
	print SCHREIBEN  $Zeile;	# Rückgabe in Ausgabe-Datei schreiben
	close(SCHREIBEN);				# Datei schliessen
	fhem("set ".$FileLogNameOut." reopen");		# Aktualisierung FileLog für Ausgaben

	return $Zeile;
}

sub StatistikZeile_Datum ($$$) {	# Rückgabe einer Zeile aus Statistik-FLog für Gestern
	my $Datum			= $_[0];	# Übergabe Datum YYY-MM-DD
	my $FileLogName		= $_[1];	# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $ZeilenFilter	= $_[2];	# Übergabe Filter, nur passende Zeilen werden (von Gestern) betrachtet

	my $FileName = "";			# Filename
	$FileName = FileLogName_Datum($Datum,$FileLogName);	# Ermitteln LogFileName vom FileLog (so wie es zum Datum hieß)
	if ($FileName eq "") {
		return "Datei von LogFile:".$FileLogName." nicht gefunden";
	}

	my $DatumVon= "";					# Datum von (ab dem FileLog ausgewertet wird)
	my $DatumBis= "";					# Datum bis (bis dahin wird FileLog ausgewertet)
	$DatumVon	= $Datum;
	$DatumBis	= Datum1Tag($Datum);
#	print "StatistikZeile_Datum: von:".$DatumVon.", bis:".$DatumBis."\n";
	
	my $FileHandle	= "";			# File handle
	open FILE,"<".$FileName;		# Datei zum Lesen öffnen
	if (not defined($FileHandle)) {
		return "Fehler beim Öffnen der Datei:".$FileName;
	}

	my $Text	= "";			# Textfeld zur Speicherung der Rückgabe-Zeichenkette
	my $ZeilenAnz	= 0;		# Anzahl ausgewerteter Zeilen (Datum + Filter)
	my $Zeile 		= "";		# Zeile aus Datei
	my @ZeilenTeile	= "";		# Bestandteile einer Zeile
	my $ZDatum		= "";		# Datumsfeld aus Zeile

	$ZeilenFilter	= $ZeilenFilter."\\b";		# (mit Wortgrenze, also dahint leer oder Tab)
	while(defined(my $Zeile = <FILE>)) {
		@ZeilenTeile = split(/[\s,\t]+/, $Zeile);	# Zeile zerlegen, Trennzeiche: Leer oder Tab (beliebig viele)
		$ZDatum= $ZeilenTeile[0];					# 1.Teil aus Zeile -> Datum
#		print "Datumsfeld:".$ZDatum."\n";
		$ZDatum= date2num($ZDatum);					# Datum in Zahl umwandeln
#		print "Datumszahl:".$ZDatum."\n";
		if ($DatumVon <= $ZDatum and $ZDatum <= $DatumBis) {	# Datum liegt im Zeitfenster
			if ($Zeile =~ /$ZeilenFilter/) {				# Zeile entspricht Filter (mit Wortgrenze, also dahint leer oder Tab)
				$ZeilenAnz = $ZeilenAnz +1;
#				print $ZeilenAnz.".Zeile:".$Zeile."\n";
				$Text	= $Zeile;							# Speicherung der Rückgabe-Zeichenkette
			}
		}
	}
	close(FILE);				# Datei schliessen

	if ($ZeilenAnz == 0) {		# wenn genau eine Zeile ausgewertet wurde (Datum +Filter)
		return "keine Zeile gefunden, Datum:".DatumHeute(-1).", Filter:".$ZeilenFilter.", Datei:".$FileName;
	}
	if ($ZeilenAnz > 1) {		# wenn zu viele Zeilen ausgewertet wurden (Datum +Filter)
		return $ZeilenAnz." Zeilen gefunden (nur eine erwartet), Datum:".DatumHeute(-1).", Filter:".$ZeilenFilter.", Datei:".$FileName;
	}

	return $Text;
}

sub StatistikZeile_Gestern ($$) {	# Rückgabe einer Zeile aus Statistik-FLog für Gestern
	my $FileLogName		= $_[0];	# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $ZeilenFilter	= $_[1];	# Übergabe Filter, nur passende Zeilen werden (von Gestern) betrachtet

	my $FileName = "";			# Filename
	$FileName = FileLogName_gestern($FileLogName);	# Ermitteln LogFileName vom FileLog (so wie es gestern hieß)
	if ($FileName eq "") {
		return "Datei von LogFile:".$FileLogName." nicht gefunden";
	}

	my $ZeitVon	= "";				# Zeit von (ab dem FileLog ausgewertet wird)
	my $ZeitBis	= "";				# Zeit bis (bis dahin wird FileLog ausgewertet)
	$ZeitVon = DatumHeute(-1);		# YYYY-MM-DD
	$ZeitBis = DatumHeute(0);		# YYYY-MM-DD
	$ZeitVon= date2num($ZeitVon);	# Datum in Zahl umwandeln
	$ZeitBis= date2num($ZeitBis);	# Datum in Zahl umwandeln
	
	my $FileHandle	= "";			# File handle
	open FILE,"<".$FileName;		# Datei zum Lesen öffnen
	if (not defined($FileHandle)) {
		return "Fehler beim Öffnen der Datei:".$FileName;
	}

	my $Text	= "";			# Textfeld zur Speicherung der Rückgabe-Zeichenkette
	my $ZeilenAnz	= 0;		# Anzahl ausgewerteter Zeilen (Datum + Filter)
	my $Zeile 		= "";		# Zeile aus Datei
	my @ZeilenTeile	= "";		# Bestandteile einer Zeile
	my $ZDatum		= "";		# Datumsfeld aus Zeile

	$ZeilenFilter	= $ZeilenFilter."\\b";		# (mit Wortgrenze, also dahint leer oder Tab)
	while(defined(my $Zeile = <FILE>)) {
		@ZeilenTeile = split(/[\s,\t]+/, $Zeile);	# Zeile zerlegen, Trennzeiche: Leer oder Tab (beliebig viele)
		$ZDatum= $ZeilenTeile[0];					# 1.Teil aus Zeile -> Datum
#		print "Datumsfeld:".$ZDatum."\n";
		$ZDatum= date2num($ZDatum);					# Datum in Zahl umwandeln
#		print "Datumszahl:".$ZDatum."\n";
		if ($ZeitVon <= $ZDatum and $ZDatum <= $ZeitBis) {	# Datum liegt im Zeitfenster
			if ($Zeile =~ /$ZeilenFilter/) {				# Zeile entspricht Filter (mit Wortgrenze, also dahint leer oder Tab)
				$ZeilenAnz = $ZeilenAnz +1;
#				print $ZeilenAnz.".Zeile:".$Zeile."\n";
				$Text	= $Zeile;							# Speicherung der Rückgabe-Zeichenkette
			}
		}
	}
	close(FILE);				# Datei schliessen

	if ($ZeilenAnz == 0) {		# wenn genau eine Zeile ausgewertet wurde (Datum +Filter)
		return "keine Zeile gefunden, Datum:".DatumHeute(-1).", Filter:".$ZeilenFilter.", Datei:".$FileName;
	}
	if ($ZeilenAnz > 1) {		# wenn zu viele Zeilen ausgewertet wurden (Datum +Filter)
		return $ZeilenAnz." Zeilen gefunden (nur eine erwartet), Datum:".DatumHeute(-1).", Filter:".$ZeilenFilter.", Datei:".$FileName;
	}

	return $Text;
}

sub LogFile_Gestern_Sum ($$$$;$$$) {	# Rückgabe Summe aus Log-File für Gestern
	my $Comment	=		$_[0];	# Übergabe Beschreibung
	my $FileLogName	=	$_[1];	# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $ZeilenFilter =	$_[2];	# Übergabe Filter, nur passende Zeilen werden (im Zeitfenster) betrachtet
	my $WertFNr	=		$_[3];	# Übergabe Feldnummer, in welchem der Wert steht
	;
	my $Format	=		$_[4];	# Übergabe Format für Werte
	my $Unit	=		$_[5];	# Übergabe Einheit
	my $KFaktor	=		$_[6];	# Übergabe Korrektur-Faktor

	my $Text	= "";			# Textfeld zur Speicherung der Rückgabe-Zeichenkette
	$Text		= LogFile_Statistik_Gestern($Comment,$FileLogName,$ZeilenFilter,$WertFNr,$Format,$Unit,$KFaktor);

	my $Summe	= "";	# Summe
	my $WAnz	= "";	# Anzahl Werte
	$Summe	= TSuche_VonBis($Text,"Sum:","Avr:");		# Wert für 'Summe' heraussuchen
	$WAnz	= TSuche_VonBis($Text,"Anz:");				# Werteanzahl herraussuchen
	$Text	= TSuche_VonBis($Text,"","Min:");			# Beginn (Datum+Kommentar) herraussuchen
	$Text	= $Text." <b>".$Summe."</b> (Werte: ".$WAnz.")";	# Rückgabe-Text zusammenbauen
	
	return $Text;
}

sub LogFile_Gestern_Avr ($$$$;$$$) {	# Rückgabe Durchschnitt aus Log-File für Gestern
	my $Comment	=		$_[0];	# Übergabe Beschreibung
	my $FileLogName	=	$_[1];	# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $ZeilenFilter =	$_[2];	# Übergabe Filter, nur passende Zeilen werden (im Zeitfenster) beatrachtet
	my $WertFNr	=		$_[3];	# Übergabe Feldnummer, in welchem der Wert steht
	;
	my $Format	=		$_[4];	# Übergabe Format für Werte
	my $Unit	=		$_[5];	# Übergabe Einheit
	my $KFaktor	=		$_[6];	# Übergabe Korrektur-Faktor

	my $Text	= "";			# Textfeld zur Speicherung der Rückgabe-Zeichenkette
	$Text		= LogFile_Statistik_Gestern($Comment,$FileLogName,$ZeilenFilter,$WertFNr,$Format,$Unit,$KFaktor);

	my $Min	= "";		# Min-Wert
	my $Max	= "";		# Max-Wert
	my $Avr	= "";		# Durchschnitt
	my $WAnz	= "";	# Anzahl Werte
	$Min	= TSuche_VonBis($Text,"Min:","Max:");		# Wert für 'Min' heraussuchen
	$Max	= TSuche_VonBis($Text,"Max:","Last:");		# Wert für 'Max' heraussuchen
	$Avr	= TSuche_VonBis($Text,"Avr:","Anz:");		# Wert für 'Avr' heraussuchen
	$WAnz	= TSuche_VonBis($Text,"Anz:");				# Werteanzahl herraussuchen
	$Text	= TSuche_VonBis($Text,"","Min:");			# Beginn (Datum+Kommentar) herraussuchen

	$Min	= $Min-$Avr;	# Abweichung nach unten
	$Max	= $Max-$Avr;	# Abweichung nach oben
	if ($Format ne "") {					# wenn Format übergeben wurde
		$Min= sprintf($Format, $Min);
		$Max= sprintf($Format, $Max);
	}

#	$Text	= $Text." ".$Avr.", Min:".$Min.", Max:".$Max.", (Werte: ".$WAnz.")";	# Rückgabe-Text zusammenbauen
	$Text	= $Text." <b>".$Avr."</b> [".$Min."|+".$Max."] (Werte: ".$WAnz.")";	# Rückgabe-Text zusammenbauen
	return $Text;
}

sub TSuche_VonBis ($$;$) {		# Rückgabe Text
	my $Text		= $_[0];	# Übergabe Text
	my $SucheVon	= $_[1];	# Übergabe Suchtext von
	;
	my $SucheBis	= $_[2];	# Übergabe Suchtext bis

	my $PosVon = -1;			# Position von
	if ($SucheVon ne "") {		# wenn für Suchtext von keine leere zeichenkette übergeben wurde
		$PosVon = index($Text,$SucheVon);
	} else {
		$PosVon = 0;			# Position von -> Beginn
	}
	
	my $PosBis = -1;			# Position bis
	if (defined($SucheBis)) {	# wenn Suchtext bis übergeben wurde
		$PosBis = index($Text,$SucheBis);
	}
	
	if ($PosVon >= 0) {			# Suchtext von in Zeichenkette enthalten
		$PosVon = $PosVon + length($SucheVon);
		if ($PosBis >= 0) {		# Suchtext bis in Zeichenkette enthalten
			$Text = substr($Text,$PosVon,$PosBis-$PosVon);
		} else {				# Suchtext bis nicht in Zeichenkette enthalten
			$Text = substr($Text,$PosVon);
		}
	}
	$Text =~ s/^\s+//;	# Leerzeichen am Beginn entfernen
	$Text =~ s/\s+$//;	# Leerzeichen am Ende   entfernen
	return $Text;
}

sub LogFile_Statistik_Gestern ($$$$;$$$) {	# Rückgabe Statistik (min, max, avg,...) aus Log-File für Gestern
	my $Comment	=		$_[0];	# Übergabe Beschreibung
	my $FileLogName	=	$_[1];	# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $ZeilenFilter =	$_[2];	# Übergabe Filter, nur passende Zeilen werden (im Zeitfenster) beatrachtet
	my $WertFNr	=		$_[3];	# Übergabe Feldnummer, in welchem der Wert steht
	;
	my $Format	=		$_[4];	# Übergabe Format für Werte
	my $Unit	=		$_[5];	# Übergabe Einheit
	my $KFaktor	=		$_[6];	# Übergabe Korrektur-Faktor

	my $ZeitVon	= "";			# Zeit von (ab dem FileLog ausgewertet wird)
	my $ZeitBis	= "";			# Zeit bis (bis dahin wird FileLog ausgewertet)
	$ZeitVon = DatumHeute(-1);	# YYYY-MM-DD
	$ZeitBis = DatumHeute(0);	# YYYY-MM-DD

	my $FileName = "";			# Filename
	$FileName = FileLogName_gestern($FileLogName);	# Ermitteln LogFileName vom FileLog (so wie es gestern hieß)
	if ($FileName eq "") {
		return "Datei von LogFile:".$FileLogName." nicht gefunden";
	}
	return File_Statistik($Comment,$FileName,$ZeitVon,$ZeitBis,$ZeilenFilter,$WertFNr,$Format,$Unit,$KFaktor);
}

sub LogFile_Statistik_FileOut_Datum ($$$$$$;$$$) {	# Ausgabe Statistik (min, max, avg,...) aus Log-File für bestimmtes Datum in Datei schreiben
	my $Datum		= $_[0];	# Übergabe Datum YYYY-MM-DD
	my $Comment		= $_[1];	# Übergabe Beschreibung
	my $FileLogName	= $_[2];	# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $FileNameOut	= $_[3];	# Übergabe File-Name für AusgabeDatei
	my $ZeilenFilter= $_[4];	# Übergabe Filter, nur passende Zeilen werden (im Zeitfenster) beatrachtet
	my $WertFNr		= $_[5];	# Übergabe Feldnummer, in welchem der Wert steht
	;
	my $Format		= $_[6];	# Übergabe Format für Werte
	my $Unit		= $_[7];	# Übergabe Einheit
	my $KFaktor		= $_[8];	# Übergabe Korrektur-Faktor

	my $DatumVon	= "";			# Datum von (ab dem FileLog ausgewertet wird)
	my $DatumBis	= "";			# Datum bis (bis dahin wird FileLog ausgewertet)
	$DatumVon		= $Datum;
	$DatumBis		= Datum1Tag($Datum);
	print "LogFile_Statistik_FileOut_Datum: von:".$DatumVon.", bis:".$DatumBis."\n";

	my $Text	= "";			# ein Ergebnis merken
	my $FileName = "";			# Filename
	$FileName = FileLogName_Datum($Datum,$FileLogName);	# Ermitteln LogFileName vom FileLog (so wie es zum Datum hieß)
	if ($FileName eq "") {
		return "Datei von LogFile:".$FileLogName." nicht gefunden";
	}
	$Text	= File_Statistik($Comment,$FileName,$DatumVon,$DatumBis,$ZeilenFilter,$WertFNr,$Format,$Unit,$KFaktor);
	$Text	= $Text."\n";

	my $FileHandle ="";			# File handle
	$FileHandle = open SCHREIBEN ,">>".$FileNameOut;	# Datei zum Schreiben (append) öffnen
	if (not defined($FileHandle)) {
		return "Fehler beim Schreiben in Datei:".$FileNameOut;
	}
	print SCHREIBEN  $Text;		# Rückgabe in Ausgabe-Datei schreiben
	close(SCHREIBEN);			# Datei schliessen
	return $Text;
}

sub LogFile_Statistik_FileOut_Gestern ($$$$$;$$$) {	# Ausgabe Statistik (min, max, avg,...) aus Log-File für Gestern in Datei schreiben
	my $Comment	=		$_[0];	# Übergabe Beschreibung
	my $FileLogName	=	$_[1];	# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $FileNameOut=	$_[2];	# Übergabe File-Name für AusgabeDatei
	my $ZeilenFilter =	$_[3];	# Übergabe Filter, nur passende Zeilen werden (im Zeitfenster) beatrachtet
	my $WertFNr	=		$_[4];	# Übergabe Feldnummer, in welchem der Wert steht
	;
	my $Format	=		$_[5];	# Übergabe Format für Werte
	my $Unit	=		$_[6];	# Übergabe Einheit
	my $KFaktor	=		$_[7];	# Übergabe Korrektur-Faktor

	my $ZeitVon	= "";			# Zeit von (ab dem FileLog ausgewertet wird)
	my $ZeitBis	= "";			# Zeit bis (bis dahin wird FileLog ausgewertet)
	$ZeitVon = DatumHeute(-1);	# YYYY-MM-DD -> gestern
	$ZeitBis = DatumHeute(0);	# YYYY-MM-DD -> heute

	my $Text	= "";			# ein Ergebnis merken
	my $FileName = "";			# Filename
	$FileName = FileLogName_gestern($FileLogName);	# Ermitteln LogFileName vom FileLog (so wie es gestern hieß)
	if ($FileName eq "") {
		return "Datei von LogFile:".$FileLogName." nicht gefunden";
	}
	$Text	= File_Statistik($Comment,$FileName,$ZeitVon,$ZeitBis,$ZeilenFilter,$WertFNr,$Format,$Unit,$KFaktor);
	$Text	= $Text."\n";

	my $FileHandle ="";			# File handle
	$FileHandle = open SCHREIBEN ,">>".$FileNameOut;	# Datei zum Schreiben (append) öffnen
	if (not defined($FileHandle)) {
		return "Fehler beim Schreiben in Datei:".$FileNameOut;
	}
	print SCHREIBEN  $Text;		# Rückgabe in Ausgabe-Datei schreiben
	close(SCHREIBEN);			# Datei schliessen
	return $Text;
}

sub LogFile_Statistik_Datum ($$$$$;$$$) {	# Rückgabe Statistik (min, max, avg,...) aus Log-File für best. Datum
	my $Datum	=		$_[0];	# Übergabe Datum YYYY-MM-DD
	my $Comment	=		$_[1];	# Übergabe Beschreibung
	my $FileLogName	=	$_[2];	# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $ZeilenFilter =	$_[3];	# Übergabe Filter, nur passende Zeilen werden (im Zeitfenster) beatrachtet
	my $WertFNr	=		$_[4];	# Übergabe Feldnummer, in welchem der Wert steht
	;
	my $Format	=		$_[5];	# Übergabe Format für Werte
	my $Unit	=		$_[6];	# Übergabe Einheit
	my $KFaktor	=		$_[7];	# Übergabe Korrektur-Faktor

	my $FileName = "";			# Filename
	$FileName = FileLogName_Datum($Datum,$FileLogName);	# Ermitteln LogFileName vom FileLog (so wie es zum Datum hieß)
	if ($FileName eq "") {
		return "Datei von LogFile:".$FileLogName." nicht gefunden";
	}

	my $DatumVon	= "";			# Datum von (ab dem FileLog ausgewertet wird)
	my $DatumBis	= "";			# Datum bis (bis dahin wird FileLog ausgewertet)
	$DatumVon		= $Datum;
	$DatumBis		= Datum1Tag($Datum);
#	print "LogFile_Statistik_Datum: von:".$DatumVon.", bis:".$DatumBis."\n";

	return File_Statistik($Comment,$FileName,$DatumVon,$DatumBis,$ZeilenFilter,$WertFNr,$Format,$Unit,$KFaktor);
}

sub LogFile_Statistik ($$$$$$;$$$) {	# Rückgabe Statistik (min, max, avg,...) aus Log-File für best Zeitraum
	my $Comment	=		$_[0];	# Übergabe Beschreibung
	my $FileLogName	=	$_[1];	# Übergabe Name Filelog (dessen LogFile wird ausgewertet)
	my $ZeitVon	= 		$_[2];	# Übergabe Zeit von YYYY-MM-DD (ab dem File ausgewertet wird)
	my $ZeitBis	=		$_[3];	# Übergabe Zeit bis YYYY-MM-DD (bis dahin wird File ausgewertet)
	my $ZeilenFilter =	$_[4];	# Übergabe Filter, nur passende Zeilen werden (im Zeitfenster) beatrachtet
	my $WertFNr	=		$_[5];	# Übergabe Feldnummer, in welchem der Wert steht
	;
	my $Format	=		$_[6];	# Übergabe Format für Werte
	my $Unit	=		$_[7];	# Übergabe Einheit
	my $KFaktor	=		$_[8];	# Übergabe Korrektur-Faktor

	my $FileName = "";			# Filename
	$FileName = FileLog_FileName($FileLogName);	# Ermitteln aktuelles LogFile vom FileLog
	if ($FileName eq "") {
		return "Datei von LogFile:".$FileLogName." nicht gefunden";
	}

	return File_Statistik($Comment,$FileName,$ZeitVon,$ZeitBis,$ZeilenFilter,$WertFNr,$Format,$Unit,$KFaktor);
}

sub File_Statistik_vonbis_Day ($$$$$$$;$$$) {	# Rückgabe Statistik (min, max, avg,...) aus File für jeden Tag von-bis
	my $Comment	=		$_[0];	# Übergabe Beschreibung
	my $FileNameRead=	$_[1];	# Übergabe File-Name
	my $FileNameOut=	$_[2];	# Übergabe File-Name
	my $DatumVon= 		$_[3];	# Übergabe Datum von YYYY-MM-DD (ab dieses Datum wird für jeden Tag ein Eintag erstellt)
	my $DatumBis= 		$_[4];	# Übergabe Datum bis YYYY-MM-DD (bis zu dieses Datum wird für jeden Tag ein Eintag erstellt)
	my $ZeilenFilter =	$_[5];	# Übergabe Filter, nur passende Zeilen werden (im Zeitfenster) beatrachtet
	my $WertFNr	=		$_[6];	# Übergabe Feldnummer, in welchem der Wert steht
	;
	my $Format	=		$_[7];	# Übergabe Format für Werte
	my $Unit	=		$_[8];	# Übergabe Einheit
	my $KFaktor	=		$_[9];	# Übergabe Korrektur-Faktor

#	print "File_Statistik_vonbis_Day, von Datum: ".$DatumVon."\n";
#	print "File_Statistik_vonbis_Day, bis Datum: ".$DatumBis."\n";
	if (not( date2num($DatumVon) < date2num($DatumBis))) {	# Datumsangaben falsch
		return "Datum falsch\n";
	}

	my $FileHandle ="";			# File handle
	$FileHandle = open SCHREIBEN ,">>".$FileNameOut;	# Datei zum Schreiben (append) öffnen
	if (not defined($FileHandle)) {
		return "Fehler beim Schreiben in Datei:".$FileNameOut;
	}

	my $Datum	= "";			# Übergabe Datum (für dieses Datum wird File ausgewertet)
	my $Text	= "";			# ein Ergebnis merken
	my $Ergebnis= "";			# Gesamt-Ergebnis merken
	$Datum = $DatumVon;			# Start Datum

	until( date2num($Datum) > date2num($DatumBis) ) {
#		print "File_Statistik_vonbis_Day, fuer Datum: ".$Datum."\n";
		$Text	= File_Statistik_Day($Comment,$FileNameRead,$Datum,$ZeilenFilter,$WertFNr,$Format,$Unit,$KFaktor);
		$Text	= $Text."\n";
		print SCHREIBEN  $Text;
		$Ergebnis = $Ergebnis.$Text;
		$Datum	= DatumDiffTag($Datum,1);	# +1 Tag
	}
	close(SCHREIBEN);			# Datei schliessen
	return $Ergebnis;
}

sub File_Statistik_Day ($$$$$;$$$) {	# Rückgabe Statistik (min, max, avg,...) aus File für einen Tag
	my $Comment	=		$_[0];	# Übergabe Beschreibung
	my $FileName	=	$_[1];	# Übergabe File-Name
	my $Datum	= 		$_[2];	# Übergabe Datum YYYY-MM-DD (für dieses Datum wird File ausgewertet)
	my $ZeilenFilter =	$_[3];	# Übergabe Filter, nur passende Zeilen werden (im Zeitfenster) beatrachtet
	my $WertFNr	=		$_[4];	# Übergabe Feldnummer, in welchem der Wert steht
	;
	my $Format	=		$_[5];	# Übergabe Format für Werte
	my $Unit	=		$_[6];	# Übergabe Einheit
	my $KFaktor	=		$_[7];	# Übergabe Korrektur-Faktor

	my $ZeitVon	= "";			# Zeit von (ab dem File ausgewertet wird)
	my $ZeitBis	= "";			# Zeit bis (bis dahin wird File ausgewertet)

	$ZeitVon	= $Datum;		# setzen Anfangsdatum
	$ZeitBis	= DatumDiffTag($ZeitVon,1);	# +1 Tag
	
	return File_Statistik($Comment,$FileName,$ZeitVon,$ZeitBis,$ZeilenFilter,$WertFNr,$Format,$Unit,$KFaktor);
}

sub File_Statistik ($$$$$$;$$$) {# Rückgabe Statistik (min, max, avg,...) aus File für best Zeitraum
	# Read_FileLog_FileName		# alter name
	my $Comment		= $_[0];	# Übergabe Beschreibung
	my $FileName	= $_[1];	# Übergabe File-Name
	my $ZeitVon		= $_[2];	# Übergabe Zeit von YYYY-MM-DD (ab dem File ausgewertet wird)
	my $ZeitBis		= $_[3];	# Übergabe Zeit bis YYYY-MM-DD (bis dahin wird File ausgewertet)
	my $ZeilenFilter= $_[4];	# Übergabe Filter, nur passende Zeilen werden (im Zeitfenster) beatrachtet
	my $WertFNr		= $_[5];	# Übergabe Feldnummer, in welchem der Wert steht
	;
	my $Format		= $_[6];	# Übergabe Format für Werte
	my $Unit		= $_[7];	# Übergabe Einheit
	my $KFaktor		= $_[8];	# Übergabe Korrektur-Faktor

	my $Datum	= $ZeitVon;		# Datum der Auswertung
	if (not defined($Format)) {	# wenn Format nicht übergeben wurde
		$Format	= "";
	}
	if (not defined($Unit)) {	# wenn Einheit nicht übergeben wurde
		$Unit	= "";
	} else {
		$Unit	= " ".$Unit;
	}
	if (not defined($Comment)) {	# wenn Kommentar nicht übergeben wurde
		$Comment= "";
	}
	if (not defined($KFaktor)) {	# wenn Korrektur-Faktor nicht übergeben wurde
		$KFaktor= 1;
	}
	
	my $FileHandle ="";			# File handle
	open FILE,"<".$FileName;	# Datei zum Lesen öffnen
	if (not defined($FileHandle)) {
		return "Fehler beim Öffnen der Datei:".$FileName;
	}
	
	my $ZeilenAnz			= 0;			# Anzahl ausgewerteter Zeilen (Datum + Filter)
#	my $ZeilenZeitfenster	= 0;			# Anzahl Zeilen, welche im Zeitfenster liegen
	my $Zeile 				= "";			# Zeile aus Datei
	my @ZeilenTeile			= "";			# Bestandteile einer Zeile
	my $ZDatum				= "";			# Datumsfeld aus Zeile
	my $ZWert				= "";			# Wert aus Zeile
	my $WertMin				=  1000000;		# minimaler Wert aus Zeitfenster + Filter
	my $WertMax				= -1000000;		# maximaler Wert aus Zeitfenster + Filter
	my $WertSum				= 0;			# Summe der Werte aus Zeitfenster + Filter
	my $WertAvr				= 0;			# Durchschnitts-Wert aus Zeitfenster + Filter

#	print "Dateiname :".$FileName."\n";
#	print "Beschreib.:".$Comment."\n";
#	print "Datum von :".$ZeitVon."\n";
#	print "Datum bis :".$ZeitBis."\n";
#	print "Filter    :".$ZeilenFilter."\n";
#	print "Wert-Nr.  :".$WertFNr."\n";
#	print "Format    :".$Format."\n";
#	print "Einheit   :".$Unit."\n";

	$ZeitVon= date2num($ZeitVon);				# Datum in Zahl umwandeln
	$ZeitBis= date2num($ZeitBis);				# Datum in Zahl umwandeln
	if (not($ZeitVon < $ZeitBis)) {				# Datumsangaben falsch
		return "Datum, von:".$ZeitVon.", bis:".$ZeitBis." falsch\n";
	}
	
	while(defined(my $Zeile = <FILE>)) {
		@ZeilenTeile = split(/[\s,\t]+/, $Zeile);	# Zeile zerlegen, Trennzeiche: Leer oder Tab (beliebig viele)
		$ZDatum= $ZeilenTeile[0];					# 1.Teil aus Zeile -> Datum
#		print "Datumsfeld:".$ZDatum."\n";
		$ZDatum= time2num($ZDatum);					# Datum in Zahl umwandeln
#		print "Datumszahl:".$ZDatum."\n";
		if ($ZeitVon <= $ZDatum and $ZDatum <= $ZeitBis) {	# Datum liegt im Zeitfenster
			if ($Zeile =~ $ZeilenFilter) {					# Zeile entspricht Filter
				$ZeilenAnz = $ZeilenAnz +1;
				$ZWert= $ZeilenTeile[$WertFNr];		# 1.Teil aus Zeile -> Wert
				$ZWert= $ZWert * $KFaktor;			# Korrektur-Faktor
#				print "Wert:".$ZWert.", aus:".$Zeile;
				if ($ZWert < $WertMin) {			# prüfen of Wert aus Zeile kleiner als Minimalwert ist
					$WertMin = $ZWert;				# neuer Minimalwert
				}
				if ($ZWert > $WertMax) {			# prüfen of Wert aus Zeile größer als Maximalwert ist
					$WertMax = $ZWert;				# neuer Maximalwert
				}
				$WertSum = $WertSum+$ZWert;			# für Summe und Mittelwertberechnung Werte aufsummieren
			}
		}
	}
	if ($ZeilenAnz >0) {						# wenn mindestens eine Zeile ausgewertet wurde (Datum +Filter)
		$WertAvr = $WertSum/$ZeilenAnz;			# Berechnung Mittelwert
		if ($Format ne "") {					# wenn Format übergeben wurde
			$WertMin= sprintf($Format, $WertMin);
			$WertMax= sprintf($Format, $WertMax);
			$ZWert	= sprintf($Format, $ZWert);
			$WertSum= sprintf($Format, $WertSum);
			$WertAvr= sprintf($Format, $WertAvr);
		}
		$WertMin= $WertMin.$Unit."\t";			# Einheit und Tab anhängen
		$WertMax= $WertMax.$Unit."\t";			# Einheit und Tab anhängen
		$ZWert	= $ZWert.$Unit."\t";			# Einheit und Tab anhängen
		$WertSum= $WertSum.$Unit."\t";			# Einheit und Tab anhängen
		$WertAvr= $WertAvr.$Unit."\t";			# Einheit und Tab anhängen
	} else {	
		$WertMin= "n/a\t";						# kein Min-Wert, da keine Zeilen gelesen wurden
		$WertMax= "n/a\t";						# kein Max-Wert, da keine Zeilen gelesen wurden
		$ZWert	= "n/a\t";						# kein Letzter-Wert, da keine Zeilen gelesen wurden
		$WertSum= "n/a\t";						# kein Summen-Wert, da keine Zeilen gelesen wurden
		$WertAvr= "n/a\t";						# kein Mittelwert, da keine Zeilen gelesen wurden
	}
#	print "Min Wert  :".$WertMin."\n";
#	print "Max Wert  :".$WertMax."\n";
#	print "letzer W. :".$ZWert."\n";
#	print "Summe     :".$WertSum."\n";
#	print "Mittelwert:".$WertAvr."\n";
#	print "WerteAnz  :".$ZeilenAnz."\n";

	close(FILE);								# Datei schliessen
	if ( length($Comment) <21)	{				# prüfen Länge Kommentar Feld
		$Comment	= $Comment."\t\t";			# zwei Tabs zur Formatierung der Zeile
	} else {	
		$Comment	= $Comment."\t";			# nur ein Tab
	}
	return $Datum." ".$Comment."Min: ".$WertMin."Max: ".$WertMax."Last: ".$ZWert."Sum: ".$WertSum."Avr: ".$WertAvr."Anz: ".$ZeilenAnz;
}

sub FileLogName_Datum ($$) {	# Rückgabe FileName von einem FileLog für bestimmtes Datum (Beachtung neuer Filename bei z.B. Monatswechsel)
	my $Datum		= $_[0];	# Übergabe Datum YYYY-MM-DD
	my $FileLogName	= $_[1];	# Übergabe Name Filelog (dessen LogFile wird ausgewertet)

	my $Sekunden	= date2num($Datum);	# Datum in Sekunden umwandeln
	my $logfile = "";			# Wert für logfile
	$logfile = InternalVal($FileLogName,"logfile","");	# Auslesen Wert von internen Wert 'logfile'
	if ($logfile eq "") {
		print "logfile-Wert von FileLog:".$FileLogName." nicht gefunden\n";
		return "";
	}
	my $sec		= "";			#	Sekunden
	my $min		= "";			#	Minuten
	my $hour	= "";			#	Stunden
	my $Day		= "";			#	%d day of month (01..31)
	my $Month	= "";			#	%m month (01..12)
	my $Year	= "";			#	%Y year (1970...)
	my $wDay	= "";			#	%w day of week (0..6); 0 represents Sunday
	my $jDay	= "";			#	%j day of year (001..366)
	my $isdst	= "";			#	Sommerzeit
	($sec , $min, $hour, $Day, $Month, $Year, $wDay, $jDay, $isdst) = localtime($Sekunden);	# aktuelle Zeit -1 Tag
	$Year		= $Year	+ 1900;	# Korrektur Jahreszahl
	$Month		= $Month + 1;	# Korrektur Monat
	
	my $wWeek	= "";			#	%W week number of year with Monday as first day of week (00..53)
	my $uWeek	= "";			#	%U week number of year with Sunday as first day of week (00..53)
	$wWeek = strftime("%W",localtime(time));
	$uWeek = strftime("%U",localtime(time));

	$Day	= sprintf("%2.2d", $Day);	# Zahl zweistellig formatieren
	$Month	= sprintf("%2.2d", $Month);	# Zahl zweistellig formatieren
	$jDay	= sprintf("%3.3d", $jDay);	# Zahl dreistellig formatieren
	
#	print "Uhrzeit: ".$hour.":".$min.":".$sec."\n";
#	print "Datum  : ".$Day.".".$Month.".".$Year."\n";
#	print "Tag    : ".$jDay.", Tag der Woche:".$wDay.", Woche(Mo):".$wWeek.", Woche(So):".$uWeek.", Sommerzeit:".$isdst."\n";
	
#	print "Filename vorher:".FileLog_FileName($FileLogName)."\n";	# 
#	print "Logfile vorher :".$logfile."\n";		# 
	$logfile	=~ s/%d/$Day/g;		#	%d day of month (01..31)
	$logfile	=~ s/%m/$Month/g;	#	%m month (01..12)
	$logfile	=~ s/%Y/$Year/g;	#	%Y year (1970...)
	$logfile	=~ s/%w/$wDay/g;	#	%w day of week (0..6); 0 represents Sunday
	$logfile	=~ s/%j/$jDay/g;	#	%j day of year (001..366)
#	print "Logfile nachher:".$logfile."\n";		# 
	return $logfile;
}

sub FileLogName_gestern ($) {	# Rückgabe FileName von einem FileLog für gestern (Beachtung neuer Filename bei z.B. Monatswechsel)
	my $FileLogName	=	$_[0];	# Übergabe Name Filelog (dessen LogFile wird ausgewertet)

	my $logfile = "";			# Wert für logfile
	$logfile = InternalVal($FileLogName,"logfile","");	# Auslesen Wert von internen Wert 'logfile'
	if ($logfile eq "") {
		print "logfile-Wert von FileLog:".$FileLogName." nicht gefunden\n";
		return "";
	}
	my $sec		= "";			#	Sekunden
	my $min		= "";			#	Minuten
	my $hour	= "";			#	Stunden
	my $Day		= "";			#	%d day of month (01..31)
	my $Month	= "";			#	%m month (01..12)
	my $Year	= "";			#	%Y year (1970...)
	my $wDay	= "";			#	%w day of week (0..6); 0 represents Sunday
	my $jDay	= "";			#	%j day of year (001..366)
	my $isdst	= "";			#	Sommerzeit
	($sec , $min, $hour, $Day, $Month, $Year, $wDay, $jDay, $isdst) = localtime(time-(60*60*24));	# aktuelle Zeit -1 Tag
	$Year		= $Year	+ 1900;	# Korrektur Jahreszahl
	$Month		= $Month + 1;	# Korrektur Monat
	
	my $wWeek	= "";			#	%W week number of year with Monday as first day of week (00..53)
	my $uWeek	= "";			#	%U week number of year with Sunday as first day of week (00..53)
	$wWeek = strftime("%W",localtime(time));
	$uWeek = strftime("%U",localtime(time));

	$Day	= sprintf("%2.2d", $Day);	# Zahl zweistellig formatieren
	$Month	= sprintf("%2.2d", $Month);	# Zahl zweistellig formatieren
	$jDay	= sprintf("%3.3d", $jDay);	# Zahl dreistellig formatieren
	
#	print "Uhrzeit: ".$hour.":".$min.":".$sec."\n";
#	print "Datum  : ".$Day.".".$Month.".".$Year."\n";
#	print "Tag    : ".$jDay.", Tag der Woche:".$wDay.", Woche(Mo):".$wWeek.", Woche(So):".$uWeek.", Sommerzeit:".$isdst."\n";
	
#	print "Filename vorher:".FileLog_FileName($FileLogName)."\n";	# 
#	print "Logfile vorher :".$logfile."\n";		# 
	$logfile	=~ s/%d/$Day/g;		#	%d day of month (01..31)
	$logfile	=~ s/%m/$Month/g;	#	%m month (01..12)
	$logfile	=~ s/%Y/$Year/g;	#	%Y year (1970...)
	$logfile	=~ s/%w/$wDay/g;	#	%w day of week (0..6); 0 represents Sunday
	$logfile	=~ s/%j/$jDay/g;	#	%j day of year (001..366)
#	print "Logfile nachher:".$logfile."\n";		# 
	return $logfile;
}

sub FileLog_FileName ($) {		# Rückgabe aktuellen Filenamen von FileLog
	my $FileLogName	= $_[0];	# Übergabe Name Filelog

	my $FileName	= "";		# Filename
	$FileName = InternalVal($FileLogName,"currentlogfile","");	# Auslesen Wert von internen Wert 'currentlogfile'
	return $FileName;
}

sub Datum1Tag ($) {			# Rückgabe Datum + 1 tag
	my $Datum	= $_[0];	# Übergabe Datum YYYY-MM-DD
	my $DatumBis= "";		# Datum bis (bis dahin wird FileLog ausgewertet)
	$DatumBis	= sec2Datum(date2num($Datum) + 24*60*60);	# + 1 Tag in Sekunden
	return $DatumBis;
}

1;
