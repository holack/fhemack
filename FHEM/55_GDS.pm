# $Id: 55_GDS.pm 8677 2015-06-01 17:11:36Z betateilchen $
####################################################################################################
#
#	55_GDS.pm
#
#	An FHEM Perl module to retrieve data from "Deutscher Wetterdienst"
#
#	Copyright: betateilchen ®
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
####################################################################################################

package main;

use strict;
use warnings;
use feature qw/say switch/;
use Time::HiRes qw(gettimeofday);
use Text::CSV;
eval "use Coro::LWP";
Log 4,"GDS: using Coro::LWP" unless $@;
use Net::FTP;
use List::MoreUtils 'first_index'; 
use XML::Simple;
use HttpUtils;
require LWP::UserAgent;

no if $] >= 5.017011, warnings => 'experimental';

my ($bulaList, $cmapList, %rmapList, $fmapList, %bula2bulaShort, %bulaShort2dwd, %dwd2Dir, %dwd2Name,
	$alertsXml, %capCityHash, %capCellHash, $sList, $aList);

my $tempDir = "/tmp/";

####################################################################################################
#
# Main routines
#
####################################################################################################


sub GDS_Initialize($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $found;

	$hash->{DefFn}		=	"GDS_Define";
	$hash->{UndefFn}	=	"GDS_Undef";
	$hash->{GetFn}		=	"GDS_Get";
	$hash->{SetFn}		=	"GDS_Set";
	$hash->{ShutdownFn}	=	"GDS_Shutdown";
	$hash->{AttrFn}		=	"GDS_Attr";
	$hash->{AttrList}	=	"disable:0,1 ".
							"gdsFwName gdsFwType:0,1,2,3,4,5,6,7 gdsAll:0,1 ".
							"gdsDebug:0,1 gdsLong:0,1 gdsPolygon:0,1 ".
							"gdsSetCond gdsPassiveFtp:0,1 ".
							$readingFnAttributes;

	$tempDir = "c:\\temp\\" if($^O eq "MSWin32");

	fillMappingTables($hash);
	initDropdownLists($hash);

	if($name){
		(undef, $found) = retrieveFile($hash,"conditions");
		if($found){
			$sList = getListStationsDropdown($hash)
		} else {
			Log3($name, 2, "GDS $name: No datafile (conditions) found");
		}

		(undef, $found) = retrieveFile($hash,"alerts");
		if($found){
			($aList, undef) = buildCAPList($hash);
		} else {
			Log3($name, 2, "GDS $name: No datafile (alerts) found");
		}
	}
}

sub GDS_Define($$$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	my ($found, $dummy);

	return "syntax: define <name> GDS <username> <password>" if(int(@a) != 4 ); 
	my $name = $hash->{NAME};

	$hash->{helper}{USER}		= $a[2];
	$hash->{helper}{PASS}		= $a[3];
	$hash->{helper}{URL}		= "ftp-outgoing2.dwd.de";
	$hash->{helper}{INTERVAL} = 1200;

	Log3($name, 4, "GDS $name: created");
	Log3($name, 4, "GDS $name: tempDir=".$tempDir);

    GDS_addExtension("GDS_CGI","gds","GDS Files");

	fillMappingTables($hash);
	initDropdownLists($hash);

	(undef, $found) = retrieveFile($hash,"conditions");
	if($found){
		$sList = getListStationsDropdown($hash)
	} else {
		Log3($name, 2, "GDS $name: No datafile (conditions) found");
	}
	retrieveFile($hash,"alerts");
	if($found){
		($aList, undef) = buildCAPList($hash);
	} else {
		Log3($name, 3, "GDS $name: No datafile (alerts) found");
	}
	readingsSingleUpdate($hash, '_tzOffset', _calctz(time,localtime(time))*3600, 0);
	readingsSingleUpdate($hash, 'state', 'active',1);

	return undef;
}

sub GDS_Undef($$) {
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};
	RemoveInternalTimer($hash);
    my $url = '/gds';
    delete $data{FWEXT}{$url} if int(devspec2array('TYPE=GDS')) == 1;
	return undef;
}

sub GDS_Shutdown($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 ($name,4,"GDS $name: shutdown requested");
	return undef;
}

sub GDS_Set($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $usage =	"Unknown argument, choose one of clear:alerts,all help:noArg rereadcfg:noArg update:noArg ".
				"conditions:".$sList." ";

	readingsSingleUpdate($hash, '_tzOffset', _calctz(time,localtime(time))*3600, 0);

	my $command		= lc($a[1]);
	my $parameter	= $a[2] if(defined($a[2]));

	my ($result, $next);

	$hash->{LOCAL} = 1;

	return $usage if $command eq '?';

	if(IsDisabled($name)) {
		readingsSingleUpdate($hash, 'state', 'disabled', 0);
		return "GDS $name is disabled. Aborting..." if IsDisabled($name);
	}

	readingsSingleUpdate($hash, 'state', 'active', 0);

	given($command) {
		when("clear"){
			CommandDeleteReading(undef, "$name a_.*");
			CommandDeleteReading(undef, "$name c_.*") if(defined($parameter) && $parameter eq "all");
			CommandDeleteReading(undef, "$name g_.*") if(defined($parameter) && $parameter eq "all");
			}
		when("help"){
			$result = setHelp();
			break;
			}

		when("rereadcfg"){
			eval {
				retrieveFile($hash,"conditions");
				$sList = getListStationsDropdown($hash);
			}; 
			eval {
				retrieveFile($hash,"alerts");
				($aList, undef) = buildCAPList($hash);
			}; 
			break;
			}

		when("update"){
			RemoveInternalTimer($hash);
			GDS_GetUpdate($hash);
			break;
			}

		when("conditions"){
			readingsSingleUpdate($hash, "state", "active",1);
			retrieveConditions($hash, "c", @a);
            $attr{$name}{gdsSetCond} = ReadingsVal($name,'c_stationName',undef);
			$next = gettimeofday()+$hash->{helper}{INTERVAL};
			readingsSingleUpdate($hash, "c_nextUpdate", localtime($next), 1);
			RemoveInternalTimer($hash);
			InternalTimer($next, "GDS_GetUpdate", $hash, 1);
			break;
			}

		default { return $usage; };
	}
	return $result;
}

