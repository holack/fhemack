﻿########################################################################################
#
# Alarm.pm
#
# FHEM module for house alarm
#
# Prof. Dr. Peter A. Henning
#
# $Id: 95_Alarm.pm 2014-08 - pahenning $
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
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
########################################################################################

package main;

use strict;
use warnings;
use vars qw(%defs);		        # FHEM device/button definitions
use vars qw(%intAt);		    # FHEM at definitions

#########################
# Global variables
my $alarmname       = "Alarms";    # link text
my $alarmhiddenroom = "AlarmRoom"; # hidden room
my $alarmpublicroom = "Alarm";     # public room
my $alarmno         = 8;
my $alarmversion    = "2.5";

#########################################################################################
#
# Alarm_Initialize 
# 
# Parameter hash = hash of device addressed 
#
#########################################################################################

sub Alarm_Initialize ($) {
  my ($hash) = @_;
		
  $hash->{DefFn}       = "Alarm_Define";
  $hash->{SetFn}   	   = "Alarm_Set";  
  $hash->{GetFn}       = "Alarm_Get";
  $hash->{UndefFn}     = "Alarm_Undef";   
  #$hash->{AttrFn}      = "Alarm_Attr";
  my $attst            = "lockstate:lock,unlock statedisplay:simple,color,table,graphics,none armdelay armwait armact disarmact cancelact";
  for( my $level=0;$level<$alarmno;$level++ ){
     $attst .=" level".$level."start level".$level."end level".$level."msg level".$level."xec:0,1 level".$level."onact level".$level."offact ";
  }
  $hash->{AttrList}    = $attst;
  
  $data{FWEXT}{Alarmx}{LINK} = "?room=".$alarmhiddenroom;
  $data{FWEXT}{Alarmx}{NAME} = $alarmname;				  
	
  return undef;
}

#########################################################################################
#
# Alarm_Define - Implements DefFn function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub Alarm_Define ($$) {
 my ($hash, $def) = @_;
 my $now = time();
 my $name = $hash->{NAME}; 
 $hash->{VERSION} = $alarmversion;
 readingsSingleUpdate( $hash, "state", "Initialized", 0 ); 
  
 RemoveInternalTimer($hash);
 InternalTimer      ($now + 5, 'Alarm_CreateEntry', $hash, 0);

 return;
}

#########################################################################################
#
# Alarm_Undef - Implements Undef function
# 
# Parameter hash = hash of device addressed, def = definition string
#
#########################################################################################

sub Alarm_Undef ($$) {
  my ($hash,$arg) = @_;
  
  RemoveInternalTimer($hash);
  
  return undef;
}

#########################################################################################
#
# Alarm_Attr - Implements Attr function
# 
# Parameter hash = hash of device addressed, ???
#
#########################################################################################

sub Alarm_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  return;  
}

#########################################################################################
#
# Alarm_CreateEntry - Puts the Alarm entry into the FHEM menu
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Alarm_CreateEntry($) {
   my ($hash) = @_;
 
   my $name = $hash->{NAME};
   if (!defined $defs{$name."_weblink"}) {
      FW_fC("define ".$name."_weblink weblink htmlCode {Alarm_Html(\"".$name."\")}");
      Log3 $hash, 3, "[".$name. " V".$alarmversion."]"." Weblink ".$name."_weblink created";
   }
   FW_fC("attr ".$name."_weblink room ".$alarmhiddenroom);

   foreach my $dn (sort keys %defs) {
      if ($defs{$dn}{TYPE} eq "FHEMWEB" && $defs{$dn}{NAME} !~ /FHEMWEB:/) {
	     my $hr = AttrVal($defs{$dn}{NAME}, "hiddenroom", "");	
	     if (index($hr,$alarmhiddenroom) == -1){ 		
		    if ($hr eq "") {
		       FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$alarmhiddenroom);
		    }else {
		       FW_fC("attr ".$defs{$dn}{NAME}." hiddenroom ".$hr.",".$alarmhiddenroom);
		    }
		    Log3 $hash, 3, "[".$name. " V".$alarmversion."]"." Added hidden room '".$alarmhiddenroom."' to ".$defs{$dn}{NAME};
	     }	
      }
   }
   my $mga = Alarm_getstate($hash)." Keine Störung";
   readingsSingleUpdate( $hash, "state", $mga, 0 );
}

#########################################################################################
#
# Alarm_Set - Implements the Set function
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Alarm_Set($@) {
   my ( $hash, $name, $cmd, @args ) = @_;

   if ( $cmd =~ /^(cancel|arm|disarm)(ed)?$/ ) {
      return "[Alarm] Invalid argument to set $cmd, must be numeric"
         if ( $args[0] !~ /\d+/ );
      return "[Alarm] Invalid argument to set $cmd, must be 0 < arg < $alarmno"
         if ( ($args[0] >= $alarmno)||($args[0]<0) );
      if( $cmd =~ /^cancel(ed)?$/ ){     
         Alarm_Exec($name,$args[0],"web","button","cancel");
      }elsif ( $cmd =~ /^arm(ed)?$/ ) {
         Alarm_Arm($name,$args[0],"web","button","arm");
      }elsif ( $cmd =~ /^disarm(ed)?$/ ){
         Alarm_Arm($name,$args[0],"web","button","disarm");
      }else{
         return "[Alarm] Invalid argument set $cmd";
      }
	  return;
   } elsif ( $cmd =~ /^lock(ed)?$/ ) {
	  readingsSingleUpdate( $hash, "lockstate", "locked", 0 ); 
	  return;
   } elsif ( $cmd =~ /^unlock(ed)?$/ ) {
	  readingsSingleUpdate( $hash, "lockstate", "unlocked", 0 );
	  return;
   } else {
     my $str =  join(",",(0..($alarmno-1)));
	 return "[Alarm] Unknown argument " . $cmd . ", choose one of canceled:$str armed:$str disarmed:$str locked:noArg unlocked:noArg";
   }
}

