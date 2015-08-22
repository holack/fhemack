#!/usr/bin/perl

################################################################
#
#  Copyright notice
#
#  (c) 2005-2014
#  Copyright: Rudolf Koenig (r dot koenig at koeniglich dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
#  Homepage:  http://fhem.de
#
# $Id: fhem.pl 8690 2015-06-04 16:47:20Z rudolfkoenig $


use strict;
use warnings;
use IO::Socket;
use Time::HiRes qw(gettimeofday);
use Scalar::Util qw(looks_like_number);
use Errno qw(:POSIX);

##################################################
# Forward declarations
#
sub AddDuplicate($$);
sub AnalyzeCommand($$;$);
sub AnalyzeCommandChain($$;$);
sub AnalyzeInput($);
sub AnalyzePerlCommand($$);
sub AssignIoPort($;$);
sub AttrVal($$$);
sub CallFn(@);
sub CheckDuplicate($$@);
sub CommandChain($$);
sub Debug($);
sub DoSet(@);
sub Dispatch($$$);
sub DoTrigger($$@);
sub EvalSpecials($%);
sub FileRead($);
sub FileWrite($@);
sub FmtDateTime($);
sub FmtTime($);
sub GetLogLevel(@);
sub GetTimeSpec($);
sub GlobalAttr($$$$);
sub HandleArchiving($);
sub HandleTimeout();
sub IOWrite($@);
sub InternalTimer($$$$);
sub InternalVal($$$);
sub IsDisabled($);
sub IsDummy($);
sub IsIgnored($);
sub IsIoDummy($);
sub LoadModule($;$);
sub Log($$);
sub Log3($$$);
sub OldTimestamp($);
sub OldValue($);
sub OpenLogfile($);
sub PrintHash($$);
sub ReadingsNum($$$);
sub ReadingsTimestamp($$$);
sub ReadingsVal($$$);
sub RemoveInternalTimer($);
sub ReplaceEventMap($$$);
sub ResolveDateWildcards($@);
sub SemicolonEscape($);
sub SignalHandling();
sub TimeNow();
sub Value($);
sub WakeUpFn($);
sub WriteStatefile();
sub XmlEscape($);
sub addEvent($$);
sub addToDevAttrList($$);
sub addToAttrList($);
sub addToWritebuffer($$@);
sub attrSplit($);
sub computeClientArray($$);
sub concatc($$$);
sub configDBUsed();
sub createNtfyHash();
sub createUniqueId();
sub devspec2array($);
sub doGlobalDef($);
sub escapeLogLine($);
sub evalStateFormat($);
sub fhem($@);
sub fhemTimeGm($$$$$$);
sub fhemTimeLocal($$$$$$);
sub fhemTzOffset($);
sub getAllAttr($);
sub getAllGets($);
sub getAllSets($);
sub getUniqueId();
sub latin1ToUtf8($);
sub myrename($$);
sub notifyRegexpChanged($$);
sub readingsBeginUpdate($);
sub readingsBulkUpdate($$$@);
sub readingsEndUpdate($$);
sub readingsSingleUpdate($$$$);
sub redirectStdinStdErr();
sub rejectDuplicate($$$);
sub setGlobalAttrBeforeFork($);
sub setReadingsVal($$$$);
sub utf8ToLatin1($);

sub CommandAttr($$);
sub CommandDefaultAttr($$);
sub CommandDefine($$);
sub CommandDefMod($$);
sub CommandDelete($$);
sub CommandDeleteAttr($$);
sub CommandDeleteReading($$);
sub CommandDisplayAttr($$);
sub CommandGet($$);
sub CommandIOWrite($$);
sub CommandInclude($$);
sub CommandInform($$);
sub CommandList($$);
sub CommandModify($$);
sub CommandQuit($$);
sub CommandReload($$;$);
sub CommandRename($$);
sub CommandRereadCfg($$);
sub CommandSave($$);
sub CommandSet($$);
sub CommandSetReading($$);
sub CommandSetstate($$);
sub CommandShutdown($$);
sub CommandSleep($$);
sub CommandTrigger($$);
sub CommandVersion($$);

# configDB special
sub cfgDB_Init;
sub cfgDB_ReadAll($);
sub cfgDB_SaveState;
sub cfgDB_SaveCfg;
sub cfgDB_AttrRead($);
sub cfgDB_ReadFile($);
sub cfgDB_UpdateFile($);
sub cfgDB_WriteFile($@);
sub cfgDB_svnId;

##################################################
# Variables:
# global, to be able to access them from modules

#Special values in %modules (used if set):
# AttrFn   - called for attribute changes
# DefFn    - define a "device" of this type
# DeleteFn - clean up (delete logfile), called by delete after UndefFn
# ExceptFn - called if the global select reports an except field
# FingerprintFn - convert messages for duplicate detection
# GetFn    - get some data from this device
# NotifyFn - call this if some device changed its properties
# ParseFn  - Interpret a raw message
# ReadFn   - Reading from a Device (see FHZ/WS300)
# ReadyFn  - check for available data, if no FD
# RenameFn - inform the device about its renameing
# SetFn    - set/activate this device
# ShutdownFn-called before shutdown
# StateFn  - set local info for this device, do not activate anything
# UndefFn  - clean up (delete timer, close fd), called by delete and rereadcfg

#Special values in %defs:
# TYPE    - The name of the module it belongs to
# STATE   - Oneliner describing its state
# NR      - its "serial" number
# DEF     - its definition
# READINGS- The readings. Each value has a "VAL" and a "TIME" component.
# FD      - FileDescriptor. Used by selectlist / readyfnlist
# IODev   - attached to io device
# CHANGED - Currently changed attributes of this device. Used by NotifyFn
# VOLATILE- Set if the definition should be saved to the "statefile"
# NOTIFYDEV - if set, the notifyFn will only be called for this device

use vars qw($devcount);         # Maximum device number, used for storing
use vars qw($fhem_started);     # used for uptime calculation
use vars qw($init_done);        #
use vars qw($internal_data);    # FileLog/DbLog -> SVG data transport
use vars qw($nextat);           # Time when next timer will be triggered.
use vars qw($readytimeout);     # Polling interval. UNIX: device search only
use vars qw($reread_active);
use vars qw($winService);       # the Windows Service object
use vars qw(%attr);             # Attributes
use vars qw(%cmds);             # Global command name hash.
use vars qw(%data);             # Hash for user data
use vars qw(%defaultattr);      # Default attributes, used by FHEM2FHEM
use vars qw(%defs);             # FHEM device/button definitions
use vars qw(%inform);           # Used by telnet_ActivateInform
use vars qw(%intAt);            # Internal at timer hash, global for benchmark
use vars qw(%modules);          # List of loaded modules (device/log/etc)
use vars qw(%ntfyHash);         # hash of devices needed to be notified.
use vars qw(%oldvalue);         # Old values, see commandref.html
use vars qw(%readyfnlist);      # devices which want a "readyfn"
use vars qw(%selectlist);       # devices which want a "select"
use vars qw(%value);            # Current values, see commandref.html
use vars qw($lastDefChange);    # number of last def/attr change
use vars qw(@structChangeHist); # Contains the last 10 structural changes
use vars qw($cmdFromAnalyze);   # used by the warnings-sub

my $AttrList = "verbose:0,1,2,3,4,5 room group comment alias ".
                "eventMap userReadings";
my $currcfgfile="";             # current config/include file
my $currlogfile;                # logfile, without wildcards
my $cvsid = '$Id: fhem.pl 8690 2015-06-04 16:47:20Z rudolfkoenig $';
my $duplidx=0;                  # helper for the above pool
my $evalSpecials;               # Used by EvalSpecials->AnalyzeCommand parameter passing
my $intAtCnt=0;
my $logopened = 0;              # logfile opened or using stdout
my $namedef = "where <name> is a single device name, a list separated by komma (,) or a regexp. See the devspec section in the commandref.html for details.\n";
my $rcvdquit;                   # Used for quit handling in init files
my $readingsUpdateDelayTrigger; # needed internally
my $sig_term = 0;               # if set to 1, terminate (saving the state)
my $wbName = ".WRITEBUFFER";    # Buffer-name for delayed writing via select
my %comments;                   # Comments from the include files
my %duplicate;                  # Pool of received msg for multi-fhz/cul setups
my @cmdList;                    # Remaining commands in a chain. Used by sleep

$init_done = 0;
$lastDefChange = 0;
$readytimeout = ($^O eq "MSWin32") ? 0.1 : 5.0;


$modules{Global}{ORDER} = -1;
$modules{Global}{LOADED} = 1;
no warnings 'qw';
my @globalAttrList = qw(
  altitude
  apiversion
  archivecmd
  archivedir
  autoload_undefined_devices:1,0
  backup_before_update
  backupcmd
  backupdir
  backupsymlink
  configfile
  dupTimeout
  exclude_from_update
  holiday2we
  language:EN,DE
  lastinclude
  latitude
  logdir
  logfile
  longitude
  modpath
  motd
  mseclog:1,0
  nofork:1,0
  nrarchive
  pidfilename
  port
  restartDelay
  restoreDirs
  sendStatistics:onUpdate,manually,never
  showInternalValues:1,0
  stacktrace:1,0
  statefile
  title
  uniqueID
  updateInBackground:1,0
  updateNoFileCheck:1,0
  version
);
use warnings 'qw';
$modules{Global}{AttrList} = join(" ", @globalAttrList);
$modules{Global}{AttrFn} = "GlobalAttr";

use vars qw($readingFnAttributes);
$readingFnAttributes = "event-on-change-reading event-on-update-reading ".
                       "event-aggregator event-min-interval stateFormat";


%cmds = (
  "?"       => { ReplacedBy => "help" },
  "attr"    => { Fn=>"CommandAttr",
           Hlp=>"<devspec> <attrname> [<attrval>],set attribute for <devspec>"},
  "createlog"=> { ModuleName => "autocreate" },
  "define"  => { Fn=>"CommandDefine",
           Hlp=>"<name> <type> <options>,define a device" },
  "defmod"  => { Fn=>"CommandDefMod",
           Hlp=>"<name> <type> <options>,define or modify a device" },
  "deleteattr" => { Fn=>"CommandDeleteAttr",
           Hlp=>"<devspec> [<attrname>],delete attribute for <devspec>" },
  "deletereading" => { Fn=>"CommandDeleteReading",
            Hlp=>"<devspec> [<attrname>],delete user defined reading for ".
                 "<devspec>" },
  "delete"  => { Fn=>"CommandDelete",
            Hlp=>"<devspec>,delete the corresponding definition(s)"},
  "displayattr"=> { Fn=>"CommandDisplayAttr",
            Hlp=>"<devspec> [attrname],display attributes" },
  "get"     => { Fn=>"CommandGet",
            Hlp=>"<devspec> <type dependent>,request data from <devspec>" },
  "include" => { Fn=>"CommandInclude",
            Hlp=>"<filename>,read the commands from <filenname>" },
  "inform" => { Fn=>"CommandInform",
            ClientFilter => "telnet",
            Hlp=>"{on|off|raw|timer|status},echo all events to this client" },
  "iowrite" => { Fn=>"CommandIOWrite",
            Hlp=>"<iodev> <data>,write raw data with iodev" },
  "list"    => { Fn=>"CommandList",
            Hlp=>"[devspec],list definitions and status info" },
  "modify"  => { Fn=>"CommandModify",
            Hlp=>"device <options>,modify the definition (e.g. at, notify)" },
  "quit"    => { Fn=>"CommandQuit",
            ClientFilter => "telnet",
            Hlp=>",end the client session" },
  "exit"    => { Fn=>"CommandQuit",
            ClientFilter => "telnet",
            Hlp=>",end the client session" },
  "reload"  => { Fn=>"CommandReload",
            Hlp=>"<module-name>,reload the given module (e.g. 99_PRIV)" },
  "rename"  => { Fn=>"CommandRename",
            Hlp=>"<old> <new>,rename a definition" },
  "rereadcfg"  => { Fn=>"CommandRereadCfg",
            Hlp=>"[configfile],read in the config after deleting everything" },
  "restore" => {
            Hlp=>"[list] [<filename|directory>],restore files saved by update"},
  "save"    => { Fn=>"CommandSave",
            Hlp=>"[configfile],write the configfile and the statefile" },
  "set"     => { Fn=>"CommandSet",
            Hlp=>"<devspec> <type dependent>,transmit code for <devspec>" },
  "setreading" => { Fn=>"CommandSetReading",
            Hlp=>"<devspec> <reading> <value>,set reading for <devspec>" },
  "setstate"=> { Fn=>"CommandSetstate",
            Hlp=>"<devspec> <state>,set the state shown in the command list" },
  "setdefaultattr" => { Fn=>"CommandDefaultAttr",
            Hlp=>"<attrname> <attrvalue>,set attr for following definitions" },
  "shutdown"=> { Fn=>"CommandShutdown",
            Hlp=>"[restart],terminate the server" },
  "sleep"  => { Fn=>"CommandSleep",
            Hlp=>"<sec> [quiet],sleep for sec, 3 decimal places" },
  "trigger" => { Fn=>"CommandTrigger",
            Hlp=>"<devspec> <state>,trigger notify command" },
  "update" => {
            Hlp => "[<fileName>|all|check|force] ".
                                      "[http://.../controlfile],update FHEM" },
  "updatefhem" => { ReplacedBy => "update" },
  "usb"     => { ModuleName => "autocreate" },
  "version" => { Fn => "CommandVersion",
            Hlp=>"[filter],print SVN version of loaded modules" },
);

###################################################
# Start the program
if(int(@ARGV) < 1) {
  print "Usage:\n";
  print "as server: fhem configfile\n";
  print "as client: fhem [host:]port cmd cmd cmd...\n";
  if($^O =~ m/Win/) {
    print "install as windows service: fhem.pl configfile -i\n";
    print "uninstall the windows service: fhem.pl -u\n";
  }
  exit(1);
}

# If started as root, and there is a fhem user in the /etc/passwd, su to it
if($^O !~ m/Win/ && $< == 0) {

  my @pw = getpwnam("fhem");
  if(@pw) {
    use POSIX qw(setuid setgid);

    # set primary group
    setgid($pw[3]);

    # read all secondary groups into an array:
    my @groups;
    while ( my ($name, $pw, $gid, $members) = getgrent() ) {
      push(@groups, $gid) if ( grep($_ eq $pw[0],split(/\s+/,$members)) );
    }

    # set the secondary groups via $)
    if (@groups) {
      $) = "$pw[3] ".join(" ",@groups);
    } else {
      $) = "$pw[3] $pw[3]";
    }

    setuid($pw[2]);
  }

}

