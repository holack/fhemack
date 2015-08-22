# $Id: 10_OWServer.pm 8629 2015-05-24 20:31:31Z borisneubert $
################################################################
#
#  Copyright notice
#
#  (c) 2012 Copyright: Dr. Boris Neubert & Martin Fischer
#  e-mail: omega at online dot de
#  e-mail: m_fischer at gmx dot de
#
#  This file is part of fhem.
#
#  Fhem is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
#
#  Fhem is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
################################################################################

package main;

use strict;
use warnings;
# this must be the latest OWNet from
#  http://owfs.cvs.sourceforge.net/viewvc/owfs/owfs/module/ownet/perl5/OWNet/lib/OWNet.pm
# the version at CPAN is outdated and malfunctioning as at 2012-12-19
use lib::OWNet;

use vars qw(%owfamily);
# 1-Wire devices (order by family code)
# http://owfs.sourceforge.net/family.html
%owfamily = (
  "01"  => "DS2401 DS1990A",
  "05"  => "DS2405",
  "10"  => "DS18S20 DS1920",
  "12"  => "DS2406 DS2507",
  "1B"  => "DS2436",
  "1D"  => "DS2423",
  "20"  => "DS2450",
  "22"  => "DS1822",
  "24"  => "DS2415 DS1904",
  "26"  => "DS2438",
  "27"  => "DS2417",
  "28"  => "DS18B20",
  "29"  => "DS2408",
  "3A"  => "DS2413",
  "3B"  => "DS1825",
  "7E"  => "EDS000XX",
  "81"  => "DS1420",
  "FF"  => "LCD",
);

use vars qw(%gets %sets);
%gets = (
  "/settings/timeout/directory"        => "",
  "/settings/timeout/ftp"              => "",
  "/settings/timeout/ha7"              => "",
  "/settings/timeout/network"          => "",
  "/settings/timeout/presence"         => "",
  "/settings/timeout/serial"           => "",
  "/settings/timeout/server"           => "",
  "/settings/timeout/stable"           => "",
  "/settings/timeout/uncached"         => "",
  "/settings/timeout/usb"              => "",
  "/settings/timeout/volatile"         => "",
  "/settings/timeout/w1"               => "",
  "/settings/units/pressure_scale"     => "",
  "/settings/units/temperature_scale"  => "",
);

%sets = (
  "timeout/directory"        => "",
  "timeout/ftp"              => "",
  "timeout/ha7"              => "",
  "timeout/network"          => "",
  "timeout/presence"         => "",
  "timeout/serial"           => "",
  "timeout/server"           => "",
  "timeout/stable"           => "",
  "timeout/uncached"         => "",
  "timeout/usb"              => "",
  "timeout/volatile"         => "",
  "timeout/w1"               => "",
  "units/pressure_scale"     => "",
  "units/temperature_scale"  => "",
);

#####################################
sub
OWServer_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{WriteFn} = "OWServer_Write";
  $hash->{ReadFn}  = "OWServer_Read";
  $hash->{DirFn}   = "OWServer_Dir";
  $hash->{FindFn}  = "OWServer_Find";
  $hash->{Clients} = ":OWDevice:OWAD:OWCOUNT:OWMULTI:OWSWITCH:OWTHERM:";

# Consumer
  $hash->{DefFn}   = "OWServer_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn}= "OWServer_Notify";
  $hash->{NotifyOrderPrefix}= "50a-";
  $hash->{UndefFn} = "OWServer_Undef";
  $hash->{GetFn}   = "OWServer_Get";
  $hash->{SetFn}   = "OWServer_Set";
# $hash->{AttrFn}  = "OWServer_Attr";
  $hash->{AttrList}= "nonblocking " . $readingFnAttributes;
}

#####################################
sub
OWServer_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t]+", $def, 3);
  my $name = $a[0];
  if(@a < 3) {
    my $msg = "wrong syntax for $name: define <name> OWServer <protocol>";
    Log 2, $msg;
    return $msg;
  }

  my $protocol = $a[2];

  $hash->{fhem}{protocol}= $protocol;

  if( $init_done ) {
    OWServer_OpenDev($hash);
  }

  return undef;
}


#####################################
sub
OWServer_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log3 $name, $lev, "deleting OWServer for $d";
        delete $defs{$d}{IODev};
      }
  }

  OWServer_CloseDev($hash);
  return undef;
}