#########################################################################################
#
# Alarm_Set - Implements the Get function
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Alarm_Get($@) {
  my ($hash, @a) = @_;
  my $res = "";
  
  my $arg = (defined($a[1]) ? $a[1] : "");
  if ($arg eq "version") {
    return "Alarm.version => $alarmversion";
  } else {
    return "Unknown argument $arg choose one of version";
  }
}

#########################################################################################
#
# Alarm_getstate - Helper function to assemble a state display
# 
# Parameter hash = hash of device addressed
#
#########################################################################################

sub Alarm_getstate($) {
  my ($hash) = @_;
  my $res = '';
  my $type = AttrVal($hash->{NAME},"statedisplay",0);
  #--------------------------
  if( $type eq "simple" ){
     for( my $level=0;$level<$alarmno;$level++ ){
        if( $hash->{READINGS}{"level".$level}{VAL} eq "off" ){
           $res.='O';
        }else{
           $res.='X';
        }
     }
  #--------------------------
  }elsif( $type eq "color" ){
     $res = '<span style="color:green">';
     for( my $level=0;$level<$alarmno;$level++ ){
        if( $hash->{READINGS}{"level".$level}{VAL} eq "off" ){
           $res.=' '.$level;
        }else{
           $res.=' <span style="width:1ex;color:red">'.$level.'</span>';
        }
     }
     $res.='</span>';
  #--------------------------
  }elsif( $type eq "table" ){
     $res = '<table><tr style="height:1ex">';
     for( my $level=0;$level<$alarmno;$level++ ){
        if( $hash->{READINGS}{"level".$level}{VAL} eq "off" ){
           $res.='<td style="width:1ex;background-color:green"/>';
        }else{
           $res.='<td style="width:1ex;background-color:red"/>';
        }
     }
     $res.='</tr></table>';
  #--------------------------
  }
  return $res;
}

#########################################################################################
#
# Alarm_Exec - Execute the Alarm
# 
# Parameter name  = name of the Alarm definition
#           level = Alarm level 
#           dev   = name of the device calling the alarm
#           evt   = event calling the alarm
#           act   = action - "on" or "off"
#
#########################################################################################