###################################################
# Client code
if(int(@ARGV) > 1 && $ARGV[$#ARGV] ne "-i") {
  my $buf;
  my $addr = shift @ARGV;
  $addr = "localhost:$addr" if($addr !~ m/:/);
  my $client = IO::Socket::INET->new(PeerAddr => $addr);
  die "Can't connect to $addr\n" if(!$client);
  for(my $i=0; $i < int(@ARGV); $i++) {
    syswrite($client, $ARGV[$i]."\n");
  }
  shutdown($client, 1);
  while(sysread($client, $buf, 256) > 0) {
    $buf =~ s/\xff\xfb\x01Password: //;
    $buf =~ s/\xff\xfc\x01\r\n//;
    $buf =~ s/\xff\xfd\x00//;
    print($buf);
  }
  exit(0);
}
# End of client code
###################################################


###################################################
# Windows Service Support: install/remove or start the fhem service
if($^O =~ m/Win/) {
  (my $dir = $0) =~ s+[/\\][^/\\]*$++; # Find the FHEM directory
  chdir($dir);
  $winService = eval {require FHEM::WinService; FHEM::WinService->new(\@ARGV);};
  if((!$winService || $@) && ($ARGV[$#ARGV] eq "-i" || $ARGV[$#ARGV] eq "-u")) {
    print "Cannot initialize FHEM::WinService: $@, exiting.\n";
    exit 0;
  }
}
$winService ||= {};

###################################################
# Server initialization
doGlobalDef($ARGV[0]);

if(configDBUsed()) {
  eval "use configDB";
  Log 1, $@ if($@);
  cfgDB_Init();
}


# As newer Linux versions reset serial parameters after fork, we parse the
# config file after the fork. But we need some global attr parameters before, so we
# read them here.
setGlobalAttrBeforeFork($attr{global}{configfile});

Log 1, $_ for eval{@{$winService->{ServiceLog}};};

# Go to background if the logfile is a real file (not stdout)
if($^O =~ m/Win/ && !$attr{global}{nofork}) {
  $attr{global}{nofork}=1;
}
if($attr{global}{logfile} ne "-" && !$attr{global}{nofork}) {
  defined(my $pid = fork) || die "Can't fork: $!";
  exit(0) if $pid;
}

# FritzBox special: Wait until the time is set via NTP,
# but not more than 2 hours
if(time() < 2*3600) {
  Log 1, "date/time not set, waiting up to 2 hours to be set.";
  while(time() < 2*3600) {
    sleep(5);
  }
}

###################################################
# initialize the readings semantics meta information
require RTypes;
RTypes_Initialize();

my $cfgErrMsg = "Error messages while initializing FHEM:";
my $cfgRet="";
if(configDBUsed()) {
  my $ret = cfgDB_ReadAll(undef);
  $cfgRet .= "configDB: $ret" if($ret);

} else {
  my $ret = CommandInclude(undef, $attr{global}{configfile});
  $cfgRet .= "configfile: $ret" if($ret);

  if($attr{global}{statefile} && -r $attr{global}{statefile}) {
    $ret = CommandInclude(undef, $attr{global}{statefile});
    $cfgRet .= "statefile: $ret" if($ret);
  }
}

if($cfgRet) {
  $attr{global}{motd} = "$cfgErrMsg\n$cfgRet";
  Log 1, $cfgRet;

} elsif($attr{global}{motd} && $attr{global}{motd} =~ m/^$cfgErrMsg/) {
  $attr{global}{motd} = "";

}

SignalHandling();

my $pfn = $attr{global}{pidfilename};
if($pfn) {
  die "$pfn: $!\n" if(!open(PID, ">$pfn"));
  print PID $$ . "\n";
  close(PID);
}

my $gp = $attr{global}{port};
if($gp) {
  Log 3, "Converting 'attr global port $gp' to 'define telnetPort telnet $gp'";
  my $ret = CommandDefine(undef, "telnetPort telnet $gp");
  Log 1, "$ret" if($ret);
  delete($attr{global}{port});
}

my $sc_text = "SecurityCheck:";
$attr{global}{motd} = "$sc_text\n\n"
        if(!$attr{global}{motd} || $attr{global}{motd} =~ m/^$sc_text/);

$init_done = 1;
$lastDefChange = 1;

foreach my $d (keys %defs) {
  if($defs{$d}{IODevMissing}) {
    Log 3, "No I/O device found for $defs{$d}{NAME}";
    delete $defs{$d}{IODevMissing};
  }
}

DoTrigger("global", "INITIALIZED", 1);
$fhem_started = time;

$attr{global}{motd} .= "Running with root privileges."
        if($^O !~ m/Win/ && $<==0 && $attr{global}{motd} =~ m/^$sc_text/);
$attr{global}{motd} .=
        "\nRestart FHEM for a new check if the problem is fixed,\n".
        "or set the global attribute motd to none to supress this message.\n"
        if($attr{global}{motd} =~ m/^$sc_text\n\n./);
my $motd = $attr{global}{motd};
if($motd eq "$sc_text\n\n") {
  delete($attr{global}{motd});
} else {
  if($motd ne "none") {
    $motd =~ s/\n/ /g;
    Log 2, $motd;
  }
}

my $osuser = "os $^O, user ".(getlogin || getpwuid($<) || "unknown");
Log 0, "Server started with ".int(keys %defs).
        " defined entities (version $attr{global}{version}, $osuser, pid $$)";

################################################
# Main Loop
sub MAIN {MAIN:};               #Dummy


my $errcount= 0;
while (1) {
  my ($rout,$rin, $wout,$win, $eout,$ein) = ('','', '','', '','');

  my $timeout = HandleTimeout();

  foreach my $p (keys %selectlist) {
    my $hash = $selectlist{$p};
    if(defined($hash->{FD})) {
      vec($rin, $hash->{FD}, 1) = 1
        if(!defined($hash->{directWriteFn}) && !$hash->{wantWrite} );
      vec($win, $hash->{FD}, 1) = 1
        if( (defined($hash->{directWriteFn}) ||
             defined($hash->{$wbName}) || 
             $hash->{wantWrite} ) && !$hash->{wantRead} );
    }
    vec($ein, $hash->{EXCEPT_FD}, 1) = 1
        if(defined($hash->{"EXCEPT_FD"}));
  }
  $timeout = $readytimeout if(keys(%readyfnlist) &&
                              (!defined($timeout) || $timeout > $readytimeout));
  $timeout = 5 if $winService->{AsAService} && $timeout > 5;
  my $nfound = select($rout=$rin, $wout=$win, $eout=$ein, $timeout);

  $winService->{serviceCheck}->() if($winService->{serviceCheck});
  CommandShutdown(undef, undef) if($sig_term);

  if($nfound < 0) {
    my $err = int($!);
    next if($err==0 || $err==4); # 4==EINTR

    Log 1, "ERROR: Select error $nfound ($err), error count= $errcount";
    $errcount++;

    # Handling "Bad file descriptor". This is a programming error.
    if($err == 9) {  # BADF, don't want to "use errno.ph"
      my $nbad = 0;
      foreach my $p (keys %selectlist) {
        my ($tin, $tout) = ('', '');
        vec($tin, $selectlist{$p}{FD}, 1) = 1;
        if(select($tout=$tin, undef, undef, 0) < 0) {
          Log 1, "Found and deleted bad fileno for $p";
          delete($selectlist{$p});
          $nbad++;
        }
      }
      next if($nbad > 0);
      next if($errcount <= 3);
    }
    die("Select error $nfound ($err)\n");
  } else {
    $errcount= 0;
  }

  ###############################
  # Message from the hardware (FHZ1000/WS3000/etc) via select or the Ready
  # Function. The latter ist needed for Windows, where USB devices are not
  # reported by select, but is used by unix too, to check if the device is
  # attached again.
  foreach my $p (keys %selectlist) {
    my $hash = $selectlist{$p};
    my $isDev = ($hash && $hash->{NAME} && $defs{$hash->{NAME}});
    my $isDirect = ($hash && ($hash->{directReadFn} || $hash->{directWriteFn}));
    next if(!$isDev && !$isDirect);

    if(defined($hash->{FD}) && vec($rout, $hash->{FD}, 1)) {
      delete $hash->{wantRead};

      if($hash->{directReadFn}) {
        $hash->{directReadFn}($hash);
      } else {
        CallFn($hash->{NAME}, "ReadFn", $hash);
      }
    }

    if( defined($hash->{FD}) && vec($wout, $hash->{FD}, 1)) {
      delete $hash->{wantWrite};

      if($hash->{directWriteFn}) {
        $hash->{directWriteFn}($hash);

      } elsif(defined($hash->{$wbName})) {
        my $wb = $hash->{$wbName};
        alarm($hash->{ALARMTIMEOUT}) if($hash->{ALARMTIMEOUT});
        my $ret = syswrite($hash->{CD}, $wb);
        my $werr = int($!);
        alarm(0) if($hash->{ALARMTIMEOUT});

        if(!defined($ret) && $werr == EWOULDBLOCK ) {
          $hash->{wantRead} = 1
            if(TcpServer_WantRead($hash));

        } elsif(!$ret) { # zero=EOF, undef=error
          Log 4, "Write error to $p, deleting $hash->{NAME}";
          TcpServer_Close($hash);
          CommandDelete(undef, $hash->{NAME});

        } else {
          if($ret == length($wb)) {
            delete($hash->{$wbName});
            if($hash->{WBCallback}) {
              no strict "refs";
              my $ret = &{$hash->{WBCallback}}($hash);
              use strict "refs";
              delete $hash->{WBCallback};
            }
          } else {
            $hash->{$wbName} = substr($wb, $ret);
          }
        }
      }
    }

    if(defined($hash->{"EXCEPT_FD"}) && vec($eout, $hash->{EXCEPT_FD}, 1)) {
      CallFn($hash->{NAME}, "ExceptFn", $hash);
    }
  }

  foreach my $p (keys %readyfnlist) {
    next if(!$readyfnlist{$p});                 # due to rereadcfg / delete

    if(CallFn($readyfnlist{$p}{NAME}, "ReadyFn", $readyfnlist{$p})) {
      if($readyfnlist{$p}) {                    # delete itself inside ReadyFn
        CallFn($readyfnlist{$p}{NAME}, "ReadFn", $readyfnlist{$p});
      }

    }
  }

}

################################################
#Functions ahead, no more "plain" code

################################################
sub
IsDummy($)
{
  my $devname = shift;

  return 1 if(defined($attr{$devname}) && defined($attr{$devname}{dummy}));
  return 0;
}

sub
IsIgnored($)
{
  my $devname = shift;
  if($devname &&
     defined($attr{$devname}) && $attr{$devname}{ignore}) {
    Log 4, "Ignoring $devname";
    return 1;
  }
  return 0;
}

sub
IsDisabled($)
{
  my $devname = shift;
  return 0 if(!$devname || !defined($attr{$devname}));

  return 1 if($attr{$devname}{disable});
  return 3 if($defs{$devname} && $defs{$devname}{STATE} &&
              $defs{$devname}{STATE} eq "inactive");

  my $dfi = $attr{$devname}{disabledForIntervals};
  if(defined($dfi)) {
    my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
    my $hms = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
    foreach my $ft (split(" ", $dfi)) {
      my ($from, $to) = split("-", $ft);
      return 2 if($from && $to && $from le $hms && $hms le $to);
    }
  }

  return 0;
}


################################################
sub
IsIoDummy($)
{
  my $name = shift;

  return IsDummy($defs{$name}{IODev}{NAME})
                if($defs{$name} && $defs{$name}{IODev});
  return 1;
}


################################################
sub
GetLogLevel(@)
{
  my ($dev,$deflev) = @_;
  my $df = defined($deflev) ? $deflev : 2;

  return $df if(!defined($dev));
  return $attr{$dev}{loglevel}
        if(defined($attr{$dev}) && defined($attr{$dev}{loglevel}));
  return $df;
}


################################################
# the new Log with integrated loglevel checking
sub
Log3($$$)
{
  my ($dev, $loglevel, $text) = @_;

  $dev = $dev->{NAME} if(defined($dev) && ref($dev) eq "HASH");
     
  if(defined($dev) &&
     defined($attr{$dev}) &&
     defined (my $devlevel = $attr{$dev}{verbose})) {
    return if($loglevel > $devlevel);

  } else {
    return if($loglevel > $attr{global}{verbose});

  }

  my ($seconds, $microseconds) = gettimeofday();
  my @t = localtime($seconds);
  my $nfile = ResolveDateWildcards($attr{global}{logfile}, @t);
  OpenLogfile($nfile) if(!$currlogfile || $currlogfile ne $nfile);

  my $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d",
          $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0]);
  if($attr{global}{mseclog}) {
    $tim .= sprintf(".%03d", $microseconds/1000);
  }

  if($logopened) {
    print LOG "$tim $loglevel: $text\n";
  } else {
    print "$tim $loglevel: $text\n";
  }
  return undef;
}

################################################
sub
Log($$)
{
  my ($loglevel, $text) = @_;
  Log3(undef, $loglevel, $text);
}


#####################################
sub
IOWrite($@)
{
  my ($hash, @a) = @_;

  my $dev = $hash->{NAME};
  return if(IsDummy($dev) || IsIgnored($dev));
  my $iohash = $hash->{IODev};
  if(!$iohash ||
     !$iohash->{TYPE} ||
     !$modules{$iohash->{TYPE}} ||
     !$modules{$iohash->{TYPE}}{WriteFn}) {
    Log 5, "No IO device or WriteFn found for $dev";
    return;
  }

  return if(IsDummy($iohash->{NAME}));

  no strict "refs";
  my $ret = &{$modules{$iohash->{TYPE}}{WriteFn}}($iohash, @a);
  use strict "refs";
  return $ret;
}

#####################################
sub
CommandIOWrite($$)
{
  my ($cl, $param) = @_;
  my @a = split(" ", $param);

  return "Usage: iowrite <iodev> <param> ..." if(int(@a) < 2);

  my $name = shift(@a);
  my $hash = $defs{$name};
  return "$name not found" if(!$hash);
  return undef if(IsDummy($name) || IsIgnored($name));
  if(!$hash->{TYPE} ||
     !$modules{$hash->{TYPE}} ||
     !$modules{$hash->{TYPE}}{WriteFn}) {
    Log 1, "No IO device or WriteFn found for $name";
    return;
  }
  unshift(@a, "") if(int(@a) == 1);
  no strict "refs";
  my $ret = &{$modules{$hash->{TYPE}}{WriteFn}}($hash, @a);
  use strict "refs";
  return $ret;
}


#####################################
# i.e. split a line by ; (escape ;;), and execute each
sub
AnalyzeCommandChain($$;$)
{
  my ($c, $cmd, $allowed) = @_;
  my @ret;

  if($cmd =~ m/^[ \t]*(#.*)?$/) {      # Save comments
    if(!$init_done) {
      if($currcfgfile ne AttrVal("global", "statefile", "")) {
        my $nr =  $devcount++;
        $comments{$nr}{TEXT} = $cmd;
        $comments{$nr}{CFGFN} = $currcfgfile
            if($currcfgfile ne AttrVal("global", "configfile", ""));
      }
    }
    return undef;
  }

  $cmd =~ s/^\s*#.*$//s; # Remove comments at the beginning of the line

  $cmd =~ s/;;/SeMiCoLoN/g;
  my @saveCmdList = @cmdList;   # Needed for recursive calls
  @cmdList = split(";", $cmd);
  my $subcmd;
  while(defined($subcmd = shift @cmdList)) {
    $subcmd =~ s/SeMiCoLoN/;/g;
    my $lret = AnalyzeCommand($c, $subcmd, $allowed);
    push(@ret, $lret) if(defined($lret));
  }
  @cmdList = @saveCmdList;
  $evalSpecials = undef;
  return join("\n", @ret) if(@ret);
  return undef;
}

#####################################
sub
AnalyzePerlCommand($$)
{
  my ($cl, $cmd) = @_;

  $cmd =~ s/\\ *\n/ /g;               # Multi-line. Probably not needed anymore

  # Make life easier for oneliners:
  %value = ();
  foreach my $d (keys %defs) {
    $value{$d} = $defs{$d}{STATE}
  }
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
  my $hms = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
  my $we = (($wday==0 || $wday==6) ? 1 : 0);
  if(!$we) {
    my $h2we = $attr{global}{holiday2we};
    if($h2we && $value{$h2we}) {
      my ($a, $b) = ReplaceEventMap($h2we, [$h2we, $value{$h2we}], 0);
      $we = 1 if($b ne "none");
    }
  }
  $month++;
  $year+=1900;

  if($evalSpecials) {
    $cmd = join("", map { my $n = substr($_,1);
                          my $v = $evalSpecials->{$_};
                          $v =~ s/(['\\])/\\$1/g;
                          "my \$$n='$v';";
                        } keys %{$evalSpecials})
           . $cmd;
    # Normally this is deleted in AnalyzeCommandChain, but ECMDDevice calls us
    # directly, and combining perl with something else isnt allowed anyway.
    $evalSpecials = undef;
  }

  $cmdFromAnalyze = $cmd;
  my $ret = eval $cmd;
  $ret = $@ if($@);
  $cmdFromAnalyze = undef;
  return $ret;
}

sub
AnalyzeCommand($$;$)
{
  my ($cl, $cmd, $allowed) = @_;

  $cmd = "" if(!defined($cmd)); # Forum #29963
  $cmd =~ s/^(\n|[ \t])*//;# Strip space or \n at the begginning
  $cmd =~ s/[ \t]*$//;

  Log 5, "Cmd: >$cmd<";
  return undef if(!$cmd);

  if($cmd =~ m/^{.*}$/s) {              # Perl code
    return "Forbidden command $cmd." if($allowed && $allowed !~ m/\bperl\b/);
    return AnalyzePerlCommand($cl, $cmd);
  }

  if($cmd =~ m/^"(.*)"$/s) { # Shell code in bg, to be able to call us from it
    return "Forbidden command $cmd." if($allowed && $allowed !~ m/\bshell\b/);
    if($evalSpecials) {
      map { $ENV{substr($_,1)} = $evalSpecials->{$_}; } keys %{$evalSpecials};
    }
    my $out = "";
    $out = ">> $currlogfile 2>&1" if($currlogfile ne "-" && $^O ne "MSWin32");
    system("$1 $out &");
    return undef;
  }

  $cmd =~ s/^[ \t]*//;
  if($evalSpecials) {
    map { my $n = substr($_,1); my $v = $evalSpecials->{$_};
          $cmd =~ s/\$$n/$v/g; } keys %{$evalSpecials};
  }
  my ($fn, $param) = split("[ \t][ \t]*", $cmd, 2);
  return undef if(!$fn);

  #############
  # Search for abbreviation
  if(!defined($cmds{$fn})) {
    foreach my $f (sort keys %cmds) {
      if(length($f) > length($fn) && lc(substr($f,0,length($fn))) eq lc($fn)) {
        Log 5, "$fn => $f";
        $fn = $f;
        last;
      }
    }
  }
  $fn = $cmds{$fn}{ReplacedBy}
                if(defined($cmds{$fn}) && defined($cmds{$fn}{ReplacedBy}));

  return "Forbidden command $fn." if($allowed && $allowed !~ m/\b$fn\b/);

  #############
  # autoload commands.
  my $lcfn = lc($fn);
  $fn = $lcfn if(defined($cmds{$lcfn}));
  if(!defined($cmds{$fn}) || !defined($cmds{$fn}{Fn})) {
    my $modName;
    map { $modName = $_ if($lcfn eq lc($_)); } keys %modules;
    $modName = $cmds{$lcfn}{ModuleName}
                        if($cmds{$lcfn} && $cmds{$lcfn}{ModuleName});
    LoadModule($modName) if($modName);
    $fn = $lcfn if($cmds{$lcfn});
    return "Unknown command $fn, try help." if(!$cmds{$fn} || !$cmds{$fn}{Fn});
  }

  if($cl && $cmds{$fn}{ClientFilter} &&
     $cl->{TYPE} !~ m/$cmds{$fn}{ClientFilter}/) {
    return "This command ($fn) is not valid for this input channel.";
  }

  $param = "" if(!defined($param));
  no strict "refs";
  my $ret = &{$cmds{$fn}{Fn} }($cl, $param, $fn);
  use strict "refs";
  return undef if(defined($ret) && $ret eq "");
  return $ret;
}

sub
devspec2array($)
{
  my ($name) = @_;

  return "" if(!defined($name));
  if(defined($defs{$name})) {
    # FHEM2FHEM LOG mode fake device, avoid local set/attr/etc operations on it
    return "FHEM2FHEM_FAKE_$name" if($defs{$name}{FAKEDEVICE});
    return $name;
  }

  my (@ret, $isAttr);
  foreach my $l (split(",", $name)) {   # List of elements

    if(defined($defs{$l})) {
      push @ret, $l;
      next;
    }

    my @names = sort keys %defs;
    my @res;
    foreach my $dName (split(":FILTER=", $l)) {
      my ($n,$op,$re) = ("NAME","=",$dName);
      if($dName =~ m/^([^!<>]*)(=|!=|<=|>=|<|>)(.*)$/) {
        ($n,$op,$re) = ($1,$2,$3);
        $isAttr = 1;    # Compatibility: return "" instead of $name
      }
      ($n,$op,$re) = ($1,"eval","") if($dName =~ m/^{(.*)}$/);

      @res=();
      foreach my $d (@names) {
        next if($attr{$d} && $attr{$d}{ignore});

        if($op eq "eval") {
          my $exec = EvalSpecials($n, %{{"%DEVICE"=>$d}});
          push @res, $d if(AnalyzePerlCommand(undef, $exec));
          next;
        }

        my $hash = $defs{$d};
        if(!$hash->{TYPE}) {
          Log 1, "Error: $d has no TYPE";
          next;
        }
        my $val = $hash->{$n};
        if(!defined($val)) {
          my $r = $hash->{READINGS};
          $val = $r->{$n}{VAL} if($r && $r->{$n});
        }
        if(!defined($val)) {
          $val = $attr{$d}{$n} if($attr{$d});
        }
        $val="" if(!defined($val));
        $val = $val->{NAME} if(ref($val) eq 'HASH' && $val->{NAME}); # IODev

        my $lre = ($n eq "room" ? "(^|,)($re)(,|\$)" : "^($re)\$");
        my $valReNum =(looks_like_number($val) && looks_like_number($re) ? 1:0);
        eval { # a bad regexp is deadly
          if(($op eq  "=" && $val =~ m/$lre/s) ||
             ($op eq "!=" && $val !~ m/$lre/s) ||
             ($op eq "<"  && $valReNum && $val < $re) ||
             ($op eq ">"  && $valReNum && $val > $re) ||
             ($op eq "<=" && $valReNum && $val <= $re) ||
             ($op eq ">=" && $valReNum && $val >= $re)) {
            push @res, $d 
          }
        };

        if($@) {
          Log 1, "devspec2array $name: $@";
          return $name;
        }
      }
      @names = @res;
    }
    push @ret,@res;
  }
  return $name if(!@ret && !$isAttr);
  return @ret;
}

#####################################
sub
CommandInclude($$)
{
  my ($cl, $arg) = @_;
  my $fh;
  my @ret;
  my $oldcfgfile;

  if(!open($fh, $arg)) {
    return "Can't open $arg: $!";
  }
  Log 1, "Including $arg";
  if(!$init_done &&
     $arg ne AttrVal("global", "statefile", "") &&
     $arg ne AttrVal("global", "configfile", "")) {
    my $nr =  $devcount++;
    $comments{$nr}{TEXT} = "include $arg";
    $comments{$nr}{CFGFN} = $currcfgfile
          if($currcfgfile ne AttrVal("global", "configfile", ""));
  }
  $oldcfgfile  = $currcfgfile;
  $currcfgfile = $arg;

  my $bigcmd = "";
  $rcvdquit = 0;
  while(my $l = <$fh>) {
    $l =~ s/[\r\n]//g;

    if($l =~ m/^(.*)\\ *$/) {       # Multiline commands
      $bigcmd .= "$1\n";
    } else {
      my $tret = AnalyzeCommandChain($cl, $bigcmd . $l);
      push @ret, $tret if(defined($tret));
      $bigcmd = "";
    }
    last if($rcvdquit);

  }
  $currcfgfile = $oldcfgfile;
  close($fh);
  return join("\n", @ret) if(@ret);
  return undef;
}


#####################################
sub
OpenLogfile($)
{
  my $param = shift;

  close(LOG);
  $logopened=0;
  $currlogfile = $param;

  # STDOUT is closed in windows services per default
  if(!$winService->{AsAService} && $currlogfile eq "-") {
    open LOG, '>&STDOUT' || die "Can't dup stdout: $!";

  } else {

    HandleArchiving($defs{global}) if($defs{global}{currentlogfile});
    $defs{global}{currentlogfile} = $param;
    $defs{global}{logfile} = $attr{global}{logfile};

    open(LOG, ">>$currlogfile") || return("Can't open $currlogfile: $!");
    redirectStdinStdErr() if($init_done);
    
  }
  LOG->autoflush(1);
  $logopened = 1;
  return undef;
}

sub
redirectStdinStdErr()
{
  # Redirect stdin/stderr
  return if(!$currlogfile || $currlogfile eq "-");

  open STDIN,  '</dev/null'      or print "Can't read /dev/null: $!\n";

  close(STDERR);
  open(STDERR, ">>$currlogfile") or print "Can't append STDERR to log: $!\n";
  STDERR->autoflush(1);

  close(STDOUT);
  open STDOUT, '>&STDERR'        or print "Can't dup stdout: $!\n";
  STDOUT->autoflush(1);
}


#####################################
sub
CommandRereadCfg($$)
{
  my ($cl, $param) = @_;
  my $name = ($cl ? $cl->{NAME} : "__anonymous__");
  my $cfgfile = ($param ? $param : $attr{global}{configfile});
  return "Cannot open $cfgfile: $!"
        if(! -f $cfgfile && !configDBUsed());

  $attr{global}{configfile} = $cfgfile;
  WriteStatefile();

  $reread_active=1;
  $init_done = 0;
  foreach my $d (sort { $defs{$b}{NR} <=> $defs{$a}{NR} } keys %defs) {
    my $ret = CallFn($d, "UndefFn", $defs{$d}, $d)
        if($name && $name ne $d);
    Log 1, "$d is against deletion ($ret), continuing with rereadcfg anyway"
        if($ret);
    delete $defs{$d};
  }

  %comments = ();
  %defs = ();
  %attr = ();
  %selectlist = ();
  %readyfnlist = ();
  my $informMe = $inform{$name};
  %inform = ();

  doGlobalDef($cfgfile);
  my $ret;
  
  if(configDBUsed()) {
    $ret = cfgDB_ReadAll($cl);

  } else {
    setGlobalAttrBeforeFork($cfgfile);

    $ret = CommandInclude($cl, $cfgfile);
    if($attr{global}{statefile} && -r $attr{global}{statefile}) {
      my $ret2 = CommandInclude($cl, $attr{global}{statefile});
      $ret = (defined($ret) ? "$ret\n$ret2" : $ret2) if(defined($ret2));
    }
  }

  $defs{$name} = $selectlist{$name} = $cl if($name && $name ne "__anonymous__");
  $inform{$name} = $informMe if($informMe);
  @structChangeHist = ();
  $lastDefChange++;
  DoTrigger("global", "REREADCFG", 1);

  $init_done = 1;
  $reread_active=0;
  return $ret;
}

#####################################
sub
CommandQuit($$)
{
  my ($cl, $param) = @_;

  if(!$cl) {
    $rcvdquit = 1;
  } else {
    $cl->{rcvdQuit} = 1;
    return "Bye..." if($cl->{prompt});
  }
  return undef;
}

#####################################
sub
WriteStatefile()
{
  if(configDBUsed()) {
    return cfgDB_SaveState();
  }

  return "No statefile specified" if(!$attr{global}{statefile});
  if(!open(SFH, ">$attr{global}{statefile}")) {
    my $msg = "WriteStateFile: Cannot open $attr{global}{statefile}: $!";
    Log 1, $msg;
    return $msg;
  }

  my $t = localtime;
  print SFH "#$t\n";

  foreach my $d (sort keys %defs) {
    next if($defs{$d}{TEMPORARY});
    if($defs{$d}{VOLATILE}) {
      my $def = $defs{$d}{DEF};
      $def =~ s/;/;;/g; # follow-on-for-timer at
      print SFH "define $d $defs{$d}{TYPE} $def\n";
    }

    my $val = $defs{$d}{STATE};
    if(defined($val) &&
       $val ne "unknown" &&
       $val ne "Initialized" &&
       $val ne "???") {
      $val =~ s/;/;;/g;
      $val =~ s/\n/\\\n/g;
      print SFH "setstate $d $val\n"
    }

    #############
    # Now the detailed list
    my $r = $defs{$d}{READINGS};
    if($r) {
      foreach my $c (sort keys %{$r}) {

        my $rd = $r->{$c};
        if(!defined($rd->{TIME})) {
          Log 4, "WriteStatefile $d $c: Missing TIME, using current time";
          $rd->{TIME} = TimeNow();
        }

        if(!defined($rd->{VAL})) {
          Log 4, "WriteStatefile $d $c: Missing VAL, setting it to 0";
          $rd->{VAL} = 0;
        }
        my $val = $rd->{VAL};
        $val =~ s/;/;;/g;
        $val =~ s/\n/\\\n/g;
        print SFH "setstate $d $rd->{TIME} $c $val\n";
      }
    }
  }

  return "$attr{global}{statefile}: $!" if(!close(SFH));
  return "";
}

#####################################
sub
CommandSave($$)
{
  my ($cl, $param) = @_;

  if($param && $param eq "?") {
    return "No structural changes." if(!@structChangeHist);
    return "Last 10 structural changes:\n  ".join("\n  ", @structChangeHist);
  }

  @structChangeHist = ();
  DoTrigger("global", "SAVE", 1);

  my $ret =  WriteStatefile();
  return $ret if($ret);
  $ret = "";    # cfgDB_SaveState may return undef

  if(configDBUsed()) {
    $ret = cfgDB_SaveCfg();
    return ($ret ? $ret : "Saved configuration to the DB");
  }

  $param = $attr{global}{configfile} if(!$param);
  return "No configfile attribute set and no argument specified" if(!$param);
  if(!open(SFH, ">$param")) {
    return "Cannot open $param: $!";
  }
  my %fh = ("configfile" => *SFH);
  my %skip;

  my %devByNr;
  map { $devByNr{$defs{$_}{NR}} = $_ } keys %defs;

  for(my $i = 0; $i < $devcount; $i++) {

    my ($h, $d);
    if($comments{$i}) {
      $h = $comments{$i};

    } else {
      $d = $devByNr{$i};
      next if(!defined($d) ||
              $defs{$d}{TEMPORARY} || # e.g. WEBPGM connections
              $defs{$d}{VOLATILE});   # e.g at, will be saved to the statefile
      $h = $defs{$d};
    }

    my $cfgfile = $h->{CFGFN} ? $h->{CFGFN} : "configfile";
    my $fh = $fh{$cfgfile};
    if(!$fh) {
      if(!open($fh, ">$cfgfile")) {
        $ret .= "Cannot open $cfgfile: $!, ignoring its content\n";
        $fh{$cfgfile} = 1;
        $skip{$cfgfile} = 1;
      } else {
        $fh{$cfgfile} = $fh;
      }
    }
    next if($skip{$cfgfile});

    if(!defined($d)) {
      print $fh $h->{TEXT},"\n";
      next;
    }

    if($d ne "global") {
      my $def = $defs{$d}{DEF};
      if(defined($def)) {
        $def =~ s/;/;;/g;
        $def =~ s/\n/\\\n/g;
        print $fh "define $d $defs{$d}{TYPE} $def\n";
      } else {
        print $fh "define $d $defs{$d}{TYPE}\n";
      }
    }

    foreach my $a (sort {
                     return -1 if($a eq "userattr"); # userattr must be first
                     return  1 if($b eq "userattr");
                     return $a cmp $b;
                   } keys %{$attr{$d}}) {
      next if($d eq "global" &&
              ($a eq "configfile" || $a eq "version"));
      my $val = $attr{$d}{$a};
      $val =~ s/;/;;/g;
      $val =~ s/\n/\\\n/g;
      print $fh "attr $d $a $val\n";
    }
  }
  print SFH "include $attr{global}{lastinclude}\n"
        if($attr{global}{lastinclude});

  foreach my $key (keys %fh) {
    next if($fh{$key} eq "1"); ## R/O include files
    $ret .= "$key: $!" if(!close($fh{$key}));
  }

  return ($ret ? $ret : "Wrote configuration to $param");
}

#####################################
sub
CommandShutdown($$)
{
  my ($cl, $param) = @_;
  return "Usage: shutdown [restart]"
        if($param && $param ne "restart");

  DoTrigger("global", "SHUTDOWN", 1);
  Log 0, "Server shutdown";

  foreach my $d (sort keys %defs) {
    CallFn($d, "ShutdownFn", $defs{$d});
  }

  WriteStatefile();
  unlink($attr{global}{pidfilename}) if($attr{global}{pidfilename});
  if($param && $param eq "restart") {
    if ($^O !~ m/Win/) {
      system("(sleep " . AttrVal("global", "restartDelay", 2) .
                                 "; exec $^X $0 $attr{global}{configfile})&");
    } elsif ($winService->{AsAService}) {
      # use the OS SCM to stop and start the service
      exec('cmd.exe /C net stop fhem & net start fhem');
    }
  }
  exit(0);
}

#####################################
sub
DoSet(@)
{
  my @a = @_;

  my $dev = $a[0];
  my $hash = $defs{$dev};
  return "Please define $dev first" if(!$hash);
  return "Bogus entry $dev without TYPE" if(!$hash->{TYPE});
  return "No set implemented for $dev" if(!$modules{$hash->{TYPE}}{SetFn});

  # No special handling needed fo the Usage check
  return CallFn($dev, "SetFn", $hash, @a) if($a[1] && $a[1] eq "?");

  @a = ReplaceEventMap($dev, \@a, 0) if($attr{$dev}{eventMap});
  $hash->{".triggerUsed"} = 0; 
  my ($ret, $skipTrigger) = CallFn($dev, "SetFn", $hash, @a);
  return $ret if($ret);
  return undef if($skipTrigger);

  # Backward compatibility. Use readingsUpdate in SetFn now
  # case: DoSet is called from a notify triggered by DoSet with same dev
  if(defined($hash->{".triggerUsed"}) && $hash->{".triggerUsed"} == 0) {
    shift @a;
    # set arg if the module did not triggered events
    my $arg = join(" ", @a) if(!$hash->{CHANGED} || !int(@{$hash->{CHANGED}}));
    DoTrigger($dev, $arg, 0);
  }
  delete($hash->{".triggerUsed"});

  return undef;
}


#####################################
sub
CommandSet($$)
{
  my ($cl, $param) = @_;
  my @a = split("[ \t][ \t]*", $param);
  return "Usage: set <name> <type-dependent-options>\n$namedef" if(int(@a)<1);

  my @rets;
  foreach my $sdev (devspec2array($a[0])) {

    $a[0] = $sdev;
    my $ret = DoSet(@a);
    push @rets, $ret if($ret);

  }
  return join("\n", @rets);
}


#####################################
sub
CommandGet($$)
{
  my ($cl, $param) = @_;

  my @a = split("[ \t][ \t]*", $param);
  return "Usage: get <name> <type-dependent-options>\n$namedef" if(int(@a) < 1);


  my @rets;
  foreach my $sdev (devspec2array($a[0])) {
    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }
    if(!$modules{$defs{$sdev}{TYPE}}{GetFn}) {
      push @rets, "No get implemented for $sdev";
      next;
    }

    $a[0] = $sdev;
    my $ret = CallFn($sdev, "GetFn", $defs{$sdev}, @a);
    push @rets, $ret if(defined($ret) && $ret ne "");
  }
  return join("\n", @rets);
}

#####################################
sub
LoadModule($;$)
{
  my ($m, $ignoreErr) = @_;

  if($modules{$m} && !$modules{$m}{LOADED}) {   # autoload
    my $o = $modules{$m}{ORDER};
    my $ret = CommandReload(undef, "${o}_$m", $ignoreErr);
    if($ret) {
      Log 0, $ret if(!$ignoreErr);
      return "UNDEFINED";
    }

    if(!$modules{$m}{LOADED}) {                 # Case corrected by reload?
      foreach my $i (keys %modules) {
        if(uc($m) eq uc($i) && $modules{$i}{LOADED}) {
          delete($modules{$m});
          $m = $i;
          last;
        }
      }
    }
  }
  return $m;
}

#####################################
sub
CommandDefine($$)
{
  my ($cl, $def) = @_;
  my @a = split("[ \t]+", $def, 3);
  my $ignoreErr;

  # used by RSS in fhem.cfg.demo, with no GD installed
  if($a[0] && $a[0] eq "-ignoreErr") {
    $def =~ s/\s*-ignoreErr\s*//;
    @a = split("[ \t][ \t]*", $def, 3);
    $ignoreErr = 1;
  }
  my $name = $a[0];
  return "Usage: define <name> <type> <type dependent arguments>"
                if(int(@a) < 2);
  return "$name already defined, delete it first" if(defined($defs{$name}));
  return "Invalid characters in name (not A-Za-z0-9.:_): $name"
                        if($name !~ m/^[a-z0-9.:_]*$/i);

  my $m = $a[1];
  if(!$modules{$m}) {                           # Perhaps just wrong case?
    foreach my $i (keys %modules) {
      if(uc($m) eq uc($i)) {
        $m = $i;
        last;
      }
    }
  }

  my $newm = LoadModule($m, $ignoreErr);
  return "Cannot load module $m" if($newm eq "UNDEFINED");
  $m = $newm;

  return "Unknown module $m" if(!$modules{$m} || !$modules{$m}{DefFn});

  my %hash;

  $hash{NAME}  = $name;
  $hash{TYPE}  = $m;
  $hash{STATE} = "???";
  $hash{DEF}   = $a[2] if(int(@a) > 2);
  $hash{NR}    = $devcount++;
  $hash{CFGFN} = $currcfgfile
        if($currcfgfile ne AttrVal("global", "configfile", ""));

  # If the device wants to issue initialization gets/sets, then it needs to be
  # in the global hash.
  $defs{$name} = \%hash;

  my $ret = CallFn($name, "DefFn", \%hash, $def);
  if($ret) {
    Log 1, "define $name $def: $ret";
    delete $defs{$name};                            # Veto
    delete $attr{$name};

  } else {
    foreach my $da (sort keys (%defaultattr)) {     # Default attributes
      CommandAttr($cl, "$name $da $defaultattr{$da}");
    }
    if($modules{$m}{NotifyFn} && !$hash{NTFY_ORDER}) {
      $hash{NTFY_ORDER} = ($modules{$m}{NotifyOrderPrefix} ?
                $modules{$m}{NotifyOrderPrefix} : "50-") . $name;
    }
    %ntfyHash = ();
    addStructChange("define", $name, $def);
    DoTrigger("global", "DEFINED $name", 1) if($init_done);
  }
  return $ret;
}

#####################################
sub
CommandModify($$)
{
  my ($cl, $def) = @_;
  my @a = split("[ \t]+", $def, 2);

  return "Usage: modify <name> <type dependent arguments>"
                if(int(@a) < 1);

  # Return a list of modules
  return "Define $a[0] first" if(!defined($defs{$a[0]}));
  %ntfyHash = ();
  my $hash = $defs{$a[0]};

  $hash->{OLDDEF} = $hash->{DEF};
  $hash->{DEF} = $a[1];
  my $ret = CallFn($a[0], "DefFn", $hash,
        "$a[0] $hash->{TYPE}".(defined($a[1]) ? " $a[1]" : ""));
  if($ret) {
    $hash->{DEF} = $hash->{OLDDEF};
  } else {
    addStructChange("modify", $a[0], $def);
    DoTrigger("global", "MODIFIED $a[0]", 1) if($init_done);
  }

  delete($hash->{OLDDEF});
  return $ret;
}

#####################################
sub
CommandDefMod($$)
{
  my ($cl, $def) = @_;
  my @a = split("[ \t]+", $def, 3);
  return "Usage: defmod <name> <type> <type dependent arguments>"
                if(int(@a) < 2);
  if($defs{$a[0]}) {
    $def = $a[2] ? "$a[0] $a[2]" : $a[0];
    return CommandModify($cl, $def);
  } else {
    return CommandDefine($cl, $def);
  }
}

#############
# internal
sub
AssignIoPort($;$)
{
  my ($hash, $proposed) = @_;
  my $ht = $hash->{TYPE};
  my $hn = $hash->{NAME};
  my $hasIODevAttr = ($ht &&
                      $modules{$ht}{AttrList} &&
                      $modules{$ht}{AttrList} =~ m/IODev/);

  $proposed = $attr{$hn}{IODev}
        if(!$proposed && $attr{$hn} && $attr{$hn}{IODev});
  
  if($proposed && $defs{$proposed}) {
    $hash->{IODev} = $defs{$proposed};
    $attr{$hn}{IODev} = $proposed if($hasIODevAttr);
    delete($defs{$proposed}{".clientArray"});
    return;
  }
  # Set the I/O device, search for the last compatible one.
  for my $p (sort { $defs{$b}{NR} <=> $defs{$a}{NR} } keys %defs) {

    my $cl = $defs{$p}{Clients};
    $cl = $modules{$defs{$p}{TYPE}}{Clients} if(!$cl);

    if($cl && $defs{$p}{NAME} ne $hn) {      # e.g. RFR
      my @fnd = grep { $hash->{TYPE} =~ m/^$_$/; } split(":", $cl);
      if(@fnd) {
        $hash->{IODev} = $defs{$p};
        delete($defs{$p}{".clientArray"}); # Force a recompute
        last;
      }
    }
  }
  if($hash->{IODev}) {
    # See CUL_WS_Attr() for details
    $attr{$hn}{IODev} = $hash->{IODev}{NAME}
      if($hasIODevAttr && $hash->{TYPE} ne "CUL_WS");

  } else {
    if($init_done) {
      Log 3, "No I/O device found for $hn";
    } else {
      $hash->{IODevMissing} = 1;
    }
  }
  return undef;
}


#############
sub
CommandDelete($$)
{
  my ($cl, $def) = @_;
  return "Usage: delete <name>$namedef\n" if(!$def);

  my @rets;
  foreach my $sdev (devspec2array($def)) {
    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    my $ret = CallFn($sdev, "UndefFn", $defs{$sdev}, $sdev);
    if($ret) {
      push @rets, $ret;
      next;
    }
    $ret = CallFn($sdev, "DeleteFn", $defs{$sdev}, $sdev);
    if($ret) {
      push @rets, $ret;
      next;
    }


    # Delete releated hashes
    foreach my $p (keys %selectlist) {
      if($selectlist{$p} && $selectlist{$p}{NAME} eq $sdev) {
        delete $selectlist{$p};
      }
    }
    foreach my $p (keys %readyfnlist) {
      delete $readyfnlist{$p}
        if($readyfnlist{$p} && $readyfnlist{$p}{NAME} eq $sdev);
    }

    my $temporary = $defs{$sdev}{TEMPORARY};
    addStructChange("delete", $sdev, $sdev) if(!$temporary);
    delete($attr{$sdev});
    delete($defs{$sdev});
    DoTrigger("global", "DELETED $sdev", 1) if(!$temporary);

  }
  return join("\n", @rets);
}

#############
sub
CommandDeleteAttr($$)
{
  my ($cl, $def) = @_;

  my @a = split(" ", $def, 2);
  return "Usage: deleteattr <name> [<attrname>]\n$namedef" if(@a < 1);

  my @rets;
  foreach my $sdev (devspec2array($a[0])) {

    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    $a[0] = $sdev;
    
    if($a[1] && $a[1] eq "userReadings") {
      delete($defs{$sdev}{'.userReadings'});
    }

    my $ret = CallFn($sdev, "AttrFn", "del", @a);
    if($ret) {
      push @rets, $ret;
      next;
    }

    if(@a == 1) {
      delete($attr{$sdev});
      addStructChange("deleteAttr", $sdev, $sdev);
      DoTrigger("global", "DELETEATTR $sdev", 1) if($init_done);

    } else {
      delete($attr{$sdev}{$a[1]}) if(defined($attr{$sdev}));
      addStructChange("deleteAttr", $sdev, join(" ", @a));
      DoTrigger("global", "DELETEATTR $sdev $a[1]", 1) if($init_done);

    }

  }

  return join("\n", @rets);
}

#############
sub
CommandDisplayAttr($$)
{
  my ($cl, $def) = @_;

  my @a = split(" ", $def, 2);
  return "Usage: displayattr <name> [<attrname>]\n$namedef" if(@a < 1);

  my @rets;
  my @devspec = devspec2array($a[0]);

  foreach my $sdev (@devspec) {

    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    my $ap = $attr{$sdev};
    next if(!$ap);
    my $d = (@devspec > 1 ? "$sdev " : "");

    if(defined($a[1])) {
      push @rets, "$d$ap->{$a[1]}" if(defined($ap->{$a[1]}));

    } else {
      push @rets, map { "$d$_ $ap->{$_}" } sort keys %{$ap};

    }

  }

  return join("\n", @rets);
}

#############
sub
CommandDeleteReading($$)
{
  my ($cl, $def) = @_;

  my @a = split(" ", $def, 2);
  return "Usage: deletereading <name> <reading>\n$namedef" if(@a != 2);

  eval { "" =~ m/$a[1]/ };
  return "Bad regexp $a[1]: $@" if($@);

  %ntfyHash = ();
  my @rets;
  foreach my $sdev (devspec2array($a[0])) {

    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    $a[0] = $sdev;
    my $readingspec= '^' . $a[1] . '$';

    foreach my $reading (grep { /$readingspec/ }
                                keys %{$defs{$sdev}{READINGS}} ) {
      delete($defs{$sdev}{READINGS}{$reading});
      push @rets, "Deleted reading $reading for device $sdev";
    }
    
  }
  return join("\n", @rets);
}

sub
CommandSetReading($$)
{
  my ($cl, $def) = @_;

  my @a = split(" ", $def, 3);
  return "Usage: setreading <name> <reading> <value>\n$namedef" if(@a != 3);

  my @rets;
  foreach my $sdev (devspec2array($a[0])) {

    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }
    readingsSingleUpdate($defs{$sdev}, $a[1], $a[2], 1);
  }
  return join("\n", @rets);
}


#############
sub
PrintHash($$)
{
  my ($h, $lev) = @_;
  my $si = AttrVal("global", "showInternalValues", 0);
  return "" if($h->{".visited"});
  $h->{".visited"} = 1;

  my ($str,$sstr) = ("","");
  foreach my $c (sort keys %{$h}) {
    next if(!$si && $c =~ m/^\./ || $c eq ".visited");
    if(ref($h->{$c})) {
      if(ref($h->{$c}) eq "HASH") {
        if(defined($h->{$c}{TIME}) && defined($h->{$c}{VAL})) {
          $str .= sprintf("%*s %-19s   %-15s %s\n",
                          $lev," ", $h->{$c}{TIME},$c,$h->{$c}{VAL});
        } elsif($c eq "IODev" || $c eq "HASH") {
          $str .= sprintf("%*s %-10s %s\n", $lev," ",$c, $h->{$c}{NAME});

        } else {
          $sstr .= sprintf("%*s %s:\n",
                          $lev, " ", uc(substr($c,0,1)).lc(substr($c,1)));
          $sstr .= PrintHash($h->{$c}, $lev+2);
        }
      } elsif(ref($h->{$c}) eq "ARRAY") {
         $sstr .= sprintf("%*s %s:\n", $lev, " ", $c);
         foreach my $v (@{$h->{$c}}) {
           $sstr .= sprintf("%*s %s\n", $lev+2, " ", $v);
         }
      }
    } else {
      my $v = $h->{$c};
      $str .= sprintf("%*s %-10s %s\n", $lev," ",$c, defined($v) ? $v : "");
    }
  }
  delete $h->{".visited"};
  return $str . $sstr;
}

#####################################
sub
CommandList($$)
{
  my ($cl, $param) = @_;
  my $str = "";

  if(!$param) { # List of all devices

    $str = "\nType list <name> for detailed info.\n";
    my $lt = "";

    # Sort first by type then by name
    for my $d (sort { my $x=$modules{$defs{$a}{TYPE}}{ORDER}.$defs{$a}{TYPE} cmp
                            $modules{$defs{$b}{TYPE}}{ORDER}.$defs{$b}{TYPE};
                         $x=($a cmp $b) if($x == 0); $x; } keys %defs) {
      next if(IsIgnored($d));
      my $t = $defs{$d}{TYPE};
      $str .= "\n$t:\n" if($t ne $lt);
      $str .= sprintf("  %-20s (%s)\n", $d, $defs{$d}{STATE});
      $lt = $t;
    }

  } else { # devspecArray

    my @arg = split(" ", $param);
    my @list = devspec2array($arg[0]);
    if($arg[1]) {
      foreach my $sdev (@list) { # Show a Hash-Entry or Reading for each device

        if($defs{$sdev}) {
          if(defined($defs{$sdev}{$arg[1]})) {
            my $val = $defs{$sdev}{$arg[1]};
            $val = $val->{NAME} if(ref($val) eq 'HASH' && $val->{NAME});
            $str .= sprintf("%-20s %s\n", $sdev, $val);

          } elsif($defs{$sdev}{READINGS} &&
                  defined($defs{$sdev}{READINGS}{$arg[1]})) {
            $str .= sprintf("%-20s %s %s\n", $sdev,
                    $defs{$sdev}{READINGS}{$arg[1]}{TIME},
                    $defs{$sdev}{READINGS}{$arg[1]}{VAL});

          } elsif($attr{$sdev} && 
                  defined($attr{$sdev}{$arg[1]})) {
            $str .= sprintf("%-20s %s\n", $sdev, $attr{$sdev}{$arg[1]});

          }
        }
      }

    } elsif(@list == 1) { # Details
      my $sdev = $list[0];
      if(!defined($defs{$sdev})) {
        $str .= "No device named $param found";
      } else {
        $str .= "Internals:\n";
        $str .= PrintHash($defs{$sdev}, 2);
        $str .= "Attributes:\n";
        $str .= PrintHash($attr{$sdev}, 2);
      }

    } else {
      foreach my $sdev (@list) {         # List of devices
        $str .= "$sdev\n";
      }

    }
  }

  return $str;
}


#####################################
sub
CommandReload($$;$)
{
  my ($cl, $param, $ignoreErr) = @_;
  my %hash;
  $param =~ s,/,,g;
  $param =~ s,\.pm$,,g;
  my $file = "$attr{global}{modpath}/FHEM/$param.pm";
  my $cfgDB = '-';
  if( ! -r "$file" ) {
    if(configDBUsed()) {
      # try to find the file in configDB
      my $r = _cfgDB_Fileexport($file); # create file temporarily
      return "Can't read $file from configDB." if ($r =~ m/^0/);
      $cfgDB = 'X';
    } else {
      # configDB not used and file not found: it's a real error!
      return "Can't read $file: $!";
    }
  }

  my $m = $param;
  $m =~ s,^([0-9][0-9])_,,;
  my $order = (defined($1) ? $1 : "00");
  Log 5, "Loading $file";

  no strict "refs";
  my $ret = eval {
    my $ret=do "$file";
    unlink($file) if($cfgDB eq 'X'); # delete temp file
    if(!$ret) {
      Log 1, "reload: Error:Modul $param deactivated:\n $@" if(!$ignoreErr);
      return $@;
    }

    # Get the name of the initialize function. This may differ from the
    # filename as sometimes we live on a FAT fs with wrong case.
    my $fnname = $m;
    foreach my $i (keys %main::) {
      if($i =~ m/^(${m})_initialize$/i) {
        $fnname = $1;
        last;
      }
    }
    &{ "${fnname}_Initialize" }(\%hash);
    $m = $fnname;
    return undef;
  };
  use strict "refs";

  return "$@" if($@);
  return $ret if($ret);

  my ($defptr, $ldata);
  if($modules{$m}) {
    $defptr = $modules{$m}{defptr};
    $ldata = $modules{$m}{ldata};
  }
  $modules{$m} = \%hash;
  $modules{$m}{ORDER} = $order;
  $modules{$m}{LOADED} = 1;
  $modules{$m}{defptr} = $defptr if($defptr);
  $modules{$m}{ldata} = $ldata if($ldata);

  return undef;
}

#####################################
sub
CommandRename($$)
{
  my ($cl, $param) = @_;
  my ($old, $new) = split(" ", $param);

  return "old name is empty" if(!defined($old));
  return "new name is empty" if(!defined($new));

  return "Please define $old first" if(!defined($defs{$old}));
  return "$new already defined" if(defined($defs{$new}));
  return "Invalid characters in name (not A-Za-z0-9.:_): $new"
                        if($new !~ m/^[a-z0-9.:_]*$/i);
  return "Cannot rename global" if($old eq "global");

  %ntfyHash = ();
  $defs{$new} = $defs{$old};
  $defs{$new}{NAME} = $new;
  delete($defs{$old});          # The new pointer will preserve the hash

  $attr{$new} = $attr{$old} if(defined($attr{$old}));
  delete($attr{$old});

  $oldvalue{$new} = $oldvalue{$old} if(defined($oldvalue{$old}));
  delete($oldvalue{$old});

  CallFn($new, "RenameFn", $new,$old);# ignore replies

  addStructChange("rename", $new, $param);
  DoTrigger("global", "RENAMED $old $new", 1);
  return undef;
}

#####################################
sub
getAllAttr($)
{
  my $d = shift;
  return "" if(!$defs{$d});

  my $list = $AttrList; # Global values
  $list .= " " . $modules{$defs{$d}{TYPE}}{AttrList}
        if($modules{$defs{$d}{TYPE}}{AttrList});
  $list .= " " . $attr{global}{userattr}
        if($attr{global}{userattr});
  $list .= " " . $attr{$d}{userattr}
        if($attr{$d} && $attr{$d}{userattr});
  $list .= " userattr";
  return $list;
}

#####################################
sub
getAllGets($)
{
  my $d = shift;
  
  my $a2 = CommandGet(undef, "$d ?");
  return "" if($a2 !~ m/unknown.*choose one of /i);
  $a2 =~ s/.*choose one of //;
  return $a2;
}

#####################################
sub
getAllSets($)
{
  my $d = shift;
  
  if(AttrVal("global", "apiversion", 1)> 1) {
    my @setters= getSetters($defs{$d});
    return join(" ", @setters);
  }

  my $a2 = CommandSet(undef, "$d ?");
  $a2 =~ s/.*choose one of //;
  $a2 = "" if($a2 =~ /^No set implemented for/);
  return "" if($a2 eq "");

  $a2 = $defs{$d}{".eventMapCmd"}." $a2" if(defined($defs{$d}{".eventMapCmd"}));
  return $a2;
}

sub
GlobalAttr($$$$)
{
  my ($type, $me, $name, $val) = @_;

  return if($type ne "set");
  ################
  if($name eq "logfile") {
    my @t = localtime;
    my $ret = OpenLogfile(ResolveDateWildcards($val, @t));
    if($ret) {
      return $ret if($init_done);
      die($ret);
    }
  }

  ################
  elsif($name eq "verbose") {
    if($val =~ m/^[0-5]$/) {
      return undef;
    } else {
      $attr{global}{verbose} = 3;
      return "Valid value for verbose are 0,1,2,3,4,5";
    }
  }

  elsif($name eq "modpath") {
    return "modpath must point to a directory where the FHEM subdir is"
        if(! -d "$val/FHEM");
    my $modpath = "$val/FHEM";

    opendir(DH, $modpath) || return "Can't read $modpath: $!";
    push @INC, $modpath if(!grep(/\Q$modpath\E/, @INC));
    $attr{global}{version} = $cvsid;
    my $counter = 0;

    if(configDBUsed()) {
      my $list = cfgDB_Read99(); # retrieve filelist from configDB
      if($list) {
        foreach my $m (split(/,/,$list)) {
          $m =~ m/^([0-9][0-9])_(.*)\.pm$/;
          CommandReload(undef, $m) if(!$modules{$2}{LOADED});
          $counter++;
        }
      }
    }

    foreach my $m (sort readdir(DH)) {
      next if($m !~ m/^([0-9][0-9])_(.*)\.pm$/);
      $modules{$2}{ORDER} = $1;
      CommandReload(undef, $m)                  # Always load utility modules
         if($1 eq "99" && !$modules{$2}{LOADED});
      $counter++;
    }
    closedir(DH);

    if(!$counter) {
      return "No modules found, set modpath to a directory in which a " .
             "subdirectory called \"FHEM\" exists wich in turn contains " .
             "the fhem module files <*>.pm";
    }


  }

  return undef;
}

#####################################
sub
CommandAttr($$)
{
  my ($cl, $param) = @_;
  my ($ret, @a);

  @a = split(" ", $param, 3) if($param);

  return "Usage: attr <name> <attrname> [<attrvalue>]\n$namedef"
           if(@a && @a < 2);

  my @rets;
  foreach my $sdev (devspec2array($a[0])) {

    my $hash = $defs{$sdev};
    my $attrName = $a[1];
    if(!defined($hash)) {
      push @rets, "Please define $sdev first" if($init_done);#define -ignoreErr
      next;
    }

    my $list = getAllAttr($sdev);
    if($attrName eq "?") {
      push @rets, "$sdev: unknown attribute $attrName, choose one of $list";
      next;
    }

    if(" $list " !~ m/ ${attrName}[ :;]/) {
       my $found = 0;
       foreach my $atr (split("[ \t]", $list)) { # is it a regexp?
         if(${attrName} =~ m/^$atr$/) {
           $found++;
           last;
         }
      }
      if(!$found) {
        push @rets, "$sdev: unknown attribute $attrName. ".
                        "Type 'attr $a[0] ?' for a detailed list.";
        next;
      }
    }

    if($attrName eq 'disable' and $a[2] && $a[2] eq 'toggle') {
       $a[2] = IsDisabled($sdev) ? 0 : 1;
    }

    if($attrName eq "userReadings") {

      my %userReadings;
      # myReading1[:trigger1] [modifier1] { codecodecode1 }, ...
      my $arg= $a[2];

      # matches myReading1[:trigger2] { codecode1 }
      my $regexi= '\s*([\w.-]+)(:\S*)?\s+((\w+)\s+)?({.*?})\s*';
      my $regexo= '^(' . $regexi . ')(,\s*(.*))*$';

      #Log 1, "arg is $arg";

      while($arg =~ /$regexo/) {
        my $userReading= $2;
        my $trigger= $3 ? $3 : undef;
        my $modifier= $5 ? $5 : "none";
        my $perlCode= $6;
        #Log 1, sprintf("userReading %s has perlCode %s with modifier %s%s",
        # $userReading,$perlCode,$modifier,$trigger?" and trigger $trigger":"");
        if(grep { /$modifier/ }
                qw(none difference differential offset monotonic integral)) {
          $trigger =~ s/^:// if($trigger);
          $userReadings{$userReading}{trigger}= $trigger;
          $userReadings{$userReading}{modifier}= $modifier;
          $userReadings{$userReading}{perlCode}= $perlCode;
        } else {
          push @rets, "$sdev: unknown modifier $modifier for ".
                "userReading $userReading, this userReading will be ignored";
        }
        $arg= defined($8) ? $8 : "";
      }
      $hash->{'.userReadings'}= \%userReadings;
    } 

    if($attrName eq "IODev" && (!$a[2] || !defined($defs{$a[2]}))) {
      push @rets,"$sdev: unknown IODev specified";
      next;
    }

    if($attrName eq "eventMap") {
      delete $hash->{".eventMapHash"};
      delete $hash->{".eventMapCmd"};
      $attr{$sdev}{eventMap} = (defined $a[2] ? $a[2] : 1);
      my $r = ReplaceEventMap($sdev, "test", 1); # refresh eventMapCmd
      if($r =~ m/^ERROR in eventMap for /) {
        delete($attr{$sdev}{eventMap});
        return $r;
      }
    }

    $a[0] = $sdev;
    my $oVal = ($attr{$sdev} ? $attr{$sdev}{$attrName} : "");
    $ret = CallFn($sdev, "AttrFn", "set", @a);
    if($ret) {
      push @rets, $ret;
      next;
    }

    my $val = $a[2];
    $val = 1 if(!defined($val));
    $attr{$sdev}{$attrName} = $val;

    if($attrName eq "IODev") {
      my $ioname = $a[2];
      $hash->{IODev} = $defs{$ioname};
      $hash->{NR} = $devcount++
        if($defs{$ioname}{NR} > $hash->{NR});
      delete($defs{$ioname}{".clientArray"}); # Force a recompute
    }
    if($attrName eq "stateFormat" && $init_done) {
      evalStateFormat($hash);
    }
    addStructChange("attr", $sdev, $param) if(!defined($oVal) || $oVal ne $val);
    DoTrigger("global", "ATTR $sdev $attrName $val", 1) if($init_done);

  }

  Log 3, join(" ", @rets) if(!$cl && @rets);
  return join("\n", @rets);
}


#####################################
# Default Attr
sub
CommandDefaultAttr($$)
{
  my ($cl, $param) = @_;

  my @a = split(" ", $param, 2);
  if(int(@a) == 0) {
    %defaultattr = ();
  } elsif(int(@a) == 1) {
    $defaultattr{$a[0]} = 1;
  } else {
    $defaultattr{$a[0]} = $a[1];
  }
  return undef;
}

#####################################
sub
CommandSetstate($$)
{
  my ($cl, $param) = @_;

  my @a = split(" ", $param, 2);
  return "Usage: setstate <name> <state>\n$namedef" if(@a != 2);

  my @rets;
  foreach my $sdev (devspec2array($a[0])) {
    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    my $d = $defs{$sdev};

    # Detailed state with timestamp
    if($a[1] =~ m/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) +([^ ].*)$/) {
      my ($tim, $nameval) =  ($1, $2);
      my ($sname, $sval) = split(" ", $nameval, 2);
      (undef, $sval) = ReplaceEventMap($sdev, [$sdev, $sval], 0)
                                if($attr{$sdev}{eventMap});
      my $ret = CallFn($sdev, "StateFn", $d, $tim, $sname, $sval);
      if($ret) {
        push @rets, $ret;
        next;
      }

      if(!defined($d->{READINGS}{$sname}) ||
         !defined($d->{READINGS}{$sname}{TIME}) ||
         $d->{READINGS}{$sname}{TIME} lt $tim) {
        $d->{READINGS}{$sname}{VAL} = $sval;
        $d->{READINGS}{$sname}{TIME} = $tim;
      }

    } else {

      # The timestamp is not the correct one, but we do not store a timestamp
      # for this reading.
      my $tn = TimeNow();
      $oldvalue{$sdev}{TIME} = $tn;
      $oldvalue{$sdev}{VAL} = ($init_done ? $d->{STATE} : $a[1]);

      # Do not overwrite state like "opened" or "initialized"
      $d->{STATE} = $a[1] if($init_done || $d->{STATE} eq "???");
      my $ret = CallFn($sdev, "StateFn", $d, $tn, "STATE", $a[1]);
      if($ret) {
        push @rets, $ret;
        next;
      }

    }
  }
  return join("\n", @rets);
}

#####################################
sub
CommandTrigger($$)
{
  my ($cl, $param) = @_;

  my ($dev, $state) = split(" ", $param, 2);
  return "Usage: trigger <name> <state>\n$namedef" if(!$dev);
  $state = "" if(!defined($state));

  my @rets;
  foreach my $sdev (devspec2array($dev)) {
    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }
    my $ret = DoTrigger($sdev, $state);
    if($ret) {
      push @rets, $ret;
      next;
    }
  }
  return join("\n", @rets);
}