sub GDS_Get($@) {
	my ($hash, @a) = @_;
	my $command		= lc($a[1]);
	my $parameter	= $a[2] if(defined($a[2]));
	my $name = $hash->{NAME};

	$hash->{LOCAL} = 1;

	my $usage = "Unknown argument $command, choose one of help:noArg rereadcfg:noArg ".
				"list:stations,capstations,data ".
				"alerts:".$aList." ".
				"conditions:".$sList." ".
				"conditionsmap:".$cmapList." ".
				"forecastsmap:".$fmapList." ".
				"radarmap:".$cmapList." ".
				"warningsmap:"."Deutschland,Bodensee,".$bulaList." ".
				"warnings:".$bulaList;

	return $usage if $command eq '?';

	if(IsDisabled($name)) {
		readingsSingleUpdate($hash, 'state', 'disabled', 0);
		return "GDS $name is disabled. Aborting..." if IsDisabled($name);
	}

	readingsSingleUpdate($hash, 'state', 'active', 0);
	readingsSingleUpdate($hash, '_tzOffset', _calctz(time,localtime(time))*3600, 0);

	my ($result, @datensatz, $found);

	given($command) {

		when("conditionsmap"){
			# retrieve map: current conditions
			retrieveFile($hash,$command,$parameter);
			break;
		}

		when("forecastsmap"){
			# retrieve map: forecasts
			retrieveFile($hash,$command,$parameter);
			break;
		}

		when("warningsmap"){
			# retrieve map: warnings
			retrieveFile($hash,$command,$parameter);
			break;
		}

		when("radarmap"){
			# retrieve map: radar
			$parameter = ucfirst($parameter);
			retrieveFile($hash,$command,$parameter,$rmapList{$parameter});
			break;
			}

		when("help"){
			$result = getHelp();
			break;
			}

		when("list"){
			given($parameter){
				when("capstations")	{ $result = getListCapStations($hash,$parameter); break,}
				when("data")		{ $result = getListData($hash); break; }
				when("stations")	{ $result = getListStationsText($hash); break; }
				default				{ $usage  = "get <name> list <parameter>"; return $usage; }
			}
			break;
			}

		when("alerts"){
			if($parameter =~ y/0-9// == length($parameter)){
				while ( my( $key, $val ) = each %capCellHash ) {
					push @datensatz,$val if $key =~ m/^$parameter/;
				}
#				push @datensatz,$capCellHash{$parameter};
			} else {
				push @datensatz,$capCityHash{$parameter};
			}
			CommandDeleteReading(undef, "$name a_.*");
			if($datensatz[0]){
				my $anum = 0;
				foreach(@datensatz) {
					decodeCAPData($hash,$_,$anum);
					$anum++;
				};
				readingsSingleUpdate($hash,'a_count',$anum,1);
			} else {
				$result = "Keine Warnmeldung für die gesuchte Region vorhanden.";
			}
			break;
			}

		when("headlines"){
			$result = gdsHeadlines($name);
			break;
			}

		when("conditions"){
			retrieveConditions($hash, "g", @a);
			break;
			}

		when("rereadcfg"){
			retrieveFile($hash,"conditions");
			retrieveFile($hash,"alerts");
			initDropdownLists($hash);
			break;
			}

		when("warnings"){
			my $vhdl;
			$result =	"     VHDL30 = current          |     VHDL31 = weekend or holiday\n".
						"     VHDL32 = preliminary      |     VHDL33 = cancel VHDL32\n".
						sepLine(31)."+".sepLine(38);
			for ($vhdl=30; $vhdl <=33; $vhdl++){
				(undef, $found) = retrieveFile($hash, $command, $parameter, $vhdl,1);
				if($found){
					$result .= retrieveTextWarn($hash);
					$result .= "\n".sepLine(70);
				}
			}
			$result .= "\n\n";
			break;
			}

		default { return $usage; };
	}
	return $result;
}

sub GDS_Attr(@){
	my @a = @_;
	my $hash = $defs{$a[1]};
	my (undef, $name, $attrName, $attrValue) = @a;
	given($attrName){
		when("gdsDebug"){
			CommandDeleteReading(undef, "$name _dF.*") if($attrValue != 1);
			break;
			}
		when("gdsSetCond"){
			my $dummy = "gdsDummy_$name";
			CommandDefine(undef, "$dummy at +00:00:30 set $name conditions $attrValue");
			$defs{$dummy}{TEMPORARY} = 1;
			$attr{$dummy}{room} = 'hidden';
			break;
			}
		default {$attr{$name}{$attrName} = $attrValue;}
	}
	if(IsDisabled($name)) {
		readingsSingleUpdate($hash, 'state', 'disabled', 0);
	} else {
		readingsSingleUpdate($hash, 'state', 'active', 0);
	}
	return "";
}

sub GDS_GetUpdate($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my (@a, $next);

	if(IsDisabled($name)) {
		readingsSingleUpdate($hash, 'state', 'disabled', 0);
		Log3 ($name, 2, "GDS $name is disabled, data update cancelled.");
	} else {
		readingsSingleUpdate($hash, 'state', 'active', 0);
		push @a, undef;
		push @a, undef;
		push @a, ReadingsVal($name, "c_stationName", "");
		retrieveConditions($hash, "c", @a);
	}

	$next = gettimeofday()+$hash->{helper}{INTERVAL};
	readingsSingleUpdate($hash, "c_nextUpdate", localtime($next), 1);
	InternalTimer($next, "GDS_GetUpdate", $hash, 1);

	return 1;
}

sub GDS_addExtension($$$) {
    my ($func,$link,$friendlyname)= @_;
  
    my $url = "/" . $link;
    Log3(undef,4,"Register gds webservice in FWEXT");
    $data{FWEXT}{$url}{FUNC} = $func;
    $data{FWEXT}{$url}{LINK} = "+$link";
    $data{FWEXT}{$url}{NAME} = $friendlyname;
    $data{FWEXT}{$url}{FORKABLE} = 0;
}

sub GDS_CGI {
  my ($request) = @_;
  my ($name,$ext)= GDS_splitRequest($request);
  if(defined($name)) {
     my $filename= "$tempDir/$name.$ext";
     my $MIMEtype= filename2MIMEType($filename);
     my @contents;
     if(open(INPUTFILE, $filename)) {
       binmode(INPUTFILE);
       @contents= <INPUTFILE>;
       close(INPUTFILE);
       return("$MIMEtype; charset=utf-8", join("", @contents));
     } else {
       return("text/plain; charset=utf-8", "File not found: $filename");
     }
  } else {
    return GDS_Overview();
  }
}

sub GDS_splitRequest($) {
  my ($request) = @_;

  if($request =~ /^.*\/gds$/) {
    # http://localhost:8083/fhem/gds2
    return (undef,undef); # name, ext
  } else {
    my $call= $request;
    $call =~ s/^.*\/gds\/([^\/]*)$/$1/;
    my $name= $call;
    $name =~ s/^(.*)\.(jpg)$/$1/;
    my $ext= $call;
    $ext =~ s/^$name\.(.*)$/$1/;
    return ($name,$ext);
  }
}

sub GDS_Overview {
  my ($name, $url);
  my $html= GDS_HTMLHead("GDS Overview") . "<body>\n\n";
  foreach my $def (sort keys %defs) {
     if($defs{$def}{TYPE} eq "GDS") {
        $name= $defs{$def}{NAME};
        $url   = GDS_getURL();
        $html .= "$name<br>\n<ul>\n";
        $html .= "<a href=\"$url/gds/$name\_conditionsmap.jpg\" target=\"_blank\">Aktuelle Wetterkarte: Wetterlage</a><br/>\n";
        $html .= "<a href=\"$url/gds/$name\_forecastsmap.jpg\" target=\"_blank\">Aktuelle Wetterkarte: Vorhersage</a><br/>\n";
        $html .= "<a href=\"$url/gds/$name\_warningsmap.jpg\" target=\"_blank\">Aktuelle Wetterkarte: Warnungen</a><br/>\n";
        $html .= "<a href=\"$url/gds/$name\_radarmap.jpg\" target=\"_blank\">Aktuelle Wetterkarte: Radarkarte</a><br/>\n";
        $html.= "</ul>\n\n";
    }
  }
  $html.="</body>\n" . GDS_HTMLTail();

  return ("text/html; charset=utf-8", $html);
}

