##############################################
package main;

use strict;
use warnings;

sub Lipo_State_Initialize ();	# Initialisierung
sub DevListe ($);				# gibt alle Devices zur�ck, bei welchen dem Filter entsprechen
sub SetCmd2Liste ($$);			# Set-Kommando f�r jedes Ger�t in Liste ausf�hren
sub average ();					# R�ckgabe Durchschnitt
sub Summe ();					# R�ckgabe Summe
sub Maximum ();					# R�ckgabe Maximum
sub Minimum ();					# R�ckgabe Minimum
sub Anzahl ();					# R�ckgabe Anzahl Zahlen
sub DevStateCommand ($$);		# Ausf�hrung eines Kommandos auf allen Geraeten mit einen angebegenen Status
sub readingWert ($$);			# gibt alle Devices zur�ck, bei welchen ein Reading einen bestimmten Wert hat
sub readingNotWert ($$);		# gibt alle Devices zur�ck, bei welchen ein Reading einen bestimmten Wert nicht hat (aber vorhanden ist)
sub runCommand ($);				# Kommando ausf�hren und Ausgabe zur�ckgeben


sub Lipo_State_Initialize {
	return;
}

sub DevListe ($) {				# gibt alle Devices zur�ck, bei welchen dem Filter entsprechen
	my $Filter		= $_[0];	# �bergabe Filter
	
	my $i			= 0;		# Z�hler  Zeilen
	my @Zeile;					# Ausgabe Zeilen
	my @Teile;
	my $DevName		= "";		# Name des Devices
	my $text		= "";		# Text f�r R�ckgabe
	
	@Zeile	= runCommand("list ".$Filter);	# Ausgabe Ger�testatus aller Devices
#	@Zeile	= devspec2array($Reading);	# Ausgabe Ger�testatus aller Devices

	for($i=0; $i<@Zeile; $i++) {
#		print "DevListe, Zeile:".$i.", Inhalt:".$Zeile[$i]."\n";
		@Teile		= split(/\s+/,$Zeile[$i]);	# Trennzeichen ' ' ein oder mehrfach
		$DevName	= $Teile[0];
#		print "DevListe, Zeile:".$i.", DevName:".$DevName."\n";
		if ($text ne "")	{$text= $text." ";}	# wenn nicht leer -> Leerzeichen anh�ngen
		$text	= $text.$DevName;				# zur Ausgabe hinzuf�gen
	}

#	print  $text;
	return $text;
}

sub SetCmd2Liste ($$) {			# Set-Kommando f�r jedes Ger�t in Liste ausf�hren
	my $DevListe	= $_[0];	# �bergabe Ger�teliste (Leerzeichen Trennzeichen)
	my $command		= $_[1];	# �bergabe Kommando (Teil nach 'set device')

	my @Device;					# Ger�te
	@Device		= split(/\s+/,$DevListe);	# Trennzeichen ' ' ein oder mehrfach

	my $output	= "";			# FHEM Kommando Ausgabe
	my $i		= 0;			# Z�hler  Zeilen
	for($i=0; $i<@Device; $i++) {
#		print "Set2Liste, Device:".$i.", DevName:".$Device[$i]."\n";
		Log(3, "SetCmd2Liste, Device: ".$Device[$i].", Kommando: ".$command);
		$output	= fhem("set ".$Device[$i]." ".$command);	# Kommando ausf�hren
#		print	$output;
	}

	return "set '".$command."' -> ".$DevListe;
}

sub average		{		# R�ckgabe Durchschnitt
	my $Wert	= 0;
	my $Anzahl	= 0;
	my $Summe	= 0;
	foreach $Wert ( @_ ) {
		if ($Wert =~ /[\d+]/ and $Wert ne "") {	# pr�fen ob Wert eine Zahl ist
			$Summe	+= $Wert;	# Wert zu Summe addieren
			$Anzahl++;			# +1
		}
	}
	my $Durchschnitt = 0;
	if ($Anzahl>0) {
		$Durchschnitt	= $Summe/$Anzahl;
	}
	return $Durchschnitt;
}

sub Summe		{		# R�ckgabe Summe
	my $Wert	= 0;
	my $Summe	= 0;
	foreach $Wert ( @_ ) {
		if ($Wert =~ /[\d+]/ and $Wert ne "") {	# pr�fen ob Wert eine Zahl ist
			$Summe	+= $Wert;	# Wert zu Summe addieren
		}
	}
	return $Summe;
}