#####################################
sub
CommandInform($$)
{
  my ($cl, $param) = @_;

  return if(!$cl);
  my $name = $cl->{NAME};

  return "Usage: inform {on|timer|raw|off} [regexp]"
        if($param !~ m/^(on|off|raw|timer|status)/);

  if($param eq "status") {
    my $i = $inform{$name};
    return $i ? ($i->{type} . ($i->{regexp} ? " ".$i->{regexp} : "")) : "off";
  }

  delete($inform{$name});
  if($param !~ m/^off/) {
    my ($type, $regexp) = split(" ", $param);
    $inform{$name}{NR} = $cl->{NR};
    $inform{$name}{type} = $type;
    if($regexp) {
      eval { "Hallo" =~ m/$regexp/ };
      return "Bad regexp: $@" if($@);
      $inform{$name}{regexp} = $regexp;
    }
    Log 4, "Setting inform to $param";

  }

  return undef;
}

#####################################
sub
WakeUpFn($)
{
  my $h = shift;
  $evalSpecials = $h->{evalSpecials};
  my $ret = AnalyzeCommandChain(undef, $h->{cmd});
  Log 2, "After sleep: $ret" if($ret && !$h->{quiet});
}


sub
CommandSleep($$)
{
  my ($cl, $param) = @_;
  my ($sec, $quiet) = split(" ", $param);

  return "Argument missing" if(!defined($sec));
  return "Cannot interpret $sec as seconds" if($sec !~ m/^[0-9\.]+$/);
  return "Second parameter must be quiet" if($quiet && $quiet ne "quiet");

  Log 4, "sleeping for $sec";

  if(@cmdList && $sec && $init_done) {
    my %h = (cmd          => join(";", @cmdList),
             evalSpecials => $evalSpecials,
             quiet        => $quiet);
    InternalTimer(gettimeofday()+$sec, "WakeUpFn", \%h, 0);
    @cmdList=();

  } else {
    select(undef, undef, undef, $sec);

  }
  return undef;
}

