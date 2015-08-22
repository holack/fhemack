##############################################
package main;

use strict;
use warnings;

sub Lipo_email_Initialize ();	# Initialisierung
sub FormatBR ($;$$);			# formatiert eine Zahl Blau oder Rot
sub FormatGR ($;$$);			# formatiert eine Zahl Grün oder Rot
sub FormatWenn ($$;$$$$);		# formatiert einen Text in Abhängigkeit von einer Bedingung
sub TextWenn ($$;$);			# gibt einen Text in Abhängigkeit von einer Bedingung zurück
sub PCA_Verbrauch ($;$);		# erzeugt eine Zeile für Verbrauch einer PCA301 Steckdose für eMail
sub fb_mail ();					# ???


sub Lipo_email_Initialize {
	return;
}

sub FormatBR ($;$$) {				# formatiert eine Zahl Blau oder Rot
	my $Zahl			= $_[0];	# Übergabe der zu formatierenden Zahl
	;
	my $kleinerBlau		= $_[1];	# Übergabe unter welchen Wert, die Zahl Blau dargestellt wird (Standard 0)
	my $groesserRot		= $_[2];	# Übergabe über  welchen Wert, die Zahl Rot  dargestellt wird (Standard 0)

	if (!defined $kleinerBlau) {	# keine Übergabe
		$kleinerBlau	= 0;		# Standard 0
	}
	if (!defined $groesserRot) {	# keine Übergabe
		$groesserRot	= 0;		# Standard 0
	}

	if ($Zahl < $kleinerBlau) {		# Zahl ist kleiner
		$Zahl = "<b><font color='blue'>".$Zahl."</font></b>";	# Zahl Blau formatieren
	}
	if ($Zahl > $groesserRot) {		# Zahl ist größer
		$Zahl = "<b><font color='red'>" .$Zahl."</font></b>";	# Zahl Rot  formatieren
	}

	return $Zahl;
}

sub FormatGR ($;$$) {				# formatiert eine Zahl Grün oder Rot
	my $Zahl			= $_[0];	# Übergabe der zu formatierenden Zahl
	;
	my $kleinerGruen	= $_[1];	# Übergabe unter welchen Wert, die Zahl Blau dargestellt wird (Standard 0)
	my $groesserRot		= $_[2];	# Übergabe über  welchen Wert, die Zahl Rot  dargestellt wird (Standard 0)

	if (!defined $kleinerGruen) {	# keine Übergabe
		$kleinerGruen	= 0;		# Standard 0
	}
	if (!defined $groesserRot) {	# keine Übergabe
		$groesserRot	= 0;		# Standard 0
	}

	if ($Zahl < $kleinerGruen) {		# Zahl ist kleiner
		$Zahl = "<b><font color='green'>".$Zahl."</font></b>";	# Zahl Blau formatieren
	}
	if ($Zahl > $groesserRot) {		# Zahl ist größer
		$Zahl = "<b><font color='red'>" .$Zahl."</font></b>";	# Zahl Rot  formatieren
	}

	return $Zahl;
}