sub GDS_HTMLHead($) {
  my ($title) = @_;
  my $doctype= '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">';
  my $xmlns= 'xmlns="http://www.w3.org/1999/xhtml"';
  my $code= "$doctype\n<html $xmlns>\n<head>\n<title>$title</title>\n</head>\n";
  return $code;
}

sub GDS_HTMLTail {
  return "</html>";
}

sub GDS_getURL {
  my $proto = (AttrVal($FW_wname, 'HTTPS', 0) == 1) ? 'https' : 'http';
  return $proto."://$FW_httpheader{Host}$FW_ME"; #".$FW_ME;
}

####################################################################################################
#
#	Tools
#
####################################################################################################


sub getHelp(){
	return	"Use one of the following commands:\n".
			sepLine(35)."\n".
			"get <name> alerts <region>\n".
			"get <name> conditions <stationName>\n".
			"get <name> help\n".
			"get <name> list capstations|stations|data\n".
			"get <name> rereadcfg\n".
			"get <name> warnings <region>\n";
}

sub getListData($){
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my ($line, @a);
	open WXDATA, $tempDir.$name."_conditions";
	while (chomp($line = <WXDATA>)) {
		push @a, latin1ToUtf8($line);
	}
	close WXDATA;

	return join("\n", @a);
}

sub getListStationsText($){
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my ($line, @a);
	open WXDATA, $tempDir.$name."_conditions";
	while (chomp($line = <WXDATA>)) {
		push @a, substr(latin1ToUtf8($line),0,19);
	}
	close WXDATA;

	splice(@a,0,6);
	splice(@a,first_index { /Höhe/ } @a);
	splice(@a,-1);
	@a = sort(@a);
	unshift(@a, "Use one of the following stations:", sepLine(40));

	return join("\n", @a);
}

sub getListCapStations($$){
	my ($hash, $command) = @_;
	my $name = $hash->{NAME};
	my (%capHash, $file, $csv, @columns, $err, $key, $cList);

	$file = $tempDir.'capstations.csv';
	$csv = Text::CSV->new( { binary => 1 } );
	$csv->sep_char (";");

	# prüfen, ob CSV schon vorhanden,
	# falls nicht: vom Server holen
	if (!-e $tempDir."caplist.csv"){
		retrieveFile($hash, $command);
	}

	# CSV öffnen und parsen
	open (CSV, "<", $file) or die $!;
	while (<CSV>) {
		next if ($. == 1);
		if ($csv->parse($_)) {
			@columns = $csv->fields();
			$capHash{latin1ToUtf8($columns[4])} = $columns[0];
		} else {
			$err = $csv->error_input;
			print "Failed to parse line: $err";
		}
	}
	close CSV;

	# Ausgabe sortieren und zusammenstellen
	foreach $key (sort keys %capHash) {
		$cList .= $capHash{$key}."\t".$key."\n";
	}
	return $cList;
}

sub setHelp(){
	return	"Use one of the following commands:\n".
			sepLine(35)."\n".
			"set <name> clear alerts|all\n".
			"set <name> conditions <stationName>\n".
			"set <name> rereadcfg\n".
			"set <name> update\n".
			"set <name> help\n";
}

sub buildCAPList(@){
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $xml			= new XML::Simple;
	$alertsXml		= undef;
	eval	{	
		$alertsXml		= $xml->XMLin($tempDir.$name.'_alerts', KeyAttr => {}, ForceArray => [ 'info', 'eventCode', 'area', 'geocode' ]);
		};
    if ($@) {
      Log3($name,1,'GDS: error analyzing alerts XML:'.$@);
      return (undef,undef);
    }
	my $info		= 0;
	my $area		= 0;
	my $record		= 0;
	my $n			= 0;
	my ($capCity, $capCell, $capExit, $capEvt, @a, $list);

	%capCityHash	= ();
	%capCellHash	= ();
	$aList			= undef;
	
	while(1) {
		$area = 0;
		while(1){
			$capCity = $alertsXml->{info}[$info]{area}[$area]{areaDesc};
			$capExit = $alertsXml->{info}[$info]{event};
			if(!$capCity) {last;}
			$capCell = findCAPWarnCellId($info, $area);
			$n = 100*$info+$area;
			$capCity = latin1ToUtf8($capCity.' '.$capExit);
			push @a, $capCity;
			$capCity =~ s/\s/_/g;
			$capCityHash{$capCity} = $n;
			$capCellHash{"$capCell$n"} = $n;
			$area++;
			$record++;
			$capCity = undef;
		}
		if(!$capExit){last;}
		$info++;
	}

	@a = sort(@a);
	$list = join(",", @a);
	$list =~ s/\s/_/g;
	$list = "No_alerts_published!" if !$record;
	return ($list, $record);
}