sub Alarm_Exec($$$$$){

   my ($name,$level,$dev,$evt,$act) = @_;
   my $hash  = $defs{$name};
   my $xec   = AttrVal($name, "level".$level."xec", 0); 
   my $xac   = $hash->{READINGS}{'level'.$level}{VAL};
   my $msg   = '';
   my $cmd;
   my $mga;
   my $dly;
   my @sta;
   
   #Log3 $hash,1,"[Alarm $level] Exec called with dev $dev evt $evt act $act]";
   return 
     if ($dev eq 'global');

   #-- raising the alarmy 
   if( $act eq "on" ){
      #-- only if this level is armed and not yet active
      if( ($xec eq "armed") && ($xac eq "off") ){ 
         #-- check for time
         my $start = AttrVal($name, "level".$level."start", 0);
         if(  index($start, '{') != -1){
           $start = eval($start);
         }
         my @st = split(':',$start);
         if( (int(@st)>3) || (int(@st)<2) || ($st[0] > 23) || ($st[0] < 0) || ($st[1] > 59) || ($st[1] < 0) ){
           Log3 $hash,1,"[Alarm $level] Cannot be executed due to wrong time spec $start for level".$level."start";
           return;
         }
         
         my $end   = AttrVal($name, "level".$level."end", 0);
         if(  index($end, '{') != -1){
           $end = eval($end);
         }
         my @et  = split(':',$end);
         if( (int(@et)>3) || (int(@et)<2) || ($et[0] > 23) || ($et[0] < 0) || ($et[1] > 59) || ($et[1] < 0) ){
           Log3 $hash,1,"[Alarm $level] Cannot be executed due to wrong time spec $end for level".$level."end";
           return;
         }
         
         my $stp = $st[0]*60+$st[1];
         my $etp = $et[0]*60+$et[1];
     
         my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst) = localtime(time);
         my $ntp = $hour*60+$min;
     
         if( (($stp < $etp) && ($ntp <= $etp) && ($ntp >= $stp)) ||  (($stp > $etp) && (($ntp <= $etp) || ($ntp >= $stp))) ){  
            #-- raised by sensor (attribute values have been controlled in CreateNotifiers)
            @sta = split('\|',  AttrVal($dev, "alarmSettings", 0));
            if( $sta[2] ){
              $mga = $sta[2]." ".AttrVal($name, "level".$level."msg", 0);
              #-- replace some parts
              my @evtpart = split(" ",$evt);
              $mga =~ s/\$NAME/$dev/g;
              $mga =~ s/\$EVENT/$evt/g;
              for( my $i=1;$i<= int(@evtpart);$i++){
                 $mga =~ s/\$EVTPART$i/$evtpart[$i-1]/g;
              }
              #-- readings
              readingsSingleUpdate( $hash, "level".$level,$dev,0 );
              readingsSingleUpdate( $hash, "short", $mga, 0);
              $mga = Alarm_getstate($hash)." ".$mga;
              readingsSingleUpdate( $hash, "state", $mga, 0 );
              $msg = "[Alarm $level] raised from device $dev with event $evt";
              #-- calling actors AFTER state update
              $cmd = AttrVal($name, "level".$level."onact", 0);
              fhem($cmd); 
              Log3 $hash,3,$msg;
           }else{  
              $msg = "[Alarm $level] not raised, alarmSensor $dev has wrong settings";
              Log3 $hash,1,$msg;            
           }
         }else{
            $msg = "[Alarm $level] not raised, not in time slot";
            Log3 $hash,5,$msg;
         }
      }else{
         $msg = "[Alarm $level] not raised, not armed or already active";
         Log3 $hash,5,$msg;
      } 
   }elsif( ($act eq "off")||($act eq "cancel") ){
      #-- only if this level is active
      if( $xac ne "off"){
         #-- deleting all running ats
         $dly = sprintf("alarm%1ddly",$level);
         foreach my $d (sort keys %intAt ) {
            next if( $intAt{$d}{FN} ne "at_Exec" );
            $mga = $intAt{$d}{ARG}{NAME};
            next if( $mga !~ /$dly\d/);
            #Log3 $hash,1,"[Alarm] Killing delayed action $name";
            CommandDelete(undef,"$mga");
         }
         #-- calling actors BEFORE state update
         $cmd = AttrVal($name, "level".$level."offact", 0);
         fhem($cmd);
         $cmd = AttrVal($name, "cancelact", 0);
         fhem($cmd)
           if( $cmd );
         #-- readings
         readingsSingleUpdate( $hash, "level".$level,"off",0 );
         $mga = " Level $level canceled";
         readingsSingleUpdate( $hash, "short", "", 0);
         $mga = Alarm_getstate($hash)." ".$mga;
         readingsSingleUpdate( $hash, "state", $mga, 0 );
         $msg = "[Alarm $level] canceled from device $dev";
         Log3 $hash,3,$msg;
     }
   }else{
     Log3 $hash,3,"[Alarm $level] Exec called with act=$act";
   }
   #return $msg;
}

#########################################################################################
#
# Alarm_Arm - Arm the Alarm
# 
# Parameter name  = name of the Alarm definition
#           level = Alarm level 
#           dev   = name of the device calling the alarm
#           act   = action - "armed" or "disarmed"
#
#########################################################################################

sub Alarm_Arm($$$$$){

   my ($name,$level,$dev,$evt,$act) = @_;
   my $hash  = $defs{$name};
   my $xac   = $hash->{READINGS}{"level"}{VAL};
   my $xec   = AttrVal($name, 'level'.$level.'xec', 0);
   my $msg   = '';
   my $mga;
   my $cmd;
         
   #-- arming the alarm
   if( ($act eq "arm") && ( $xec ne "armed")  ){
      my $xdl     = AttrVal($name, "armdelay", 0);
      my $cmdwait = AttrVal($name, "armwait", 0);
      my $cmdact  = AttrVal($name, "armact", 0);
      if( ($xdl eq '')|($xdl eq '0:00')|($xdl eq '00:00') ){
         CommandAttr(undef,$name.' level'.$level.'xec armed');
         $msg = "[Alarm $level] armed from device $dev with event $evt"; 
         Log3 $hash,3,$msg; 
      } elsif( $xdl =~ /([0-9])?:([0-5][0-9])?/  ){
         CommandAttr(undef,$name.' level'.$level.'xec armwait');
         #--transform commands from fhem to perl level
         my @cmdactarr = split(/;/,$cmdact);
         my $cmdactf;
         if( int(@cmdactarr) == 1 ){
           $cmdactf   = "fhem(\"".$cmdact."\");;";
         }else{
           $cmdactf   = '';
             for(my $i=0;$i<int(@cmdactarr);$i++){
               $cmdactf.="fhem(\"".$cmdactarr[$i]."\");;";
           }
         }
         #-- compose commands
         $cmd = sprintf("define alarm%1d.arm.dly at +00:%02d:%02d {fhem(\"attr %s level%1dxec armed\");;%s}",$level,$1,$2,$name,$level,$cmdactf);
         $msg = "[Alarm $level] will be armed from device $dev with event $evt, delay $xdl"; 
         #-- delete old delayed arm
         fhem('delete alarm'.$level.'.arm.dly' )
           if( defined $defs{'alarm'.$level.'.arm.dly'});
         #-- define new delayed arm
         fhem($cmd); 
         #-- execute armwait action
         fhem($cmdwait);
         Log3 $hash,3,$msg; 
      }else{
         $msg = "[Alarm $level] cannot be armed due to wrong delay timespec"; 
         Log3 $hash,1,$msg; 
      }
   #-- disarming implies canceling as well
   }elsif( ($act eq "disarm") &&  ($xec ne "disarmed")) {
      #-- delete old delayed arm
      fhem('delete alarm'.$level.'.arm.dly' )
         if( defined $defs{'alarm'.$level.'.arm.dly'});
      CommandAttr (undef,$name.' level'.$level.'xec disarmed');
      Alarm_Exec($name,$level,"program","disarm","cancel");
      #--
      $msg = "[Alarm $level] disarmed from device $dev with event $evt";
      $cmd = AttrVal($name, "disarmact", 0);
      fhem("define alarm".$level.".disarm.T at +00:00:03 ".$cmd)
        if( $cmd ); 
   }
   return $msg;
}