#####################################
sub
CommandVersion($$)
{
  my ($cl, $param) = @_;

  my @ret = ("# $cvsid");
  push @ret, cfgDB_svnId if(configDBUsed());
  foreach my $m (sort keys %modules) {
    next if(!$modules{$m}{LOADED} || $modules{$m}{ORDER} < 0);
    Log 4, "Looking for SVN Id in module $m";
    my $fn = "$attr{global}{modpath}/FHEM/".$modules{$m}{ORDER}."_$m.pm";
    if(!open(FH, $fn)) {
      my $ret = "$fn: $!";
      if(configDBUsed()){
        Log 4, "Looking for module $m in configDB to find SVN Id";
        $ret = cfgDB_Fileversion($fn,$ret);
      }
      push @ret, $ret;
    } else {
      push @ret, map { chomp; $_ } grep(/# \$Id:/, <FH>);
    }
  }
  if($param) {
    return join("\n", grep /$param/, @ret);
  } else {
    return join("\n", @ret);
  }
}

#####################################
# Return the time to the next event (or undef if there is none)
# and call each function which was scheduled for this time
sub
HandleTimeout()
{
  return undef if(!$nextat);

  my $now = gettimeofday();
  return ($nextat-$now) if($now < $nextat);

  $now += 0.01;# need to cover min delay at least
  $nextat = 0;
  #############
  # Check the internal list.
  foreach my $i (sort { $intAt{$a}{TRIGGERTIME} <=>
                        $intAt{$b}{TRIGGERTIME} } keys %intAt) {
    my $tim = $intAt{$i}{TRIGGERTIME};
    my $fn = $intAt{$i}{FN};
    if(!defined($tim) || !defined($fn)) {
      delete($intAt{$i});
      next;
    } elsif($tim <= $now) {
      no strict "refs";
      &{$fn}($intAt{$i}{ARG});
      use strict "refs";
      delete($intAt{$i});
    } else {
      $nextat = $tim if(!$nextat || $nextat > $tim);
    }
  }

  return undef if(!$nextat);
  $now = gettimeofday(); # possibly some tasks did timeout in the meantime
                         # we will cover them 
  return ($now+ 0.01 < $nextat) ? ($nextat-$now) : 0.01;
}


#####################################
sub
InternalTimer($$$$)
{
  my ($tim, $fn, $arg, $waitIfInitNotDone) = @_;

  if(!$init_done && $waitIfInitNotDone) {
    select(undef, undef, undef, $tim-gettimeofday());
    no strict "refs";
    &{$fn}($arg);
    use strict "refs";
    return;
  }
  $intAt{$intAtCnt}{TRIGGERTIME} = $tim;
  $intAt{$intAtCnt}{FN} = $fn;
  $intAt{$intAtCnt}{ARG} = $arg;
  $intAtCnt++;
  $nextat = $tim if(!$nextat || $nextat > $tim);
}

sub
RemoveInternalTimer($)
{
  my ($arg) = @_;
  foreach my $a (keys %intAt) {
    delete($intAt{$a}) if($intAt{$a}{ARG} eq $arg);
  }
}

#####################################
sub
stacktrace() {
  
  my $i = 1;
  my $max_depth = 50;
  
  Log 3, "stacktrace:";
  while( (my @call_details = (caller($i++))) && ($i<$max_depth) ) {
    Log 3, sprintf ("    %-35s called by %s (%s)",
               $call_details[3], $call_details[1], $call_details[2]);
  }
}

my $inWarnSub;

sub
SignalHandling()
{
  if($^O ne "MSWin32") {
    $SIG{INT}  = sub { exit() };
    $SIG{TERM} = sub { $sig_term = 1; };
    $SIG{PIPE} = 'IGNORE';
    $SIG{CHLD} = 'IGNORE';
    $SIG{HUP}  = sub { CommandRereadCfg(undef, "") };
    $SIG{ALRM} = sub { Log 1, "ALARM signal, blocking write?" };
    #$SIG{'XFSZ'} = sub { Log 1, "XFSZ signal" }; # to test with limit filesize 
  }
  $SIG{__WARN__} = sub {
    my ($msg) = @_;

    return if($inWarnSub);
    if(!$attr{global}{stacktrace} && $data{WARNING}{$msg}) {
      $data{WARNING}{$msg}++;
      return;
    }
    $inWarnSub = 1;
    $data{WARNING}{$msg}++;
    chomp($msg);
    Log 1, "PERL WARNING: $msg"; 
    Log 3, "eval: $cmdFromAnalyze" if($cmdFromAnalyze && $msg =~ m/\(eval /);
    stacktrace() if($attr{global}{stacktrace} &&
                    $attr{global}{verbose} >= 3 &&
                    $msg !~ m/ redefined at /);
    $inWarnSub = 0;
  };  
  # $SIG{__DIE__} = sub {...} #Removed. Forum #35796
}


#####################################
sub
TimeNow()
{
  return FmtDateTime(time());
}

#####################################
sub
FmtDateTime($)
{
  my @t = localtime(shift);
  return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
      $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
}

sub
FmtTime($)
{
  my @t = localtime(shift);
  return sprintf("%02d:%02d:%02d", $t[2], $t[1], $t[0]);
}

#####################################
sub
CommandChain($$)
{
  my ($retry, $list) = @_;
  my $ov = $attr{global}{verbose};
  my $oid = $init_done;

  $init_done = 0;       # Rudi: ???
  $attr{global}{verbose} = 1; # ???
  foreach my $cmd (@{$list}) {
    for(my $n = 0; $n < $retry; $n++) {
      Log 1, sprintf("Trying again $cmd (%d out of %d)", $n+1,$retry) if($n>0);
      my $ret = AnalyzeCommand(undef, $cmd);
      last if(!defined($ret) || $ret !~ m/Timeout/);
    }
  }
  $attr{global}{verbose} = $ov;
  $init_done = $oid;
}

#####################################
sub
ResolveDateWildcards($@)
{
  use POSIX qw(strftime);

  my ($f, @t) = @_;
  return $f if(!$f);
  return $f if($f !~ m/%/);     # Be fast if there is no wildcard
  $f =~ s/%L/$attr{global}{logdir}/g if($attr{global}{logdir}); #log directory
  return strftime($f,@t);
}

sub
SemicolonEscape($)
{
  my $cmd = shift;
  $cmd =~ s/^[ \t]*//;
  $cmd =~ s/[ \t]*$//;
  if($cmd =~ m/^{.*}$/s || $cmd =~ m/^".*"$/s) {
    $cmd =~ s/;/;;/g
  }
  return $cmd;
}

sub
EvalSpecials($%)
{
  # The character % will be replaced with the received event,
  #     e.g. with on or off or measured-temp: 21.7 (Celsius)
  # The character @ will be replaced with the device name.
  # To use % or @ in the text itself, use the double mode (%% or @@).
  # Instead of % and @, the parameters %EVENT (same as %),
  #     %NAME (same as @) and %TYPE (contains the device type, e.g. FHT)
  #     can be used. A single % looses its special meaning if any of these
  #     parameters appears in the definition.
  my ($exec, %specials)= @_;
  $exec = SemicolonEscape($exec);

  # %EVTPART due to HM remote logic
  my $idx = 0;
  if(defined($specials{"%EVENT"})) {
    foreach my $part (split(" ", $specials{"%EVENT"})) {
      $specials{"%EVTPART$idx"} = $part;
      $idx++;
    }
  }

  my $re = join("|", keys %specials);
  $re =~ s/%//g;
  if($exec =~ m/\$($re)\b/) {
    $evalSpecials = \%specials;
    return $exec;
  }

  $exec =~ s/%%/____/g;


  # perform macro substitution
  my $extsyntax= 0;
  foreach my $special (keys %specials) {
    $extsyntax+= ($exec =~ s/$special/$specials{$special}/g);
  }
  if(!$extsyntax) {
    $exec =~ s/%/$specials{"%EVENT"}/g;
  }
  $exec =~ s/____/%/g;

  $exec =~ s/@@/____/g;
  $exec =~ s/@/$specials{"%NAME"}/g;
  $exec =~ s/____/@/g;

  return $exec;
}

#####################################
# Parse a timespec: Either HH:MM:SS or HH:MM or { perfunc() }
sub
GetTimeSpec($)
{
  my ($tspec) = @_;
  my ($hr, $min, $sec, $fn);

  if($tspec =~ m/^([0-9]+):([0-5][0-9]):([0-5][0-9])$/) {
    ($hr, $min, $sec) = ($1, $2, $3);
  } elsif($tspec =~ m/^([0-9]+):([0-5][0-9])$/) {
    ($hr, $min, $sec) = ($1, $2, 0);
  } elsif($tspec =~ m/^{(.*)}$/) {
    $fn = $1;
    $tspec = AnalyzeCommand(undef, "{$fn}");
    if(!$@ && $tspec =~ m/^([0-9]+):([0-5][0-9]):([0-5][0-9])$/) {
      ($hr, $min, $sec) = ($1, $2, $3);
    } elsif(!$@ && $tspec =~ m/^([0-9]+):([0-5][0-9])$/) {
      ($hr, $min, $sec) = ($1, $2, 0);
    } else {
      $tspec = "<empty string>" if(!$tspec);
      return ("the at function \"$fn\" must return a timespec and not $tspec.",
                undef, undef, undef, undef);
    }
  } else {
    return ("Wrong timespec $tspec: either HH:MM:SS or {perlcode}",
                undef, undef, undef, undef);
  }
  return (undef, $hr, $min, $sec, $fn);
}


sub
deviceEvents($$)
{
  my ($hash, $withState) = @_;

  return undef if(!$hash || !$hash->{CHANGED});

  if($withState) {
    my $cws = $hash->{CHANGEDWITHSTATE};
    if(defined($cws)){
      if(int(@{$cws}) == 0) {
        @{$cws} = @{$hash->{CHANGED}};
        push @{$cws}, "state: $hash->{READINGS}{state}{VAL}"
                if($hash->{READINGS} && $hash->{READINGS}{state});
      }
      return $cws;
    }
  }
  return $hash->{CHANGED};
}

#####################################
# Do the notification
sub
DoTrigger($$@)
{
  my ($dev, $newState, $noreplace) = @_;
  my $ret = "";
  my $hash = $defs{$dev};
  return "" if(!defined($hash));

  $hash->{".triggerUsed"} = 1 if(defined($hash->{".triggerUsed"}));
  if(defined($newState)) {
    if($hash->{CHANGED}) {
      push @{$hash->{CHANGED}}, $newState;
    } else {
      $hash->{CHANGED}[0] = $newState;
    }
  } elsif(!defined($hash->{CHANGED})) {
    return "";
  }

  if(!$noreplace) {     # Backward compatibility for code without readingsUpdate
    if($attr{$dev}{eventMap}) {
      my $c = $hash->{CHANGED};
      for(my $i = 0; $i < @{$c}; $i++) {
        $c->[$i] = ReplaceEventMap($dev, $c->[$i], 1);
      }
      $hash->{STATE} = ReplaceEventMap($dev, $hash->{STATE}, 1);
    }
  }

  my $max = int(@{$hash->{CHANGED}});
  Log 5, "Triggering $dev ($max changes)";
  return "" if(defined($attr{$dev}) && defined($attr{$dev}{do_not_notify}));
  my $now = TimeNow();

  ################
  # Log/notify modules
  # If modifying a device in its own trigger, do not call the triggers from
  # the inner loop.
  if($max && !defined($hash->{INTRIGGER})) {
    $hash->{INTRIGGER}=1;
    Log 5, "Notify loop for $dev $hash->{CHANGED}->[0]";
    createNtfyHash() if(!%ntfyHash);
    $hash->{NTFY_TRIGGERTIME} = $now; # Optimize FileLog
    my $ntfyLst = (defined($ntfyHash{$dev}) ? $ntfyHash{$dev} : $ntfyHash{"*"});
    foreach my $n (@{$ntfyLst}) {
      next if(!defined($defs{$n}));     # Was deleted in a previous notify
      my $r = CallFn($n, "NotifyFn", $defs{$n}, $hash);
      $ret .= " $n:$r" if($r);
    }
    delete($hash->{NTFY_TRIGGERTIME});

    ################
    # Inform
    if($hash->{CHANGED}) {    # It gets deleted sometimes (?)
      $max = int(@{$hash->{CHANGED}}); # can be enriched in the notifies
      foreach my $c (keys %inform) {
        my $dc = $defs{$c};
        if(!$dc || $dc->{NR} != $inform{$c}{NR}) {
          delete($inform{$c});
          next;
        }
        next if($inform{$c}{type} eq "raw");
        my $tn = $now;
        if($attr{global}{mseclog}) {
          my ($seconds, $microseconds) = gettimeofday();
          $tn .= sprintf(".%03d", $microseconds/1000);
        }
        my $re = $inform{$c}{regexp};
        for(my $i = 0; $i < $max; $i++) {
          my $state = $hash->{CHANGED}[$i];
          next if($re && !($dev =~ m/$re/ || "$dev:$state" =~ m/$re/));
          addToWritebuffer($dc,($inform{$c}{type} eq "timer" ? "$tn " : "").
                                "$hash->{TYPE} $dev $state\n");
        }
      }
    }

    delete($hash->{INTRIGGER});
  }


  ####################
  # Used by triggered perl programs to check the old value
  # Not suited for multi-valued devices (KS300, etc)
  $oldvalue{$dev}{TIME} = $now;
  $oldvalue{$dev}{VAL} = $hash->{STATE};

  if(!defined($hash->{INTRIGGER})) {
    delete($hash->{CHANGED});
    delete($hash->{CHANGEDWITHSTATE});
  }

  Log 3, "NTFY return: $ret" if($ret);

  return $ret;
}

#####################################
# Wrapper for calling a module function
sub
CallFn(@)
{
  my $d = shift;
  my $n = shift;

  if(!$d || !$defs{$d}) {
    $d = "<undefined>" if(!defined($d));
    Log 0, "Strange call for nonexistent $d: $n";
    return undef;
  }
  if(!$defs{$d}{TYPE}) {
    Log 0, "Strange call for typeless $d: $n";
    return undef;
  }
  my $fn = $modules{$defs{$d}{TYPE}}{$n};
  return "" if(!$fn);
  if(wantarray) {
    no strict "refs";
    my @ret = &{$fn}(@_);
    use strict "refs";
    return @ret;
  } else {
    no strict "refs";
    my $ret = &{$fn}(@_);
    use strict "refs";
    return $ret;
  }
}

#####################################
# Used from perl oneliners inside of scripts
sub
fhem($@)
{
  my ($param, $silent) = @_;
  my $ret = AnalyzeCommandChain(undef, $param);
  Log 3, "$param : $ret" if($ret && !$silent);
  return $ret;
}

#####################################
# initialize the global device
sub
doGlobalDef($)
{
  my ($arg) = @_;

  $devcount = 1;
  $defs{global}{NR}    = $devcount++;
  $defs{global}{TYPE}  = "Global";
  $defs{global}{STATE} = "<no definition>";
  $defs{global}{DEF}   = "<no definition>";
  $defs{global}{NAME}  = "global";

  CommandAttr(undef, "global verbose 3");
  CommandAttr(undef, "global configfile $arg");
  CommandAttr(undef, "global logfile -");
}

#####################################
# rename does not work over Filesystems: lets copy it
sub
myrename($$)
{
  my ($from, $to) = @_;

  if(!open(F, $from)) {
    Log(1, "Rename: Cannot open $from: $!");
    return;
  }
  if(!open(T, ">$to")) {
    Log(1, "Rename: Cannot open $to: $!");
    return;
  }
  while(my $l = <F>) {
    print T $l;
  }
  close(F);
  close(T);
  unlink($from);
}

#####################################
# Make a directory and its parent directories if needed.
sub
HandleArchiving($)
{
  my ($log) = @_;
  my $ln = $log->{NAME};
  return if(!$attr{$ln});

  # If there is a command, call that
  my $cmd = $attr{$ln}{archivecmd};
  if($cmd) {
    $cmd =~ s/%/$log->{currentlogfile}/g;
    Log 2, "Archive: calling $cmd";
    system($cmd);
    return;
  }

  my $nra = $attr{$ln}{nrarchive};
  my $ard = $attr{$ln}{archivedir};
  return if(!defined($nra));

  # If nrarchive is set, then check the last files:
  # Get a list of files:

  my ($dir, $file);
  if($log->{logfile} =~ m,^(.+)/([^/]+)$,) {
    ($dir, $file) = ($1, $2);
  } else {
    ($dir, $file) = (".", $log->{logfile});
  }

  $file =~ s/%./.+/g;
  return if(!opendir(DH, $dir));
  my @files = sort grep {/^$file$/} readdir(DH);
  closedir(DH);

  my $max = int(@files)-$nra;
  for(my $i = 0; $i < $max; $i++) {
    if($ard) {
      Log 2, "Moving $files[$i] to $ard";
      myrename("$dir/$files[$i]", "$ard/$files[$i]");
    } else {
      Log 2, "Deleting $files[$i]";
      unlink("$dir/$files[$i]");
    }
  }
}

#####################################
# Call a logical device (FS20) ParseMessage with data from a physical device
# (FHZ). Note: $hash may be dummy, used by FHEM2FHEM
sub
Dispatch($$$)
{
  my ($hash, $dmsg, $addvals) = @_;
  my $module = $modules{$hash->{TYPE}};
  my $name = $hash->{NAME};

  Log3 $hash, 5, "$name dispatch $dmsg";

  my ($isdup, $idx) = CheckDuplicate($name, $dmsg, $module->{FingerprintFn});
  return rejectDuplicate($name,$idx,$addvals) if($isdup);

  my @found;
  my $clientArray = $hash->{".clientArray"};
  $clientArray = computeClientArray($hash, $module) if(!$clientArray);

  foreach my $m (@{$clientArray}) {
    # Module is not loaded or the message is not for this module
    next if($dmsg !~ m/$modules{$m}{Match}/i);

    if( my $ffn = $modules{$m}{FingerprintFn} ) {
      ($isdup, $idx) = CheckDuplicate($name, $dmsg, $ffn);
      return rejectDuplicate($name,$idx,$addvals) if($isdup);
    }

    no strict "refs"; $readingsUpdateDelayTrigger = 1;
    @found = &{$modules{$m}{ParseFn}}($hash,$dmsg);
    use strict "refs"; $readingsUpdateDelayTrigger = 0;
    last if(int(@found));
  }

  if(!int(@found) || !defined($found[0])) {
    my $h = $hash->{MatchList}; $h = $module->{MatchList} if(!$h);
    if(defined($h)) {
      foreach my $m (sort keys %{$h}) {
        if($dmsg =~ m/$h->{$m}/) {
          my ($order, $mname) = split(":", $m);

          if($attr{global}{autoload_undefined_devices}) {
            my $newm = LoadModule($mname);
            $mname = $newm if($newm ne "UNDEFINED");
            if($modules{$mname} && $modules{$mname}{ParseFn}) {
              no strict "refs"; $readingsUpdateDelayTrigger = 1;
              @found = &{$modules{$mname}{ParseFn}}($hash,$dmsg);
              use strict "refs"; $readingsUpdateDelayTrigger = 0;
            } else {
              Log 0, "ERROR: Cannot autoload $mname";
            }

          } else {
            Log3 $name, 3, "$name: Unknown $mname device detected, " .
                        "define one to get detailed information.";
            return undef;

          }
        }
      }
    }
    if(!int(@found) || !defined($found[0])) {
      DoTrigger($name, "UNKNOWNCODE $dmsg");
      Log3 $name, 3, "$name: Unknown code $dmsg, help me!";
      return undef;
    }
  }

  ################
  # Inform raw
  if(!$module->{noRawInform}) {
    foreach my $c (keys %inform) {
      if(!$defs{$c} || $defs{$c}{NR} != $inform{$c}{NR}) {
        delete($inform{$c});
        next;
      }
      next if($inform{$c}{type} ne "raw");
      syswrite($defs{$c}{CD}, "$hash->{TYPE} $name $dmsg\n");
    }
  }

  # Special return: Do not notify
  return undef if(!defined($found[0]) || $found[0] eq "");

  foreach my $found (@found) {

    if($found =~ m/^(UNDEFINED.*)/) {
      DoTrigger("global", $1);
      return undef;

    } else {
      if($defs{$found}) {
        if(!$defs{$found}{".noDispatchVars"}) { # CUL_HM special
          $defs{$found}{MSGCNT}++;
          my $avtrigger = ($attr{$name} && $attr{$name}{addvaltrigger});
          if($addvals) {
            foreach my $av (keys %{$addvals}) {
              $defs{$found}{"${name}_$av"} = $addvals->{$av};
              push(@{$defs{$found}{CHANGED}}, "$av: $addvals->{$av}")
                if($avtrigger);
            }
          }
          $defs{$found}{"${name}_MSGCNT"}++;
          $defs{$found}{"${name}_TIME"} = TimeNow();
          $defs{$found}{LASTInputDev} = $name;
        }
        delete($defs{$found}{".noDispatchVars"});
      }

      DoTrigger($found, undef);
    }
  }

  $duplicate{$idx}{FND} = \@found 
        if(defined($idx) && defined($duplicate{$idx}));

  return \@found;
}

sub
CheckDuplicate($$@)
{
  my ($ioname, $msg, $ffn) = @_;

  if($ffn) {
    no strict "refs";
    ($ioname,$msg) = &{$ffn}($ioname,$msg);
    use strict "refs";
    return (0, undef) if( !defined($msg) );
    #Debug "got $ffn ". $ioname .":". $msg;
  }

  my $now = gettimeofday();
  my $lim = $now-AttrVal("global","dupTimeout", 0.5);

  foreach my $oidx (keys %duplicate) {
    if($duplicate{$oidx}{TIM} < $lim) {
      delete($duplicate{$oidx});

    } elsif($duplicate{$oidx}{MSG} eq $msg &&
            $duplicate{$oidx}{ION} eq "") {
      return (1, $oidx);

    } elsif($duplicate{$oidx}{MSG} eq $msg &&
            $duplicate{$oidx}{ION} ne $ioname) {
      return (1, $oidx);

    }
  }
  #Debug "is unique";
  $duplicate{$duplidx}{ION} = $ioname;
  $duplicate{$duplidx}{MSG} = $msg;
  $duplicate{$duplidx}{TIM} = $now;
  $duplidx++;
  return (0, $duplidx-1);
}

sub
rejectDuplicate($$$)
{
  #Debug "is duplicate";
  my ($name,$idx,$addvals) = @_;
  my $found = $duplicate{$idx}{FND};
  foreach my $found (@{$found}) {
    if($addvals) {
      foreach my $av (keys %{$addvals}) {
        $defs{$found}{"${name}_$av"} = $addvals->{$av};
      }
    }
    $defs{$found}{"${name}_MSGCNT"}++;
    $defs{$found}{"${name}_TIME"} = TimeNow();
  }
  return $duplicate{$idx}{FND};
}

sub
AddDuplicate($$)
{
  $duplicate{$duplidx}{ION} = shift;
  $duplicate{$duplidx}{MSG} = shift;
  $duplicate{$duplidx}{TIM} = gettimeofday();
  $duplidx++;
}

# Add an attribute to the userattr list, if not yet present
sub
addToDevAttrList($$)
{
  my ($dev,$arg) = @_;

  my $ua = $attr{$dev}{userattr};
  $ua = "" if(!$ua);
  my %hash = map { ($_ => 1) }
             grep { " $AttrList " !~ m/ $_ / }
             split(" ", "$ua $arg");
  $attr{$dev}{userattr} = join(" ", sort keys %hash);
}

sub
addToAttrList($)
{
  addToDevAttrList("global", shift);
}

sub
attrSplit($)
{
  my ($em) = @_;
  my $sc = " ";               # Split character
  my $fc = substr($em, 0, 1); # First character of the eventMap
  if($fc eq "," || $fc eq "/") {
    $sc = $fc;
    $em = substr($em, 1);
  }
  return split($sc, $em);
}

#######################
# $dir: 0: User to Device (i.e. set) 1: Device to Usr (i.e trigger)
# $dir: 0: $str is an array pointer  1: $str is a a string
sub
ReplaceEventMap($$$)
{
  my ($dev, $str, $dir) = @_;
  my $em = $attr{$dev}{eventMap};

  return $str    if($dir && !$em);
  return @{$str} if(!$dir && (!$em || int(@{$str}) < 2 || $str->[1] eq "?"));

  return ReplaceEventMap2($dev, $str, $dir, $em) if($em =~ m/^{.*}$/);
  my @emList = attrSplit($em);

  if(!defined $defs{$dev}{".eventMapCmd"}) {
    # Delete the first word of the translation (.*:), else it will be
    # interpreted as the single possible value for a dropdown
    # Why is the .*= deleted?
    $defs{$dev}{".eventMapCmd"} = join(" ", grep { !/ / }
                  map { $_ =~ s/.*?=//s; $_ =~ s/.*?://s; "$_:noArg" } @emList);
  }

  my $dname = shift @{$str} if(!$dir);
  my $nstr = join(" ", @{$str}) if(!$dir);

  my $changed;
  foreach my $rv (@emList) {
    # Real-Event-Regexp:GivenName[:modifier]
    my ($re, $val, $modifier) = split(":", $rv, 3);
    next if(!defined($val));
    if($dir) {  # dev -> usr
      my $reIsWord = ($re =~ m/^\w*$/); # dim100% is not \w only, cant use \b
      if($reIsWord) {
        if($str =~ m/\b$re\b/) {
          $str =~ s/\b$re\b/$val/;
          $changed = 1;
        }
      } else {
        if($str =~ m/$re/) {
          $str =~ s/$re/$val/;
          $changed = 1;
        }
      }

    } else {    # usr -> dev
      if($nstr eq $val) { # for special translations like <> and <<
        $nstr = $re;
        $changed = 1;
      } else {
        my $reIsWord = ($val =~ m/^\w*$/);
        if($reIsWord) {
          if($nstr =~ m/\b$val\b/) {
            $nstr =~ s/\b$val\b/$re/;
            $changed = 1;
          }
        } elsif($nstr =~ m/$val/) {
          $nstr =~ s/$val/$re/;
          $changed = 1;
        }
      }
    }
    last if($changed);

  }
  return $str if($dir);

  if($changed) {
    my @arr = split(" ",$nstr);
    unshift @arr, $dname;
    return @arr;
  } else {
    unshift @{$str}, $dname;
    return @{$str};
  }
}

# $dir: 0:usr,$str is array pointer, 1:dev, $str is string
# perl notation: { dev=>{"re1"=>"Evt1",...}, dpy=>{"re2"=>"Set 1",...}}
sub
ReplaceEventMap2($$$)
{
  my ($dev, $str, $dir) = @_;

  my $hash = $defs{$dev};
  my $emh = $hash->{".eventMapHash"};
  if(!$emh) {
    eval "\$emh = $attr{$dev}{eventMap}";
    if($@) {
      my $msg = "ERROR in eventMap for $dev: $@";
      Log 1, $msg;
      return $msg;
    }
    $hash->{".eventMapHash"} = $emh;

    $defs{$dev}{".eventMapCmd"} = "";
    if($emh->{usr}) {
      my @cmd;
      my $fw = $emh->{fw};
      $defs{$dev}{".eventMapCmd"} = join(" ",
          map { ($fw && $fw->{$_}) ? $fw->{$_}:$_} sort keys %{$emh->{usr} });
    }
  }

  if($dir == 1) {
    $emh = $emh->{dev};
    if($emh) {
      foreach my $k (keys %{$emh}) {
        return $emh->{$k} if($str eq $k);
        return eval '"'.$emh->{$k}.'"' if($str =~ m/$k/);
      }
    }
    return $str;
  }

  $emh = $emh->{usr};
  return @{$str} if(!$emh);
    
  my $dname = shift @{$str};
  my $nstr = join(" ", @{$str});
  foreach my $k (keys %{$emh}) {
    my $nv;
    if($nstr eq $k) {
      $nv = $emh->{$k};

    } elsif($nstr =~ m/$k/) {
      $nv = eval '"'.$emh->{$k}.'"';

    }
    if($nv) {
      my @arr = split(" ",$nv);
      unshift @arr, $dname;
      return @arr;
    }
  }
  unshift @{$str}, $dname;
  return @{$str};
}

sub
setGlobalAttrBeforeFork($)
{
  my ($f) = @_;

  my ($err, @rows);
  if($f eq 'configDB') {
    @rows = cfgDB_AttrRead('global');
  } else {
    ($err, @rows) = FileRead($f);
    die("$err\n") if($err);
  }

  foreach my $l (@rows) {
    $l =~ s/[\r\n]//g;
    next if($l !~ m/^attr\s+global\s+([^\s]+)\s+(.*)$/);
    my ($n,$v) = ($1,$2);
    $v =~ s/#.*//;
    $v =~ s/ .*$//;
    $attr{global}{$n} = $v;
    GlobalAttr("set", "global", $n, $v);
  }
}


###########################################
# Functions used to make fhem-oneliners more readable,
# but also recommended to be used by modules
sub
InternalVal($$$)
{
  my ($d,$n,$default) = @_;
  if(defined($defs{$d}) &&
     defined($defs{$d}{$n})) {
     return $defs{$d}{$n};
  }
  return $default;
}

sub
ReadingsVal($$$)
{
  my ($d,$n,$default) = @_;
  if(defined($defs{$d}) &&
     defined($defs{$d}{READINGS}) &&
     defined($defs{$d}{READINGS}{$n}) &&
     defined($defs{$d}{READINGS}{$n}{VAL})) {
     return $defs{$d}{READINGS}{$n}{VAL};
  }
  return $default;
}

sub
ReadingsNum($$$)
{
  my ($d,$n,$default) = @_;
  my $val = ReadingsVal($d,$n,$default);
  $val =~ s/[^-\.\d]//g;
  return $val;
}

sub
ReadingsTimestamp($$$)
{
  my ($d,$n,$default) = @_;
  if(defined($defs{$d}) &&
     defined($defs{$d}{READINGS}) &&
     defined($defs{$d}{READINGS}{$n}) &&
     defined($defs{$d}{READINGS}{$n}{TIME})) {
     return $defs{$d}{READINGS}{$n}{TIME};
  }
  return $default;
}

sub
Value($)
{
  my ($d) = @_;
  if(defined($defs{$d}) &&
     defined($defs{$d}{STATE})) {
     return $defs{$d}{STATE};
  }
  return "";
}

sub
OldValue($)
{
  my ($d) = @_;
  return $oldvalue{$d}{VAL} if(defined($oldvalue{$d})) ;
  return "";
}

sub
OldTimestamp($)
{
  my ($d) = @_;
  return $oldvalue{$d}{TIME} if(defined($oldvalue{$d})) ;
  return "";
}

sub
AttrVal($$$)
{
  my ($d,$n,$default) = @_;
  return $attr{$d}{$n} if($d && defined($attr{$d}) && defined($attr{$d}{$n}));
  return $default;
}

################################################################
# Functions used by modules.
sub
setReadingsVal($$$$)
{
  my ($hash,$rname,$val,$ts) = @_;
  $hash->{READINGS}{$rname}{VAL} = $val;
  $hash->{READINGS}{$rname}{TIME} = $ts;
}

sub
addEvent($$)
{
  my ($hash,$event) = @_;
  push(@{$hash->{CHANGED}}, $event);
}

sub 
concatc($$$) {
  my ($separator,$a,$b)= @_;;
  return($a && $b ?  $a . $separator . $b : $a . $b);
}

################################################################
#
# Wrappers for commonly used core functions in device-specific modules. 
#
################################################################

#
# Call readingsBeginUpdate before you start updating readings.
# The updated readings will all get the same timestamp,
# which is the time when you called this subroutine.
#
sub 
readingsBeginUpdate($)
{
  my ($hash)= @_;
  my $name = $hash->{NAME};
  
  # get timestamp
  my $now = gettimeofday();
  my $fmtDateTime = FmtDateTime($now);
  $hash->{".updateTime"} = $now; # in seconds since the epoch
  $hash->{".updateTimestamp"} = $fmtDateTime;

  my $attrminint = AttrVal($name, "event-min-interval", undef);
  if($attrminint) {
    my @a = split(/,/,$attrminint);
    $hash->{".attrminint"} = \@a;
  }
  
  my $attraggr = AttrVal($name, "event-aggregator", undef);
  if($attraggr) {
    my @a = split(/,/,$attraggr);
    $hash->{".attraggr"} = \@a;
  }

  my $attreocr= AttrVal($name, "event-on-change-reading", undef);
  if($attreocr) {
    my @a = split(/,/,$attreocr);
    $hash->{".attreocr"} = \@a;
  }
  
  my $attreour= AttrVal($name, "event-on-update-reading", undef);
  if($attreour) {
    my @a = split(/,/,$attreour);
    $hash->{".attreour"} = \@a;
  }

  $hash->{CHANGED}= () if(!defined($hash->{CHANGED}));
  return $fmtDateTime;
}

sub
evalStateFormat($)
{
  my ($hash) = @_;

  my $name = $hash->{NAME};

  ###########################
  # Set STATE
  my $sr = AttrVal($name, "stateFormat", undef);
  my $st = $hash->{READINGS}{state};
  if(!$sr) {
    $st = $st->{VAL} if(defined($st));

  } elsif($sr =~ m/^{(.*)}$/) {
    $st = eval $1;
    if($@) {
      $st = "Error evaluating $name stateFormat: $@";
      Log 1, $st;
    }

  } else {
    # Substitute reading names with their values, leave the rest untouched.
    $st = $sr;
    my $r = $hash->{READINGS};
    $st =~ s/\b([A-Za-z\d_\.-]+)\b/($r->{$1} ? $r->{$1}{VAL} : $1)/ge;

  }
  $hash->{STATE} = ReplaceEventMap($name, $st, 1) if(defined($st));
}

#
# Call readingsEndUpdate when you are done updating readings.
# This optionally calls DoTrigger to propagate the changes.
#
sub
readingsEndUpdate($$)
{
  my ($hash,$dotrigger)= @_;
  my $name = $hash->{NAME};

  $hash->{".triggerUsed"} = 1 if(defined($hash->{".triggerUsed"}));

  # process user readings
  if(defined($hash->{'.userReadings'})) {
    my %userReadings= %{$hash->{'.userReadings'}};
    foreach my $userReading (keys %userReadings) {

      my $trigger = $userReadings{$userReading}{trigger};
      if(defined($trigger)) {
        my @fnd = grep { $_ && $_ =~ m/^$trigger/ } @{$hash->{CHANGED}};
        next if(!@fnd);
      }

      my $modifier= $userReadings{$userReading}{modifier};
      my $perlCode= $userReadings{$userReading}{perlCode};
      my $oldvalue= $userReadings{$userReading}{value};
      my $oldt= $userReadings{$userReading}{t};
      #Debug "Evaluating " . $userReadings{$userReading};
      $cmdFromAnalyze = $perlCode;      # For the __WARN__ sub
      my $value= eval $perlCode;
      $cmdFromAnalyze = undef;
      my $result;
      # store result
      if($@) {
        $value = "Error evaluating $name userReading $userReading: $@";
        Log 1, $value;
        $result= $value;
      } elsif($modifier eq "none") {
        $result= $value;
      } elsif($modifier eq "difference") {
        $result= $value - $oldvalue if(defined($oldvalue));
      } elsif($modifier eq "differential") {
        my $deltav= $value - $oldvalue if(defined($oldvalue));
        my $deltat= $hash->{".updateTime"} - $oldt if(defined($oldt));
        if(defined($deltav) && defined($deltat) && ($deltat>= 1.0)) {
          $result= $deltav/$deltat;
        }
      } elsif($modifier eq "integral") {
        if(defined($oldt) && defined($oldvalue)) {
          my $deltat= $hash->{".updateTime"} - $oldt if(defined($oldt));
          my $avgval= ($value + $oldvalue) / 2;
          $result = ReadingsVal($name,$userReading,$value);
          if(defined($deltat) && $deltat>= 1.0) {
            $result+= $avgval*$deltat;
          }
        }
      } elsif($modifier eq "offset") {
        $oldvalue = $value if( !defined($oldvalue) );
        $result = ReadingsVal($name,$userReading,0);
        $result += $oldvalue if( $value < $oldvalue );
      } elsif($modifier eq "monotonic") {
        $oldvalue = $value if( !defined($oldvalue) );
        $result = ReadingsVal($name,$userReading,$value);
        $result += $value - $oldvalue if( $value > $oldvalue );
      } 
      readingsBulkUpdate($hash,$userReading,$result,1) if(defined($result));
      # store value
      $hash->{'.userReadings'}{$userReading}{TIME}= $hash->{".updateTimestamp"};
      $hash->{'.userReadings'}{$userReading}{t}= $hash->{".updateTime"};
      $hash->{'.userReadings'}{$userReading}{value}= $value;
    }
  }
  evalStateFormat($hash);

  # turn off updating mode
  delete $hash->{".updateTimestamp"};
  delete $hash->{".updateTime"};
  delete $hash->{".attreour"};
  delete $hash->{".attreocr"};
  delete $hash->{".attraggr"};
  delete $hash->{".attrminint"};


  # propagate changes
  if($dotrigger && $init_done) {
    DoTrigger($name, undef, 0) if(!$readingsUpdateDelayTrigger);
  } else {
    if(!defined($hash->{INTRIGGER})) {
      delete($hash->{CHANGED});
      delete($hash->{CHANGEDWITHSTATE})
    }
  }
  
  return undef;
}

#
# Call readingsBulkUpdate to update the reading.
# Example: readingsUpdate($hash,"temperature",$value);
#
sub
readingsBulkUpdate($$$@)
{
  my ($hash,$reading,$value,$changed)= @_;
  my $name= $hash->{NAME};

  return if(!defined($reading) || !defined($value));
  # sanity check
  if(!defined($hash->{".updateTimestamp"})) {
    Log 1, "readingsUpdate($name,$reading,$value) missed to call ".
                "readingsBeginUpdate first.";
    return;
  }
  
  # shorthand
  my $readings= $hash->{READINGS}{$reading};

  if(!defined($changed)) {
    $changed = (substr($reading,0,1) ne "."); # Dont trigger dot-readings
  }
  $changed = 0 if($hash->{".ignoreEvent"});

  # check for changes only if reading already exists
  if($changed && defined($readings)) {
  
    # these flags determine if any of the "event-on" attributes are set
    my $attreocr = $hash->{".attreocr"};
    my $attreour = $hash->{".attreour"};

    # determine whether the reading is listed in any of the attributes
    my $eocr = $attreocr && (my @eocrv=grep { my $l = $_;
                                            $l =~ s/:.*//;
                                            ($reading=~ m/^$l$/) ? $_ : undef} @{$attreocr});
    my $eour = $attreour && grep($reading =~ m/^$_$/, @{$attreour});

    # check if threshold is given
    my $eocrExists = $eocr;
    if( $eocr
        && $eocrv[0] =~ m/.*:(.*)/ ) {
      my $threshold = $1;

      $value =~ s/[^\d\.\-]//g; # We expect only numbers here.
      my $last_value = $hash->{".attreocr-threshold$reading"};
      if( !defined($last_value) ) {
        $hash->{".attreocr-threshold$reading"} = $value;
      } elsif( abs($value-$last_value) < $threshold ) {
        $eocr = 0;
      } else {
        $hash->{".attreocr-threshold$reading"} = $value;
      }
    }

    # determine if an event should be created:
    # always create event if no attribute is set
    # or if the reading is listed in event-on-update-reading
    # or if the reading is listed in event-on-change-reading...
    # ...and its value has changed...
    # ...and the change greater then the threshold
    $changed= !($attreocr || $attreour)
              || $eour  
              || ($eocr && ($value ne $readings->{VAL}));
    #Log 1, "EOCR:$eocr EOUR:$eour CHANGED:$changed";

    my @v = grep { my $l = $_;
                   $l =~ s/:.*//;
                   ($reading=~ m/^$l$/) ? $_ : undef} @{$hash->{".attrminint"}};
    if(@v) {
      my (undef, $minInt) = split(":", $v[0]);
      my $now = $hash->{".updateTime"};
      my $le = $hash->{".lastTime$reading"};
      if($le && $now-$le < $minInt) {
        if(!$eocr || ($eocr && $value eq $readings->{VAL})){
          $changed = 0;
        } else {
          $hash->{".lastTime$reading"} = $now;
        }
      } else {
        $hash->{".lastTime$reading"} = $now;
        $changed = 1 if($eocrExists);
      }
    }
    
  }

  if($changed) {
    #Debug "Processing $reading: $value";
    my @v = grep { my $l = $_;
                  $l =~ s/:.*//;
                  ($reading=~ m/^$l$/) ? $_ : undef} @{$hash->{".attraggr"}};
    if(@v) {
      # e.g. power:20:linear:avg
      my (undef, $duration, $method, $function) = split(":", $v[0], 4);
      my $ts;
      if(defined($readings->{".ts"})) {
        $ts= $readings->{".ts"};
      } else {
        require "TimeSeries.pm";
        $ts= TimeSeries->new( { method => $method, autoreset => $duration } );
        $readings->{".ts"}= $ts;
        # access from command line:
        # { $defs{"myClient"}{READINGS}{"myValue"}{".ts"}{max} }
        #Debug "TimeSeries created.";
      }
      my $now = $hash->{".updateTime"};
      my $val = $value; # save value
      $changed = $ts->elapsed($now);
      $value = $ts->{$function} if($changed);
      $ts->add($now, $val); 
    } else {
      # If no event-aggregator attribute, then remove stale series if any.
      delete $readings->{".ts"};
    }
  }  
  
  
  setReadingsVal($hash, $reading, $value, $hash->{".updateTimestamp"}); 
  
  my $rv = "$reading: $value";
  if($changed) {
    if($reading eq "state") {
      $rv = "$value";
      $hash->{CHANGEDWITHSTATE} = [];
    }
    addEvent($hash, $rv);
  }
  return $rv;
}

#
# this is a shorthand call
#
sub
readingsSingleUpdate($$$$)
{
  my ($hash,$reading,$value,$dotrigger)= @_;
  readingsBeginUpdate($hash);
  my $rv = readingsBulkUpdate($hash,$reading,$value);
  readingsEndUpdate($hash,$dotrigger);
  return $rv;
}

##############################################################################
#
# date and time routines
#
##############################################################################

sub
fhemTzOffset($)
{
  # see http://stackoverflow.com/questions/2143528/whats-the-best-way-to-get-the-utc-offset-in-perl
  my $t = shift;
  my @l = localtime($t);
  my @g = gmtime($t);

  # the offset is positive if the local timezone is ahead of GMT, e.g. we get
  # 2*3600 seconds for CET DST vs GMT
  return 60*(($l[2] - $g[2] + 
            ((($l[5] << 9)|$l[7]) <=> (($g[5] << 9)|$g[7])) * 24)*60 +
            $l[1] - $g[1]);
}

sub
fhemTimeGm($$$$$$) {
    # see http://de.wikipedia.org/wiki/Unixzeit
    my ($sec,$min,$hour,$mday,$month,$year) = @_;

    # $mday= 1..
    # $month= 0..11
    # $year is year-1900
    
    $year+= 1900;
    my $isleapyear= $year % 4 ? 0 : $year % 100 ? 1 : $year % 400 ? 0 : 1;
    my $leapyears= int(($year-1969)/4) - int(($year-1901)/100) + int(($year-1601)/400);
    #Debug sprintf("%02d.%02d.%04d %02d:%02d:%02d %d leap years, is leap year: %d", $mday,$month+1,$year,$hour,$min,$sec,$leapyears,$isleapyear);

    if ( $^O eq 'MacOS' ) {
      $year-= 1904;
    } else {
      $year-= 1970; # the Unix Epoch
    }

    my @d= (0,31,59,90,120,151,181,212,243,273,304,334); # no leap day
    # add one day in leap years if month is later than February
    $mday++ if($month>1 && $isleapyear);
    return $sec+60*($min+60*($hour+24*($d[$month]+$mday-1+365*$year+$leapyears)));
}

sub
fhemTimeLocal($$$$$$) {
    my $t= fhemTimeGm($_[0],$_[1],$_[2],$_[3],$_[4],$_[5]);
    return $t-fhemTzOffset($t);
}

# compute the list of defined logical modules for a physical module
sub
computeClientArray($$)
{
  my ($hash, $module) = @_;
  my @a = ();
  my @mRe = split(":", $hash->{Clients} ? $hash->{Clients}:$module->{Clients});

  foreach my $m (sort { $modules{$a}{ORDER}.$a cmp $modules{$b}{ORDER}.$b }
                  grep { defined($modules{$_}{ORDER}) } keys %modules) {
    foreach my $re (@mRe) {
      if($m =~ m/^$re$/) {
        push @a, $m if($modules{$m}{Match});
        last;
      }
    }
  }

  $hash->{".clientArray"} = \@a;
  return \@a;
}

# http://perldoc.perl.org/perluniintro.html, UNICODE IN OLDER PERLS
sub
latin1ToUtf8($)
{
  my ($s)= @_;
  $s =~ s/([\x80-\xFF])/chr(0xC0|ord($1)>>6).chr(0x80|ord($1)&0x3F)/eg;
  return $s;
}

sub
utf8ToLatin1($)
{
  my ($s)= @_;
  $s =~ s/([\xC2\xC3])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg;
  return $s;
}

# replaces some common control chars by escape sequences
# in order to make logs more readable
sub escapeLogLine($) {
  my ($s)= @_;
  
  # http://perldoc.perl.org/perlrebackslash.html
  my %escSequences = (
      '\a' => "\\a",
      '\e' => "\\e",
      '\f' => "\\f",
      '\n' => "\\n",
      '\r' => "\\r",
      '\t' => "\\t",
      );
  
  $s =~ s/\\/\\\\/g;
  foreach my $regex (keys %escSequences) {
    $s =~ s/$regex/$escSequences{$regex}/g;
  }
  $s =~ s/([\000-\037])/sprintf("\\%03o", ord($1))/eg;
  return $s;
}

sub
Debug($) {
  my $msg= shift;
  Log 1, "DEBUG>" . $msg;
}

sub
addToWritebuffer($$@)
{
  my ($hash, $txt, $callback, $nolimit) = @_;

  if($hash->{isChild}) {  # Wont go to the main select in a forked process
    TcpServer_WriteBlocking( $hash, $txt );
    if($callback) {
      no strict "refs";
      my $ret = &{$callback}($hash);
      use strict "refs";
    }
    return;
  }

  $hash->{WBCallback} = $callback;
  if(!$hash->{$wbName}) {
    $hash->{$wbName} = $txt;
  } elsif($nolimit || length($hash->{$wbName}) < 102400) {
    $hash->{$wbName} .= $txt;
  } else {
    return 0;
  }

  return 1; # success
}

sub
createNtfyHash()
{
  my @ntfyList = sort { $defs{$a}{NTFY_ORDER} cmp $defs{$b}{NTFY_ORDER} }
                 grep { $defs{$_}{NTFY_ORDER} } keys %defs;
  foreach my $d (@ntfyList) {
    my $nd = $defs{$d}{NOTIFYDEV};
    #Log 1, "Created notify class for $nd / $d" if($nd);
    $ntfyHash{$nd} = [] if($nd && !defined($ntfyHash{$nd}));
  }
  $ntfyHash{"*"} = [];
  foreach my $d (@ntfyList) {
    my $nd = $defs{$d}{NOTIFYDEV};
    if($nd) {
      push @{$ntfyHash{$nd}}, $d;

    } else {
      foreach $nd (keys %ntfyHash) {
        push @{$ntfyHash{$nd}}, $d;
      }
    }
  }
}

sub
notifyRegexpChanged($$)
{
  my ($hash, $re) = @_;

  my $dev;
  $dev = $1 if($re =~ m/^([^:]*)$/ || $re =~ m/^([^:]*):(.*)$/);

  if($dev && defined($defs{$dev}) && $re !~ m/\|/) { # Forum #36663
    $hash->{NOTIFYDEV} = $dev;
  } else {
    delete($hash->{NOTIFYDEV}); # when called by modify
  }
}

sub
configDBUsed()
{ 
  return ($attr{global}{configfile} eq 'configDB');
}

sub
FileRead($)
{
  my ($param) = @_;
  my ($err, @ret, $fileName, $forceType);

  if(ref($param) eq "HASH") {
    $fileName = $param->{FileName};
    $forceType = $param->{ForceType};
  } else {
    $fileName = $param;
  }
  $forceType = "" if(!defined($forceType));

  if(configDBUsed() && $forceType ne "file") {
    ($err, @ret) = cfgDB_FileRead($fileName);

  } else {
    if(open(FH, $fileName)) {
      @ret = <FH>;
      close(FH);
      chomp(@ret);
    } else {
      $err = "Can't open $fileName: $!";
    }
  }

  return ($err, @ret);
}

sub
FileWrite($@)
{
  my ($param, @rows) = @_;
  my ($err, @ret, $fileName, $forceType);

  if(ref($param) eq "HASH") {
    $fileName = $param->{FileName};
    $forceType = $param->{ForceType};
  } else {
    $fileName = $param;
  }
  $forceType = "" if(!defined($forceType));

  if(configDBUsed() && $forceType ne "file") {
    return cfgDB_FileWrite($fileName, @rows);

  } else {
    if(open(FH, ">$fileName")) {
      binmode (FH);
      foreach my $l (@rows) {
        print FH $l,"\n";
      }
      close(FH);
      return undef;

    } else {
      return "Can't open $fileName: $!";

    }
  }
}

sub
getUniqueId()
{
  my ($err, $uniqueID) = getKeyValue("uniqueID");
  return $uniqueID if(defined($uniqueID));
  $uniqueID = createUniqueId();
  setKeyValue("uniqueID", $uniqueID);
  return $uniqueID;
}

my $srandUsed;
sub
createUniqueId()
{
  my $uniqueID;
  srand(time) if(!$srandUsed);
  $srandUsed = 1;
  $uniqueID = join "",map { unpack "H*", chr(rand(256)) } 1..16;
  return $uniqueID;
}

sub
getKeyValue($)
{
  my ($key) = @_;
  my $fName = $attr{global}{modpath}."/FHEM/FhemUtils/uniqueID";
  my ($err, @l) = FileRead($fName);
  return ($err, undef) if($err);
  for my $l (@l) {
    return (undef, $1) if($l =~ m/^$key:(.*)/);
  }
  return (undef, undef);
}

sub
setKeyValue($$)
{
  my ($key,$value) = @_;
  my $fName = $attr{global}{modpath}."/FHEM/FhemUtils/uniqueID";
  my ($err, @old) = FileRead($fName);
  my @new;
  if($err) {
    push(@new, "# This file is auto generated.",
               "# Please do not modify, move or delete it.",
               "");
    @old = ();
  }
  
  my $fnd;
  foreach my $l (@old) {
    if($l =~ m/^$key:/) {
      $fnd = 1;
      push @new, "$key:$value" if(defined($value));
    } else {
      push @new, $l;
    }
  }
  push @new, "$key:$value" if(!$fnd && defined($value));

  return FileWrite($fName, @new);
}

sub
addStructChange($$$)
{
  return if(!$init_done);

  my ($cmd, $dev, $param) = @_;
  return if(!$defs{$dev} || $defs{$dev}{TEMPORARY});

  $lastDefChange++;
  return if($defs{$dev}{VOLATILE});

  shift @structChangeHist if(@structChangeHist > 9);
  $param = substr($param, 0, 40)."..." if(length($param) > 40);
  push @structChangeHist, "$cmd $param";
}

sub
fhemFork()
{
  my $pid = fork;
  if(!defined($pid)) {
    Log 1, "Cannot fork: $!";
    return undef;
  }

  return $pid if($pid);

  # Child here
  # Close all kind of FD. Reasons:
  # - cannot restart FHEM if child keeps TCP Serverports open
  # ...?
  foreach my $d (sort keys %defs) {
    my $h = $defs{$d};
    $h->{DBH}->{InactiveDestroy} = 1 if($h->{TYPE} eq 'DbLog');
    TcpServer_Close($h) if($h->{SERVERSOCKET});
    if($h->{DeviceName}) {
      require "$attr{global}{modpath}/FHEM/DevIo.pm";
      DevIo_CloseDev($h,1);
    }
  }
  return 0;
}

1;
