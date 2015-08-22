##############################################
# $Id: 90_at.pm 8326 2015-03-29 13:30:57Z rudolfkoenig $
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

#####################################
sub
at_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "at_Define";
  $hash->{UndefFn}  = "at_Undef";
  $hash->{SetFn}    = "at_Set";
  $hash->{AttrFn}   = "at_Attr";
  $hash->{StateFn}  = "at_State";
  $hash->{AttrList} = "disable:0,1 disabledForIntervals ".
                        "skip_next:0,1 alignTime";
  $hash->{FW_detailFn} = "at_fhemwebFn";
}


my %at_stt;
my $at_detailFnCalled;

sub
at_SecondsTillTomorrow($)  # 86400, if tomorrow is no DST change
{
  my $t = shift;
  my $dayHour = int($t/3600);

  if(!$at_stt{$dayHour}) {
    my @l1 = localtime($t);
    my @l2 = localtime($t+86400);
    $at_stt{$dayHour} = 86400+($l1[2]-$l2[2])*3600;
  }

  return $at_stt{$dayHour};
}


#####################################
sub
at_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, undef, $tm, $command) = split("[ \t]+", $def, 4);

  if(!$command) {
    if($hash->{OLDDEF}) { # Called from modify, where command is optional
      RemoveInternalTimer($hash);
      (undef, $command) = split("[ \t]+", $hash->{OLDDEF}, 2);
      $hash->{DEF} = "$tm $command";
    } else {
      return "Usage: define <name> at <timespec> <command>";
    }
  }
  return "Wrong timespec, use \"[+][*[{count}]]<time or func>\""
                                        if($tm !~ m/^(\+)?(\*({\d+})?)?(.*)$/);
  my ($rel, $rep, $cnt, $tspec) = ($1, $2, $3, $4);
  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($tspec);
  return $err if($err);

  $rel = "" if(!defined($rel));
  $rep = "" if(!defined($rep));
  $cnt = "" if(!defined($cnt));
  $hash->{RELATIVE} = ($rel ? "yes" : "no");
  $hash->{PERIODIC} = ($rep ? "yes" : "no");
  $hash->{TIMESPEC} = $tspec;
  $hash->{COMMAND} = $command;

  my $ot = $data{AT_TRIGGERTIME} ? $data{AT_TRIGGERTIME} : gettimeofday();
  $ot = int($ot) if(!$rel);     # No way to specify subseconds
  my @lt = localtime($ot);
  my $nt = $ot;

  $nt -= ($lt[2]*3600+$lt[1]*60+$lt[0])         # Midnight for absolute time
                        if($rel ne "+");
  $nt += ($hr*3600+$min*60+$sec); # Plus relative time
  $nt += at_SecondsTillTomorrow($nt) if($ot >= $nt);  # Do it tomorrow...
  @lt = localtime($nt);
  my $ntm = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
  if($rep) {    # Setting the number of repetitions
    $cnt =~ s/[{}]//g;
    return undef if($cnt eq "0");
    $cnt = 0 if(!$cnt);
    $cnt--;
    $hash->{REP} = $cnt; 
  } else {
    $hash->{VOLATILE} = 1;      # Write these entries to the statefile
  }

  my $alTime = AttrVal($name, "alignTime", undef);
    
  if(!$data{AT_RECOMPUTE} && $alTime) {
    my $ret = at_adjustAlign($hash, $alTime);
    return $ret if($ret);

  } else {
    $hash->{TRIGGERTIME} = $nt;
    $hash->{TRIGGERTIME_FMT} = FmtDateTime($nt);
    RemoveInternalTimer($hash);
    InternalTimer($nt, "at_Exec", $hash, 0);
    $hash->{NTM} = $ntm if($rel eq "+" || $fn);
    my $d = IsDisabled($name);  # 1
    my $val = ($d==3 ? "inactive" : ($d ? "disabled":("Next: ".FmtTime($nt))));
    readingsSingleUpdate($hash, "state", $val,
          !$hash->{READINGS}{state} || $hash->{READINGS}{state}{VAL} ne $val);
  }

  return undef;
}

sub
at_Undef($$)
{
  my ($hash, $name) = @_;
  $hash->{DELETED} = 1;
  RemoveInternalTimer($hash);
  return undef;
}