#########################################################################################
#
# Alarm_CreateNotifiers - Create the notifiers
# 
# Parameter name = name of the Alarm definition
#
#########################################################################################

sub Alarm_CreateNotifiers($){
  my ($name) = @_; 

  my $ret = "";
  my $res;
 
  my $hash = $defs{$name};
  #-- don't do anything if locked
  if( $hash->{READINGS}{"lockstate"}{VAL} ne "unlocked" ){
     Log3 $hash, 1, "[Alarm] State locked, cannot create new notifiers";
     return "State locked, cannot create new notifiers";
  }
  
  for( my $level=0;$level<$alarmno;$level++ ){
  
     #-- delete old defs in any case
     fhem('delete alarm'.$level.'.on.N' )
        if( defined $defs{'alarm'.$level.'.on.N'});
     fhem('delete alarm'.$level.'.off.N' )
        if( defined $defs{'alarm'.$level.'.off.N'});
     fhem('delete alarm'.$level.'.arm.N' )
        if( defined $defs{'alarm'.$level.'.arm.N'});
     fhem('delete alarm'.$level.'.disarm.N' )
        if( defined $defs{'alarm'.$level.'.disarm.N'});
  
     my $start = AttrVal($name, "level".$level."start", 0);
     my @st;
     if( index($start,'{')!=-1 ){
        Log3 $hash,1,"[Alarm $level] perl function $start detected for level".$level."start, currently the function gives ".eval($start);
     }else{
        @st = split(':',($start ne '') ? $start :'0:00');
        if( (int(@st)!=2) || ($st[0] > 23) || ($st[0] < 0) || ($st[1] > 59) || ($st[1] < 0) ){
           Log3 $hash,1,"[Alarm $level] Will not be executed due to wrong time spec $start for level".$level."start";
           next;
        }
     }
     
     my $end   = AttrVal($name, "level".$level."end", 0);
     my @et;
     if( index($end,'{')!=-1 ){
        Log3 $hash,1,"[Alarm $level] perl function $end detected for level".$level."end, currently the function gives ".eval($end);
     }else{
        @et = split(':',($end ne '') ? $end :'23:59');
        if( (int(@et)!=2) || ($et[0] > 23) || ($et[0] < 0) || ($et[1] > 59) || ($et[1] < 0) ){
           Log3 $hash,1,"[Alarm $level] Will not be executed due to wrong time spec $end for level".$level."end";
           next;
        }
     }
    
     #-- now set up the command for cancel alarm, and contained in this loop all other notifiers as well
     my $cmd = '';
     foreach my $d (keys %defs ) {
        next if(IsIgnored($d));
        if( AttrVal($d, "alarmDevice","") eq "Sensor" ) {
           my @aval = split('\|',AttrVal($d, "alarmSettings",""));
           if( int(@aval) != 4){
              # Log3 $hash, 1, "[Alarm $level] Settings incomplete for sensor $d";
              next;
           }
           if( (index($aval[0],"alarm".$level) != -1) && ($aval[3] eq "off") ){
              $cmd .= '('.$aval[1].')|';
              #Log3 $hash,1,"[Alarm $level] Adding sensor $d to cancel notifier";
           }
        }   
     }
     if( $cmd eq '' ){
        Log3 $hash,1,"[Alarm $level] No \"Cancel\" device defined, level will be ignored";
     } else {
        $cmd  =  substr($cmd,0,length($cmd)-1);
        $cmd  = 'alarm'.$level.'.off.N notify '.$cmd;
        $cmd .= ' {main::Alarm_Exec("'.$name.'",'.$level.',"$NAME","$EVENT","off")}';
        CommandDefine(undef,$cmd);
        CommandAttr (undef,'alarm'.$level.'.off.N room '.$alarmpublicroom); 
        CommandAttr (undef,'alarm'.$level.'.off.N group alarmNotifier'); 
        Log3 $hash,5,"[Alarm $level] Created cancel notifier";    
     
        #-- now set up the command for raising alarm - only if cancel exists
        $cmd        = '';
        my $cmdarm   = "";
        my $cmddisarm = "";
        foreach my $d (sort keys %defs ) {
           next if(IsIgnored($d));
           if( AttrVal($d, "alarmDevice","") eq "Sensor" ) {
              my @aval = split('\|',AttrVal($d, "alarmSettings",""));
              if( int(@aval) != 4){
                 # Log3 $hash, 1, "[Alarm $level] Settings incomplete for sensor $d";
                 next;
              }
              if( index($aval[0],"alarm".$level) != -1){
                 if( $aval[3] eq "on" ){
                    $cmd .= '('.$aval[1].')|';
                    # Log3 $hash,1,"[Alarm $level] Adding sensor $d to raise notifier";
                 }elsif( $aval[3] eq "arm" ){
                    $cmdarm .= '('.$aval[1].')|';
                    #Log3 $hash,1,"[Alarm $level] Adding sensor $d to arm notifier";
                 }elsif( $aval[3] eq "disarm" ){
                    $cmddisarm .= '('.$aval[1].')|';
                    # Log3 $hash,1,"[Alarm $level] Adding sensor $d to disarm notifier";
                 }
              }
           }   
        }
        #-- raise notifier
        if( $cmd eq '' ){
           Log3 $hash,1,"[Alarm $level] No \"Raise\" device defined";
        } else {   
           $cmd  = substr($cmd,0,length($cmd)-1);
           $cmd  = 'alarm'.$level.'.on.N notify '.$cmd;
           $cmd .= ' {main::Alarm_Exec("'.$name.'",'.$level.',"$NAME","$EVENT","on")}';
           CommandDefine(undef,$cmd);
           CommandAttr (undef,'alarm'.$level.'.on.N room '.$alarmpublicroom); 
           CommandAttr (undef,'alarm'.$level.'.on.N group alarmNotifier'); 
           Log3 $hash,5,"[Alarm $level] Created raise notifier";
           
           #-- now set up the list of actors
           $cmd      = '';
           my $cmd2  = '';
           my $nonum = 0;
           foreach my $d (sort keys %defs ) {
              next if(IsIgnored($d));
              if( AttrVal($d, "alarmDevice","") eq "Actor" ) {
                 my @aval = split('\|',AttrVal($d, "alarmSettings",""));
                 if( int(@aval) != 4){
                   Log3 $hash, 5, "[Alarm $level] Settings incomplete for actor $d";
                   next;
                 }
                 if( index($aval[0],"alarm".$level) != -1 ){
                    #-- activate without delay 
                    if( $aval[3] eq "0" ){
                       $cmd  .= $aval[1].';';
                    #-- activate with delay
                    } else {
                       $nonum++;
                       my @tarr = split(':',$aval[3]);
                       if( int(@tarr) == 1){   
                          if( $aval[3] > 59 ){
                             Log3 $hash,3,"[Alarm $level] Invalid delay specification for actor $d: $aval[3] > 59";
                             $cmd = '';
                          } else {
                             $cmd  .= sprintf('define alarm%1ddly%1d at +00:00:%02d %s;',$level,$nonum,$aval[3],$aval[1]);       
                          }
                       }elsif( int(@tarr) == 2){
                          $cmd  .= sprintf('define alarm%1ddly%1d at +00:%02d:%02d %s;',$level,$nonum,$tarr[0],$tarr[1],$aval[1]);
                       }      
                    }
                    $cmd2 .= $aval[2].';'
                      if( $aval[2] ne '' );
                    Log3 $hash,5,"[Alarm $level] Adding actor $d to action list";
                 }
              }   
           }
           if( $cmd ne '' ){
              CommandAttr(undef,$name.' level'.$level.'onact '.$cmd);
              CommandAttr(undef,$name.' level'.$level.'offact '.$cmd2);
              Log3 $hash,5,"[Alarm $level] Added on/off actors to $name";
           } else {
              Log3 $hash,5,"[Alarm $level] Adding on/off actors not possible";
           }
           #-- arm notifier - optional, but only in case the alarm may be raised
           if( $cmdarm ne '' ){
              $cmdarm  = substr($cmdarm,0,length($cmdarm)-1);
              $cmdarm  = 'alarm'.$level.'.arm.N notify '.$cmdarm;
              $cmdarm .= ' {main::Alarm_Arm("'.$name.'",'.$level.',"$NAME","$EVENT","arm")}';
              CommandDefine(undef,$cmdarm);
              CommandAttr (undef,'alarm'.$level.'.arm.N room '.$alarmpublicroom); 
              CommandAttr (undef,'alarm'.$level.'.arm.N group alarmNotifier'); 
              Log3 $hash,3,"[Alarm $level] Created arm notifier";
           }
           #-- disarm notifier - optional, but only in case the alarm may be raised
           if( $cmddisarm ne '' ){
              $cmddisarm  = substr($cmddisarm,0,length($cmddisarm)-1);
              $cmddisarm  = 'alarm'.$level.'.disarm.N notify '.$cmddisarm;
              $cmddisarm .= ' {main::Alarm_Arm("'.$name.'",'.$level.',"$NAME","$EVENT","disarm")}';
              CommandDefine(undef,$cmddisarm);
              CommandAttr (undef,'alarm'.$level.'.disarm.N room '.$alarmpublicroom); 
              CommandAttr (undef,'alarm'.$level.'.disarm.N group alarmNotifier'); 
              Log3 $hash,3,"[Alarm $level] Created disarm notifier";
           }
        }
     }
  }
  return "Created alarm notifiers";
}