#####################################
sub
OWServer_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return unless(defined($hash->{fhem}{owserver}));
  delete $hash->{fhem}{owserver};
  readingsSingleUpdate($hash, "state", "DISCONNECTED", 1);
}

########################
sub
OWServer_OpenDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  OWServer_CloseDev($hash);
  my $protocol= $hash->{fhem}{protocol};
  Log3 $name, 3, "$name: Opening connection to OWServer $protocol...";
  my $owserver= OWNet->new($protocol);
  if($owserver) {
    Log3 $name, 3, "$name: Successfully connected to $protocol.";
    $hash->{fhem}{owserver}= $owserver;
    readingsSingleUpdate($hash, "state", "CONNECTED", 1);
    my $ret  = OWServer_DoInit($hash);
  }
  return $owserver
}

#####################################
sub
OWServer_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  return if($attr{$name} && $attr{$name}{disable});

  OWServer_OpenDev($hash);

  return undef;
}

#####################################
sub
OWServer_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};

  my $owserver= $hash->{fhem}{owserver};
  foreach my $reading (sort keys %gets) {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"$reading",$owserver->read("$reading"));
    readingsEndUpdate($hash,1);
  }
  readingsSingleUpdate($hash, "state", "Initialized", 1);
  OWServer_Autocreate($hash);
  return undef;
}

#####################################
sub
OWServer_Read($@)
{
  my ($hash,$path)= @_;

  return undef unless(defined($hash->{fhem}{owserver}) || $hash->{LAST_READ_FAILED});

  my $ret= undef;

  if(AttrVal($hash->{NAME},"nonblocking",undef) && $init_done) {
    $hash->{".path"}= $path;
    pipe(READER,WRITER);
    #READER->autoflush(1);
    WRITER->autoflush(1);

    my $pid= fork;
    if(!defined($pid)) {
      Log3 $hash, 1, "OWServer: Cannot fork: $!";
      return undef;
    }

    InternalTimer(gettimeofday()+6, "OWServer_TimeoutChild", $pid, 0);
    if($pid == 0) {
      close READER;
      $ret= OWNet::read($hash->{DEF},$path);
      $ret =~ s/^\s+//g if(defined($ret));
      my $r= defined($ret) ? $ret : "<undefined>";
      Log3 $hash, 5, "OWServer child read $path: $r";
      delete $hash->{".path"};
      print WRITER $ret if(defined($ret)); 
      close WRITER;
      # see http://forum.fhem.de/index.php?t=tree&goto=94670
      # changed from
      # exit 0;
      # to
      POSIX::_exit(0);
    }

    Log3 $hash, 5, "OWServer child ID for reading '$path' is $pid";
    close WRITER;
    # http://forum.fhem.de/index.php/topic,16945.0/topicseen.html#msg110673
    my ($rout,$rin, $eout,$ein) = ('','', '','');
    vec($rin, fileno(READER),  1) = 1;
    $ein = $rin;
    my $nfound = select($rout=$rin, undef, $eout=$ein, 4);
    if( $nfound ) {
      chomp($ret= <READER>);
      RemoveInternalTimer($pid);
      OWServer_OpenDev($hash) if( $hash->{LAST_READ_FAILED} );
      $hash->{LAST_READ_FAILED} = 0;
    } else {
      Log3 undef, 1, "OWServer: read timeout for child $pid";
      $hash->{NR_READ_FAILED} = 0 if( !$hash->{NR_READ_FAILED} );
      $hash->{NR_READ_FAILED}++;
      OWServer_CloseDev($hash) if( !$hash->{LAST_READ_FAILED} );
      $hash->{LAST_READ_FAILED} = 1;
    }
    close READER;

  } else {
    $ret= $hash->{fhem}{owserver}->read($path);
    $ret =~ s/^\s+//g if(defined($ret));
    $hash->{LAST_READ_FAILED} = 0;
  }

  # if a device does not exist, the server returns undef
  # therefore it's not a good idea to blame the connection
  # and remove the server in such a case.
  #if(!defined($ret)) { OWServer_CloseDev($hash); }
  return $ret;
}

#####################################
sub
OWServer_TimeoutChild($)
{
  my $pid= shift;
  Log3 undef, 1, "OWServer: Terminated child $pid" if($pid && kill(9, $pid));
}