sub
at_Exec($)
{
  my ($hash) = @_;

  return if($hash->{DELETED});           # Just deleted
  my $name = $hash->{NAME};
  Log3 $name, 5, "exec at command $name";

  my $skip = AttrVal($name, "skip_next", undef);
  delete $attr{$name}{skip_next} if($skip);

  my $command = SemicolonEscape($hash->{COMMAND});
  my $ret = AnalyzeCommandChain(undef, $command)
        if(!$skip && !IsDisabled($name));
  Log3 $name, 3, "$name: $ret" if($ret);

  return if($hash->{DELETED});           # Deleted in the Command

  my $count = $hash->{REP};
  my $def = $hash->{DEF};

  # Avoid drift when the timespec is relative
  $data{AT_TRIGGERTIME} = $hash->{TRIGGERTIME} if($def =~ m/^\+/);

  if($count) {
    $def =~ s/{\d+}/{$count}/ if($def =~ m/^\+?\*{\d+}/);  # Replace the count
    Log3 $name, 5, "redefine at command $name as $def";

    $data{AT_RECOMPUTE} = 1;             # Tell sunrise compute the next day
    at_Define($hash, "$name at $def");   # Recompute the next TRIGGERTIME
    delete($data{AT_RECOMPUTE});

  } else {
    CommandDelete(undef, $name);          # We are done

  }
  delete($data{AT_TRIGGERTIME});
}

sub
at_adjustAlign($$)
{
  my($hash, $attrVal) = @_;

  my ($alErr, $alHr, $alMin, $alSec, undef) = GetTimeSpec($attrVal);
  return "$hash->{NAME} alignTime: $alErr" if($alErr);
  my ($tm, $command) = split("[ \t]+", $hash->{DEF}, 2);
  $tm =~ m/^(\+)?(\*({\d+})?)?(.*)$/;
  my ($rel, $rep, $cnt, $tspec) = ($1, $2, $3, $4);
  return "startTimes: $hash->{NAME} is not relative" if(!$rel);
  my (undef, $hr, $min, $sec, undef) = GetTimeSpec($tspec);

  my $now = time();
  my $alTime = ($alHr*60+$alMin)*60+$alSec-fhemTzOffset($now);
  my $step = ($hr*60+$min)*60+$sec;
  my $ttime = int($hash->{TRIGGERTIME});
  my $off = ($ttime % 86400) - 86400;
  while($off < $alTime) {
    $off += $step;
  }
  $ttime += ($alTime-$off);
  $ttime += $step if($ttime < $now);

  RemoveInternalTimer($hash);
  InternalTimer($ttime, "at_Exec", $hash, 0);
  $hash->{TRIGGERTIME} = $ttime;
  $hash->{TRIGGERTIME_FMT} = FmtDateTime($ttime);
  $hash->{STATE} = "Next: " . FmtTime($ttime);
  $hash->{NTM} = FmtTime($ttime);
  return undef;
}

sub
at_Set($@)
{
  my ($hash, @a) = @_;

  my %sets = (modifyTimeSpec=>1, inactive=>0, active=>0);
  my $cmd = join(" ", sort keys %sets);
  $cmd =~ s/modifyTimeSpec/modifyTimeSpec:time/ if($at_detailFnCalled);
  $at_detailFnCalled = 0;
  return "no set argument specified" if(int(@a) < 2);
  return "Unknown argument $a[1], choose one of $cmd"
    if(!defined($sets{$a[1]}));
    
  if($a[1] eq "modifyTimeSpec") {
    my ($err, undef) = GetTimeSpec($a[2]);
    return $err if($err);

    my $def = ($hash->{RELATIVE} eq "yes" ? "+":"").
              ($hash->{PERIODIC} eq "yes" ? "*":"").
              $a[2];
    $hash->{OLDDEF} = $hash->{DEF};
    my $ret = at_Define($hash, "$hash->{NAME} at $def");
    delete $hash->{OLDDEF};
    return $ret;

  } elsif($a[1] eq "inactive") {
    readingsSingleUpdate($hash, "state", "inactive", 1);
    return undef;

  } elsif($a[1] eq "active") {
    readingsSingleUpdate($hash,"state","Next: ".FmtTime($hash->{TRIGGERTIME}),1)
      if(!AttrVal($hash->{NAME}, "disable", undef));
    return undef;
  }

}
  