sub decodeCAPData($$$){
	my ($hash, $datensatz, $anum) = @_;
	my $name		= $hash->{NAME};
	my $info		= int($datensatz/100);
	my $area		= $datensatz-$info*100;

	my (%readings, @dummy, $i, $k, $n, $v, $t);

	my $_gdsAll		= AttrVal($name,"gdsAll", 0);
	my $_gdsDebug	= AttrVal($name,"gdsDebug", 0);
	my $_gdsLong	= AttrVal($name,"gdsLong", 0);
	my $_gdsPolygon	= AttrVal($name,"gdsPolygon", 0);

	Log3($name, 4, "GDS $name: Decoding CAP record #".$datensatz);

# topLevel informations
	@dummy = split(/\./, $alertsXml->{identifier});

	$readings{"a_".$anum."_identifier"}		= $alertsXml->{identifier}	if($_gdsAll || $_gdsDebug);
	$readings{"a_".$anum."_idPublisher"}	= $dummy[5]					if($_gdsAll);
	$readings{"a_".$anum."_idSysten"}		= $dummy[6]					if($_gdsAll);
	$readings{"a_".$anum."_idTimeStamp"}	= $dummy[7]					if($_gdsAll);
	$readings{"a_".$anum."_idIndex"}		= $dummy[8]					if($_gdsAll);
	$readings{"a_".$anum."_sent"}			= $alertsXml->{sent};
	$readings{"a_".$anum."_status"}			= $alertsXml->{status};
	$readings{"a_".$anum."_msgType"}		= $alertsXml->{msgType};

# infoSet informations
	$readings{"a_".$anum."_language"}		= $alertsXml->{info}[$info]{language}		if($_gdsAll);
	$readings{"a_".$anum."_category"}		= $alertsXml->{info}[$info]{category};
	$readings{"a_".$anum."_event"}			= $alertsXml->{info}[$info]{event};
	$readings{"a_".$anum."_responseType"}	= $alertsXml->{info}[$info]{responseType};
	$readings{"a_".$anum."_urgency"}		= $alertsXml->{info}[$info]{urgency}		if($_gdsAll);
	$readings{"a_".$anum."_severity"}		= $alertsXml->{info}[$info]{severity}		if($_gdsAll);
	$readings{"a_".$anum."_certainty"}		= $alertsXml->{info}[$info]{certainty}		if($_gdsAll);

# eventCode informations
# loop through array
	$i = 0;
	while(1){
		($n, $v) = (undef, undef);
		$n = $alertsXml->{info}[$info]{eventCode}[$i]{valueName};
		if(!$n) {last;}
		$n = "a_".$anum."_eventCode_".$n;
		$v = $alertsXml->{info}[$info]{eventCode}[$i]{value};
		$readings{$n} .= $v." " if($v);
		$i++;
	}

# time/validity informations
	$readings{"a_".$anum."_effective"}		= $alertsXml->{info}[$info]{effective}					if($_gdsAll);
	$readings{"a_".$anum."_onset"}			= $alertsXml->{info}[$info]{onset};
	$readings{"a_".$anum."_expires"}		= $alertsXml->{info}[$info]{expires};
	$readings{"a_".$anum."_valid"}			= checkCAPValid($readings{"a_".$anum."_onset"},$readings{"a_".$anum."_expires"});
	$readings{"a_".$anum."_onset_local"}	= capTrans($readings{"a_".$anum."_onset"});
	$readings{"a_".$anum."_expires_local"}	= capTrans($readings{"a_".$anum."_expires"});
	$readings{"a_".$anum."_sent_local"}		= capTrans($readings{"a_".$anum."_sent"});

	$readings{a_valid} = ReadingsVal($name,'a_valid',0) || $readings{"a_".$anum."_valid"};

# text informations
	$readings{"a_".$anum."_headline"}		= $alertsXml->{info}[$info]{headline};
	$readings{"a_".$anum."_description"}	= $alertsXml->{info}[$info]{description}				if($_gdsAll || $_gdsLong);
	$readings{"a_".$anum."_instruction"}	= $alertsXml->{info}[$info]{instruction} 				if($readings{"a_".$anum."_responseType"} eq "Prepare" 
																						&& ($_gdsAll || $_gdsLong));

# area informations
	$readings{"a_".$anum."_areaDesc"} 		=  $alertsXml->{info}[$info]{area}[$area]{areaDesc};
	$readings{"a_".$anum."_areaPolygon"}	=  $alertsXml->{info}[$info]{area}[$area]{polygon}		if($_gdsAll || $_gdsPolygon);

# area geocode informations
# loop through array
	$i = 0;
	while(1){
		($n, $v) = (undef, undef);
		$n = $alertsXml->{info}[$info]{area}[$area]{geocode}[$i]{valueName};
		if(!$n) {last;}
		$n = "a_".$anum."_geoCode_".$n;
		$v = $alertsXml->{info}[$info]{area}[$area]{geocode}[$i]{value};
		$readings{$n} .= $v." " if($v);
		$i++;
	}

	$readings{"a_".$anum."_altitude"}		= $alertsXml->{info}[$info]{area}[$area]{altitude}		if($_gdsAll);
	$readings{"a_".$anum."_ceiling"}		= $alertsXml->{info}[$info]{area}[$area]{ceiling}		if($_gdsAll);

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "_dataSource", "Quelle: Deutscher Wetterdienst");
	while(($k, $v) = each %readings){
		readingsBulkUpdate($hash, $k, latin1ToUtf8($v)) if(defined($v)); }
	readingsEndUpdate($hash, 1);
	eval {readingsSingleUpdate($hash, 'a_'.$anum.'_eventCode_AREA_COLOR_hex', _rgbd2h(ReadingsVal($name, 'a_'.$anum.'_eventCode_AREA_COLOR', '')),0);};

	return;
}

# sub
# _calctz($@)
# {
  # my ($nt,@lt) = @_;

  # my $off = $lt[2]*3600+$lt[1]*60+$lt[0];
  # $off = 12*3600-$off;
  # $nt += $off;  # This is noon, localtime

  # my @gt = gmtime($nt);

  # return (12-$gt[2]);
# }

sub checkCAPValid($$){
	my ($onset,$expires) = @_;
	my $valid = 0;
	my $offset = _calctz(time,localtime(time))*3600; # used from 99_SUNRISE_EL
    my $t = (time - $offset);

	$onset =~ s/T/ /;
	$onset =~ s/\+/ \+/;
	$onset = time_str2num($onset);

	$expires =~ s/T/ /;
	$expires =~ s/\+/ \+/;
	$expires = time_str2num($expires);

	$valid = 1 if($onset lt $t && $expires gt $t);
	return $valid;
}

sub capTrans($) {
	my ($t) = @_;
	my $valid = 0;
	my $offset = _calctz(time,localtime(time))*3600; # used from 99_SUNRISE_EL
	$t =~ s/T/ /;
	$t =~ s/\+/ \+/;
	$t = time_str2num($t);
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($t+$offset);
	$mon  += 1;
	$year += 1900;
	$t = sprintf "%02s.%02s.%02s %02s:%02s:%02s", $mday, $mon, $year, $hour, $min, $sec;
	return $t;
}

sub findCAPWarnCellId($$){
	my ($info, $area) = @_;
	my $i = 0;
	while($i < 100){
		if($alertsXml->{info}[$info]{area}[$area]{geocode}[$i]{valueName} eq "WARNCELLID"){
			return $alertsXml->{info}[$info]{area}[$area]{geocode}[$i]{value};
			last;
		}
		$i++;
	}
}

sub retrieveTextWarn($){
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my ($line, @a);
	open WXDATA, $tempDir.$name."_warnings";
	while (chomp($line = <WXDATA>)) { 
		push @a, latin1ToUtf8($line); }
	close WXDATA;
	return join("", @a);
}