#####################################
sub
OWServer_Write($@)
{
  my ($hash,$path,$value)= @_;

  return undef if($hash->{LAST_READ_FAILED});

  return undef unless(defined($hash->{fhem}{owserver}));

  return $hash->{fhem}{owserver}->write($path,$value);
}

#####################################
sub
OWServer_Dir($@)
{
  my ($hash,$path)= @_;

  return undef if($hash->{LAST_READ_FAILED});

  return undef unless(defined($hash->{fhem}{owserver}));

  $path= ($path) ? $path : "/";
  return $hash->{fhem}{owserver}->dir($path);
}

#####################################
sub
OWServer_Find($@)
{
  my ($hash,$slave)= @_;

  return undef if($hash->{LAST_READ_FAILED});

  return undef unless(defined($hash->{fhem}{owserver}));

  my $owserver= $hash->{fhem}{owserver};
  my @dir= split(",",$owserver->dir("/"));
  my $path= undef;
  for my $entry (@dir) {
    $entry = substr($entry,1);
    next if($entry !~ m/^bus.\d+/m);
    my @busdir= split(",",$owserver->dir("/$entry"));
    $path= (grep { m/$slave/i } @busdir) ? $entry : undef;
    last if($path)
  }
  return $path;
}

#####################################
sub
OWServer_Autocreate($)
{
  my ($hash)= @_;
  my $name = $hash->{NAME};

  my $acdname= "";
  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "autocreate");
    $acdname= $defs{$d}{NAME};
    return undef if(AttrVal($acdname,"disable",undef));
  }
  return undef unless($acdname ne "");
  
  my $owserver= $hash->{fhem}{owserver};

  my @dir= split(",", $owserver->dir("/"));
  my @devices= grep { m/^\/[0-9a-f]{2}.[0-9a-f]{12}$/i } @dir;

  my %defined = ();
  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} !~ /^OW(Device|AD|ID|MULTI|COUNT|LCD|SWITCH|THERM)$/);
    if(defined($defs{$d}{fhem}) && defined($defs{$d}{fhem}{address})) {
      $defined{$defs{$d}{fhem}{address}} = $d; 
    } elsif(defined($defs{$d}{OW_ID}) and defined($defs{$d}{OW_FAMILY})) {
      $defined{"$defs{$d}{OW_FAMILY}.$defs{$d}{OW_ID}"} = $d;
    }
  }

  my $created = 0;
  for my $device (@devices) {
    my $address= substr($device,1);
    my $family= substr($address,0,2);
    if(!exists $owfamily{$family}) {
      Log3 $name, 2, "$name: Autocreate: unknown familycode '$family' found. Please report this!";
      next;
    } else {
      my $type= $owserver->read($device . "/type");
      my $owtype= $owfamily{$family};
      if($owtype !~ m/$type/) {
        Log3 $name, 2, "$name: Autocreate: type '$type' not defined in familycode '$family'. Please report this!";
        next;
      } elsif( defined($defined{$address}) ) {
        Log3 $name, 5, "$name address '$address' already defined as '$defined{$address}'";
        next;
      } else {
        my $id= substr($address,3);
        my $devname= $type . "_" . $id;
        Log3 $name, 5, "$name create new device '$devname' for address '$address'";
        my $interval= ($family eq "81") ? "" : " 60";
        my $define= "$devname OWDevice $address" . $interval;
        my $cmdret;
        $cmdret= CommandDefine(undef,$define);
        if($cmdret) {
          Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for address '$address': $cmdret";
        } else {
          $created++;
          $cmdret= CommandAttr(undef,"$devname room OWDevice");
        }
      }
    }
  }

  CommandSave(undef,undef) if( $created && AttrVal($acdname, "autosave", 1 ) );

  return undef;
}