sub
at_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $do = 0;

  my $hash = $defs{$name};

  if($cmd eq "set" && $attrName eq "alignTime") {
    return "alignTime needs a list of timespec parameters" if(!$attrVal);
    my $ret = at_adjustAlign($hash, $attrVal);
    return $ret if($ret);
  }

  if($cmd eq "set" && $attrName eq "disable") {
    $do = (!defined($attrVal) || $attrVal) ? 1 : 2;
  }
  $do = 2 if($cmd eq "del" && (!$attrName || $attrName eq "disable"));
  return if(!$do);
  my $val = ($do == 1 ?  "disabled" :
                         "Next: " . FmtTime($hash->{TRIGGERTIME}));
  readingsSingleUpdate($hash, "state", $val, 1);
  return undef;
}

#############
# Adjust one-time relative at's after reboot, the execution time is stored as
# state
sub
at_State($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  if($vt eq "state" && $val eq "inactive") {
    readingsSingleUpdate($hash, "state", "inactive", 1);
    return undef;
  }

  return undef if($hash->{DEF} !~ m/^\+\d/ ||
                  $val !~ m/Next: (\d\d):(\d\d):(\d\d)/);

  my ($h, $m, $s) = ($1, $2, $3);
  my $then = ($h*60+$m)*60+$s;
  my $now = time();
  my @lt = localtime($now);
  my $ntime = ($lt[2]*60+$lt[1])*60+$lt[0];
  return undef if($ntime > $then); 

  my $name = $hash->{NAME};
  RemoveInternalTimer($hash);
  InternalTimer($now+$then-$ntime, "at_Exec", $hash, 0);
  $hash->{NTM} = "$h:$m:$s";
  $hash->{STATE} = $val;
  
  return undef;
}

#########################
sub
at_fhemwebFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};

  $at_detailFnCalled = 1 if(!$pageHash);

  my $ts = $hash->{TIMESPEC}; $ts =~ s/'/\\'/g;
  my $isPerl = ($ts =~ m/^{(.*)}/);
  $ts = $1 if($isPerl);

return "<br>Timespec wizard:".
"<table id='atWizard' nm='$hash->{NAME}' ts='$ts' rl='$hash->{RELATIVE}' ".
       "pr='$hash->{PERIODIC}' ip='$isPerl' class='block wide'>".<<'EOF';
  <tr class="even">
    <td>Relative &nbsp; <input type="checkbox" id="aw_rl" value="yes"></td>
    <td>Periodic &nbsp; <input type="checkbox" id="aw_pr" value="yes"></td>
  </tr><tr class="odd"><td>Use perl function for timespec</td>
    <td><input type="checkbox" id="aw_ip"></td>
  </tr><tr class="even"><td>Timespec</td>
    <td><input type="text" name="aw_pts"></td>
  </tr><tr class="even"><td>Timespec</td>
    <td><input type="text" name="aw_ts" size="5"></td>
  </tr>
  </tr><tr class="even">
    <td colspan="2"><input type="button" id="aw_md" value="Modify"></td>
  </tr>
</table>
<script type="text/javascript">
  {
    var t=$("#atWizard"), ip=$(t).attr("ip"), ts=$(t).attr("ts");
    FW_replaceWidget("[name=aw_ts]", "aw_ts", ["time"], "12:00");
    $("[name=aw_ts] input[type=text]").attr("id", "aw_ts");

    function ipClick() {
      var c = $("#aw_ip").prop("checked");
      $("[name=aw_ts]") .closest("tr").css("display",!c ? "table-row" : "none");
      $("[name=aw_pts]").closest("tr").css("display", c ? "table-row" : "none");
    }
    $("#aw_rl").prop("checked", $(t).attr("rl")=="yes");
    $("#aw_pr").prop("checked", $(t).attr("pr")=="yes");
    $("#aw_ip").prop("checked", ip);
    $("[name=aw_ts]").val(ip ? "12:00" : ts);
    $("[name=aw_pts]").val(ip ? ts : 'sunset()');
    $("#aw_ip").change(ipClick);
    ipClick();
    $("#aw_md").click(function(){
      var nm = $(t).attr("nm");
      var def = nm+" ";
      def += $("#aw_rl").prop("checked") ? "+":"";
      def += $("#aw_pr").prop("checked") ? "*":"";
      def += $("#aw_ip").prop("checked") ? 
               "{"+$("[name=aw_pts]").val()+"}" : $("[name=aw_ts]").val();
      def = def.replace(/\+/g, "%2b");
      def = def.replace(/;/g, ";;");
      location = location.pathname+"detail="+nm+"&cmd=modify "+def;
    });
  }