sub retrieveConditions($$@){
	my ($hash, $prefix, @a) = @_;
	my $name		= $hash->{NAME};
	my $user		= $hash->{helper}{USER};
	my $pass		= $hash->{helper}{PASS};
	(my $myStation	= utf8ToLatin1($a[2])) =~ s/_/ /g; # replace underscore in stationName by space
	my $searchLen	= length($myStation);

	my ($debug, $dataFile, $found, $line, $item, %pos, %alignment, %wx, %cread, $k, $v);

	$debug = AttrVal($name, "gdsDebug", 0);

	Log3($name, 4, "GDS $name: Retrieving conditions data");
	
	($dataFile, $found) = retrieveFile($hash,"conditions",undef,undef,1);
	open WXDATA, $tempDir.$name."_conditions";
	while (chomp($line = <WXDATA>)) {
		map {s/\r//g;} ($line);
		if ($line =~ /Station/) {		# Header line... find out data positions
			@a = split(/\s+/, $line);
			foreach $item (@a) {
				$pos{$item} = index($line, $item);
			}
		}
		if (index(substr(lc($line),0,$searchLen), substr(lc($myStation),0,$searchLen)) != -1) { last; }
	}
	close WXDATA;

	%alignment = ("Station" => "l", "H\xF6he" => "r", "Luftd." => "r", "TT" => "r", "Tn12" => "r", "Tx12" => "r", 
	"Tmin" => "r", "Tmax" => "r", "Tg24" => "r", "Tn24" => "r", "Tm24" => "r", "Tx24" => "r", "SSS24" => "r", "SGLB24" => "r", 
	"RR1" => "r", "RR12" => "r", "RR24" => "r", "SSS" => "r", "DD" => "r", "FF" => "r", "FX" => "r", "Wetter/Wolken" => "l", "B\xF6en" => "l");
	
	foreach $item (@a) {
		Log3($hash, 4, "conditions item: $item");
		$wx{$item} = &readItem($line, $pos{$item}, $alignment{$item}, $item);
	}

	%cread = ();
	$cread{"_dataSource"} = "Quelle: Deutscher Wetterdienst";

	if(length($wx{"Station"})){
		$cread{$prefix."_stationName"}	= $wx{"Station"};
		$cread{$prefix."_altitude"}			= $wx{"H\xF6he"};
		$cread{$prefix."_pressure-nn"}	= $wx{"Luftd."};
		$cread{$prefix."_temperature"}	= $wx{"TT"};
		$cread{$prefix."_tMinAir12"}		= $wx{"Tn12"};
		$cread{$prefix."_tMaxAir12"}		= $wx{"Tx12"};
		$cread{$prefix."_tMinGrnd24"}		= $wx{"Tg24"};
		$cread{$prefix."_tMinAir24"}		= $wx{"Tn24"};
		$cread{$prefix."_tAvgAir24"}		= $wx{"Tm24"};
		$cread{$prefix."_tMaxAir24"}		= $wx{"Tx24"};
		$cread{$prefix."_tempMin"}			= $wx{"Tmin"};
		$cread{$prefix."_tempMax"}			= $wx{"Tmax"};
		$cread{$prefix."_rain1h"}				= $wx{"RR1"};
		$cread{$prefix."_rain12h"}			= $wx{"RR12"};
		$cread{$prefix."_rain24h"}			= $wx{"RR24"};
		$cread{$prefix."_snow"}					= $wx{"SSS"};
		$cread{$prefix."_sunshine"}			= $wx{"SSS24"};
		$cread{$prefix."_solar"}				= $wx{"SGLB24"};
		$cread{$prefix."_windDir"}			= $wx{"DD"};
		$cread{$prefix."_windSpeed"}		= $wx{"FF"};
		$cread{$prefix."_windPeak"}			= $wx{"FX"};
		$cread{$prefix."_weather"}			= $wx{"Wetter\/Wolken"};
		$cread{$prefix."_windGust"}			= $wx{"B\xF6en"};
	} else {
		$cread{$prefix."_stationName"}	= "unknown: $myStation";
	}

#	CommandDeleteReading(undef, "$name $prefix"."_.*");
	readingsBeginUpdate($hash);
	while(($k, $v) = each %cread) { 
	readingsBulkUpdate($hash, $k, latin1ToUtf8($v)) if(defined($v)); }
	readingsEndUpdate($hash, 1);

	return ;
}

sub retrieveFile($$;$$$){
#
# request = type, e.g. alerts, conditions, warnings
# parameter = additional selector, e.g. Bundesland
#
	my ($hash, $request, $parameter, $parameter2, $useFtp) = @_;
	my $name		= $hash->{NAME};
	my $user		= $hash->{helper}{USER};
	my $pass		= $hash->{helper}{PASS};
	my $proxyName	= AttrVal($name, "gdsProxyName", "");
	my $proxyType	= AttrVal($name, "gdsProxyType", "");
	my $passive		= AttrVal($name, "gdsPassiveFtp", 0);
	my $debug		= AttrVal($name, "gdsDebug",0);

	my ($dwd, $dir, $ftp, @files, $dataFile, $targetFile, $found, $readingName);
	
	my $urlString =	"ftp://$user:$pass\@ftp-outgoing2.dwd.de/";
	my $ua;
	eval { $ua = LWP::UserAgent->new; };

	if(!defined($ua)) {
		Log3($name, 1, "GDS $name: LWP not available!");
		readingsSingleUpdate($hash, 'LWP error', 'LWP not available!',1);
		return;
	}

	$ua->timeout(10);
	$ua->env_proxy;

	given($request){

		when("capstations"){
			$dir = "gds/help/";
			$dwd = "legend_warnings_CAP_WarnCellsID.csv";
			$targetFile = $tempDir.$request.".csv";
			break;
		}

		when("conditionsmap"){
			$dir = "gds/specials/observations/maps/germany/";
			$dwd = $parameter."*";
			$targetFile = $tempDir.$name."_".$request.".jpg";
			break;
		}

		when("forecastsmap"){
			$dir = "gds/specials/forecasts/maps/germany/";
			$dwd = $parameter."*";
			$targetFile = $tempDir.$name."_".$request.".jpg";
			break;
		}

		when("warningsmap"){
			if(length($parameter) != 2){
				$parameter = $bula2bulaShort{lc($parameter)};
			}
			$dwd = "Schilder".$dwd2Dir{$bulaShort2dwd{lc($parameter)}}.".jpg";
			$dir = "gds/specials/warnings/maps/";
			$targetFile = $tempDir.$name."_".$request.".jpg";
			break;
		}

		when("radarmap"){
			$dir = "gds/specials/radar/".$parameter2;
			$dwd = "Webradar_".$parameter."*";
			$targetFile = $tempDir.$name."_".$request.".jpg";
			break;
		}

		when("alerts"){
			$dir = "gds/specials/warnings/xml/PVW/";
			$dwd = "Z_CAP*";
			$targetFile = $tempDir.$name."_".$request;
			break;
			}

		when("conditions"){
			$useFtp = 1;
			$dir = "gds/specials/observations/tables/germany/";
			$dwd = "*";
			$targetFile = $tempDir.$name."_".$request;
			break;
			}

		when("warnings"){
			$useFtp = 1;
			if(length($parameter) != 2){
				$parameter = $bula2bulaShort{lc($parameter)};
			}
			$dwd = $bulaShort2dwd{lc($parameter)};
			$dir = $dwd2Dir{$dwd};
			$dwd = "VHDL".$parameter2."_".$dwd."*";
			$dir = "gds/specials/warnings/".$dir."/";
			$targetFile = $tempDir.$name."_".$request;
			break;
			}
	}

	Log3($name, 4, "GDS $name: searching for $dir".$dwd." on DWD server");
	$urlString .= $dir;

	$found = 0;
	eval {
		$ftp = Net::FTP->new(	"ftp-outgoing2.dwd.de",
								Debug => 0,
								Timeout => 10,
								Passive => $passive,
								FirewallType => $proxyType,
								Firewall => $proxyName);
		Log3($name, 4, "GDS $name: ftp connection established.");
		if(defined($ftp)){
			$ftp->login($user, $pass);
			$ftp->cwd("$dir");
			@files = undef;
			@files = $ftp->ls($dwd);
			if(@files){
				Log3($name, 4, "GDS $name: filelist found.");
				@files = sort(@files);
				$dataFile = $files[-1];
				$urlString .= $dataFile;
				Log3($name, 4, "GDS $name: retrieving $dataFile");
				if($useFtp){
					Log3($name, 4, "GDS $name: using FTP for retrieval");
					$ftp->get($files[-1], $targetFile);
				} else {
					Log3($name, 4, "GDS $name: using HTTP for retrieval");
					$ua->get($urlString,':content_file' => $targetFile);
				}
				$found = 1;
			} else { 
				Log3($name, 4, "GDS $name: filelist not found.");
				$found = 0;
			}
			$ftp->quit;
		}
		Log3($name, 4, "GDS $name: updating readings.");
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "_dataSource",		"Quelle: Deutscher Wetterdienst");
		readingsBulkUpdate($hash, "_dF_".$request, $dataFile) if(AttrVal($name, "gdsDebug", 0));
		readingsEndUpdate($hash, 1);
	};
	return ($dataFile, $found);
}