sub FormatWenn ($$;$$$$) {		# formatiert einen Text in Abhängigkeit von einer Bedingung
	my $Text		= $_[0];	# Übergabe zu formatierenden Text
	my $Bedingung	= $_[1];	# Übergabe Bedingung
	;
	my $FormatJaStart	= $_[2];	# Übergabe Format, welches bei erfüllter Bedingung vor den Text gesetzt wird			(Standard: rot & fett)
	my $FormatJaEnde	= $_[3];	# Übergabe Format, welches bei erfüllter Bedingung nach dem Text angehängt wird			(Standard: Ende rot & fett)
	my $FormatNeinStart	= $_[4];	# Übergabe Format, welches bei nicht erfüllter Bedingung vor den Text gesetzt wird		(Standard: fett)
	my $FormatNeinEnde	= $_[5];	# Übergabe Format, welches bei nicht erfüllter Bedingung nach dem Text angehängt wird	(Standard: Ende fett)

	if (!defined $FormatJaStart) {	# wenn kein Format für erfüllte Bedingung übergeben wurde, Standard: rot & fett
		$FormatJaStart	= "<b><font color='red'>";
	}
	if (!defined $FormatJaEnde) {	# wenn kein Format für erfüllte Bedingung übergeben wurde, Standard: Ende Schrift & fett
		$FormatJaEnde		= "</font></b>";
	}

	if (!defined $FormatNeinStart) {# wenn kein Format für nicht erfüllte Bedingung übergeben wurde, Standard: fett
		$FormatNeinStart	= "<b>";
	}
	if (!defined $FormatNeinEnde) {	# wenn kein Format für nicht erfüllte Bedingung übergeben wurde, Standard: Ende fett
		$FormatNeinEnde	= "</b>";
	}

	if (AnalyzeCommandChain(undef, "{".$Text." ".$Bedingung."}")) {	# wenn Bedingung erfüllt ist
		$Text = $FormatJaStart.$Text.$FormatJaEnde;		# Text formatieren
	}
	else {
		$Text = $FormatNeinStart.$Text.$FormatNeinEnde;	# Text formatieren
	}

	return $Text;
}

sub TextWenn ($$;$) {			# gibt einen Text in Abhängigkeit von einer Bedingung zurück
	my $Bedingung	= $_[0];	# Übergabe Bedingung (bei wahr wird TextJa zurückgegeben, sonst falls angegeben TextNein)
	my $TextJa		= $_[1];	# Übergabe Text, welcher bei erfüllter Bedingung zurückgegeben wird
	;
	my $TextNein	= $_[2];	# optional Übergabe Text, welcher bei nicht erfüllter Bedingung zurückgegeben wird

	if (!defined $TextNein) {	# wenn optional Text nicht übergeben wurde
		$TextNein	= "";
	}

	my $Text		= "";		# Text der zurückgegeben wird
	if (AnalyzeCommandChain(undef, "{".$Bedingung."}") eq 1) {	# Analyse, ob Bedingung erfüllt ist
		$Text = $TextJa;		# Text bei erfüllter Bedingung
	}
	else {
		$Text = $TextNein;		# Text bei nicht erfüllter Bedingung
	}
	return $Text;
}

sub PCA_Verbrauch ($;$) {		# erzeugt eine Zeile für Verbrauch einer PCA301 Steckdose für eMail
	my $PCA301	= $_[0];		# Übergabe Name des PCA301 Steckdose Verbrauchs Dummies
	;
	my $Bedingung	= $_[1];	# Übergabe Bedingung für Formatierung in rot
	if (!defined $Bedingung) {	# keine Übergabe einer Bedingung für Formatierung in rot
		$Bedingung	= "";		# keine Formatierung
	}

	my $Text	= "";			# Ausgabe-Text

	if (ReadingsNum($PCA301,"state",0) > 0) {
		if ($Bedingung eq "") {	# keine Bedingung für Formatierung übergeben
			$Text	= "<b>".ReadingsVal($PCA301,"state",0)." kWh</b>";
		}
		else {
			$Text	= FormatWenn(ReadingsVal($PCA301,"state",0),$Bedingung)."<b> kWh</b>";
		}
		$Text	= $Text.", Nachts: ".ReadingsVal($PCA301,"Nacht_Anteil","");
	}
	else {					# kein Verbrauch
		$Text	= "kein Verbrauch";
	}
	$Text	= $Text.", Vorgestern: ".ReadingsVal($PCA301,"Vorgestern",0)." kWh";

	return $Text;
}

sub fb_mail {
  my $rcpt = $_[0];
  my $subject = $_[1];
  my $text = $_[2];
  system("echo '$text' >./log/99_email.txt");
  system("/sbin/mailer mailer -s '$subject' -t '$rcpt' -i ./log/99_email.txt");
}

1;