</script>
EOF
}

1;

=pod
=begin html

<a name="at"></a>
<h3>at</h3>
<ul>

  Start an arbitrary FHEM command at a later time.<br>
  <br>

  <a name="atdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; at &lt;timespec&gt; &lt;command&gt;</code><br>
    <br>
    <code>&lt;timespec&gt;</code> format: [+][*{N}]&lt;timedet&gt;<br>
    <ul>
      The optional <code>+</code> indicates that the specification is
      <i>relative</i>(i.e. it will be added to the current time).<br>
      The optional <code>*</code> indicates that the command should be
      executed <i>repeatedly</i>.<br>
      The optional <code>{N}</code> after the * indicates,that the command
      should be repeated <i>N-times</i> only.<br>
      &lt;timedet&gt; is either HH:MM, HH:MM:SS or {perlfunc()}, where perlfunc
      must return a HH:MM or HH:MM:SS date. Note: {perlfunc()} may not contain
      any spaces or tabs.
    </ul>
    <br>

    Examples:
    <PRE>
    # absolute ones:
    define a1 at 17:00:00 set lamp on                            # fhem command
    define a2 at 17:00:00 { Log 1, "Teatime" }                   # Perl command
    define a3 at 17:00:00 "/bin/echo "Teatime" > /dev/console"   # shell command
    define a4 at *17:00:00 set lamp on                           # every day

    # relative ones
    define a5 at +00:00:10 set lamp on                 # switch on in 10 seconds
    define a6 at +00:00:02 set lamp on-for-timer 1     # Blink once in 2 seconds
    define a7 at +*{3}00:00:02 set lamp on-for-timer 1 # Blink 3 times

    # Blink 3 times if the piri sends a command
    define n1 notify piri:on.* define a8 at +*{3}00:00:02 set lamp on-for-timer 1

    # Switch the lamp on from sunset to 11 PM
    define a9 at +*{sunset_rel()} set lamp on
    define a10 at *23:00:00 set lamp off

    # More elegant version, works for sunset > 23:00 too
    define a11 at +*{sunset_rel()} set lamp on-till 23:00

    # Only do this on weekend
    define a12 at +*{sunset_rel()} { fhem("set lamp on-till 23:00") if($we) }

    # Switch lamp1 and lamp2 on from 7:00 till 10 minutes after sunrise
    define a13 at *07:00 set lamp1,lamp2 on-till {sunrise(+600)}

    # Switch the lamp off 2 minutes after sunrise each day
    define a14 at +{sunrise(+120)} set lamp on

    # Switch lamp1 on at sunset, not before 18:00 and not after 21:00
    define a15 at *{sunset(0,"18:00","21:00")} set lamp1 on

    </PRE>

    Notes:<br>
    <ul>
      <li>if no <code>*</code> is specified, then a command will be executed
          only once, and then the <code>at</code> entry will be deleted.  In
          this case the command will be saved to the statefile (as it
          considered volatile, i.e. entered by cronjob) and not to the
          configfile (see the <a href="#save">save</a> command.)
      </li>

      <li>if the current time is greater than the time specified, then the
          command will be executed tomorrow.</li>

      <li>For even more complex date handling you either have to call fhem from
          cron or filter the date in a perl expression, see the last example and
          the section <a href="#perl">Perl special</a>.
      </li>
    </ul>
    <br>
  </ul>


  <a name="atset"></a>
  <b>Set</b>
  <ul>
    <a name="modifyTimeSpec"></a>
    <li>modifyTimeSpec &lt;timespec&gt;<br>
        Change the execution time. Note: the N-times repetition is ignored.
        It is intended to be used in combination with
        <a href="#webCmd">webCmd</a>, for an easier modification from the room
        overview in FHEMWEB.</li>
    <li>inactive<br>
        Inactivates the current device. Note the slight difference to the
        disable attribute: using set inactive the state is automatically saved
        to the statefile on shutdown, there is no explicit save necesary.<br>
        This command is intended to be used by scripts to temporarily
        deactivate the at.<br>
        The concurrent setting of the disable attribute is not recommended.
        </li>
    <li>active<br>
        Activates the current device (see inactive).</li>
  </ul><br>



  <a name="atget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="atattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="disable"></a>
    <li>disable<br>
        Can be applied to at/watchdog/notify/FileLog devices.<br>
        Disables the corresponding at/notify or FileLog device. Note:
        If applied to an <a href="#at">at</a>, the command will not be executed,
        but the next time will be computed.</li><br>

    <a name="disabledForIntervals"></a>
    <li>disabledForIntervals HH:MM-HH:MM HH:MM-HH-MM...<br>
        Space separated list of HH:MM tupels. If the current time is between
        the two time specifications, the current device is disabled. Instead of
        HH:MM you can also specify HH or HH:MM:SS. To specify an interval
        spawning midnight, you have to specify two intervals, e.g.:
        <ul>
          23:00-24:00 00:00-01:00
        </ul>
        </li><br>

    <a name="skip_next"></a>
    <li>skip_next<br>
        Used for at commands: skip the execution of the command the next
        time.</li><br>

    <a name="alignTime"></a>
    <li>alignTime<br>
        Applies only to relative at definitions: adjust the time of the next
        command execution so, that it will also be executed at the desired
        alignTime. The argument is a timespec, see above for the
        definition.<br>
        Example:<br>
        <ul>
        # Make sure that it chimes when the new hour begins<br>
        define at2 at +*01:00 set Chime on-for-timer 1<br>
        attr at2 alignTime 00:00<br>
        </ul>
        </li><br>

  </ul>
  <br>