#########################################################################################
#
# Alarm_Html - returns HTML code for the Alarm page
# 
# Parameter name = name of the Alarm definition
#
#########################################################################################

sub Alarm_Html($)
{
	my ($name) = @_; 

    my $ret = "";
 
    my $hash = $defs{$name};
    my $id = $defs{$name}{NR};
    
    #-- 
    readingsSingleUpdate( $hash, "state", Alarm_getstate($hash)." ".$hash->{READINGS}{"short"}{VAL}, 0 );
 
    #--
    my $lockstate = ($hash->{READINGS}{lockstate}{VAL}) ? $hash->{READINGS}{lockstate}{VAL} : "unlocked";
    my $showhelper = ($lockstate eq "unlocked") ? 1 : 0; 

    #--
    $ret .= "<script type=\"text/javascript\" src=\"/fhem/pgm2/alarm.js\"></script><script type=\"text/javascript\">\n";
    $ret .= "var alarmno = ".$alarmno.";\n";
    for( my $k=0;$k<$alarmno;$k++ ){
      $ret .= "ah.setItem('l".$k."s','".AttrVal($name, "level".$k."start", 0)."');\n"
        if( defined AttrVal($name, "level".$k."start", 0));
      $ret .= "ah.setItem('l".$k."e','".AttrVal($name, "level".$k."end", 0)."');\n"
        if( defined AttrVal($name, "level".$k."end", 0));
      $ret .= "ah.setItem('l".$k."m','".AttrVal($name, "level".$k."msg", 0)."');\n"
        if( defined AttrVal($name, "level".$k."msg", 0));
      $ret .= "ah.setItem('l".$k."x','".AttrVal($name, "level".$k."xec", 0)."');\n"
        if( defined AttrVal($name, "level".$k."xec", 0));
    }
    $ret .= "</script>\n";
    
    $ret .= "<table class=\"roomoverview\">\n";
    $ret .= "<tr><td><input type=\"button\" value=\"Set Alarms\" onclick=\"javascript:alarm_set('$name')\"/></td></tr>\n";
    
    #-- settings table
    my $row=1;
    $ret .= "<tr><td><div class=\"devType\">Settings</div></td></tr>";
    $ret .= "<tr><td><table class=\"block wide\" id=\"settingstable\">\n"; 
    $ret .= "<tr class=\"odd\"><td class=\"col1\" colspan=\"4\"><table id=\"armtable\" border=\"0\">\n";
    $ret .= "<tr class==\"odd\"><td class=\"col1\" align=\"right\">Arm Button &#8608</td>";
    $ret .=                    "<td class=\"col2\" align=\"right\"> Wait Action ";
    $ret .= sprintf("<input type=\"text\" id=\"armwait\" size=\"50\" maxlength=\"512\" value=\"%s\"/>",AttrVal($name, "armwait","")); 
    $ret .=               "</td><td class=\"col3\" rowspan=\"2\"> &#8628 Delay <br> &#8626";
    $ret .= sprintf("<input type=\"text\" id=\"armdelay\" size=\"4\" maxlength=\"5\" value=\"%s\"/>",AttrVal($name, "armdelay",""));
    $ret .=               "</td></tr>\n"; 
    $ret .= "<tr class==\"even\"><td class=\"col1\"></td><td class=\"col2\" align=\"right\">Arm Action ";
    $ret .= sprintf("<input type=\"text\" id=\"armaction\" size=\"50\" maxlength=\"512\" value=\"%s\"/>",AttrVal($name, "armact","")); 
    $ret .=               "</td></tr>\n";
    $ret .="<tr class==\"odd\"><td class=\"col1\">Disarm Button &#8608</td><td class=\"col2\" align=\"right\">Disarm Action ";
    $ret .= sprintf("<input type=\"text\" id=\"disarmaction\" size=\"50\" maxlength=\"512\" value=\"%s\"/>",AttrVal($name, "disarmact","")); 
    $ret .= "</td><td></td></tr><tr class==\"odd\"><td class=\"col1\">Cancel Button &#8608</td><td class=\"col2\" align=\"right\"> Cancel Action ";
    $ret .= sprintf("<input type=\"text\" id=\"cancelaction\" size=\"50\" maxlength=\"512\" value=\"%s\"/>",AttrVal($name, "cancelact","")); 
    $ret .= "</td><td></td></tr></table></td></tr>";
    $ret .= "<tr class=\"odd\"><td class=\"col1\">Level</td><td class=\"col2\">Time [hh:mm]</td><td class=\"col3\">Message Part II</td>".
            "<td class=\"col4\">Armed/Cancel</td></tr>\n";
    for( my $k=0;$k<$alarmno;$k++ ){
      $row++;
      my $sval = AttrVal($name, "level".$k."start", 0);
      $sval = ""
        if( $sval eq "1");
      my $eval = AttrVal($name, "level".$k."end", 0);
      $eval = ""
        if( $eval eq "1");
      my $mval = AttrVal($name, "level".$k."msg", 0);
      $mval = ""
        if( $mval eq "1");

      my $xval = AttrVal($name, "level".$k."xec", 0);
      $ret .= sprintf("<tr class=\"%s\"><td class=\"col1\">Alarm $k</td>\n", ($row&1)?"odd":"even"); 
      $ret .= "<td class=\"col2\">Start&nbsp;<input type=\"text\" id=\"l".$k."s\" size=\"4\" maxlength=\"120\" value=\"$sval\"/>&nbsp;".
              "End&nbsp;<input type=\"text\" id=\"l".$k."e\" size=\"4\" maxlength=\"120\" value=\"$eval\"/></td>".
              "<td class=\"col3\"><input type=\"text\" id=\"l".$k."m\" size=\"25\" maxlength=\"256\" value=\"$mval\"/></td>";
      $ret .= sprintf("<td class=\"col4\"><input type=\"checkbox\" id=\"l".$k."x\" %s onclick=\"javascript:alarm_arm('$name','$k')\"/>",($xval eq "armed")?"checked=\"checked\"":"").
              "<input type=\"button\" value=\"Cancel\" onclick=\"javascript:alarm_cancel('$name','$k')\"/></td></tr>\n";
    }    
    $ret .= "</table></td></tr></tr>";
   
    #-- sensors table
    $row=1;
    $ret .= "<tr><td><div class=\"devType\">Sensors</div></td></tr>";
    $ret .= "<tr><td><table class=\"block wide\" id=\"sensorstable\">\n"; 
    $ret .= "<tr class=\"odd\"><td/><td class=\"col2\">Notify to Alarm Level<br/>".join("&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;",(0..($alarmno-1)))."</td><td class=\"col3\">".
            "Notify on RegExp&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Message Part I</td><td class=\"col4\">Action</td></tr>\n";
    foreach my $d (sort keys %defs ) {
       next if(IsIgnored($d));
       if( AttrVal($d, "alarmDevice","") eq "Sensor" ) {
           my @aval = split('\|',AttrVal($d, "alarmSettings",""));
           if( int(@aval) != 4){
             @aval=("","","","");
           }
           $row++;
           $ret .= sprintf("<tr class=\"%s\" informId=\"$d\" name=\"sensor\">", ($row&1)?"odd":"even");
           $ret .= "<td width=\"100\" class=\"col1\"><a href=\"$FW_ME?detail=$d\">$d</a></td>\n";
           $ret .= "<td id=\"$d\" class=\"col2\">\n";
           for( my $k=0;$k<$alarmno;$k++ ){
              $ret .= sprintf("<input type=\"checkbox\" name=\"alarm$k\" value=\"$k\" %s/>&nbsp;",(index($aval[0],"alarm".$k) != -1)?"checked=\"checked\"":""); 
           }
           $ret .= "</td><td class=\"col3\"><input type=\"text\" name=\"alarmnotify\" size=\"13\" maxlength=\"512\" value=\"$aval[1]\"/>";
           $ret .= "<input type=\"text\" name=\"alarmmsg\" size=\"13\" maxlength=\"512\" value=\"$aval[2]\"/></td>\n"; 
           $ret .= sprintf("<td class=\"col4\"><select name=\"%sonoff\"><option value=\"on\" %s>Raise</option><option value=\"off\" %s>Cancel</option>",
               $d,($aval[3] eq "on")?"selected=\"selected\"":"",($aval[3] eq "off")?"selected=\"selected\"":"");
           $ret .= sprintf("<option value=\"arm\" %s>Arm</option><option value=\"disarm\" %s>Disarm</option><select></td></tr>\n",
               ($aval[3] eq "arm")?"selected=\"seleced\"":"",($aval[3] eq "disarm")?"selected=\"selected\"":"");
       }
    }  
    $ret .= "</table></td></tr></tr>";
    
    #-- actors table
    $row=1;
    $ret .= "<tr><td><div class=\"devType\">Actors</div></td></tr>";
    $ret .= "<tr><td><table class=\"block wide\" id=\"actorstable\">\n"; 
    $ret .= "<tr class=\"odd\"><td/><td class=\"col2\">Set by Alarm Level<br/>".join("&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;",(0..($alarmno-1))).
            "</td><td class=\"col3\">Set Action".
            "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Unset Action</td><td class=\"col4\">Delay</td></tr>\n";
    foreach my $d (sort keys %defs ) {
       next if(IsIgnored($d));
       if( AttrVal($d, "alarmDevice","") eq "Actor" ) {
           my @aval = split('\|',AttrVal($d, "alarmSettings",""));
           if( int(@aval) != 4){
             @aval=("","","","");
           }
           $row++;
           $ret .= sprintf("<tr class=\"%s\" informId=\"$d\" name=\"actor\">", ($row&1)?"odd":"even");
           $ret .= "<td width=\"100\" class=\"col1\"><a href=\"$FW_ME?detail=$d\">$d</a></td>\n";
           $ret .= "<td id=\"$d\" class=\"col2\">\n";
           for( my $k=0;$k<$alarmno;$k++ ){
              $ret .= sprintf("<input type=\"checkbox\" name=\"alarm$k\"%s/>&nbsp;",(index($aval[0],"alarm".$k) != -1)?"checked=\"checked\"":""); 
           }
           $ret .= "</td><td class=\"col3\"><input type=\"text\" name=\"alarmon\" size=\"13\" maxlength=\"512\" value=\"$aval[1]\"/>"; 
           $ret .= "<input type=\"text\" name=\"alarmaoff\" size=\"13\" maxlength=\"512\" value=\"$aval[2]\"/></td>"; 
           $ret .= "<td class=\"col4\"><input type=\"text\" name=\"delay\" size=\"4\" maxlength=\"5\" value=\"$aval[3]\"/></td></tr>\n";
       }
    }  
	$ret .= "</table></td></tr></tr>\n";
	
	$ret .= "</table>";
 
 return $ret; 
}