sub Maximum		{		# R�ckgabe Maximum
	my $Wert	= 0;
	my $Maximum	= "n/a";
	foreach $Wert ( @_ ) {
		if ($Wert =~ /[\d+]/ and $Wert ne "") {	# pr�fen ob Wert eine Zahl ist
			if ($Wert > $Maximum or $Maximum eq "n/a") {	# wenn Wert groesser als Maximum ist
				$Maximum	= $Wert;		# neues Maximum setzen
			}
		}
	}
	return $Maximum;
}

sub Minimum	{		# R�ckgabe Minimum
	my $Wert	= 0;
	my $Minimum	= "n/a";
	foreach $Wert ( @_ ) {
		if ($Wert =~ /[\d+]/ and $Wert ne "") {	# pr�fen ob Wert eine Zahl ist
			if ($Wert < $Minimum or $Minimum eq "n/a") {	# wenn Wert kleiner als Maximum ist
				$Minimum	= $Wert;		# neues Minimum setzen
			}
		}
	}
	return $Minimum;
}

sub Anzahl		{		# R�ckgabe Anzahl Zahlen
	my $Wert	= 0;
	my $Anzahl	= 0;
	foreach $Wert ( @_ ) {
		if ($Wert =~ /[\d+]/ and $Wert ne "") {	# pr�fen ob Wert eine Zahl ist
			$Anzahl++;			# +1
		}
	}
	return $Anzahl;
}

sub DevStateCommand ($$) {		# Ausf�hrung eines Kommandos auf allen Geraeten mit einen angebegenen Status
	my $DevState	= $_[0];	# �bergabe ObjektState
	my $DevCommand	= $_[1];	# �bergabe Kommando, welches ausgef�hrt werden soll
	
	my @Zeile;					# Ausgabe
	my @Teile;
	my $command = "";			# FHEM Kommando
	my $output = "";			# FHEM Kommando Ausgabe
	my $i;
	my $DevName;
	
#	system("echo DevList fuer :".$DevState." >>./log/99_Lipo.txt");
	
	$command = "list .* STATE";	# FHEM Kommando: alle Devices mit Status anzeigen
#	system("echo DevList, Kommando:".$command." >>./log/99_Lipo.txt");
#	$output = fhem($command);	# Ausgabe Ger�testatus aller Devices
#	@Zeile = split(/\n/,$output);	# Trennzeichen 'newline' ein oder mehrfach

	@Zeile	= runCommand($command);	# FHEM Kommando alle Devices mit Status anzeigen

	for($i=0; $i<@Zeile; $i++) {
#		system("echo DevList, Zeile:".$i.", Inhalt:".$Zeile[$i]." >>./log/99_Lipo.txt");
		$output = substr($Zeile[$i],index($Zeile[$i], " ")+1);
#		system("echo DevList, Zeile:".$i.", Status:".$output." >>./log/99_Lipo.txt");
		if ($output eq $DevState) {	# Device-Status entspricht gesuchtem Status
			$DevName = substr($Zeile[$i],0,index($Zeile[$i], " "));
#			system("echo ''DevList, Zeile:".$i.", Inhalt:".$Zeile[$i]."'' >>./log/99_Lipo.txt");
#			system("echo DevList, Zeile:".$i.", gesuchtes Device:".$DevName." >>./log/99_Lipo.txt");
			$command = "set ".$DevName." ".$DevCommand;	# FHEM Kommando alle Devices mit Status anzeigen
#			system("echo DevList, Kommando:".$command." >>./log/99_Lipo.txt");
			fhem($command);	# Ausgabe Ger�testatus aller Devices
		}
	}

	return @Zeile;
}

