# $Id: 98_RandomTimer.pm 7654 2015-01-21 19:09:46Z dietmar63 $
##############################################################################
#
#     98_RandomTimer_Initialize.pm
#     written by Dietmar Ortmann
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
# 10.09.2013 Svenson : disable direct if attribute changed, add state disabled;
#                      randomtimer run every day if attribut runonce 0 (default is 1)
#
##############################################################################
package main;

use strict;
use warnings;
use IO::Socket;
use Time::HiRes qw(gettimeofday);
use Time::Local 'timelocal_nocheck';

sub RandomTimer_stopTimeReached($);
sub schaltZeitenErmitteln ($$);
sub RandomTimer_setState($);

sub RandomTimer_Initialize($)
{
  my ($hash) = @_;

  if(!$modules{Twilight}{LOADED} && -f "$attr{global}{modpath}/FHEM/59_Twilight.pm") {
    my $ret = CommandReload(undef, "59_Twilight");
    Log3 undef, 1, $ret if($ret);
  }

  $hash->{DefFn}     = "RandomTimer_Define";
  $hash->{UndefFn}   = "RandomTimer_Undef";
  $hash->{AttrFn}    = "RandomTimer_Attr";
  $hash->{AttrList}  = "onCmd offCmd switchmode disable:0,1 disableCond runonce:0,1 keepDeviceAlive ".
                       $readingFnAttributes;
}
########################################################################
sub RandomTimer_Undef($$) {

  my ($hash, $arg) = @_;

  myRemoveInternalTimer("SetTimer", $hash);
  myRemoveInternalTimer("Exec",     $hash);
  delete $modules{RandomTimer}{defptr}{$hash->{NAME}};
  return undef;
}
########################################################################
sub RandomTimer_Define($$)
{
  my ($hash, $def) = @_;

  RemoveInternalTimer($hash);
  my ($name, $type, $timespec_start, $device, $timespec_stop, $timeToSwitch) =
    split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> RandomTimer <timespec_start> <device> <timespec_stop> <timeToSwitch>"
    if(!defined $timeToSwitch);

  return "Wrong timespec_start <$timespec_start>, use \"[+][*]<time or func>\""
     if($timespec_start !~ m/^(\+)?(\*)?(.*)$/i);

  my ($rel, $rep, $tspec) = ($1, $2, $3);

  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($tspec);
  return $err if($err);

  $rel = "" if(!defined($rel));
  $rep = "" if(!defined($rep));

  return "Wrong timespec_stop <$timespec_stop>, use \"[+][*]<time or func>\""
     if($timespec_stop !~ m/^(\+)?(\*)?(.*)$/i);
  my ($srel, $srep, $stspec) = ($1, $2, $3);
  my ($e, $h, $m, $s, $f) = GetTimeSpec($stspec);
  return $e if($e);

  return "invalid timeToSwitch <$timeToSwitch>, use 9999"
     if(!($timeToSwitch =~  m/^[0-9]{2,4}$/i));

  RandomTimer_set_switchmode ($hash, "800/200") if (!defined $hash->{SWITCHMODE});
   
  $hash->{NAME}           = $name;
  $hash->{DEVICE}         = $device;
  $hash->{TIMESPEC_START} = $timespec_start;
  $hash->{TIMESPEC_STOP}  = $timespec_stop;
  $hash->{TIMETOSWITCH}   = $timeToSwitch;
  $hash->{REP}            = $rep;
  $hash->{REL}            = $rel;
  $hash->{S_REP}          = $srep;
  $hash->{S_REL}          = $srel;
  $hash->{COMMAND}        = "off";

  myRemoveInternalTimer("SetTimer", $hash);
  myInternalTimer      ("SetTimer", time()+1, "RandomTimer_SetTimer", $hash, 0);

  return undef;
}
########################################################################
sub RandomTimer_SetTimer($)
{
  my ($myHash) = @_;
  my $hash = myGetHashIndirekt($myHash, (caller(0))[3]);
  return if (!defined($hash));

  my $now = time();
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($now);
  
  $hash->{active} = 0;

  schaltZeitenErmitteln($hash, $now);
  RandomTimer_setState($hash);
  
  Log3 $hash, 4, "[".$hash->{NAME}."]" . " timings  RandomTimer on $hash->{DEVICE}: "
   . strftime("%H:%M:%S(%d)",localtime($hash->{startTime})) . " - "
   . strftime("%H:%M:%S(%d)",localtime($hash->{stopTime}));
  
  my $secToMidnight = 24*3600 -(3600*$hour + 60*$min + $sec);
  
  my $setExecTime = max($now, $hash->{startTime});
  myRemoveInternalTimer("Exec",     $hash);
  myInternalTimer      ("Exec",     $setExecTime, "RandomTimer_Exec", $hash, 0);

  if ($hash->{REP} gt "") {
     my $setTimerTime = max($now+$secToMidnight, $hash->{stopTime}) + $hash->{TIMETOSWITCH}+15;
     myRemoveInternalTimer("SetTimer", $hash);
     myInternalTimer      ("SetTimer", $setTimerTime, "RandomTimer_SetTimer", $hash, 0);
  }
}
########################################################################
# define Test RandomTimer  +00:00:05 Brunnen +00:05:00 60 ; 
# attr Test room RandomTimerX                             ; 
# attr Test verbose 5                                     ;
# define ds at +00:00:30 attr Test disable 1              ;
#
sub RandomTimer_Exec($) {
   my ($myHash) = @_;
   
   my $hash = myGetHashIndirekt($myHash, (caller(0))[3]);
   return if (!defined($hash));
  
   # Wenn aktiv aber disabled, dann timer abschalten, Meldung ausgeben.
   my $active          = RandomTimer_isAktiv($hash);
   my $disabled        = RandomTimer_isDisabled($hash);
   my $stopTimeReached = RandomTimer_stopTimeReached($hash);
   
   if ($active) {
      # wenn temporär ausgeschaltet
      if ($disabled) {
       #Log3 $hash, 3, "[".$hash->{NAME}. "] RandomTimer for $hash->{DEVICE} going down";
       Log3 $hash, 3, "[".$hash->{NAME}."]"." ending   RandomTimer on $hash->{DEVICE}: "
          . strftime("%H:%M:%S(%d)",localtime($hash->{startTime})) . " - "
          . strftime("%H:%M:%S(%d)",localtime($hash->{stopTime}));
        RandomTimer_down($hash);
        RandomTimer_setState($hash);
        $hash->{active} = 0;
      }
      # Wenn aktiv und Abschaltzeit erreicht, dann Gerät ausschalten, Meldung ausgeben und Timer schließen
      if ($stopTimeReached) {
         Log3 $hash, 3, "[".$hash->{NAME}."]"." ending   RandomTimer on $hash->{DEVICE}: "
            . strftime("%H:%M:%S(%d)",localtime($hash->{startTime})) . " - "
            . strftime("%H:%M:%S(%d)",localtime($hash->{stopTime}));
         RandomTimer_down($hash);
         $hash->{active} = 0;
         if ( AttrVal($hash->{NAME}, "runonce", -1) eq 1 ) {
            Log 3, "[".$hash->{NAME}. "]" ."runonceMode";
            fhem ("delete $hash->{NAME}") ;
         }
         RandomTimer_setState($hash);
         return;
      }
   } else { # !active
      if ($disabled) {
         Log3 $hash, 4, "[".$hash->{NAME}. "] RandomTimer on $hash->{DEVICE} timer disabled - no switch";
         RandomTimer_setState($hash);
         $hash->{active} = 0;
      }
      if ($stopTimeReached) {
         Log3 $hash, 4, "[".$hash->{NAME}."]"." defintion RandomTimer on $hash->{DEVICE}: "
            . strftime("%H:%M:%S(%d)",localtime($hash->{startTime})) . " - "
            . strftime("%H:%M:%S(%d)",localtime($hash->{stopTime}));
         RandomTimer_setState($hash);
         $hash->{active} = 0;
         return;
      }
      if (!$disabled) { 
         Log3 $hash, 3, "[".$hash->{NAME}."]"." starting RandomTimer on $hash->{DEVICE}: "
            . strftime("%H:%M:%S(%d)",localtime($hash->{startTime})) . " - "
            . strftime("%H:%M:%S(%d)",localtime($hash->{stopTime}));
         $hash->{active} = 1;      
      }
   }
   
   RandomTimer_setState($hash);
   RandomTimer_device_toggle($hash) if (!$disabled);

   my $nextSwitch = time() + getSecsToNextAbschaltTest($hash);
   myRemoveInternalTimer("Exec", $hash);
   myInternalTimer      ("Exec", $nextSwitch, "RandomTimer_Exec", $hash, 0);

}
########################################################################
sub RandomTimer_stopTimeReached($) {
   my ($hash) = @_;
   return ( time()>$hash->{stopTime} );
}
########################################################################
sub RandomTimer_isAktiv ($) {
   my ($hash) = @_;
   return defined ($hash->{active}) ? $hash->{active}  : 0;
}
########################################################################
sub RandomTimer_down($) {
   my ($hash) = @_;

   $hash->{COMMAND} = AttrVal($hash->{NAME}, "keepDeviceAlive", 0) ? "on" : "off";
   RandomTimer_device_switch($hash);
}
########################################################################
sub RandomTimer_setState($) {
  my ($hash) = @_;
     
  if (RandomTimer_isDisabled($hash)) {
     $hash->{STATE}  = "disabled";
  } else {
     $hash->{STATE}  = $hash->{active} ? "on" : "off";
  }
  
}
########################################################################
sub RandomTimer_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $hash = $defs{$name};
  
  if( $attrName ~~ ["switchmode"] ) {
     RandomTimer_set_switchmode($hash, $attrVal);
  }
  
  if( $attrName ~~ ["disable","disableCond"] ) {
     
     #RandomTimer_setState($hash); # funktioniert nicht, weil zu diesem Zeitpunkt der Attributwerte noch nicht gesetzt ist. 
     RemoveInternalTimer($hash);
     InternalTimer      (time()+1, "RandomTimer_setState", $hash, 0);       
  }
  return undef;
}
########################################################################
sub RandomTimer_set_switchmode ($$) {

   my ($hash, $attrVal) = @_;
   my $mod = "[".$hash->{NAME} ."] ";

                            
   if(!($attrVal =~  m/^([0-9]{1,3})\/([0-9]{1,3})$/i)) {
      Log3 undef, 3, $mod . "invalid switchMode <$attrVal>, use 999/999";
   } else {
      my ($sigmaoff, $sigmaon) = ($1, $2);
      $hash->{SWITCHMODE}   = $attrVal;
      $hash->{SIGMAON}      = $sigmaon;
      $hash->{SIGMAOFF}     = $sigmaoff;
      $attr{$hash->{NAME}}{switchmode} = $attrVal;
   }
}
########################################################################
sub getSecsToNextAbschaltTest($)
{
    my ($hash) = @_;
    my $intervall = $hash->{TIMETOSWITCH};

    my $proz = 10;
    my $delta    = $intervall * $proz/100;
    my $nextSecs = $intervall - $delta/2 + int(rand($delta));

    return $nextSecs;
}
########################################################################
sub schaltZeitenErmitteln ($$) {
  my ($hash,$now) = @_;

  startZeitErmitteln($hash, $now);
  stopZeitErmitteln ($hash, $now);

}
########################################################################
sub zeitBerechnen  ($$$$) {
   my ($now, $hour, $min, $sec) = @_;

   my @jetzt_arr = localtime($now);
   #Stunden               Minuten               Sekunden
   $jetzt_arr[2] = $hour; $jetzt_arr[1] = $min; $jetzt_arr[0] = $sec;
   my $next = timelocal_nocheck(@jetzt_arr);
   return $next;
}
########################################################################
sub addDays ($$) {
   my ($now, $days) = @_;

   my @jetzt_arr = localtime($now);
   $jetzt_arr[3] += $days;
   my $next = timelocal_nocheck(@jetzt_arr);
   return $next;

}
########################################################################
sub startZeitErmitteln  ($$) {
   my ($hash,$now) = @_;

   my $timespec_start = $hash->{TIMESPEC_START};

   return "Wrong timespec_start <$timespec_start>, use \"[+][*]<time or func>\""
      if($timespec_start !~ m/^(\+)?(\*)?(.*)$/i);
   my ($rel, $rep, $tspec) = ($1, $2, $3);

   my ($err, $hour, $min, $sec, $fn) = GetTimeSpec($tspec);
   return $err if($err);

   my $startTime;
   if($rel) {
      $startTime = $now + 3600* $hour        + 60* $min       +  $sec;
   } else {
      $startTime = zeitBerechnen($now, $hour, $min, $sec);
   }
   $hash->{startTime} = $startTime;
   $hash->{STARTTIME} = strftime("%d.%m.%Y  %H:%M:%S",localtime($startTime));
}
########################################################################
sub stopZeitErmitteln  ($$) {
   my ($hash,$now) = @_;

   my $timespec_stop = $hash->{TIMESPEC_STOP};

   return "Wrong timespec_stop <$timespec_stop>, use \"[+][*]<time or func>\""
      if($timespec_stop !~ m/^(\+)?(\*)?(.*)$/i);
   my ($rel, $rep, $tspec) = ($1, $2, $3);

   my ($err, $hour, $min, $sec, $fn) = GetTimeSpec($tspec);
   return $err if($err);

   my $stopTime;
   if($rel) {
      $stopTime = $hash->{startTime} + 3600* $hour        + 60* $min       +  $sec;
   } else {
      $stopTime = zeitBerechnen($now, $hour, $min, $sec);
   }
   if ($hash->{startTime} > $stopTime) {
      $stopTime  = addDays($stopTime, 1);
   }
   $hash->{stopTime} = $stopTime;
   $hash->{STOPTIME} = strftime("%d.%m.%Y  %H:%M:%S",localtime($stopTime));

}
########################################################################
sub RandomTimer_device_toggle ($)
{
    my ($hash) = @_;

    my $sigma = ($hash->{COMMAND} eq "on") ? $hash->{SIGMAON} : $hash->{SIGMAOFF};

    my $zufall = int(rand(1000));
    Log3 $hash, 4,  "[".$hash->{NAME}."]"." Zustand:$hash->{COMMAND} sigma:$sigma random:$zufall->" . ($zufall < $sigma);

    if ($zufall < $sigma ) {
       $hash->{COMMAND}  = ($hash->{COMMAND} eq "on") ? "off" : "on";
       RandomTimer_device_switch($hash); 
    }
}
########################################################################
sub RandomTimer_device_switch ($)
{
   my ($hash) = @_;
   my $command = "set @ $hash->{COMMAND}";
   if ($hash->{COMMAND} eq "on") {
      $command = AttrVal($hash->{NAME}, "onCmd", $command);
   } else {
      $command = AttrVal($hash->{NAME}, "offCmd", $command);
   }
   $command =~ s/@/$hash->{DEVICE}/g;
   $command = SemicolonEscape($command);
   Log3 $hash, 4, "[".$hash->{NAME}. "]"." command: $command";

   my $ret  = AnalyzeCommandChain(undef, $command);
   Log3 ($hash, 3, $ret)                  if($ret)
}
########################################################################
sub RandomTimer_isDisabled($) {
   my ($hash) = @_;

   my $disable     = AttrVal($hash->{NAME}, "disable",     0 );
   my $disableCond = AttrVal($hash->{NAME}, "disableCond", "");
   
   $disable = $disable || eval ($disableCond);
   if ($@) {
      $@ =~ s/\n/ /g; 
      Log3 ($hash, 3, "[$hash->{NAME}] " . $@);
   }
   $disable = 0 if (!defined($disable));
   
   return $disable;
}
########################################################################
sub RandomTimer_Wakeup() {  # {RandomTimer_Wakeup()}

  foreach my $hc ( sort keys %{$modules{RandomTimer}{defptr}} ) {
     my $hash = $modules{RandomTimer}{defptr}{$hc};
    
     my $myHash->{HASH}=$hash;
     RandomTimer_SetTimer($myHash);
     Log3 undef, 3, "RandomTimer_Wakeup() for $hash->{NAME} done!";
  }
  Log3 undef,  3, "RandomTimer_Wakeup() done!";
}