sub getListStationsDropdown($){
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my ($line, $liste, @a);

	open WXDATA, $tempDir.$name."_conditions";
	while (chomp($line = <WXDATA>)) {
		push @a, trim(substr(latin1ToUtf8($line),0,19));
	}
	close WXDATA;

	splice(@a,0,6);
	splice(@a,first_index { /Höhe/ } @a);
	splice(@a,-1);
	@a = sort(@a);

	$liste = join(",", @a);
	$liste =~ s/\s+,/,/g; # replace multiple spaces followed by comma with comma
	$liste =~ s/\s/_/g;   # replace spaces in stationName with underscore for list in frontende
	return $liste;
}

sub readItem {
	my ($line, $pos, $align, $item)  = @_;
	my $x;
	
	if ($align eq "l") {
		$x = substr($line, $pos);
		$x =~ s/  .+$//g;	# after two spaces => next field
	}
	if ($align eq "r") {
		$pos += length($item);
		$x = substr($line, 0, $pos);
		$x =~ s/^.+  //g;	# remove all before the item
	}
	return $x;
}

sub sepLine($) {
	my ($len) = @_;
	my ($output, $i);
	for ($i=0; $i<$len; $i++) { $output .= "-"; }
	return $output;
}

sub _rgbd2h($) {
	my ($input) = @_;
	my @a = split(" ", $input);
	my $output = sprintf( "%02x%02x%02x", $a[0],$a[1],$a[2]);
	return $output;
}

sub createIndexFile($){
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if($name){
		my $text =	"<html><head></head><body>".
					"<a href=\"./".$name."/".$name."_conditionsmap.jpg\" target=\"blank\">Aktuelle Wetterkarte: Wetterlage</a><br/>".
					"<a href=\"./".$name."/".$name."_forecastsmap.jpg\" target=\"blank\">Aktuelle Wetterkarte: Vorhersage</a><br/>".
					"<a href=\"./".$name."/".$name."_warningsmap.jpg\" target=\"blank\">Aktuelle Wetterkarte: Warnungen</a><br/>".
					"<a href=\"./".$name."/".$name."_radarmap.jpg\" target=\"blank\">Aktuelle Radarkarte</a><br/>".
					"</body></html>";
		open	(DATEI, ">".$tempDir.$name.".html") or die $!;
		print	 DATEI $text;
		close	(DATEI);
	}
	return;
}

sub fillMappingTables($){

	$bulaList =	"Baden-Württemberg,Bayern,Berlin,Brandenburg,Bremen,".
				"Hamburg,Hessen,Mecklenburg-Vorpommern,Niedersachsen,".
				"Nordrhein-Westfalen,Rheinland-Pfalz,Saarland,Sachsen,".
				"Sachsen-Anhalt,Schleswig-Holstein,Thüringen";

	$cmapList =	"Deutschland,Mitte,Nordost,Nordwest,Ost,Suedost,Suedwest,West";

	%rmapList = (
	Deutschland	=> "",
	Mitte		=> "central/",
	Nordost		=> "northeast/",
	Nordwest	=> "northwest/",
	Ost			=> "east/",
	Suedost		=> "southeast/",
	Suedwest	=> "southwest/",
	West		=> "west/");

	$fmapList =	"Deutschland_heute_frueh,Deutschland_heute_mittag,Deutschland_heute_spaet,Deutschland_heute_nacht,".
				"Deutschland_morgen_frueh,Deutschland_morgen_spaet,".
				"Deutschland_ueberm_frueh,Deutschland_ueberm_spaet,".
				"Deutschland_tag4_frueh,Deutschland_tag4_spaet,".
				"Mitte_heute_frueh,Mitte_heute_mittag,Mitte_heute_spaet,Mitte_heute_nacht,".
				"Mitte_morgen_frueh,Mitte_morgen_spaet,".
				"Mitte_ueberm_frueh,Mitte_ueberm_spaet,".
				"Mitte_tag4_frueh,Mitte_tag4_spaet,".
				"Nordost_heute_frueh,Nordost_heute_mittag,Nordost_heute_spaet,Nordost_heute_nacht,".
				"Nordost_morgen_frueh,Nordost_morgen_spaet,".
				"Nordost_ueberm_frueh,Nordost_ueberm_spaet,".
				"Nordost_tag4_frueh,Nordost_tag4_spaet,".
				"Nordwest_heute_frueh,Nordwest_heute_mittag,Nordwest_heute_spaet,Nordwest_heute_nacht,".
				"Nordwest_morgen_frueh,Nordwest_morgen_spaet,".
				"Nordwest_ueberm_frueh,Nordwest_ueberm_spaet,".
				"Nordwest_tag4_frueh,Nordwest_tag4_spaet,".
				"Ost_heute_frueh,Ost_heute_mittag,Ost_heute_spaet,Ost_heute_nacht,".
				"Ost_morgen_frueh,Ost_morgen_spaet,".
				"Ost_ueberm_frueh,Ost_ueberm_spaet,".
				"Ost_tag4_frueh,Ost_tag4_spaet,".
				"Suedost_heute_frueh,Suedost_heute_mittag,Suedost_heute_spaet,Suedost_heute_nacht,".
				"Suedost_morgen_frueh,Suedost_morgen_spaet,".
				"Suedost_ueberm_frueh,Suedost_ueberm_spaet,".
				"Suedost_tag4_frueh,Suedost_tag4_spaet,".
				"Suedwest_heute_frueh,Suedwest_heute_mittag,Suedwest_heute_spaet,Suedwest_heute_nacht,".
				"Suedwest_morgen_frueh,Suedwest_morgen_spaet,".
				"Suedwest_ueberm_frueh,Suedwest_ueberm_spaet,".
				"Suedwest_tag4_frueh,Suedwest_tag4_spaet,".
				"West_heute_frueh,West_heute_mittag,West_heute_spaet,West_heute_nacht,".
				"West_morgen_frueh,West_morgen_spaet,".
				"West_ueberm_frueh,West_ueberm_spaet,".
				"West_tag4_frueh,West_tag4_spaet";

#
# Bundesländer den entsprechenden Dienststellen zuordnen
#
	%bula2bulaShort = (
	"baden-württemberg"			=> "bw",
	"bayern"					=> "by",
	"berlin"					=> "be",
	"brandenburg"				=> "bb",
	"bremen"					=> "hb",
	"hamburg"					=> "hh",
	"hessen" 					=> "he",
	"mecklenburg-vorpommern"	=> "mv",
	"niedersachsen"				=> "ni",
	"nordrhein-westfalen"		=> "nw",
	"rheinland-pfalz"			=> "rp",
	"saarland"					=> "sl",
	"sachsen"					=> "sn",
	"sachsen-anhalt"			=> "st",
	"schleswig-holstein"		=> "sh",
	"thüringen"					=> "th",
	"deutschland"				=> "xde",
	"bodensee"					=> "xbo" );

	%bulaShort2dwd = (
	bw => "DWSG",
	by => "DWMG",
	be => "DWPG",
	bb => "DWPG",
	hb => "DWHG",
	hh => "DWHH",
	he => "DWOH",
	mv => "DWPH",
	ni => "DWHG",
	nw => "DWEH",
	rp => "DWOI",
	sl => "DWOI",
	sn => "DWLG",
	st => "DWLH",
	sh => "DWHH",
	th => "DWLI",
	xde => "xde",
	xbo => "xbo" );

#
# Dienststellen den entsprechenden Serververzeichnissen zuordnen
#
	%dwd2Dir = (
	DWSG => "SU", # Stuttgart
	DWMG => "MS", # München
	DWPG => "PD", # Potsdam
	DWHG => "HA", # Hamburg
	DWHH => "HA", # Hamburg
	DWOH => "OF", # Offenbach
	DWPH => "PD", # Potsdam
	DWHG => "HA", # Hamburg
	DWEH => "EM", # Essen
	DWOI => "OF", # Offenbach
	DWLG => "LZ", # Leipzig
	DWLH => "LZ", # Leipzig
	DWLI => "LZ", # Leipzig
	DWHC => "HA", # Hamburg
	DWHB => "HA", # Hamburg
	DWPD => "PD", # Potsdam
	DWRW => "PD", # Potsdam
	DWEM => "EM", # Essen
	LSAX => "LZ", # Leipzig
	LSNX => "LZ", # Leipzig
	THLX => "LZ", # Leipzig
	DWOF => "OF", # Offenbach
	DWTR => "OF", # Offenbach
	DWSU => "SU", # Stuttgart
	DWMS => "MS", # München
	xde  => "D",
	xbo  => "Bodensee");
#	???? => "FG" # Freiburg);

	%dwd2Name = (
	EM => "Essen",
	FG => "Freiburg",
	HA => "Hamburg",
	LZ => "Leipzig",
	MS => "München",
	OF => "Offenbach",
	PD => "Potsdam",
	SU => "Stuttgart");

return;
}