sub readingWert ($$) {			# gibt alle Devices zur�ck, bei welchen ein Reading einen bestimmten Wert hat
	my $Reading		= $_[0];	# �bergabe Attributname
	my $VerglWert	= $_[1];	# �bergabe Vergleichs-Wert
	
	my $i			= 0;		# Z�hler  Zeilen
	my $m			= 0;		# Z�hler  Werte
	my @Zeile;					# Ausgabe Zeilen
	my @Wert;					# Werte in einer Zeile
	my $DevName		= "";		# Name des Devices
	my $AttrWert	= "";		# Wert des Attributes
	my $text		= "";		# Text f�r R�ckgabe
	
	@Zeile	= runCommand("list .* ".$Reading);	# Ausgabe Ger�testatus aller Devices
#	@Zeile	= devspec2array($Reading);	# Ausgabe Ger�testatus aller Devices

	for($i=0; $i<@Zeile; $i++) {
#		print "attribWert, Zeile:".$i.", Inhalt:".$Zeile[$i]."\n";
		@Wert		= split(/\s+/,$Zeile[$i]);	# Trennzeichen ' ' ein oder mehrfach
#		print "attribWert, Zeile:".$i.", Wert[0]:".$Wert[0].", Wert[1]:".$Wert[1].", Wert[2]:".$Wert[2].", Wert[3]:".$Wert[3].", Wert[4]:".$Wert[4]."\n";
		$DevName	= $Wert[0];
		$AttrWert	= $Wert[3];
#		print "attribWert, Zeile:".$i.", DevName:".$DevName.", AttrWert:".$AttrWert."\n";
		if (lc($AttrWert) eq lc($VerglWert)) {	# Device-Status entspricht gesuchtem Status
#			print "attribWert, Uebereinstimmung:".$i.", DevName:".$DevName.", AttrWert:".$AttrWert."\n";
			if (EigLesen($DevName,"Funktion","n/a") ne "inaktiv") {		# nur wenn 'Funktion' nicht "inaktiv" ist
				if ($text ne "") {$text	= $text.",<br>";}				# Komma + neue Zeile anh�ngen, wenn nicht leer
#				$text	= $text.$DevName." ".$Reading."=".$AttrWert;	# zur Ausgabe hinzuf�gen
				$text	= $text."<b>".$DevName."</b> ".$Reading."=<b><font color='red'>".$AttrWert."</font></b><br>";	# zur Ausgabe hinzuf�gen (formatiert)
			}
		}
	}

#	print  $text;
	return $text;
}

sub readingNotWert ($$) {		# gibt alle Devices zur�ck, bei welchen ein Reading einen bestimmten Wert nicht hat (aber vorhanden ist)
	my $Reading		= $_[0];	# �bergabe Attributname
	my $VerglWert	= $_[1];	# �bergabe Vergleichs-Wert
	
	my $i			= 0;		# Z�hler  Zeilen
	my $m			= 0;		# Z�hler  Werte
	my @Zeile;					# Ausgabe Zeilen
	my @Wert;					# Werte in einer Zeile
	my $DevName		= "";		# Name des Devices
	my $AttrWert	= "";		# Wert des Attributes
	my $text		= "";		# Text f�r R�ckgabe
	
	@Zeile	= runCommand("list .* ".$Reading);	# Ausgabe Ger�testatus aller Devices
#	@Zeile	= devspec2array($Reading);	# Ausgabe Ger�testatus aller Devices

	for($i=0; $i<@Zeile; $i++) {
#		print "attribWert, Zeile:".$i.", Inhalt:".$Zeile[$i]."\n";
		@Wert		= split(/\s+/,$Zeile[$i]);	# Trennzeichen ' ' ein oder mehrfach
#		print "attribWert, Zeile:".$i.", Wert[0]:".$Wert[0].", Wert[1]:".$Wert[1].", Wert[2]:".$Wert[2].", Wert[3]:".$Wert[3].", Wert[4]:".$Wert[4]."\n";
		$DevName	= $Wert[0];
		$AttrWert	= $Wert[3];
#		print "attribWert, Zeile:".$i.", DevName:".$DevName.", AttrWert:".$AttrWert."\n";
		if (lc($AttrWert) ne lc($VerglWert)) {	# Device-Status entspricht nicht gesuchtem Status
#			print "attribWert, Uebereinstimmung:".$i.", DevName:".$DevName.", AttrWert:".$AttrWert."\n";
			if (EigLesen($DevName,"Funktion","n/a") ne "inaktiv") {		# nur wenn 'Funktion' nicht "inaktiv" ist
				if ($text ne "") {										# wenn schon Ger�te gefunden wurden
					$text	= $text.",<br>";							# Komma + neue Zeile anh�ngen
				}
#				$text	= $text.$DevName." ".$Reading."=".$AttrWert;	# zur Ausgabe hinzuf�gen
				$text	= $text."<b>".$DevName."</b> ".$Reading."=<b><font color='red'>".$AttrWert."</font></b><br>";	# zur Ausgabe hinzuf�gen (formatiert)
			}
		}
	}
#	print  $text;
	return $text;
}

sub runCommand ($) {			# Kommando ausf�hren und Ausgabe zur�ckgeben
	my $command	= $_[0];		# �bergabe Kommando

	my $output	= "";			# FHEM Kommando Ausgabe
	my @Zeile;					# Ausgabe

#	Log (2, "runCommand, Kommando:".$command);
	$output	= fhem($command);	# Ausgabe Ger�testatus aller Devices
#	print	"Ausgabe runCommand:\n";
#	print	$output;
	
	@Zeile	= split(/\n/,$output);	# Trennzeichen 'newline' ein oder mehrfach
	return @Zeile;
}

1;