#####################################
sub
OWServer_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];

  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];
  #my $arg = ($a[2] ? $a[2] : "");
  #my @args= @a; shift @args; shift @args;

  my $owserver= $hash->{fhem}{owserver};

  if($cmd eq "devices") {
        my @dir= split(",", $owserver->dir("/"));
        my @devices= grep { m/^\/[0-9a-f]{2}.[0-9a-f]{12}$/i } @dir;
        my $ret;
        for my $device (@devices) {
          my $name= "";
          my $address= substr($device,1);
          my $type= $owserver->read($device . "/type");
          foreach my $p (keys %defs) {
             $name= concatc(", ", $name, $p) if($defs{$p}{TYPE} eq "OWDevice" and $defs{$p}{fhem}{address} eq $address);
          }
          $ret .= sprintf("%s %10s %s\n", $address, $type, $name);
        }
        return $ret;
  } elsif($cmd eq "errors") {
        my $path= "statistics/errors";
        my @dir= split(",", $owserver->dir($path));
        my $wide= (reverse sort { $a <=> $b } map { length($_) } @dir)[0];
        $wide= $wide-length($path);
        my $ret= "=> $path:\n";
        for my $error (@dir) {
          my $stat= $owserver->read("$path/$error");
          my (undef, $str) = $error =~ m|^(.*[/\\])([^/\\]+?)$|;
          $str =~ s/_/ /g;
          $ret .= sprintf("%-*s %d\n",$wide,$str,($stat) ? $stat : 0);
        }
        return $ret;
  } elsif(defined($gets{$cmd})) {
        my $ret;
        my $value= $owserver->read($cmd);
        readingsSingleUpdate($hash,$cmd,$value,1);
        return "$cmd => $value";

  } else {
        return "Unknown argument $cmd, choose one of devices ".join(" ", sort keys %gets);
  }

}

#####################################
sub
OWServer_Set($@)
{
        my ($hash, @a) = @_;
        my $name = $a[0];

        # usage check
        #my $usage= "Usage: set $name classdef <classname> <filename> OR set $name reopen";
        my $usage= "Unknown argument $a[1], choose one of reopen ".join(" ", sort keys %sets);
        return $usage if($a[1] ne "reopen" && !defined($sets{$a[1]}));

        if((@a == 2) && ($a[1] eq "reopen")) {
                OWServer_OpenDev($hash);
                return undef;
        } elsif(@a == 3) {
          my $cmd= $a[1];
          my $value= $a[2];
          my $owserver= $hash->{fhem}{owserver};
          my $ret= $owserver->write("/settings/$cmd",$value);
          #return $ret if($ret);
          readingsSingleUpdate($hash,"/settings/$cmd",$value,1);
        }
        return undef;

}
#####################################


1;


=pod
=begin html

<a name="OWServer"></a>
<h3>OWServer</h3>
<ul>
  <br>
  <a name="OWDevicedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OWServer &lt;protocol&gt;</code>
    <br><br>

    Defines a logical OWServer device. OWServer is the server component of the
    <a href="http://owfs.org">1-Wire Filesystem</a>. It serves as abstraction layer
    for any 1-wire devices on a host. &lt;protocol&gt; has
    format &lt;hostname&gt;:&lt;port&gt;. For details see
    <a href="http://owfs.org/index.php?page=owserver_protocol">owserver documentation</a>.
    <br><br>
    You need <a href="http://owfs.cvs.sourceforge.net/viewvc/owfs/owfs/module/ownet/perl5/OWNet/lib/OWNet.pm">OWNet.pm from owfs.org</a>, which is normally deployed with FHEM. As at 2012-12-23 the OWNet module
    on CPAN has an issue which renders it useless for remote connections.
    <br><br>
    The actual 1-wire devices are defined as <a href="#OWDevice">OWDevice</a> devices.
    If <a href="#autocreate">autocreate</a> is enabled, all the devices found are created at
    start of FHEM automatically.
    <br><br>
    This module is completely unrelated to the 1-wire modules with names all in uppercase.
    <br><br>
    Examples:
    <ul>
      <code>define myLocalOWServer OWServer localhost:4304</code><br>
      <code>define myRemoteOWServer OWServer raspi:4304</code><br>
    </ul>
    <br><br>
    Notice: if you get no devices add both <code>localhost</code> and the FQDN of your owserver as server directives
    to the owserver configuration file
    on the remote host.
    <br><br>

  </ul>

  <a name="OWServerset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of<br><br>
    <li><code>reopen</code><br>
      Reopens the connection to the owserver.
    </li>
    <li>owserver (OWFS) specific settings:
      <ul>
        <li><code>timeout/directory</code></li>
        <li><code>timeout/ftp</code></li>
        <li><code>timeout/ha7</code></li>
        <li><code>timeout/network</code></li>
        <li><code>timeout/presence</code></li>
        <li><code>timeout/serial</code></li>
        <li><code>timeout/server</code></li>
        <li><code>timeout/stable</code></li>
        <li><code>timeout/uncached</code></li>
        <li><code>timeout/usb</code></li>
        <li><code>timeout/volatile</code></li>
        <li><code>timeout/w1</code></li>
        <li><code>units/pressure_scale</code></li>
        <li><code>units/temperature_scale</code></li>
      </ul>
    </li>
    For further informations have look on <a href="http://owfs.org/uploads/owserver.1.html#sect41">owserver manual</a>).
    <br>
  </ul>
  <br><br>


  <a name="OWServerget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of<br><br>
    <li><code>devices</code><br>
      Lists the addresses and types of all 1-wire devices provided by the owserver. Also shows
      the corresponding <a href="#OWDevice">OWDevice</a> if one is defined for the respective 1-wire devices.
    </li>
    <li><code>errors</code><br>
      List a view of error statistics.</li>
    <li>owserver (OWFS) specific settings:
      <ul>
        <li><code>/settings/timeout/directory</code></li>
        <li><code>/settings/timeout/ftp</code></li>
        <li><code>/settings/timeout/ha7</code></li>
        <li><code>/settings/timeout/network</code></li>
        <li><code>/settings/timeout/presence</code></li>
        <li><code>/settings/timeout/serial</code></li>
        <li><code>/settings/timeout/server</code></li>
        <li><code>/settings/timeout/stable</code></li>
        <li><code>/settings/timeout/uncached</code></li>
        <li><code>/settings/timeout/usb</code></li>
        <li><code>/settings/timeout/volatile</code></li>
        <li><code>/settings/timeout/w1</code></li>
        <li><code>/settings/units/pressure_scale</code></li>
        <li><code>/settings/units/temperature_scale</code></li>
      </ul>
    </li>
    For further informations have look on <a href="http://owfs.org/uploads/owserver.1.html#sect41">owserver manual</a>).
    <br>
  </ul>
  <br><br>


  <a name="OWDeviceattr"></a>
  <b>Attributes</b>
  <ul>
    <li>nonblocking<br>
    Get all readings (OWServer / <a href="#OWDevice">OWDevice</a>) via a child process. This ensures, that FHEM
    is not blocked during communicating with the owserver.<br>
    Example:<br>
    <code> attr &lt;name&gt; nonblocking 1</code>
    </li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br><br>
  Note: unset <code>nonblocking</code> if you experience lockups of FHEM.

