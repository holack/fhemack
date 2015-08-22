################################################################
# $Id: 98_update.pm 8574 2015-05-14 07:59:32Z rudolfkoenig $

package main;
use strict;
use warnings;
use HttpUtils;
use File::Copy qw(mv cp);
use Blocking;

sub CommandUpdate($$);
sub upd_getUrl($);
sub upd_initRestoreDirs($);
sub upd_mkDir($$$);
sub upd_rmTree($);
sub upd_writeFile($$$$);
sub upd_mv($$);

my $updateInBackground;
my $updRet;
my %updDirs;
my $updArg;
my $mainPgm = "/fhem.pl\$";


########################################
sub
update_Initialize($$)
{
  my %hash = (
    Fn  => "CommandUpdate",
    Hlp => "[<fileName>|all|check|force] [http://.../controlfile],update FHEM",
  );
  $cmds{update} = \%hash;
}

########################################
sub
CommandUpdate($$)
{
  my ($cl,$param) = @_;
  my @args = split(/ +/,$param);
  my $arg = (defined($args[0]) ? $args[0] : "all");
  my $src = (defined($args[1]) ? $args[1] :
                "http://fhem.de/fhemupdate/controls_fhem.txt");

  my $ret = eval { "Hello" =~ m/$arg/ };
  return "first argument must be a valid regexp, all, force or check"
        if($arg =~ m/^[-\?\*]/ || $ret);
  $arg = lc($arg) if($arg =~ m/^(check|all|force)$/i);

  $updateInBackground = AttrVal("global","updateInBackground",undef);
  $updateInBackground = 0 if($arg ne "all");                                   
  $updArg = $arg;
  if($updateInBackground) {
    CallFn($cl->{NAME}, "ActivateInformFn", $cl, "global");
    BlockingCall("doUpdateInBackground", {src=>$src,arg=>$arg});
    return "Executing the update the background.";

  } else {
    doUpdate($src, $arg);
    my $ret = $updRet; $updRet = "";
    return $ret;

  }
}

sub
uLog($$)
{
  my ($loglevel, $arg) = @_;
  return if($loglevel > $attr{global}{verbose} || !defined($arg));

  if($updateInBackground) {
    Log 1, $arg;
  } else {
    Log $loglevel, $arg if($updArg ne "check");
    $updRet .= "$arg\n";
  }
}

my $inLog = 0;
sub
update_Log2Event($$)
{
  my ($level, $text) = @_;
  return if($inLog || $level > $attr{global}{verbose});
  $inLog = 1;
  $text =~ s/\n/ /g; # Multiline text causes havoc in Analyze
  BlockingInformParent("DoTrigger", ["global", $text, 1], 0);
  BlockingInformParent("Log", [$level, $text], 0);
  $inLog = 0;
}

sub
doUpdateInBackground($)
{
  my ($h) = @_;

  no warnings 'redefine'; # The main process is not affected
  *Log = \&update_Log2Event;
  sleep(2); # Give time for ActivateInform / FHEMWEB / JavaScript
  doUpdate($h->{src}, $h->{arg});
}


