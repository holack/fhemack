##############################################
package main;

use strict;
use warnings;

sub Lipo_Zeit_Initialize ();	# Initialisierung
sub DatumHeute (;$);			# Datum ausgeben
sub DatumDiffTag ($$);			# Datumsdifferent für x Tage ausgeben
sub time2diff ($$);				# Zeit-Differenz von zwei Zeiten
sub timeDiffSec ($$);			# Zeit-Differenz von zwei Zeiten in Sekunden
sub timeDiffMin ($$);			# Zeit-Differenz von zwei Zeiten in Minuten
sub timeDiffStd ($$);			# Zeit-Differenz von zwei Zeiten in Stunden
sub timeAlterSec ($);			# vergangene Zeit seit übergebener Zeit in Sekunden
sub timeAlterMin ($);			# vergangene Zeit seit übergebener Zeit in Miniten
sub timeAlterStd ($);			# vergangene Zeit seit übergebener Zeit in Sunden
sub time2num ($);				# Datumsfeld in Zahl umwandeln (Anzahl Sekunden)
sub date2num ($);				# Datum YYYY-MM-DD in Zahl umwandeln (Anzahl Sekunden)
sub zeit2num ($);				# Zeit hh:mm in Zahl umwandeln (Anzahl Sekunden)
sub hhmmAddSec ($$);			# zu Zeit hh:mm:ss ein Anzahl Sekunden addieren
sub Std2hhmm ($);				# Stunden nach HH:MM umwandeln (Stunden auch größer 24)
sub Sec2hhmm ($);				# Sekunden nach HH:MM umwandeln (Stunden auch größer 24)
sub Sec2dddhhmm ($);			# Sekunden nach dd HH:MM umwandeln (Tage,Stunden:Minuten)
sub Sec2hhmmss ($);				# Sekunden nach HH:MM:SS umwandeln (Stunden auch größer 24)
sub sec2Datum ($);				# Zahl (Anzahl Sekunden) in Datum umwandeln
sub sec2Time ($);				# Zahl (Anzahl Sekunden) in Datumfeld umwandeln
sub hhmm ($);					# aus Datumsfeld hh:mm herauslösen
sub hhmmss2hhmm ($);			# aus hh:mm:ss --> hh:mm herauslösen

sub Lipo_Zeit_Initialize {
	return;
}

sub DatumHeute (;$) {		# Datum ausgeben
	my $DiffTage =	$_[0];	# Übergabe Differenz (in Tagen) zum heutigen Tag
	if (not defined($DiffTage)) {	# wenn Differenz nicht übergeben wurde
		$DiffTage= 0;
	}
	my $Datum	= "";
	my @time	= localtime(time);		# $Sekunden, $Minuten, $Stunden, $Tag, $Monat, $Jahr, $Wochentag, $Jahrestag, $Sommerzeit
	
#	print "Uhrzeit: ".$time[2].":".$time[1].":".$time[0]."\n";
#	print "Datum  : ".$time[3].".".$time[4].".".$time[5]."\n";
#	print "Wochentag: ".$time[6].", Jahrestag:".$time[7].", Sommerzeit:".$time[8]."\n";
	
#	$time[0]	= 0;				# Sekunden
#	$time[1]	= 0;				# Minuten
#	$time[2]	= 0;				# Stunden
#	$time[3]	= $time[3];			# Tag
#	$time[4]	= $time[4]-1;		# Monat
#	$time[5]	= $time[5]-1900;	# Jahr
#	$time[6]	= undef;				# Wochentag
#	$time[7]	= undef;				# Jahrestag
#	$time[8]	= $time[8];			# Sommerzeit

#	$Datum = strftime("%Y-%m-%d",@time);
#	print "Datum heute:".$Datum."\n";
#	print "Tage Diff. :".$DiffTage."\n";

	$time[3]	= $time[3] + $DiffTage;	# Tage
	$Datum = strftime("%Y-%m-%d",0,0,0,$time[3],$time[4],$time[5]);
#	print "Datum Diff.:".$Datum."\n";
    return $Datum;
}