</ul>

=end html
=begin html_DE

<a name="OWServer"></a>
<h3>OWServer</h3>
<ul>
  <br>
  <a name="OWDevicedefine"></a>
  <b>Definition</b>
  <ul>
    <code>define &lt;name&gt; OWServer &lt;protocol&gt;</code>
    <br><br>

    Definiert eine logische OWServer- Instanz. OWServer ist die Serverkomponente des
    <a href="http://owfs.org">1-Wire Dateisystems</a>. Sie ermöglicht den Zugriff auf 
    alle 1-Wire- Busteilnehmer eines Systems.<br><br>
        &lt;protocol&gt; hat das Format &lt;hostname&gt;:&lt;port&gt;  Nähere Informationen dazu gibt es in der <a href="http://owfs.org/index.php?page=owserver_protocol">owserver Dokumentation</a>.
        <br><br>
    Voraussetzung innerhalb von FHEM ist das Modul <a href="http://owfs.cvs.sourceforge.net/viewvc/owfs/owfs/module/ownet/perl5/OWNet/lib/OWNet.pm">OWNet.pm von owfs.org</a>, welches bereits mit FHEM ausgeliefert wird. 
        Das auf CPAN erhältliche OWNet- Modul beinhaltet seit dem 23.12.2012 einen Fehler, der es für Fernzugriffe unbrauchbar macht.<p>
        Auf dem Computer, an dem der 1-Wire- Bus angeschlossen ist, muss die Software "owserver" installiert sein. Zusätzlich sollte auf diesem Rechner die Konfigurationsdatei "owfs.conf" eingesehen bzw. angepasst werden. <a href="http://www.fhemwiki.de/wiki/OWServer_%26_OWDevice#Tipps_und_Tricks"> Einen WIKI- Artikel dazu gibt es hier.</a>
    <br><br>
    Die vorhandenen 1-Wire- Busteilnehmer werden als <a href="#OWDevice">OWDevice</a> -Geräte definiert.
    Wenn <a href="#autocreate">autocreate</a> aktiviert ist, werden beim Start von FHEM alle Geräte automatisch erkannt und eingerichtet.
    <br><br>
        <b>Achtung: Dieses Modul ist weder verwandt noch verwendbar mit den 1-Wire Modulen, deren Namen nur aus Großbuchstaben bestehen!</b>
    <br><br>
    Beispiele für die Einrichtung:
    <ul>
      <code>define myLocalOWServer OWServer localhost:4304</code><br>
      <code>define myRemoteOWServer OWServer 192.168.1.100:4304</code><br>
          <code>define myRemoteOWServer OWServer raspi:4304</code><br>
    </ul>
    <br>
    Hinweis: Sollten keine Geräte erkannt werden, kann man versuchen in der owserver- Konfigurationsdatei (owfs.conf) zwei Servereinträge anzulegen:
        Einen mit <code>localhost</code> und einen mit dem "FQDN", bzw. dem Hostnamen, oder der  IP-Adresse des Computers, auf dem die Software "owserver" läuft.
    <br><br>

  </ul>

  <a name="OWServerset"></a>
  <b>Set- Befehle</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    wobei <code>value</code> für einen der folgenden Befehle steht:<br><br>
    <li><code>reopen</code><br>
      Erneuert die Verbindung zum owserver.
    </li>
    <li>owserver (OWFS) -spezifische Einstellungen:
      <ul>
        <li><code>timeout/directory</code></li>
        <li><code>timeout/ftp</code></li>
        <li><code>timeout/ha7</code></li>
        <li><code>timeout/network</code></li>
        <li><code>timeout/presence</code></li>
        <li><code>timeout/serial</code></li>
        <li><code>timeout/server</code></li>
        <li><code>timeout/stable</code></li>
        <li><code>timeout/uncached</code></li>
        <li><code>timeout/usb</code></li>
        <li><code>timeout/volatile</code></li>
        <li><code>timeout/w1</code></li>
        <li><code>units/pressure_scale</code></li>
        <li><code>units/temperature_scale</code></li>
      </ul>
    </li>
    Nähere Informationen zu diesen Einstellungen gibt es im <a href="http://owfs.org/uploads/owserver.1.html#sect41">owserver- Manual</a>.
    <br>
  </ul>
  <br><br>


  <a name="OWServerget"></a>
  <b>Get- Befehle</b>
  <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    wobei <code>value</code> für einen der folgenden Befehle steht:<br><br>
    <li><code>devices</code><br>
      Gibt eine Liste der Adressen und Typen aller von owserver erkannten Geräte aus. Außerdem
          werden die entsprechenden <a href="#OWDevice">OWDevice-</a> Namen angezeigt, soweit sie bereits definiert sind.
    </li>
    <li><code>errors</code><br>
      Liefert eine Fehlerstatistik zurück.</li>
    <li>owserver (OWFS) -spezifische Einstellungen:
      <ul>
        <li><code>/settings/timeout/directory</code></li>
        <li><code>/settings/timeout/ftp</code></li>
        <li><code>/settings/timeout/ha7</code></li>
        <li><code>/settings/timeout/network</code></li>
        <li><code>/settings/timeout/presence</code></li>
        <li><code>/settings/timeout/serial</code></li>
        <li><code>/settings/timeout/server</code></li>
        <li><code>/settings/timeout/stable</code></li>
        <li><code>/settings/timeout/uncached</code></li>
        <li><code>/settings/timeout/usb</code></li>
        <li><code>/settings/timeout/volatile</code></li>
        <li><code>/settings/timeout/w1</code></li>
        <li><code>/settings/units/pressure_scale</code></li>
        <li><code>/settings/units/temperature_scale</code></li>
      </ul>
    </li>
    Nähere Informationen zu diesen Einstellungen gibt es im <a href="http://owfs.org/uploads/owserver.1.html#sect41">owserver- Manual</a>.
    <br>
  </ul>
  <p>

  <a name="OWDeviceattr"></a>
  <b>Attribute</b>
  <ul>
    <li>nonblocking<br>
    Holt alle readings (OWServer / <a href="#OWDevice">OWDevice</a>) über einen Tochterprozess. Dieses Verfahren stellt sicher,
    dass FHEM während der Kommunikation mit owserver nicht angehalten wird.<br>
    Beispiel:<br>
    <code> attr &lt;name&gt; nonblocking 1</code>
    </li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
  Hinweis: Falls in FHEM trotzdem ungewöhnliche Stillstände auftreten, sollte das Attribut <code>nonblocking</code> wieder deaktiviert werden.<br>  

</ul>

=end html_DE
=cut