1;

=pod
=begin html

<a name="RandomTimer"></a>
<h1>RandomTimer</h1>
   <h2>Define</h2>
       <ul>
          <code><font size="+2">define &lt;name&gt; RandomTimer  &lt;timespec_start&gt; &lt;device&gt; &lt;timespec_stop&gt; [&lt;timeToSwitch&gt;]</font></code><br>
         <br>
         Defines a device, that imitates the random switch functionality of a timer clock, like a <b>FS20 ZSU</b>.
         The idea to create it, came from the problem, that is was always a little bit tricky to install a timer clock before
         holiday: finding the manual, testing it the days before and three different timer clocks with three different manuals - a horror.<br>
         By using it in conjunction with a dummy and a <a href="#disableCond">disableCond</a>, I'm able to switch the always defined timer on every weekend easily from all over the world.
         <br><br>
         <h3>Descrition</h3>
          a RandomTimer device starts at timespec_start switching device. Every (timeToSwitch
          seconds +-10%) it trys to switch device on/off. The switching period stops when the
          next time to switch is greater than timespec_stop.
         <br><br>
       </ul>
       <h3>Parameter</h3>
           <ul>
              <b>timespec_start</b>
              <br>
                The parameter <b>timespec_start</b> defines the start time of the timer with format: HH:MM:SS.
                It can be a Perlfunction as known from the <a href="#at">at</a> timespec &nbsp;.
                <br><br>
              <b>device</b>
              <br>
                       The parameter <b>device</b> defines the fhem device that should be switched.
                <br><br>
              <b>timespec_stop</b>
              <br>
                       The parameter <b>timespec_stop</b> defines the stop time of the timer with format: HH:MM:SS.
                It can be a Perlfunction as known from the timespec <a href="#at">at</a> &nbsp;.
                <br><br>
              <b>timeToSwitch</b>
              <br>
                       The parameter <b>timeToSwitch</b> defines the time in seconds between two on/off switches.
                <br><br>
           </ul>
       <h3>Examples</h3>
           <ul>
             <li>
               <code>define ZufallsTimerTisch      RandomTimer  *{sunset_abs()} StehlampeTisch  +03:00:00             500</code><br>
               defines a timer that starts at sunset an ends 3 hous later. The timer trys to switch every 500 seconds(+-10%).
             </li><br><br>
             <li>
               <code>define ZufallsTimerTisch      RandomTimer  *{sunset_abs()} StehlampeTisch  *{sunset_abs(3*3600)} 480</code><br>
               defines a timer that starts at sunset and stops after sunset + 3 hours. The timer trys to switch every 480 seconds(+-10%).
             </li><br><br>
             <li>
               <code>define ZufallsTimerTisch      RandomTimer  *{sunset_abs()} StehlampeTisch  22:30:00 300</code><br>
               defines a timer that starts at sunset an ends at 22:30. The timer trys to switch every 300 seconds(+-10%).
             </li><br><br>
          </ul>

  <!-- -------------------------------------------------------------------------- -->
  <!-- Set     ------------------------------------------------------------------ -->
  <!-- -------------------------------------------------------------------------- -->
  <a name="RandomTimerSet"></a>
  <h3>Set</h3>
  <ul>
    N/A
  </ul>
  <!-- ----------------------------- -->
  <!-- Get     ------------------------- -->
  <!-- Get     ------------------------------------------------------------------ -->
  <!-- -------------------------------------------------------------------------- -->
  <a name="RandomTimerGet"></a>
  <h3>Get</h3>
  <ul>
    N/A
  </ul>
  <!-- -------------------------------------------------------------------------- -->
  <!-- Attributes --------------------------------------------------------------- -->
  <!-- -------------------------------------------------------------------------- -->
  <a name="RandomTimerAttributes"></a>
  <h3>Attributes</h3>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a name="disableCond">disableCond</a><br>
        The default behavior of a RandomTimer is, that it works.
        To set the Randomtimer out of work, you can specify in the disableCond attibute a condition in perlcode that must evaluate to true.
        The Condition must be put into round brackets. The best way is to define
        a function in 99_utils.
        <br>
        <b>Examples</b>
        <pre>
        attr   ZufallsTimerZ         disableCond      (!isVerreist())
        attr   ZufallsTimerZ         disableCond      (Value("presenceDummy") ne "present"))        
        </pre>
    </li>

    <li><a name="disableCond">disableCond</a><br>
        The default behavior of a RandomTimer is, that it shuts down the device after stoptime is reached.
        The <b>keepDeviceAlive</b> attribute  changes the behavior. If set, the device status is not changed when the stoptime is reached.
        <br>
        <b>Example</b>
        <pre>
        attr   ZufallsTimerZ         keepDeviceAlive
        </pre>
    </li>

    <li><a name="onOffCmd">onCmd, offCmd</a><br>
        Setting the on-/offCmd changes the command sent to the device. Standard is: "set &lt;device&gt; on".
        The device can be specified by a @.
        <br>
        <b>Examples</b>
        <pre>
        attr   Timer                  oncmd   {fhem("set @ on-for-timer 14")}
        attr   Timer                  offCmd  {fhem("set @ off 16")}
        attr   Timer                  oncmd  set @ on-for-timer 12
        attr   Timer                  offCmd set @ off 12
        </pre>
    </li>

    <li><a name="switchmode">switchmode</a><br>
        Setting the switchmode you can influence the behavior of switching on/off.
        The parameter has the Format 999/999 and the default ist 800/200. The values are in "per mill".
        The first  parameter sets the value of the probability that the device will be switched on  when the device is off.
        The second parameter sets the value of the probability that the device will be switched off when the device is off.
        <b>Examples</b>
        <pre>
        attr   ZufallsTimerZ         switchmode  400/400
        </pre>
    </li>
 
   </ul>
=end html
=cut