1;

=pod
=begin html

<a name="Alarm"></a>
        <h3>Alarm</h3>
        <p> FHEM module to set up a House Alarm System with 8 different alarm levels</p>
        <a name="Alarmdefine"></a>
        <h4>Define</h4>
        <p>
            <code>define &lt;name&gt; Alarm</code> 
            <br />Defines the Alarm system.
        </p>
        <a name="Alarmset"></a>
        <h4>Set</h4>
        <ul>
            <li><a name="alarm_cancel">
                    <code>set &lt;name&gt; canceled &lt;level&gt;</code>
                </a>
                <br/>cancels an alarm of level &lt;level&gt;, where &lt;level&gt; = 0..7
            </li>
            <li><a name="alarm_arm">
                    <code>set &lt;name&gt; armed &lt;level&gt;</code><br/>
                    <code>set &lt;name&gt; disarmed &lt;level&gt;</code>
                </a>
                <br/>sets the alarm of level &lt;level&gt; to armed (i.e., active) or disarmed (i.e., inactive), where &lt;level&gt; = 0..7
            </li>
            <li><a name="alarm_lock">
                    <code>set &lt;name&gt; locked</code><br/>
                    <code>set &lt;name&gt; unlocked</code>
                </a>
                <br/>sets the lockstate of the alarm module to <i>locked</i> (i.e., alarm setups may not be changed)
                resp. <i>unlocked</i> (i.e., alarm setups may be changed>)</li>
        </ul>
        <a name="Alarmget"></a>
        <h4>Get</h4>
        <ul>
            <li><a name="alarm_version"></a>
                <code>get &lt;name&gt; version</code>
                <br />Display the version of the module</li>
        </ul>
        <a name="Alarmattr"></a>
        <h4>Attributes</h4>
        <ul>
            <li><a name="alarm_lockstate"><code>attr &lt;name&gt; lockstate locked|unlocked</code></a>
                <br /><i>locked</i> means that alarm setups may not be changed, 
                <i>unlocked</i> means that alarm setups may be changed></li>
            <li><a name="alarm_statedisplay"><code>attr &lt;name&gt; statedisplay simple,color,table,none</code></a>
                <br />defines how the state of all eight alarm levels is shown. Example for the case when only alarm no. 2 is raised:
                <ul>
                    <li> simple=OOXOOOOO</li>
                    <li> color=<span style="color:green"> 0 1 <span style="width:1ex;color:red">2</span> 3 4 5 6 7</span></li>
                    <li> table=<table><tr style="height:1ex"><td style="width:1ex;background-color:green"/><td style="width:1ex;background-color:green"/><td style="width:1ex;background-color:red"/><td style="width:1ex;background-color:green"/><td style="width:1ex;background-color:green"/><td style="width:1ex;background-color:green"/><td style="width:1ex;background-color:green"/><td style="width:1ex;background-color:green"/></tr></table> </li>
                    <li> none=no state display</li>
                </ul>
                </li>
            <li><a name="alarm_armdelay"><code>attr &lt;name&gt; armdelay <i>mm:ss</i></code></a>
                <br />time until the arming of an alarm becomes operative (0:00 - 9:59 allowed)</li>
            <li><a name="alarm_armwait"><code>attr &lt;name&gt; armwait <i>action</i></code></a>
                <br />FHEM action to be carried out immediately after the arm event</li>
            <li><a name="alarm_armact"><code>attr &lt;name&gt; armact <i>action</i></code></a>
                <br />FHEM action to be carried out at the arme event after the delay time </li>
            <li><a name="alarm_disarmact"><code>attr &lt;name&gt; disarmact <i>action</i></code></a>
                <br />FHEM action to be carried out on the disarming of an alarm</li>
            <li><a name="alarm_cancelact"><code>attr &lt;name&gt; cancelact <i>action</i></code></a>
                <br />FHEM action to be carried out on the canceling of an alarm</li>
            <li><a name="alarm_internals"/>For each of the 8 alarm levels, several attributes hold the alarm setup. 
                They should not be changed by hand, but through the web interface to avoid confusion: 
                <code>level&lt;level&gt;start, level&lt;level&gt;end, level&lt;level&gt;msg, level&lt;level&gt;xec, 
                level&lt;level&gt;onact, level&lt;level&gt;offact</code></li>
            <li>Standard attributes <a href="#alias">alias</a>, <a href="#comment">comment</a>, <a
                    href="#event-on-update-reading">event-on-update-reading</a>, <a
                    href="#event-on-change-reading">event-on-change-reading</a>, <a href="#room"
                    >room</a>, <a href="#eventMap">eventMap</a>, <a href="#loglevel">loglevel</a>,
                    <a href="#webCmd">webCmd</a></li>
        </ul>
=end html
=begin html_DE

<a name="Alarm"></a>
<h3>Alarm</h3>

=end html_DE
=cut
