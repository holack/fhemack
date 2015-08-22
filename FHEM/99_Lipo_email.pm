##############################################
package main;

use strict;
use warnings;

sub Lipo_email_Initialize ();	# Initialisierung
sub FormatBR ($;$$);			# formatiert eine Zahl Blau oder Rot
sub FormatGR ($;$$);			# formatiert eine Zahl Gr�n oder Rot
sub FormatWenn ($$;$$$$);		# formatiert einen Text in Abh�ngigkeit von einer Bedingung
sub TextWenn ($$;$);			# gibt einen Text in Abh�ngigkeit von einer Bedingung zur�ck
sub PCA_Verbrauch ($;$);		# erzeugt eine Zeile f�r Verbrauch einer PCA301 Steckdose f�r eMail
sub fb_mail ();					# ???


sub Lipo_email_Initialize {
	return;
}

sub FormatBR ($;$$) {				# formatiert eine Zahl Blau oder Rot
	my $Zahl			= $_[0];	# �bergabe der zu formatierenden Zahl
	;
	my $kleinerBlau		= $_[1];	# �bergabe unter welchen Wert, die Zahl Blau dargestellt wird (Standard 0)
	my $groesserRot		= $_[2];	# �bergabe �ber  welchen Wert, die Zahl Rot  dargestellt wird (Standard 0)

	if (!defined $kleinerBlau) {	# keine �bergabe
		$kleinerBlau	= 0;		# Standard 0
	}
	if (!defined $groesserRot) {	# keine �bergabe
		$groesserRot	= 0;		# Standard 0
	}

	if ($Zahl < $kleinerBlau) {		# Zahl ist kleiner
		$Zahl = "<b><font color='blue'>".$Zahl."</font></b>";	# Zahl Blau formatieren
	}
	if ($Zahl > $groesserRot) {		# Zahl ist gr��er
		$Zahl = "<b><font color='red'>" .$Zahl."</font></b>";	# Zahl Rot  formatieren
	}

	return $Zahl;
}

sub FormatGR ($;$$) {				# formatiert eine Zahl Gr�n oder Rot
	my $Zahl			= $_[0];	# �bergabe der zu formatierenden Zahl
	;
	my $kleinerGruen	= $_[1];	# �bergabe unter welchen Wert, die Zahl Blau dargestellt wird (Standard 0)
	my $groesserRot		= $_[2];	# �bergabe �ber  welchen Wert, die Zahl Rot  dargestellt wird (Standard 0)

	if (!defined $kleinerGruen) {	# keine �bergabe
		$kleinerGruen	= 0;		# Standard 0
	}
	if (!defined $groesserRot) {	# keine �bergabe
		$groesserRot	= 0;		# Standard 0
	}

	if ($Zahl < $kleinerGruen) {		# Zahl ist kleiner
		$Zahl = "<b><font color='green'>".$Zahl."</font></b>";	# Zahl Blau formatieren
	}
	if ($Zahl > $groesserRot) {		# Zahl ist gr��er
		$Zahl = "<b><font color='red'>" .$Zahl."</font></b>";	# Zahl Rot  formatieren
	}

	return $Zahl;
}

sub FormatWenn ($$;$$$$) {		# formatiert einen Text in Abh�ngigkeit von einer Bedingung
	my $Text		= $_[0];	# �bergabe zu formatierenden Text
	my $Bedingung	= $_[1];	# �bergabe Bedingung
	;
	my $FormatJaStart	= $_[2];	# �bergabe Format, welches bei erf�llter Bedingung vor den Text gesetzt wird			(Standard: rot & fett)
	my $FormatJaEnde	= $_[3];	# �bergabe Format, welches bei erf�llter Bedingung nach dem Text angeh�ngt wird			(Standard: Ende rot & fett)
	my $FormatNeinStart	= $_[4];	# �bergabe Format, welches bei nicht erf�llter Bedingung vor den Text gesetzt wird		(Standard: fett)
	my $FormatNeinEnde	= $_[5];	# �bergabe Format, welches bei nicht erf�llter Bedingung nach dem Text angeh�ngt wird	(Standard: Ende fett)

	if (!defined $FormatJaStart) {	# wenn kein Format f�r erf�llte Bedingung �bergeben wurde, Standard: rot & fett
		$FormatJaStart	= "<b><font color='red'>";
	}
	if (!defined $FormatJaEnde) {	# wenn kein Format f�r erf�llte Bedingung �bergeben wurde, Standard: Ende Schrift & fett
		$FormatJaEnde		= "</font></b>";
	}

	if (!defined $FormatNeinStart) {# wenn kein Format f�r nicht erf�llte Bedingung �bergeben wurde, Standard: fett
		$FormatNeinStart	= "<b>";
	}
	if (!defined $FormatNeinEnde) {	# wenn kein Format f�r nicht erf�llte Bedingung �bergeben wurde, Standard: Ende fett
		$FormatNeinEnde	= "</b>";
	}

	if (AnalyzeCommandChain(undef, "{".$Text." ".$Bedingung."}")) {	# wenn Bedingung erf�llt ist
		$Text = $FormatJaStart.$Text.$FormatJaEnde;		# Text formatieren
	}
	else {
		$Text = $FormatNeinStart.$Text.$FormatNeinEnde;	# Text formatieren
	}

	return $Text;
}

sub TextWenn ($$;$) {			# gibt einen Text in Abh�ngigkeit von einer Bedingung zur�ck
	my $Bedingung	= $_[0];	# �bergabe Bedingung (bei wahr wird TextJa zur�ckgegeben, sonst falls angegeben TextNein)
	my $TextJa		= $_[1];	# �bergabe Text, welcher bei erf�llter Bedingung zur�ckgegeben wird
	;
	my $TextNein	= $_[2];	# optional �bergabe Text, welcher bei nicht erf�llter Bedingung zur�ckgegeben wird

	if (!defined $TextNein) {	# wenn optional Text nicht �bergeben wurde
		$TextNein	= "";
	}

	my $Text		= "";		# Text der zur�ckgegeben wird
	if (AnalyzeCommandChain(undef, "{".$Bedingung."}") eq 1) {	# Analyse, ob Bedingung erf�llt ist
		$Text = $TextJa;		# Text bei erf�llter Bedingung
	}
	else {
		$Text = $TextNein;		# Text bei nicht erf�llter Bedingung
	}
	return $Text;
}

sub PCA_Verbrauch ($;$) {		# erzeugt eine Zeile f�r Verbrauch einer PCA301 Steckdose f�r eMail
	my $PCA301	= $_[0];		# �bergabe Name des PCA301 Steckdose Verbrauchs Dummies
	;
	my $Bedingung	= $_[1];	# �bergabe Bedingung f�r Formatierung in rot
	if (!defined $Bedingung) {	# keine �bergabe einer Bedingung f�r Formatierung in rot
		$Bedingung	= "";		# keine Formatierung
	}

	my $Text	= "";			# Ausgabe-Text

	if (ReadingsNum($PCA301,"state",0) > 0) {
		if ($Bedingung eq "") {	# keine Bedingung f�r Formatierung �bergeben
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