sub DatumDiffTag ($$) {		# Datumsdifferent für x Tage ausgeben
	my $Datum	= 	$_[0];	# Übergabe Datum
	my $DiffTage=	$_[1];	# Übergabe Differenz in Tagen
	
	my ($year,$mon,$day) = split(/[\s.:-]+/, $Datum);
	$day		= $day + $DiffTage;		# Tages-Dirrenzen addieren
#	print "File_Statistik_Day, day :".$day."\n";
#	print "File_Statistik_Day, mon :".$mon."\n";
#	print "File_Statistik_Day, year:".$year."\n";
	
	my @time;					# $Sekunden, $Minuten, $Stunden, $Tag, $Monat, $Jahr, $Wochentag, $Jahrestag, $Sommerzeit
	$time[0]	= 0;			# Sekunden
	$time[1]	= 0;			# Minuten
	$time[2]	= 0;			# Stunden
	$time[3]	= $day;			# Tag
	$time[4]	= $mon-1;		# Monat
	$time[5]	= $year-1900;	# Jahr

	my $DiffDatum	= "";		#
	$DiffDatum	= strftime("%Y-%m-%d",@time);
#	print "DatumDiffTag, Datum    :".$Datum."\n";
#	print "DatumDiffTag, DiffTage :".$DiffTage."\n";
#	print "DatumDiffTag, DiffDatum:".$DiffDatum."\n";

    return $DiffDatum;
}

sub time2diff ($$) {		# Zeit-Differenz von zwei Zeiten
	my $Time1	= 	$_[0];	# Übergabe Zeitpunkt 1
	my $Time2	= 	$_[1];	# Übergabe Zeitpunkt 2

	return time2num($Time2)-time2num($Time1);
}

sub timeDiffSec ($$) {		# Zeit-Differenz von zwei Zeiten in Sekunden
	my $Time1	= 	$_[0];	# Übergabe Zeitpunkt 1
	my $Time2	= 	$_[1];	# Übergabe Zeitpunkt 2

	return time2num($Time2)-time2num($Time1);
}

sub timeDiffMin ($$) {		# Zeit-Differenz von zwei Zeiten in Minuten
	my $Time1	= 	$_[0];	# Übergabe Zeitpunkt 1
	my $Time2	= 	$_[1];	# Übergabe Zeitpunkt 2

	return (time2num($Time2)-time2num($Time1))/60;
}

sub timeDiffStd ($$) {		# Zeit-Differenz von zwei Zeiten in Stunden
	my $Time1	= 	$_[0];	# Übergabe Zeitpunkt 1
	my $Time2	= 	$_[1];	# Übergabe Zeitpunkt 2

	return (time2num($Time2)-time2num($Time1))/60/60;
}

sub timeAlterSec ($) {		# vergangene Zeit seit übergebener Zeit in Sekunden
	my $Time1	= $_[0];	# Übergabe Zeitpunkt 1
	
	my $Time2	= 0;		# Zeitpunkt 2
	$Time2		= strftime("%Y-%m-%d_%H:%M:%S", localtime(time));	# aktuelle Zeit
	
	return time2num($Time2)-time2num($Time1);
}

sub timeAlterMin ($) {		# vergangene Zeit seit übergebener Zeit in Miniten
	my $Time1	= $_[0];	# Übergabe Zeitpunkt 1
	
	my $Time2	= 0;		# Zeitpunkt 2
	$Time2		= strftime("%Y-%m-%d_%H:%M:%S", localtime(time));	# aktuelle Zeit
	
	return (time2num($Time2)-time2num($Time1))/60;
}

sub timeAlterStd ($) {		# vergangene Zeit seit übergebener Zeit in Sunden
	my $Time1	= $_[0];	# Übergabe Zeitpunkt 1
	
	my $Time2	= 0;		# Zeitpunkt 2
	$Time2		= strftime("%Y-%m-%d_%H:%M:%S", localtime(time));	# aktuelle Zeit
	
	return (time2num($Time2)-time2num($Time1))/60/60;
}