sub
doUpdate($$)
{
  my ($src, $arg) = @_;
  my ($basePath, $ctrlFileName);
  if($src !~ m,^(.*)/([^/]*)$,) {
    uLog 1, "Cannot parse $src, probably not a valid http control file";
    return;
  }
  $basePath = $1;
  $ctrlFileName = $2;

  if(AttrVal("global", "backup_before_update", 0) && $arg ne "check") {
    my $cmdret = AnalyzeCommand(undef, "backup");
    if ($cmdret !~ m/backup done.*/) {
      uLog 1, "Something went wrong during backup: $cmdret";
      uLog 1, "update was canceled. Please check manually!";
      return;
    }
  }

  my $remCtrlFile = upd_getUrl($src);
  return if(!$remCtrlFile);
  my @remList = split("\n", $remCtrlFile);
  uLog 4, "Got remote controlfile with ".int(@remList)." entries.";

  ###########################
  # read in & digest the local control file
  my $root = $attr{global}{modpath};
  my $restoreDir = ($arg eq "check" ? "" : upd_initRestoreDirs($root));

  my @locList;
  if(($arg eq "check" || $arg eq "all") &&
     open(FD, "$root/FHEM/$ctrlFileName")) {
    @locList = map { $_ =~ s/[\r\n]//; $_ } <FD>;
    close(FD);
    uLog 4, "Got local controlfile with ".int(@locList)." entries.";
  }
  my %lh;
  foreach my $l (@locList) {
    my @l = split(" ", $l, 4);
    next if($l[0] ne "UPD");
    $lh{$l[3]}{TS} = $l[1];
    $lh{$l[3]}{LEN} = $l[2];
  }

  my ($canJoin, $needJoin);
  my $cj = "$root/contrib/commandref_join.pl";
  if(-f $cj &&
     -f "$root/docs/commandref_frame.html" &&
     -w "$root/docs/commandref.html" &&
     (AttrVal('global','exclude_from_update','') !~ m/commandref/) ) {
    $canJoin = 1;
  }

  my @excl = split(" ", AttrVal("global", "exclude_from_update", ""));
  my $noSzCheck = AttrVal("global", "updateNoFileCheck", configDBUsed());

  my @rl = upd_getChanges($root, $basePath);
  ###########################
  # process the remote controlfile
  my ($nChanged,$nSkipped) = (0,0);
  my $isSingle = ($arg ne "all" && $arg ne "force"  && $arg ne "check");
  foreach my $r (@remList) {
    my @r = split(" ", $r, 4);

    if($r[0] eq "MOV" && ($arg eq "all" || $arg eq "force")) {
      if($r[1] =~ m+\.\.+ || $r[2] =~ m+\.\.+) {
        uLog 1, "Suspicious line $r, aborting";
        return 1;
      }
      upd_mkDir($root, $r[2], 0);
      my $mvret = upd_mv("$root/$r[1]", "$root/$r[2]");
      uLog 4, "mv $root/$r[1] $root/$r[2]". ($mvret ? " FAILED:$mvret":"");
    }

    next if($r[0] ne "UPD");
    my $fName = $r[3];
    if($fName =~ m+\.\.+) {
      uLog 1, "Suspicious line $r, aborting";
      return 1;
    }

    my $isExcl;
    foreach my $ex (@excl) {
      $isExcl = 1 if($fName =~ m/$ex/);
    }

    if($isSingle) {
      next if($fName !~ m/$arg/);
      if($isExcl) {
        uLog 1, "update: skipping $fName, matches exclude_from_update";
        $nSkipped++;
        next;
      }

    } else {
      my $fPath = "$root/$fName";
      $fPath = $0 if($fPath =~ m/$mainPgm/);
      my $fileOk = ($lh{$fName} &&
                    $lh{$fName}{TS} eq $r[1] &&
                    $lh{$fName}{LEN} eq $r[2]);
      if($isExcl && !$fileOk) {
        uLog 1, "update: skipping $fName, matches exclude_from_update";
        $nSkipped++;
        next;
      }

      if($noSzCheck) {
        next if($isExcl || $fileOk);

      } else {
        my $sz = -s $fPath;
        next if($isExcl || ($fileOk && defined($sz) && $sz eq $r[2]));

      }
    }

    $needJoin = 1 if($fName =~ m/commandref_frame/ || $fName =~ m/\d+.*.pm/);
    next if($fName =~ m/commandref.*html/ && $fName !~ m/frame/ && $canJoin);

    uLog 1, "List of new / modified files since last update:"
      if($arg eq "check" && $nChanged == 0);

    $nChanged++;
    uLog 1, "$r[0] $fName";
    next if($arg eq "check");

    my $remFile = upd_getUrl("$basePath/$fName");
    return if(!$remFile); # Error already reported

    if(length($remFile) ne $r[2]) {
      uLog 1,
          "Got ".length($remFile)." bytes for $fName, not $r[2] as expected,";
      if($attr{global}{verbose} == 5) {
        upd_writeFile($root, $restoreDir, "$fName.corrupt", $remFile);
        uLog 1, "saving it to $fName.corrupt .";
        next;
      } else {
        uLog 1, "aborting.";
        return;
      }
    }

    return if(!upd_writeFile($root, $restoreDir, $fName, $remFile));
  }

  if($nChanged == 0 && $nSkipped == 0) {
    uLog 1, "nothing to do...";
    return;
  }

  if(@rl) {
    uLog(1, "");
    uLog 1, "New entries in the CHANGED file:";
    map { uLog 1, $_ } @rl;
  }
  return if($arg eq "check");

  if($arg eq "all" || $arg eq "force") { # store the controlfile
    return if(!upd_writeFile($root, $restoreDir,
                           "FHEM/$ctrlFileName", $remCtrlFile));
  }

  return "" if(!$nChanged);

  if($canJoin && $needJoin) {
    chdir($root);
    uLog(1, "Calling $^X $cj, this may take a while");
    my $ret = `$^X $cj`;
    foreach my $l (split(/[\r\n]+/, $ret)) {
      uLog(1, $l);
    }
  }

  uLog(1, "");
  uLog 1,
      'update finished, "shutdown restart" is needed to activate the changes.';
  my $ss = AttrVal("global","sendStatistics",undef);
  if(!defined($ss)) {
    uLog(1, "");
    uLog(1, "Please consider using the global attribute sendStatistics");
  } elsif(defined($ss) && lc($ss) eq "onupdate") {
    uLog(1, "");
    my $ret = AnalyzeCommandChain(undef, "fheminfo send");
    $ret =~ s/.*server response:/server response:/ms;
    uLog(1, "fheminfo $ret");
  }
}

sub
upd_mv($$)
{
  my ($src, $dest) = @_;
  if($src =~ m/\*/) {
    $src =~ m,^(.*)/([^/]+)$,;
    my ($dir, $pat) = ($1, $2);
    $pat = "^$pat\$";
    opendir(my $dh, $dir) || return "$dir: $!";
    while(my $r = readdir($dh)) {
      next if($r !~ m/$pat/ || "$dir/$r" eq $dest);
      my $mvret = mv("$dir/$r", $dest);
      return "MV $dir/$r $dest: $!" if(!$mvret);
      Log 3, "MV $dir/$r $dest";
    }
    closedir($dh);

  } else {
    return "MV $src $dest: $!" if(mv($src, $dest));

  }
  return undef;
}

sub
upd_mkDir($$$)
{
  my ($root, $dir, $isFile) = @_;
  if($isFile) { # Delete the file Component
    $dir =~ m,^(.*)/([^/]*)$,;
    $dir = $1;
  }
  return if($updDirs{$dir});
  $updDirs{$dir} = 1;
  my @p = split("/", $dir);
  for(my $i = 0; $i < int(@p); $i++) {
    my $path = "$root/".join("/", @p[0..$i]);
    if(!-d $path) {
      mkdir $path;
      uLog 4, "MKDIR $root/".join("/", @p[0..$i]);
    }
  }
}

sub
upd_getChanges($$)
{
  my ($root, $basePath) = @_;
  my $lFile = "";
  if(open(FH, "$root/CHANGED")) {
    foreach my $l (<FH>) { # first non-comment line
      next if($l =~ m/^#/);
      chomp $l;
      $lFile = $l;
      last;
    }
    close(FH);
  }
  my @lines = split(/[\r\n]/,upd_getUrl("$basePath/CHANGED"));
  my $maxLines = 25;
  my @ret;
  foreach my $line (@lines) {
    next if($line =~ m/^#/);
    last if($line eq "" || $line eq $lFile);
    push @ret, $line;
    if($maxLines-- < 1) {
      push @ret, "... rest of lines skipped.";
      last;
    }
  }
  return @ret;
}

sub
upd_getUrl($)
{
  my ($url) = @_;
  $url =~ s/%/%25/g;
  my ($err, $data) = HttpUtils_BlockingGet({ url=>$url });
  if($err) {
    uLog 1, $err;
    return "";
  }
  if(length($data) == 0) {
    uLog 1, "$url: empty file received";
    return "";
  }
  return $data;
}

sub
upd_writeFile($$$$)
{
  my($root, $restoreDir, $fName, $content) = @_;

  # copy the old file and save the new
  upd_mkDir($root, $fName, 1);
  upd_mkDir($root, "$restoreDir/$fName", 1) if($restoreDir);
  if($restoreDir && -f "$root/$fName" &&
     ! cp("$root/$fName", "$root/$restoreDir/$fName")) {
    uLog 1, "cp $root/$fName $root/$restoreDir/$fName failed:$!, ".
              "aborting the update";
    return 0;
  }

  my $rest = ($restoreDir ? "trying to restore the previous version and ":"").
                "aborting the update";
  my $fPath = "$root/$fName";
  $fPath = $0 if($fPath =~ m/$mainPgm/);
  if(!open(FD, ">$fPath")) {
    uLog 1, "open $fPath failed: $!, $rest";
    cp "$root/$restoreDir/$fName", "$root/$fName" if($restoreDir);
    return 0;
  }
  binmode(FD);
  print FD $content;
  close(FD);

  my $written = -s "$fPath";
  if($written != length($content)) {
    uLog 1, "writing $fPath failed: $!, $rest";
    cp "$root/$restoreDir/$fName", "$fPath" if($restoreDir);
    return;
  }

  cfgDB_FileUpdate("$fPath") if(configDBUsed());

  return 1;
}

sub
upd_rmTree($)
{
  my ($dir) = @_;

  my $dh;
  if(!opendir($dh, $dir)) {
    uLog 1, "opendir $dir: $!";
    return;
  }
  my @files = grep { $_ ne "." && $_ ne ".." } readdir($dh);
  closedir($dh);

  foreach my $f (@files) {
    if(-d "$dir/$f") {
      upd_rmTree("$dir/$f");
    } else {
      uLog 4, "rm $dir/$f";
      unlink("$dir/$f");
    }
  }
  uLog 4, "rmdir $dir";
  rmdir($dir);
}

sub
upd_initRestoreDirs($)
{
  my ($root) = @_;

  my $nDirs = AttrVal("global","restoreDirs", 3);
  if($nDirs !~ m/^\d+$/ || $nDirs < 0) {
    uLog 1, "invalid restoreDirs value $nDirs, setting it to 3";
    $nDirs = 3;
  }
  return "" if($nDirs == 0);

  my $rdName = "restoreDir";
  my @t = localtime;
  my $restoreDir = sprintf("$rdName/%04d-%02d-%02d",
                        $t[5]+1900, $t[4]+1, $t[3]);
  Log 1, "MKDIR $restoreDir" if(!  -d "$root/restoreDir");
  upd_mkDir($root, $restoreDir, 0);

  if(!opendir(DH, "$root/$rdName")) {
    uLog 1, "opendir $root/$rdName: $!";
    return "";
  }
  my @oldDirs = sort grep { $_ !~ m/^\./ && $_ ne $restoreDir } readdir(DH);
  closedir(DH);
  while(int(@oldDirs) > $nDirs) {
    my $dir = "$root/$rdName/". shift(@oldDirs);
    next if($dir =~ m/$restoreDir/);    # Just in case
    uLog 1, "RMDIR: $dir";
    upd_rmTree($dir);
  }
    
  return $restoreDir;
}
1;

=pod
=begin html

<a name="update"></a>
<h3>update</h3>
<ul>
  <code>update [&lt;fileName&gt;|all|check|force]
       [http://.../controlfile]</code>
  <br>
  <br>
  Update the FHEM installation. Technically this means update will download
  http://fhem.de/fhemupdate/controls_fhem.txt first, compare it to the local
  version in FHEM/controls_fhem.txt, and will download each file where the
  attributes (timestamp and filelength) are different.
  <br>
  Notes:
  <ul>
    <li>The contrib directory will not be updated.</li>
    <li>The files are automatically transferred from the source repository
        (SVN) to the web site once a day, at 7:45 CET / CEST.</li>
    <li>The all argument is default.</li>
    <li>The force argument will disregard the local file.</li>
    <li>The check argument will only display the files it would download, and
        the last section of the CHANGED file.</li>
    <li>Specifying a filename will only download matching files (regexp).</li>
  </ul>
  See also the restore command.<br>
  <br>
  Examples:<br>
  <ul>
    <li>update check</li>
    <li>update</li>
    <li>update force</li>
    <li>update check http://fhem.de/fhemupdate/controls_fhem.txt</li>
  </ul>
  <a name="updateattr"></a>

  <br>
  <b>Attributes</b> (use attr global ...)
  <ul>
    <a name="updateInBackground"></a>
    <li>updateInBackground<br>
        If this attribute is set (to 1), the update will be executed in a
        background process. The return message is communicated via events, and
        in telnet the inform command is activated, in FHEMWEB the Event
        Monitor.
        </li><br>

    <a name="updateNoFileCheck"></a>
    <li>updateNoFileCheck<br>
        If set, the command won't compare the local file size with the expected
        size. This attribute was introduced to satisfy some experienced FHEM
        user, its default value is 0.
        </li><br>

    <a name="backup_before_update"></a>
    <li>backup_before_update<br>
        If this attribute is set, an update will back up your complete
        installation via the <a href="#backup">backup</a> command. The default
        is not set as update relies on the restore feature (see below).<br>
        Example:<br>
        <ul>
          attr global backup_before_update
        </ul>
        </li><br>

    <a name="exclude_from_update"></a>
    <li>exclude_from_update<br>
        Contains a space separated list of fileNames (regexps) which will be
        excluded by an update. The special value commandref will disable calling
        commandref_join at the end, i.e commandref.html will be out of date.
        The module-only documentation is not affected and is up-to-date.<br>
        Example:<br>
        <ul>
          attr global exclude_from_update 21_OWTEMP.pm FS20.off.png
        </ul>
        </li><br>

    <a name="restoreDirs"></a>
    <li>restoreDirs<br>
        update saves each file before overwriting it with the new version from
        the Web. For this purpose update creates a directory restoreDir in the
        global modpath directory, then a subdirectory with the current date,
        where the old version of the currently replaced file is stored.
        The default value of this attribute is 3, meaning that 3 old versions
        (i.e. date-directories) are kept, and the older ones are deleted. If
        the attribute is set to 0, the feature is deactivated.
        </li><br>


  </ul>
</ul>

=end html
=begin html_DE

<a name="update"></a>
<h3>update</h3>
<ul>
  <code>update [&lt;fileName&gt;|all|check|force]
        [http://.../controlfile]</code>
  <br>
  <br>
  Erneuert die FHEM Installation. D.h. es wird zuerst die Datei
  http://fhem.de/fhemupdate/controls_fhem.txt heruntergeladen, mit der lokalen
  Version dieser Datei (FHEM/controls_fhem.txt) verglichen. Danach werden
  alle Programmdateien heruntergeladen, deren Gr&ouml;&szlig;e oder Zeitstempel
  sich unterscheidet.
  <br>
  Zu beachten:
  <ul>
    <li>Das contrib Verzeichnis wird nicht heruntergeladen.</li>
    <li>Die Dateien werden auf der Webseite einmal am Tag um 07:45 MET/MEST aus
        der Quell-Verwaltungssystem (SVN) bereitgestellt.</li>
    <li>Das all Argument ist die Voreinstellung.</li>
    <li>Das force Argument beachtet die lokale controls_fhem.txt Datei
        nicht.</li>
    <li>Das check Argument zeigt die neueren Dateien an, und den letzten
        Abschnitt aus der CHANGED Datei</li>
    <li>Falls man &lt;fileName&gt; spezifiziert, dann werden nur die Dateien
        heruntergeladen, die diesem Regexp entsprechen.</li>
  </ul>
  Siehe also das restore Befehl.<br>
  <br>
  Beispiele:<br>
  <ul>
    <li>update check</li>
    <li>update</li>
    <li>update force</li>
    <li>update check http://fhem.de/fhemupdate/controls_fhem.txt</li>
  </ul>
  <a name="updateattr"></a>

  <br>
  <b>Attribute</b>  (sind mit attr global zu setzen)
  <ul>
    <a name="updateInBackground"></a>
    <li>updateInBackground<br>
        Wenn dieses Attribut gesetzt ist, wird das update Befehl in einem
        separaten Prozess ausgef&uuml;hrt, und alle Meldungen werden per Event
        &uuml;bermittelt. In der telnet Sitzung wird inform, in FHEMWEB wird
        das Event Monitor aktiviert.
        </li><br>

    <a name="updateNoFileCheck"></a>
    <li>updateNoFileCheck<br>
        Wenn dieses Attribut gesetzt ist, wird die Gr&ouml;&szlig;e der bereits
        vorhandenen, lokalen Datei nicht mit der Sollgr&ouml;&szlig;e
        verglichen. Dieses Attribut wurde nach nicht genau spezifizierten Wnsch
        erfahrener FHEM Benutzer eingefuehrt, die Voreinstellung ist 0.
        </li><br>

    <a name="backup_before_update"></a>
    <li>backup_before_update<br>
        Wenn dieses Attribut gesetzt ist, erstellt FHEM eine Sicherheitskopie
        der FHEM Installation vor dem update mit dem backup Befehl. Die
        Voreinstellung is "nicht gesetzt", da update sich auf das restore
        Feature verl&auml;sst, s.u.<br>
        Beispiel:<br>
        <ul>
          attr global backup_before_update
        </ul>
        </li><br>

    <a name="exclude_from_update"></a>
    <li>exclude_from_update<br>
        Enth&auml;lt eine Liste durch Leerzeichen getrennter Dateinamen
        (regexp), welche nicht im update ber&uuml;cksichtigt werden.<br>
        Falls der Wert commandref enth&auml;lt, dann wird commandref_join.pl
        nach dem update nicht aufgerufen, d.h. die Gesamtdokumentation ist
        nicht mehr aktuell. Die Moduldokumentation bleibt weiterhin aktuell.
        <br>
        Beispiel:<br>
        <ul>
          attr global exclude_from_update 21_OWTEMP.pm temp4hum4.gplot 
        </ul>
        </li><br>

    <li><a href="#restoreDirs">restoreDirs</a>
        update sichert jede Datei vor dem &Uuml;berschreiben mit der neuen
        Version aus dem Web. F&uuml;r diesen Zweck wird zuerst ein restoreDir
        Verzeichnis in der global modpath Verzeichnis angelegt, und danach
        ein Unterverzeichnis mit dem aktuellen Datum. In diesem Verzeichnis
        werden vor dem &Uuml;berschreiben die alten Versionen der Dateien
        gerettet. Die Voreinstellung ist 3, d.h. die letzten 3
        Datums-Verzeichnisse werden aufgehoben, und die &auml;lteren entfernt.
        Falls man den Wert auf 0 setzt, dann ist dieses Feature deaktiviert.
        </li><br>

  </ul>
</ul>


=end html_DE
=cut