sub initDropdownLists($){
	my($hash) = @_;
	my $name = $hash->{NAME};

	if ($name){
		if(-e $tempDir.$name."_conditions"){
			$sList = getListStationsDropdown($hash);
		} else {
			Log3($name, 3, "GDS $name: no datafile (conditions) found"); 
			$sList = "please_use_rereadcfg_first";
		}

		if (-e $tempDir.$name."_alerts"){
			($aList, undef) = buildCAPList($hash);
		} else {
			Log3($name, 3, "GDS $name: no datafile (alerts) found"); 
			$aList = "please_use_rereadcfg_first";
		}
	} else {
		$aList = "please_use_rereadcfg_first";
		$sList = $aList;
	}
	return;
}

sub gdsHeadlines($;$) {
  my ($d,$sep) = @_;
  my $text = "";
  $sep = (defined($sep)) ? $sep : '|';
  my $count = ReadingsVal($d,'a_count',0);
  for (my $i = 0; $i < $count; $i++) {
    $text .= $sep if $i;
    $text .= ReadingsVal('gds','a_'.$i.'_headline','')
  }
  return $text;
}

1;


####################################################################################################
#
# Documentation 
#
####################################################################################################
#
#	Changelog:
#
#	2013-08-07	initial release
#
#	2013-08-08	added	logging
#				added	firewall/proxy support
#				fixed	XMLin missing parameter 
#				added	:noArg to setlist-definitions
#				added	AttrFn
#				modi	retrieval of VHDL messages 30-33
#
#	2013-08-09	added	more logging
#				fixed	missing error message if WARNCELLID does not exist
#				update	commandref
#
#	2013-08-10	added	some more tolerance on text inputs
#				modi	switched from GetLogList to Log3
#
#	2013-08-11	added	retrieval for condition maps
#				added	retrieval for forecast maps
#				added	retrieval for warning maps
#				added	retrieval for radar maps
#				modi	use LWP::ua for some file transfers instead of ftp
#						due to transfer errors on image files
#						use parameter #5 = 1 in RetrieveFile for ftp
#				added	get <name> caplist
#
#	2013-08-13	fixed	some minor bugs to prevent annoying console messages
#				added	support for fhem installtions running on windows-based systems
#
#	2013-11-03	added	error handling for malformed XML files from GDS
#
#	2014-02-04	added	ShutdownFn
#				changed	FTP Timeout
#
#	2014-02-26	added	attribute gdsPassiveFtp
#
#	2014-05-07	added	readings a_onset_local & a_expires_local
#
#	2014-05-22	added	reading a_sent_local
#
#	2014-05-23	added	set <name> clear alerts|all
#						fixed some typos in docu and help
#
#	2014-10-15	added	attr disable
#
#	2015-01-03	added	multiple alerts handling
#
#   2015-01-30  changed use own FWEXT instead of HTTPSRV
#
#   2015-04-07  fixed   a_X_valid calculation: use onset, too
#
####################################################################################################
#
# Further informations
#
# DWD's data format is unpleasant to read, 
# since the data columns change depending on the available data
# (e.g. the SSS column for snow disappears when there is no snow).
# It's also in ISO8859-1, i.e. it contains non-ASCII characters. To
# avoid problems, we need some conversion subs in this program.
#
# Höhe  : m über NN
# Luftd.: reduzierter Luftdruck auf Meereshöhe in hPa
# TT    : Lufttemperatur in Grad Celsius
# Tn12  : Minimum der Lufttemperatur, 18 UTC Vortag bis 06 UTC heute, Grad Celsius
# Tx12  : Maximum der Lufttemperatur, 18 UTC Vortag bis 06 UTC heute, Grad Celsius
# Tg24  : Temperaturminimum 5cm ¸ber Erdboden, 22.05.2014 00 UTC bis 24 UTC, Grad Celsius
# Tn24  : Minimum der Lufttemperatur, 22.05.2014 00 UTC bis 24 UTC, Grad Celsius
# Tm24  : Mittel der Lufttemperatur, 22.05.2014 00 UTC bis 24 UTC, Grad Celsius
# Tx24  : Maximum der Lufttemperatur, 22.05.2014 00 UTC bis 24 UTC, Grad Celsius
# Tmin  : Minimum der Lufttemperatur, 06 UTC Vortag bis 06 UTC heute, Grad Celsius
# Tmax  : Maximum der Lufttemperatur, 06 UTC Vortag bis 06 UTC heute, Grad Celsius
# RR1   : Niederschlagsmenge, einstündig, mm = l/qm
# RR12  : Niederschlagsmenge, 12st¸ndig, 18 UTC Vortag bis 06 UTC heute, mm = l/qm
# RR24  : Niederschlagsmenge, 24stündig, 06 UTC Vortag bis 06 UTC heute, mm = l/qm
# SSS   : Gesamtschneehöhe in cm
# SSS24 : Sonnenscheindauer 22.05.2014 in Stunden
# SGLB24: Tagessumme Globalstrahlung am 22.05.2014 in J/qcm 
# DD    : Windrichtung 
# FF    : Windgeschwindigkeit letztes 10-Minutenmittel in km/h
# FX    : höchste Windspitze im Bezugszeitraum in km/h
# ---   : Wert nicht vorhanden
#
####################################################################################################

=pod
=begin html