</ul>

=end html

=begin html_DE

<a name="at"></a>
<h3>at</h3>
<ul>

  Startet einen beliebigen FHEM Befehl zu einem sp&auml;teren Zeitpunkt.<br>
  <br>

  <a name="atdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; at &lt;timespec&gt; &lt;command&gt;</code><br>
    <br>
    <code>&lt;timespec&gt;</code> Format: [+][*{N}]&lt;timedet&gt;<br>
    <ul>
      Das optionale <code>+</code> zeigt, dass die Angabe <i>relativ</i> ist 
      (also zur jetzigen Zeit dazugez&auml;hlt wird).<br>

      Das optionale <code>*</code> zeigt, dass die Ausf&uuml;hrung
      <i>wiederholt</i> erfolgen soll.<br>

      Das optionale <code>{N}</code> nach dem * bedeutet, dass der Befehl genau
      <i>N-mal</i> wiederholt werden soll.<br>

      &lt;timedet&gt; ist entweder HH:MM, HH:MM:SS oder {perlfunc()}, wobei
      perlfunc HH:MM or HH:MM:SS zur&uuml;ckgeben muss. Hinweis: {perlfunc()}
      darf keine Leerzeichen enthalten.

    </ul>
    <br>

    Beispiele:
    <PRE>
    # Absolute Beispiele:
    define a1 at 17:00:00 set lamp on                            # fhem Befehl
    define a2 at 17:00:00 { Log 1, "Teatime" }                   # Perl Befehl
    define a3 at 17:00:00 "/bin/echo "Teatime" > /dev/console"   # shell Befehl
    define a4 at *17:00:00 set lamp on                           # Jeden Tag

    # Realtive Beispiele:
    define a5 at +00:00:10 set lamp on                  # Einschalten in 10 Sekunden
    define a6 at +00:00:02 set lamp on-for-timer 1      # Einmal blinken in 2 Sekunden
    define a7 at +*{3}00:00:02 set lamp on-for-timer 1  # Blinke 3 mal

    # Blinke 3 mal wenn  piri einen Befehl sendet
    define n1 notify piri:on.* define a8 at +*{3}00:00:02 set lamp on-for-timer 1

    # Lampe von Sonnenuntergang bis 23:00 Uhr einschalten
    define a9 at +*{sunset_rel()} set lamp on
    define a10 at *23:00:00 set lamp off

    # Elegantere Version, ebenfalls von Sonnenuntergang bis 23:00 Uhr
    define a11 at +*{sunset_rel()} set lamp on-till 23:00

    # Nur am Wochenende ausf&uuml;hren
    define a12 at +*{sunset_rel()} { fhem("set lamp on-till 23:00") if($we) }

    # Schalte lamp1 und lamp2 ein von 7:00 bis 10 Minuten nach Sonnenaufgang
    define a13 at *07:00 set lamp1,lamp2 on-till {sunrise(+600)}

    # Schalte lamp jeden Tag 2 Minuten nach Sonnenaufgang aus
    define a14 at +{sunrise(+120)} set lamp on

    # Schalte lamp1 zum Sonnenuntergang ein, aber nicht vor 18:00 und nicht nach 21:00
    define a15 at *{sunset(0,"18:00","21:00")} set lamp1 on

    </PRE>

    Hinweise:<br>
    <ul>
      <li>wenn kein <code>*</code> angegeben wird, wird der Befehl nur einmal
      ausgef&uuml;hrt und der entsprechende <code>at</code> Eintrag danach
      gel&ouml;scht. In diesem Fall wird der Befehl im Statefile gespeichert
      (da er nicht statisch ist) und steht nicht im Config-File (siehe auch <a
      href="#save">save</a>).</li>

      <li>wenn die aktuelle Zeit gr&ouml;&szlig;er ist als die angegebene Zeit,
      dann wird der Befehl am folgenden Tag ausgef&uuml;hrt.</li>

      <li>F&uuml;r noch komplexere Datums- und Zeitabl&auml;ufe muss man den
      Aufruf entweder per cron starten oder Datum/Zeit mit perl weiter
      filtern. Siehe hierzu das letzte Beispiel und das <a href="#perl">Perl
      special</a>.  </li>

    </ul>
    <br>
  </ul>


  <a name="atset"></a>
  <b>Set</b>
  <ul>
    <a name="modifyTimeSpec"></a>
    <li>modifyTimeSpec &lt;timespec&gt;<br>
        &Auml;ndert die Ausf&uuml;hrungszeit. Achtung: die N-malige
        Wiederholungseinstellung wird ignoriert. Gedacht zur einfacheren
        Modifikation im FHEMWEB Raum&uuml;bersicht, dazu muss man
        modifyTimeSpec in <a href="webCmd">webCmd</a> spezifizieren.
        </li>
    <li>inactive<br>
        Deaktiviert das entsprechende Ger&auml;t. Beachte den leichten
        semantischen Unterschied zum disable Attribut: "set inactive"
        wird bei einem shutdown automatisch in fhem.state gespeichert, es ist
        kein save notwendig.<br>
        Der Einsatzzweck sind Skripte, um das at tempor&auml;r zu
        deaktivieren.<br>
        Das gleichzeitige Verwenden des disable Attributes wird nicht empfohlen.
        </li>
    <li>active<br>
        Aktiviert das entsprechende Ger&auml;t, siehe inactive.
        </li>
  </ul><br>


  <a name="atget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="atattr"></a>
  <b>Attribute</b>
  <ul>
    <a name="disable"></a>
    <li>disable<br>
        Deaktiviert das entsprechende Ger&auml;t.<br>
        Hinweis: Wenn angewendet auf ein <a href="#at">at</a>, dann wird der
        Befehl nicht ausgef&uuml;hrt, jedoch die n&auml;chste
        Ausf&uuml;hrungszeit berechnet.</li><br>

    <a name="disabledForIntervals"></a>
    <li>disabledForIntervals HH:MM-HH:MM HH:MM-HH-MM...<br>
        Das Argument ist eine Leerzeichengetrennte Liste von Minuszeichen-
        getrennten HH:MM Paaren. Falls die aktuelle Uhrzeit zwischen diesen
        Werten f&auml;llt, dann wird die Ausf&uuml;hrung, wie beim disable,
        ausgesetzt.  Statt HH:MM kann man auch HH oder HH:MM:SS angeben.
        Um einen Intervall um Mitternacht zu spezifizieren, muss man zwei
        einzelne angeben, z.Bsp.:
        <ul>
          23:00-24:00 00:00-01:00
        </ul>
        </li><br>

    <a name="skip_next"></a>
    <li>skip_next<br>
        Wird bei at Befehlen verwendet um die n&auml;chste Ausf&uuml;hrung zu
        &uuml;berspringen</li><br>

    <a name="alignTime"></a>
    <li>alignTime<br>
        Nur f&uuml;r relative Definitionen: Stellt den Zeitpunkt der
        Ausf&uuml;hrung des Befehls so, dass er auch zur alignTime
        ausgef&uuml;hrt wird.  Dieses Argument ist ein timespec. Siehe oben
        f&uuml; die Definition<br>

        Beispiel:<br>
        <ul>
        # Stelle sicher das es gongt wenn eine neue Stunde beginnt.<br>
        define at2 at +*01:00 set Chime on-for-timer 1<br>
        attr at2 alignTime 00:00<br>
        </ul>
        </li><br>

  </ul>
  <br>

</ul>

=end html_DE

=cut