sub time2num ($) {			# Datumsfeld in Zahl umwandeln (Anzahl Sekunden)
	my $Datum	= 	$_[0];	# Übergabe Datum
	my @a;
	if($Datum ne "") {
		@a = split("[- :_]", $Datum);

		if (!defined $a[5]) {$a[5] = 0;}	# wenn Sekunden nicht übergeben wurden
		if (!defined $a[4]) {$a[4] = 0;}	# wenn Minuten  nicht übergeben wurden
		if (!defined $a[3]) {$a[3] = 0;}	# wenn Stunden  nicht übergeben wurden

		return mktime($a[5], $a[4],$a[3], $a[2], $a[1]-1,$a[0]-1900,0,0,-1);
	} else {
		my           ($sec , $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
		return mktime($sec , $min, $hour, $mday, $mon, $year, 0,     0,     -1);
	}
}

sub date2num ($) {			# Datum YYYY-MM-DD in Zahl umwandeln (Anzahl Sekunden)
	my $Datum	= 	$_[0];	# Übergabe Datum
	my @a;
    @a = split("[- :_]", $Datum);
#	my           ($sec, $min, $hour, $mday, $mon   , $year     , $wday, $yday, $isdst) = localtime(time);
    return mktime(0   , 0   , 0    , $a[2], $a[1]-1, $a[0]-1900, 0    , 0    , 0);
}

sub zeit2num ($) {			# Zeit hh:mm in Zahl umwandeln (Anzahl Sekunden)
	my $Zeit	= 	$_[0];	# Übergabe Zeit
	my @a;
    @a = split("[- :_]", $Zeit);
	my           ($sec , $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
    return mktime($sec ,$a[1], $a[0], $mday, $mon, $year, $wday, $yday, $isdst);
}

sub hhmmAddSec ($$) {		# zu Zeit hh:mm:ss ein Anzahl Sekunden addieren
	my $Zeit	= 	$_[0];	# Übergabe Zeit
	my $SecAdd	= 	$_[1];	# Übergabe Anzahl Sekunden die addiert werden sollen

	my ($hh, $mm, $ss);
    ($hh, $mm, $ss) = split("[:]", $Zeit);
	if (!defined $ss) {		# wenn keine Sekunden übergeben wurden
		$ss = 0;
	}

	my $add	= 0;
	$add	= int($SecAdd/3600);
	$hh		= $hh + $add;
	$hh		= $hh - int($hh/24)*24;		# hh nicht größer als 24
	$hh		= sprintf("%2.2d", $hh);	# Zahl zweistellig formatieren
	$SecAdd	= $SecAdd - $add*3600;
	
	$add	= int($SecAdd/60);
	$mm		= $mm + $add;
	$mm		= sprintf("%2.2d", $mm);	# Zahl zweistellig formatieren
	$SecAdd	= $SecAdd - $add*60;
	
	$ss		= int($ss + $SecAdd);
	$ss		= sprintf("%2.2d", $ss);	# Zahl zweistellig formatieren

    return $hh.":".$mm.":".$ss;
}

sub Std2hhmm ($) {		# Stunden nach HH:MM umwandeln (Stunden auch größer 24)
	my $Std	= 	$_[0];	# Übergabe Anzahl der Sekunden

	my $hh	= 0;		# Anzahl der Stunden
	my $mm	= 0;		# Anzahl der Minuten
	
	$hh		= int($Std);
	$hh		= sprintf("%2.2d", $hh);	# Stunden zweistellig formatieren

	$Std	= $Std - $hh;				# restliche Stunden berechnen (Stunden anziehen)
	$mm		= int($Std*60);
	$mm		= sprintf("%2.2d", $mm);	# Minuten zweistellig formatieren
    return $hh.":".$mm;
}

sub Sec2hhmm ($) {		# Sekunden nach HH:MM umwandeln (Stunden auch größer 24)
	my $Sec	= 	$_[0];	# Übergabe Anzahl der Sekunden

	my $hh	= 0;		# Anzahl der Stunden
	my $mm	= 0;		# Anzahl der Minuten
	
	$hh		= int($Sec/3600);
	$hh		= sprintf("%2.2d", $hh);	# Stunden zweistellig formatieren

	$Sec	= $Sec - $hh*3600;			# restliche Sekunden berechnen (Stunden anziehen)
	$mm		= int($Sec/60);
	$mm		= sprintf("%2.2d", $mm);	# Minuten zweistellig formatieren

#	$Sec	= $Sec - $mm*60;			# restliche Sekunden berechnen (Minuten anziehen)
#	$Sec	= sprintf("%2.2d", $Sec);	# Sekunden zweistellig formatieren

#    return $hh.":".$mm.":".$Sec;
    return $hh.":".$mm;
}

sub Sec2dddhhmm ($) {	# Sekunden nach dd HH:MM umwandeln (Tage,Stunden:Minuten)
	my $Sec	= 	$_[0];	# Übergabe Anzahl der Sekunden

	my $dd	= 0;		# Anzahl der Tage
	my $hh	= 0;		# Anzahl der Stunden
	my $mm	= 0;		# Anzahl der Minuten
	
	$dd		= int($Sec/3600/24);

	$Sec	= $Sec - $dd*3600*24;		# restliche Sekunden berechnen (Tage anziehen)
	$hh		= int($Sec/3600);
	$hh		= sprintf("%2.2d", $hh);	# Stunden zweistellig formatieren

	$Sec	= $Sec - $hh*3600;			# restliche Sekunden berechnen (Stunden anziehen)
	$mm		= int($Sec/60);
	$mm		= sprintf("%2.2d", $mm);	# Minuten zweistellig formatieren

	if ($dd >0) {		# wenn Tage >0
		return $dd."d ".$hh.":".$mm;
	} else {
		return $hh.":".$mm;
	}
}

sub Sec2hhmmss ($) {	# Sekunden nach HH:MM:SS umwandeln (Stunden auch größer 24)
	my $Sec	= 	$_[0];	# Übergabe Anzahl der Sekunden

	my $hh	= 0;		# Anzahl der Stunden
	my $mm	= 0;		# Anzahl der Minuten
	
	$hh		= int($Sec/3600);
	$hh		= sprintf("%2.2d", $hh);	# Stunden zweistellig formatieren

	$Sec	= $Sec - $hh*3600;			# restliche Sekunden berechnen (Stunden anziehen)
	$mm		= int($Sec/60);
	$mm		= sprintf("%2.2d", $mm);	# Minuten zweistellig formatieren

	$Sec	= $Sec - $mm*60;			# restliche Sekunden berechnen (Minuten anziehen)
	$Sec	= sprintf("%2.2d", $Sec);	# Sekunden zweistellig formatieren

    return $hh.":".$mm.":".$Sec;
#    return $hh.":".$mm;
}

sub sec2Datum ($) {			# Zahl (Anzahl Sekunden) in Datum umwandeln
	my $Sekunden= $_[0];	# Übergabe Anzahl Sekunden
#	my                                  ($sec     , $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
#	return strftime("%Y-%m-%d", $Sekunden,0,0,0,0,70,0,0,$isdst);
	my                         ($sec, $min, $hour  , $mday, $mon, $year   , $wday, $yday, $isdst) = $Sekunden;
	return strftime("%Y-%m-%d", $sec, $min, $hour+1, $mday, $mon, $year+70, $wday, $yday, 0);
}

sub sec2Time ($) {			# Zahl (Anzahl Sekunden) in Datumfeld umwandeln
	my $Sekunden= $_[0];	# Übergabe Anzahl Sekunden
#	my                                  ($sec     , $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
#	return strftime("%Y-%m-%d_%H:%M:%S", $Sekunden, 0   , 0    , 0    , 0   , 70   , 0    , 0    ,0);
	my                                  ($sec, $min, $hour  , $mday, $mon, $year   , $wday, $yday, $isdst) = $Sekunden;
	return strftime("%Y-%m-%d_%H:%M:%S", $sec, $min, $hour+1, $mday, $mon, $year+70, $wday, $yday, 0);
}

sub hhmm ($) {				# aus Datumsfeld hh:mm herauslösen
	my $Zeit	= 	$_[0];	# Übergabe Zeit
	my @a;
    @a = split("[- :_.]", $Zeit);
    return $a[3].":".$a[4];
}

sub hhmmss2hhmm ($) {		# aus hh:mm:ss --> hh:mm herauslösen
	my $Zeit	= 	$_[0];	# Übergabe Zeit
	$Zeit		= substr($Zeit,0,5);
    return $Zeit;
}

1;