<a name="GDS"></a>
<h3>GDS</h3>
<ul>

	<b>Prerequesits</b>
	<ul>
	
		<br/>
		Module uses following additional Perl modules:<br/><br/>
		<code>Net::FTP, List::MoreUtils, XML::Simple, Text::CSV</code><br/><br/>
		If not already installed in your environment, please install them using appropriate commands from your environment.

	</ul>
	<br/><br/>
	
	<a name="GDSdefine"></a>
	<b>Define</b>
	<ul>

		<br/>
		<code>define &lt;name&gt; GDS &lt;username&gt; &lt;password&gt;</code>
		<br/><br/>
		This module provides connection to <a href="http://www.dwd.de/grundversorgung">GDS service</a> generated by <a href="http://www.dwd.de">DWD</a><br/>

	</ul>
	<br/><br/>

	<a name="GDSset"></a>
	<b>Set-Commands</b><br/>
	<ul>

		<br/>
		<code>set &lt;name&gt; clear alerts|all</code>
		<br/><br/>
		<ul>
			<li>alerts: Delete all a_* readings</li>
			<li>all: Delete all a_*, c_* and g_* readings</li>
		</ul>
		<br/>

		<code>set &lt;name&gt; conditions &lt;stationName&gt;</code>
		<br/><br/>
		<ul>Retrieve current conditions at selected station. Data will be updated periodically.</ul>
		<br/>

		<code>set &lt;name&gt; help</code>
		<br/><br/>
		<ul>Show a help text with available commands</ul>
		<br/>

		<code>set &lt;name&gt; rereadcfg</code>
		<br/><br/>
		<ul>Reread all required data from DWD Server manually: station list and CAP data</ul>
		<br/>

		<code>set &lt;name&gt; update</code>
		<br/><br/>
		<ul>Update conditions readings at selected station and restart update-timer</ul>
		<br/>

		<li>condition readings generated by SET use prefix "c_"</li>
		<li>readings generated by SET will be updated automatically every 60 minutes</li>

	</ul>
	<br/><br/>

	<a name="GDSget"></a>
	<b>Get-Commands</b><br/>
	<ul>

		<br/>
		<code>get &lt;name&gt; alerts &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve alert message for selected region from previously read alert file (see rereadcfg)</ul>
		<br/>

		<code>get &lt;name&gt; conditions &lt;stationName&gt;</code>
		<br/><br/>
		<ul>Retrieve current conditions at selected station</ul>
		<br/>

		<code>get &lt;name&gt; conditionsmap &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve map (imagefile) showing current conditions at selected station</ul>
		<br/>

		<code>get &lt;name&gt; forecastsmap &lt;stationName&gt;</code>
		<br/><br/>
		<ul>Retrieve map (imagefile) showing forecasts for selected region</ul>
		<br/>

		<code>get &lt;name&gt; headlines</code>
		<br/><br/>
		<ul>Returns a string, containing all alert headlines separated by |</ul>
		<br/>

		<code>get &lt;name&gt; help</code>
		<br/><br/>
		<ul>Show a help text with available commands</ul>
		<br/>

		<code>get &lt;name&gt; list capstations|data|stations</code>
		<br/><br/>
		<ul>
			<li><b>capstations:</b> Retrieve list showing all defined warning regions. You can find your WARNCELLID with this list.</li>
			<li><b>data:</b> List current conditions for all available stations in one single table</li>
			<li><b>stations:</b> List all available stations that provide conditions data</li>
		</ul>
		<br/>

		<code>get &lt;name&gt; radarmap &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve map (imagefile) containig radar view from selected region</ul>
		<br/>

		<code>get &lt;name&gt; rereadcfg</code>
		<br/><br/>
		<ul>Reread all required data from DWD Server manually: station list and CAP data</ul>
		<br/>

		<code>get &lt;name&gt; warnings &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve current warnings report for selected region
			<ul>
				<br/>
				<li>report type VHDL30 = regular report, issued daily</li>
				<li>report type VHDL31 = regular report, issued before weekend or national holiday</li>
				<li>report type VHDL32 = preliminary report, issued on special conditions</li>
				<li>report type VHDL33 = cancel report, issued if necessary to cancel VHDL32</li>
			</ul>
		</ul>
		<br/>

		<code>get &lt;name&gt; warningssmap &lt;region&gt;</code>
		<br/><br/>
		<ul>Retrieve map (imagefile) containig current warnings for selected region marked with symbols</ul>
		<br/><br/>
		<b>All downloaded mapfiles</b> can be found inside "GDS Files" area in left navigation bar.

	</ul>
	<br/><br/>

	<a name="GDSattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#readingFnAttributes">readingFnAttributes</a></li>
		<br/>
		<li><b>disable</b> - if set, gds will not try to connect to internet</li>
		<li><b>gdsAll</b> - defines filter for "all data" from alert message</li>
		<li><b>gdsDebug</b> - defines filter for debug informations</li>
		<li><b>gdsSetCond</b> - defines conditions area to be used after system restart</li>
		<li><b>gdsLong</b> - show long text fields "description" and "instruction" from alert message in readings</li>
		<li><b>gdsPolygon</b> - show polygon data from alert message in a reading</li>
		<br/>
		<li><b>gdsPassiveFtp</b> - set to 1 to use passive FTP transfer</li>
		<li><b>gdsFwName</b> - define firewall hostname in format &lt;hostname&gt;:&lt;port&gt;</li>
		<li><b>gdsFwType</b> - define firewall type in a value 0..7 please refer to <a href="http://search.cpan.org/~gbarr/libnet-1.22/Net/Config.pm#NetConfig_VALUES">cpan documentation</a> for further informations regarding firewall settings.</li>
	</ul>
	<br/><br/>

	<b>Generated Readings/Events:</b>
	<br/><br/>
	<ul>
		<li><b>_&lt;readingName&gt;</b> - debug informations</li>
		<li><b>a_X_&lt;readingName&gt;</b> - weather data from CAP alert messages. Readings will NOT be updated automatically<br/>
			a_ readings contain a set of alert inforamtions, X represents a numeric set identifier starting with 0<br/>
			that will be increased for every valid alert message in selected area<br/></li>
		<li><b>a_count</b> - number of currently valid alert messages, can be used for own loop iterations on alert messages</li>
		<li><b>a_valid</b> - returns 1 if at least one of decoded alert messages is valid</li>
		<li><b>c_&lt;readingName&gt;</b> - weather data from SET weather conditions. Readings will be updated every 20 minutes</li>
		<li><b>g_&lt;readingName&gt;</b> - weather data from GET weather conditions. Readings will NOT be updated automatically</li>
	</ul>
	<br/><br/>

	<b>Author's notes</b><br/><br/>
	<ul>

		<li>Module uses following additional Perl modules:<br/><br/>
		<code>Net::FTP, List::MoreUtils, XML::Simple, Text::CSV</code><br/><br/>
		If not already installed in your environment, please install them using appropriate commands from your environment.</li>
		<br/><br/>
		<li>Have fun!</li><br/>

	</ul>

</ul>

=end html
=begin html_DE

<a name="GDS"></a>
<h3>GDS</h3>
<ul>
Sorry, keine deutsche Dokumentation vorhanden.<br/><br/>
Die englische Doku gibt es hier: <a href='http://fhem.de/commandref.html#GDS'>GDS</a><br/>
</ul>
=end html_DE
=cut
