##############################################
##############################################
# CUL HomeMatic handler
# $Id: 10_CUL_HM.pm 8683 2015-06-03 21:26:40Z martinp876 $

package main;

use strict;
use warnings;
use HMConfig;

# ========================import constants=====================================

my $culHmModel            =\%HMConfig::culHmModel;
my $culHmRegDefShLg       =\%HMConfig::culHmRegDefShLg;
my $culHmRegDefine        =\%HMConfig::culHmRegDefine;
my $culHmRegGeneral       =\%HMConfig::culHmRegGeneral;
my $culHmRegType          =\%HMConfig::culHmRegType;
my $culHmRegModel         =\%HMConfig::culHmRegModel;
my $culHmRegChan          =\%HMConfig::culHmRegChan;
my $culHmGlobalGets       =\%HMConfig::culHmGlobalGets;
my $culHmVrtGets          =\%HMConfig::culHmVrtGets;
my $culHmSubTypeGets      =\%HMConfig::culHmSubTypeGets;
my $culHmModelGets        =\%HMConfig::culHmModelGets;
my $culHmGlobalSetsDevice =\%HMConfig::culHmGlobalSetsDevice;
my $culHmSubTypeDevSets   =\%HMConfig::culHmSubTypeDevSets;
my $culHmGlobalSetsChn    =\%HMConfig::culHmGlobalSetsChn;
my $culHmGlobalSets       =\%HMConfig::culHmGlobalSets;
my $culHmGlobalSetsVrtDev =\%HMConfig::culHmGlobalSetsVrtDev;
my $culHmSubTypeSets      =\%HMConfig::culHmSubTypeSets;
my $culHmModelSets        =\%HMConfig::culHmModelSets;
my $culHmChanSets         =\%HMConfig::culHmChanSets;
my $culHmFunctSets        =\%HMConfig::culHmFunctSets;
my $culHmBits             =\%HMConfig::culHmBits;
my $culHmCmdFlags         =\@HMConfig::culHmCmdFlags;
my $K_actDetID            ="000000";

############################################################

sub CUL_HM_Initialize($);
sub CUL_HM_reqStatus($);
sub CUL_HM_autoReadConfig();
sub CUL_HM_updateConfig($);
sub CUL_HM_Define($$);
sub CUL_HM_Undef($$);
sub CUL_HM_Rename($$$);
sub CUL_HM_Attr(@);
sub CUL_HM_Parse($$);
sub CUL_HM_parseCommon(@);
sub CUL_HM_qAutoRead($$);
sub CUL_HM_Get($@);
sub CUL_HM_Set($@);
sub CUL_HM_valvePosUpdt(@);
sub CUL_HM_infoUpdtDevData($$$);
sub CUL_HM_infoUpdtChanData(@);
sub CUL_HM_getConfig($);
sub CUL_HM_SndCmd($$);
sub CUL_HM_responseSetup($$);
sub CUL_HM_eventP($$);
sub CUL_HM_protState($$);
sub CUL_HM_respPendRm($);
sub CUL_HM_respPendTout($);
sub CUL_HM_respPendToutProlong($);
sub CUL_HM_PushCmdStack($$);
sub CUL_HM_ProcessCmdStack($);
sub CUL_HM_pushConfig($$$$$$$$@);
sub CUL_HM_ID2PeerList ($$$);
sub CUL_HM_peerChId($$);
sub CUL_HM_peerChName($$);
sub CUL_HM_getMId($);
sub CUL_HM_getRxType($);
sub CUL_HM_getFlag($);
sub CUL_HM_getAssChnIds($);
sub CUL_HM_h2IoId($);
sub CUL_HM_IoId($);
sub CUL_HM_hash2Id($);
sub CUL_HM_hash2Name($);
sub CUL_HM_name2Hash($);
sub CUL_HM_name2Id(@);
sub CUL_HM_id2Name($);
sub CUL_HM_id2Hash($);
sub CUL_HM_getDeviceHash($);
sub CUL_HM_getDeviceName($);
sub CUL_HM_DumpProtocol($$@);
sub CUL_HM_getRegFromStore($$$$@);
sub CUL_HM_updtRegDisp($$$);
sub CUL_HM_encodeTime8($);
sub CUL_HM_decodeTime8($);
sub CUL_HM_encodeTime16($);
sub CUL_HM_convTemp($);
sub CUL_HM_decodeTime16($);
sub CUL_HM_secSince2000();
sub CUL_HM_getChnLvl($);
sub CUL_HM_initRegHash();
sub CUL_HM_fltCvT($);
sub CUL_HM_CvTflt($);
sub CUL_HM_getRegN($$@);
sub CUL_HM_4DisText($);
sub CUL_HM_TCtempReadings($);
sub CUL_HM_repReadings($);
sub CUL_HM_dimLog($);
sub CUL_HM_ActGetCreateHash();
sub CUL_HM_time2sec($);
sub CUL_HM_ActAdd($$);
sub CUL_HM_ActDel($);
sub CUL_HM_ActCheck($);
sub CUL_HM_UpdtReadBulk(@);
sub CUL_HM_UpdtReadSingle(@);
sub CUL_HM_setAttrIfCh($$$$);
sub CUL_HM_noDup(@);        #return list with no duplicates
sub CUL_HM_noDupInString($);#return string with no duplicates, comma separated
sub CUL_HM_storeRssi(@);
sub CUL_HM_qStateUpdatIfEnab($@);
sub CUL_HM_getAttrInt($@);
sub CUL_HM_appFromQ($$);
sub CUL_HM_autoReadReady($);
sub CUL_HM_calcDisWm($$$);

# ----------------modul globals-----------------------
my $respRemoved; # used to control trigger of stack processing
my $IOpoll     = 0.2;# poll speed to scan IO device out of order

my $maxPendCmds = 10;  #number of parallel requests
my @evtEt = ();    #readings for entities. Format hash:trigger:reading:value
my $evtDly = 0;    # ugly switch to delay set readings if in parser - actually not our job, but fhem.pl refuses
                 # need to take care that ACK is first
#+++++++++++++++++ startup, init, definition+++++++++++++++++++++++++++++++++++
sub CUL_HM_Initialize($) {
  my ($hash) = @_;

  $hash->{Match}     = "^A....................";
  $hash->{DefFn}     = "CUL_HM_Define";
  $hash->{UndefFn}   = "CUL_HM_Undef";
  $hash->{ParseFn}   = "CUL_HM_Parse";
  $hash->{SetFn}     = "CUL_HM_Set";
  $hash->{GetFn}     = "CUL_HM_Get";
  $hash->{RenameFn}  = "CUL_HM_Rename";
  $hash->{AttrFn}    = "CUL_HM_Attr";
  $hash->{NotifyFn}  = "CUL_HM_Notify";

  $hash->{Attr}{dev} =  "ignore:1,0 dummy:1,0 "  # -- device only attributes
                       ."IODev IOList IOgrp "        
                       ."hmProtocolEvents:0_off,1_dump,2_dumpFull,3_dumpTrigger "
                       ."rssiLog:1,0 "         # enable writing RSSI to Readings (device only)
                       ."actCycle "            # also for action detector                       
                       ;
  $hash->{Attr}{devPhy} =    # -- physical device only attributes
                        "serialNr firmware .stc .devInfo "
                       ."actStatus "
                       ."autoReadReg:0_off,1_restart,2_pon-restart,3_onChange,4_reqStatus,5_readMissing,8_stateOnly "
                       ."burstAccess:0_off,1_auto "
                       ."msgRepeat "
                       ."hmProtocolEvents:0_off,1_dump,2_dumpFull,3_dumpTrigger "
                       ."aesCommReq:1,0 "      # IO will request AES if 
                       ;
  $hash->{Attr}{chn} =  "repPeers "            # -- channel only attributes
                       ."peerIDs "
                       ."tempListTmpl "
                       ."levelRange levelMap ";
  $hash->{Attr}{glb} =  "do_not_notify:1,0 showtime:1,0 "
                       ."rawToReadable unit "#"KFM-Sensor" only
                       ."expert:0_off,1_on,2_full "
                       ."param "
                       ."actAutoTry:0_off,1_on "
                       ;
  $hash->{AttrList}  =  
                        $hash->{Attr}{glb}
                       .$hash->{Attr}{dev}
                       .$hash->{Attr}{devPhy}
                       .$hash->{Attr}{chn}
                       .$readingFnAttributes
                       ;
                       
  my @modellist;
  foreach my $model (keys %{$culHmModel}){
    push @modellist,$culHmModel->{$model}{name};
  }
  $hash->{AttrList}  .= " model:"  .join(",", sort @modellist);
  $hash->{AttrList}  .= " subType:".join(",",
               CUL_HM_noDup(map { $culHmModel->{$_}{st} } keys %{$culHmModel}));

  $hash->{prot}{rspPend} = 0;#count Pending responses
  my @statQArr     = ();
  my @statQWuArr   = ();
  my @confQArr     = ();
  my @confQWuArr   = ();
  my @confCheckArr = ();
  my @confUpdt     = ();
  $hash->{helper}{qReqStat}     = \@statQArr;
  $hash->{helper}{qReqStatWu}   = \@statQWuArr;
  $hash->{helper}{qReqConf}     = \@confQArr;
  $hash->{helper}{qReqConfWu}   = \@confQWuArr;
  $hash->{helper}{confCheckArr} = \@confCheckArr;
  $hash->{helper}{confUpdt}     = \@confUpdt;
  $hash->{helper}{cfgCmpl}{init}= 1;# mark entities with complete config
  #statistics
  $hash->{stat}{s}{dummy}=0;
  $hash->{stat}{r}{dummy}=0;
  RemoveInternalTimer("StatCntRfresh");
  InternalTimer(gettimeofday()+3600*20,"CUL_HM_statCntRfresh","StatCntRfresh", 0);

  CUL_HM_initRegHash();
  $hash->{hmIoMaxDly}     = 60;# poll timeout - stop poll and discard
  $hash->{hmAutoReadScan} = 4; # delay autoConf readings
  $hash->{helper}{hmManualOper} = 0;# default automode
  
}

sub CUL_HM_updateConfig($){
  # this routine is called 5 sec after the last define of a restart
  # this gives FHEM sufficient time to fill in attributes
  # it will also be called after each manual definition
  # Purpose is to parse attributes and read config
  RemoveInternalTimer("updateConfig");
  if (!$init_done){
    InternalTimer(gettimeofday()+5,"CUL_HM_updateConfig", "updateConfig", 0);
    return;
  }

  foreach my $name (@{$modules{CUL_HM}{helper}{updtCfgLst}}){
    my $hash = $defs{$name};
    next if (!$hash->{DEF}); # likely renamed
    
    my $id = $hash->{DEF};
    my $nAttr = $modules{CUL_HM}{helper}{hmManualOper};# no update for attr
    
    if ($id eq $K_actDetID){# if action detector
      $attr{$name}{"event-on-change-reading"} = 
                AttrVal($name, "event-on-change-reading", ".*")
                if(!$nAttr);
      $attr{$name}{model} = "ActionDetector";
      delete $hash->{helper}{role};
      delete $attr{$name}{$_}
            foreach ( "autoReadReg","actCycle","actStatus","burstAccess","serialNr"
                     ,"IODev","IOList","IOgrp","hmProtocolEvents","rssiLog"); 
      #$hash->{helper}{role}{vrt} = 1;
      #$hash->{helper}{role}{dev} = 1;
      next;
    }
    CUL_HM_ID2PeerList($name,"",1); # update peerList out of peerIDs

    my $chn = substr($id."00",6,2);
    my $st  = CUL_HM_Get($hash,$name,"param","subType");
    my $md  = CUL_HM_Get($hash,$name,"param","model");

    $hash->{helper}{role}{prs} = 1 if(CUL_HM_Set($hash,$name,"?") =~ m /press/ && $st ne "virtual");
    foreach my $rName ("D-firmware","D-serialNr",".D-devInfo",".D-stc"){
      # move certain attributes to readings for future handling
      my $aName = $rName;
      $aName =~ s/D-//;
      my $aVal = AttrVal($name,$aName,undef);      
      CUL_HM_UpdtReadSingle($hash,$rName,$aVal,0)
           if (!defined ReadingsVal($name,$rName,undef));
    }
    if    ($md =~ /(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/){
      $hash->{helper}{role}{chn} = 1 if (length($id) == 6); #tc special
    }
    elsif ($md =~ m/HM-CC-RT-DN/){
      $hash->{helper}{shRegR}{"07"} = "00" if ($chn eq "04");# shadowReg List 7 read from CH 0
      $hash->{helper}{shRegW}{"07"} = "04" if ($chn eq "00");# shadowReg List 7 write to CH 4
    }
    elsif ($md =~ m/HM-TC-IT-WM-W-EU/){
      $hash->{helper}{shRegR}{"07"} = "00" if ($chn eq "02");# shadowReg List 7 read from CH 0
      $hash->{helper}{shRegW}{"07"} = "02" if ($chn eq "00");# shadowReg List 7 write to CH 4
    }
    elsif ($md =~ m/(HM-CC-VD|ROTO_ZEL-STG-RM-FSA)/){
      $hash->{helper}{oldDes} = "0";
    }
    elsif ($md =~ m/(HM-Dis-WM55)/){
      foreach my $t ("s","l"){
        if(!defined $hash->{helper}{dispi}{$t}{"l1"}{d}){# setup if one is missing
          $hash->{helper}{dispi}{$t}{"l$_"}{d}=1 foreach (1,2,3,4,5,6);
        }
      }
    }
    elsif ($st eq "dimmer"  ) {#setup virtual dimmer channels
      my $mId = CUL_HM_getMId($hash);
      #configure Dimmer virtual channel assotiation
      if ($hash->{helper}{role}{chn}){
        my $chn = (length($id) == 8)?substr($id,6,2):"01";
        my $devId = substr($id,0,6);
        if ($culHmModel->{$mId} && $culHmModel->{$mId}{chn} =~ m/Sw._V/){#virtual?
          my @chnPh = (grep{$_ =~ m/Sw:/ } split ',',$culHmModel->{$mId}{chn});
          @chnPh = split ':',$chnPh[0] if (@chnPh);
          my $chnPhyMax = $chnPh[2]?$chnPh[2]:1;         # max Phys channels
          my $chnPhy    = int(($chn-$chnPhyMax+1)/2);    # assotiated phy chan
          my $idPhy     = $devId.sprintf("%02X",$chnPhy);# ID assot phy chan
          my $pHash     = CUL_HM_id2Hash($idPhy);        # hash assot phy chan
          $idPhy        = $pHash->{DEF};                 # could be device!!!
          if ($pHash){
            $pHash->{helper}{vDim}{idPhy} = $idPhy;
            my $vHash = CUL_HM_id2Hash($devId.sprintf("%02X",$chnPhyMax+2*$chnPhy-1));
            if ($vHash){
              $pHash->{helper}{vDim}{idV2}  = $vHash->{DEF};
              $vHash->{helper}{vDim}{idPhy} = $idPhy;
            }
            else{
              delete $pHash->{helper}{vDim}{idV2};
            }
            $vHash = CUL_HM_id2Hash($devId.sprintf("%02X",$chnPhyMax+2*$chnPhy));
            if ($vHash){
              $pHash->{helper}{vDim}{idV3}  = $vHash->{DEF};
              $vHash->{helper}{vDim}{idPhy} = $idPhy;
            }
            else{
              delete $pHash->{helper}{vDim}{idV3};
            }
          }
        }
      }
    }
    elsif ($st eq "virtual" ) {#setup virtuals
      $hash->{helper}{role}{vrt} = 1;
      if($hash->{helper}{role}{dev} && $md eq "CCU-FHEM"){
        CUL_HM_UpdtCentral($name);
      }
      if (   $hash->{helper}{fkt} 
          && $hash->{helper}{fkt} =~ m/^(vdCtrl|virtThSens)$/){
        my $vId = substr($id."01",0,8);
        $hash->{helper}{virtTC} = "00";
        $hash->{helper}{vd}{msgRed}= 0 if(!defined $hash->{helper}{vd}{msgRed});
        if(!defined $hash->{helper}{vd}{next}){
          ($hash->{helper}{vd}{msgCnt},$hash->{helper}{vd}{next}) = 
                    split(";",ReadingsVal($name,".next","0;".gettimeofday()));
          $hash->{helper}{vd}{idl} = 0;
          $hash->{helper}{vd}{idh} = 0;
        }
        my $d =ReadingsVal($name,"valvePosTC","");
        $d =~ s/ %//;
        CUL_HM_Set($hash,$name,"valvePos",$d);
        CUL_HM_Set($hash,$name,"virtTemp",ReadingsVal($name,"temperature",""));
        CUL_HM_Set($hash,$name,"virtHum" ,ReadingsVal($name,"humidity",""));
        CUL_HM_UpdtReadSingle($hash,"valveCtrl","restart",1) if (ReadingsVal($name,"valvePosTC",""));
        RemoveInternalTimer("valvePos:$vId");
        RemoveInternalTimer("valveTmr:$vId");
        InternalTimer($hash->{helper}{vd}{next}
                     ,"CUL_HM_valvePosUpdt","valvePos:$vId",0);
        # delete - virtuals dont have regs 
        delete $attr{$name}{$_}
            foreach ("autoReadReg","actCycle","actStatus","burstAccess","serialNr"); 
      }
    }
    elsif ($st eq "sensRain") {
      $hash->{helper}{lastRain} = ReadingsTimestamp($name,"state","")
            if (ReadingsVal($name,"state","") eq "rain");
    }
    next if ($nAttr);# stop if default setting if attributes is not desired

    my $actCycle = AttrVal($name,"actCycle",undef);
    CUL_HM_ActAdd($id,$actCycle) if ($actCycle );#add 2 ActionDetect?
    # --- set default attributes if missing ---
    if ($hash->{helper}{role}{dev}){
      if( $st ne "virtual"){
        $attr{$name}{expert}     = AttrVal($name,"expert"     ,"2_full");
        $attr{$name}{autoReadReg}= AttrVal($name,"autoReadReg","4_reqStatus");
        CUL_HM_hmInitMsg($hash);
      }
      if (CUL_HM_getRxType($hash)&0x02){#burst dev must restrict retries!
        $attr{$name}{msgRepeat} = 1 if (!$attr{$name}{msgRepeat});
      }
    }
    CUL_HM_Attr("attr",$name,"expert",$attr{$name}{expert}) 
          if ($attr{$name}{expert});#need update after readings are available
    if ($chn eq "03" && 
        $md =~ /(-TC|ROTO_ZEL-STG-RM-FWT|HM-CC-RT-DN)/){
      $attr{$name}{stateFormat} = "last:trigLast";
    }
    foreach(keys %{$attr{$name}}){
      delete $attr{$name}{$_} if(CUL_HM_AttrCheck($name,$_));
    }

    # -+-+-+-+-+ add default web-commands
    my $webCmd;
    $webCmd  = AttrVal($name,"webCmd",undef);
    if(!defined $webCmd){
      if    ($st eq "virtual"      ){
        if   ($hash->{helper}{fkt} && $hash->{helper}{fkt} eq "sdLead")    {$webCmd="teamCall:alarmOn:alarmOff";}
        elsif($hash->{helper}{fkt} && $hash->{helper}{fkt} eq "vdCtrl")    {$webCmd="valvePos";}
        elsif($hash->{helper}{fkt} && $hash->{helper}{fkt} eq "virtThSens"){$webCmd="virtTemp:virtHum";}
        elsif(!$hash->{helper}{role}{dev})                                 {$webCmd="press short:press long";}
        elsif($md =~ m/^virtual_/)                                         {$webCmd="virtual";}
        elsif($md eq "CCU-FHEM")                                           {$webCmd="virtual:update";}

      }
      elsif((!$hash->{helper}{role}{chn} &&
               $md !~ m/(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/)
            ||$st eq "repeater"
            ||$md =~ m/(HM-CC-VD|ROTO_ZEL-STG-RM-FSA)/ ){$webCmd="getConfig:clear msgEvents";
        if ($md =~ m/HM-CC-RT-DN/)                      {$webCmd.=":burstXmit";}
      }
      elsif($st eq "blindActuator"){
        if ($hash->{helper}{role}{chn}){$webCmd="statusRequest:toggleDir:on:off:up:down:stop";}
        else{                           $webCmd="statusRequest:getConfig:clear msgEvents";}
      }
      elsif($st eq "dimmer"       ){
        if ($hash->{helper}{role}{chn}){$webCmd="statusRequest:toggle:on:off:up:down";}
        else{                           $webCmd="statusRequest:getConfig:clear msgEvents";}
      }
      elsif($st eq "switch"       ){
        if ($hash->{helper}{role}{chn}){$webCmd="statusRequest:toggle:on:off";}
        else{                           $webCmd="statusRequest:getConfig:clear msgEvents";}
      }
      elsif($st eq "smokeDetector"){   $webCmd="statusRequest";
        if ($hash->{helper}{fkt} eq "sdLead"){
                                        $webCmd.=":teamCall:alarmOn:alarmOff";}
      }
      elsif($st eq "keyMatic"     ){   $webCmd="lock:inhibit on:inhibit off";
      }
      elsif($md eq "HM-OU-CFM-PL" ){   $webCmd="press short:press long"
                                          .($chn eq "02"?":playTone replay":"");
      }

      if ($webCmd){
        my $eventMap  = AttrVal($name,"eventMap",undef);

        my @wc;
        push @wc,ReplaceEventMap($name, $_, 1) foreach (split ":",$webCmd);
        $webCmd = join ":",@wc;
      }
    }
    $attr{$name}{webCmd} = $webCmd if ($webCmd);

    CUL_HM_qStateUpdatIfEnab($name);
    next if (0 == (0x07 & CUL_HM_getAttrInt($name,"autoReadReg")));
    if(CUL_HM_peerUsed($name) == 2){
      CUL_HM_qAutoRead($name,1);
    }
    else{
      foreach(CUL_HM_reglUsed($name)){
        next if (!$_);
        if(ReadingsVal($name,$_,"x") !~ m/00:00/){
          CUL_HM_qAutoRead($name,1);
          last;
        }
      }
    }
    #remove invalid attributes
    if (!$hash->{helper}{role}{dev}){
      my @l = split(" ",$modules{CUL_HM}{Attr}{dev});
      map {$_ =~ s/\:.*//} @l; 
      foreach (@l){
        delete $attr{$name}{$_} if (defined $attr{$name}{$_});
      }
    }
    if (!$hash->{helper}{role}{chn}){
      my @l = split(" ",$modules{CUL_HM}{Attr}{chn});
      map {$_ =~ s/\:.*//} @l; 
      foreach (@l){
        delete $attr{$name}{$_} if (defined $attr{$name}{$_});
      }
    }
    CUL_HM_complConfig($name);
  }
  delete $modules{CUL_HM}{helper}{updtCfgLst};
}
sub CUL_HM_Define($$) {##############################
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $HMid = uc($a[2]);

  return "wrong syntax: define <name> CUL_HM 6-digit-hex-code [Raw-Message]"
        if(!(int(@a)==3 || int(@a)==4) || $HMid !~ m/^[A-F0-9]{6,8}$/i);
  return  "HMid DEF already used by " . CUL_HM_id2Name($HMid)
        if ($modules{CUL_HM}{defptr}{$HMid});
  my $name = $hash->{NAME};
  if(length($HMid) == 8) {# define a channel
    my $devHmId = substr($HMid, 0, 6);
    my $chn = substr($HMid, 6, 2);
    my $devHash = $modules{CUL_HM}{defptr}{$devHmId};
    return "please define a device with hmId:".$devHmId." first" if(!$devHash);

    my $devName = $devHash->{NAME};
    $hash->{device} = $devName;          #readable ref to device name
    $hash->{chanNo} = $chn;              #readable ref to Channel
    $devHash->{"channel_$chn"} = $name;  #reference in device as well
    $attr{$name}{model} = AttrVal($devName, "model", undef);
    $hash->{helper}{role}{chn}=1;
    if($chn eq "01"){
      $attr{$name}{peerIDs} = AttrVal($devName, "peerIDs", "");
      $hash->{READINGS}{peerList}{VAL} = ReadingsVal($devName,"peerList","");
      $hash->{peerList} = $devHash->{peerList} if($devHash->{peerList});

      delete $devHash->{helper}{role}{chn};#device no longer
      delete $devHash->{peerList};
      delete $devHash->{READINGS}{peerList};
      delete $attr{$devName}{peerIDs};
    }
  }
  else{# define a device
    $hash->{helper}{role}{dev}   = 1;
    $hash->{helper}{role}{chn}   = 1;# take role of chn 01 until it is defined
    $hash->{helper}{q}{qReqConf} = ""; # queue autoConfig requests 
    $hash->{helper}{q}{qReqStat} = ""; # queue statusRequest for this device
    $hash->{helper}{mRssi}{mNo}  = "";
    CUL_HM_prtInit ($hash);
    $hash->{helper}{io}{vccu} = "";
    $hash->{helper}{io}{prefIO} = "";
    CUL_HM_assignIO($hash)if (!$init_done && $HMid ne "000000");
  }
  $modules{CUL_HM}{defptr}{$HMid} = $hash;

  #- - - - create auto-update - - - - - -
  CUL_HM_ActGetCreateHash() if($HMid eq '000000');#startTimer
  $hash->{DEF} = $HMid;
  CUL_HM_Parse($hash, $a[3]) if(int(@a) == 4);

  CUL_HM_queueUpdtCfg($name);
  return undef;
}
sub CUL_HM_Undef($$) {###############################
  my ($hash, $name) = @_;
  my $devName = $hash->{device};
  my $HMid = $hash->{DEF};
  CUL_HM_unQEntity($name,"qReqConf");
  CUL_HM_unQEntity($name,"qReqStat");
  CUL_HM_complConfigTestRm($name);
  my $chn = substr($HMid,6,2);
  if ($chn){# delete a channel
    my $devHash = $defs{$devName};
    delete $devHash->{"channel_$chn"} if ($devName);
    $devHash->{helper}{role}{chn}=1 if($chn eq "01");# return chan 01 role
  }
  else{# delete a device
     CommandDelete(undef,$hash->{$_}) foreach (grep(/^channel_/,keys %{$hash}));
  }
  delete($modules{CUL_HM}{defptr}{$HMid});
  return undef;
}
sub CUL_HM_Rename($$$) {#############################
  my ($name, $oldName) = @_;
  my $HMid = CUL_HM_name2Id($name);
  my $hash = $defs{$name};
  if (!$hash->{helper}{role}{dev}){# we are channel, inform the device
    $hash->{chanNo} = substr($HMid,6,2);
    my $devHash = CUL_HM_id2Hash(substr($HMid,0,6));
    $hash->{device} = $devHash->{NAME};
    $devHash->{"channel_".$hash->{chanNo}} = $name;
  }
  else{# we are a device - inform channels if exist
    foreach (grep (/^channel_/, keys%{$hash})){
      my $chnHash = $defs{$hash->{$_}};
      $chnHash->{device} = $name;
    }
    CUL_HM_UpdtCentral($name) if (AttrVal($name, "model", "") eq "CCU-FHEM");
  }
  if ($hash->{helper}{role}{chn}){
    my $HMidCh = substr($HMid."01",0,8);
    foreach my $pId (keys %{$modules{CUL_HM}{defptr}}){
      my $pH = $modules{CUL_HM}{defptr}{$pId};
      my $pN = $pH->{NAME};
      my $pPeers = AttrVal($pN, "peerIDs", "");
      if ($pPeers =~ m/$HMidCh/){
        CUL_HM_ID2PeerList ($pN,"x",0);
        foreach my $pR (grep /-$oldName-/,keys%{$pH->{READINGS}}){
          my $pRn = $pR;
          $pRn =~ s/$oldName/$name/;
          $pH->{READINGS}{$pRn}{VAL} = $pH->{READINGS}{$pR}{VAL};
          $pH->{READINGS}{$pRn}{TIME} = $pH->{READINGS}{$pR}{TIME};
          delete $pH->{READINGS}{$pR};
        }
      }
    }
  }
  return;
}
sub CUL_HM_Attr(@) {#################################
  my ($cmd,$name, $attrName,$attrVal) = @_;
  my $chk = CUL_HM_AttrCheck($name, $attrName);
  return $chk if ($chk);
  my @hashL;
  my $updtReq = 0;
  my $hash = CUL_HM_name2Hash($name);
  if   ($attrName eq "expert"){#[0,1,2]
    $attr{$name}{$attrName} = $attrVal;
    my $eHash = $defs{$name};
    foreach my $chId (CUL_HM_getAssChnIds($name)){
      my $cHash = CUL_HM_id2Hash($chId);
      push(@hashL,$cHash) if ($eHash ne $cHash);
    }
    push(@hashL,$eHash);
    foreach my $hash (@hashL){
      my $exLvl = CUL_HM_getAttrInt($hash->{NAME},"expert");
      if    ($exLvl eq "0"){# off
        foreach my $rdEntry (grep /^RegL_/,keys %{$hash->{READINGS}}){
          $hash->{READINGS}{".".$rdEntry} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
        }
        foreach my $rdEntry (grep /^R-/   ,keys %{$hash->{READINGS}}){
           my $reg = $rdEntry;
            $reg =~ s/.*-//;
          next if(!$culHmRegDefine->{$reg} || $culHmRegDefine->{$reg}{d} eq '1');
          $hash->{READINGS}{".".$rdEntry} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
        }
      }
      elsif ($exLvl eq "1"){# on: Only register values, no raw data
        # move register to visible if available
        foreach my $rdEntry (grep /^RegL_/,keys %{$hash->{READINGS}}){
          $hash->{READINGS}{".".$rdEntry} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
        }
        foreach my $rdEntry (grep /^\.R-/ ,keys %{$hash->{READINGS}}){
          $hash->{READINGS}{substr($rdEntry,1)} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
        }
      }
      elsif ($exLvl eq "2"){# full - incl raw data
        foreach my $rdEntry (grep /^\.R(egL_|-)/,keys %{$hash->{READINGS}}){
          $hash->{READINGS}{substr($rdEntry,1)} = $hash->{READINGS}{$rdEntry};
          delete $hash->{READINGS}{$rdEntry};
        }
      }
      else{;
      }
    }
  }
  elsif($attrName eq "actCycle"){#"000:00" or 'off'
    if ($cmd eq "set"){
      if (CUL_HM_name2Id($name) eq $K_actDetID){
        return "$attrName must be higher then 30, $attrVal not allowed"
              if ($attrVal < 30);
      }
      else{
        return "attribut not allowed for channels"
                      if (!$hash->{helper}{role}{dev});
      }
    }
    $updtReq = 1;
  }
  elsif($attrName eq "param"){
    my $md  = CUL_HM_Get($hash,$name,"param","model");
    my $st  = CUL_HM_Get($hash,$name,"param","subType");
    my $chn = substr(CUL_HM_hash2Id($hash),6,2);
    if ($md eq "HM-Sen-RD-O" && $chn eq "02"){
      delete $hash->{helper}{param};
      my @param = split ",",$attrVal;
      foreach (@param){
        if    ($_ eq "offAtPon"){$hash->{helper}{param}{offAtPon} = 1}
        elsif ($_ eq "onAtRain"){$hash->{helper}{param}{onAtRain} = 1}
        else {return "param $_ unknown, use offAtPon or onAtRain";}
      }
    }
    elsif ($st eq "virtual"){
      if ($cmd eq "set"){
        if ($attrVal eq "noOnOff"){# no action
        }
        elsif ($attrVal =~ m/msgReduce/){# send only each other message
          my (undef,$rCnt) = split(":",$attrVal,2);
          $rCnt=(defined $rCnt && $rCnt =~ m/^\d$/)?$rCnt:1;
          $hash->{helper}{vd}{msgRed}=$rCnt;
        }
        else{
          return "attribut param $attrVal not valid for $name";
        }
      }
      else{
        delete $hash->{helper}{vd}{msgRed};
      }
    }
#    elsif ($st eq "blindActuator"){
    else{
      if ($cmd eq "set"){
        if ($attrVal eq "levelInverse"){# no action
        }
        else{
          return "attribut param $attrVal not valid for $name";
        }
      }
      else{
        delete $hash->{helper}{vd}{msgRed};
      }
    }
#    else{
#      return "attribut param not valid for $name";
#    }
  }
  elsif($attrName eq "peerIDs"){
    if ($cmd eq "set"){
      return "$attrName not usable for devices" if(!$hash->{helper}{role}{chn});
      my $id = $hash->{DEF};
      if ($id ne $K_actDetID && $attrVal){# if not action detector
        my @ids = grep /......../,split(",",$attrVal);
        $attr{$name}{peerIDs} = join",",@ids if (@ids);
        CUL_HM_ID2PeerList($name,"",1);       # update peerList out of peerIDs
      }
    }
    else{# delete
      delete $hash->{peerList};
      delete $hash->{READINGS}{peerList};
    }
  }
  elsif($attrName eq "msgRepeat"){
    if ($cmd eq "set"){
      return "$attrName not usable for channels" if(!$hash->{helper}{role}{dev});#only for device
      return "value $attrVal ignored, must be an integer" if ($attrVal !~ m/^(\d+)$/);
    }
    return;
  }
  elsif($attrName eq "model" && $hash->{helper}{role}{dev}){
    delete $hash->{helper}{rxType}; # needs new calculation
    delete $hash->{helper}{mId};
    if ($attrVal eq "CCU-FHEM"){
      $attr{$name}{subType} = "virtual";
      $updtReq = 1;
      CUL_HM_UpdtCentral($name);
    }
    else{
      CUL_HM_hmInitMsg($hash) if ($init_done);
    }
    $attr{$name}{$attrName} = $attrVal if ($cmd eq "set");
  }
  elsif($attrName eq "subType"){
    $updtReq = 1;
  }
  elsif($attrName eq "aesCommReq" ){
    if ($cmd eq "set"){
      return "use $attrName only for device"        if (!$hash->{helper}{role}{dev});
      return "$attrName support 0 or 1 only"        if ($attrVal !~ m/[01]/);
      return "$attrName invalid for virtal devices" if ($hash->{role}{vrt});
      $attr{$name}{$attrName} = $attrVal;
    }
    else{
      delete $attr{$name}{$attrName};
    }
    CUL_HM_hmInitMsg($hash);
  }
  elsif($attrName eq "burstAccess"){
    if ($cmd eq "set"){
      return "use burstAccess only for device"             if (!$hash->{helper}{role}{dev});
      return $name." not a conditional burst model"        if (!CUL_HM_getRxType($hash) & 0x80);
      return "$attrVal not a valid option for burstAccess" if ($attrVal !~ m/^[01]/);
      if ($attrVal =~ m/^0/){$hash->{protCondBurst} = "forced_off";}
      else                  {$hash->{protCondBurst} = "unknown";}
    }
    else{                    $hash->{protCondBurst} = "forced_off";}
    delete $hash->{helper}{rxType}; # needs new calculation
  }
  elsif($attrName eq "IODev"){
    if ($cmd eq "set"){
      return "use $attrName only for device" if (!$hash->{helper}{role}{dev});
    }
  }
  elsif($attrName eq "IOList"){
    return "use $attrName only for ccu device" 
            if (!$hash->{helper}{role}{dev}
                || AttrVal($name,"model","CCU-FHEM") !~ "CCU-FHEM");
    if($cmd eq "set"){$attr{$name}{$attrName} = $attrVal;}
    else             {delete $attr{$name}{$attrName};}
    CUL_HM_UpdtCentral($name);
  }
  elsif($attrName eq "IOgrp" ){
    if ($cmd eq "set"){
      return "use $attrName only for devices" if (!$hash->{helper}{role}{dev});
      my ($ioCCU,$prefIO) = split(":",$attrVal,2);
      $hash->{helper}{io}{vccu}   = $ioCCU;
      if ($prefIO){
        my @prefIOA = split(",",$prefIO);
        $hash->{helper}{io}{prefIO} = \@prefIOA;
      }
      else{
        delete $hash->{helper}{io}{prefIO};
      }
    }
    else{
      $hash->{helper}{io}{vccu} = "";
      $hash->{helper}{io}{prefIO} = "";
    }
  }
  elsif($attrName eq "autoReadReg"){
    if ($cmd eq "set"){
      CUL_HM_complConfigTest($name)
        if (!CUL_HM_getAttrInt($name,"ignore"));;
    }
  }
  elsif($attrName eq "rssiLog" ){
    if ($cmd eq "set"){
      return "use $attrName only for device" if (!$hash->{helper}{role}{dev});
    }
  }
  elsif($attrName eq "levelRange" ){
    if ($cmd eq "set"){
      return "use $attrName only for dimmer" if (CUL_HM_Get($defs{$name},$name,"param","subType") ne "dimmer");
      my ($min,$max) = split (",",$attrVal);
      return "use format min,max" if (!defined $max);
      return "min:$min must be between 0 and 100" if ($min<0 || $min >100);
      return "max:$max must be between 0 and 100" if ($max<0 || $max >100);
      return "min:$min mit be lower then max:$max" if ($min >= $max);
    }
  }
  elsif($attrName eq "levelMap" ){
    if ($cmd eq "set"){
      return "use $attrName only for channels" if (!$hash->{helper}{role}{chn});
      delete $hash->{helper}{lm};
      foreach (split":",$attrVal){
        my ($val,$vNm) = split"=",$_;
        if ($val !~ m/^\d*$/){
          delete $hash->{helper}{lm};
          return "$val is not numeric";
        }
        $hash->{helper}{lm}{$val} = $vNm;
      }
    }
    else{
      delete $hash->{helper}{lm};
    }
  }
  elsif($attrName eq "actAutoTry" ){
    if ($cmd eq "set"){
      return "$attrName only usable for ActionDetector" if(CUL_HM_hash2Id($hash) ne "000000");#only for device
    }
  }
  
  CUL_HM_queueUpdtCfg($name) if ($updtReq);
  return;
}
sub CUL_HM_AttrCheck(@) {############################
  #verify if attr is applicable
  my ($name, $attrName) = @_;
  return undef if (!$init_done); # we cannot determine if attributes are missing
  if ($defs{$name}{helper}{role}{vrt}){
    return " $attrName illegal for virtual devices"
      if ($modules{CUL_HM}{Attr}{devPhy} =~ m /\b$attrName\b/);
  }
  if (!$defs{$name}{helper}{role}{chn}){
    return " $attrName only valid for channels"
      if ($modules{CUL_HM}{Attr}{chn} =~ m /\b$attrName\b/);
  }
  if (!$defs{$name}{helper}{role}{dev}){
    return " $attrName only valid for devices"
      if (($modules{CUL_HM}{Attr}{dev}.$modules{CUL_HM}{Attr}{devPhy}) =~ m /\b$attrName\b/);
  }
  if ($defs{$name}{helper}{role}{vrt}){
    return " $attrName only valid for physical devices"
      if ($modules{CUL_HM}{Attr}{devPhy} =~ m /\b$attrName\b/);
  }
  return undef;
}
sub CUL_HM_prtInit($){ #setup protocol variables after define
  my ($hash)=@_;
  $hash->{helper}{prt}{sProc} = 0; # stack not being processed by now
  $hash->{helper}{prt}{bErr} = 0;
}
sub CUL_HM_hmInitMsg($){ #define device init msg for HMLAN
  #message to be send to HMLAN/USB to define device communication defails
  #bit-usage is widely unknown. 
  #p[1]: 00000001 = request AES
  #p[1]: 00000010 = data pending - autosend wakeup and lazyConfig
  #                   if device send data
  #p[2]: is this the number of the AES key to be used? 
  my ($hash)=@_;
  my $rxt = CUL_HM_getRxType($hash);
  my $id = CUL_HM_hash2Id($hash);
  my @p;
  if ($hash->{helper}{role}{vrt}){;}                     #virtual channels should not be assigned
  elsif(!($rxt & ~0x04)) {@p = ("$id","00","01","FE1F");}#config only
  elsif(  $rxt &  0x10)  {@p = ("$id","00","01","1E");  }#lazyConfig (01,00,1E also possible?)
  else                   {@p = ("$id","00","01","00");  }
# else                   {@p = ("$id","00","01","1E");  }
  if (AttrVal($hash->{NAME},"aesCommReq",0)){
    $p[1] = sprintf("%02X",(hex($p[1]) + 1));
    $p[3] = ($p[3]eq "")?"1E":$p[3];
  }
  $hash->{helper}{io}{newChn} = "";
  $hash->{helper}{io}{rxt} = (($rxt & 0x18)            #wakeup || #lazyConfig
                             && AttrVal($hash->{NAME},"model",0) ne "HM-WDS100-C6-O") #Todo - not completely clear how it works
                                 ?2:0;
  $hash->{helper}{io}{p} = \@p;
  CUL_HM_hmInitMsgUpdt($hash);
}
sub CUL_HM_hmInitMsgUpdt($){ #update device init msg for HMLAN
  my ($hash)=@_;
  return if (  $hash->{helper}{role}{vrt}
             ||!defined $hash->{helper}{io}{p});
  my $oldChn = $hash->{helper}{io}{newChn};
  my @p = @{$hash->{helper}{io}{p}};
  # General todo
  #  $p[1] |= 2; need to be set if data is pending for a wakeup device. 
  # it will force HMLAN to send A112 (have data). HMLAN will return 
  # status "81" ACK if the device answers the A112 - FHEM should start sending Data by then
  # 
  if($hash->{helper}{prt}{sProc}){
    $p[1] = sprintf("%02X",hex($p[1]) | $hash->{helper}{io}{rxt});
  }
#  else{
#    $p[1] = sprintf("%02X",hex($p[1]) & 0xFD);# remove this Bit if no more data to send
#                                              # otherwise could cause continous send (e.g. from SC)
#  }
  $hash->{helper}{io}{newChn} = '+'.join(",",@p);
  if ((  $hash->{helper}{io}{newChn} ne $oldChn)
      && $hash->{IODev}
      && $hash->{IODev}->{TYPE}
      && $hash->{IODev}->{TYPE} eq "HMLAN"){
    IOWrite($hash, "", "init:$p[0]");
  }
}

sub CUL_HM_Notify(@){#################################
  my ($ntfy, $dev) = @_;
  return "" if ($dev->{NAME} ne "global");

  my $events = deviceEvents($dev, AttrVal($ntfy->{NAME}, "addStateEvent", 0));
  return if(!$events); # Some previous notify deleted the array.
  return "" if (grep !/INITIALIZED/,@{$events});
  delete $modules{CUL_HM}{NotifyFn};
  CUL_HM_updateConfig("startUp");
}

#+++++++++++++++++ msg receive, parsing++++++++++++++++++++++++++++++++++++++++
# translate level to readable
    my %lvlStr = ( md  =>{ "HM-SEC-WDS"      =>{"00"=>"dry"     ,"64"=>"damp"    ,"C8"=>"wet"        }
                          ,"HM-SEC-WDS-2"    =>{"00"=>"dry"     ,"64"=>"damp"    ,"C8"=>"wet"        }
                          ,"HM-CC-SCD"       =>{"00"=>"normal"  ,"64"=>"added"   ,"C8"=>"addedStrong"}
                          ,"HM-Sen-RD-O"     =>{"00"=>"dry"                      ,"C8"=>"rain"}
                          ,"HM-MOD-Em-8"     =>{"00"=>"closed"                   ,"C8"=>"open"}
                          ,"HM-WDS100-C6-O"  =>{"00"=>"quiet"                    ,"C8"=>"storm"}
                         }
                  ,mdCh=>{ "HM-Sen-RD-O01"   =>{"00"=>"dry"                      ,"C8"=>"rain"}
                          ,"HM-Sen-RD-O02"   =>{"00"=>"off"                      ,"C8"=>"on"}
                         }
                  ,st  =>{ "smokeDetector"   =>{"01"=>"no alarm","C7"=>"tone off","C8"=>"Smoke Alarm"}
                          ,"threeStateSensor"=>{"00"=>"closed"  ,"64"=>"tilted"  ,"C8"=>"open"}
                         }
                  );
                  
    my %disColor=(white=>0,red=>1,orange=>2,yellow=>3,green=>4,blue=>5);
    my %disIcon=( off =>0, on=>1, open=>2, closed=>3, error=>4, ok=>5
                 ,info=>6, newMsg=>7, serviceMsg=>8
                 ,sigGreen=>9, sigYellow=>10, sigRed=>11
                 ,ic12=>12, ic13=>13
                 ,noIcon=>99
                );
    my %disBtn=(  txt01_1=>0, txt01_2=>1, txt02_1=>2, txt02_2=>3, txt03_1=>4 
                , txt03_2=>5, txt04_1=>6, txt04_2=>7, txt05_1=>8, txt05_2=>9
                , txt06_1=>10,txt06_2=>11,txt07_1=>12,txt07_2=>13,txt08_1=>14
                , txt08_2=>15,txt09_1=>16,txt09_2=>17,txt10_1=>18,txt10_2=>19
                );
                 
                  
                  
                  
                  
sub CUL_HM_Parse($$) {#########################################################
  my ($iohash, $msgIn) = @_;
  
  my ($msg,$msgStat,$myRSSI,$msgIO) = split(":",$msgIn,4);
  # Msg format: Allnnffttssssssddddddpp...
  my ($t,$len,$mNo,$mFlg,$mTp,$src,$dst,$p) = unpack 'A1A2A2A2A2A6A6A*',$msg;
  my $mFlgH = hex($mFlg);
  return if (!$iohash ||
             ref($iohash) ne 'HASH'  ||
             $t ne 'A'  || 
             length($msg)<20);

  if ($modules{CUL_HM}{helper}{updating}){
    if ("done" eq CUL_HM_FWupdateSteps($msg)){
      my $shash = CUL_HM_id2Hash($src);
      my @e = CUL_HM_pushEvnts();
      $defs{$_}{".noDispatchVars"} = 1 foreach (grep !/^$shash->{NAME}$/,@e);
      return (@e,$shash->{NAME}); #return something to please dispatcher
    }
    else{
      return "";
    }
  }
 
  return "" if($msgStat && $msgStat eq 'NACK');# lowlevel error

  $p = "" if(!defined($p)); # generate some abreviations 
  my @mI = unpack '(A2)*',$p; # split message info to bytes
  my $mStp = $mI[0] ? $mI[0] : ""; #message subtype
  my $mTyp = $mTp.$mStp;           #message type/subtype
  
  # $shash will be replaced for multichannel commands
  my $shash  = CUL_HM_id2Hash($src); #sourcehash - will be modified to channel entity
  my $devH   = $shash;               # source device hash
  my $dstH   = CUL_HM_id2Hash($dst); # destination device hash
  my $id     = CUL_HM_h2IoId($iohash);
  my $ioName = $iohash->{NAME};
  $evtDly    = 1;# switch delay trigger on
  CUL_HM_statCnt($ioName,"r");
  my $dname = ($dst eq "000000") ? "broadcast" :
                         ($dstH ? $dstH->{NAME} :
                    ($dst eq $id ? $ioName :
                                   $dst));
  if(!$shash && $mTp eq "00") { # generate device
    my $sname = "HM_$src";
    Log3 undef, 2, "CUL_HM Unknown device $sname is now defined";
    DoTrigger("global","UNDEFINED $sname CUL_HM $src");
    # CommandDefine(undef,"$sname CUL_HM $src");
    $shash = CUL_HM_id2Hash($src); #sourcehash - changed to channel entity
    $devH = $shash;
    $devH->{IODev} = $iohash;
    $shash->{helper}{io}{nextSend} = gettimeofday()+0.09;# io couldn't set
  }

  my @entities = ("global"); #additional entities with events to be notifies
  ####################  attack alarm detection#####################
  if (   $dstH && $dst ne "000000"
      && !CUL_HM_getAttrInt($dname,"ignore")
      && ($mTp eq '01' || $mTp eq '11'
      )){
    my $ioId = AttrVal($dstH->{IODev}{NAME},"hmId","-");
    if($ioId ne $src){
      CUL_HM_eventP($dstH,"ErrIoId_$src");
      my ($evntCnt,undef) = split(' last_at:',$dstH->{"prot"."ErrIoId_$src"},2);
      push @evtEt,[$dstH,1,"sabotageAttackId:ErrIoId_$src cnt:$evntCnt"];
    }
    if( defined $dstH->{helper}{cSnd} && 
          $dstH->{helper}{cSnd} =~ m/substr($msg,7)/){
      Log3 $dname,2,"CUL_HM $dname attack:$dstH->{helper}{cSnd}:".substr($msg,7);
      CUL_HM_eventP($dstH,"ErrIoAttack");
      my ($evntCnt,undef) = split(' last_at:',$dstH->{"prot"."ErrIoAttack"},2);
      push @evtEt,[$dstH,1,"sabotageAttack:ErrIoAttack cnt:$evntCnt"];
    }
  }
  ###########

  #  return "" if($src eq $id);# mirrored messages - covered by !$shash
  if(!$shash){    # Unknown source
    $evtDly    = 0;# switch delay trigger off
    return "" if ($msg =~ m/998112......000001/);# HMLAN internal message, consum 
    my $ccu =InternalVal($ioName,"owner_CCU","");
    CUL_HM_DumpProtocol("RCV",$iohash,$len,$mNo,$mFlg,$mTp,$src,$dst,$p);

    if ($defs{$ccu}){#
      push @evtEt,[$defs{$ccu},0,"unknown_$src:received"];# do not trigger
      return CUL_HM_pushEvnts();
    }
    return;
  }
  $respRemoved = 0;  #set to 'no response in this message' at start
  my $name = $shash->{NAME};
  my $ioId = CUL_HM_h2IoId($devH->{IODev});
  $ioId = $id if(!$ioId);
  if (CUL_HM_getAttrInt($name,"ignore")){
    $defs{$_}{".noDispatchVars"} = 1 foreach (grep !/^$devH->{NAME}$/,@entities);
    return (CUL_HM_pushEvnts(),$name,@entities);
  }

  if ($msgStat){
    if   ($msgStat =~ m/AESKey/){
      push @evtEt,[$shash,1,"aesKeyNbr:".substr($msgStat,7)];
      $msgStat = ""; # already processed
    }
    elsif($msgStat =~ m/AESCom/){# AES communication to central
      my $aesStat = substr($msgStat,7);
      push @evtEt,[$shash,1,"aesCommToDev:".$aesStat];
      ### General may need substential rework
      # activate AES only for dedicated channels?
      if($mTp =~ m /^4[01]/){ #someone is triggered##########
        my $chn = hex($mI[0])& 0x3f;
        my $cName = CUL_HM_id2Name($src.sprintf("%02X",$chn));
        my $bCnt = hex($mI[1]);
        push @evtEt,[$defs{$cName},1,"trig_aes_$dname:$aesStat:$bCnt"] 
              if (defined $defs{$cName});

        if($aesStat eq "ok"                     #aes ok
           && defined $devH->{cmdStacAESPend}   #commands waiting
           && $ioId eq $dst){                   #aes from IO device
          foreach (@{$devH->{cmdStacAESPend}}) {
            my ($h,$c) = split(";",$_);
            CUL_HM_PushCmdStack(CUL_HM_id2Hash($h),$c);
          }
          CUL_HM_ProcessCmdStack($shash);
        }
        delete $devH->{cmdStacAESPend};          

        my @peers = grep !/00000000/,split(",",AttrVal($cName,"peerIDs",""));
        foreach my $peer (grep /$dst/,@peers){
          my $pName = CUL_HM_id2Name($peer);
          $pName = CUL_HM_id2Name(substr($peer,0,6)) if (!$defs{$pName});
          next if (!$defs{$pName});#||substr($peer,0,6) ne $dst
          push @evtEt,[$defs{$pName},1,"trig_aes_$cName:$aesStat:$bCnt"];
        }
      }
      $defs{$_}{".noDispatchVars"} = 1 foreach (grep !/^$devH->{NAME}$/,@entities);
      return (CUL_HM_pushEvnts(),$name);
    }
  }
  CUL_HM_eventP($shash,"Evt_$msgStat")if ($msgStat);#log io-events
  CUL_HM_eventP($shash,"Rcv");
  my $target = " (to $dname)";
  my $st = AttrVal($name, "subType", "");
  my $md = AttrVal($name, "model"  , "");
  my $tn = TimeNow();
  CUL_HM_storeRssi($name
                  ,"at_".(($mFlgH&0x40)?"rpt_":"").$ioName # repeater?
                  ,$myRSSI
                  ,$mNo);

  # +++++ check for duplicate or repeat ++++
  my $msgX = "No:$mNo - t:$mTp s:$src d:$dst ".($p?$p:"");
  if($devH->{lastMsg} && $devH->{lastMsg} eq $msgX) { #duplicate -lost 'ack'?
           
    if(   $devH->{helper}{rpt}                           #was responded
       && $devH->{helper}{rpt}{IO}  eq $ioName           #from same IO
       && $devH->{helper}{rpt}{flg} eq substr($msg,5,1)  #not from repeater
       && $devH->{helper}{rpt}{ts}  < gettimeofday()-0.24 # again if older then 240ms (typ repeat time)
                                                          #todo: hack since HMLAN sends duplicate status messages
       ){
      my $ack = $devH->{helper}{rpt}{ack};#shorthand
      my $i=0;
      $devH->{helper}{rpt}{ts} = gettimeofday();
      CUL_HM_SndCmd(${$ack}[$i++],${$ack}[$i++]) while ($i<@{$ack});
      Log3 $name,4,"CUL_HM $name dupe: repeat ".scalar(@{$ack})." ack, dont process";
    }
    else{
      Log3 $name,4,"CUL_HM $name dupe: dont process";
    }
    CUL_HM_pushEvnts();
    $defs{$_}{".noDispatchVars"} = 1 foreach (grep !/^$devH->{NAME}$/,@entities);
    CUL_HM_sndIfOpen("x:$ioName");
    return (CUL_HM_pushEvnts(),$name,@entities); #return something to please dispatcher
  }
  $shash->{lastMsg} = $msgX;
  delete $shash->{helper}{rpt};# new message, rm recent ack
  my @ack; # ack and responses, might be repeated
  $devH->{helper}{HM_CMDNR} = hex($mNo);
  
  CUL_HM_DumpProtocol("RCV",$iohash,$len,$mNo,$mFlg,$mTp,$src,$dst,$p);

  #----------start valid messages parsing ---------
  my $parse = CUL_HM_parseCommon($iohash,$mNo,$mFlg,$mTp,$src,$dst,$p,$st,$md,$dname);
  push @evtEt,[$shash,1,"powerOn:$tn"] if($parse eq "powerOn");
  push @evtEt,[$shash,1,""]            if($parse eq "parsed"); # msg is parsed but may
                                                             # be processed further
  if   ($parse eq "ACK" ||
        $parse eq "done"   ){# remember - ACKinfo will be passed on
    push @evtEt,[$shash,1,""];
  }
  elsif($parse eq "NACK"){
    push @evtEt,[$shash,1,"state:NACK"];
  }
  elsif($mTp eq "12") {#$lcm eq "09A112" Another fhem request (HAVE_DATA)
    ;
  }
  elsif($md =~ m/^(KS550|KS888|HM-WDS100-C6-O)/) { ############################
    if($mTp eq "70") {
      my ($t,$h,$r,$w,$wd,$s,$b) = map{hex($_)} unpack 'A4A2A4A4(A2)*',$p;
      my $tsgn = ($t & 0x4000);
      $t = ($t & 0x3fff)/10;
      $t = sprintf("%0.1f", $t-1638.4) if($tsgn);
      my $ir = ($r & 0x8000)?1:0;
      $r = ($r & 0x7fff) * 0.295;
      my $wdr = ($w>>14)*22.5;
      $w = ($w & 0x3fff)/10;
      $wd = $wd * 5;
      my $sM = "state:";
      if(defined $t)  {$sM .= "T: $t "    ;push @evtEt,[$shash,1,"temperature:$t"    ];}
      if(defined $h)  {$sM .= "H: $h "    ;push @evtEt,[$shash,1,"humidity:$h"       ];}
      if(defined $w)  {$sM .= "W: $w "    ;push @evtEt,[$shash,1,"windSpeed:$w"      ];}
      if(defined $r)  {$sM .= "R: $r "    ;push @evtEt,[$shash,1,"rain:$r"           ];}
      if(defined $ir) {$sM .= "IR: $ir "  ;push @evtEt,[$shash,1,"isRaining:$ir"     ];}
      if(defined $wd) {$sM .= "WD: $wd "  ;push @evtEt,[$shash,1,"windDirection:$wd" ];}
      if(defined $wdr){$sM .= "WDR: $wdr ";push @evtEt,[$shash,1,"windDirRange:$wdr" ];}
      if(defined $s)  {$sM .= "S: $s "    ;push @evtEt,[$shash,1,"sunshine:$s"       ];}
      if(defined $b)  {$sM .= "B: $b "    ;push @evtEt,[$shash,1,"brightness:$b"     ];}
      push @evtEt,[$shash,1,$sM];
    }
    elsif ($mTp eq "41"){
      my ($chn,$cnt,$state)=(hex($1),hex($2),$3) if($p =~ m/^(..)(..)(..)/);
      $chn = sprintf("%02X",$chn & 0x3f);
      $shash = $modules{CUL_HM}{defptr}{"$src$chn"}
                             if($modules{CUL_HM}{defptr}{"$src$chn"});
      my $txt;
      if    ($shash->{helper}{lm} && $shash->{helper}{lm}{hex($state)}){$txt = $shash->{helper}{lm}{hex($state)}}
      elsif ($lvlStr{md}{$md})                                         {$txt = $lvlStr{md}{$md}{$state}}
      elsif ($lvlStr{st}{$st})                                         {$txt = $lvlStr{st}{$st}{$state}}
      else                                                             {$txt = "unknown:$state"}
      push @evtEt,[$shash,1,"storm:$txt"];
      push @evtEt,[$devH,1,"trig_$chn:$dname"];
      #push @evtEt,[$devH,1,"battery:". ($err?"low"  :"ok"  )]; has no battery
    }
    else {
      push @evtEt,[$shash,1,"unknown:$p"];
    }
  }
  elsif($md =~ m/(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/) { ###########################
    my ($sType,$chn) = ($mI[0],$mI[1]);
    if($mTp eq "70") { # weather event
      $chn = '01'; # fix definition
      my (    $t,      $h) =  (hex($mI[0].$mI[1]), hex($mI[2]));# temp is 15 bit signed
      $t = sprintf("%2.1f",($t & 0x3fff)/10*(($t & 0x4000)?-1:1));
      my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
      if ($chnHash){
        push @evtEt,[$chnHash,1,"state:T: $t H: $h"];
        push @evtEt,[$chnHash,1,"measured-temp:$t"];
        push @evtEt,[$chnHash,1,"humidity:$h"];
      }
      push @evtEt,[$shash,1,"state:T: $t H: $h"];
      push @evtEt,[$shash,1,"measured-temp:$t"];
      push @evtEt,[$shash,1,"humidity:$h"];
    }
    elsif($mTp eq "58") {# climate event
      $chn = '02'; # fix definition
      my (   $d1,     $vp) = # adjust_command[0..4] adj_data[0..250]
         (    $mI[0], hex($mI[1]));
      $vp = int($vp/2.56+0.5);   # valve position in %
      my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
      if($chnHash){
        push @evtEt,[$chnHash,1,"state:$vp"];
        if ($chnHash->{helper}{needUpdate}){
          if ($chnHash->{helper}{needUpdate} == 1){
            $chnHash->{helper}{needUpdate}++;
          }
          else{
            CUL_HM_qStateUpdatIfEnab(":".$chnHash->{NAME});
            delete $chnHash->{helper}{needUpdate};
          }
        }
      }
      push @evtEt,[$shash,1,"actuator:$vp"];

      # Set the valve state too, without an extra trigger
      if($dstH){
        push @evtEt,[$dstH,1,"state:set_$vp"   ];
        push @evtEt,[$dstH,1,"ValveDesired:$vp"];
      }
    }
    elsif(($mTp eq '02' &&$sType eq '01')||    # ackStatus
          ($mTp eq '10' &&$sType eq '06')){    # infoStatus
      my $dTemp = hex($mI[2])/2;
      $dTemp = ($dTemp < 6 )?'off':
               ($dTemp >30 )?'on' :sprintf("%0.1f", $dTemp);
      my $err = hex($mI[3]);
      my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
      if($chnHash){
        my $chnName = $chnHash->{NAME};
        my $mode = ReadingsVal($chnName,"R-controlMode","");
        push @evtEt,[$chnHash,1,"desired-temp:$dTemp"];
        push @evtEt,[$chnHash,1,"desired-temp-manu:$dTemp"] if($mode =~ m /manual/  && $mTp eq '10');
#       readingsSingleUpdate($chnHash,"desired-temp-cent",$dTemp,1) if($mode =~ m /central/ && $mTp eq '02');
#       removed - shall not be changed automatically - change is  only temporary
#       CUL_HM_Set($chnHash,$chnName,"desired-temp",$dTemp)         if($mode =~ m /central/ && $mTp eq '10');
        $chnHash->{helper}{needUpdate} = 1                          if($mode =~ m /central/ && $mTp eq '10');
       }
      push @evtEt,[$shash,1,"desired-temp:$dTemp"];
      push @evtEt,[$shash,1,"battery:".($err&0x80?"low":"ok")];
    }
    elsif($mTp eq "10" &&                   # Config change report
          ($p =~ m/^0402000000000501/)) {   # paramchanged L5
      my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
      my $dTemp;
      if($chnHash){
        my $chnName = $chnHash->{NAME};
        my $mode = ReadingsVal($chnName,"R-controlMode","");
        $dTemp = ReadingsVal($chnName,"desired-temp","21.0");
        if (!$chnHash->{helper}{oldMode} || $chnHash->{helper}{oldMode} ne $mode){
          $dTemp = ReadingsVal($chnName,"desired-temp-manu",$dTemp)if ($mode =~ m /manual/);
          $dTemp = ReadingsVal($chnName,"desired-temp-cent",$dTemp)if ($mode =~ m /central/);
          $chnHash->{helper}{oldMode} = $mode;
        }
        push @evtEt,[$chnHash,1,"desired-temp:$dTemp"];
      }
      push @evtEt,[$shash,1,"desired-temp:$dTemp"]
    }
    elsif($mTp eq "01"){                       # status reports
      if($p =~ m/^010809(..)0A(..)/) { # TC set valve  for VD => post events to VD
        my (   $of,     $vep) = (hex($1), hex($2));
        push @evtEt,[$shash,1,"ValveErrorPosition_for_$dname: $vep"];
        push @evtEt,[$shash,1,"ValveOffset_for_$dname: $of"];
        push @evtEt,[$dstH,1,"ValveErrorPosition:set_$vep"];
        push @evtEt,[$dstH,1,"ValveOffset:set_$of"];
      }
      elsif($p =~ m/^010[56]/){ # 'prepare to set' or 'end set'
        push @evtEt,[$shash,1,""]; #
      }
    }
    elsif($mTp eq "3F" && $ioId eq $dst) {     # Timestamp request
      my $s2000 = sprintf("%02X", CUL_HM_secSince2000());
      push @ack,$shash,"${mNo}803F$ioId${src}0204$s2000";
      push @evtEt,[$shash,1,"time-request"];
    }
  }
  elsif($md =~ m/(HM-CC-VD|ROTO_ZEL-STG-RM-FSA)/) { ###########################
    if($mTp eq "02" && @mI > 2) {#subtype+chn+value+err
      my ($chn,$vp, $err) = map{hex($_)} @mI[1..3];
      $chn = sprintf("%02X",$chn&0x3f);
      $vp = int($vp)/2;   # valve position in %
      push @evtEt,[$shash,1,"ValvePosition:$vp"];
      push @evtEt,[$shash,1,"state:$vp"];
      $shash = $modules{CUL_HM}{defptr}{"$src$chn"}
                             if($modules{CUL_HM}{defptr}{"$src$chn"});

      my $stErr = ($err >>1) & 0x7;    # Status-Byte Evaluation
      push @evtEt,[$shash,1,"battery:".(($stErr == 4)?"critical":($err&0x80?"low":"ok"))];
      if (!$stErr){#remove both conditions
        push @evtEt,[$shash,1,"motorErr:ok"];
      }
      else{
        push @evtEt,[$shash,1,"motorErr:blocked"                  ]if($stErr == 1);
        push @evtEt,[$shash,1,"motorErr:loose"                    ]if($stErr == 2);
        push @evtEt,[$shash,1,"motorErr:adjusting range too small"]if($stErr == 3);
#       push @evtEt,[$shash,1,"battery:critical"                  ]if($stErr == 4);
      }
      push @evtEt,[$shash,1,"motor:opening"] if(($err&0x30) == 0x10);
      push @evtEt,[$shash,1,"motor:closing"] if(($err&0x30) == 0x20);
      push @evtEt,[$shash,1,"motor:stop"   ] if(($err&0x30) == 0x00);

      #VD hang detection
      my $des = ReadingsVal($name, "ValveDesired", $vp);
      $des =~ s/ .*//; # remove unit     
      if (($des < $vp-1 || $des > $vp+1) && ($err&0x30) == 0x00){ 
        if ($shash->{helper}{oldDes} eq $des){#desired valve position stable
          push @evtEt,[$shash,1,"operState:errorTargetNotMet"];
          push @evtEt,[$shash,1,"operStateErrCnt:".(ReadingsVal($name,"operStateErrCnt","0")+1)];
        }
        else{
          push @evtEt,[$shash,1,"operState:changed"];
        }
      }
      else{
        push @evtEt,[$shash,1,"operState:".((($err&0x30) == 0x00)?"onTarget":"adjusting")];
      }
      $shash->{helper}{oldDes} = $des;
    }
  }
  elsif($md =~ m/HM-CC-RT-DN/) { ##############################################
    my %ctlTbl=( 0=>"auto", 1=>"manual", 2=>"party",3=>"boost");

    if   (  ($mTyp eq "100A") #info-level/
          ||($mTyp eq "0201")){#ackInfo

      my ($err       ,$ctrlMode  ,$setTemp          ,$bTime,$pTemp,$pStart,$pEnd,$chn,$uk0,$lBat,$actTemp,$vp) = 
         (hex($mI[3]),hex($mI[5]),hex($mI[1].$mI[2]),"-"    ,"-"   ,"-"    ,"-"                             );
      
      if($mTp eq "10"){
        $chn = "04";#fixed
        my $bat  =(($err            ) & 0x1f)/10+1.5;
        $actTemp =sprintf("%2.1f",((($setTemp        ) & 0x3ff)/10));
        $vp      = (hex($mI[4])     ) & 0x7f ;
        $setTemp = ($setTemp    >>10);
        $err     = ($err        >> 5);
        $shash = $modules{CUL_HM}{defptr}{"$src$chn"} if($modules{CUL_HM}{defptr}{"$src$chn"});
        push @evtEt,[$shash,1,"measured-temp:$actTemp" ];
        push @evtEt,[$shash,1,"ValvePosition:$vp"    ];
        #device---
        push @evtEt,[$devH,1,"measured-temp:$actTemp"];
        push @evtEt,[$devH,1,"batteryLevel:$bat"];
        push @evtEt,[$devH,1,"actuator:$vp"];
        #weather Chan
        my $wHash = $modules{CUL_HM}{defptr}{$src."01"}; 
        if ($wHash){
          push @evtEt,[$wHash,1,"measured-temp:$actTemp"];
          push @evtEt,[$wHash,1,"state:$actTemp"];
        }
      }
      else{
        $chn        =  $mI[1];
        $setTemp    = ($setTemp        );
        $lBat       = $err&0x80?"low":"ok"; # prior to changes of $err!
        $err        = ($err        >> 1);
        $shash = $modules{CUL_HM}{defptr}{"$src$chn"} if($modules{CUL_HM}{defptr}{"$src$chn"});
        $actTemp = ReadingsVal($name,"measured-temp","");
        $vp      = ReadingsVal($name,"actuator","");
      }
      delete $devH->{helper}{getBatState};
      $setTemp    =(($setTemp        ) & 0x3f )/2;
      $err        = ($err            ) & 0x7  ;
      $uk0        = ($ctrlMode       ) & 0x3f ;#unknown
      $ctrlMode   = ($ctrlMode   >> 6) & 0x3  ;
      
      $setTemp = ($setTemp < 5 )?'off':
                 ($setTemp >30 )?'on' :sprintf("%.1f",$setTemp);
      if (defined $mI[6]){# message with party mode
        my @pt =  map{hex($_)} @mI[5..$#mI];
        $pTemp =(($pt[7]     )& 0x3f)/2 if (defined $pt[7]) ;
        my $st  = (    ($pt[0]      )& 0x3f)/2;
        $pStart =     (($pt[2]      )& 0x7f)   # year
                 ."-".(($pt[6]  >> 4)& 0x0f)   # month
                 ."-".(($pt[1]      )& 0x1f)   # day
                 ." ".int($st)                 # Time h
                 .":".(int($st)!=$st?"30":"00")# Time min
                 ;
        my $et  = (    ($pt[3]      )& 0x3f)/2;
        $pEnd   =     (($pt[5]      )& 0x7f)   # year
                 ."-".(($pt[6]      )& 0x0f)   # month
                 ."-".(($pt[4]      )& 0x1f)   # day
                 ." ".int($et)                 # Time h
                 .":".(int($et)!=$et?"30":"00")# Time min
                 ;
      }
      elsif(defined $mI[5] && $ctrlMode == 3 ){#message with boost
        $bTime     = ((hex($mI[5])  ) & 0x3f)." min";
      }

      my %errTbl=( 0=>"ok", 1=>"ValveTight", 2=>"adjustRangeTooLarge"
                  ,3=>"adjustRangeTooSmall" , 4=>"communicationERR"
                  ,5=>"unknown", 6=>"lowBat", 7=>"ValveErrorPosition" );

      push @evtEt,[$shash,1,"motorErr:$errTbl{$err}" ];
      push @evtEt,[$shash,1,"desired-temp:$setTemp"  ];
      push @evtEt,[$shash,1,"controlMode:$ctlTbl{$ctrlMode}"];
      push @evtEt,[$shash,1,"boostTime:$bTime"];
      push @evtEt,[$shash,1,"state:T: $actTemp desired: $setTemp valve: $vp"];
      push @evtEt,[$shash,1,"partyStart:$pStart"];
      push @evtEt,[$shash,1,"partyEnd:$pEnd"];
      push @evtEt,[$shash,1,"partyTemp:$pTemp"];
      #push @evtEt,[$shash,1,"unknown0:$uk0"];
      #push @evtEt,[$shash,1,"unknown1:".$2 if ($p =~ m/^0A(.10)(.*)/)];
      push @evtEt,[$devH,1,"battery:$lBat"] if ($lBat);
      push @evtEt,[$devH,1,"desired-temp:$setTemp"];
    }
    elsif($mTp eq "59" && defined $mI[0]) {#inform team about new value
      my $setTemp = sprintf("%.1f",int(hex($mI[0])/4)/2);
      my $ctrlMode = hex($mI[0])&0x3;
      push @evtEt,[$shash,1,"desired-temp:$setTemp"];
      push @evtEt,[$shash,1,"controlMode:$ctlTbl{$ctrlMode}"];

      my $tHash = $modules{CUL_HM}{defptr}{$dst."04"};
      if ($tHash){
        push @evtEt,[$tHash,1,"desired-temp:$setTemp"];
        push @evtEt,[$tHash,1,"controlMode:$ctlTbl{$ctrlMode}"];
      }
    }
    elsif($mTp eq "3F" && $ioId eq $dst) { # Timestamp request
      my $s2000 = sprintf("%02X", CUL_HM_secSince2000());
      push @ack,$shash,"${mNo}803F$ioId${src}0204$s2000";
      push @evtEt,[$shash,1,"time-request"];
      # schedule desired-temp just to get an AckInfo for battery state
      $shash->{helper}{getBatState} = 1;
    }
  }
  elsif($md eq "HM-TC-IT-WM-W-EU") { ##########################################
    my %ctlTbl=( 0=>"auto", 1=>"manual", 2=>"party",3=>"boost");
    if( ( $mTp eq "10" && $mI[0] eq '0B')  #info-level
      ||( $mTp eq "02" && $mI[0] eq '01')) {#ack-status
      my @d = map{hex($_)} unpack 'A2A4(A2)*',$p;
      my ($chn,$setTemp,$actTemp, $cRep,$wRep,$bat ,$lbat,$ctrlMode,$bTime,$pTemp,$pStart,$pEnd) =
          ("02",$d[1],$d[1],      $d[2],$d[2],$d[2],$d[2],""       ,"-"   ,"-"   ,"-"    ,"-");
      
      $lbat       = ($lbat           ) & 0x80;
      my $dHash = $shash;
      $shash = $modules{CUL_HM}{defptr}{"$src$chn"}
                             if($modules{CUL_HM}{defptr}{"$src$chn"});
      if ($mTp eq "10"){
        $ctrlMode   = $d[3];
        $bat        =(($bat            ) & 0x1f)/10+1.5;
        $setTemp    =(($setTemp    >>10) & 0x3f )/2;
        $actTemp    =(($actTemp        ) & 0x3ff)/10;
        $actTemp    = -1 * $actTemp if ($d[1] & 0x200 );# obey signed
        $actTemp = sprintf("%2.1f",$actTemp);
        push @evtEt,[$shash,1,"measured-temp:$actTemp"];
        push @evtEt,[$dHash,1,"measured-temp:$actTemp"];
        push @evtEt,[$dHash,1,"batteryLevel:$bat"];
        $cRep = (($cRep    >>6) & 0x01 )?"on":"off";
        $wRep = (($wRep    >>5) & 0x01 )?"on":"off";        
      }
      else{#actTemp is not provided in ack message - use old value
        $ctrlMode   = $d[4];
        $actTemp = ReadingsVal($name,"measured-temp",0);
        $setTemp  =(hex($mI[2]) & 0x3f )/2;
        $cRep = (($cRep    >>2) & 0x01 )?"on":"off";
        $wRep = (($wRep    >>1) & 0x01 )?"on":"off";        
      }
      $ctrlMode = ($ctrlMode   >> 6) & 0x3  ;
      $setTemp  = ($setTemp < 5 )?'off':
                  ($setTemp >30 )?'on' :sprintf("%.1f",$setTemp);
      
      if (defined $d[11]){# message with party mode
        $pTemp =(($d[11]     )& 0x3f)/2 if (defined $d[11]) ;
        my @p;
        if ($mTp eq "10") {@p = @d[3..9]}
        else              {@p = @d[4..10]}
        my $st = (($p[0]      )& 0x3f)/2;
        $pStart =     (($p[2]      )& 0x7f)    # year
                 ."-".(($p[6]  >> 4)& 0x0f)    # month
                 ."-".(($p[1]      )& 0x1f)    # day
                 ." ".int($st)                 # Time h
                 .":".(int($st)!=$st?"30":"00")# Time min
                 ;
        my $et = (($p[3]      )& 0x3f)/2;
        $pEnd   =     (($p[5]      )& 0x7f)    # year
                 ."-".(($p[6]      )& 0x0f)    # month
                 ."-".(($p[4]      )& 0x1f)    # day
                 ." ".int($et)                 # Time h
                 .":".(int($et)!=$et?"30":"00")# Time min
                 ;
        push @evtEt,[$shash,1,"partyStart:$pStart"];
        push @evtEt,[$shash,1,"partyEnd:$pEnd"];
        push @evtEt,[$shash,1,"partyTemp:$pTemp"];
      }
      elsif(defined $d[3] && $ctrlMode == 3 ){#message with boost
        $bTime     = (($d[3]       ) & 0x3f)." min";
      }

      push @evtEt,[$shash,1,"desired-temp:$setTemp"];
      push @evtEt,[$shash,1,"controlMode:$ctlTbl{$ctrlMode}"];
      push @evtEt,[$shash,1,"state:T: $actTemp desired: $setTemp"];
      push @evtEt,[$shash,1,"battery:".($lbat?"low":"ok")];
      push @evtEt,[$shash,1,"commReporting:$cRep"];
      push @evtEt,[$shash,1,"winOpenReporting:$wRep"];
      push @evtEt,[$shash,1,"boostTime:$bTime"];
      push @evtEt,[$dHash,1,"desired-temp:$setTemp"];
    }
    elsif($mTp eq "70"){
      my $chn = "01";
      $shash = $modules{CUL_HM}{defptr}{"$src$chn"}
                             if($modules{CUL_HM}{defptr}{"$src$chn"});
      my ($t,$h) =  map{hex($_)} unpack 'A4A2',$p;
      $t -= 0x8000 if($t > 1638.4);
      $t = sprintf("%0.1f", $t/10);
      push @evtEt,[$shash,1,"temperature:$t"];
      push @evtEt,[$shash,1,"humidity:$h"];
      push @evtEt,[$shash,1,"state:T: $t H: $h"];
    }
    elsif($mTp eq "5A"){# thermal control - might work with broadcast
      my $chn = "02";
      $shash = $modules{CUL_HM}{defptr}{"$src$chn"}
                             if($modules{CUL_HM}{defptr}{"$src$chn"});
      my ($t,$h) =  map{hex($_)} unpack 'A4A2',$p;
      my $setTemp    =(($t    >>10) & 0x3f )/2;
      my $actTemp    =(($t        ) & 0x3ff)/10;
      $actTemp = sprintf("%2.1f",$actTemp);
      $setTemp = ($setTemp < 5 )?'off':
                 ($setTemp >30 )?'on' :sprintf("%.1f",$setTemp);
      push @evtEt,[$shash,1,"measured-temp:$actTemp"];
      push @evtEt,[$shash,1,"desired-temp:$setTemp"];
      push @evtEt,[$shash,1,"humidity:$h"];
      push @evtEt,[$shash,1,"state:T: $actTemp desired: $setTemp"];
    }
    elsif($mTp =~ m/^4./) {
      my ($chn,$lvl) = ($mI[0],hex($mI[2])/2);
      my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
      if ($chnHash){
        push @evtEt,[$chnHash,1,"level:$lvl"];
      }
    }
    elsif($mTp eq "3F" && $ioId eq $dst) { # Timestamp request
      my $s2000 = sprintf("%02X", CUL_HM_secSince2000());
      push @ack,$shash,"${mNo}803F$ioId${src}0204$s2000";
      push @evtEt,[$shash,1,"time-request"];
    }
  }
  elsif($md =~ m/^(HM-Sen-Wa-Od|HM-CC-SCD)$/){ ################################
    if (($mTp eq "02" && $p =~ m/^01/) ||  # handle Ack_Status
        ($mTp eq "10" && $p =~ m/^06/) ||  #or Info_Status message here
        ($mTp eq "41"))                {
      my $lvl = substr($p,4,2);
      my $err = hex(substr($p,6,2));
      if    ($lvlStr{md}{$md}){$lvl = $lvlStr{md}{$md}{$lvl}}
      elsif ($lvlStr{st}{$st}){$lvl = $lvlStr{st}{$st}{$lvl} }
      else                    {$lvl = hex($lvl)/2}

      push @evtEt,[$shash,1,"level:$lvl"] if($md eq "HM-Sen-Wa-Od");
      push @evtEt,[$shash,1,"state:$lvl"];
      push @evtEt,[$shash,1,"battery:".($err&0x80?"low":"ok")] if (defined $err);
    }
  }
  elsif($md eq "KFM-Sensor") { ################################################
    if ($mTp eq "53"){
      if($p =~ m/(..)4(.)0200(..)(..)(..)/) {
        my ($chn,$seq, $k_v1, $k_v2, $k_v3) = (hex($1),hex($2),$3,hex($4),hex($5));
        push @evtEt,[$shash,1,"battery:".($chn & 0x80?"low":"ok")];
        my $v = 1408 - ((($k_v3 & 0x07)<<8) + $k_v2);
        push @evtEt,[$shash,1,"rawValue:$v"];
        my $nextSeq = ReadingsVal($name,"Sequence","");
        $nextSeq =~ s/_.*//;
        $nextSeq = ($nextSeq %15)+1;      
        push @evtEt,[$shash,1,"Sequence:$seq".($nextSeq ne $seq?"_seqMiss":"")];

        my $r2r = AttrVal($name, "rawToReadable", undef);
        if($r2r) {
          my @r2r = split("[ :]", $r2r);
          foreach(my $idx = 0; $idx < @r2r-2; $idx+=2) {
            if($v >= $r2r[$idx] && $v <= $r2r[$idx+2]) {
              my $f = (($v-$r2r[$idx])/($r2r[$idx+2]-$r2r[$idx]));
              my $cv = ($r2r[$idx+3]-$r2r[$idx+1])*$f + $r2r[$idx+1];
              my $unit = AttrVal($name, "unit", "");
              push @evtEt,[$shash,1,sprintf("state:%.1f %s",$cv,$unit)];
              push @evtEt,[$shash,1,sprintf("content:%.1f %s",$cv,$unit)];
              last;
            }
          }
        } 
        else {
          push @evtEt,[$shash,1,"state:$v"];
        }
      }
    }
  }
  elsif($st eq "THSensor") { ##################################################
    if    ($mTp eq "70"){
      my $chn;
      my ($d1,$h,$ap) = map{hex($_)} unpack 'A4A2A4',$p;
      if    ($md =~  m/^(WS550|WS888|HM-WDC7000)/){$chn = "10"}
      elsif ($md eq "HM-WDS30-OT2-SM")            {$chn = "05";$h=""}
      elsif ($md =~  m/^(S550IA|HM-WDS30-T-O)/)   {$chn = "01";$h=""}
      else                                        {$chn = "01"}

      my $t =  $d1 & 0x7fff;
      $t -= 0x8000 if($t &0x4000);
      $t = sprintf("%0.1f", $t/10);
      my $statemsg = "state:T: $t";
      push @evtEt,[$shash,1,"temperature:$t"];#temp is always there
      push @evtEt,[$devH,1,"battery:".($d1 & 0x8000?"low":"ok")];
      if($modules{CUL_HM}{defptr}{$src.$chn}){
        my $ch = $modules{CUL_HM}{defptr}{$src.$chn};
        push @evtEt,[$ch,1,$statemsg];
        push @evtEt,[$ch,1,"temperature:$t"];
      }
      if ($h) {$statemsg .= " H: $h"  ; push @evtEt,[$shash,1,"humidity:$h"]; }
      if ($ap){$statemsg .= " AP: $ap"; push @evtEt,[$shash,1,"airpress:$ap"];}
      push @evtEt,[$shash,1,$statemsg];
    }
    elsif ($mTp eq "53"){
      my ($chn,@dat) = unpack 'A2(A6)*',$p;
      push @evtEt,[$devH,1,"battery:".(hex($chn)&0x80?"low":"ok")];
      foreach (@dat){
        my ($a,$d) = unpack 'A2A4',$_;
        $d = hex($d);
        $d -= 0x10000 if($d & 0xC000);
        $d = sprintf("%0.1f",$d/10);
        my $chId = sprintf("%02X",hex($a) & 0x3f);
        my $chnHash = $modules{CUL_HM}{defptr}{$src.$chId};
        if ($chnHash){
          push @evtEt,[$chnHash,1,"state:T: $d"];
          push @evtEt,[$chnHash,1,"temperature:$d"];
        }
        else{
          push @evtEt,[$shash,1,"Chan_$chId:T: $d"];
        }
      }
    }
  }
  elsif($st eq "sensRain") {###################################################
    my $hHash = CUL_HM_id2Hash($src."02");# hash for heating
    my $pon = 0;# power on if mNo == 0 and heating status plus second msg
                # status or trigger from rain channel
    if (($mTp eq "02" && $p =~ m/^01/) || #Ack_Status
        ($mTp eq "10" && $p =~ m/^06/)) { #Info_Status

      my ($subType,$chn,$val,$err) = ($mI[0],hex($mI[1]),$mI[2],hex($mI[3]));
      $chn = sprintf("%02X",$chn&0x3f);
      my $chId = $src.$chn;
      $shash = $modules{CUL_HM}{defptr}{$chId}
                             if($modules{CUL_HM}{defptr}{$chId});

      push @evtEt,[$shash,1,"timedOn:".(($err&0x40 && $chn eq "02")?"running":"off")];

      my $mdCh = $md.$chn;
      if($lvlStr{mdCh}{$mdCh} && $lvlStr{mdCh}{$mdCh}{$val}){
        $val = $lvlStr{mdCh}{$mdCh}{$val};
      }
      else{
        $val = hex($val)/2;
      }
      push @evtEt,[$shash,1,"state:$val"];

      if ($val eq "rain"){#--- handle lastRain---
        $shash->{helper}{lastRain} = $tn;
      }
      elsif ($val eq "dry" && $shash->{helper}{lastRain}){
        push @evtEt,[$shash,0,"lastRain:$shash->{helper}{lastRain}"];
        delete $shash->{helper}{lastRain};
      }

      push @evtEt,[$shash,0,'.level:'.($val eq "off"?"0":"100")];

      if    ($mNo eq "00" && $chn eq "02" && $val eq "on"){
        $hHash->{helper}{pOn} = 1;
      }
      elsif ($mNo eq "01" && $chn eq "01" &&
             $hHash->{helper}{pOn} && $hHash->{helper}{pOn} == 1){
        $pon = 1;
      }
      else{
        delete $hHash->{helper}{pOn};
        my $hHash = CUL_HM_id2Hash($src."02");# hash for heating
        if ($chn eq "01" &&
            $hHash->{helper}{param} && $hHash->{helper}{param}{onAtRain}){
          CUL_HM_Set($hHash,$hHash->{NAME},$val eq "rain"?"on":"off");
        }
      }
    }
    elsif ($mTp eq "41")   { #eventonAtRain
      my ($chn,$bno,$val) = @mI;
      $chn = sprintf("%02X",hex($chn)&0x3f);
      $shash = $modules{CUL_HM}{defptr}{$src.$chn}
                             if($modules{CUL_HM}{defptr}{$src.$chn});
      push @evtEt,[$shash,1,"trigger:".hex($bno).":".$lvlStr{mdCh}{$md.$chn}{$val}.$target];
      if ($mNo eq "01" && $bno eq "01" &&
          $hHash->{helper}{pOn} && $hHash->{helper}{pOn} == 1){
        $pon = 1;
      }
      delete $shash->{helper}{pOn};
    }
    if ($pon){# we have power ON, perform action
      push @evtEt,[$devH,1,"powerOn:$tn",];
      CUL_HM_Set($hHash,$hHash->{NAME},"off")
                 if ($hHash && $hHash->{helper}{param}{offAtPon});
    }
  }
  elsif($st =~ m /^(switch|dimmer|blindActuator)$/) {##########################
    if (($mTp eq "02" && $p =~ m/^01/) ||  # handle Ack_Status
        ($mTp eq "10" && $p =~ m/^06/)) { #    or Info_Status message here

      my $rSUpdt = 0;# require status update
      my ($subType,$chn,$val,$err) = ($mI[0],hex($mI[1]),hex($mI[2])/2,hex($mI[3]));
      $chn = sprintf("%02X",$chn&0x3f);
      my $chId = $src.$chn;
      $shash = $modules{CUL_HM}{defptr}{$chId}
                             if($modules{CUL_HM}{defptr}{$chId});
      $name = $shash->{NAME};
      my($lvlMin,$lvlMax)=split",",AttrVal($name, "levelRange", "0,100");
      my $physLvl;                             #store phys level if available
      if(   defined $mI[5]                     #message with physical level?
         && $st eq "dimmer"){
        my $pl = hex($mI[5])/2;
        my $vDim = $shash->{helper}{vDim};     #shortcut
        if ($vDim->{idPhy} &&
            CUL_HM_id2Hash($vDim->{idPhy})){   #has virt chan
          RemoveInternalTimer("sUpdt:".$chId);
          if ($mTp eq "10"){                   #valid PhysLevel
            foreach my $tmpKey ("idPhy","idV2","idV3",){#update all virtuals
              my $vh = CUL_HM_id2Hash($vDim->{$tmpKey}) if ($vDim->{$tmpKey});
              next if (!$vh || $vDim->{$tmpKey} eq $chId);
              my $vl = ReadingsVal($vh->{NAME},"level","???");
              my $vs = ($vl eq "100"?"on":($vl eq "0"?"off":"$vl"));
              my($clvlMin,$clvlMax)=split",",AttrVal($vh->{NAME}, "levelRange", "0,100");
              my $plc = int(($pl-$clvlMin)/($clvlMax - $clvlMin)*200)/2;
              $plc = 1 if ($pl && $plc <= 0);
              $vs = ($plc ne $vl)?"chn:$vs  phys:$plc":$vs;
              push @evtEt,[$vh,1,"state:$vs"];
              push @evtEt,[$vh,1,"phyLevel:$plc"];
            }
            $pl = (($pl-$lvlMin)<=0 && $pl)
                     ? 1
                     : int(($pl-$lvlMin)/($lvlMax - $lvlMin)*200)/2;
            push @evtEt,[$shash,1,"phyLevel:$pl"];      #phys level
            $physLvl = $pl;
          }
          else{                                #invalid PhysLevel
            $rSUpdt = 1;
            CUL_HM_stateUpdatDly($name,5) if ($shash->{helper}{dlvl});# update to get level
            # CUL_HM_stateUpdatDly($name,5);     # update to get level
            # we have to relay on device. Ack may come from a conditional event (BM)
            # if condition is not met device will not send status. 
            # We need to avoid regular requests
            # therefore only update if we initiated the request
          }
        }
      }
      my $pVal = $val;# necessary for roper 'off', not logical off
      $val = (($val-$lvlMin)<=0 && $val)
                  ? 1
                  : int((($val-$lvlMin)/($lvlMax - $lvlMin))*200)/2;

      # blind option: reverse Level Meaning 0 = open, 100 = closed
      if ("levelInverse" eq AttrVal($name, "param", "")){;
        $pVal = $val = 100-$val;
      }
      $physLvl = ReadingsVal($name,"phyLevel",$val)
            if(!defined $physLvl);             #not updated? use old or ignore

      my $vs = ($shash->{helper}{lm} && $shash->{helper}{lm}{$val})?$shash->{helper}{lm}{$val}
                     :($val==100 ? "on":($pVal==0 ? "off":"$val")); # user string...
      push @evtEt,[$shash,1,"level:$val"];
      push @evtEt,[$shash,1,"pct:$val"]; # duplicate to level - necessary for "slider"
      push @evtEt,[$shash,1,"deviceMsg:$vs$target"] if($chn ne "00");
      push @evtEt,[$shash,1,"state:".(($physLvl ne $val)?"chn:$vs phys:$physLvl":$vs)];
      my $eventName = "unknown"; # different names for events
      if   ($st eq "switch")       {$eventName = "switch";}  
      elsif($st eq "blindActuator"){$eventName = "motor" ;}  
      elsif($st eq "dimmer")       {$eventName = "dim"   ;}
      
      my $action; #determine action
      push @evtEt,[$shash,1,"timedOn:".(($err&0x40)?"running":"off")];
      if ($shash->{helper}{dlvl} && defined $err){#are we waiting?
        if ($mI[2] ne $shash->{helper}{dlvl} #level not met?
            && !($err&0x70)){                #and already stopped not timedOn
          #level not met, repeat
          Log3 $name,3,"CUL_HM $name repeat, level $mI[2] instead of $shash->{helper}{dlvl}";
          if ($shash->{helper}{dlvlCmd}){# first try
            CUL_HM_PushCmdStack($shash,$shash->{helper}{dlvlCmd});
            CUL_HM_ProcessCmdStack($shash);
            delete $shash->{helper}{dlvlCmd};# will prevent second try
          }
          else{# no second try - alarm and stop
            push @evtEt,[$shash,1,"levelMissed:desired:".hex($shash->{helper}{dlvl})/2];
            delete $shash->{helper}{dlvl};# we only make one attempt
          }
        }
        else{# either level met, timed on or we are driving...
          delete $shash->{helper}{dlvl};
        }
      }
      if ($st ne "switch"){
        my $dir = ($err >> 4) & 3;
        my %dirName = ( 0=>"stop" ,1=>"up" ,2=>"down" ,3=>"err" );
        push @evtEt,[$shash,1,"$eventName:$dirName{$dir}:$vs"  ];
        $shash->{helper}{dir}{rct} = $shash->{helper}{dir}{cur} 
                  if($shash->{helper}{dir}{cur} &&
                     $shash->{helper}{dir}{cur} ne $dirName{$dir});
        $shash->{helper}{dir}{cur} = $dirName{$dir};
      }
      if (!$rSUpdt){#dont touch if necessary for dimmer
        if(($err&0x70) == 0x10 || ($err&0x70) == 0x20){
          my $wt = $shash->{helper}{stateUpdatDly}
                         ?$shash->{helper}{stateUpdatDly}
                         :120;
          CUL_HM_stateUpdatDly($name,$wt);
        }
        else {
          CUL_HM_unQEntity($name,"qReqStat");
        }
        delete $shash->{helper}{stateUpdatDly};
      }
 
      if ($st eq "dimmer"){
        push @evtEt,[$shash,1,"overload:".(($err&0x02)?"on":"off")];
        push @evtEt,[$shash,1,"overheat:".(($err&0x04)?"on":"off")];
        push @evtEt,[$shash,1,"reduced:" .(($err&0x08)?"on":"off")];
         #hack for blind  - other then behaved devices blind does not send
         #        a status info for chan 0 at power on
         #        chn3 (virtual chan) and not used up to now
         #        info from it is likely a power on!
        push @evtEt,[$shash,1,"powerOn:$tn"]   if($chn eq "03");
      }
      elsif ($md eq "HM-SEC-SFA-SM"){ # && $chn eq "00")
        my $h = CUL_HM_getDeviceHash($shash);
        push @evtEt,[$h,1,"powerError:"   .(($err&0x02) ? "on":"off")];
        push @evtEt,[$h,1,"sabotageError:".(($err&0x04) ? "on":"off")];
        push @evtEt,[$h,1,"battery:".(($err&0x08)?"critical":($err&0x80?"low":"ok"))];
      }
      elsif ($md =~ m /HM-LC-SW.-BA-PCB/){
        my $h = CUL_HM_getDeviceHash($shash);
        push @evtEt,[$h,1,"battery:" . (($err&0x80) ? "low" : "ok" )];
      }
    }
  }
  elsif($st =~ m /^(remote|pushButton|swi)$/
      ||$md eq "HM-SEN-EP") { #################################################
    if($mTp eq "40") {
      my ($chn) = map{hex($_)} ($mI[0]);# button/event count 
      my $btnName;
      my $bat   = ($chn&0x80)?"low":"ok";
      my $type  = ($chn & 0x40)?"l":"s";
      my $state = ($chn & 0x40)?"Long":"Short";
      $chn = $chn & 0x3f;
      my $chnHash = $modules{CUL_HM}{defptr}{$src.sprintf("%02X",$chn)};

      if ($chnHash){# use userdefined name - ignore irritating on-off naming
        $btnName = $chnHash->{NAME};
      }
      else{# Button not defined, use default naming
        $chnHash = $shash;
        $btnName = "Btn$chn";
      }
      if($type eq "l"){# long press
        $state .= ($mFlgH & 0x20 ? "Release" : "");
      }

      push @evtEt,[$devH,1,"battery:$bat"];
      push @evtEt,[$devH,1,"state:$btnName $state"];
      if($md eq "HM-Dis-WM55"){
        if ($devH->{cmdStack}){# there are pending commands. we only send new ones
          delete $devH->{cmdStack};
          delete $devH->{cmdStacAESPend};
          delete $devH->{helper}{prt}{rspWait};
          delete $devH->{helper}{prt}{rspWaitSec};
          delete $devH->{helper}{prt}{mmcA};
          delete $devH->{helper}{prt}{mmcS};
          delete $devH->{lastMsg};
        }

        CUL_HM_calcDisWm($chnHash,$devH->{NAME},$type);
        if (CUL_HM_getAttrInt($name,"aesCommReq") == 1){
          my @arr = ();
          $devH->{cmdStacAESPend} = \@arr;
          push (@{$devH->{cmdStacAESPend} },"$src;++A011$id$src$_")
                foreach (@{$chnHash->{helper}{disp}{$type}});
       }
        else{
          CUL_HM_PushCmdStack($shash,"++A011$id$src$_")
                foreach (@{$chnHash->{helper}{disp}{$type}});
        }
      }
    }
    else{# could be an Em8
      my($chn,$cnt,$state,$err);
      if($mTp eq "41"){
        ($chn,$cnt,$state)=(hex($mI[0]),$mI[1],$mI[2]);
        my $err = $chn & 0x80;
        $chn = sprintf("%02X",$chn & 0x3f);
        $shash = $modules{CUL_HM}{defptr}{"$src$chn"}
                               if($modules{CUL_HM}{defptr}{"$src$chn"});
        push @evtEt,[$devH,1,"battery:". ($err?"low"  :"ok"  )];
      }
      elsif(($mTp eq "10" && $mI[0] eq "06") ||
            ($mTp eq "02" && $mI[0] eq "01")) {
        ($chn,$state,$err) = (hex($mI[1]), $mI[2], hex($mI[3]));
        $chn = sprintf("%02X",$chn&0x3f);
        $shash = $modules{CUL_HM}{defptr}{"$src$chn"}
                               if($modules{CUL_HM}{defptr}{"$src$chn"});
        push @evtEt,[$devH,1,"alive:yes"];
        push @evtEt,[$devH,1,"battery:". (($err&0x80)?"low"  :"ok"  )];
      }
      if (defined($state) && $chn ne "00"){# if state was detected post events
        my $txt;
        if    ($shash->{helper}{lm} && $shash->{helper}{lm}{hex($state)}){$txt = $shash->{helper}{lm}{hex($state)}}
        elsif ($lvlStr{md}{$md}){$txt = $lvlStr{md}{$md}{$state}}
        elsif ($lvlStr{st}{$st}){$txt = $lvlStr{st}{$st}{$state}}
        else                    {$txt = "unknown:$state"}
      
        push @evtEt,[$shash,1,"state:$txt"];
        push @evtEt,[$shash,1,"contact:$txt$target"];
      }
    }

  }
  elsif($st eq "powerSensor") {################################################
    if (($mTyp eq "0201") ||  # handle Ack_Status
        ($mTyp eq "1006")) {  #    or Info_Status message here

      my ($chn,$val,$err) = (hex($mI[1]),hex($mI[2])/2,hex($mI[3]));
      $chn = sprintf("%02X",$chn&0x3f);
      my $chId = $src.$chn;
      $shash = $modules{CUL_HM}{defptr}{$chId}
                             if($modules{CUL_HM}{defptr}{$chId});
                             
      push @evtEt,[$devH,1,"battery:".(($err&0x80)?"low"  :"ok"  )];

      push @evtEt,[$shash,1,"state:$val"];
    }
    elsif ($mTp eq "53" ||$mTp eq "54" ) {  #    Gas_EVENT_CYCLIC
      $shash = $modules{CUL_HM}{defptr}{$src."01"}
                             if($modules{CUL_HM}{defptr}{$src."01"});
      my ($eCnt,$P) = map{hex($_)} unpack 'A8A6',$p;
      $eCnt = ($eCnt&0x7fffffff)/1000;       #0.0  ..2147483.647 m3
      $P = $P   /1000;                       #0.0  ..16777.215 m3
      push @evtEt,[$shash,1,"gasCnt:"   .$eCnt];
      push @evtEt,[$shash,1,"gasPower:"    .$P];    
      my $sumState = "eState:E: $eCnt P: $P";
      push @evtEt,[$shash,1,$sumState];    
      push @evtEt,[$shash,1,"boot:"     .(($eCnt&0x800000)?"on":"off")];
      if($eCnt == 0 && hex($mNo) < 3 ){
        push @evtEt,[$devH,1,"powerOn:$tn"];
        my $eo = ReadingsVal($shash->{NAME},"gasCnt",0)+
                 ReadingsVal($shash->{NAME},"gasCntOffset",0);
        push @evtEt,[$shash,1,"gasCntOffset:".$eo];
      }
    }
    elsif ($mTp eq "5E" ||$mTp eq "5F" ) {  #    POWER_EVENT_CYCLIC
      $shash = $modules{CUL_HM}{defptr}{$src."02"}
                             if($modules{CUL_HM}{defptr}{$src."02"});
      my ($eCnt,$P,$I,$U,$F) = map{hex($_)} unpack 'A6A6A4A4A2',$p;
      $eCnt = ($eCnt&0x7fffff)/10;          #0.0  ..838860.7  Wh
      $P = $P   /100;                       #0.0  ..167772.15 W
      
      push @evtEt,[$shash,1,"energy:"   .$eCnt];
      push @evtEt,[$shash,1,"power:"    .$P];    

      my $sumState = "eState:E: $eCnt P: $P";
      if (defined $I){
        $I = $I   /1;                         #0.0  ..65535.0   mA
        push @evtEt,[$shash,1,"current:"  .$I];   
        push @evtEt,[$defs{$devH->{channel_04}},1,"state:$I"   ] if ($devH->{channel_04});
        $sumState .= " I: $I";        
      }
      if (defined $U){
        $U = $U   /10;                        #0.0  ..6553.5    mV
        push @evtEt,[$shash,1,"voltage:"  .$U];    
        push @evtEt,[$defs{$devH->{channel_05}},1,"state:$U"   ] if ($devH->{channel_05});
        $sumState .= " U: $U";        
      }
      if (defined $F){
        $F -= 256 if ($F > 127);
        $F = $F/100+50;                      # 48.72..51.27     Hz
        push @evtEt,[$shash,1,"frequency:".$F];
        push @evtEt,[$defs{$devH->{channel_06}},1,"state:$F"   ] if ($devH->{channel_06});
        $sumState .= " f: $F";        
      }
      
      push @evtEt,[$shash,1,$sumState];    
      push @evtEt,[$shash,1,"boot:"     .(($eCnt&0x800000)?"on":"off")];
      
      push @evtEt,[$defs{$devH->{channel_02}},1,"state:$eCnt"] if ($devH->{channel_02});
      push @evtEt,[$defs{$devH->{channel_03}},1,"state:$P"   ] if ($devH->{channel_03});

      my $el = ReadingsVal($shash->{NAME},"energy",0);# get Energy last
      my $eo = ReadingsVal($shash->{NAME},"energyOffset",0);
      if($eCnt == 0 && hex($mNo) < 3 ){
        push @evtEt,[$devH,1,"powerOn:$tn"];
        $eo += $el;
        push @evtEt,[$shash,1,"energyOffset:".$eo];
      }
      elsif($el > 800000 && $el < $eCnt ){# handle overflow
        $eo += 838860.7;
        push @evtEt,[$shash,1,"energyOffset:".$eo];
      }
      push @evtEt,[$shash,1,"energyCalc:".($eo + $eCnt)];
    }
  }
  elsif($st eq "powerMeter") {#################################################
    if (($mTyp eq "0201") ||  # handle Ack_Status
        ($mTyp eq "1006")) {  #    or Info_Status message here

      my ($chn,$val,$err) = (hex($mI[1]),hex($mI[2])/2,hex($mI[3]));
      $chn = sprintf("%02X",$chn&0x3f);
      my $chId = $src.$chn;
      $shash = $modules{CUL_HM}{defptr}{$chId}
                             if($modules{CUL_HM}{defptr}{$chId});
      my $vs = ($val==100 ? "on":($val==0 ? "off":"$val %")); # user string...

      push @evtEt,[$shash,1,"level:$val"];
      push @evtEt,[$shash,1,"pct:$val"]; # duplicate to level - necessary for "slider"
      push @evtEt,[$shash,1,"deviceMsg:$vs$target"] if($chn ne "00");
      push @evtEt,[$shash,1,"state:$vs"];
      push @evtEt,[$shash,1,"timedOn:".(($err&0x40)?"running":"off")];
    }
    elsif ($mTp eq "5E" ||$mTp eq "5F" ) {  #    POWER_EVENT_CYCLIC
      $shash = $modules{CUL_HM}{defptr}{$src."02"}
                             if($modules{CUL_HM}{defptr}{$src."02"});
      my ($eCnt,$P,$I,$U,$F) = map{hex($_)} unpack 'A6A6A4A4A2',$p;
      $eCnt = ($eCnt&0x7fffff)/10;          #0.0  ..838860.7  Wh
      $P = $P   /100;                       #0.0  ..167772.15 W
      $I = $I   /1;                         #0.0  ..65535.0   mA
      $U = $U   /10;                        #0.0  ..6553.5    mV
      $F -= 256 if ($F > 127);
      $F = $F/100+50;                      # 48.72..51.27     Hz
      
      push @evtEt,[$shash,1,"energy:"   .$eCnt];
      push @evtEt,[$shash,1,"power:"    .$P];    
      push @evtEt,[$shash,1,"current:"  .$I];    
      push @evtEt,[$shash,1,"voltage:"  .$U];    
      push @evtEt,[$shash,1,"frequency:".$F];
      push @evtEt,[$shash,1,"eState:E: $eCnt P: $P I: $I U: $U f: $F"];    
      push @evtEt,[$shash,1,"boot:"     .(($eCnt&0x800000)?"on":"off")];
      
      push @evtEt,[$defs{$devH->{channel_02}},1,"state:$eCnt"] if ($devH->{channel_02});
      push @evtEt,[$defs{$devH->{channel_03}},1,"state:$P"   ] if ($devH->{channel_03});
      push @evtEt,[$defs{$devH->{channel_04}},1,"state:$I"   ] if ($devH->{channel_04});
      push @evtEt,[$defs{$devH->{channel_05}},1,"state:$U"   ] if ($devH->{channel_05});
      push @evtEt,[$defs{$devH->{channel_06}},1,"state:$F"   ] if ($devH->{channel_06});
      
      my $el = ReadingsVal($shash->{NAME},"energy",0);# get Energy last
      my $eo = ReadingsVal($shash->{NAME},"energyOffset",0);
      if($eCnt == 0 && hex($mNo) < 3 ){
        push @evtEt,[$devH,1,"powerOn:$tn"];
        $eo += $el;
        push @evtEt,[$shash,1,"energyOffset:".$eo];
      }
      elsif($el > 800000 && $el < $eCnt ){# handle overflow
        $eo += 838860.7;
        push @evtEt,[$shash,1,"energyOffset:".$eo];
      }
      push @evtEt,[$shash,1,"energyCalc:".($eo + $eCnt)];
    }
  }
  elsif($st eq "repeater"){ ###################################################
    if (($mTp eq "02" && $p =~ m/^01/) ||  # handle Ack_Status
        ($mTp eq "10" && $p =~ m/^06/)) {  #or Info_Status message here
      my ($state,$err) = ($1,hex($2)) if ($p =~ m/^....(..)(..)/);
      # not sure what level are possible
      push @evtEt,[$shash,1,"state:".($state eq '00'?"ok":"level:".$state)];
      push @evtEt,[$shash,1,"battery:".   (($err&0x80)?"low"  :"ok"  )];
      my $flag = ($err>>4) &0x7;
      push @evtEt,[$shash,1,"flags:".     (($flag)?"none"     :$flag  )];
    }
  }
  elsif($st eq "virtual" && $md =~ m/^virtual_/){ #############################
    # possibly add code to count all acks that are paired.
    if($mTp eq "02") {# this must be a reflection from what we sent, ignore
      push @evtEt,[$shash,1,""];
    }
    elsif ($mTp =~ m /^4[01]/){# if channel is SD team we have to act
      CUL_HM_parseSDteam($mTp,$src,$dst,$p);
    }
  }
  elsif($st eq "outputUnit"){ #################################################
    if($mTp eq "40" && @mI == 2){
      my ($button, $bno) = (hex($mI[0]), hex($mI[1]));
      if(!(exists($shash->{BNO})) || $shash->{BNO} ne $bno){
        $shash->{BNO}=$bno;
          $shash->{BNOCNT}=1;
      }
      else{
        $shash->{BNOCNT}+=1;
      }
      my $btn = int($button&0x3f);
      push @evtEt,[$shash,1,"state:Btn$btn on$target"];
    }
    elsif(($mTp eq "02" && $mI[0] eq "01") ||   # handle Ack_Status
          ($mTp eq "10" && $mI[0] eq "06")){    #    or Info_Status message
      my ($msgChn,$msgState) = ((hex($mI[1])&0x1f),$mI[2]) if (@mI > 2);
      my $chnHash = $modules{CUL_HM}{defptr}{$src.sprintf("%02X",$msgChn)};
      $chnHash = $shash if(!$chnHash && $msgChn && $msgChn == 1);
      if ($md eq "HM-OU-LED16") {
        #special: all LEDs map to device state
        my $devState = ReadingsVal($name,"color","00000000");
        if($parse eq "powerOn"){# reset LEDs after power on
          CUL_HM_PushCmdStack($shash,'++A011'.$ioId.$src."8100".$devState);
          CUL_HM_ProcessCmdStack($shash);
          # no event necessary, all the same as before
        }
        else {# just update datafields in storage
          if (@mI > 8){#status for all channel included
            # open to decode byte $mI[4] - related to backlight? seen 20 and 21
            my $lStat = join("",@mI[5..8]); # all LED status in one long
            my %colTbl=("00"=>"off","01"=>"red","10"=>"green","11"=>"orange");
            my @leds = reverse(unpack('(A2)*',sprintf("%032b",hex($lStat))));
            $_ = $colTbl{$_} foreach (@leds);
            for(my $cCnt = 0;$cCnt<16;$cCnt++){# go for all channels
              my $cH = $modules{CUL_HM}{defptr}{$src.sprintf("%02X",$cCnt+1)};
              next if (!$cH);
              if (ReadingsVal($cH->{NAME},"state","") ne $leds[$cCnt]) {
                push @evtEt,[$cH,1,"color:$leds[$cCnt]"];
                push @evtEt,[$cH,1,"state:$leds[$cCnt]"];
              }
            }
            push @evtEt,[$shash,1,"color:$lStat"];
            push @evtEt,[$shash,1,"state:$lStat"];
          }
          else{# branch can be removed if message is always that long
            my $bitLoc = ($msgChn-1)*2;#calculate bit location
            my $mask = 3<<$bitLoc;
            my $value = sprintf("%08X",(hex($devState) &~$mask)|($msgState<<$bitLoc));
            push @evtEt,[$shash,1,,"color:$value"];
            push @evtEt,[$shash,1, "state:$value"];
            if ($chnHash){
               $shash = $chnHash;
               my %colorTable=("00"=>"off","01"=>"red","02"=>"green","03"=>"orange");
               my $actColor = $colorTable{$msgState};
               $actColor = "unknown" if(!$actColor);
              push @evtEt,[$shash,1,"color:$actColor"];
              push @evtEt,[$shash,1,"state:$actColor"];
            }
           }
        }
      }
#      elsif ($md eq "HM-OU-CFM-PL"){
      else{
        if ($chnHash){
          $shash = $chnHash;
          my $val = hex($mI[2])/2;
          $val = ($val == 100 ? "on" : ($val == 0 ? "off" : "$val %"));
          push @evtEt,[$shash,1,"state:$val"];
        }
      }
    }
  }
  elsif($st =~ m /^(motionDetector|motionAndBtn)$/) { #########################
    my $state = $mI[2];
    if(($mTp eq "10" ||$mTp eq "02") && $p =~ m/^06....../) {
      my ($chn,$err,$bright)=(hex($mI[1]),hex($mI[3]),hex($mI[2]));
      my $chId = $src.sprintf("%02X",$chn&0x3f);
      $shash = $modules{CUL_HM}{defptr}{$chId}
                             if($modules{CUL_HM}{defptr}{$chId});
      push @evtEt,[$shash,1,"brightness:".$bright];
      if ($md eq "HM-Sec-MDIR"){
        push @evtEt,[$shash,1,"sabotageError:".(($err&0x0E)?"on":"off")];
      }
      else{
        push @evtEt,[$shash,1,"cover:".        (($err&0x0E)?"open" :"closed")];
      }
      push @evtEt,[$shash,1,"battery:".   (($err&0x80)?"low"  :"ok"  )];
    }
    elsif($mTp eq "41") {#01 is channel
      my($chn,$cnt,$bright) = (hex($mI[0]),hex($mI[1]),hex($mI[2]));
      my $nextTr = (@mI >3)? (int((1<<((hex($mI[3])>>4)-1))/1.1)."s")
                           : "-";
      my $chId = $src.sprintf("%02X",$chn&0x3f);
      $shash = $modules{CUL_HM}{defptr}{$chId}
                             if($modules{CUL_HM}{defptr}{$chId});
                             
      push @evtEt,[$shash,1,"state:motion"];
      push @evtEt,[$shash,1,"motion:on$target"];
      push @evtEt,[$shash,1,"motionCount:$cnt"."_next:$nextTr"];
      push @evtEt,[$shash,1,"brightness:$bright"];
    }
    elsif($mTp eq "70" && $p =~ m/^7F(..)(.*)/) {
      my($d1, $d2) = ($1, $2);
      push @evtEt,[$shash,1,"devState_raw$d1:$d2"];
      $state = 0;
    }

    if($ioId eq $dst && $mFlgH&0x20 && $state){
      push @ack,$shash,$mNo."8002".$ioId.$src."0101${state}00";
    }
  }
  elsif($st eq "smokeDetector") { #############################################
    #Info Level: mTp=0x10 p(..)(..)(..) subtype=06, channel, state (1 byte)
    #Event:      mTp=0x41 p(..)(..)(..) channel   , unknown, state (1 byte)

    if ($mTp eq "10" && $p =~ m/^06..(..)(..)/) {
       # m:A0 A010 233FCE 1743BF 0601 01  00 31
      my ($state,$err) = (hex($1),hex($2));
      push @evtEt,[$devH ,1,"battery:"     .(($err&0x80)?"low"     :"ok")];
      push @evtEt,[$shash,1,"level:"  .hex($state)];
      $state = (($state < 2)?"off":"smoke-Alarm");
      push @evtEt,[$shash,1,"state:$state"];
      push @evtEt,[$devH ,1,"powerOn:$tn"] if(length($p) == 8 && $mNo eq "00");
      if ($md eq "HM-SEC-SD-2"){
        push @evtEt,[$shash,1,"alarmTest:"   .(($err&0x02)?"failed"  :"ok")];
        push @evtEt,[$shash,1,"smokeChamber:".(($err&0x04)?"degraded":"ok")];
      }
      my $tName = ReadingsVal($name,"peerList","");#inform team
      $tName =~ s/,.*//;
      CUL_HM_updtSDTeam($tName,$name,$state);
    }
    elsif ($mTp =~ m /^4[01]/){ #autonomous event
      CUL_HM_parseSDteam($mTp,$src,$dst,$p);
    }
    elsif ($mTp eq "01"){ #Configs
      my $sType = substr($p,0,2);
      if   ($sType eq "01"){# add peer to group
        push @evtEt,[$shash,1,"SDteam:add_$dname"];
      }
      elsif($sType eq "02"){# remove from group
        push @evtEt,[$shash,1,"SDteam:remove_".$dname];
      }
      elsif($sType eq "05"){# set param List 3 and 4
        push @evtEt,[$shash,1,""];
      }
    }
    else{
      push @evtEt,[$shash,1,"SDunknownMsg:$p"] if(!@evtEt);
    }

    if($ioId eq $dst && ($mFlgH&0x20)){  # Send Ack/Nack
      push @ack,$shash,$mNo."8002".$ioId.$src.($mFlg.$mTp eq "A001" ? "80":"00");
    }
  }
  elsif($st eq "threeStateSensor") { ##########################################
    #Event:      mTp=0x41 p(..)(..)(..)     channel   , unknown, state
    #Info Level: mTp=0x10 p(..)(..)(..)(..) subty=06, chn, state,err (3bit)
    #AckStatus:  mTp=0x02 p(..)(..)(..)(..) subty=01, chn, state,err (3bit)
    my ($chn,$state,$err,$cnt); #define locals
    if(($mTp eq "10" && $p =~ m/^06/) ||
       ($mTp eq "02" && $p =~ m/^01/)) {
      $p =~ m/^..(..)(..)(..)?$/;
      ($chn,$state,$err) = (hex($1), $2, hex($3));
      $chn = sprintf("%02X",$chn&0x3f);
      $shash = $modules{CUL_HM}{defptr}{"$src$chn"}
                             if($modules{CUL_HM}{defptr}{"$src$chn"});
      push @evtEt,[$devH,1,"alive:yes"];
      push @evtEt,[$devH,1,"battery:". (($err&0x80)?"low"  :"ok"  )];
      if (  $md =~ m/^(HM-SEC-SC.*|HM-Sec-RHS|Roto_ZEL-STG-RM-F.K)$/){
                                 push @evtEt,[$devH,1,"sabotageError:".(($err&0x0E)?"on"   :"off")];}
      elsif($md ne "HM-SEC-WDS"){push @evtEt,[$devH,1,"cover:"        .(($err&0x0E)?"open" :"closed")];}
    }
    elsif($mTp eq "41"){
      ($chn,$cnt,$state)=(hex($1),$2,$3) if($p =~ m/^(..)(..)(..)/);
      my $err = $chn & 0x80;
      $chn = sprintf("%02X",$chn & 0x3f);
      $shash = $modules{CUL_HM}{defptr}{"$src$chn"}
                             if($modules{CUL_HM}{defptr}{"$src$chn"});
      push @evtEt,[$devH,1,"battery:". ($err?"low"  :"ok"  )];
    }
    if (defined($state)){# if state was detected post events
      my $txt;
      if    ($shash->{helper}{lm} && $shash->{helper}{lm}{hex($state)}){$txt = $shash->{helper}{lm}{hex($state)}}
      elsif ($lvlStr{md}{$md}){$txt = $lvlStr{md}{$md}{$state}}
      elsif ($lvlStr{st}{$st}){$txt = $lvlStr{st}{$st}{$state}}
      else                    {$txt = "unknown:$state"}

      push @evtEt,[$shash,1,"state:$txt"];
      push @evtEt,[$shash,1,"contact:$txt$target"];
    }
    elsif(!@evtEt){push @evtEt,[$devH,1,"3SSunknownMsg:$p"];}
  }
  elsif($st eq "winMatic") {  #################################################
    my($sType,$chn,$lvl,$stat) = @mI;
    if(($mTp eq "10" && $sType eq "06") ||
       ($mTp eq "02" && $sType eq "01")){
      $shash = $modules{CUL_HM}{defptr}{"$src$chn"}
                             if($modules{CUL_HM}{defptr}{"$src$chn"});
      # stateflag meaning unknown
      push @evtEt,[$shash,1,"state:".(($lvl eq "FF")?"locked":((hex($lvl)/2)))];
      if ($chn eq "01"){
        my %err = (0=>"ok",1=>"TurnError",2=>"TiltError");
        my %dir = (0=>"no",1=>"up",2=>"down",3=>"undefined");
        push @evtEt,[$shash,1,"motorErr:"  .$err{(hex($stat)>>1)&0x03}];
        push @evtEt,[$shash,1,"direction:" .$dir{(hex($stat)>>4)&0x03}];
      }
      else{ #should be akku
        my %statF = (0=>"trickleCharge",1=>"charge",2=>"dischange",3=>"unknown");
        push @evtEt,[$shash,1,"charge:".$statF{(hex($stat)>>4)&0x03}];
      }
    }
#    if ($p =~ m/^0287(..)89(..)8B(..)/) {
#      my ($air, $course) = ($1, $3);
#      push @evtEt,[$shash,1,"airing:".($air eq "FF" ? "inactiv" : CUL_HM_decodeTime8($air))];
#      push @evtEt,[$shash,1,"course:".($course eq "FF" ? "tilt" : "close")];
#    }
#    elsif($p =~ m/^0201(..)03(..)04(..)05(..)07(..)09(..)0B(..)0D(..)/) {
#      my ($flg1, $flg2, $flg3, $flg4, $flg5, $flg6, $flg7, $flg8) =
#         ($1, $2, $3, $4, $5, $6, $7, $8);
#      push @evtEt,[$shash,1,"airing:".($flg5 eq "FF" ? "inactiv" : CUL_HM_decodeTime8($flg5))];
#      push @evtEt,[$shash,1,"contact:tesed"];
#    }
  }
  elsif($st eq "keyMatic") {  #################################################
    #Info Level: mTp=0x10 p(..)(..)(..)(..) subty=06, chn, state,err (3bit)
    #AckStatus:  mTp=0x02 p(..)(..)(..)(..) subty=01, chn, state,err (3bit)

    if(($mTyp eq "1006") ||
       ($mTyp eq "0201")) {
      my ($chn,$val, $err) = ($mI[1],hex($mI[2]), hex($mI[3]));
      $shash = $modules{CUL_HM}{defptr}{"$src$chn"}
                             if($modules{CUL_HM}{defptr}{"$src$chn"});

      my $stErr = ($err >>1) & 0x7;
      my $error = 'unknown_'.$stErr;
      $error = 'motor aborted'  if ($stErr == 2);
      $error = 'clutch failure' if ($stErr == 1);
      $error = 'none'           if ($stErr == 0);
      my %dir = (0=>"none",1=>"up",2=>"down",3=>"undef");
      my $state = "";
      RemoveInternalTimer ($name."uncertain:permanent");
      CUL_HM_unQEntity($name,"qReqStat");
      if ($err & 0x30) { # uncertain - we have to check
        CUL_HM_stateUpdatDly($name,13) if(ReadingsVal($name,"uncertain","no") eq "no");
        InternalTimer(gettimeofday()+20,"CUL_HM_readValIfTO", $name.":uncertain:permanent", 0);
        $state = " (uncertain)";
      }
      push @evtEt,[$shash,1,"unknown:40"] if($err&0x40);
      push @evtEt,[$shash,1,"battery:"   .(($err&0x80) ? "low":"ok")];
      push @evtEt,[$shash,1,"uncertain:" .(($err&0x30) ? "yes":"no")];
      push @evtEt,[$shash,1,"direction:" .$dir{($err>>4)&3}];
      push @evtEt,[$shash,1,"error:" .    ($error)];
      push @evtEt,[$shash,1,"lock:"  .   (($val == 1) ? "unlocked" : "locked")];
      push @evtEt,[$shash,1,"state:" .   (($val == 1) ? "unlocked" : "locked") . $state];
    }
  }
  elsif($md eq "CCU-FHEM") {  #################################################
    push @evtEt,[$shash,1,""];
  }
  elsif (eval "defined(&CUL_HM_Parse$st)"){####################################
    no strict "refs";
    my @ret = &{"CUL_HM_Parse$st"}($mFlg,$mTp,$src,$dst,$p,$target);
    use strict "refs";
    push @evtEt,@ret;
  }
  else{########################################################################
    ; # no one wants the message
  }

  #------------ parse if FHEM or virtual actor is destination   ---------------

  if(   AttrVal($dname, "subType", "none") eq "virtual"
     && AttrVal($dname, "model", "none") =~ m/^virtual_/){# see if need for answer
    my $sendAck = 0;
    if($mTp =~ m/^4/ && @mI > 1) { #Push Button event
      my ($recChn,$trigNo) = (hex($mI[0]),hex($mI[1]));# button number/event count
      my $longPress = ($recChn & 0x40)?"long":"short";
      my $recId = $src.sprintf("%02X",($recChn&0x3f));
      foreach my $dChId (CUL_HM_getAssChnIds($dname)){# need to check all chan
        next if (!$modules{CUL_HM}{defptr}{$dChId});
        my $dChNo = substr($dChId,6,2);
        my $dChName = CUL_HM_id2Name($dChId);
        if(($attr{$dChName}{peerIDs}?$attr{$dChName}{peerIDs}:"") =~m/$recId/){
          my $dChHash = $defs{$dChName};
          $sendAck = 1;
          $dChHash->{helper}{trgLgRpt} = 0
                if (!defined($dChHash->{helper}{trgLgRpt}));
          $dChHash->{helper}{trgLgRpt} +=1;
          my $trgLgRpt = $dChHash->{helper}{trgLgRpt};

          my ($stT,$stAck) = ("ack","00");#state text and state Ack for Msg
          if (AttrVal($dChName,"param","") !~ m/noOnOff/){
            $stT  = ReadingsVal($dChName,"virtActState","OFF");
            $stT = ($stT eq "OFF")?"ON":"OFF" 
                if ($trigNo ne ReadingsVal($dChName,"virtActTrigNo","0"));
            $stAck = '01'.$dChNo.(($stT eq "ON")?"C8":"00")."00"
          }
          
          if ($mFlgH & 0x20){
            $longPress .= "_Release";
            $dChHash->{helper}{trgLgRpt}=0;
            push @ack,$shash,$mNo."8002".$dst.$src.$stAck;
          }
          push @evtEt,[$dChHash,1,"state:$stT"];
          push @evtEt,[$dChHash,1,"virtActState:$stT"];
          push @evtEt,[$dChHash,1,"virtActTrigger:".CUL_HM_id2Name($recId)];
          push @evtEt,[$dChHash,1,"virtActTrigType:$longPress"];
          push @evtEt,[$dChHash,1,"virtActTrigRpt:$trgLgRpt"];
          push @evtEt,[$dChHash,1,"virtActTrigNo:$trigNo"];
        }
      }
    }
    elsif($mTp eq "58" && $p =~ m/^(..)(..)/) {# climate event
      my ($d1,$vp) =($1,hex($2)); # adjust_command[0..4] adj_data[0..250]
      $vp = int($vp/2.56+0.5);    # valve position in %
      my $chnHash = $modules{CUL_HM}{defptr}{$dst."01"};
      $chnHash = $dstH if (!$chnHash);
      push @evtEt,[$chnHash,1,"ValvePosition:$vp %"];
      push @evtEt,[$chnHash,1,"ValveAdjCmd:".$d1];
      push @ack,$chnHash,$mNo."8002".$dst.$src.'0101'.
                         sprintf("%02X",$vp*2)."0000";
    }
    elsif($mTp eq "02"){
      if ($dstH->{helper}{prt}{rspWait}{mNo}             &&
          $dstH->{helper}{prt}{rspWait}{mNo} eq $mNo ){
        #ack we waited for - stop Waiting
        CUL_HM_respPendRm($dstH);
      }
    }
    else{
      $sendAck = 1;
    }
    push @ack,$dstH,$mNo."8002".$dst.$src."00" if ($mFlgH & 0x20 && (!@ack) && $sendAck);
  }
  elsif($ioId eq $dst){# if fhem is destination check if we need to react
    if($mTp =~ m/^4./ &&  #Push Button event
       ($mFlgH & 0x20)){  #response required Flag
                # fhem CUL shall ack a button press
      if ($md =~ m/^(HM-SEC-SC.*|Roto_ZEL-STG-RM-FFK)$/){# SCs - depending on FW version - do not accept ACK only. Especially if peered
        push @ack,$shash,$mNo."8002".$dst.$src."0101".((hex($mI[0])&1)?"C8":"00")."00";
      }
      else{
        push @ack,$shash,$mNo."8002$dst$src"."00";
      }
      Log3 $name,5,"CUL_HM $name prep ACK for $mI[0]";
    }
  }

  #------------ send default ACK if not applicable------------------
  #    ack if we are destination, anyone did accept the message (@evtEt)
  #        parser did not supress
  push @ack,$shash, $mNo."8002".$ioId.$src."00"
      if(   ($ioId eq $dst)   #are we adressee
         && ($mFlgH & 0x20)   #response required Flag
         && @evtEt            #only ack if we identified it
         && (!@ack)           #sender requested ACK
         );
  if (@ack) {# send acks and store for repeat
    $devH->{helper}{rpt}{IO}  = $ioName;
    $devH->{helper}{rpt}{flg} = substr($msg,5,1);
    $devH->{helper}{rpt}{ack} = \@ack;
    $devH->{helper}{rpt}{ts}  = gettimeofday();
    my $i=0;
    my $rr = $respRemoved;
    CUL_HM_SndCmd($ack[$i++],$ack[$i++])while ($i<@ack);
    $respRemoved = $rr;
    Log3 $name,5,"CUL_HM $name sent ACK:".(int(@ack));
  }
  CUL_HM_ProcessCmdStack($shash) if ($respRemoved); # cont if complete
  CUL_HM_sndIfOpen(".x:".$ioName);
  
  #------------ process events ------------------
  push @evtEt,[$shash,1,"noReceiver:src:$src ".$mFlg.$mTp." $p"] 
        if(!@entities && !@evtEt);
  push @entities,CUL_HM_pushEvnts();
  @entities = CUL_HM_noDup(@entities,$shash->{NAME});
  $defs{$_}{".noDispatchVars"} = 1 foreach (grep !/^$devH->{NAME}$/,@entities);
  return @entities;
}
sub CUL_HM_parseCommon(@){#####################################################
  # parsing commands that are device independent
  my ($ioHash,$mNo,$mFlg,$mTp,$src,$dst,$p,$st,$md,$dname) = @_;
  my $shash = $modules{CUL_HM}{defptr}{$src};
  my $dstH = $modules{CUL_HM}{defptr}{$dst} if (defined $modules{CUL_HM}{defptr}{$dst});
  return "" if(!$shash->{DEF});# this should be from ourself
  my $ret = "";
  my $rspWait = $shash->{helper}{prt}{rspWait};
  my $pendType = $rspWait->{Pending} ? $rspWait->{Pending} : "";
  #------------ parse message flag for start processing command Stack
  # TC wakes up with 8270, not with A258
  # VD wakes up with 8202
  #                  9610
  my $rxt = CUL_HM_getRxType($shash);
  my $mFlgH = hex($mFlg);
  if($rxt & 0x08){ #wakeup device
    if(($mFlgH & 0xA2) == 0x82){ #wakeup signal
      CUL_HM_appFromQ($shash->{NAME},"wu");# stack cmds if waiting
      if ($shash->{cmdStack}){
        CUL_HM_SndCmd($shash, '++A112'.CUL_HM_IoId($shash).$src);
        CUL_HM_ProcessCmdStack($shash);
      }
    }
    elsif($shash->{helper}{prt}{sProc} != 1){ # no wakeup signal, 
      # this is an autonom message send ACK but dont process further
      $shash->{helper}{prt}{sleeping} = 1 if($mFlgH & 0x20) ;
    }
  }
  if($rxt & 0x10 && $shash->{helper}{prt}{sleeping}){ # lazy config
    if($mFlgH & 0x02                  #wakeup device
       && $defs{$shash->{IODev}{NAME}}{TYPE} eq "HMLAN"){
      $shash->{helper}{io}{newCh} = 1 if ($shash->{helper}{prt}{sProc} == 2);
      CUL_HM_appFromQ($shash->{NAME},"cf");# stack cmds if waiting
      $shash->{helper}{prt}{sleeping} = 0;
      CUL_HM_ProcessCmdStack($shash);
    }
    else{
      $shash->{helper}{prt}{sleeping} = 1;
    }
  }  

  my $repeat;
  if   ($mTp eq "02"){# Ack/Nack/aesReq ####################
    my $subType = substr($p,0,2);
    my $reply;
    my $success;

    if ($shash->{helper}{prt}{rspWait}{brstWu}){
      if ($shash->{helper}{prt}{rspWait}{mNo} eq $mNo &&
          $subType eq "00"){
        if ($shash->{helper}{prt}{awake} && $shash->{helper}{prt}{awake}==4){#re-burstWakeup
          delete $shash->{helper}{prt}{rspWait};#clear burst-wakeup values
          $shash->{helper}{prt}{rspWait}{$_} = $shash->{helper}{prt}{rspWaitSec}{$_}
                  foreach (keys%{$shash->{helper}{prt}{rspWaitSec}});   #back to original message
          delete $shash->{helper}{prt}{rspWaitSec};
          IOWrite($shash, "", $shash->{helper}{prt}{rspWait}{cmd});     # and send
          CUL_HM_statCnt($shash->{IODev}{NAME},"s");
          #General set timer
          return "done";
        }
        $shash->{protCondBurst} = "on" if (   $shash->{protCondBurst}
                                           && $shash->{protCondBurst} !~ m/forced/);
        $shash->{helper}{prt}{awake}=2;#awake
      }
      else{
        $shash->{protCondBurst} = "off" if ($shash->{protCondBurst} !~ m/forced/);
        $shash->{helper}{prt}{awake}=3;#reject
        return "done";
      }
    }

    if   ($subType =~ m/^8/){#NACK
      #82 : peer not accepted - list full (VD)
      #84 : request undefined register
      #85 : peer not accepted - why? unknown
      $success = "no";
      CUL_HM_eventP($shash,"Nack");
      $reply = "NACK";
    }
    elsif($subType eq "01"){ #ACKinfo#################
      $success = "yes";
      my (undef,$chn,undef,undef,$rssi) = unpack '(A2)*',$p;
      my $chnHash = CUL_HM_id2Hash($src.$chn);
      push @evtEt,[$chnHash,0,"recentStateType:ack"];
      CUL_HM_storeRssi( $shash->{NAME}
                       ,($dstH?$dstH->{NAME}:$shash->{IODev}{NAME})
                       ,(-1)*(hex($rssi))
                       ,$mNo)
            if ($rssi && $rssi ne '00' && $rssi ne'80');
      $reply = "ACKStatus";
      if ($shash->{helper}{tmdOn}){
        if ((not hex(substr($p,6,2))&0x40) && # not timedOn, we have to repeat
            $shash->{helper}{tmdOn} eq substr($p,2,2) ){# virtual channels for dimmer may be incorrect
          my ($pre,$nbr,$msg) = unpack 'A4A2A*',$shash->{helper}{prt}{rspWait}{cmd};
          $shash->{helper}{prt}{rspWait}{cmd} = sprintf("%s%02X%s",
                                                    $pre,hex($nbr)+1,$msg);
          CUL_HM_eventP($shash,"TimedOn");
          $success = "no";
          $repeat = 1;
          $reply = "NACK";
        }
      }
    }
    elsif($subType eq "04"){ #ACK-AES, interim########
      my (undef,$key,$aesKeyNbr) = unpack'A2A12A2',$p;
      push @evtEt,[$shash,1,"aesKeyNbr:".$aesKeyNbr] if (defined $aesKeyNbr);# if   ($msgStat =~ m/AESKey/)
      #push @evtEt,[$shash,1,"aesCommToDev:".substr($msgStat,7)];#elsif($msgStat =~ m/AESCom/){# AES communication to central
      #$success = ""; #result not final, another response should come
      $reply = "done";
    }
    else{                    #ACK
      $success = "yes";
      $reply = "ACK";
    }

    if (   $shash->{helper}{prt}{mmcS}
        && $shash->{helper}{prt}{mmcS} == 3){
      # after write device might need a break
      # allow for wake types only - and if commands are pending
      $shash->{helper}{prt}{try} = 1 if(CUL_HM_getRxType($shash) & 0x08 #wakeup
                                         && $shash->{cmdStack});
      if ($success eq 'yes'){
        delete $shash->{helper}{prt}{mmcA};
        delete $shash->{helper}{prt}{mmcS};
      }
    };

    if($success){#do we have a final ack?
      #mark timing on the channel, not the device
      my $chn = sprintf("%02X",hex(substr($p,2,2))&0x3f);
      my $chnhash = $modules{CUL_HM}{defptr}{$chn?$src.$chn:$src};
      $chnhash = $shash if(!$chnhash);
      push @evtEt,[$chnhash,0,"CommandAccepted:$success"];
      CUL_HM_ProcessCmdStack($shash) if(CUL_HM_IoId($shash) eq $dst);
      delete $shash->{helper}{prt}{wuReSent}
              if (!$shash->{helper}{prt}{mmcS});
    }
    $ret = $reply;
  }
  elsif($mTp eq "03"){# AESack #############################
    #Reply to AESreq - only visible with CUL or in monitoring mode
    #not with HMLAN/USB
    #my $aesKey = $p;
    push @evtEt,[$shash,1,"aesReqTo:".$dstH->{NAME}] if (defined $dstH);
    $ret = "done";    
  }

  elsif($mTp eq "00"){######################################
    my $paired = 0; #internal flag
    CUL_HM_infoUpdtDevData($shash->{NAME}, $shash,$p)
                  if (!$modules{CUL_HM}{helper}{hmManualOper});
    my $ioN = $ioHash->{NAME};
    # hmPair set in IOdev or  eventually in ccu!
    my $ioOwn = InternalVal($ioN,"owner_CCU","");
    my $hmPair = InternalVal($ioN,"hmPair"      ,InternalVal($ioOwn,"hmPair"      ,0 ));
    my $hmPser = InternalVal($ioN,"hmPairSerial",InternalVal($ioOwn,"hmPairSerial",""));
    if ( $hmPair ){# pairing is active
      if (!$hmPser || $hmPser eq ReadingsVal($shash->{NAME},"D-serialNr","")){

        # pairing requested - shall we?      
        my $ioId = CUL_HM_h2IoId($ioHash);
        # pair now
        Log3 $shash,3, "CUL_HM pair: $shash->{NAME} "
                      ."$attr{$shash->{NAME}}{subType}, "
                      ."model $attr{$shash->{NAME}}{model} "
                      ."serialNr ".ReadingsVal($shash->{NAME},"D-serialNr","");
        CUL_HM_RemoveHMPair("hmPairForSec:$ioOwn");# just in case...
        delete $ioHash->{hmPair};
        delete $ioHash->{hmPairSerial};
        CUL_HM_respPendRm($shash); # remove all pending messages
        delete $shash->{cmdStack};
        delete $shash->{helper}{prt}{rspWait};
        delete $shash->{helper}{prt}{rspWaitSec};
        delete $shash->{READINGS}{"RegL_00:"};
        delete $shash->{READINGS}{".RegL_00:"};
        
        if (!$modules{CUL_HM}{helper}{hmManualOper}){
          $attr{$shash->{NAME}}{IODev} = $ioN;
          $attr{$shash->{NAME}}{IOgrp} = "$ioOwn:$ioHash->{NAME}" if($ioOwn);
          CUL_HM_assignIO($shash) ;
        }
        
        my ($idstr, $s) = ($ioId, 0xA);
        $idstr =~ s/(..)/sprintf("%02X%s",$s++,$1)/ge;
        CUL_HM_pushConfig($shash, $ioId, $src,0,0,0,0, "0201$idstr");
        
        $attr{$shash->{NAME}}{autoReadReg}= 
              AttrVal($shash->{NAME},"autoReadReg","4_reqStatus");
        CUL_HM_qAutoRead($shash->{NAME},0);
          # stack cmds if waiting. Do noch start if we have a burst device
          # it may not paire
        CUL_HM_appFromQ($shash->{NAME},"cf") if ($rxt == 0x04);
        
        $respRemoved = 1;#force command stack processing
        $paired = 1;
      }
    }

    if($paired == 0 && CUL_HM_getRxType($shash) & 0x04){#no pair -send config?
      CUL_HM_appFromQ($shash->{NAME},"cf");   # stack cmds if waiting
      my $ioId = CUL_HM_h2IoId($shash->{IODev});
      $respRemoved = 1;#force command stack processing
    }
    $ret = "done";
  }
  elsif($mTp eq "10"){######################################
    my $subType = substr($p,0,2);
    if   ($subType eq "00"){ #SerialRead====================================
      my $sn = pack("H*",substr($p,2,20));
      push @evtEt,[$shash,0,"D-serialNr:$sn"];
      $attr{$shash->{NAME}}{serialNr} = $sn;
      CUL_HM_respPendRm($shash) if ($pendType eq "SerialRead");
      $ret = "done";
    }
    elsif($subType eq "01"){ #storePeerList=================================
      my $mNoInt = hex($mNo); 
      if ($pendType eq "PeerList"  && 
          ($rspWait->{mNo} == $mNoInt || $rspWait->{mNo} == $mNoInt-1)){
        $rspWait->{mNo} = $mNoInt;

        my $chn = $shash->{helper}{prt}{rspWait}{forChn};
        my $chnhash = $modules{CUL_HM}{defptr}{$src.$chn};
        $chnhash = $shash if (!$chnhash);
        my $chnName = $chnhash->{NAME};
        my @peers;
        if($attr{$shash->{NAME}}{model} eq "HM-Dis-WM55"){
          #how ugly - this device adds one byte at begin - remove it. 
          (undef,@peers) = unpack 'A4(A8)*',$p;
        }
        else{
          (undef,@peers) = unpack 'A2(A8)*',$p;
        }

        $_ = '00000000' foreach (grep /^000000/,@peers);#correct bad term(6 chars) from rain sens)
        $chnhash->{helper}{peerIDsRaw}.= ",".join",",@peers;

        CUL_HM_ID2PeerList ($chnName,$_,1) foreach (@peers);
        if (grep /00000000/,@peers) {# last entry, peerList is complete
          # check for request to get List3 data
          my $reqPeer = $chnhash->{helper}{getCfgList};
          if ($reqPeer){
            my $flag = CUL_HM_getFlag($shash);
            my $ioId = CUL_HM_IoId($shash);
            my @peerID = split(",",(AttrVal($chnName,"peerIDs","")));
            foreach my $l (split ",",$chnhash->{helper}{getCfgListNo}){
              next if (!$l);
              my $listNo = "0".$l;
              foreach my $peer (grep (!/00000000/,@peerID)){
                $peer .="01" if (length($peer) == 6); # add the default
                if ($peer &&($peer eq $reqPeer || $reqPeer eq "all")){
                  CUL_HM_PushCmdStack($shash,sprintf("++%s01%s%s%s04%s%s",
                          $flag,$ioId,$src,$chn,$peer,$listNo));# List3 or 4
                }
              }
            }
          }
          CUL_HM_respPendRm($shash);
          delete $chnhash->{helper}{getCfgList};
          delete $chnhash->{helper}{getCfgListNo};
          CUL_HM_rmOldRegs($chnName);
        }
        else{
          CUL_HM_respPendToutProlong($shash);#wasn't last - reschedule timer
        }
        $ret = "done";
      }
      else{#response without request - discard
        $ret = "done";
      }
    }
    elsif($subType eq "02" ||$subType eq "03"){ #ParamResp==================
      my $mNoInt = hex($mNo); 
      if ( $pendType eq "RegisterRead" && 
          ($rspWait->{mNo} == $mNoInt || $rspWait->{mNo} == $mNoInt-1)){
        $repeat = 1;#prevent stop for messagenumber match
        $rspWait->{mNo} = $mNoInt;  # next message will be numbered same or one plus.       
        
        my $chnSrc = $src.$rspWait->{forChn};
        my $chnHash = $modules{CUL_HM}{defptr}{$chnSrc};
        $chnHash = $shash if (!$chnHash);
        my $chnName = $chnHash->{NAME};
        my ($format,$data) = ($1,$2) if ($p =~ m/^(..)(.*)/);
        my $list = $rspWait->{forList};
        $list = "00" if (!$list); #use the default
        if ($format eq "02"){ # list 2: format aa:dd aa:dd ...
          $data =~ s/(..)(..)/ $1:$2/g;
        }
        elsif ($format eq "03"){ # list 3: format aa:dddd
          my $addr;
          my @dataList;
          ($addr,$data) = (hex($1),$2) if ($data =~ m/(..)(.*)/);
          if ($addr == 0){
           $data = "00:00";
           push @dataList,"00:00";
          }
          else{
            $data =~s/(..)/$1:/g;
            foreach my $d1 (split(":",$data)){
              push (@dataList,sprintf("%02X:%s",$addr++,$d1));
            }
            $data = join(" ",@dataList);
          }
        }
        my $lastAddr = hex($1) if ($data =~ m/.*(..):..$/);
        my $peer = $rspWait->{forPeer};
        my $regLNp = "RegL_$list:$peer";# pure, no expert
        my $regLN = ((CUL_HM_getAttrInt($chnName,"expert") == 2)?"":".").$regLNp;
        if (   defined $lastAddr 
            && (    $lastAddr > $rspWait->{nAddr}
                 || $lastAddr == 0)){
          CUL_HM_UpdtReadSingle($chnHash,$regLN,ReadingsVal($chnName,$regLN,"")." $data",0);
          $rspWait->{nAddr} = $lastAddr;
        }

        if ($data =~ m/00:00$/){ # this was the last message in the block
          if($list eq "00"){
            my $name = CUL_HM_id2Name($src);
            push @evtEt,[$shash,0,"PairedTo:".CUL_HM_getRegFromStore($name,"pairCentral",0,"")];
          }
          CUL_HM_respPendRm($shash);
          delete $chnHash->{helper}{shadowReg}{$regLNp};   #rm shadow
          # peerChannel name from/for user entry. <IDorName> <deviceID> <ioID>
          CUL_HM_updtRegDisp($chnHash,$list,
                CUL_HM_peerChId($peer,
                        substr($chnHash->{DEF},0,6)));
          $ret = "done";
        }
        else{
          CUL_HM_respPendToutProlong($shash);#wasn't last - reschedule timer
          $ret = "done";
        }
      }
      else{#response without request - discard
        $ret = "done";
      }
    }
    elsif($subType eq "04"){ #ParamChange===================================
      my($chn,$peerID,$list,$data) = ($1,$2,$3,$4) if($p =~ m/^04(..)(........)(..)(.*)/);
      my $chnHash = $modules{CUL_HM}{defptr}{$src.$chn};
      $chnHash = $shash if(!$chnHash); # will add param to dev if no chan
      my $regLNp = "RegL_$list:".CUL_HM_id2Name($peerID);
      $regLNp =~ s/broadcast//;
      $regLNp =~ s/ /_/g; #remove blanks
      my $regLN = ((CUL_HM_getAttrInt($chnHash->{NAME},"expert") == 2)?"":".").$regLNp;

      $data =~ s/(..)(..)/ $1:$2/g;

      my $lN = ReadingsVal($chnHash->{NAME},$regLN,"");
      my $sdH = CUL_HM_shH($chnHash,$list,$dst);
      my $shdwReg = $sdH->{helper}{shadowReg}{$regLNp};
      foreach my $entry(split(' ',$data)){
        my ($a,$d) = split(":",$entry);
        last if ($a eq "00");
        if ($lN =~m/$a:/){$lN =~ s/$a:../$a:$d/;
        }else{            $lN .= " ".$entry;}
        $shdwReg =~ s/ $a:..// if ($shdwReg);# confirmed: remove from shadow
      }
      $sdH->{helper}{shadowReg}{$regLNp} = $shdwReg; # todo possibley needs change
      $lN = join(' ',sort(split(' ',$lN)));# re-order
      if ($lN =~ s/00:00//){$lN .= " 00:00"};
      CUL_HM_UpdtReadSingle($chnHash,$regLN,$lN,0);
      CUL_HM_updtRegDisp($chnHash,$list,$peerID);
      $ret= "parsed";
    }
    elsif($subType eq "06"){ #reply to status request=======================
      my (undef,$chn,undef,undef,$rssi) = unpack '(A2)*',$p;
      my $chnHash = CUL_HM_id2Hash($src.$chn);
      push @evtEt,[$chnHash,0,"recentStateType:info"];
      CUL_HM_storeRssi( $shash->{NAME}
                       ,($dstH?$dstH->{NAME}:$shash->{IODev}{NAME})
                       ,(-1)*(hex($rssi))
                       ,$mNo)
            if ($rssi && $rssi ne '00' && $rssi ne'80');
      @{$modules{CUL_HM}{helper}{qReqStat}} = grep { $_ ne $shash->{NAME} }
                                       @{$modules{CUL_HM}{helper}{qReqStat}};

      if ($pendType eq "StatusReq"){#it is the answer to our request
        my $chnSrc = $src.$shash->{helper}{prt}{rspWait}{forChn};
        my $chnhash = $modules{CUL_HM}{defptr}{$chnSrc};
        $chnhash = $shash if (!$chnhash);
        CUL_HM_respPendRm($shash);
        $ret = "STATresp";
      }
      else{
        if ($chn eq "00"
            || (   $mNo eq "00" 
                && $chn eq "01" 
                && $shash->{helper}{mRssi}{mNo} !~ m/^F/)){# this is power on
          my $name = $shash->{NAME};
          CUL_HM_qStateUpdatIfEnab($name);
          CUL_HM_qAutoRead($name,2);
          $ret = "powerOn" ;# check dst eq "000000" as well?
        }
      }
    }
  }
  elsif($mTp eq "12"){ #wakeup received - ignore############
    $ret = "done";
  }
  elsif($mTp =~ m /^4[01]/){ #someone is triggered##########
    my $chn = hex(substr($p,0,2));
    my $cnt = hex(substr($p,2,2));
    my $long = ($chn & 0x40)?"long":"short";
    $chn = $chn & 0x3f;
    my $cHash = CUL_HM_id2Hash($src.sprintf("%02X",$chn));
    my $cName = $cHash->{NAME};
    my $level = "-";
    if (length($p)>5){
      my $l = substr($p,4,2);
      if    ($cHash->{helper}{lm} && $cHash->{helper}{lm}{hex($l)}){$level = $cHash->{helper}{lm}{hex($l)}}
      elsif ($lvlStr{md}{$md}     && $lvlStr{md}{$md}{$l}    ){$level = $lvlStr{md}{$md}{$l}}
      elsif ($lvlStr{st}{$st}     && $lvlStr{st}{$st}{$l}    ){$level = $lvlStr{st}{$st}{$l}}
      else                                                    {$level = hex($l)};
    }
    elsif($mTp eq "40"){
      $level = $long;
      my $state = ucfirst($long);
      if($long eq "long"){# long press
        if(!$cHash->{BNO} || $cHash->{BNO} ne $cnt){#cnt = event counter
          $cHash->{BNO}=$cnt;
          $cHash->{BNOCNT}=0; # message counter reset
        }
        $cHash->{BNOCNT}+=1;
        $state .= ($mFlgH & 0x20 ? "Release" : "")." $cHash->{BNOCNT}_$cnt";
      }

      push @evtEt,[$cHash,1,"trigger:".(ucfirst($long))."_$cnt"];
      push @evtEt,[$cHash,1,"state:".$state." (to $dname)"] if ($shash ne $cHash);
    }
    push @evtEt,[$cHash,1,"trigger_cnt:$cnt"];

    my $peerIDs = AttrVal($cName,"peerIDs","");
    if ($peerIDs =~ m/$dst/){# dst is available in the ID list
      foreach my $peer (grep /^$dst/,split(",",$peerIDs)){
        my $pName = CUL_HM_id2Name($peer);
        next if (!$pName || !$defs{$pName});
        $pName = CUL_HM_id2Name($dst) if (!$defs{$pName}); #$dst - device-id of $peer
        push @evtEt,[$defs{$pName},1,"trig_$cName:$level"];
        push @evtEt,[$defs{$pName},1,"trigLast:$cName ".(($level ne "-")?":$level":"")];
        
        CUL_HM_stateUpdatDly($pName,10) if ($mTp eq "40");#conditional request may not deliver state-req
      }
    }
    elsif($mFlgH & 2 # dst can be garbage - but not if answer request
          && (   !$dstH 
              || $dstH->{NAME} ne InternalVal($shash->{NAME},"IODev",""))
          ){
      my $pName = CUL_HM_id2Name($dst);
      push @evtEt,[$cHash,1,"trigDst_$pName:noConfig"];
    }
    return "";
  }
  elsif($mTp eq "70"){ #Time to trigger TC##################
    #send wakeup and process command stack
  }
  if ($rspWait->{mNo}             &&
      $rspWait->{mNo} eq $mNo     &&
      !$repeat){
    #response we waited for - stop Waiting
    CUL_HM_respPendRm($shash);
  }

  return $ret;
}

sub CUL_HM_queueUpdtCfg($){
  my $name = shift;
  if ($modules{CUL_HM}{helper}{hmManualOper}){ # no update when manual operation
    delete $modules{CUL_HM}{helper}{updtCfgLst};
  }
  else{
    my @arr;
    if ($modules{CUL_HM}{helper}{updtCfgLst}){
      @arr = CUL_HM_noDup((@{$modules{CUL_HM}{helper}{updtCfgLst}}, $name));
    }
    else{
      push @arr,$name;
    }
    $modules{CUL_HM}{helper}{updtCfgLst} = \@arr;
  }
  RemoveInternalTimer("updateConfig");
  InternalTimer(gettimeofday()+5,"CUL_HM_updateConfig", "updateConfig", 0);
}
sub CUL_HM_parseSDteam(@){#handle SD team events
  my ($mTp,$sId,$dId,$p) = @_;
  
  my @entities;
  my $dHash = CUL_HM_id2Hash($dId);
  my $dName = CUL_HM_id2Name($dId);
  my $sHash = CUL_HM_id2Hash($sId);
  my $sName = CUL_HM_hash2Name($sHash);
  if (AttrVal($sName,"subType","") eq "virtual"){
    foreach my $cId (CUL_HM_getAssChnIds($sName)){
      my $cHash = CUL_HM_id2Hash($cId);
      next if (!$cHash->{sdTeam} || $cHash->{sdTeam} ne "sdLead");
      my $cName = CUL_HM_id2Name($cId);
      $sHash = $cHash;
      $sName = CUL_HM_id2Name($cId);
      last;
    }
  }
  return () if (!$sHash->{sdTeam} || $sHash->{sdTeam} ne "sdLead");

  if ($mTp eq "40"){ #test
    my $trgCnt = hex(substr($p,2,2));
    push @evtEt,[$sHash,1,"teamCall:from $dName:$trgCnt"];
    foreach (split ",",$attr{$sName}{peerIDs}){
      my $tHash = CUL_HM_id2Hash($_);
      push @evtEt,[$tHash,1,"teamCall:from $dName:$trgCnt"];
    }
  }
  elsif ($mTp eq "41"){ #Alarm detected
    #C8: Smoke Alarm
    #C7: tone off
    #01: no alarm
    my (undef,$No,$state) = unpack 'A2A2A2',$p;
    if(($dHash) && # update source(ID reported in $dst)
       (!$dHash->{helper}{alarmNo} || $dHash->{helper}{alarmNo} ne $No)){
      $dHash->{helper}{alarmNo} = $No;
    }
    else{
      return ();# duplicate alarm
    }
    my ($sVal,$sProsa,$smokeSrc) = (hex($state),"off","none");
    if ($sVal > 1){
      $sProsa = "smoke-Alarm_".$No;
      $smokeSrc = $dName;
      push @evtEt,[$sHash,1,"recentAlarm:$smokeSrc"] if($sVal == 200);
    }
    push @evtEt,[$sHash,1,"state:$sProsa"];
    push @evtEt,[$sHash,1,'level:'.$sVal];
    push @evtEt,[$sHash,1,"eventNo:".$No];
    push @evtEt,[$sHash,1,"smoke_detect:".$smokeSrc];
    foreach (split ",",$attr{$sName}{peerIDs}){
      my $tHash = CUL_HM_id2Hash($_);
      push @evtEt,[$tHash,1,"state:$sProsa"];
      push @evtEt,[$tHash,1,"smoke_detect:$smokeSrc"];
    }
  }
  return @entities;
}
sub CUL_HM_updtSDTeam(@){#in: TeamName, optional caller name and its new state
  # update team status if virtual team lead
  # check all member state
  # prio: 1:alarm, 2: unknown, 3: off
  # sState given in input may not yet be visible in readings
  my ($name,$sName,$sState) = @_;
  return undef if (!$defs{$name} || AttrVal($name,"model","") !~ m "virtual");
  ($sName,$sState) = ("","") if (!$sName || !$sState);
  return undef if (ReadingsVal($name,"state","off") =~ m/smoke-Alarm/);
  my $dStat = "off";
  foreach my $pId(split(',',AttrVal($name,"peerIDs",""))){#screen teamIDs for Alarm
    my $pNam = CUL_HM_id2Name(substr($pId,0,6)) if ($pId && $pId ne "00000000");
    next if (!$pNam ||!$defs{$pNam});
    my $pStat = ($pNam eq $sName)
                  ?$sState
                  :ReadingsVal($pNam,"state",undef);
    if    (!$pStat)         {$dStat = "unknown";}
    elsif ($pStat ne "off") {$dStat = $pStat;last;}
  }
  return CUL_HM_UpdtReadSingle($defs{$name},"state",$dStat,1);
}
sub CUL_HM_pushEvnts(){########################################################
  #write events to Readings and collect touched devices
  my @ent = ();
  $evtDly = 0;# switch delay trigger off
  if (scalar(@evtEt) > 0){
    @evtEt = sort {($a->[0] cmp $b->[0])|| ($a->[1] cmp $b->[1])} @evtEt;
    my ($h,$x) = ("","");
    my @evts = ();
    foreach my $e(@evtEt){
      if(scalar(@{$e} != 3)){
        Log 2,"CUL_HM set reading invalid:".join(",",@{$e});
        next;
      }
      if ($h ne ${$e}[0] || $x ne ${$e}[1]){
        push @ent,CUL_HM_UpdtReadBulk($h,$x,@evts);
        @evts = ();
        ($h,$x) = (${$e}[0],${$e}[1]);
      }
      push @evts,${$e}[2] if (${$e}[2]);
    }
    @evtEt = ();
    push @ent,CUL_HM_UpdtReadBulk($h,$x,@evts);
  }

  return @ent;
}

sub CUL_HM_Get($@) {#+++++++++++++++++ get command+++++++++++++++++++++++++++++
  my ($hash, @a) = @_;
  return "no value specified" if(@a < 2);
  return "" if(!$hash->{NAME});
  my $name = $hash->{NAME};
  my $devName = InternalVal($name,"device",$name);
  my $st = AttrVal($devName, "subType", "");
  my $md = AttrVal($devName, "model", "");

  my $cmd = $a[1];
  
  my $roleC = $hash->{helper}{role}{chn}?1:0; #entity may act in multiple roles
  my $roleD = $hash->{helper}{role}{dev}?1:0;
  my $roleV = $hash->{helper}{role}{vrt}?1:0;
  my $fkt   = $hash->{helper}{fkt}?$hash->{helper}{fkt}:"";
  
  my ($dst,$chn) = unpack 'A6A2',$hash->{DEF}.($roleC?'01':'00');

  my $h = undef;
  $h = $culHmGlobalGets->{$cmd}       if(!$roleV      &&($roleD || $roleC));
  $h = $culHmVrtGets->{$cmd}          if(!defined($h) && $roleV);
  $h = $culHmSubTypeGets->{$st}{$cmd} if(!defined($h) && $culHmSubTypeGets->{$st});
  $h = $culHmModelGets->{$md}{$cmd}   if(!defined($h) && $culHmModelGets->{$md});
  my @h;
  @h = split(" ", $h) if($h);

  if(!defined($h)) {
    my @arr = ();
    if(!$roleV &&($roleD || $roleC)){foreach(keys %{$culHmGlobalGets}        ){push @arr,"$_:".$culHmGlobalGets->{$_}          }};
    if($roleV)                      {foreach(keys %{$culHmVrtGets}           ){push @arr,"$_:".$culHmVrtGets->{$_}             }};
    if($culHmSubTypeGets->{$st})    {foreach(keys %{$culHmSubTypeGets->{$st}}){push @arr,"$_:".${$culHmSubTypeGets->{$st}}{$_} }};
    if($culHmModelGets->{$md})      {foreach(keys %{$culHmModelGets->{$md}}  ){push @arr,"$_:".${$culHmModelGets->{$md}}{$_}   }};
    
    foreach(@arr){
      my ($cmd,$val) = split(":",$_,2);
      if (!$val               ||
          $val !~ m/^\[.*\]$/ ||
          $val =~ m/\[.*\[/   ||
          $val =~ m/(\<|\>)]/
          ){
        $_ = $cmd;
      }
      else{
        $val =~ s/(\[|\])//g;
        my @vArr = split('\|',$val);
        foreach (@vArr){
          if ($_ =~ m/(.*)\.\.(.*)/ ){
            my @list = map { ($_.".0", $_+0.5) } (($1+0)..($2+0));
            pop @list;
            $_ = join(",",@list);
          }
        }
        $_ = "$cmd:".join(",",@vArr);
      }
    }

    my $usg = "Unknown argument $cmd, choose one of ".join(" ",sort @arr);

    return $usg;
  }
  elsif($h eq "" && @a != 2) {
    return "$cmd requires no parameters";

  }
  elsif($h !~ m/\.\.\./ && @h != @a-2) {
    return "$cmd requires parameter: $h";
  }
  my $devHash = CUL_HM_getDeviceHash($hash);

  #----------- now start processing --------------
  if   ($cmd eq "param") {  ###################################################
    my $p = $a[2];
    return $attr{$name}{$p}              if ($attr{$name}{$p});
    return $hash->{READINGS}{$p}{VAL}    if ($hash->{READINGS}{$p});
    return $hash->{$p}                   if ($hash->{$p});
    return $hash->{helper}{$p}           if ($hash->{helper}{$p} && ref($hash->{helper}{$p}) ne "HASH");
    
    return $attr{$devName}{$p}           if ($attr{$devName}{$p});
    return "undefined";
  }
  elsif($cmd =~ m /^(reg|regVal)$/) {  ########################################
    my (undef,undef,$regReq,$list,$peerId) = @a;
    if ($regReq eq 'all'){
      my @regArr = CUL_HM_getRegN($st,$md,($roleD?"00":""),($roleC?$chn:""));

      my @peers; # get all peers we have a reglist
      my @listWp; # list that require peers
      foreach my $readEntry (keys %{$hash->{READINGS}}){
        if ($readEntry =~m /^[\.]?RegL_(.*)/){ #reg Reading "RegL_<list>:peerN
          my $peer = substr($1,3);
          next if (!$peer);
          push(@peers,$peer);
          push(@listWp,substr($1,1,1));
        }
      }
      my @regValList; #storage of results
      my $regHeader = "list:peer\tregister         :value\n";
      foreach my $regName (@regArr){
        my $regL  = $culHmRegDefine->{$regName}->{l};
        my @peerExe = (grep (/$regL/,@listWp))?@peers:("00000000");
        foreach my $peer(@peerExe){
          next if($peer eq "");
          my $regVal= CUL_HM_getRegFromStore($name,$regName,0,$peer);#determine
          my $peerN = CUL_HM_id2Name($peer);
          $peerN = "      " if ($peer  eq "00000000");
          push @regValList,sprintf("   %d:%s\t%-16s :%s\n",
                  $regL,$peerN,$regName,$regVal)
                if ($regVal !~ m /invalid/);
        }
      }
      my $addInfo = "";
      if    ($md =~ m/(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/ && $chn eq "02"){$addInfo = CUL_HM_TCtempReadings($hash)}
      elsif ($md =~ m/HM-CC-RT-DN/ && $chn eq "04"){$addInfo = CUL_HM_TCITRTtempReadings($hash,$md,7)}
      elsif ($md =~ m/HM-TC-IT/    && $chn eq "02"){$addInfo = CUL_HM_TCITRTtempReadings($hash,$md,7,8,9)}
      elsif ($md =~ m/(^HM-PB-4DIS-WM|HM-Dis-WM55|HM-RC-Dis-H-x-EU)/)
                                                   {$addInfo = CUL_HM_4DisText($hash)}
      elsif ($md eq "HM-Sys-sRP-Pl")               {$addInfo = CUL_HM_repReadings($hash)}

      return $name." type:".$st." - \n".
             $regHeader.join("",sort(@regValList)).
             $addInfo;
    }
    else{
      my $regVal = CUL_HM_getRegFromStore($name,$regReq,$list,$peerId);
	  $regVal =~ s/ .*// if ($cmd eq "regVal");
      return ($regVal =~ m /^invalid/)? "Value not captured"
                                     : $regVal;
    }
  }
  elsif($cmd eq "regList") {  #################################################
    my @regArr = CUL_HM_getRegN($st,$md,$chn);

    my @rI;
    foreach my $regName (@regArr){
      my $reg  = $culHmRegDefine->{$regName};
      my $help = $reg->{t};
      my ($min,$max) = ($reg->{min},"to ".$reg->{max});
      if ($reg->{c} eq "lit"){
        $help .= " options:".join(",",keys%{$reg->{lit}});
        $min = "";
        $max = "literal";
      }
      elsif (defined($reg->{lit})){
        $help .= " special:".join(",",keys%{$reg->{lit}});
      }
      push @rI,sprintf("%4d: %-16s | %3s %-14s | %8s | %s\n",
              $reg->{l},$regName,$min,$max.$reg->{u},
              ((($reg->{l} == 3)||($reg->{l} == 4))?"required":""),
              $help)
            if (($roleD && $reg->{l} == 0)||
                ($roleC && $reg->{l} != 0));
    }

    my $info = sprintf("list: %16s | %-18s | %-8s | %s\n",
                     "register","range","peer","description");
    foreach(sort(@rI)){$info .= $_;}
    return $info;
  }
  elsif($cmd eq "cmdList") {  #################################################
    my   @arr;

    if(!$roleV) {push @arr,"$_ $culHmGlobalGets->{$_}" foreach (keys %{$culHmGlobalGets})};
    if($roleV)  {push @arr,"$_ $culHmVrtGets->{$_}"     foreach (keys %{$culHmVrtGets})};

    push @arr,"$_ $culHmSubTypeGets->{$st}{$_}" foreach (keys %{$culHmSubTypeGets->{$st}});
    push @arr,"$_ $culHmModelGets->{$md}{$_}"   foreach (keys %{$culHmModelGets->{$md}});
    my   @arr1;
    if( !$roleV)                             {foreach(keys %{$culHmGlobalSets}           ){push @arr1,"$_ ".$culHmGlobalSets->{$_}            }};
    if(($st eq "virtual"||!$st)    && $roleD){foreach(keys %{$culHmGlobalSetsVrtDev}     ){push @arr1,"$_ ".$culHmGlobalSetsVrtDev->{$_}      }};
    if( !$roleV                    && $roleD){foreach(keys %{$culHmGlobalSetsDevice}     ){push @arr1,"$_ ".$culHmGlobalSetsDevice->{$_}      }};
    if( !$roleV                    && $roleD){foreach(keys %{$culHmSubTypeDevSets->{$st}}){push @arr1,"$_ ".${$culHmSubTypeDevSets->{$st}}{$_}}};
    if( !$roleV                    && $roleC){foreach(keys %{$culHmGlobalSetsChn}        ){push @arr1,"$_ ".$culHmGlobalSetsChn->{$_}         }};
    if( $culHmSubTypeSets->{$st}   && $roleC){foreach(keys %{$culHmSubTypeSets->{$st}}   ){push @arr1,"$_ ".${$culHmSubTypeSets->{$st}}{$_}   }};
    if( $culHmModelSets->{$md})              {foreach(keys %{$culHmModelSets->{$md}}     ){push @arr1,"$_ ".${$culHmModelSets->{$md}}{$_}     }};
    if( $culHmChanSets->{$md."00"} && $roleD){foreach(keys %{$culHmChanSets->{$md."00"}} ){push @arr1,"$_ ".${$culHmChanSets->{$md."00"}}{$_} }};
    if( $culHmChanSets->{$md.$chn} && $roleC){foreach(keys %{$culHmChanSets->{$md.$chn}} ){push @arr1,"$_ ".${$culHmChanSets->{$md.$chn}}{$_} }};
    if( $culHmFunctSets->{$fkt}    && $roleC){foreach(keys %{$culHmFunctSets->{$fkt}}    ){push @arr1,"$_ ".${$culHmFunctSets->{$fkt}}{$_}    }};

    my $info .= " Gets ------\n";
    $info .= join("\n",sort @arr);
    $info .= "\n\n Sets ------\n";
    $info .= join("\n",sort @arr1);
    return $info;
  }
  elsif($cmd eq "saveConfig"){  ###############################################
    return "no filename given" if (!$a[2]);
    my $fName = $a[2];
    open(aSave, ">>$fName") || return("Can't open $fName: $!");
    my $sName;
    my @eNames;
    if ($a[3] && $a[3] eq "strict"){
      @eNames = ($name);
      $sName =  $name;
    }
    else{
      $sName = $devName;
      @eNames = CUL_HM_getAssChnNames($sName);
    }
    print aSave "\n\n#======== store device data:".$sName." === from: ".TimeNow();
    foreach my $eName (@eNames){
      print aSave "\n#---      entity:".$eName;
      foreach my $rName ("D-firmware","D-serialNr",".D-devInfo",".D-stc"){
        my $rVal = ReadingsVal($eName,$rName,undef);        
        print aSave "\nsetreading $eName $rName $rVal" if (defined $rVal);
      }
      my $pIds = AttrVal($eName, "peerIDs", "");
      my $timestamps = "\n#     timestamp of the readings for reference";
      if ($pIds){
        print aSave "\n# Peer Names:"
                    .InternalVal($eName,"peerList","");
        $timestamps .= "\n#        "
                      .InternalVal($eName,"peerList","")
                      ." :peerList";
        print aSave "\nset ".$eName." peerBulk ".$pIds;
      }
      my $ehash = $defs{$eName};
      foreach my $read (sort grep(/^[\.]?RegL_/,keys %{$ehash->{READINGS}})){
        print aSave "\nset ".$eName." regBulk ".$read." "
              .ReadingsVal($eName,$read,"");
        $timestamps .= "\n#        ".ReadingsTimestamp($eName,$read,"")." :".$read;
      }
      print aSave $timestamps;
    }
    print aSave "\n======= finished ===\n";
    close(aSave);
  }
  elsif($cmd eq "listDevice"){  ###############################################
    if      ($md eq "CCU-FHEM"){
      my @dl = grep !/^$/,
               map{AttrVal($_,"IOgrp","") =~ m/^$name/ ? $_ : ""}
               keys %defs;
      my @rl;
      foreach (@dl){
        my(undef,$pref) = split":",$attr{$_}{IOgrp},2;
        $pref =  "---" if (!$pref);
        my $IODev = $defs{$_}{IODev}->{NAME}?$defs{$_}{IODev}->{NAME}:"---";
        push @rl, "$IODev / $pref $_ ";
      }
      return "devices using $name\ncurrent IO / preferred\n  ".join "\n  ", sort @rl;
    } 
    elsif ($md eq "ActionDetector"){
      my $re = $a[2]?$a[2]:"all";
      if($re && $re =~ m/^(all|alive|unknown|dead|notAlive)$/){
        my @fnd = map {$_.":".$defs{$name}{READINGS}{$_}{VAL}}
                  grep /^status_/,
                  keys %{$defs{ActionDetector}{READINGS}};
        if    ($re eq "notAlive"){ @fnd = grep !/:alive$/,@fnd; }
        elsif ($re eq "all")     {;        }
        else                     { @fnd = grep /:$a[2]$/,@fnd;}
        $_ =~ s/status_(.*):.*/$1/ foreach(@fnd);
        push @fnd,"empty" if (!scalar(@fnd));
        return  join",",sort(@fnd);
      } else{
        return "please enter parameter [alive|unknown|dead|notAlive]";
      }
    }
  }
  elsif($cmd eq "info"){  ###############################################
    return CUL_HM_ActInfo();
  }
 
  Log3 $name,3,"CUL_HM get $name " . join(" ", @a[1..$#a]);

  my $rxType = CUL_HM_getRxType($hash);
  CUL_HM_ProcessCmdStack($devHash) if ($rxType & 0x03);#burst/all
  return "";
}
sub CUL_HM_Set($@) {#+++++++++++++++++ set command+++++++++++++++++++++++++++++
  my ($hash, @a) = @_;
  return "no value specified" if(@a < 2);
  return "FW update in progress - please wait" 
        if ($modules{CUL_HM}{helper}{updating});
  my $act = join(" ", @a[1..$#a]);
  my $name    = $hash->{NAME};
  return "device ignored due to attr 'ignore'"
        if (CUL_HM_getAttrInt($name,"ignore"));
  my $devName = InternalVal($name,"device",$name);
  my $st      = AttrVal($devName, "subType", "");
  my $md      = AttrVal($devName, "model"  , "");
  my $flag    = CUL_HM_getFlag($hash); #set burst flag
  my $cmd     = $a[1];
  my ($dst,$chn) = unpack 'A6A2',$hash->{DEF}.'01';#default to chn 01 for dev
  return "" if (!defined $chn);

  my $roleC = $hash->{helper}{role}{chn}?1:0; #entity may act in multiple roles
  my $roleD = $hash->{helper}{role}{dev}?1:0;
  my $roleV = $hash->{helper}{role}{vrt}?1:0;
  my $fkt   = $hash->{helper}{fkt}?$hash->{helper}{fkt}:"";
  
  my $h = undef;
  $h = $culHmGlobalSets->{$cmd}         if(                !$roleV                    &&($roleD || $roleC));
  $h = $culHmGlobalSetsVrtDev->{$cmd}   if(!defined($h) &&( $roleV || !$st)           && $roleD);
  $h = $culHmGlobalSetsDevice->{$cmd}   if(!defined($h) && !$roleV                    && $roleD);
  $h = $culHmSubTypeDevSets->{$st}{$cmd}if(!defined($h) && !$roleV                    && $roleD);
  $h = $culHmGlobalSetsChn->{$cmd}      if(!defined($h) && !$roleV                    && $roleC);
  $h = $culHmSubTypeSets->{$st}{$cmd}   if(!defined($h) && $culHmSubTypeSets->{$st}   && $roleC);
  $h = $culHmModelSets->{$md}{$cmd}     if(!defined($h) && $culHmModelSets->{$md}  );
  $h = $culHmChanSets->{$md."00"}{$cmd} if(!defined($h) && $culHmChanSets->{$md."00"} && $roleD);
  $h = $culHmChanSets->{$md.$chn}{$cmd} if(!defined($h) && $culHmChanSets->{$md.$chn} && $roleC); 
  $h = $culHmFunctSets->{$fkt}{$cmd}    if(!defined($h) && $culHmFunctSets->{$fkt});

  my @h;
  @h = split(" ", $h) if($h);
  my @postCmds=(); #Commands to be appended after regSet (ugly...)

  if(!defined($h) && defined($culHmSubTypeSets->{$st}{pct}) && $cmd =~ m/^\d+/) {
    splice @a, 1, 0,"pct";#insert the actual command
  }
  elsif(!defined($h)) { ### unknown - return the commandlist
    my @arr1 = ();
    if( !$roleV &&($roleD || $roleC)        ){foreach(keys %{$culHmGlobalSets}           ){push @arr1,"$_:".$culHmGlobalSets->{$_}            }};
    if(( $roleV||!$st)             && $roleD){foreach(keys %{$culHmGlobalSetsVrtDev}     ){push @arr1,"$_:".$culHmGlobalSetsVrtDev->{$_}      }};
    if( !$roleV                    && $roleD){foreach(keys %{$culHmGlobalSetsDevice}     ){push @arr1,"$_:".$culHmGlobalSetsDevice->{$_}      }};
    if( !$roleV                    && $roleD){foreach(keys %{$culHmSubTypeDevSets->{$st}}){push @arr1,"$_:".${$culHmSubTypeDevSets->{$st}}{$_}}};
    if( !$roleV                    && $roleC){foreach(keys %{$culHmGlobalSetsChn}        ){push @arr1,"$_:".$culHmGlobalSetsChn->{$_}         }};
    if( $culHmSubTypeSets->{$st}   && $roleC){foreach(keys %{$culHmSubTypeSets->{$st}}   ){push @arr1,"$_:".${$culHmSubTypeSets->{$st}}{$_}   }};
    if( $culHmModelSets->{$md})              {foreach(keys %{$culHmModelSets->{$md}}     ){push @arr1,"$_:".${$culHmModelSets->{$md}}{$_}     }};
    if( $culHmChanSets->{$md."00"} && $roleD){foreach(keys %{$culHmChanSets->{$md."00"}} ){push @arr1,"$_:".${$culHmChanSets->{$md."00"}}{$_} }};
    if( $culHmChanSets->{$md.$chn} && $roleC){foreach(keys %{$culHmChanSets->{$md.$chn}} ){push @arr1,"$_:".${$culHmChanSets->{$md.$chn}}{$_} }};
    if( $culHmFunctSets->{$fkt}    && $roleC){foreach(keys %{$culHmFunctSets->{$fkt}}    ){push @arr1,"$_:".${$culHmFunctSets->{$fkt}}{$_}    }};
    @arr1 = CUL_HM_noDup(@arr1);
    foreach(@arr1){
      my ($cmd,$val) = split(":",$_,2);
      if (!$val               ||
          $val !~ m/^\[.*\]$/ ||
          $val =~ m/\[.*\[/   ||
          $val =~ m/(\<|\>)]/
          ){
        $_ = $cmd;
      }
      else{
        $val =~ s/(\[|\])//g;
        my @vArr = split('\|',$val);
        foreach (@vArr){
          if ($_ =~ m/(.*)\.\.(.*)/ ){
            my @list = map { ($_.".0", $_+0.5) } (($1+0)..($2+0));
            pop @list;
            $_ = join(",",@list);
          }
        }
        $_ = "$cmd:".join(",",@vArr);
      }
    }
    my $usg = "Unknown argument $cmd, choose one of ".join(" ",sort @arr1);
    $usg =~ s/ pct/ pct:slider,0,1,100/;
    $usg =~ s/ virtual/ virtual:slider,1,1,50/;

    return $usg;
  }
  elsif($h eq "" && @a != 2) {
    return "$cmd requires no parameters";
  }
  elsif($h !~ m/\.\.\./ && @h != @a-2) {
    return "$cmd requires parameter: $h";
  }

  my $id = CUL_HM_IoId($defs{$devName});
  if(length($id) != 6 ){# have to try to find an O
    CUL_HM_assignIO($defs{$devName});
    $id = CUL_HM_IoId($defs{$devName});
    return "no IO device identified" if(length($id) != 6 );
  }
  

  #convert 'old' commands to current methodes like regSet and regBulk...
  # Unify the interface
  if(   $cmd eq "sign"){
    splice @a,1,0,"regSet";# make hash,regSet,reg,value
  }
  elsif($cmd eq "unpair"){
    splice @a,1,3, ("regSet","pairCentral","000000");
  }
  elsif($cmd eq "ilum") { ################################################# reg
    return "$a[2] not specified. choose 0-15 for brightness"  if ($a[2]>15);
    return "$a[3] not specified. choose 0-127 for duration"   if ($a[3]>127);
    return "unsupported for channel, use $devName"            if (!$roleD);
    splice @a,1,3, ("regBulk","RegL_00:",sprintf("04:%02X",$a[2]),sprintf("08:%02X",$a[3]*2));
  }
  elsif($cmd eq "text") { ################################################# reg
    my ($bn,$l1, $l2) = ($chn,$a[2],$a[3]); # Create CONFIG_WRITE_INDEX string
    if ($roleD){# if used on device.
      return "$a[2] is not a button number" if($a[2] !~ m/^\d*$/ || $a[2] < 1);
      return "$a[3] is not on or off" if($a[3] !~ m/^(on|off)$/);
      $bn = $a[2]*2-($a[3] eq "on" ? 0 : 1);
      ($l1, $l2) = ($a[4],$a[5]);
      $chn = sprintf("%02X",$bn)
      }
    else{
      return "to many parameter. Try set $a[0] text $a[2] $a[3]" if($a[4]);
    }
    my $s = 54;
    $l1 =~ s/\\_/ /g;
    $l1 = substr($l1."\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 0, 12);
    $l1 =~ s/(.)/sprintf(" %02X:%02X",$s++,ord($1))/ge;

    $s = 70;
    $l2 =~ s/\\_/ /g;
    $l2 = substr($l2."\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", 0, 12);
    $l2 =~ s/(.)/sprintf(" %02X:%02X",$s++,ord($1))/ge;
    @a = ($a[0],"regBulk","RegL_01:",split(" ",$l1.$l2));
  }
  elsif($cmd =~ m /(displayMode|displayTemp|displayTempUnit|controlMode)/) {
    if ($md =~ m/(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/){#controlMode different for RT
      splice @a,1,3, ("regSet",$a[1],$a[2]);
      push @postCmds,"++803F$id${dst}0204".sprintf("%02X",CUL_HM_secSince2000());
    }
  }
  elsif($cmd eq "partyMode") { ################################################
    my ($eH,$eM,$days,$prep) = ("","","","");
    if ($a[2] =~ m/^(prep|exec)$/){
      $prep = $a[2];
      splice  @a,2,1;#remove prep
    }
    $days = $a[3];
    ($eH,$eM)  = split(':',$a[2]);

    my ($s,$m,$h) = localtime();
    return "$eH:$eM passed at $h:$m. Please enter time in the feature" 
                                                            if ($days == 0 && ($h+($m/60))>=($eH+($eM/60)) );
    return "$eM illegal - use 00 or 30 minutes only"        if ($eM !~ m/^(00|30)$/);
    return "$eH illegal - hour must be between 0 and 23"    if ($eH < 0 || $eH > 23);
    return "$days illegal - days must be between 0 and 200" if ($days < 0 || $days > 200);
    $eH += 128 if ($eM eq "30");

    my $cHash = CUL_HM_id2Hash($dst."02");
    $cHash->{helper}{partyReg} = sprintf("61%02X62%02X0000",$eH,$days);
    $cHash->{helper}{partyReg} =~ s/(..)(..)/ $1:$2/g;
    if ($cHash->{READINGS}{"RegL_06:"}){#remove old settings
      $cHash->{READINGS}{"RegL_06:"}{VAL} =~ s/ 61:.*//;
      $cHash->{READINGS}{"RegL_06:"}{VAL} =~ s/ 00:00//;
      $cHash->{READINGS}{"RegL_06:"}{VAL} .= $cHash->{helper}{partyReg};
    }
    else{
      $cHash->{READINGS}{"RegL_06:"}{VAL} = $cHash->{helper}{partyReg};
    }
    CUL_HM_pushConfig($hash,$id,$dst,2,"000000","00",6,
                      sprintf("61%02X62%02X",$eH,$days),$prep);
    splice @a,1,3, ("regSet","controlMode","party");
    splice @a,2,0, ($prep) if ($prep);
    push @postCmds,"++803F$id${dst}0204".sprintf("%02X",CUL_HM_secSince2000());
  }

  $cmd = $a[1];# get converted command

  #if chn cmd is executed on device but refers to a channel? 
  my $chnHash = (!$roleC && $modules{CUL_HM}{defptr}{$dst."01"})?
                 $modules{CUL_HM}{defptr}{$dst."01"}:$hash;
  my $devHash = CUL_HM_getDeviceHash($hash);
  my $state = "set_".join(" ", @a[1..(int(@a)-1)]);

  if   ($cmd eq "raw") {  #####################################################
    return "Usage: set $a[0] $cmd data [data ...]" if(@a < 3);
    $state = "";
    my $msg = $a[2];
    foreach my $sub (@a[3..$#a]) {
      last if ($sub !~ m/^[A-F0-9]*$/);
      $msg .= $sub;      
    }
    CUL_HM_PushCmdStack($hash, $msg);
  }
  elsif($cmd eq "clear") { ####################################################
    my (undef,undef,$sectIn) = @a;
    my @sectL;
    if ($sectIn eq "all") {
      @sectL = ("rssi","msgEvents","readings","attack");#readings is last - it schedules a reread possible
    }
    elsif($sectIn =~ m/(rssi|trigger|msgEvents|readings|register|unknownDev|attack)/){
      @sectL = ($sectIn);
    }
    else{
      return "unknown section. User readings, msgEvents or rssi";
    }
    foreach my $sect (@sectL){
      if   ($sect eq "readings"){
        my @cH = ($hash);
        push @cH,$defs{$hash->{$_}} foreach(grep /^channel/,keys %{$hash});
        delete $_->{READINGS} foreach (@cH);
        delete $modules{CUL_HM}{helper}{cfgCmpl}{$name};
        CUL_HM_complConfig($_->{NAME}) foreach (@cH);
        CUL_HM_qStateUpdatIfEnab($_->{NAME}) foreach (@cH);
      }
      elsif($sect eq "unknownDev"){
        delete $hash->{READINGS}{$_} 
             foreach (grep /^unknown_/,keys %{$hash->{READINGS}});
      }
      elsif($sect eq "trigger"){
        delete $hash->{READINGS}{$_} 
             foreach (grep /^trig/,keys %{$hash->{READINGS}});
      }
      elsif($sect eq "register"){
        my @cH = ($hash);
        push @cH,$defs{$hash->{$_}} foreach(grep /^channel/,keys %{$hash});
      
        foreach my $h(@cH){
          delete $h->{READINGS}{$_}
               foreach (grep /^(\.?)(R-|RegL)/,keys %{$h->{READINGS}});
          delete $modules{CUL_HM}{helper}{cfgCmpl}{$name};
          CUL_HM_complConfig($h->{NAME});
        }
      }
      elsif($sect eq "msgEvents"){
        CUL_HM_respPendRm($hash);
      
        $hash->{helper}{prt}{bErr}=0;
        delete $hash->{cmdStack};
        delete $hash->{helper}{prt}{rspWait};
        delete $hash->{helper}{prt}{rspWaitSec};
        delete $hash->{helper}{prt}{mmcA};
        delete $hash->{helper}{prt}{mmcS};
        delete $hash->{lastMsg};
        delete ($hash->{$_}) foreach (grep(/^prot/,keys %{$hash}));
      
        if ($hash->{IODev}{NAME} &&
            $modules{CUL_HM}{$hash->{IODev}{NAME}} &&
            $modules{CUL_HM}{$hash->{IODev}{NAME}}{pendDev}){
          @{$modules{CUL_HM}{$hash->{IODev}{NAME}}{pendDev}} =
                grep !/$name/,@{$modules{CUL_HM}{$hash->{IODev}{NAME}}{pendDev}};
        }
        CUL_HM_unQEntity($name,"qReqConf");
        CUL_HM_unQEntity($name,"qReqStat");
        CUL_HM_protState($hash,"Info_Cleared");
      }
      elsif($sect eq "rssi"){
        delete $defs{$name}{helper}{rssi};
        delete ($hash->{$_}) foreach (grep(/^rssi/,keys %{$hash}))
      }
      elsif($sect eq "attack"){
        delete $defs{$name}{helper}{rssi};
        delete ($hash->{$_}) foreach (grep(/^protErrIo(Id|Attack)/,keys %{$hash}));
        delete $hash->{READINGS}{$_}
            foreach (grep /^sabotageAttack/,keys %{$hash->{READINGS}});
     }
    }
    $state = "";
  }
  elsif($cmd eq "reset") { ####################################################
    CUL_HM_PushCmdStack($hash,"++".$flag."11".$id.$dst."0400");
  }
  elsif($cmd eq "burstXmit") { ################################################
    $state = "";
    $hash->{helper}{prt}{brstWu}=1;# start burst wakeup
    CUL_HM_SndCmd($hash,"++B112$id$dst");
  }
  elsif($cmd eq "defIgnUnknown") { ############################################
    $state = "";
    foreach (map {substr($_,8)} 
             grep /^unknown_......$/,
             keys %{$hash->{READINGS}}){
      if (!$modules{CUL_HM}{defptr}{$_}){
        CommandDefine(undef,"unknown_$_ CUL_HM $_") ;
        $attr{"unknown_$_"}{ignore} = 1;
      }
      delete $hash->{READINGS}{"unknown_$_"};
    }
  }

  elsif($cmd eq "statusRequest") { ############################################
    my @chnIdList = CUL_HM_getAssChnIds($name);
    foreach my $channel (@chnIdList){
      my $chnNo = substr($channel,6,2);
      CUL_HM_PushCmdStack($hash,"++".$flag.'01'.$id.$dst.$chnNo.'0E');
    }
    $state = "";
  }
  elsif($cmd eq "getSerial") { ################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.'0009');
    $state = "";
  }
  elsif($cmd eq "getConfig") { ################################################
    CUL_HM_unQEntity($name,"qReqConf");
    CUL_HM_getConfig($hash);
    $state = "";
  }
  elsif($cmd eq "peerBulk") { #################################################
    $state = "";
    my $pL = $a[2];
    
    return "unknown action: $a[3] - use set or unset"
             if ($a[3] && $a[3] !~ m/^(set|unset)/);
    my $set = ($a[3] && $a[3] eq "unset")?"02":"01";
    foreach my $peer (grep(!/^self/,split(',',$pL))){
      my $pID = CUL_HM_peerChId($peer,$dst);
      return "unknown peer".$peer if (length($pID) != 8);# peer only to channel
      my $pCh1 = substr($pID,6,2);
      my $pCh2 = $pCh1;
      if(($culHmSubTypeSets->{$st}   &&$culHmSubTypeSets->{$st}{peerChan}  )||
         ($culHmModelSets->{$md}     &&$culHmModelSets->{$md}{peerChan}    )||
         ($culHmChanSets->{$md.$chn} &&$culHmChanSets->{$md.$chn}{peerChan})  ){
        $pCh2 = "00";                        # button behavior
      }
      CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.$chn.$set.
                          substr($pID,0,6).$pCh1.$pCh2);
    }
    CUL_HM_qAutoRead($name,3);
  }
  elsif($cmd =~ m/^(regBulk|getRegRaw)$/) { ############################### reg
    my ($list,$addr,$data,$peerID);
    $state = "";
    if ($cmd eq "regBulk"){
      $list = $a[2];
      $list =~ s/[\.]?RegL_//;
      ($list,$peerID) = split(":",$list);
#      return "unknown list Number:".$list if(hex($list)>6);
    }
    elsif ($cmd eq "getRegRaw"){
      ($list,$peerID) = ($a[2],$a[3]);
      return "Enter valid List0-6" if ($list !~ m/^List([0-6])$/);
      $list ='0'.$1;
    }
    # as of now only hex value allowed check range and convert

    $peerID  = CUL_HM_peerChId(($peerID?$peerID:"00000000"),$dst);
    my $peerChn = ((length($peerID) == 8)?substr($peerID,6,2):"01");# have to split chan and id
    $peerID = substr($peerID,0,6);

    if($cmd eq "getRegRaw"){
      if ($list eq "00"){
        CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.'00040000000000');
      }
      else{# other lists are per channel
        my @chnIdList = CUL_HM_getAssChnIds($name);
        foreach my $channel (@chnIdList){
          my $chnNo = substr($channel,6,2);
          if ($list =~m /0[34]/){#getPeers to see if list3 is available
            CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.$chnNo.'03');
            my $chnHash = CUL_HM_id2Hash($channel);
            $chnHash->{helper}{getCfgList} = $peerID.$peerChn;#list3 regs
            $chnHash->{helper}{getCfgListNo} = int($list);
          }
          else{
            CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.$chnNo.'04'
                                          .$peerID.$peerChn.$list);
          }
        }
      }
    }
    elsif($cmd eq "regBulk"){;
      my @adIn = @a;
      shift @adIn;shift @adIn;shift @adIn;
      my $adList;
      foreach my $ad (sort @adIn){
        ($addr,$data) = split(":",$ad);
        $adList .= sprintf("%02X%02X",hex($addr),hex($data)) if ($addr ne "00");
        return "wrong addr or data:".$ad if (hex($addr)>255 || hex($data)>255);
      }
      $chn = 0 if ($list == 0);
      CUL_HM_pushConfig($hash,$id,$dst,hex($chn),$peerID,$peerChn,$list,$adList);
    }
  }
  elsif($cmd eq "regSet") { ############################################### reg
    #set <name> regSet [prep] <regName>  <value> [<peerChn>]
    #prep is internal use only. It allowes to prepare shadowReg only but supress
    #writing. Application necessarily needs to execute writing subsequent.
    my $prep = "";
    if ($a[2] =~ m/^(prep|exec)$/){
      $prep = $a[2];
      splice  @a,2,1;#remove prep
    }

    my (undef,undef,$regName,$data,$peerChnIn) = @a;
    $state = "";
    my @regArr = CUL_HM_getRegN($st,$md,($roleD?"00":""),($roleC?$chn:""));
    
    return "$regName failed: supported register are ".join(" ",sort @regArr)
            if (!grep /^$regName$/,@regArr );

    my $reg  = $culHmRegDefine->{$regName};
    my $conv = $reg->{c};
    return $st." - ".$regName            # give some help
           .($conv eq "lit"? " literal:".join(",",keys%{$reg->{lit}})." "
                               : " range:". $reg->{min}." to ".$reg->{max}.$reg->{u}
                                 .($reg->{lit}?" special:".join(",",keys%{$reg->{lit}})." "
                                              :""
                                              )
            )
           .(($reg->{l} == 3)?" peer required":"")." : ".$reg->{t}."\n"
            if ($data eq "?");
    if (   $conv ne 'lit' 
        && $reg->{lit} 
        && defined $reg->{lit}{$data} ){
      $data = $reg->{lit}{$data};#conv special value past to calculation
    }     
            
    return "value:$data out of range $reg->{min} to $reg->{max} for Reg \""
           .$regName."\""
            if (!($conv =~ m/^(lit|hex|min2time)$/)&&
                ($data < $reg->{min} ||$data > $reg->{max})); # none number
    return"invalid value. use:". join(",",sort keys%{$reg->{lit}})
            if ($conv eq 'lit' && !defined($reg->{lit}{$data}));

    if ($conv ne 'lit' && $reg->{lit} && $reg->{lit}{$data}){
      $data = $reg->{lit}{$data}; #conv special value prior to calculation
    }
    $data *= $reg->{f} if($reg->{f});# obey factor befor possible conversion
    if (!$conv){;# do nothing
    }elsif($conv eq "fltCvT"  ){$data = CUL_HM_fltCvT($data);
    }elsif($conv eq "fltCvT60"){$data = CUL_HM_fltCvT60($data);
    }elsif($conv eq "min2time"){$data = CUL_HM_time2min($data);
    }elsif($conv eq "m10s3")   {$data = $data*10-3;
    }elsif($conv eq "hex")     {$data = hex($data);
    }elsif($conv eq "lit")     {$data = $reg->{lit}{$data};
    }else{return " conv undefined - please contact admin";
    }

    my $addr = int($reg->{a});        # bit location later
    my $list = $reg->{l};
    my $bit  = ($reg->{a}*10)%10; # get fraction

    my $dLen = $reg->{s};             # datalength in bit
    $dLen = int($dLen)*8+(($dLen*10)%10);
    # only allow it level if length less then one byte!!
    return "partial Word error: ".$dLen if($dLen != 8*int($dLen/8) && $dLen>7);
    no warnings qw(overflow portable);
    my $mask = (0xffffffff>>(32-$dLen));
    use warnings qw(overflow portable);
    my $dataStr = substr(sprintf("%08X",($data & $mask) << $bit),
                                           8-int($reg->{s}+0.99)*2,);

    my ($lChn,$peerId,$peerChn) = ($chn,"000000","00");
    if (($list == 3) ||($list == 4)   # peer is necessary for list 3/4
        ||($peerChnIn))              {# and if requested by user
      return "Peer not specified" if ($peerChnIn eq "");
      $peerId  = CUL_HM_peerChId($peerChnIn,$dst);
      ($peerId,$peerChn) = unpack 'A6A2',$peerId.'01';
      return "Peer not valid" if (length ($peerId) < 6);
    }
    elsif($list == 0){
      $lChn = "00";
    }
    else{  #if($list == 1/5/6){
      $lChn = "01" if ($chn eq "00"); #by default select chan 01 for device
    }
    my $addrData;
    if ($dLen < 8){# fractional byte see whether we have stored the register
      #read full 8 bit!!!
      my $rName = CUL_HM_id2Name($dst.$lChn);
      $rName =~ s/_chn:.*//;
      my $curVal = CUL_HM_getRegFromStore($rName,$addr,$list,$peerId.$peerChn);
      if ($curVal !~ m/^(set_|)(\d+)$/){
	return "peer required for $regName" if ($curVal =~ m/peer/);
	return "cannot calculate value. Please issue set $name getConfig first - $curVal";
      }
                 ;
      $curVal = $2; # we expect one byte in int, strap 'set_' possibly
      $data = ($curVal & (~($mask<<$bit)))|($data<<$bit);
      $addrData.=sprintf("%02X%02X",$addr,$data);
    }
    else{
      for (my $cnt = 0;$cnt<int($reg->{s}+0.99);$cnt++){
        $addrData.=sprintf("%02X",$addr+$cnt).substr($dataStr,$cnt*2,2);
      }
    }

#    $lChn = "00" if($list == 7 && (!$peerChnIn ||$peerChnIn eq ""));#face to send

    my $cHash = CUL_HM_id2Hash($dst.($lChn eq '00'?"":$lChn));
    $cHash = $hash if (!$cHash);
    CUL_HM_pushConfig($cHash,$id,$dst,hex($lChn),$peerId,hex($peerChn),$list
                     ,$addrData,$prep);

    CUL_HM_PushCmdStack($hash,$_) foreach(@postCmds);#ugly commands after regSet
  }

  elsif($cmd eq "level") { ####################################################
    #level        =>"<level> <relockDly> <speed>..."
    my (undef,undef,$lvl,$rLocDly,$speed) = @a;
    $rLocDly = 111600 if (!defined($rLocDly)||$rLocDly eq "ignore");# defaults
    $speed   = 30     if (!defined($speed));
    $lvl = 127.5 if ($lvl eq "lock");
    return "please enter level 0 to 100 or lock" 
                                         if (  !defined($lvl)           
                                             || $lvl !~ m/^\d*\.?\d?$/  
                                             || ($lvl > 100 && $lvl != 127.5));
    return "reloclDelay range 0..65535 or ignore"
                                         if ( $rLocDly > 111600 ||
                                             ($rLocDly < 0.1 &&  $rLocDly ne '0' ));
    return "select speed range 0 to 100" if ( $speed > 100);
    
    $rLocDly = CUL_HM_encodeTime8($rLocDly);# calculate hex value
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'81'.$chn.
                        sprintf("%02X%02s%02X",$lvl*2,$rLocDly,$speed*2));
  }
  elsif($cmd =~ m/^(on|off|toggle)$/) { #######################################
    my $lvlInv = (AttrVal($name, "param", "") eq "levelInverse")?1:0;
    $hash->{helper}{dlvl} = ( $cmd eq 'off'||
                             ($cmd eq 'toggle' &&CUL_HM_getChnLvl($name) != 0)) 
                                ? ($lvlInv?'C8':'00')
                                : ($lvlInv?'00':'C8');
    my(undef,$lvlMax)=split",",AttrVal($name, "levelRange", "0,100");
    $hash->{helper}{dlvl} = sprintf("%02X",$lvlMax*2) 
          if ($hash->{helper}{dlvl} eq 'C8');
    $hash->{helper}{dlvlCmd} = "++$flag"."11$id$dst"
                               ."02$chn$hash->{helper}{dlvl}".'0000';
    CUL_HM_PushCmdStack($hash,$hash->{helper}{dlvlCmd});
    $hash = $chnHash; # report to channel if defined
  }
  elsif($cmd eq "toggleDir") { ################################################
    if ($hash->{helper}{dir}{cur} &&  $hash->{helper}{dir}{cur} ne "err"){
      my $old = $hash->{helper}{dir}{cur};
      $hash->{helper}{dir}{cur} = $hash->{helper}{dir}{cur} eq "stop" ?(($hash->{helper}{dir}{rct} 
                                                                      && $hash->{helper}{dir}{rct} eq "up")?"down"
                                                                                                           :"up")
                                                                      :"stop";
      $hash->{helper}{dir}{rct} = $old;
    }
    else{
      $hash->{helper}{dir}{rct} = "stop";
      $hash->{helper}{dir}{cur} = "up";
    }
    if     ($hash->{helper}{dir}{cur} eq "up"  ){
      $hash->{helper}{dlvl} = "C8";
      $hash->{helper}{dlvlCmd} = "++$flag"."11$id$dst"."02$chn".'C80000';
      CUL_HM_PushCmdStack($hash,$hash->{helper}{dlvlCmd});
    }elsif ($hash->{helper}{dir}{cur} eq "down"){
      $hash->{helper}{dlvl} = "00";
      $hash->{helper}{dlvlCmd} = "++$flag"."11$id$dst"."02$chn".'000000';
      CUL_HM_PushCmdStack($hash,$hash->{helper}{dlvlCmd});
    }else                                       {
      delete $hash->{helper}{dlvl};
      CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'03'.$chn);
    }
  }
  elsif($cmd =~ m/^(on-for-timer|on-till)$/) { ################################
    my (undef,undef,$duration,$ramp) = @a; #date prepared extention to entdate
    if ($cmd eq "on-till"){
      # to be extended to handle end date as well
      my (undef,$eH,$eM,$eSec)  = GetTimeSpec($duration);
      $eSec += $eH*3600 + $eM*60;
      my @lt = localtime;
      my $ltSec = $lt[2]*3600+$lt[1]*60+$lt[0];# actually strip of date
      $eSec += 3600*24 if ($ltSec > $eSec); # go for the next day
      $duration = $eSec - $ltSec;
    }
    return "please enter the duration in seconds"
          if (!defined $duration || $duration !~ m/^[+-]?\d+(\.\d+)?$/);
    my $tval = CUL_HM_encodeTime16($duration);# onTime   0.0..85825945.6, 0=forever
    return "timer value to low" if ($tval eq "0000");
    $ramp = ($ramp && $st eq "dimmer")?CUL_HM_encodeTime16($ramp):"0000";
    delete $hash->{helper}{dlvl};#stop desiredLevel supervision
    $hash->{helper}{stateUpdatDly} = ($duration>120)?$duration:120;
    my(undef,$lvlMax)=split",",AttrVal($name, "levelRange", "0,100");
    $lvlMax = sprintf("%02X",$lvlMax*2);
    CUL_HM_PushCmdStack($hash,"++${flag}11$id${dst}02${chn}$lvlMax$ramp$tval");
    $hash = $chnHash; # report to channel if defined
  }
  elsif($cmd eq "lock") { #####################################################
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'800100FF'); # LEVEL_SET
  }
  elsif($cmd eq "unlock") { ###################################################
      my $tval = (@a > 2) ? int($a[2]) : 0;
      my $delay = ($tval > 0) ? CUL_HM_encodeTime8($tval) : "FF";   # RELOCK_DELAY (FF=never)
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'800101'.$delay);# LEVEL_SET
  }
  elsif($cmd eq "open") { #####################################################
      my $tval = (@a > 2) ? int($a[2]) : 0;
      my $delay = ($tval > 0) ? CUL_HM_encodeTime8($tval) : "FF";   # RELOCK_DELAY (FF=never)
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'8001C8'.$delay);# OPEN
  }
  elsif($cmd eq "inhibit") { ##################################################
    return "$a[2] is not on or off" if($a[2] !~ m/^(on|off)$/);
    my $val = ($a[2] eq "on") ? "01" : "00";
    CUL_HM_UpdtReadSingle($hash,"inhibit","set_$a[2]",1);
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.$val.$chn);  # SET_LOCK
  }
  elsif($cmd =~ m/^(up|down|pct)$/) { #########################################
    my ($lvl,$tval,$rval,$duration) = (($a[2]?$a[2]:0),"","",0);
    $lvl =~ s/(\d*\.?\d*).*/$1/;
    my($lvlMin,$lvlMax) = split",",AttrVal($name, "levelRange", "0,100");
    my $lvlInv = (AttrVal($name, "param", "") eq "levelInverse")?1:0;

    if ($cmd eq "pct"){
      $lvl = $lvlMin + $lvl*($lvlMax-$lvlMin)/100;
    }
    else{#dim [<changeValue>] ... [ontime] [ramptime]
      $lvl = 10 if (!defined $a[2]); #set default step
      $lvl = $lvl*($lvlMax-$lvlMin)/100;
      $lvl = -1*$lvl if (($cmd eq "down" && !$lvlInv)|| 
                         ($cmd ne "down" && $lvlInv));
      $lvl += CUL_HM_getChnLvl($name);
    }
    $lvl = ($lvl > $lvlMax)?$lvlMax:(($lvl <= $lvlMin)?0:$lvl);
    my $plvl = ($lvlInv)?100-$lvl :$lvl;
    if ($st eq "dimmer"){# at least blind cannot stand ramp time...
      if (!$a[3]){
        $tval = "FFFF";
        $duration = 0;
      }
      elsif ($a[3] =~ m /(..):(..):(..)/){
        my ($eH,$eM,$eSec)  = ($1,$2,$3);
        $eSec += $eH*3600 + $eM*60;
        my @lt = localtime;
        my $ltSec = $lt[2]*3600+$lt[1]*60+$lt[0];# actually strip of date
        $eSec += 3600*24 if ($ltSec > $eSec); # go for the next day
        $duration = $eSec - $ltSec;
        $tval = CUL_HM_encodeTime16($duration);
      }
      else{
        $duration = $a[3];
        $tval = CUL_HM_encodeTime16($duration);# onTime 0.05..85825945.6, 0=forever
      }
      $rval = CUL_HM_encodeTime16((@a > 4)?$a[4]:2.5);# rampTime 0.0..85825945.6, 0=immediate
      $hash->{helper}{stateUpdatDly} = ($duration>120)?$duration:120;
    }
    # store desiredLevel in and its Cmd in case we have to repeat
    $plvl = sprintf("%02X",$plvl*2);
    if ($tval && $tval ne "FFFF"){
      delete $hash->{helper}{dlvl};#stop desiredLevel supervision
    }
    else{
      $hash->{helper}{dlvl} = $plvl;
    }
    $hash->{helper}{dlvlCmd} = "++$flag"."11$id$dst"."02$chn$plvl$rval$tval";
    CUL_HM_PushCmdStack($hash,$hash->{helper}{dlvlCmd});
    $state = "set_".$lvl;
    CUL_HM_UpdtReadSingle($hash,"level",$state,1);
  }
  elsif($cmd eq "stop") { #####################################################
    delete $hash->{helper}{dlvl};#stop desiredLevel supervision
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'03'.$chn);
  }
  elsif($cmd eq "setRepeat") { ################################################
    #      setRepeat    => "[no1..36] <sendName> <recName> [bdcast-yes|no]"}
    $state = "";
    my (undef,undef,$eNo,$sId,$rId,$bCst) = @a;
    my ($pattern,$cnt);
    my $repPeers = AttrVal($name,"repPeers",undef);
    my @rPeer;
    @rPeer = split ",",$repPeers;
    if ($eNo eq "setAll"){
      return " too many entries in repPeers" if (int(@rPeer) > 36);
      return "setAll: attr repPeers undefined" if (!defined $repPeers);
      my $entry = 0;
      foreach my $repData (@rPeer){
        $entry++;
        my ($s,$d,$b) =split":",$repData;
        $s = CUL_HM_name2Id($s);
        $d = CUL_HM_name2Id($d);
        return "attr repPeers entry $entry irregular:$repData"
          if (!$s || !$d || !$b
               || $s !~ m/(^[0-9A-F]{6})$/
               || $d !~ m/(^[0-9A-F]{6})$/
               || $b !~ m/^[yn]$/
               );
        $pattern .= $s.$d.(($b eq "n")?"00":"01");
      }
      while ($entry < 36){
        $entry++;
        $pattern .= "000000"."000000"."00";
      }
      $cnt = 1;# set first address byte
    }
    else{
      return "entry must be between 1 and 36" if ($eNo < 1 || $eNo > 36);
      my $sndID = CUL_HM_name2Id($sId);
      my $recID = CUL_HM_name2Id($rId);
      if ($sndID !~ m/(^[0-9A-F]{6})$/){$sndID = AttrVal($sId,"hmId","");};
      if ($recID !~ m/(^[0-9A-F]{6})$/){$recID = AttrVal($rId,"hmId","");};
      return "sender ID $sId unknown:".$sndID    if ($sndID !~ m/(^[0-9A-F]{6})$/);
      return "receiver ID $rId unknown:".$recID  if ($recID !~ m/(^[0-9A-F]{6})$/);
      return "broadcast must be yes or now"      if ($bCst  !~ m/^(yes|no)$/);
      $pattern = $sndID.$recID.(($bCst eq "no")?"00":"01");
      $cnt = ($eNo-1)*7+1;
      $rPeer[$eNo-1] = "$sId:$rId:".(($bCst eq "no")?"n":"y");
      $attr{$name}{repPeers} = join",",@rPeer;
    }
    my $addrData;
    foreach ($pattern =~ /(.{2})/g){
      $addrData .= sprintf("%02X%s",$cnt++,$_);
    }
    CUL_HM_pushConfig($hash, $id, $dst, 1,0,0,2, $addrData);
  }
  elsif($cmd eq "display") { ##################################################
    my (undef,undef,undef,$t,$c,$u,$snd,$blk,$symb) = @_;
    return "cmd only possible for device or its display channel"
           if ($roleC && $chn ne "12");
    my %symbol=(off => 0x0000,
                bulb =>0x0100,switch =>0x0200,window   =>0x0400,door=>0x0800,
                blind=>0x1000,scene  =>0x2000,phone    =>0x4000,bell=>0x8000,
                clock=>0x0001,arrowUp=>0x0002,arrowDown=>0x0004);
    my %light=(off=>0,on=>1,slow=>2,fast=>3);
    my %unit=(off =>0,Proz=>1,Watt=>2,x3=>3,C=>4,x5=>5,x6=>6,x7=>7,
              F=>8,x9=>9,x10=>10,x11=>11,x12=>12,x13=>13,x14=>14,x15=>15);

    my @symbList = split(',',$symb);
    my $symbAdd = 0;
    foreach my $symb (@symbList){
      if (!defined($symbol{$symb})){# wrong parameter
        return "'$symb ' unknown. Select one of ".join(" ",sort keys(%symbol));
      }
      $symbAdd |= $symbol{$symb};
    }

    return "$c not specified. Select one of [comma|no]"
           if ($c ne "comma" && $c ne "no");
    return "'$u' unknown. Select one of ".join(" ",sort keys(%unit))
           if (!defined($unit{$u}));
    return "'$snd' unknown. Select one of [off|1|2|3]"
           if ($snd ne "off" && $snd > 3);
    return "'$blk' unknown. Select one of ".join(" ",sort keys(%light))
           if (!defined($light{$blk}));
    my $beepBack = $snd | $light{$blk}*4;

    $symbAdd |= 0x0004 if ($c eq "comma");
    $symbAdd |= $unit{$u};

    my $text = sprintf("%5.5s",$t);#pad left with space
    $text = uc(unpack("H*",$text));

    CUL_HM_PushCmdStack($hash,sprintf("++%s11%s%s8012%s%04X%02X",
                                      $flag,$id,$dst,$text,$symbAdd,$beepBack));
  }
  elsif($cmd =~ m/^(alarm|service)$/) { #######################################
    return "$a[2] must be below 255"  if ($a[2] >255 );
    $chn = 18 if ($chn eq "01");
    my $subtype = ($cmd eq "alarm")?"81":"82";
    CUL_HM_PushCmdStack($hash,
          sprintf("++%s11%s%s%s%s%02X",$flag,$id,$dst,$subtype,$chn, $a[2]));
  }
  elsif($cmd eq "led") { ######################################################
    if ($md eq "HM-OU-LED16"){
      my %color=(off=>0,red=>1,green=>2,orange=>3);
      if (length($hash->{DEF}) == 6){# command called for a device, not a channel
        my $col4all;
        if (defined($color{$a[2]})){
          $col4all = sprintf("%02X",$color{$a[2]}*85);#Color for 4 LEDS
          $col4all = $col4all.$col4all.$col4all.$col4all;#and now for 16
        }
        elsif ($a[2] =~ m/^[A-Fa-f0-9]{1,8}$/i){
          $col4all = sprintf("%08X",hex($a[2]));
        }
        else{
            return "$a[2] unknown. use hex or: ".join(" ",sort keys(%color));
        }
        CUL_HM_UpdtReadBulk($hash,1,"color:".$col4all,
                                    "state:set_".$col4all);
        CUL_HM_PushCmdStack($hash,"++".$flag."11".$id.$dst."8100".$col4all);
      }
      else{# operating on a channel
          return "$a[2] unknown. use: ".join(" ",sort keys(%color))
              if (!defined($color{$a[2]}) );
        CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'80'.$chn.'0'.$color{$a[2]});
      }
    }
    elsif($md =~ m/HM-OU-CFM?-PL/){
      my %color = (redL =>18,greenL =>34,orangeL =>50,
                   redS =>17,greenS =>33,orangeS =>49,
                   pause=>01);
      my @itemList = split(',',$a[2]);
      my $repeat = (defined $a[3] && $a[3] =~ m/^(\d+)$/)?$a[3]:1;
      my $itemCnt = int(@itemList);
      return "no more then 10 entries please"      if ($itemCnt>10);
      return "at least one entry must be entered"  if ($itemCnt<1);
      return "repetition $repeat out of range [1..255]"
          if($repeat < 1 || $repeat > 255);
      #<entries><multiply><MP3><MP3>
      my $msgBytes = sprintf("01%02X",$repeat);
      foreach my $led (@itemList){
        if (!$color{$led} ){# wrong parameter
            return "'$led' unknown. use: ".join(" ",sort keys(%color));
        }
        $msgBytes .= sprintf("%02X",$color{$led});
      }
      $msgBytes .= "01" if ($itemCnt == 1 && $repeat == 1);#add pause to term LED
      # need to fill up empty locations  for LED channel
      $msgBytes = substr($msgBytes."000000000000000000",0,(10+2)*2);
      CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'80'.$chn.$msgBytes);
    }
    else{
      return "device for command cannot be identified";
    }
  }
  elsif($cmd eq "playTone") { #################################################
    my $msg;
    if ($a[2] eq 'replay'){
      $msg = ReadingsVal($chnHash->{NAME},".lastTone","");
    }
    else{
      my @itemList = split(',',$a[2]);
      my $repeat = (defined $a[3] && $a[3] =~ m/^(\d+)$/)?$a[3]:1;
      my $itemCnt = int(@itemList);
      return "no more then 12 entries please"  if ($itemCnt>12);
      return "repetition $repeat out of range [1..255]"
            if($repeat < 1 || $repeat > 255);
      #<entries><multiply><MP3><MP3>
      my $msgBytes = sprintf("%02X%02X",$itemCnt,$repeat);
      foreach my $mp3 (@itemList){
        return "input: $mp3 is not an integer below 255" 
           if (!defined $mp3 || $mp3 !~ /^[+-]?\d+$/ || $mp3 > 255);
        $msgBytes .= sprintf("%02X",$mp3);
      }
      $msg = '++'.$flag.'11'.$id.$dst.'80'.$chn.$msgBytes;
      CUL_HM_UpdtReadSingle($chnHash,".lastTone",$msg,0);
    }
    CUL_HM_PushCmdStack($hash,$msg) if ($msg);
  }
  elsif($cmd eq "displayWM" ) { ###############################################
    $state = "";
    # textNo color icon
    my $param = (scalar(@a)-2);
    if ($a[2] eq "help"){
      my $ret = "text :\n      <text> max 2 char";
      foreach (sort keys %disBtn){
        my (undef,$ch,undef,$ln) = unpack('A3A2A1A1',$_);
        $ch = sprintf("%02X",$ch);
        $ret .= "\n      $_ ->" 
                  .ReadingsVal( InternalVal($devName,"channel_$ch","no")
                                ,"text$ln","unkown");
      }
      $ret .= "\n      off nc(no change)"
             ."\ncolor:".join(",",sort keys %disColor)
             ."\n      nc(no change)"
             ."\nicon :".join(",",sort keys %disIcon)
             ;
      return $ret;
    }

    return "$a[2] not valid - choose short or long" if($a[2] !~ m/(short|long)/);
    my $type = $a[2] eq "short"?"s":"l";

    if(!defined $hash->{helper}{dispi}{$type}{"l1"}{d}){# setup if one is missing
      $hash->{helper}{dispi}{$type}{"l$_"}{d}=1 foreach (1,2,3,4,5,6);
    }

    if($a[3] =~ m/^line(.)$/){
      my $lnNr = $1;
      return "line number wrong - use 1..6" if($lnNr !~ m/[1-6]/);
      return "please add a text " if(!$a[4]);
      my $lnRd = "disp_$a[2]_l$lnNr";# reading assotiated with this entry
      my $dh = $hash->{helper}{dispi}{$type}{"l$lnNr"};
      if ($a[4] eq "off"){ #no display in this line
        delete $dh->{txt};
      }
      elsif($a[4] =~ m/^e:/){ # equation
        $dh->{d} = 2; # mark as equation
        $dh->{exe} = $a[4];
        $dh->{exe} =~ s/^e://;
        ($dh->{txt},$a[5],$a[6]) = eval $dh->{exe};
        return "define eval must return 3 values:" if(!defined $a[6]);
      }
      elsif($a[4] ne "nc"){ # new text
        return "text too long " .$a[4]   if (length($a[4])>12);
        $dh->{txt}=$a[4];
      }

      if($a[5]){ # set new color
        if($a[5] eq "off"){ # set new color
          delete $dh->{col};
        }
        elsif($a[5] ne "nc"){ # set new color
          return "color wrong $a[5] use:".join(",",sort keys %disColor) if (!defined $disColor{$a[5]});
          $dh->{col}=$a[5];
        }
      }

      if($a[6]){ # new icon
        if($a[6] eq "noIcon"){ # new icon
          delete $dh->{icn};
        }
        elsif($a[6] ne "nc"){ # new icon
          return "icon wrong $a[6] use:".join(",",sort keys %disIcon)  if (!defined $disIcon {$a[6]});
          $dh->{icn}=$a[6];
        }
      }
    }
    else{
      return "not enough parameter - always use txtNo, color and icon in a set"
            if(($param-1) %3);
      for (my $cnt=3;$cnt<$param;$cnt+=3){ 
        my $lnNr = int($cnt/3);
        my $dh = $hash->{helper}{dispi}{$type}{"l$lnNr"};
        return "color wrong ".$a[$cnt+1]." use:".join(",",sort keys %disColor) if (!defined $disColor{$a[$cnt+1]});
        return "icon wrong " .$a[$cnt+2]." use:".join(",",sort keys %disIcon)  if (!defined $disIcon {$a[$cnt+2]});
        return "text too long " .$a[$cnt+0]   if (length($a[$cnt+0])>12);
        if    ($a[$cnt+0] eq "nc") {} # nc = no change
        elsif ($a[$cnt+0] eq "off"){ delete $dh->{txt}      } # off =  no text display
        else                       {$dh->{txt} = $a[$cnt+0];} # nc = no change

        $dh->{col} = $a[$cnt+1];
        $dh->{icn} = $a[$cnt+2];
        delete $dh->{icn} if ($a[$cnt+2] eq "noIcon");
      }
    }

    foreach my $t (keys %{$hash->{helper}{dispi}}){ # prepare the messages
      CUL_HM_calcDisWm($hash,$devName,$t);
    }
  }

  elsif($cmd =~ m/^(controlMode|controlManu|controlParty)$/) { ################
    my $mode = $a[2];
    if ($cmd ne "controlMode"){
      $mode = substr($cmd,7);
      $mode =~ s/^Manu$/manual/;
      $a[2] = ($a[2] eq "off")?4.5:($a[2] eq "on"?30.5:$a[2]);
    }
    $mode = lc $mode;
    return "invalid $mode:select of mode [auto|boost|day|night] or"
          ." controlManu,controlParty"
                if ($mode !~ m/^(auto|manual|party|boost|day|night)$/);
    my ($temp,$party);
    if ($mode =~ m/^(auto|boost|day|night)$/){
      return "no additional params for $mode" if ($a[3]);
    }
    if($mode eq "manual"){
      my $t = $a[2] ne "manual"?$a[2]:ReadingsVal($name,"desired-temp",18);
      if ($md =~ m/CC-TC/){$t = ($t eq "off")?4.5:(($t eq "on" )?30.5:$t);}
      else                {$t = ($t eq "off")?5  :(($t eq "on" )?30  :$t);}
      return "temperatur for manual  4.5 to 30.5 C"
                if ($t < 4.5 || $t > 30.5);
      $temp = $t*2;
    }
    elsif($mode eq "party"){
      return  "use party <temp> <from-time> <from-date> <to-time> <to-date>\n"
             ."temperatur: 5 to 30 C\n"
             ."date format: party 10 03.8.13 11:30 5.8.13 12:00"
                if (!$a[2] || $a[2] < 5 || $a[2] > 30 || !$a[6] );
      $temp = $a[2]*2;
      # party format 03.8.13 11:30 5.8.13 12:00
      my ($sd,$sm,$sy) = split('\.',$a[3]);
      my ($sh,$smin)   = split(':' ,$a[4]);
      my ($ed,$em,$ey) = split('\.',$a[5]);
      my ($eh,$emin)   = split(':' ,$a[6]);

      return "wrong start day $sd"   if ($sd < 0 || $sd > 31);
      return "wrong start month $sm" if ($sm < 0 || $sm > 12);
      return "wrong start year $sy"  if ($sy < 0 || $sy > 99);
      return "wrong start hour $sh"  if ($sh < 0 || $sh > 23);
      return "wrong start minute $smin, ony 00 or 30" if ($smin != 0 && $smin != 30);
      $sh = $sh * 2 + $smin/30;

      return "wrong end day $ed"   if ($ed < 0 || $ed > 31);
      return "wrong end month $em" if ($em < 0 || $em > 12);
      return "wrong end year $ey"  if ($ey < 0 || $ey > 99);
      return "wrong end hour $eh"  if ($eh < 0 || $eh > 23);
      return "wrong end minute $emin, ony 00 or 30" if ($emin != 0 && $emin != 30);
      $eh = $eh * 2 + $emin/30;

      $party = sprintf("%02X%02X%02X%02X%02X%02X%02X",
                        $sh,$sd,$sy,$eh,$ed,$ey,($sm*16+$em));
    }
    my %mCmd = (auto=>0,manual=>1,party=>2,boost=>3,day=>4,night=>5);
    CUL_HM_UpdtReadSingle($hash,"controlMode","set_".$mode,1);
    my $msg = '8'.($mCmd{$mode}).$chn;
    $msg .= sprintf("%02X",$temp) if ($temp);
    $msg .= $party if ($party);
    CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.$msg);
  }
  elsif($cmd eq "desired-temp") { #############################################
    if ($md =~ m/(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)/){
      my $temp = ($a[2] eq "off")?9:($a[2] eq "on"?61:$a[2]*2);
      return "invalid temp:$a[2]" if($temp <9 ||$temp > 61);
      $temp = sprintf ("%02X",$temp);
      CUL_HM_PushCmdStack($hash,'++'.$flag."11$id$dst"."8604$temp");
    }
    else{
      my $temp = CUL_HM_convTemp($a[2]);
      return $temp if($temp =~ m/Invalid/);
      CUL_HM_PushCmdStack($hash,'++'.$flag.'11'.$id.$dst.'0202'.$temp);
      my $chnHash = CUL_HM_id2Hash($dst."02");
      my $mode = ReadingsVal($chnHash->{NAME},"R-controlMode","");
      $mode =~ s/set_//;#consider set as given
      CUL_HM_UpdtReadSingle($chnHash,"desired-temp-cent",$a[2],1)
            if($mode =~ m/central/);
    }
  }
  elsif($cmd =~ m/^tempList(...)$/) { ##################################### reg
    my $wd = $1;
    $state= "";
    my ($list,$addr,$prgChn);
    if ($md =~ m/(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)/){
      my %day2off = ( "Sat"=>"20", "Sun"=>"46", "Mon"=>"72", "Tue"=>"98",
                      "Wed"=>"124","Thu"=>"150","Fri"=>"176");
      ($list,$addr,$prgChn) = (7,$day2off{$wd},0);
    }
    else{
      my %day2off = ( "Sat"=>"5 0B", "Sun"=>"5 3B", "Mon"=>"5 6B",
                      "Tue"=>"5 9B", "Wed"=>"5 CB", "Thu"=>"6 01",
                      "Fri"=>"6 31");
      ($list,$addr) = split(" ", $day2off{$wd},2);
      $prgChn = 2;
      $addr = hex($addr);
    }

    my $prep = "";
    if ($a[2] =~ m/^(prep|exec)$/){
      $prep = $a[2];
      splice  @a,2,1;#remove prep
    }
    if ($md =~ m/HM-TC-IT-WM-W-EU/ && $a[2] =~ m/^p([123])$/){
      $list +=  $1 - 1;
      splice  @a,2,1;#remove list
    }
    return "To few arguments"                if(@a < 4);
    return "To many arguments, max 13 pairs" if(@a > 28 && $md =~ m/(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)/);
    return "To many arguments, max 24 pairs" if(@a > 50 && $md !~ m/(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)/);
    return "Bad format, use HH:MM TEMP ..."  if(@a % 2);
    return "Last time spec must be 24:00"    if($a[@a-2] ne "24:00");

    my ($data,$msg) = ("","");
    for(my $idx = 2; $idx < @a; $idx += 2) {
      return "$a[$idx] is not in HH:MM format"
                                if($a[$idx] !~ m/^([0-2]\d):([0-5]\d)/);
      my ($h, $m) = ($1, $2);
      my ($hByte,$lByte);
      my $temp = $a[$idx+1];
      if ($md =~ m/(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)/){
        $temp = (int($temp*2)<<9) + ($h*12+($m/5));
        $hByte = $temp>>8;
        $lByte = $temp & 0xff;
      }
      else{
        $temp = CUL_HM_convTemp($temp);
        return $temp if($temp =~ m/Invalid/);
        $hByte = $h*6+($m/10);
        $lByte = hex($temp);
      }
      $data .= sprintf("%02X%02X%02X%02X", $addr, $hByte, $addr+1,$lByte);
      $addr += 2;

      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{HOUR} = $h;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{MINUTE} = $m;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{TEMP} = $a[$idx+1];
      $msg .= sprintf(" %02d:%02d %.1f", $h, $m, $a[$idx+1]);
    }
    CUL_HM_pushConfig($hash, $id, $dst, $prgChn,0,0,$list, $data,$prep);
  }
  elsif($cmd eq "tempListTmpl") { #############################################
    $state= "";
    my $action = "verify";#defaults
    my $template = AttrVal($name,"tempListTmpl","tempList.cfg:$name");
    for my $ax ($a[2],$a[3]){
      next if (!$ax);
      if ($ax =~ m/^(verify|restore)$/){
        $action = $ax;
      }
      else{
        $template = $ax if ($ax);
      }
    }
    my $ret = CUL_HM_tempListTmpl($name,$action,$template);
    $ret = "verifed with no faults" if (!$ret && $action eq "verify");
    return $ret;
  }
  elsif($cmd eq "sysTime") { ##################################################
    $state = "";
    my $s2000 = sprintf("%02X", CUL_HM_secSince2000());
    CUL_HM_PushCmdStack($hash,"++803F$id${dst}0204$s2000");
  }
  elsif($cmd =~ m/^(valvePos|virtTemp|virtHum)$/) { ###########################
    my $valu = $a[2];

    my %lim = (valvePos =>{min=>0  ,max=>99 ,rd =>"valvePosTC" ,u =>" %"},
               virtTemp =>{min=>-20,max=>50 ,rd =>"temperature",u =>""  },
               virtHum  =>{min=>0  ,max=>99 ,rd =>"humidity"   ,u =>""  },);
    if ($md eq "HM-CC-VD"){
      return "level between $lim{$cmd}{min} and $lim{$cmd}{max} allowed"
             if ($valu !~ m/^[+-]?\d+\.?\d+$/||
                 $valu > $lim{$cmd}{max}||$valu < $lim{$cmd}{min} );
      CUL_HM_PushCmdStack($hash,'++A258'.$id.$dst
                                ."00".sprintf("%02X",($valu * 2.56)%256));
    }
    else{
      my $u = $lim{$cmd}{u};
      if ($valu eq "off"){
        $u = "";
        if ($cmd eq "virtHum") {$hash->{helper}{vd}{vinH} = "";}
        else                   {$hash->{helper}{vd}{vin}  = "";}
        if ((!$hash->{helper}{vd}{vinH} || $hash->{helper}{vd}{vinH} eq "") && 
            (!$hash->{helper}{vd}{vin}  || $hash->{helper}{vd}{vin}  eq "") ){
          $state = "$cmd:stopped";
          RemoveInternalTimer("valvePos:$dst$chn");# remove responsePending timer
          RemoveInternalTimer("valveTmr:$dst$chn");# remove responsePending timer
          delete($hash->{helper}{virtTC});
        }
      }
      if ($hash->{helper}{virtTC} || $valu ne "off") {
        if ($valu ne "off"){
          return "level between $lim{$cmd}{min} and $lim{$cmd}{max} or 'off' allowed"
               if ($valu !~ m/^[+-]?\d+\.?\d*$/||
                   $valu > $lim{$cmd}{max}||$valu < $lim{$cmd}{min} );
          if ($cmd eq "virtHum") {$hash->{helper}{vd}{vinH} = $valu;}
          else                   {$hash->{helper}{vd}{vin}  = $valu;}
        }
        $attr{$devName}{msgRepeat} = 0;#force no repeat
        if ($cmd eq "valvePos"){
          my @pId = grep !/^$/,split(',',AttrVal($name,"peerIDs",""));
          return "virtual TC support one VD only. Correct number of peers"
            if (scalar @pId != 1);
          my $ph = CUL_HM_id2Hash($pId[0]);
          return "peerID $pId[0] is not assigned to a device " if (!$ph);
          $hash->{helper}{vd}{typ} = 1; #valvePos
          my $idDev = substr($pId[0],0,6);
          $hash->{helper}{vd}{nDev}  =  CUL_HM_id2Name($idDev);
          $hash->{helper}{vd}{id}  = $modules{CUL_HM}{defptr}{$pId[0]}
                                                ?$pId[0]
                                                :$idDev;
          $hash->{helper}{vd}{cmd} = "A258$dst$idDev";
          CUL_HM_UpdtReadBulk($ph,1,
                           "state:set_$valu %",
                           "ValveDesired:$valu %");
          $hash->{helper}{vd}{val} = sprintf("%02X",($valu * 2.56)%256);
          $state = "ValveAdjust:$valu %";
        }
        else{#virtTemp || virtHum
          $hash->{helper}{vd}{typ} = 2; #virtTemp
          $hash->{helper}{vd}{cmd} = "8670$dst"."000000";
          my $t = $hash->{helper}{vd}{vin}?$hash->{helper}{vd}{vin}:0;
          $t *=10;
          $t -= 0x8000 if ($t < 0);
          $hash->{helper}{vd}{val} = sprintf("%04X", $t & 0x7fff);
          $hash->{helper}{vd}{val} .= sprintf("%02X", $hash->{helper}{vd}{vinH})
               if ($hash->{helper}{vd}{vinH} && $hash->{helper}{vd}{vinH} ne "");
        }
        $hash->{helper}{vd}{idh} = hex(substr($dst,2,2))*20077;
        $hash->{helper}{vd}{idl} = hex(substr($dst,4,2))*256;
        ($hash->{helper}{vd}{msgCnt},$hash->{helper}{vd}{next}) = 
                    split(";",ReadingsVal($name,".next","0;".gettimeofday())) if(!defined $hash->{helper}{vd}{next});
        if (!$hash->{helper}{virtTC}){
          my $pn = CUL_HM_id2Name($hash->{helper}{vd}{id});
          $hash->{helper}{vd}{ackT} = ReadingsTimestamp($pn, "ValvePosition", "")
                                          if(!defined $hash->{helper}{vd}{ackT});
          $hash->{helper}{vd}{miss}   = 0 if(!defined $hash->{helper}{vd}{miss});
          $hash->{helper}{vd}{msgRed} = 0 if(!defined $hash->{helper}{vd}{msgRed});

          $hash->{helper}{virtTC}   = ($cmd eq "valvePos")?"03":"00";
          CUL_HM_UpdtReadSingle($hash,"valveCtrl","init",1)
                if ($cmd eq "valvePos");
          $hash->{helper}{vd}{next} = ReadingsVal($name,".next",gettimeofday()) 
                if (!defined $hash->{helper}{vd}{next});
          CUL_HM_valvePosUpdt("valvePos:$dst$chn");
        }
        $hash->{helper}{virtTC} = ($cmd eq "valvePos")?"03":"00";
      }
      CUL_HM_UpdtReadSingle($hash,$lim{$cmd}{rd},$valu.$u,1);
    }
  }

  elsif($cmd eq "keydef") { ############################################### reg
    if (     $a[3] eq "tilt")      {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,"0B220D838B228D83");#JT_ON/OFF/RAMPON/RAMPOFF short and long
    } elsif ($a[3] eq "close")     {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,"0B550D838B558D83");#JT_ON/OFF/RAMPON/RAMPOFF short and long
    } elsif ($a[3] eq "closed")    {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,"0F008F00");        #offLevel (also thru register)
    } elsif ($a[3] eq "bolt")      {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,"0FFF8FFF");        #offLevel (also thru register)
    } elsif ($a[3] eq "speedclose"){CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,sprintf("23%02XA3%02X",$a[4]*2,$a[4]*2));#RAMPOFFspeed (also in reg)
    } elsif ($a[3] eq "speedtilt") {CUL_HM_pushConfig($hash,$id,$dst,1,$id,$a[2],3,sprintf("22%02XA2%02X",$a[4]*2,$a[4]*2));#RAMPOFFspeed (also in reg)
    } else                         {return 'unknown argument '.$a[3];
    }
  }
  elsif($cmd eq "teamCall") { #################################################
    $state = "";
    my $testnr = $hash->{TESTNR} ? ($hash->{TESTNR} +1) : 1;
    $hash->{TESTNR} = $testnr;
    my $tstNo = sprintf("%02X",$testnr);
    my $msg = "++9440".$dst.$dst."00".$tstNo;
    CUL_HM_PushCmdStack($hash, $msg);
    CUL_HM_parseSDteam("40",$dst,$dst,"00".$tstNo);
  }
  elsif($cmd =~ m/alarm(.*)/) { ###############################################
    $state = "";
    my $p = (($1 eq "On")?"0BC8":"0C01");
    my $msg = "++9441".$dst.$dst."01".$p;
    CUL_HM_PushCmdStack($hash, $msg);# repeat non-ack messages 3 times
    CUL_HM_PushCmdStack($hash, $msg);
    CUL_HM_PushCmdStack($hash, $msg);
    CUL_HM_parseSDteam("41",$dst,$dst,"01".$p);
  }

  elsif($cmd eq "virtual") { ##################################################
    $state = "";
    my (undef,undef,$maxBtnNo) = @a;
    return "please give a number between 1 and 50"
       if ($maxBtnNo < 1 ||$maxBtnNo > 50);# arbitrary - 255 should be max
    return $name." already defines as ".$attr{$name}{subType}
       if ($attr{$name}{subType} && $attr{$name}{subType} ne "virtual");
    $attr{$name}{subType} = "virtual";
    $attr{$name}{model}   = "virtual_".$maxBtnNo 
       if (!$attr{$name}{model} ||$attr{$name}{model} =~ m/^virtual_/);
    my $devId = $hash->{DEF};
    for (my $btn=1;$btn <= $maxBtnNo;$btn++){
      my $chnName = $name."_Btn".$btn;
      my $chnId = $devId.sprintf("%02X",$btn);
      CommandDefine(undef,"$chnName CUL_HM $chnId")
          if (!$modules{CUL_HM}{defptr}{$chnId});
    }
    foreach my $channel (keys %{$hash}){# remove higher numbers
      my $chNo = $1 if($channel =~ m/^channel_(.*)/);
      next if (!defined($chNo));
      CommandDelete(undef,$hash->{$channel})
            if (hex($chNo) > $maxBtnNo);
    }
    CUL_HM_UpdtCentral($name) if ($md eq "CCU_FHEM");
  }
  elsif($cmd eq "update") { ###################################################
    $state = "";
    if ($md eq "ActionDetector"){
      CUL_HM_ActCheck("ActionDetector");
    }
    else{
      CUL_HM_UpdtCentral($name);
    }
  }

  elsif($cmd eq "press") { ####################################################
    # [long|short] [<peer>] [<repCount(long only)>] [<repDelay>] [<forceTiming[0|1]>] ...
    my ($repCnt,$repDly,$forceTiming,$mode) = (0,0,0,0);
    if ($a[2]){
      ##############################
      if ($a[2] eq "long"){
        $mode = 64;
        splice @a,2,1;
        (undef,undef,undef,$repCnt,$repDly,$forceTiming) = @a;
        $repCnt      = 1    if (!defined $repCnt     );
        $repDly      = 0.25 if (!defined $repDly     );
        $forceTiming = 1    if (!defined $forceTiming);
        return "repeatCount $repCnt invalid. use value 1 - 255"     if ($repCnt < 1    || $repCnt>255 );
        return "repDelay $repDly invalid. use value 0.25 - 1.00"    if ($repDly < 0.25 || $repDly>1 );
        return "forceTiming $forceTiming invalid. use value 0 or 1" if ($forceTiming ne "0" && $forceTiming ne "1" );
      }
      elsif($a[2] eq "short"){
        splice @a,2,1;
      }
    }
    my $vChn = $a[2]?$a[2]:"";
    
    my $pressCnt = (!$hash->{helper}{count}?1:$hash->{helper}{count}+1)%256;
    $hash->{helper}{count}=$pressCnt;# remember for next round
    if ($st eq 'virtual'){#serve all peers of virtual button
      my @peerLchn = split(',',AttrVal($name,"peerIDs",""));
      my @peerList = map{substr($_,0,6)} @peerLchn;
      @peerList = grep !/000000/,grep !/^$/,CUL_HM_noDup(@peerList);
      my $pc =  sprintf("%02X%02X",hex($chn)+$mode,$pressCnt);# msg end
      my $snd = 0;
      foreach my $peer (sort @peerList){
        my ($pHash,$peerFlag,$rxt);
        $pHash = CUL_HM_id2Hash($peer);
        next if (   !$pHash 
                 || !$pHash->{helper}{role}
                 || !$pHash->{helper}{role}{prs});
        $rxt = CUL_HM_getRxType($pHash);
        $peerFlag = ($rxt & 0x02)?"B4":"A4" if($vChn ne "noBurst");#burst
        CUL_HM_PushCmdStack($pHash,"++${peerFlag}40$dst$peer$pc");
        $snd = 1;
        foreach my $pCh(grep /$peer/,@peerLchn){
          my $n = CUL_HM_id2Name($pCh);
          next if (!$n);
          $n =~s/_chn:.*//;
          delete $defs{$n}{helper}{dlvl};#stop desiredLevel supervision
          CUL_HM_stateUpdatDly($n,10);
        }
        if ($rxt & 0x80){#burstConditional
          CUL_HM_SndCmd($pHash, "++B112$id".substr($peer,0,6))
                if($vChn ne "noBurst");
        }
        else{
          CUL_HM_ProcessCmdStack($pHash);
        }
      }
      if(!$snd){# send 2 broadcast if no relevant peers 
        CUL_HM_PushCmdStack($hash,"++8440${dst}000000$pc");
      }
    }
    else{#serve internal channels for actor
      #which button shall be simulated? We offer
      # on/off: self button - on is even/off odd number. Obey channel
      # name of peer
      my $pId;
      if ($vChn =~ m /^(on|off)$/ && $st =~ m/(blindActuator|dimmer)/){
        $pId = $dst.sprintf("%02X",(($vChn eq "off")?-1:0) + $chn*2);
      }
      elsif($vChn){
        $pId = CUL_HM_name2Id($vChn,$devHash)."01";#01 is default for devices
      }
      else{
        $pId = $dst.sprintf("%02X",$chn);
      }
      my ($pDev,$pCh) = unpack 'A6A2',$pId;
      return "button cannot be identified" if (!$pCh);
      delete $hash->{helper}{dlvl};#stop desiredLevel supervision

      my $msg = sprintf("3E%s%s%s40%02X%02X",
                                     $id,$dst,$pDev,
                                     hex($pCh)+$mode,
                                     $pressCnt);
      for (my $cnt = 1;$cnt < $repCnt; $cnt++ ){
        CUL_HM_SndCmd($hash, "++80$msg");
        select(undef, undef, undef, $repDly);
      }
      CUL_HM_SndCmd($hash, "++${flag}$msg");
    }
  }
  elsif($cmd eq "fwUpdate") { #################################################
    return "no filename given" if (!$a[2]);
#    return "only thru CUL " if (!$hash->{IODev}->{TYPE}
#                                 ||($hash->{IODev}->{TYPE} ne "CUL"));
    # todo add version checks of CUL
    my ($fName,$pos,$enterBL) = ($a[2],0,($a[3] ? $a[3]+0 : 10));
    my @imA; # image array: image[block][msg]

    return "Illegal waitTime $enterBL - enter a value between 10 and 300" 
         if ($enterBL < 10 || $enterBL>300);    

    open(aUpdtF, $fName) || return("Can't open $fName: $!");
    while(<aUpdtF>){
      my $line = $_;
      my $fs = length($line);
      while ($fs>$pos){
        my $bs = hex(substr($line,$pos,4))*2+4;	  
        return "file corrupt. length:$fs expected:".($pos+$bs) 
              if ($fs<$pos+$bs);
        my @msg = grep !/^$/,unpack '(A60)*',substr($line,$pos,$bs);
        push @imA,\@msg; # image[block][msg]
        $pos += $bs;
      }
    }
    close(aUpdtF);
    # --- we are prepared start update---
    CUL_HM_protState($hash,"CMDs_FWupdate");
    $modules{CUL_HM}{helper}{updating} = 1;
    $modules{CUL_HM}{helper}{updatingName} = $name;
    $modules{CUL_HM}{helper}{updateData} = \@imA;
    $modules{CUL_HM}{helper}{updateStep} = 0;
    $modules{CUL_HM}{helper}{updateDst} = $dst;
    $modules{CUL_HM}{helper}{updateId} = $id;
    $modules{CUL_HM}{helper}{updateNbr} = 10;
    Log3 $name,2,"CUL_HM fwUpdate started for $name";
    CUL_HM_SndCmd($hash, sprintf("%02X",$modules{CUL_HM}{helper}{updateNbr})
                        ."3011$id${dst}CA");
                        
    $hash->{helper}{io}{newChnFwUpdate} = $hash->{helper}{io}{newChn};#temporary hide init message
    $hash->{helper}{io}{newChn} = "";

    InternalTimer(gettimeofday()+$enterBL,"CUL_HM_FWupdateEnd","fail:notInBootLoader",0);
    #InternalTimer(gettimeofday()+0.3,"CUL_HM_FWupdateSim",$dst."00000000",0);
  }
  elsif($cmd eq "postEvent") { ################################################
    my (undef,undef,$cond) = @a;
    my $cndNo;
    if ($cond =~ m/[+-]?\d+/){
      return "condition value:$cond above 200 illegal" if ($cond > 200);
      $cndNo = $cond;
    }
    else{
      my @keys;
      if ($chnHash->{helper}{lm}){
        foreach (keys %{$chnHash->{helper}{lm}}){
          if ($chnHash->{helper}{lm}{$_} eq $cond){
            $cndNo = $_;
            last;
          }
          push @keys,$chnHash->{helper}{lm};
        }
      }
      else{
        foreach my $tp (keys %lvlStr){
          foreach my $mk (keys %{$lvlStr{$tp}}){
            foreach (keys %{$lvlStr{$tp}{$mk}}){
              $cndNo = hex($_) if ($cond eq $lvlStr{$tp}{$mk}{$_});
              push @keys,$lvlStr{$tp}{$mk}{$_};
            }
          }
        }
      }
      return "cond:$cond not allowed. choose one of:[0..200],"
            .join(",",sort @keys)
        if (!defined $cndNo);
    }
    my $pressCnt = (!$hash->{helper}{count}?1:$hash->{helper}{count}+1)%256;
    $hash->{helper}{count}=$pressCnt;# remember for next round

    my @peerLChn = split(',',AttrVal($name,"peerIDs",""));
    my @peerDev;
    push (@peerDev,substr($_,0,6)) foreach (@peerLChn);
    @peerDev = CUL_HM_noDup(@peerDev);#only once per device!

    push @peerDev,'000000' if (!@peerDev);#send to broadcast if no peer
    foreach my $peer (@peerDev){
      my $pHash = CUL_HM_id2Hash($peer);
      my $rxt = CUL_HM_getRxType($pHash);
      my $peerFlag = ($rxt & 0x02)?"B4":"A4";#burst
      CUL_HM_PushCmdStack($pHash, sprintf("++%s41%s%s%02X%02X%02X"
                     ,$peerFlag,$dst,$peer
                     ,hex($chn)
                     ,$pressCnt
                     ,$cndNo));
      if ($rxt & 0x80){#burstConditional
        CUL_HM_SndCmd($pHash, "++B112$id".substr($peer,0,6));
      }
      else{
        CUL_HM_ProcessCmdStack($pHash);
      }
    }

    foreach my $peer (@peerLChn){#inform each channel
      my $pName = CUL_HM_id2Name($peer);
      $pName = CUL_HM_id2Name(substr($peer,0,6)) if (!$defs{$pName});
      next if (!$defs{$pName});
      CUL_HM_UpdtReadBulk($defs{$pName},1
                            ,"trig_$name:$cond"
                            ,"trigLast:$name:$cond");
    }
  }

  elsif($cmd eq "peerIODev") { ################################################
    # peerIODev [IO] <chn> [set|unset]...
    $state = "";
    return "command requires parameter" if (!$a[2]);
    my ($ioId,$ioCh,$set) = ($id,$a[2],'set'); #set defaults
    if ($defs{$a[2]}){ #IO device given
      $ioId =  AttrVal($a[2],"hmId","");
      return "$a[2] not valid, attribut hmid not set" 
            if($ioId !~ m/^[0-9A-F]{6}$/);
      splice @a,2,1;
      $ioCh = $a[2];
    }
    $set = $a[3] if ($a[3]);
    $ioCh = sprintf("%02X",$ioCh);
    return "No:$ioCh invalid. Number must be <=50"  if (!$ioCh || $ioCh !~ m/^(\d*)$/ || $ioCh > 50);
    return "option $set unknown - use set or unset" if ($set != m/^(set|unset)$/);
    $set = ($set eq "set")?"01":"02"; 
    CUL_HM_PushCmdStack($hash,"++${flag}01$id${dst}$chn$set$ioId${ioCh}00");
  }
  elsif($cmd eq "peerChan") { ############################################# reg
    #peerChan <btnN> <device> ... [single|dual] [set|unset] [actor|remote|both]
    my ($bNo,$peerN,$single,$set,$target) = ($a[2],$a[3],($a[4]?$a[4]:"dual"),
                                                         ($a[5]?$a[5]:"set"),
                                                         ($a[6]?$a[6]:"both"));
    $state = "";
    if ($roleD){
      $bNo = 1 if ($bNo == 0 && $roleC); # role device and channel => button=1
      return "$bNo is not a button number"                        if($bNo < 1);
    }
    
    my $peerId = CUL_HM_name2Id($peerN);
    return "please enter peer"                                    if(!$peerId);
    $peerId .= "01" if( length($peerId) == 6);

    my @pCh;
    my ($peerHash,$dSet,$cmdB);
    my $peerDst = substr($peerId,0,6);
    my $pmd     = AttrVal(CUL_HM_id2Name($peerDst), "model"  , "");

    if ($md =~ m/HM-CC-RT-DN/ && $chn eq "05" ){# rt team peers cross from 05 to 04
      @pCh = (undef,"04","05");
      $chn = "04";
      $single = "dual";
      $dSet = 1;#Dual set - set 2 channels for "remote"
    }
    else{ # normal devices
      $pCh[1] = $pCh[2] = substr($peerId,6,2);
    }
    $peerHash = $modules{CUL_HM}{defptr}{$peerDst.$pCh[1]}if ($modules{CUL_HM}{defptr}{$peerDst.$pCh[1]});
    $peerHash = $modules{CUL_HM}{defptr}{$peerDst}        if (!$peerHash);
    return "$peerN not a CUL_HM device"                           if(   ($target ne "remote") 
                                                                     && (!$peerHash || $peerHash->{TYPE} ne "CUL_HM")
                                                                     &&  $defs{$devName}{IODev}->{NAME} ne $peerN);
    return "$single must be single, dual or reverse"              if($single !~ m/^(single|dual|reverse)$/);
    return "$set must be set or unset"                            if($set    !~ m/^(set|unset)$/);
    return "$target must be [actor|remote|both]"                  if($target !~ m/^(actor|remote|both)$/);
    return "use - single [set|unset] actor - for smoke detector"  if( $st eq "smokeDetector"       && ($single ne "single" || $target ne "actor"));
    return "use - single - for ".$st                              if(($st =~ m/(threeStateSensor|motionDetector)/) && ($single ne "single"));
    return "TC WindowRec only peers to channel 01 single"         if( $pmd =~ m/(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/ && $pCh[1] eq "03" && $chn ne "01" && $set eq "set");

    my $pSt = CUL_HM_Get($peerHash,$peerHash->{NAME},"param","subType");

    
    if ($set eq "unset"){$set = 0;$cmdB ="02";}
    else                {$set = 1;$cmdB ="01";}

    my (@b,$nrCh2Pair);
    $b[1] = ($roleD) ?(($single eq "single")?$bNo : ($bNo*2 - 1))
                     : hex($chn)
                       ;
    if ($single eq "single"){
      $b[2] = $b[1];
      $b[1] = 0 if ($st eq "smokeDetector" ||$pSt eq "smokeDetector");
      $nrCh2Pair = 1;
    }
    elsif($single eq "dual"){
      $single = 0;
      $b[2] = $b[1] + 1;
      $nrCh2Pair = 2;
    }
    else{#($single eq "reverse")
      $single = 0;
      $b[2] = $b[1]++;
      $nrCh2Pair = 2;
    }

    if ( $pSt eq "smokeDetector"){
      $target = "both" if ($st eq "virtual");
    }

    # First the remote (one loop for on, one for off)
    if ($target =~ m/^(remote|both)$/){
      my $burst;
      if ($culHmRegModel->{$md}{peerNeedsBurst}|| #peerNeedsBurst supported
          $culHmRegType->{$st}{peerNeedsBurst}){
        $burst = (CUL_HM_getRxType($peerHash) & 0x82) #burst |burstConditional
                           ?"0101"  
                           :"0100";
      }
      for(my $i = 1; $i <= $nrCh2Pair; $i++) {
        if ($st eq "virtual"){
          my $btnName = $pSt eq "smokeDetector" ? $name :CUL_HM_id2Name($dst.sprintf("%02X",$b[$i]));
          next if (!defined $attr{$btnName});
          CUL_HM_ID2PeerList ($btnName,$peerDst.$pCh[$i],$set); #upd. peerlist
        }
        else{
          my $bStr = sprintf("%02X",$b[$i]);
          CUL_HM_PushCmdStack($hash,
                 "++".$flag."01${id}${dst}${bStr}$cmdB${peerDst}$pCh[$i]00");
          CUL_HM_pushConfig($hash,$id, $dst,$b[$i],$peerDst,hex($pCh[$i]),4,$burst)
                   if($burst && $cmdB eq "01"); # only if set
          CUL_HM_qAutoRead($name,3);
        }
      }
      # need to send data here- this is a 2 device command... thats why. 
      my $rxType = CUL_HM_getRxType($devHash);
      if($rxType & 0x01){#allways
        CUL_HM_ProcessCmdStack($devHash);
      }
      elsif($devHash->{cmdStack}                  &&
            $devHash->{helper}{prt}{sProc} != 1    # not processing
            ){
        if($rxType & 0x02){# handle burst Access devices - add burst Bit
          my ($pre,$tp,$tail) = unpack 'A2A2A*',$devHash->{cmdStack}[0];
          $devHash->{cmdStack}[0] = sprintf("%s%02X%s",$pre,(hex($tp)|0x10),$tail);
          CUL_HM_ProcessCmdStack($devHash);
        }
        elsif (CUL_HM_getAttrInt($name,"burstAccess")){ #burstConditional - have a try
          $hash->{helper}{prt}{brstWu}=1;# start auto-burstWakeup
          CUL_HM_SndCmd($devHash,"++B112$id$dst");
        }
      }
    }
    if ($target =~ m/^(actor|both)$/ ){
      if ($modules{CUL_HM}{defptr}{$peerDst}){# is defined or ID only?
        if ($pSt eq "virtual"){
          CUL_HM_ID2PeerList ($peerN,$dst.sprintf("%02X",$b[2]),$set);
          CUL_HM_ID2PeerList ($peerN,$dst.sprintf("%02X",$b[1]),$set) 
                if ($b[1] & !$single);
        }
        else{
          my $peerFlag = CUL_HM_getFlag($peerHash);
          if ($dSet){
           CUL_HM_PushCmdStack($peerHash, sprintf("++%s01%s%s%s%s%s%02X00",$peerFlag,$id,$peerDst,$pCh[1],$cmdB,$dst,$b[1]));
           CUL_HM_PushCmdStack($peerHash, sprintf("++%s01%s%s%s%s%s%02X00",$peerFlag,$id,$peerDst,$pCh[2],$cmdB,$dst,$b[2] ));
         }
          else{
            CUL_HM_PushCmdStack($peerHash, sprintf("++%s01%s%s%s%s%s%02X%02X",$peerFlag,$id,$peerDst,$pCh[1],$cmdB,$dst,$b[2],$b[1] ));
          }
          if(CUL_HM_getRxType($peerHash) & 0x80){
            my $pDevHash = CUL_HM_id2Hash($peerDst);#put on device
            CUL_HM_pushConfig($pDevHash,$id,$peerDst,0,0,0,0,"0101");#set burstRx
          }
          CUL_HM_qAutoRead($peerHash->{NAME},3);
        }
      $devHash = $peerHash; # Exchange the hash, as the switch is always alive.
      }
    }
    return ("",1) if ($target && $target eq "remote");#Nothing for actor
  }

  elsif($cmd  =~ m/^(pair|getVersion)$/) { ####################################
    $state = "";
    my $serial = ReadingsVal($name, "D-serialNr", undef);
    return "serial $serial - wrong length or Reading D-serialNr not present"
          if(length($serial) != 10);
    CUL_HM_PushCmdStack($hash,"++A401".$id."000000010A".uc( unpack("H*",$serial)));
    $hash->{hmPairSerial} = $serial if ($cmd eq "pair");
  }
  elsif($cmd eq "hmPairForSec") { #############################################
    $state = "";
    my $arg = $a[2]?$a[2]:"";
    return "Usage: set $name hmPairForSec <seconds_active>"
        if( $arg !~ m/^\d+$/);
    CUL_HM_RemoveHMPair("hmPairForSec:$name");
    $hash->{hmPair} = 1;
    InternalTimer(gettimeofday()+$arg, "CUL_HM_RemoveHMPair", "hmPairForSec:$name", 1);
  }
  elsif($cmd eq "hmPairSerial") { #############################################
    $state = "";
    my $serial = $a[2]?$a[2]:"";
    return "Usage: set $name hmPairSerial <10-character-serialnumber>"
        if(length($serial) != 10);

    CUL_HM_PushCmdStack($hash, "++8401${dst}000000010A".uc( unpack('H*', $serial)));
    CUL_HM_RemoveHMPair("hmPairForSec:$name");
    $hash->{hmPair} = 1;
    $hash->{hmPairSerial} = $serial;
    InternalTimer(gettimeofday()+30, "CUL_HM_RemoveHMPair", "hmPairForSec:$name", 1);
  }
  elsif($cmd eq "assignIO") { #################################################
    $state = "";
    my $io = $a[2];
    return "use set of unset - $a[3] not allowed" 
          if ($a[3] && $a[3] != m/^(set|unset)$/);
    my $set = ($a[3] && $a[3] eq "unset")?0:1;
    if ($set){
      CommandAttr(undef, "$io hmId $dst");
    }
    else{
      CommandDeleteAttr(undef, "$io hmId");
    }
    CUL_HM_UpdtCentral($name);
  }
                                             
  else{
    return "$cmd not implemented - contact sysop";
  }

  CUL_HM_UpdtReadSingle($hash,"state",$state,1) if($state);

  my $rxType = CUL_HM_getRxType($devHash);
  Log3 $name,3,"CUL_HM set $name $act";
  if($rxType & 0x01){#allways
    CUL_HM_ProcessCmdStack($devHash);
  }
  elsif($devHash->{cmdStack}                  &&
        $devHash->{helper}{prt}{sProc} != 1    # not processing
        ){
    if($rxType & 0x02){# handle burst Access devices - add burst Bit
      if($st eq "thermostat"){ # others do not support B112
        CUL_HM_SndCmd($devHash,"++B112$id$dst");
      }
      else{
        my ($pre,$tp,$tail) = unpack 'A2A2A*',$devHash->{cmdStack}[0];
        $devHash->{cmdStack}[0] = sprintf("%s%02X%s",$pre,(hex($tp)|0x10),$tail);
        CUL_HM_ProcessCmdStack($devHash);
      }
    }
    elsif (CUL_HM_getAttrInt($name,"burstAccess")){ #burstConditional - have a try
      $hash->{helper}{prt}{brstWu}=1;# start auto-burstWakeup
      CUL_HM_SndCmd($devHash,"++B112$id$dst");
    }
  }
  return ("",1);# no not generate trigger outof command
}

#+++++++++++++++++ set/get support subroutines+++++++++++++++++++++++++++++++++
sub CUL_HM_valvePosUpdt(@) {#update valve position periodically to please valve
  my($in ) = @_;
  my(undef,$vId) = split(':',$in);
  my $hash = CUL_HM_id2Hash($vId);
  my $hashVd = $hash->{helper}{vd}; 
  my $name = $hash->{NAME};
  my $msgCnt = $hashVd->{msgCnt};
  my ($idl,$lo,$hi,$nextTimer);
  my $tn = gettimeofday();
  my $nextF = $hashVd->{next};
# int32_t result = (((_address << 8) | messageCounter) * 1103515245 + 12345) >> 16;
#                          4e6d = 20077                        12996205 = C64E6D
# return (result & 0xFF) + 480;
  if ($tn > ($nextF + 3000)){# missed 20 periods;
    Log3 $name,3,"CUL_HM $name virtualTC timer off by:".int($tn - $nextF);
    $nextF = $tn;
  }
  while ($nextF < ($tn+0.05)) {# calculate next time from last successful
    $msgCnt = ($msgCnt +1) %256;
    $idl = $hashVd->{idl}+$msgCnt;
    $lo = int(($idl*0x4e6d +12345)/0x10000);#&0xff;
    $hi = ($hashVd->{idh}+$idl*198);        #&0xff;
    $nextTimer = (($lo+$hi)&0xff)/4 + 120;
    $nextF += $nextTimer;
  }
  Log3  $name,5,"CUL_HM $name m:$hashVd->{msgCnt} ->$msgCnt t:$hashVd->{next}->$nextF  M:$tn :$nextTimer";
  $hashVd->{next} = $nextF;
  $hashVd->{nextM} = $tn+$nextTimer;# new adjust if we will match
  $hashVd->{msgCnt} = $msgCnt;
  if ($hashVd->{cmd}){
    if    ($hashVd->{typ} == 1){ 
      my $vc = ReadingsVal($name,"valveCtrl","init");
      if ($vc eq 'restart'){
        CUL_HM_UpdtReadSingle($hash,"valveCtrl","unknown",1);
        my $pn = CUL_HM_id2Name($hashVd->{id});
        $hashVd->{ackT} = ReadingsTimestamp($pn, "ValvePosition", "");
        $hashVd->{msgSent} = 0;
      }
      elsif(  ($vc ne "init" && $hashVd->{msgRed} <= $hashVd->{miss})
            || $hash->{helper}{virtTC} ne "00") {
        $hashVd->{msgSent} = 1;
        CUL_HM_SndCmd($defs{$hashVd->{nDev}},sprintf("%02X%s%s%s"
                                             ,$msgCnt
                                             ,$hashVd->{cmd}
                                             ,$hash->{helper}{virtTC}
                                             ,$hashVd->{val}));
      }
      InternalTimer($tn+10,"CUL_HM_valvePosTmr","valveTmr:$vId",0);
      $hashVd->{virtTC} = $hash->{helper}{virtTC};#save for repeat
      $hash->{helper}{virtTC} = "00";
    }
    elsif ($hashVd->{typ} == 2){#send to broadcast
      CUL_HM_PushCmdStack($hash,sprintf("%02X%s%s"
                                        ,$msgCnt
                                        ,$hashVd->{cmd}
                                        ,$hashVd->{val}));
      $hashVd->{next} = $hashVd->{nextM};
      InternalTimer($hashVd->{next},"CUL_HM_valvePosUpdt","valvePos:$vId",0);
    }
  }
  else{
    delete $hash->{helper}{virtTC};
    CUL_HM_UpdtReadSingle($hash,"state","stopped",1);
    return;# terminate processing
  }
  CUL_HM_ProcessCmdStack($hash);
}
sub CUL_HM_valvePosTmr(@) {#calc next vd wakeup 
  my($in ) = @_;
  my(undef,$vId) = split(':',$in);
  my $hash = CUL_HM_id2Hash($vId); 
  my $hashVd = $hash->{helper}{vd}; 
  my $name = $hash->{NAME};
  my $vc = ReadingsVal($name,"valveCtrl","init");
  my $vcn = $vc;
  if ($hashVd->{msgSent}) {
    my $pn = CUL_HM_id2Name($hashVd->{id});
    my $ackTime = ReadingsTimestamp($pn, "ValvePosition", "");
    if (!$ackTime || $ackTime eq $hashVd->{ackT} ){
      $vcn = (++$hashVd->{miss} > 5) ? "lost"
                                     :"miss_".$hashVd->{miss};
      Log3 $name,5,"CUL_HM $name virtualTC use fail-timer";
    }
    else{#successful - store sendtime and msgCnt that calculated it
      CUL_HM_UpdtReadSingle($hash,".next","$hashVd->{msgCnt};$hashVd->{nextM}",0);
      $hashVd->{next} = $hashVd->{nextM};#use adjusted value if ack
      $vcn = "ok";
      $hashVd->{miss} = 0;
    }
    $hashVd->{msgSent} = 0;
    $hashVd->{ackT} = $ackTime;
  }
  else {
    $hash->{helper}{virtTC} = $hashVd->{virtTC} if($hash->{helper}{virtTC} eq "00" && $hashVd->{virtTC});
    $hashVd->{miss}++;
  }
  CUL_HM_UpdtReadSingle($hash,"valveCtrl",$vcn,1) if($vc ne $vcn);
  InternalTimer($hashVd->{next},"CUL_HM_valvePosUpdt","valvePos:$vId",0);
}
sub CUL_HM_weather(@) {#periodically send weather data
  my($in ) = @_;
  my(undef,$name) = split(':',$in);
  my $hash = $defs{$name};
  my $dName = CUL_HM_getDeviceName($name) ;
  my $ioId = CUL_HM_IoId($defs{$dName});
  CUL_HM_SndCmd($hash,"++8670".$ioId."00000000".$hash->{helper}{weather});
  InternalTimer(gettimeofday()+150,"CUL_HM_weather","weather:$name",0);
}
sub CUL_HM_infoUpdtDevData($$$) {#autoread config
  my($name,$hash,$p) = @_;
  my($fw1,$fw2,$mId,$serNo,$stc,$devInfo) = unpack('A1A1A4A20A2A*', $p);
  
  my $md = $culHmModel->{$mId}{name} ? $culHmModel->{$mId}{name}:"unknown";
  my $serial = pack('H*',$serNo);
  my $fw = sprintf("%d.%d", hex($fw1),hex($fw2));

  $attr{$name}{model}      = $md;
  $attr{$name}{subType}    = $culHmModel->{$mId}{st};
  $attr{$name}{serialNr}   = $serial;  # to be removed from attributes
  $attr{$name}{firmware}   = $fw;      # to be removed from attributes
#  $attr{$name}{".devInfo"} = $devInfo; # to be removed from attributes
#  $attr{$name}{".stc"}     = $stc;     # to be removed from attributes
  CUL_HM_configUpdate($name) if(ReadingsVal($name,"D-firmware","") ne $fw
                              ||ReadingsVal($name,"D-serialNr","") ne $serial
                              ||ReadingsVal($name,".D-devInfo","") ne $devInfo
                              ||ReadingsVal($name,".D-stc"    ,"") ne $stc
                              ) ;
  CUL_HM_UpdtReadBulk($hash,1,"D-firmware:$fw",
                              "D-serialNr:$serial",
                              ".D-devInfo:$devInfo",
                              ".D-stc:$stc");
  delete $hash->{helper}{rxType};
  CUL_HM_getRxType($hash); #will update rxType
  $mId = CUL_HM_getMId($hash);# set helper valiable and use result

  # autocreate undefined channels
  my @chanTypesList = split(',',$culHmModel->{$mId}{chn});
  foreach my $chantype (@chanTypesList){
    my ($chnTpName,$chnStart,$chnEnd) = split(':',$chantype);
    my $chnNoTyp = 1;
    for (my $chnNoAbs = $chnStart; $chnNoAbs <= $chnEnd;$chnNoAbs++){
      my $chnId = $hash->{DEF}.sprintf("%02X",$chnNoAbs);
      if (!$modules{CUL_HM}{defptr}{$chnId}){
        my $chnName = $name."_".$chnTpName.(($chnStart == $chnEnd)?
                                '':'_'.sprintf("%02d",$chnNoTyp));
                                
        CommandDefine(undef,$chnName.' CUL_HM '.$chnId);
        $attr{CUL_HM_id2Name($chnId)}{model} = $md;
      }
      $attr{CUL_HM_id2Name($chnId)}{model} = $md;
      $chnNoTyp++;
    }
  }
  if ($culHmModel->{$mId}{cyc}){
    CUL_HM_ActAdd($hash->{DEF},AttrVal($name,"actCycle",
                                             $culHmModel->{$mId}{cyc}));
  }
}
sub CUL_HM_getConfig($){
  my $hash = shift;
  my $flag = CUL_HM_getFlag($hash);
  my $id = CUL_HM_IoId($hash);
  my $dst = substr($hash->{DEF},0,6);
  my $name = $hash->{NAME};
  CUL_HM_configUpdate($name);
  delete $modules{CUL_HM}{helper}{cfgCmpl}{$name};
  CUL_HM_complConfigTest($name);
  CUL_HM_PushCmdStack($hash,'++'.$flag.'01'.$id.$dst.'00040000000000')
           if ($hash->{helper}{role}{dev});
  my @chnIdList = CUL_HM_getAssChnIds($name);
  foreach my $channel (@chnIdList){
    my $cHash = CUL_HM_id2Hash($channel);
    my $chn = substr($channel,6,2);
    delete $cHash->{READINGS}{$_}
          foreach (grep /^[\.]?(RegL_)/,keys %{$cHash->{READINGS}});
    my $lstAr = $culHmModel->{CUL_HM_getMId($cHash)}{lst};
    if($lstAr){ 
      my $pReq = 0; # Peer request not issued, do only once for channel
      $cHash->{helper}{getCfgListNo}= "";
      foreach my $listEntry (split(",",$lstAr)){#lists define for this channel
                                                # e.g."1, 5:2.3p ,6:2"
        my ($peerReq,$chnValid)= (0,0);
        my ($listNo,$chnLst1) = split(":",$listEntry);
        if (!$chnLst1){
          $chnValid = 1; #if no entry go for all channels
          $peerReq = 1 if($listNo eq 'p' || $listNo==3 ||$listNo==4); #default
        }
        else{
          my @chnLst = split('\.',$chnLst1);
          foreach my $lchn (@chnLst){
            no warnings;#know that lchan may be followed by 'p' causing a warning
            $chnValid = 1 if (int($lchn) == hex($chn));
            use warnings;
            $peerReq = 1 if ($chnValid && $lchn =~ m/p/);
            last if ($chnValid);
          }
        }
        if ($chnValid){# yes, we will go for a list
          if ($peerReq){# need to get the peers first
            if($listNo ne 'p'){# not if 'only peers'!
              $cHash->{helper}{getCfgList} = "all";
              $cHash->{helper}{getCfgListNo} .= ",".$listNo;
            }
            if (!$pReq){#get peers first, but only once per channel
              CUL_HM_PushCmdStack($cHash,sprintf("++%s01%s%s%s03"
                                         ,$flag,$id,$dst,$chn));
              $pReq = 1;
            }
          }
          else{
            my $ln = sprintf("%02X",$listNo);
            my $mch = CUL_HM_lstCh($cHash,$ln,$chn);
            CUL_HM_PushCmdStack($cHash,"++$flag"."01$id$dst$mch"."0400000000$ln");
          }
        }
      }
    }
  }
}

sub CUL_HM_calcDisWmSet($){
  my $dh = shift; 
  my ($txt,$col,$icon) = eval $dh->{exe};
  if ($txt eq "off")    { delete $dh->{txt};}
  elsif($txt ne "nc")   { $dh->{txt} = substr($txt,0,12);}

  if($col eq "off")              { delete $dh->{col};}
  elsif($col ne "nc"){
    if (!defined $disColor{$col}){ delete $dh->{col};}
    else                         { $dh->{col}=$col; }
  }

  if($icon eq "noIcon"){           delete $dh->{icn};}
  elsif($icon ne "nc"){ 
    if (!defined $disIcon {$icon}){delete $dh->{icn}}
    else                          {$dh->{icn}=$icon;}
  }
}
sub CUL_HM_calcDisWm($$$){
  my ($hash,$devName,$t)= @_; # t = s or l
  my $msg;
  my $ts = $t eq "s"?"short":"long";
  foreach my $l (sort keys %{$hash->{helper}{dispi}{$t}}){
    my $dh = $hash->{helper}{dispi}{$t}{"$l"};
    CUL_HM_calcDisWmSet($dh) if ($dh->{d} == 2);

    my ($ch,$ln);
    if($dh->{txt}){
      (undef,$ch,undef,$ln) = unpack('A3A2A1A1',$dh->{txt});
      $ch = sprintf("%02X",$ch) if ($ch =~ m/^\d+\d+$/);
      my $rd =  ($dh->{txt}?"$dh->{txt} ":"- ")
               .($dh->{col}?"$dh->{col} ":"- ") 
               .($dh->{icn}?"$dh->{icn} ":"- ")
               ;
      $rd .= "->". ReadingsVal(InternalVal($devName,"channel_$ch","no")
                                         ,"text$ln","unkown")
                      if (defined $disBtn{$dh->{txt}  });
      readingsSingleUpdate($hash,"disp_${ts}_$l"
                         ,$rd
                         ,0);
      if (defined $disBtn{$dh->{txt}  }){
        $msg .= sprintf("12%02X",$disBtn{$dh->{txt}  }+0x80);
      } 
      else{
        $msg .= "12";
        $msg .= uc( unpack("H*",$dh->{txt})) if ($dh->{txt});
      }
    }

    $msg .= sprintf("11%02X",$disColor{$dh->{col}}+0x80)if ($dh->{col});
    $msg .= sprintf("13%02X",$disIcon{$dh->{icn} }+0x80)if ($dh->{icn});
    $msg .= "0A";# end of line indicator
  }
  my $msgh = "800102";
  $msg .= "03";
  my @txtMsg2;
  foreach (unpack('(A28)*',$msg)){ 
    push @txtMsg2,$msgh.$_;
    $msgh = "8001";
  }
  $hash->{helper}{disp}{$t} = \@txtMsg2;
}

sub CUL_HM_RemoveHMPair($) {####################################################
  my($in ) = shift;
  my(undef,$name) = split(':',$in);
  RemoveInternalTimer("hmPairForSec:$name");
  return if (!$name || !defined $defs{$name});
  delete($defs{$name}{hmPair});
  delete($defs{$name}{hmPairSerial});
}

#+++++++++++++++++ Protocol stack, sending, repeat+++++++++++++++++++++++++++++
sub CUL_HM_pushConfig($$$$$$$$@) {#generate messages to config data to register
  my ($hash,$src,$dst,$chn,$peerAddr,$peerChn,$list,$content,$prep) = @_;
  my $flag = CUL_HM_getFlag($hash);
  my $tl = length($content);
  $chn     = sprintf("%02X",$chn);
  $peerChn = sprintf("%02X",$peerChn);
  $list    = sprintf("%02X",$list);
  $prep    = "" if (!defined $prep);
  # --store pending changes in shadow to handle bit manipulations cululativ--
  $peerAddr = "000000" if(!$peerAddr);
  my $peerN = ($peerAddr ne "000000")?CUL_HM_peerChName($peerAddr.$peerChn,$dst):"";
  $peerN =~ s/broadcast//;
  $peerN =~ s/ /_/g;#remote blanks
  my $regLNp = "RegL_".$list.":".$peerN;
  my $regPre = ((CUL_HM_getAttrInt($hash->{NAME},"expert") == 2)?"":".");
  my $regLN = $regPre.$regLNp;
  #--- copy data from readings to shadow
  my $chnhash = $modules{CUL_HM}{defptr}{$dst.$chn};
  $chnhash = $hash if (!$chnhash);
  my $sdH = CUL_HM_shH($chnhash,$list,$dst);
  my $rRd = ReadingsVal($chnhash->{NAME},$regLN,"");
  if (!$sdH->{helper}{shadowReg} ||
      !$sdH->{helper}{shadowReg}{$regLNp}){
    $sdH->{helper}{shadowReg}{$regLNp} = $rRd;
  }
  #--- update with ne value
  my $regs = $sdH->{helper}{shadowReg}{$regLNp};
  for(my $l = 0; $l < $tl; $l+=4) { #substitute changed bytes in shadow
    my $addr = substr($content,$l,2);
    my $data = substr($content,$l+2,2);
    if(!$regs || !($regs =~ s/$addr:../$addr:$data/)){
      $regs .= " ".$addr.":".$data;
    }
  }
  $sdH->{helper}{shadowReg}{$regLNp} = $regs; # update shadow
  my @changeList;
  if ($prep eq "exec"){#update complete registerset
    @changeList = keys%{$sdH->{helper}{shadowReg}};
  }
  elsif ($prep eq "prep"){
    return; #prepare shadowReg only. More data expected.
  }
  else{
    push @changeList,$regLNp;
  }
  my $changed = 0;# did we write
  foreach my $nrn(@changeList){
    my $change;
    my $nrRd = ReadingsVal($chnhash->{NAME},$regPre.$nrn,"");
    foreach (sort split " ",$sdH->{helper}{shadowReg}{$nrn}){
      $change .= $_." " if ($nrRd !~ m /$_/);# filter only changes
    }
    next if (!$change);#no changes
    $change =~ s/00:00//;
    $change =~ s/(\ |:)//g;
    my $peerN;
    $changed = 1;# yes, we did
    ($list,$peerN) = ($1,$2) if($nrn =~ m/RegL_(..):(.*)/);
    if ($peerN){($peerAddr,$peerChn) = unpack('A6A2', CUL_HM_name2Id($peerN,$hash));}
    else       {($peerAddr,$peerChn) = ('000000','00');}
    CUL_HM_updtRegDisp($hash,$list,$peerAddr.$peerChn);
    ############partition
#   my @chSplit = unpack('(A28)*',$change);
    my @chSplit = unpack('(A1120)*',$change);# makes max 40 lines, 280 byte
    foreach my $chSpl(@chSplit){
      my $mch = CUL_HM_lstCh($chnhash,$list,$chn);
      CUL_HM_PushCmdStack($hash, "++".$flag.'01'.$src.$dst.$mch.'05'.
                                          $peerAddr.$peerChn.$list);
      $tl = length($chSpl);
      for(my $l = 0; $l < $tl; $l+=28) {
        my $ml = $tl-$l < 28 ? $tl-$l : 28;
        CUL_HM_PushCmdStack($hash, "++A001".$src.$dst.$chn."08".
                                       substr($chSpl,$l,$ml));
      }
      CUL_HM_PushCmdStack($hash,"++A001".$src.$dst.$mch."06");
    }
    #########
  }
  CUL_HM_qAutoRead($hash->{NAME},3) if ($changed);
}
sub CUL_HM_PushCmdStack($$) {
  my ($chnhash, $cmd) = @_;
  my @arr = ();
  my $hash = CUL_HM_getDeviceHash($chnhash);
  my $name = $hash->{NAME};
  if(!$hash->{cmdStack}){# this is a new 'burst' of messages
    $hash->{cmdStack} = \@arr;
    $hash->{helper}{prt}{bErr}=0 if ($hash->{helper}{prt}{sProc} != 1);# not processing
  }
  push(@{$hash->{cmdStack}}, $cmd);
  my $entries = scalar @{$hash->{cmdStack}};
  $hash->{protCmdPend} = $entries." CMDs_pending";
  CUL_HM_protState($hash,"CMDs_pending") if($hash->{helper}{prt}{sProc} != 1);# not processing
}
sub CUL_HM_ProcessCmdStack($) {
  my ($chnhash) = @_;
  my $hash = CUL_HM_getDeviceHash($chnhash);

  if (!$hash->{helper}{prt}{rspWait}{cmd}){
    if($hash->{cmdStack} && @{$hash->{cmdStack}}){
     CUL_HM_SndCmd($hash, shift @{$hash->{cmdStack}});
    }
    elsif($hash->{helper}{prt}{sProc} != 0){
      CUL_HM_protState($hash,"CMDs_done");                                    
    }
  }
  return;
}

sub CUL_HM_respWaitSu($@){ #setup response for multi-message response
  # single commands
  # cmd: single msg that needs to be ACKed
  # mNo: number of message (needs to be in ACK)
  # mNoWu: number of message if wakeup
  # reSent: number of resends already done - usually init with 1
  # wakeup: was wakeup message (burst devices)
  #
  # commands with multi-message answer
  # PendCmd: command message
  # Pending: type of answer we are awaiting
  # forChn:  which channel are we working on?
  # forList: which list are we waiting for? (optional)
  # forPeer: which peer are we waiting for? (optional)
  my ($hash,@a)=@_;
  my $mHsh = $hash->{helper}{prt};
  $modules{CUL_HM}{prot}{rspPend}++ if(!$mHsh->{rspWait}{cmd});
  foreach (@a){
    next if (!$_);
    my ($f,$d)=split ":=",$_;
    $mHsh->{rspWait}{$f}=$d;
  }
  my $to = gettimeofday() + (($mHsh->{rspWait}{Pending})?rand(20)/10+4:
                                                         rand(40)/10+1);
  InternalTimer($to,"CUL_HM_respPendTout","respPend:$hash->{DEF}", 0);
 }
sub CUL_HM_responseSetup($$) {#store all we need to handle the response
 #setup repeatTimer and cmdStackControll
  my ($hash,$cmd) =  @_;
  return if($hash->{helper}{prt}{sProc} == 3);#not relevant while FW update
  my (undef,$mNo,$mFlg,$mTp,$src,$dst,$chn,$sTp,$dat) = 
        unpack 'A4A2A2A2A6A6A2A2A*',$cmd;
  $mFlg = hex($mFlg);

  if (($mFlg & 0x20) && ($dst ne '000000')){#msg wants ack
    my $rss = $hash->{helper}{prt}{wuReSent}
                       ? $hash->{helper}{prt}{wuReSent}
                       :1;#resend count - may need preloaded for WU device

    if   ($mTp eq "01" && $sTp){
      if   ($sTp eq "03"){ #PeerList-----------
        #--- remember request params in device level
        CUL_HM_respWaitSu ($hash,"Pending:=PeerList"
                                ,"cmd:=$cmd" ,"forChn:=$chn"
                                ,"mNo:=".hex($mNo)
                                ,"reSent:=$rss");

        #--- remove readings in channel
        my $chnhash = $modules{CUL_HM}{defptr}{"$dst$chn"};
        $chnhash = $hash if (!$chnhash);
        delete $chnhash->{READINGS}{peerList};#empty old list
        delete $chnhash->{peerList};#empty old list
        delete $chnhash->{helper}{peerIDsRaw};
        $attr{$chnhash->{NAME}}{peerIDs} = '';
      }
      elsif($sTp eq "04"){ #RegisterRead-------
        my ($peer, $list) = unpack 'A8A2',$dat;
        $peer = ($peer ne "00000000")?CUL_HM_peerChName($peer,$dst):"";
        #--- set messaging items
        my $chnhash = $modules{CUL_HM}{defptr}{"$dst$chn"};
        $chnhash = $hash if(!$chnhash);
        my $fch = CUL_HM_shC($chnhash,$list,$chn);
        CUL_HM_respWaitSu ($hash,"Pending:=RegisterRead"
                                ,"cmd:=$cmd" ,"forChn:=$fch"
                                ,"forList:=$list","forPeer:=$peer"
                                ,"mNo:=".hex($mNo)
                                ,"nAddr:=0"
                                ,"reSent:=$rss");
        #--- remove channel entries that will be replaced

        $peer ="" if($list !~ m/^0[347]$/);
        #empty val since reading will be cumulative
        my $rlName = ((CUL_HM_getAttrInt($chnhash->{NAME},"expert") == 2)?
                                         "":".")."RegL_".$list.":".$peer;
        $chnhash->{READINGS}{$rlName}{VAL}="";
        my $chnHash = $modules{CUL_HM}{defptr}{$dst.$chn};
        delete ($chnhash->{READINGS}{$rlName}{TIME});
      }
      elsif($sTp eq "09"){ #SerialRead-------
        CUL_HM_respWaitSu ($hash,"Pending:=SerialRead"
                                ,"cmd:=$cmd" ,"reSent:=$rss");
      }
      else{
        CUL_HM_respWaitSu ($hash,"cmd:=$cmd","mNo:=$mNo","reSent:=$rss");
      }
      $hash->{helper}{cSnd} =~ s/.*,// if($hash->{helper}{cSnd});
      $hash->{helper}{cSnd} .= ",".substr($cmd,8);
    }
    elsif($mTp eq '11'){
      my $to = "";
      if ($chn eq "02"){#!!! chn is subtype!!!
        if ($dat =~ m/(..)....(....)/){#lvl ne 0 and timer on
          # store Channel in this datafield. 
          # dimmer may answer with wrong virtual channel - then dont resent!
          $hash->{helper}{tmdOn} = $sTp if ($1 ne "00" && $2 !~ m/(0000|FFFF)/);
          $to = "timedOn:=1";
        }
      }
      CUL_HM_respWaitSu ($hash,"cmd:=$cmd","mNo:=$mNo","reSent:=$rss",$to);
      $hash->{helper}{cSnd} =~ s/.*,// if($hash->{helper}{cSnd});
      $hash->{helper}{cSnd} .= ",".substr($cmd,8);
    }
    elsif($mTp eq '12' && $mFlg & 0x10){#wakeup with burst
      # response setup - do not repeat, set counter to 250
      CUL_HM_respWaitSu ($hash,"cmd:=$cmd","mNo:=$mNo","reSent:=$rss","brstWu:=1");
    }
    elsif($mTp !~ m /C./){
      CUL_HM_respWaitSu ($hash,"cmd:=$cmd","mNo:=$mNo","reSent:=$rss");
    }

    CUL_HM_protState($hash,"CMDs_processing...");
  }
  else{# no answer expected
    if($hash->{cmdStack} && scalar @{$hash->{cmdStack}}){
      if (!$hash->{helper}{prt}{sleeping}){
        CUL_HM_protState($hash,"CMDs_processing...");
        InternalTimer(gettimeofday()+.1, "CUL_HM_ProcessCmdStack", $hash, 0);
      }
      else{
        delete $hash->{helper}{prt}{sleeping};
      }
    }
    elsif(!$hash->{helper}{prt}{rspWait}{cmd}){
      CUL_HM_protState($hash,"CMDs_done");
    }
  }

  my $mmcS = $hash->{helper}{prt}{mmcS}?$hash->{helper}{prt}{mmcS}:0;
  if ($mTp eq '01'){
    my $oCmd = "++".substr($cmd,6);
    if    ($sTp eq "05"){
      my @arr = ($oCmd);
      $hash->{helper}{prt}{mmcA}=\@arr;
      $hash->{helper}{prt}{mmcS} = 1;
    }
    elsif ($sTp =~ m/(07|08)/ && ($mmcS == 1||$mmcS == 2)){
      push @{$hash->{helper}{prt}{mmcA}},$oCmd;
      $hash->{helper}{prt}{mmcS} = 2;
    }
    elsif ($sTp eq "06" && ($mmcS == 2)){
      push @{$hash->{helper}{prt}{mmcA}},$oCmd;
      $hash->{helper}{prt}{mmcS} = 3;
    }
    elsif ($mmcS){ #
      delete $hash->{helper}{prt}{mmcA};
      delete $hash->{helper}{prt}{mmcS};
    }
  }
  elsif($mmcS){
    delete $hash->{helper}{prt}{mmcA};
    delete $hash->{helper}{prt}{mmcS};
  }

  if($hash->{cmdStack} && scalar @{$hash->{cmdStack}}){
    $hash->{protCmdPend} = scalar @{$hash->{cmdStack}}." CMDs pending";
  }
  else{
    delete($hash->{protCmdPend});
  }
}

sub CUL_HM_sndIfOpen($) {
  my(undef,$io) = split(':',$_[0]);
  RemoveInternalTimer("sndIfOpen:$io");# should not be necessary, but
  my $ioHash = $defs{$io};
  if (   $ioHash->{STATE} !~ m/^(opened|Initialized)$/
      ||(defined $ioHash->{XmitOpen} && $ioHash->{XmitOpen} != 1)
#     ||$modules{CUL_HM}{prot}{rspPend}>=$maxPendCmds
       ){#still no send allowed
    if ( $modules{CUL_HM}{$io}{tmrStart} &&
        ($modules{CUL_HM}{$io}{tmrStart} < gettimeofday() - $modules{CUL_HM}{hmIoMaxDly})){
      # we need to clean up - this is way to long Stop delay
      if ($modules{CUL_HM}{$io}{pendDev}) {
        while(@{$modules{CUL_HM}{$io}{pendDev}}){
          my $name = shift(@{$modules{CUL_HM}{$io}{pendDev}});
          CUL_HM_eventP($defs{$name},"IOerr");
        }
      }
      $modules{CUL_HM}{$io}{tmr} = 0;
    }
    else{
      if ($modules{CUL_HM}{$io}{pendDev} && @{$modules{CUL_HM}{$io}{pendDev}}){
        InternalTimer(gettimeofday()+$IOpoll,"CUL_HM_sndIfOpen",
                                    "sndIfOpen:$io", 0);
      }
    }
  }
  else{
    $modules{CUL_HM}{$io}{tmr} = 0;
    if ($modules{CUL_HM}{$io}{pendDev} && @{$modules{CUL_HM}{$io}{pendDev}}){
      my $name = shift(@{$modules{CUL_HM}{$io}{pendDev}});
      CUL_HM_ProcessCmdStack($defs{$name});
      if (@{$modules{CUL_HM}{$io}{pendDev}}){#tmr = 0, clearing queue slowly
        InternalTimer(gettimeofday()+$IOpoll,"CUL_HM_sndIfOpen",
                                      "sndIfOpen:$io", 0);
      }
    }
  }
}
sub CUL_HM_SndCmd($$) {
  my ($hash, $cmd) = @_;
  $hash = CUL_HM_getDeviceHash($hash);
  if(   AttrVal($hash->{NAME},"ignore",0) != 0
     || AttrVal($hash->{NAME},"dummy" ,0) != 0){
    CUL_HM_eventP($hash,"dummy");
    return;
  }
  CUL_HM_assignIO($hash) ;
  if(!defined $hash->{IODev} ||!defined $hash->{IODev}{NAME}){
    CUL_HM_eventP($hash,"IOerr");
    CUL_HM_UpdtReadSingle($hash,"state","ERR_IOdev_undefined",1);
    return;
  }
  
  my $io = $hash->{IODev};
  my $ioName = $io->{NAME};
  
  if (  $io->{STATE} !~ m/^(opened|Initialized)$/          # we need to queue
      ||(hex substr($cmd,2,2) & 0x20) && (                 # check for commands with resp-req
           $modules{CUL_HM}{$ioName}{tmr}                  # queue already running
         ||(defined $io->{XmitOpen} && $io->{XmitOpen} != 1)#overload, dont send
        )
      ){

    # shall we delay commands if IO device is not present?
    # it could cause trouble if light switches on after a long period
    # repetition will be stopped after 1min forsecurity reason.
    my @arr = ();
    $hash->{cmdStack} = \@arr if(!$hash->{cmdStack});
    unshift (@{$hash->{cmdStack}}, $cmd);#pushback cmd, wait for opportunity

    # push device to list
    if (!defined $modules{CUL_HM}{$ioName}{tmr}){
      # some setup work for this timer
      $modules{CUL_HM}{$ioName}{tmr} = 0;
      if (!$modules{CUL_HM}{$ioName}{pendDev}){# generate if not exist
        my @arr2 = ();
        $modules{CUL_HM}{$ioName}{pendDev} = \@arr2;
      }
    }
    @{$modules{CUL_HM}{$ioName}{pendDev}} =
          CUL_HM_noDup(@{$modules{CUL_HM}{$ioName}{pendDev}},$hash->{NAME});
    CUL_HM_respPendRm($hash);#rm timer - we are out
    if ($modules{CUL_HM}{$ioName}{tmr} != 1){# need to start timer
      my $tn = gettimeofday();
         InternalTimer($tn+$IOpoll, "CUL_HM_sndIfOpen", "sndIfOpen:$ioName", 0);
      $modules{CUL_HM}{$ioName}{tmr} = 1;
      $modules{CUL_HM}{$ioName}{tmrStart} = $tn; # abort if to long
    }
    return;
  }

  $cmd =~ m/^(..)(.*)$/;
  my ($mn, $cmd2) =  unpack 'A2A*',$cmd;

  if($mn eq "++") {
    $mn = $hash->{helper}{HM_CMDNR} ? (($hash->{helper}{HM_CMDNR} +1)&0xff) : 1;
    $hash->{helper}{HM_CMDNR} = $mn;
  }
  elsif($cmd =~ m/^[+-]/){; #continue pure
    IOWrite($hash, "", $cmd);
    return;
  }
  else {
    $mn = hex($mn);
  }
  $cmd = sprintf("As%02X%02X%s", length($cmd2)/2+1, $mn, $cmd2);
  IOWrite($hash, "", $cmd);
  CUL_HM_statCnt($ioName,"s");
  CUL_HM_eventP($hash,"Snd");
  CUL_HM_responseSetup($hash,$cmd);
  $cmd =~ m/As(..)(..)(..)(..)(......)(......)(.*)/;
  CUL_HM_DumpProtocol("SND", $io, ($1,$2,$3,$4,$5,$6,$7));
}
sub CUL_HM_statCnt($$) {# set msg statistics for (r)ecive (s)end or (u)pdate
  my ($ioName,$dir) = @_;
  my $stat   = $modules{CUL_HM}{stat};
  if (!$stat->{$ioName}){
    $stat->{r}{$ioName}{h}{$_} = 0 foreach(0..23);
    $stat->{r}{$ioName}{d}{$_} = 0 foreach(0..6);
    $stat->{s}{$ioName}{h}{$_} = 0 foreach(0..23);
    $stat->{s}{$ioName}{d}{$_} = 0 foreach(0..6);
    $stat->{$ioName}{last} = 0;
  }
  my @l = localtime(gettimeofday());

  if ($l[2] != $stat->{$ioName}{last}){#next field
    my $end = $l[2];
    if ($l[2] < $stat->{$ioName}{last}){#next day
      $end += 24;
      my $recentD = ($l[6]+6)%7;
      foreach my $ud ("r","s"){
        $stat->{$ud}{$ioName}{d}{$recentD} = 0;
        $stat->{$ud}{$ioName}{d}{$recentD} += $stat->{$ud}{$ioName}{h}{$_}
                    foreach (0..23);
      }
     }
    foreach (($stat->{$ioName}{last}+1)..$end){
      $stat->{r}{$ioName}{h}{$_%24} = 0;
      $stat->{s}{$ioName}{h}{$_%24} = 0;
    }
    $stat->{$ioName}{last} = $l[2];
  }
  $stat->{$dir}{$ioName}{h}{$l[2]}++ if ($dir ne "u");
}
sub CUL_HM_statCntRfresh($) {# update statistic once a day
  my ($ioName,$dir) = @_;
  foreach (keys %{$modules{CUL_HM}{stat}{r}}){
    if (!$defs{$ioName}){#IO device is deleted, clear counts
      delete $modules{CUL_HM}{stat}{$ioName};
      delete $modules{CUL_HM}{stat}{r}{$ioName}{h};
      delete $modules{CUL_HM}{stat}{r}{$ioName}{d};
      delete $modules{CUL_HM}{stat}{s}{$ioName}{h};
      delete $modules{CUL_HM}{stat}{s}{$ioName}{d};
      next;
    }
    CUL_HM_statCnt($_,"u") if ($_ ne "dummy");
  }
  RemoveInternalTimer("StatCntRfresh");
  InternalTimer(gettimeofday()+3600*20,"CUL_HM_statCntRfresh","StatCntRfresh",0);
}

sub CUL_HM_respPendRm($) {#del response related entries in messageing entity
  my ($hash) =  @_;
  $modules{CUL_HM}{prot}{rspPend}-- if($hash->{helper}{prt}{rspWait}{cmd});
  delete $hash->{helper}{prt}{rspWait};
  delete $hash->{helper}{prt}{wuReSent};
  delete $hash->{helper}{tmdOn};
#  delete $hash->{helper}{prt}{mmcA};
#  delete $hash->{helper}{prt}{mmcS};
  RemoveInternalTimer($hash);                  # remove resend-timer
  RemoveInternalTimer("respPend:$hash->{DEF}");# remove responsePending timer
  $respRemoved = 1;
}
sub CUL_HM_respPendTout($) {
  my ($HMid) =  @_;
  (undef,$HMid) = split(":",$HMid,2);
  my $hash = $modules{CUL_HM}{defptr}{$HMid};
  my $pHash = $hash->{helper}{prt};#shortcut
  if ($hash && $hash->{DEF} ne '000000'){# we know the device
    my $name = $hash->{NAME};
    $pHash->{awake} = 0 if (defined $pHash->{awake});# set to asleep
    return if(!$pHash->{rspWait}{reSent});      # Double timer?
    my $rxt = CUL_HM_getRxType($hash);
    if ($pHash->{rspWait}{brstWu}){#burst-wakeup try failed (conditionalBurst)
      CUL_HM_respPendRm($hash);# don't count problems, was just a try
      $hash->{protCondBurst} = "off" if (!$hash->{protCondBurst}||
                                          $hash->{protCondBurst} !~ m/forced/);;
      $pHash->{brstWu} = 0;# finished
      $pHash->{awake} = 0;# set to asleep
      CUL_HM_protState($hash,"CMDs_pending");
      # commandstack will be executed when device wakes up itself
    }
    elsif ($pHash->{try}){         #send try failed - revert, wait for wakeup
      # device might still be busy with writing flash or similar
      # we have to wait for next wakeup
      unshift (@{$hash->{cmdStack}}, "++".substr($pHash->{rspWait}{cmd},6));
      delete $pHash->{try};
      CUL_HM_respPendRm($hash);# do not count problems with wakeup try, just wait
      CUL_HM_protState($hash,"CMDs_pending");
    }
    elsif ($hash->{IODev}->{STATE} !~ m/^(opened|Initialized)$/){#IO errors
      CUL_HM_eventP($hash,"IOdly");
      CUL_HM_ProcessCmdStack($hash) if($rxt & 0x03);#burst/all
    }
    elsif ($pHash->{rspWait}{reSent} > AttrVal($name,"msgRepeat",($rxt & 0x9B)?3:0)#too many
           ){#config cannot retry
      my $pendCmd = "MISSING ACK";

      if ($pHash->{rspWait}{Pending}){
        $pendCmd = "RESPONSE TIMEOUT:".$pHash->{rspWait}{Pending};
        CUL_HM_complConfig($name,1);# check with delay
      }
      CUL_HM_eventP($hash,"ResndFail");
      CUL_HM_UpdtReadSingle($hash,"state",$pendCmd,1);
    }
    else{# manage retries
      $pHash->{rspWait}{reSent}++;
      CUL_HM_eventP($hash,"Resnd");
      Log3 $name,4,"CUL_HM_Resend: $name nr ".$pHash->{rspWait}{reSent};
      if ($hash->{protCondBurst}&&$hash->{protCondBurst} eq "on" ){
        #timeout while conditional burst was active. try re-wakeup
        my $addr = CUL_HM_IoId($hash);
        $pHash->{rspWaitSec}{$_} = $pHash->{rspWait}{$_}
                    foreach (keys%{$pHash->{rspWait}});
        CUL_HM_SndCmd($hash,"++B112$addr$HMid");
        $hash->{helper}{prt}{awake}=4;# start re-wakeup
      }
      elsif($rxt & 0x18){# wakeup/lazy devices
        #need to fill back command to queue and wait for next wakeup
        if ($pHash->{mmcA}){#fillback multi-message command
          unshift @{$hash->{cmdStack}},$_ foreach (reverse@{$pHash->{mmcA}});
          delete $pHash->{mmcA};
          delete $pHash->{mmcS};
        }
        else{#fillback simple command
          unshift (@{$hash->{cmdStack}},"++".substr($pHash->{rspWait}{cmd},6))
                if (substr($pHash->{rspWait}{cmd},8,2) ne '12');# not wakeup
        }
        my $wuReSent = $pHash->{rspWait}{reSent};# save 'invalid' count
        CUL_HM_respPendRm($hash);#clear
        CUL_HM_protState($hash,"CMDs_pending");
        $pHash->{wuReSent} = $wuReSent;# save 'invalid' count
      }
      else{# normal device resend
        if ($rxt & 0x02){# type = burst - need to set burst-Bit for retry
          if ($pHash->{mmcA}){#fillback multi-message command
            unshift @{$hash->{cmdStack}},$_ foreach (reverse@{$pHash->{mmcA}});
            delete $pHash->{mmcA};
            delete $pHash->{mmcS};
            
            my $cmd = shift @{$hash->{cmdStack}};
            $cmd = sprintf("As%02X01%s", length($cmd)/2, substr($cmd,2));
            $pHash->{rspWait}{cmd} = $cmd;
            CUL_HM_responseSetup($hash,$cmd);
          }

          my ($pre,$tp,$tail) = unpack 'A6A2A*',$pHash->{rspWait}{cmd};
          $pHash->{rspWait}{cmd} = sprintf("%s%02X%s",$pre,(hex($tp)|0x10),$tail);
        }
        IOWrite($hash, "", $pHash->{rspWait}{cmd});
        CUL_HM_statCnt($hash->{IODev}{NAME},"s");
        InternalTimer(gettimeofday()+rand(20)/10+4,"CUL_HM_respPendTout","respPend:$hash->{DEF}", 0);
      }
    }
  }
}
sub CUL_HM_respPendToutProlong($) {#used when device sends part responses
  my ($hash) =  @_;
  RemoveInternalTimer("respPend:$hash->{DEF}");
  InternalTimer(gettimeofday()+2, "CUL_HM_respPendTout", "respPend:$hash->{DEF}", 0);
}

sub CUL_HM_FWupdateSteps($){#steps for FW update
  my $mIn = shift;
  my $step = $modules{CUL_HM}{helper}{updateStep};
  my $name = $modules{CUL_HM}{helper}{updatingName};
  my $dst  = $modules{CUL_HM}{helper}{updateDst};
  my $id   = $modules{CUL_HM}{helper}{updateId};
  my $mNo  = $modules{CUL_HM}{helper}{updateNbr};
  my $hash = $defs{$name};
  my $mNoA = sprintf("%02X",$mNo);
  
  return "" if ($mIn !~ m/$mNoA..02$dst${id}00/ && $mIn !~ m/..10${dst}00000000/);
  if ($mIn =~ m/$mNoA..02$dst${id}00/){
    $modules{CUL_HM}{helper}{updateRetry} = 0;
    $modules{CUL_HM}{helper}{updateNbrPassed} = $mNo;
  }

  if ($step == 0){#check bootloader entered - now change speed
    return "" if ($mIn =~ m/$mNoA..02$dst${id}00/);
    Log3 $name,2,"CUL_HM fwUpdate $name entered mode. IO-speed: fast";
    $mNo = (++$mNo)%256; $mNoA = sprintf("%02X",$mNo);
    CUL_HM_SndCmd($hash,"${mNoA}00CB$id${dst}105B11F81547");
#    CUL_HM_SndCmd($hash,"${mNoA}20CB$id${dst}105B11F815470B081A1C191D1BC71C001DB221B623EA");
    select(undef, undef, undef, (0.04));
    CUL_HM_FWupdateSpeed($name,100);
    select(undef, undef, undef, (0.04));
    $mNo = (++$mNo)%256; $mNoA = sprintf("%02X",$mNo);
    $modules{CUL_HM}{helper}{updateStep} = $step = 1;
    $modules{CUL_HM}{helper}{updateNbr} = $mNo;
    RemoveInternalTimer("fail:notInBootLoader");
    #InternalTimer(gettimeofday()+0.3,"CUL_HM_FWupdateSim","${dst}${id}00",0);
  }

  ##16.130  CUL_Parse:  A 0A 30 0002 235EDB 255E91 00
  ##16.338  CUL_Parse:  A 0A 39 0002 235EDB 255E91 00
  ##16.716  CUL_Parse:  A 0A 42 0002 235EDB 255E91 00
  ##17.093  CUL_Parse:  A 0A 4B 0002 235EDB 255E91 00
  ##17.471  CUL_Parse:  A 0A 54 0002 235EDB 255E91 00
  ##17.848  CUL_Parse:  A 0A 5D 0002 235EDB 255E91 00
  ##...
  ##43.621 4: CUL_Parse: iocu1 A 0A 58 0002 235EDB 255E91 00
  ##44.034 4: CUL_Parse: iocu1 A 0A 61 0002 235EDB 255E91 00
  ##44.161 4: CUL_Parse: iocu1 A 1D 6A 20CA 255E91 235EDB 00121642446D1C3F45F240ED84DC5E7C1AB7554D
  ##44.180 4: CUL_Parse: iocu1 A 0A 6A 0002 235EDB 255E91 00
  ## one block = 10 messages in 200-1000ms
  my $blocks = scalar(@{$modules{CUL_HM}{helper}{updateData}});
  RemoveInternalTimer("respPend:$hash->{DEF}");
  RemoveInternalTimer("fail:Block".($step-1));
  if ($blocks < $step){#last block
    CUL_HM_FWupdateEnd("done");
    Log3 $name,2,"CUL_HM fwUpdate completed";
    return "done";
  }
  else{# programming continue
    my $bl = ${$modules{CUL_HM}{helper}{updateData}}[$step-1];
    my $no = scalar(@{$bl});
    Log3 $name,5,"CUL_HM fwUpdate write block $step of $blocks: $no messages";
    foreach my $msgP (@{$bl}){
      $mNo = (++$mNo)%256; $mNoA = sprintf("%02X",$mNo);
      CUL_HM_SndCmd($hash, $mNoA.((--$no)?"00":"20")."CA$id$dst".$msgP);
      # select(undef, undef, undef, (0.01));# no wait necessary - FHEM is slow anyway
    }
    $modules{CUL_HM}{helper}{updateStep}++;
    $modules{CUL_HM}{helper}{updateNbr} = $mNo;
    #InternalTimer(gettimeofday()+0.3,"CUL_HM_FWupdateSim","${dst}${id}00",0);
    InternalTimer(gettimeofday()+5,"CUL_HM_FWupdateBTo","fail:Block$step",0);
    return "";
  }
}
sub CUL_HM_FWupdateBTo($){# FW update block timeout
  my $in = shift;
  $modules{CUL_HM}{helper}{updateRetry}++;
  if ($modules{CUL_HM}{helper}{updateRetry} > 3){#retry exceeded
    CUL_HM_FWupdateEnd($in);
  }
  else{# have a retry
    $modules{CUL_HM}{helper}{updateStep}--;
    $modules{CUL_HM}{helper}{updateNbr} = $modules{CUL_HM}{helper}{updateNbrPassed};
    CUL_HM_FWupdateSteps("0010".$modules{CUL_HM}{helper}{updateDst}."00000000");
  }
}
sub CUL_HM_FWupdateEnd($){#end FW update
  my $in = shift;
  my $hash = $defs{$modules{CUL_HM}{helper}{updatingName}};
  CUL_HM_UpdtReadSingle($hash,"fwUpdate",$in,1);
  CUL_HM_FWupdateSpeed($modules{CUL_HM}{helper}{updatingName},10);
  $hash->{helper}{io}{newChn} = $hash->{helper}{io}{newChnFwUpdate}
      if(defined $hash->{helper}{io}{newChnFwUpdate});#restore initMsg
  delete $hash->{helper}{io}{newChnFwUpdate};
  
  delete $defs{$modules{CUL_HM}{helper}{updatingName}}->{cmdStack};
  delete $modules{CUL_HM}{helper}{updating};
  delete $modules{CUL_HM}{helper}{updatingName};
  delete $modules{CUL_HM}{helper}{updateData};
  delete $modules{CUL_HM}{helper}{updateStep};
  delete $modules{CUL_HM}{helper}{updateDst};
  delete $modules{CUL_HM}{helper}{updateId};
  delete $modules{CUL_HM}{helper}{updateNbr};
  CUL_HM_respPendRm($hash);

  CUL_HM_protState($hash,"CMDs_done_FWupdate");
  Log3 $hash->{NAME},2,"CUL_HM fwUpdate $hash->{NAME} end. IO-speed: normal";
}
sub CUL_HM_FWupdateSpeed($$){#set IO speed
  my ($name,$speed) = @_;
  my $hash = $defs{$name};
  if ($hash->{IODev}->{TYPE} ne "CUL"){
    my $msg = sprintf("G%02X",$speed);
    IOWrite($hash, "cmd",$msg);
  }
  else{
    IOWrite($hash, "cmd","speed".$speed);
  }
}
sub CUL_HM_FWupdateSim($){#end FW Simulation
  my $msg = shift;
  my $ioName = $defs{$modules{CUL_HM}{helper}{updatingName}}->{IODev}->{NAME};
  my $mNo = sprintf("%02X",$modules{CUL_HM}{helper}{updateNbr});
  if (0 == $modules{CUL_HM}{helper}{updateStep}){
    CUL_HM_Parse($defs{$ioName},"A00${mNo}0010$msg");
  }
  else{
    Log3 "",5,"FWupdate simulate No:$mNo";
    CUL_HM_Parse($defs{$ioName},"A00${mNo}8002$msg");
  }
}

sub CUL_HM_eventP($$) {#handle protocol events
  # Current Events are Rcv,NACK,IOerr,Resend,ResendFail,Snd
  # additional variables are protCmdDel,protCmdPend,protState,protLastRcv
  my ($hash, $evntType) = @_;
  my $nAttr = $hash;
  if ($evntType eq "Rcv"){
    $nAttr->{"protLastRcv"} = TimeNow();
    CUL_HM_UpdtReadSingle($hash,".protLastRcv",$nAttr->{"protLastRcv"},0);
    return;
  }

  my $evnt = $nAttr->{"prot".$evntType}?$nAttr->{"prot".$evntType}:"0 > x";
  my ($evntCnt,undef) = split(' last_at:',$evnt);
  $nAttr->{"prot".$evntType} = ++$evntCnt." last_at:".TimeNow();

  if ($evntType =~ m/(Nack|ResndFail|IOerr|dummy)/){# unrecoverable Error
    CUL_HM_UpdtReadSingle($hash,"state",$evntType,1);
    $hash->{helper}{prt}{bErr}++;
    $nAttr->{protCmdDel} = 0 if(!$nAttr->{protCmdDel});
    $nAttr->{protCmdDel} += scalar @{$hash->{cmdStack}} + 1
            if ($hash->{cmdStack});
    CUL_HM_protState($hash,"CMDs_done");
    CUL_HM_respPendRm($hash);
  }
  elsif($evntType eq "IOdly"){ # IO problem - will see whether it recovers
    my $pHash = $hash->{helper}{prt};
    if ($pHash->{mmcA}){
      unshift @{$hash->{cmdStack}},$_ foreach (reverse@{$pHash->{mmcA}});
      delete $pHash->{mmcA};
      delete $pHash->{mmcS};
    }
    else{
      unshift (@{$hash->{cmdStack}},"++".substr($pHash->{rspWait}{cmd},6));
#      unshift @{$hash->{cmdStack}}, $pHash->{rspWait}{cmd};#pushback
    }
    CUL_HM_respPendRm($hash);
  }
}
sub CUL_HM_protState($$){
  my ($hash,$state) = @_;
  my $name = $hash->{NAME};

  my $sProcIn = $hash->{helper}{prt}{sProc};
  if ($sProcIn == 3){#FW update processing
    # do not change state - commandstack is bypassed
    return if ( $state !~ m/(Info_Cleared|_FWupdate)/);
  }
  if   ($state =~ m/processing/) {
    $hash->{helper}{prt}{sProc} = 1;
  }
  elsif($state =~ m/^CMDs_done/) {
    $state .= ($hash->{helper}{prt}{bErr}?
                            ("_Errors:".$hash->{helper}{prt}{bErr})
                            :"");
    delete($hash->{cmdStack});
    delete($hash->{protCmdPend});
    $hash->{helper}{prt}{bErr}  = 0;
    $hash->{helper}{prt}{sProc} = 0;
    $hash->{helper}{prt}{awake} = 0 if (defined $hash->{helper}{prt}{awake});
  }
  elsif($state eq "Info_Cleared"){
    $hash->{helper}{prt}{sProc} = 0;
    $hash->{helper}{prt}{awake} = 0 if (defined $hash->{helper}{prt}{awake});
  }
  elsif($state eq "CMDs_pending"){
    $hash->{helper}{prt}{sProc} = 2;
  }
  elsif($state eq "CMDs_FWupdate"){
    $hash->{helper}{prt}{sProc} = 3;
  }
  $hash->{protState} = $state;
  if (!$hash->{helper}{role}{chn}){
    CUL_HM_UpdtReadSingle($hash,"state",$state,
                          ($hash->{helper}{prt}{sProc} == 1)?0:1);
  }
  Log3 $name,5,"CUL_HM $name protEvent:$state".
            ($hash->{cmdStack}?" pending:".scalar @{$hash->{cmdStack}}:"");
  CUL_HM_hmInitMsgUpdt($hash) if (  $hash->{helper}{prt}{sProc} != $sProcIn
                                  && (   $hash->{helper}{prt}{sProc} < 2
                                      ||($hash->{helper}{prt}{sProc} == 2 && $sProcIn == 0 )));
}

###################-----------helper and shortcuts--------#####################
################### Peer Handling ################
sub CUL_HM_ID2PeerList ($$$) {
  my($name,$peerID,$set) = @_;
  my $peerIDs = AttrVal($name,"peerIDs","");
  return if (!$peerID && !$peerIDs);
  my $hash = $defs{$name};
  $peerIDs =~ s/$peerID//g;         #avoid duplicate, support unset
  $peerID =~ s/^000000../00000000/;  #correct end detector
  $peerIDs.= $peerID."," if($set);
  my %tmpHash = map { $_ => 1 } split(",",$peerIDs);#remove duplicates
  $peerIDs = "";                                    #clear list
  my $peerNames = "";                               #prepare names
  my $dId = substr(CUL_HM_name2Id($name),0,6);      #get own device ID
  foreach my $pId (sort(keys %tmpHash)){
    next if ($pId !~ m/^[0-9A-F]{8}$/);             #ignore non-channel IDs
    $peerIDs .= $pId.",";                           #append ID
    next if ($pId eq "00000000");                   # and end detection
    $peerNames .= CUL_HM_peerChName($pId,$dId).",";
  }
  $attr{$name}{peerIDs} = $peerIDs;                 # make it public

  my $dHash = CUL_HM_getDeviceHash($hash);
  my $st = AttrVal($dHash->{NAME},"subType","");
  my $md = AttrVal($dHash->{NAME},"model","");
  my $chn = InternalVal($name,"chanNo","");
  if ($peerNames){
    $peerNames =~ s/_chn:01//g; # channel 01 is part of device
    CUL_HM_UpdtReadSingle($hash,"peerList",$peerNames,0);
    $hash->{peerList} = $peerNames;
    if ($st eq "virtual"){
      #if any of the peers is an SD we are team master
      my ($tMstr,$tcSim,$thSim) = (0,0,0);
      foreach (split(",",$peerNames)){
        $tMstr = 1 if(AttrVal($_,"subType","") eq "smokeDetector");
        $tcSim = 1 if(AttrVal($_,"model","")   =~ m /(HM-CC-VD|ROTO_ZEL-STG-RM-FSA)/);
        my $pch = (substr(CUL_HM_name2Id($_),6,2));
        $thSim = 1 if(AttrVal($_,"model","")   =~ m /HM-CC-RT-DN/ && $pch eq "01");
      }
      if   ($tMstr){
        $hash->{helper}{fkt}="sdLead";
        $hash->{sdTeam}="sdLead";
        CUL_HM_updtSDTeam($name);
      }
      elsif($tcSim){
        $hash->{helper}{fkt}="vdCtrl";}
      elsif($thSim){
        $hash->{helper}{fkt}="virtThSens";}
      else         {
        delete $hash->{helper}{fkt};}
      
      if(!$tMstr)  {delete $hash->{sdTeam};}      
    }
    elsif ($st eq "smokeDetector"){
      foreach (split(",",$peerNames)){
        my $tn = ($_ =~ m/self/)?$name:$_;
        next if (!$defs{$tn});
        $defs{$tn}{sdTeam} = "sdLead" ;
        $defs{$tn}{helper}{fkt}="sdLead";
      }
      if($peerNames !~ m/self/){
        delete $hash->{sdTeam};
        delete $hash->{helper}{fkt};
      }
    }
    elsif( ($md =~ m/HM-CC-RT-DN/      && $chn=~ m/(02|05|04)/)
         ||($md eq "HM-TC-IT-WM-W-EU"  && $chn=~ m/(07)/)){
      if ($chn eq "04"){
        #if 04 is peered we are "teamed" -> set channel 05
        my $ch05H = $modules{CUL_HM}{defptr}{$dHash->{DEF}."05"};
        CUL_HM_UpdtReadSingle($ch05H,"state","peered",0) if($ch05H);
      }
      else{
        CUL_HM_UpdtReadSingle($hash,"state","peered",0);
      }
    }
    elsif( ($md =~ m/HM-CC-RT-DN/      && $chn=~ m/(03|06)/)
         ||($md eq "HM-TC-IT-WM-W-EU"  && $chn=~ m/(03|06)/)){
      if (AttrVal($hash,"state","unpeered") eq "unpeered"){
        CUL_HM_UpdtReadSingle($hash,"state","unknown",0);
      }
    }
  }
  else{
    delete $hash->{READINGS}{peerList};
    delete $hash->{peerList};
    if (($md =~ m/HM-CC-RT-DN/     && $chn=~ m/(02|03|04|05|06)/)
      ||($md eq "HM-TC-IT-WM-W-EU" && $chn=~ m/(03|06|07)/)){
      if ($chn eq "04"){
        my $ch05H = $modules{CUL_HM}{defptr}{$dHash->{DEF}."05"};
        CUL_HM_UpdtReadSingle($ch05H,"state","unpeered") if($ch05H);
      }
      else{
        CUL_HM_UpdtReadSingle($hash,"state","unpeered");
      }
    }
 }
}
sub CUL_HM_peerChId($$) {# in:<IDorName> <deviceID>, out:channelID
  my($pId,$dId)=@_;
  return "" if (!$pId);
  my $iId = CUL_HM_id2IoId($dId);
  my ($pSc,$pScNo) = unpack 'A4A*',$pId; #helper for shortcut spread
  return $dId.sprintf("%02X",'0'.$pScNo) if ($pSc eq 'self');
  return $iId.sprintf("%02X",'0'.$pScNo) if ($pSc eq 'fhem');
  return "all"                           if ($pId eq 'all');#used by getRegList
  my $p = CUL_HM_name2Id($pId).'01';
  return "" if (length($p)<8);
  return substr(CUL_HM_name2Id($pId).'01',0,8);# default chan is 01
}
sub CUL_HM_peerChName($$) {#in:<IDorName> <deviceID>, out:name
  my($pId,$dId)=@_;
  my $iId = CUL_HM_id2IoId($dId);
  my($pDev,$pChn) = unpack'A6A2',$pId;
  return 'self'.$pChn if ($pDev eq $dId);
  return 'fhem'.$pChn if ($pDev eq $iId && !defined $modules{CUL_HM}{defptr}{$pDev});
  return CUL_HM_id2Name($pId);
}
sub CUL_HM_getMId($) {#in: hash(chn or dev) out:model key (key for %culHmModel)
 # Will store result in device helper
  my $hash = shift;
  $hash = CUL_HM_getDeviceHash($hash);
  my $mId = $hash->{helper}{mId};
  if (!$mId){
    my $model = AttrVal($hash->{NAME}, "model", "");
    foreach my $mIdKey(keys%{$culHmModel}){
      next if (!$culHmModel->{$mIdKey}{name} ||
                $culHmModel->{$mIdKey}{name} ne $model);
      $hash->{helper}{mId} = $mIdKey ;
      return $mIdKey;
    }
    return "";
  }
  return $mId;
}
sub CUL_HM_getRxType($) { #in:hash(chn or dev) out:binary coded Rx type
 # Will store result in device helper
  my ($hash) = @_;
  $hash = CUL_HM_getDeviceHash($hash);
  no warnings; #convert regardless of content
  my $rxtEntity = int($hash->{helper}{rxType});
  use warnings;
  if (!$rxtEntity){ #at least one bit must be set
    my $MId = CUL_HM_getMId($hash);
    my $rxtOfModel = $culHmModel->{$MId}{rxt} if ($MId && $culHmModel->{$MId}{rxt});
    if ($rxtOfModel){
      $rxtEntity |= ($rxtOfModel =~ m/b/)?0x02:0;#burst
      $rxtEntity |= ($rxtOfModel =~ m/3/)?0x02:0;#tripple-burst todo currently unknown how it works
      $rxtEntity |= ($rxtOfModel =~ m/c/)?0x04:0;#config
      $rxtEntity |= ($rxtOfModel =~ m/w/)?0x08:0;#wakeup
      $rxtEntity |= ($rxtOfModel =~ m/l/)?0x10:0;#lazyConfig
      $rxtEntity |= ($rxtOfModel =~ m/f/)?0x80:0;#burstConditional
    }
    $rxtEntity = 1 if (!$rxtEntity);#always
    $hash->{helper}{rxType} = $rxtEntity if ($MId);#store if ID is prooven
  }
  return $rxtEntity;
}
sub CUL_HM_getFlag($) {#mFlg 'A0' or 'B0' for burst/normal devices
  # currently not supported is the wakeupflag since it is hardly used
  return 'A0'; #burst mode implementation changed
  my ($hash) = @_;
  return (CUL_HM_getRxType($hash) & 0x02)?"B0":"A0"; #set burst flag
}
sub CUL_HM_getAssChnIds($) { #in: name out:ID list of assotiated channels
  # if it is a channel only return itself
  # if device and no channel
  my ($name) = @_;
  my @chnIdList;
  if ($defs{$name}){
    my $hash = $defs{$name};
    foreach my $channel (grep /^channel_/, keys %{$hash}){
      my $chnHash = $defs{$hash->{$channel}};
      push @chnIdList,$chnHash->{DEF} if ($chnHash);
    }
    my $dId = CUL_HM_name2Id($name);
    
    push @chnIdList,$dId."01" if (length($dId) == 6 && !$hash->{channel_01});
    push @chnIdList,$dId if (length($dId) == 8);
  }
  return sort(@chnIdList);
}
sub CUL_HM_getAssChnNames($) { #in: name out:list of assotiated chan and device
  my ($name) = @_;
  my @chnN = ($name);
  if ($defs{$name}){
    my $hash = $defs{$name};
    push @chnN,$defs{$name}{$_} foreach (grep /^channel_/, keys %{$defs{$name}});
  }
  return sort(@chnN);
}
#+++++++++++++++++ Conversions names, hashes, ids++++++++++++++++++++++++++++++
#Performance opti: subroutines may consume up to 5 times the performance
#
#get Attr: $val  = $attr{$hash->{NAME}}{$attrName}?$attr{$hash->{NAME}}{$attrName}      :"";
#          $val  = $attr{$name}{$attrName}        ?$attr{$name}{$attrName}              :"";
#getRead:  $val  = $hash->{READINGS}{$rlName}     ?$hash->{READINGS}{$rlName}{VAL}      :"";
#          $val  = $defs{$name}{READINGS}{$rlName}?$defs{$name}{READINGS}{$rlName}{VAL} :"";
#          $time = $hash->{READINGS}{$rlName}     ?$hash->{READINGS}{$rlName}{time}     :"";

sub CUL_HM_h2IoId($) {      #in: ioHash out: ioHMid
  my ($io) = @_;
  return "000000" if (ref($io) ne 'HASH');

  my $fhtid = defined($io->{FHTID}) ? $io->{FHTID} : "0000";
  return AttrVal($io->{NAME},"hmId","F1$fhtid");
}
sub CUL_HM_IoId($) {        #in: hash out: IO_id
  my ($hash) = @_;
  my $dHash = CUL_HM_getDeviceHash($hash);
  my $ioHash = $dHash->{IODev};
  return "" if (!$ioHash->{NAME});
  my $fhtid = defined($ioHash->{FHTID}) ? $ioHash->{FHTID} : "0000";
  return AttrVal($ioHash->{NAME},"hmId","F1$fhtid");
}
sub CUL_HM_id2IoId($) {     #in: id, out:Id of assigned IO
  my ($id) = @_;
  ($id) = unpack 'A6',$id;#get device ID
  return "" if (!$modules{CUL_HM}{defptr}{$id} ||
                !$modules{CUL_HM}{defptr}{$id}->{IODev} ||
                !$modules{CUL_HM}{defptr}{$id}->{IODev}->{NAME});
  my $ioHash = $modules{CUL_HM}{defptr}{$id}->{IODev};
  my $fhtid = defined($ioHash->{FHTID}) ? $ioHash->{FHTID} : "0000";
  return AttrVal($ioHash->{NAME},"hmId","F1$fhtid");
}
sub CUL_HM_name2IoName($) { #in: hash out: IO_id
  my ($name) = @_;
  my $dHash = CUL_HM_getDeviceHash($defs{$name});
  my $ioHash = $dHash->{IODev};
  return $ioHash->{NAME} ? $ioHash->{NAME} : "";
}

sub CUL_HM_hash2Id($) {  #in: id,   out:hash
  my ($hash) = @_;
  return $hash->{DEF};
}
sub CUL_HM_hash2Name($) {#in: hash, out:name
  my ($hash) = @_;
  return $hash->{NAME};
}
sub CUL_HM_name2Hash($) {#in: name, out:hash
  my ($name) = @_;
  return $defs{$name};
}
sub CUL_HM_name2Id(@) { #in: name or HMid ==>out: HMid, "" if no match
  my ($name,$idHash) = @_;
  my $hash = $defs{$name};
  return $hash->{DEF}        if($hash && $hash->{TYPE} eq "CUL_HM");#name is entity
  return $name               if($name =~ m/^[A-F0-9]{6,8}$/i);#was already HMid
  return $defs{$1}->{DEF}.$2 if($name =~ m/(.*)_chn:(..)/);   #<devname> chn:xx
  return "000000"            if($name eq "broadcast");        #broadcast
  return substr($idHash->{DEF},0,6).sprintf("%02X",$1)
                             if($idHash && ($name =~ m/self(.*)/));
  return CUL_HM_IoId($idHash).sprintf("%02X",$1)
                             if($idHash && ($name =~ m/fhem(.*)/));
  return AttrVal($name,"hmId",""); # could be IO device
}
sub CUL_HM_id2Name($) { #in: name or HMid out: name
  my ($p) = @_;
  $p = "" if (!defined $p);
  return $p                               if($defs{$p}||$p =~ m/_chn:/
                                             || $p !~ m/^[A-F0-9]{6,8}$/i);
  my $devId= substr($p, 0, 6);
  return "broadcast"                      if($devId eq "000000");

  my $defPtr = $modules{CUL_HM}{defptr};
  if (length($p) == 8){
    return $defPtr->{$p}{NAME}            if(defined $defPtr->{$p});#channel
    return $defPtr->{$devId}{NAME}."_chn:".substr($p,6,2)
                                          if($defPtr->{$devId});#dev, add chn
    return $p;                               #not defined, return ID only
  }
  else{
    return $defPtr->{$devId}{NAME}        if($defPtr->{$devId});#device only
    return $devId;                           #not defined, return ID only
  }
}
sub CUL_HM_id2Hash($) { #in: id, out:hash
  my ($id) = @_;
  return $modules{CUL_HM}{defptr}{$id} if (defined $modules{CUL_HM}{defptr}{$id});
  $id = substr($id,0,6);
  return defined $modules{CUL_HM}{defptr}{$id}?($modules{CUL_HM}{defptr}{$id}):undef;
}
sub CUL_HM_getDeviceHash($) {#in: hash out: devicehash
  my ($hash) = @_;
  return $hash if(!$hash->{DEF});
  my $devHash = $modules{CUL_HM}{defptr}{substr($hash->{DEF},0,6)};
  return ($devHash)?$devHash:$hash;
}
sub CUL_HM_getDeviceName($) {#in: name out: name of device
  my $name = shift;
  return $name if(!$defs{$name});#unknown, return input
  my $devHash = $modules{CUL_HM}{defptr}{substr($defs{$name}{DEF},0,6)};
  return ($devHash)?$devHash->{NAME}:$name;
}
sub CUL_HM_shH($$$){
  my ($h,$l,$d) = @_;
  if (   $h->{helper}{shRegW} 
      && $h->{helper}{shRegW}{$l}
      && $modules{CUL_HM}{defptr}{$d.$h->{helper}{shRegW}{$l}}){
    return $modules{CUL_HM}{defptr}{$d.$h->{helper}{shRegW}{$l}};
  }
  return $h;
}
sub CUL_HM_shC($$$){
  my ($h,$l,$c) = @_;
  if (   $h->{helper}{shRegW} 
      && $h->{helper}{shRegW}{$l}){
    return $h->{helper}{shRegW}{$l};
  }
  return $c;
}
sub CUL_HM_lstCh($$$){
  my ($h,$l,$c) = @_;
  if (   $h->{helper}{shRegR} 
      && $h->{helper}{shRegR}{$l}){
    return $h->{helper}{shRegR}{$l};
  }
  return $c;
}

#+++++++++++++++++ debug ++++++++++++++++++++++++++++++++++++++++++++++++++++++
sub CUL_HM_DumpProtocol($$@) {
  my ($prefix, $iohash, $len,$cnt,$msgFlags,$mTp,$src,$dst,$p) = @_;
  my $iname = $iohash->{NAME};
  no warnings;# conv 2 number would cause a warning - which is ok
  my $hmProtocolEvents = int (AttrVal(CUL_HM_id2Name($src), "hmProtocolEvents",
                              AttrVal(InternalVal($iname,"owner_CCU",$iname), "hmProtocolEvents", 0)));
  use warnings;
  return if(!$hmProtocolEvents);

  my $p01 = substr($p,0,2);
  my $p02 = substr($p,0,4);
  my $p11 = (length($p) > 2 ? substr($p,2,2) : "");

  # decode message flags for printing
  my $msgFlLong="";
  my $msgFlagsHex = hex($msgFlags);
  for(my $i = 0; $i < @{$culHmCmdFlags}; $i++) {
    $msgFlLong .= ",".${$culHmCmdFlags}[$i] if($msgFlagsHex & (1<<$i));
  }

  my $ps;
  $ps = $culHmBits->{"$mTp;p11=$p11"} if(!$ps);
  $ps = $culHmBits->{"$mTp;p01=$p01"} if(!$ps);
  $ps = $culHmBits->{"$mTp;p02=$p02"} if(!$ps);
  $ps = $culHmBits->{"$mTp"}          if(!$ps);
  my $txt = "";
  if($ps) {
    $txt = $ps->{txt};
    if($ps->{params}) {
      $ps = $ps->{params};
      foreach my $k (sort {$ps->{$a} cmp $ps->{$b} } keys %{$ps}) {
        my ($o,$l,$expr) = split(",", $ps->{$k}, 3);
        last if(length($p) <= $o);
        my $val = $l ? substr($p,$o,$l) : substr($p,$o);
        eval $expr if($hmProtocolEvents > 1 && $expr);
        $txt .= " $k:".(($hmProtocolEvents > 1 && $expr)?"":"0x")."$val";
      }
    }
    $txt = " ($txt)" if($txt);
  }
  $src=CUL_HM_id2Name($src);
  $dst=CUL_HM_id2Name($dst);
  my $msg ="$prefix L:$len N:$cnt F:$msgFlags CMD:$mTp SRC:$src DST:$dst $p$txt ($msgFlLong)";
  Log3 $iname,1,$msg;
  DoTrigger($iname, $msg) if($hmProtocolEvents > 2);
}

#+++++++++++++++++ handling register updates ++++++++++++++++++++++++++++++++++
sub CUL_HM_getRegFromStore($$$$@) {#read a register from backup data
  my($name,$regName,$list,$peerId,$regLN)=@_;
  my $hash = $defs{$name};
  my ($size,$pos,$conv,$factor,$unit) = (8,0,"",1,""); # default
  my $addr = $regName;
  my $reg = $culHmRegDefine->{$regName};
  if ($reg) { # get the register's information
    $addr = $reg->{a};
    $pos = ($addr*10)%10;
    $addr = int($addr);
    $list = $reg->{l};
    $size = $reg->{s};
    $size = int($size)*8 + ($size*10)%10;
    $conv = $reg->{c}; #unconvert formula
    $factor = $reg->{f};
    $unit = ($reg->{u}?" ".$reg->{u}:"");
  }
  else{
    return "invalid:regname or address"
            if($addr<1 ||$addr>255);
  }
  my $dst = substr(CUL_HM_name2Id($name),0,6);
  if(!$regLN){
    $regLN = ((CUL_HM_getAttrInt($name,"expert") == 2)?"":".")
              .sprintf("RegL_%02X:",$list)
              .($peerId?CUL_HM_peerChName($peerId,
                                          $dst)
                       :"");
  }
  $regLN =~ s/broadcast//;
  my $regLNp = $regLN;
  $regLNp =~s/^\.//; #remove leading '.' in case ..
  my $sdH = CUL_HM_shH($hash,sprintf("%02X",$list),$dst);
  my $sRL = (    $sdH->{helper}{shadowReg}          # shadowregList
              && $sdH->{helper}{shadowReg}{$regLNp})
                           ?$sdH->{helper}{shadowReg}{$regLNp}
                           :"";
  my $rRL = ($hash->{READINGS}{$regLN})              #realRegList
                           ?$hash->{READINGS}{$regLN}{VAL}
                           :"";
  
  my $data=0;
  my $convFlg = "";# confirmation flag - indicates data not confirmed by device
  for (my $size2go = $size;$size2go>0;$size2go -=8){
    my $addrS = sprintf("%02X",$addr);
    my ($dReadS,$dReadR) = (undef,"");  
    $dReadS = $1 if( $sRL =~ m/$addrS:(..)/);
    $dReadR = $1 if( $rRL =~ m/$addrS:(..)/);
    my $dRead = $dReadR;
    if (defined $dReadS){
      $convFlg = "set_" if ($dReadR ne $dReadS);
      $dRead = $dReadS;
    }
    else{
      if (grep /$regLN../,keys %{$hash->{READINGS}} &&
           !$peerId){
        return "invalid:peer missing";
      }
      return "invalid" if (!defined($dRead) || $dRead eq "");
    }

    $data = ($data<< 8)+hex($dRead);
    $addr++;
  }

  $data = ($data>>$pos) & (0xffffffff>>(32-$size));
  if (!$conv){                ;# do nothing
  } elsif($conv eq "lit"     ){$data = defined $reg->{litInv}{$data}?$reg->{litInv}{$data}:"undef lit:$data";
  } elsif($conv eq "fltCvT"  ){$data = CUL_HM_CvTflt($data);
  } elsif($conv eq "fltCvT60"){$data = CUL_HM_CvTflt60($data);
  } elsif($conv eq "min2time"){$data = CUL_HM_min2time($data);
  } elsif($conv eq "m10s3"   ){$data = ($data+3)/10;
  } elsif($conv eq "hex"     ){$data = sprintf("0x%06X",$data);#06 only for paired to. Currently not used by others
  } else { return " conv undefined - please contact admin";
  }
  $data /= $factor if ($factor);# obey factor after possible conversion
  if ($conv ne "lit" && $reg->{litInv} && $reg->{litInv}{$data} ){
    $data = $reg->{litInv}{$data};#conv special value past to calculation
    $unit = "";
  }     
  return $convFlg.$data.$unit;
}
sub CUL_HM_updtRegDisp($$$) {
  my($hash,$list,$peerId)=@_;
  my $listNo = $list+0;
  my $name = $hash->{NAME};
  my $devId = substr(CUL_HM_name2Id($name),0,6);
  my $ioId = CUL_HM_IoId(CUL_HM_id2Hash($devId));
  my $pReg = ($peerId && $peerId ne '00000000' )?
     CUL_HM_peerChName($peerId,$devId)."-":"";
  $pReg=~s/:/-/;
  $pReg="R-".$pReg;
  my $devName =CUL_HM_getDeviceHash($hash)->{NAME};# devName as protocol entity
  my $st = $attr{$devName}{subType} ?$attr{$devName}{subType} :"";
  my $md = $attr{$devName}{model}   ?$attr{$devName}{model}   :"";
  my $chn = $hash->{DEF};
  $chn = (length($chn) == 8)?substr($chn,6,2):"";
  my @regArr = CUL_HM_getRegN($st,$md,$chn);
  my @changedRead;
  my $expL = CUL_HM_getAttrInt($name,"expert");
  my $expLvl = ($expL != 0)?1:0;
  
  my $regLN = (($expL == 2)?"":".")
              .sprintf("RegL_%02X:",$listNo)
              .($peerId?CUL_HM_peerChName($peerId,$devId):"");
              
  if (($md eq "HM-MOD-Re-8") && $listNo == 0){#handle Fw bug 
    CUL_HM_ModRe8($hash,$regLN);
  }
  foreach my $rgN (@regArr){
    next if ($culHmRegDefine->{$rgN}->{l} ne $listNo);
    my $rgVal = CUL_HM_getRegFromStore($name,$rgN,$list,$peerId,$regLN);
    next if (!defined $rgVal || $rgVal =~ m /invalid/);
    my $rdN = ((!$expLvl && !$culHmRegDefine->{$rgN}->{d})?".":"").$pReg.$rgN;
    push (@changedRead,$rdN.":".$rgVal)
          if (ReadingsVal($name,$rdN,"") ne $rgVal);
  }
  CUL_HM_UpdtReadBulk($hash,1,@changedRead) if (@changedRead);

  # ---  handle specifics -  Devices with abnormal or long register
  if ($md =~ m/(HM-CC-TC|ROTO_ZEL-STG-RM-FWT)/){#handle temperature readings
    CUL_HM_TCtempReadings($hash)  if (($list == 5 ||$list == 6) &&
                      substr($hash->{DEF},6,2) eq "02");
  }
  elsif ($md =~ m/HM-CC-RT-DN/){#handle temperature readings
    CUL_HM_TCITRTtempReadings($hash,$md,7)  if ($list == 7 && $chn eq "04");
  }
  elsif ($md =~ m/HM-TC-IT-WM-W-EU/){#handle temperature readings
    CUL_HM_TCITRTtempReadings($hash,$md,$list)  if ($list >= 7 && $chn eq "02");
  }
  elsif ($md =~ m/(^HM-PB-4DIS-WM|HM-Dis-WM55|HM-RC-Dis-H-x-EU)/){#add text
   CUL_HM_4DisText($hash)  if ($list == 1) ;
  }
  elsif ($st eq "repeater"){
    CUL_HM_repReadings($hash) if ($list == 2);
  }
#  CUL_HM_dimLog($hash) if(CUL_HM_Get($hash,$name,"param","subType") eq "dimmer");
}
sub CUL_HM_rmOldRegs($){ # remove register i outdated
  #will remove register for deleted peers
  my $name = shift;
  my $hash = $defs{$name};
  return if (!$hash->{peerList});# so far only peer-regs are removed
  my @pList = split",",$hash->{peerList};
  my @rpList;
  foreach(grep /^R-(.*)-/,keys %{$hash->{READINGS}}){
    push @rpList,$1 if ($_ =~m /^R-(.*)-/);
  }
  @rpList = CUL_HM_noDup(@rpList);
  return if (!@rpList);
  foreach my $peer(@rpList){
    next if($hash->{peerList} =~ m /\b$peer\b/);
    delete $hash->{READINGS}{$_} foreach (grep /^R-$peer-/,keys %{$hash->{READINGS}})
  }
}

#############################
#+++++++++++++++++ parameter cacculations +++++++++++++++++++++++++++++++++++++
my @culHmTimes8 = ( 0.1, 1, 5, 10, 60, 300, 600, 3600 );
sub CUL_HM_encodeTime8($) {#####################
  my $v = shift;
  return "00" if($v < 0.1);
  for(my $i = 0; $i < @culHmTimes8; $i++) {
    if($culHmTimes8[$i] * 32 > $v) {
      for(my $j = 0; $j < 32; $j++) {
        if($j*$culHmTimes8[$i] >= $v) {
          return sprintf("%X", $i*32+$j);
        }
      }
    }
  }
  return "FF";
}
sub CUL_HM_decodeTime8($) {#####################
  my $v = hex(shift);
  return "undef" if($v > 255);
  my $v1 = int($v/32);
  my $v2 = $v%32;
  return $v2 * $culHmTimes8[$v1];
}
sub CUL_HM_encodeTime16($) {####################
  my $v = shift;
  return "0000" if($v < 0.05 || $v !~ m/^[+-]?\d+(\.\d+)?$/);

  my $ret = "FFFF";
  my $mul = 10;
  for(my $i = 0; $i < 32; $i++) {
    if($v*$mul < 0x7ff) {
      $ret=sprintf("%04X", ((($v*$mul)<<5)+$i));
      last;
    }
    $mul /= 2;
  }
  return ($ret);
}
sub CUL_HM_convTemp($) {########################
  my ($val) = @_;

  if(!($val eq "on" || $val eq "off" ||
      ($val =~ m/^\d*\.?\d+$/ && $val >= 6 && $val <= 30))) {
    my @list = map { ($_.".0", $_+0.5) } (6..30);
    pop @list;
    return "Invalid temperature $val, choose one of on off " . join(" ",@list);
  }
  $val = 100 if($val eq "on");
  $val =   0 if($val eq "off");
  return sprintf("%02X", $val*2);
}
sub CUL_HM_decodeTime16($) {####################
  my $v = hex(shift);
  my $m = int($v>>5);
  my $e = $v & 0x1f;
  my $mul = 0.1;
  return 2^$e*$m*0.1;
}
sub CUL_HM_secSince2000() {#####################
  # Calculate the local time in seconds from 2000.
  my $t = time();

  my @l = localtime($t);
  my @g = gmtime($t);
  my $t2 = $t + 60*(($l[2]-$g[2] + ((($l[5]<<9)|$l[7]) <=> (($g[5]<<9)|$g[7])) * 24) * 60 + $l[1]-$g[1])
                           # timezone and daylight saving...
        - 946684800        # seconds between 01.01.2000, 00:00 and THE EPOCH (1970)
        - 7200;            # HM Special
  return $t2;
}
sub CUL_HM_getChnLvl($){# in: name out: vit or phys level
  my $name = shift;
  my $curVal = ReadingsVal($name,"level",undef);
  $curVal = ReadingsVal($name,".level",0)if (!defined $curVal);
  $curVal =~ s/set_//;
  $curVal =~ s/ .*//;#strip unit
  return $curVal;
}

#--------------- Conversion routines for register settings---------------------
sub CUL_HM_initRegHash() { #duplicate short and long press register
  my $mp = "$attr{global}{modpath}/FHEM";
  opendir(DH, $mp) || return;
  foreach my $m (grep /^HMConfig_(.*)\.pm$/,readdir(DH)) {
    my $file = "${mp}/$m";
    no strict "refs";
      my $ret = do $file;
    use strict "refs";
    if(!$ret){ Log3 undef, 1, "Error loading file: $file:\n $@";}
    else     { Log3 undef, 3, "additional HM config file loaded: $file";}
  }
  closedir(DH);
}

my %fltCvT60 = (1=>127,60=>7620);
sub CUL_HM_fltCvT60($) { # float -> config time
  my ($inValue) = @_;
  my $exp = 0;
  my $div2;
  foreach my $div(sort{$a <=> $b} keys %fltCvT60){
    $div2 = $div;
    last if ($inValue < $fltCvT60{$div});
    $exp++;
  }
  return ($exp << 7)+int($inValue/$div2+.1);
}
sub CUL_HM_CvTflt60($) { # config time -> float
  my ($inValue) = @_;
  return ($inValue & 0x7f)*((sort {$a <=> $b} keys(%fltCvT60))[$inValue >> 7]);
}

my %fltCvT = (0.1=>3.1,1=>31,5=>155,10=>310,60=>1860,300=>9300,
              600=>18600,3600=>111601);
sub CUL_HM_fltCvT($) { # float -> config time
  my ($inValue) = @_;
  my $exp = 0;
  my $div2;
  foreach my $div(sort{$a <=> $b} keys %fltCvT){
    $div2 = $div;
    last if ($inValue < $fltCvT{$div});
    $exp++;
  }
  return ($exp << 5)+int($inValue/$div2+.1);
}
sub CUL_HM_CvTflt($) { # config time -> float
  my ($inValue) = @_;
  return ($inValue & 0x1f)*((sort {$a <=> $b} keys(%fltCvT))[$inValue >> 5]);
}
sub CUL_HM_min2time($) { # minutes -> time
  my $min = shift;
  $min = $min * 30;
  return sprintf("%02d:%02d",int($min/60),$min%60);
}
sub CUL_HM_time2min($) { # minutes -> time
  my $time = shift;
  my ($h,$m) = split ":",$time;
  $m = ($h*60 + $m)/30;
  $m = 0 if($m < 0);
  $m = 47 if($m > 47);
  return $m;
}

sub CUL_HM_getRegN($$@){ # get list of register for a model
  my ($st,$md,@chn) = @_;
  my @regArr = keys %{$culHmRegGeneral};
  push @regArr, keys %{$culHmRegType->{$st}}      if($culHmRegType->{$st});
  push @regArr, keys %{$culHmRegModel->{$md}}     if($culHmRegModel->{$md});
  foreach (@chn){
    push @regArr, keys %{$culHmRegChan->{$md.$_}} if($culHmRegChan->{$md.$_});
  }
  return @regArr;
}
sub CUL_HM_4DisText($) {      # convert text for 4dis
  #text1: start at 54 (0x36) length 12 (0x0c)
  #text2: start at 70 (0x46) length 12 (0x0c)
  my ($hash)=@_;
  my $name = $hash->{NAME};
  my $regPre = ((CUL_HM_getAttrInt($name,"expert") == 2)?"":".");
  my $reg1 = ReadingsVal($name,$regPre."RegL_01:" ,"");
  my $pref = "";
  if ($hash->{helper}{shadowReg}{"RegL_01:"}){
    $pref = "set_";
    $reg1 = $hash->{helper}{shadowReg}{"RegL_01:"};
  }
  my %txt;
  foreach my $sAddr (54,70){
    my $txtHex = $reg1;  #one row
    my $sStr = sprintf("%02X:",$sAddr);
    $txtHex =~ s/.* $sStr//;       #remove reg prior to string
    $sStr = sprintf("%02X:",$sAddr+11);
    $txtHex =~ s/$sStr(..).*/,$1/; #remove reg after string
    $txtHex =~ s/ ..:/,/g;         #remove addr
    $txtHex =~ s/ //g;             #remove space
    $txtHex =~ s/,00.*//;          #remove trailing string
    my @ch = split(",",$txtHex,12);
    foreach (@ch){$txt{$sAddr}.=chr(hex($_)) if (length($_)==2)};
  }
  CUL_HM_UpdtReadBulk($hash,1,"text1:".$pref.$txt{54},
                              "text2:".$pref.$txt{70});
  return "text1:".$txt{54}."\n".
         "text2:".$txt{70}."\n";
}
sub CUL_HM_TCtempReadings($) {# parse TC temperature readings
  my ($hash)=@_;
  my $name = $hash->{NAME};
  my $regPre = ((CUL_HM_getAttrInt($name,"expert") == 2)?"":".");
  my $reg5 = ReadingsVal($name,$regPre."RegL_05:" ,"");
  my $reg6 = ReadingsVal($name,$regPre."RegL_06:" ,"");
  { #update readings in device - oldfashioned style, copy from Readings
    my @histVals;
    foreach my $var ("displayMode","displayTemp","controlMode","decalcDay","displayTempUnit","day-temp","night-temp","party-temp"){
      my $varV = ReadingsVal($name,"R-".$var,"???");
      
      foreach my $e( grep {${$_}[2] =~ m/$var/}# see if change is pending
                     grep {$hash eq ${$_}[0]}
                     grep {scalar(@{$_} == 3)}
                     @evtEt){
        $varV = ${$e}[2];
        $varV =~ s/^R-$var:// ;
      }
      push @histVals,"$var:$varV";
    }
    if (@histVals){
      CUL_HM_UpdtReadBulk($hash,1,@histVals) ;
      CUL_HM_UpdtReadBulk(CUL_HM_getDeviceHash($hash),1,@histVals);
    }
  }
  
  if (ReadingsVal($name,"R-controlMode","") =~ m/^party/){
    if (   $reg6                # ugly handling to add vanishing party register
        && $reg6 !~ m/ 61:/
        && $hash->{helper}{partyReg}){
      $hash->{READINGS}{"RegL_06:"}{VAL} =~s/ 00:00/$hash->{helper}{partyReg}/;
    }
   }
  else{
    delete $hash->{helper}{partyReg};
  }

  my @days = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");
  $reg5 =~ s/.* 0B://;     #remove register up to addr 11 from list 5
  my $tempRegs = $reg5.$reg6;  #one row
  $tempRegs =~ s/ 00:00/ /g;   #remove regline termination
  $tempRegs =~ s/ ..:/,/g;     #remove addr Info
  $tempRegs =~ s/ //g;         #blank
  my @Tregs = split(",",$tempRegs);
  my @time  = @Tregs[grep !($_ % 2), 0..$#Tregs]; # even-index =time
  my @temp  = @Tregs[grep $_ % 2, 0..$#Tregs];    # odd-index  =data

  my @changedRead;
  my $setting;
  if (scalar( @time )<168){
    push (@changedRead,"R_tempList_State:incomplete");
    $setting = "reglist incomplete\n" ;
  }
  else{
    delete $hash->{READINGS}{$_} 
            foreach (grep !/_/,grep /tempList/,keys %{$hash->{READINGS}});
    
    foreach  (@time){$_=hex($_)*10};
    foreach  (@temp){$_=hex($_)/2};
    push (@changedRead,"R_tempList_State:".
                  (($hash->{helper}{shadowReg}{"RegL_05:"} ||
                    $hash->{helper}{shadowReg}{"RegL_06:"} )?"set":"verified"));
    for (my $day = 0; $day < 7; $day++){
      my $tSpan  = 0;
      my $dayRead = "";
      for (my $entry = 0;$entry<24;$entry++){
        my $reg = $day *24 + $entry;
        last if ($tSpan > 1430);
        $tSpan = $time[$reg];
        my $entry = sprintf("%02d:%02d %3.01f",($tSpan/60),($tSpan%60),$temp[$reg]);
          $setting .= "Temp set: ${day}_".$days[$day]." ".$entry." C\n";
          $dayRead .= " ".$entry;
        $tSpan = $time[$reg];
      }
      push (@changedRead,"R_${day}_tempList$days[$day]:$dayRead");
    }
  }
  CUL_HM_UpdtReadBulk($hash,1,@changedRead) if (@changedRead);

  return $setting;
}
sub CUL_HM_TCITRTtempReadings($$@) {# parse RT - TC-IT temperature readings
  my ($hash,$md,@list)=@_;
  my $name = $hash->{NAME};
  my $regPre = ((CUL_HM_getAttrInt($name,"expert") == 2)?"":".");
  my @changedRead;
  my $setting="";
  my %idxN = (7=>"P1_",8=>"P2_",9=>"P3_");
  $idxN{7} = "" if($md =~ m/CC-RT/);# not prefix for RT
  my @days = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");
  foreach my $lst (@list){
    my @r1;
    $lst +=0;
    # cleanup old value formats
    my $ln = length($idxN{$lst})?substr($idxN{$lst},0,2):"";
    delete $hash->{READINGS}{$_} 
          foreach (grep !/_/,grep /tempList$ln/,keys %{$hash->{READINGS}});
    my $tempRegs = ReadingsVal($name,$regPre."RegL_0$lst:","");
    if ($tempRegs !~ m/00:00/){
      for (my $day = 0;$day<7;$day++){
        push (@changedRead,"R_$idxN{$lst}${day}_tempList".$days[$day].":incomplete");
      }
      push (@changedRead,"R_$idxN{$lst}tempList_State:incomplete");
      CUL_HM_UpdtReadBulk($hash,1,@changedRead) if (@changedRead);
      next;
    }

    foreach(split " ",$tempRegs){
      my ($a,$d) = split ":",$_;
      $r1[hex($a)] = $d;
    }

    if ($hash->{helper}{shadowReg}{"RegL_0$lst:"}){
      my $ch = 0;
      foreach(split " ",$hash->{helper}{shadowReg}{"RegL_0$lst:"}){
        my ($a,$d) = split ":",$_;
        $a = hex($a);
        $ch = 1 if ((!$r1[$a] || $r1[$a] ne $d) && $a >= 20);
        $r1[$a] = $d;
      }
      push (@changedRead,"R_$idxN{$lst}tempList_State:set") if ($ch);
    }
    else{
      push (@changedRead,"R_$idxN{$lst}tempList_State:verified");
    }
     
    $tempRegs = join("",@r1[20..scalar@r1-1]);
    for (my $day = 0;$day<7;$day++){
      my $dayRead = "";
      my @time;
      my @temp;
      if (length($tempRegs)<($day+1) *13*4) {
        push (@changedRead,"R_$idxN{$lst}${day}_tempList$days[$day]:incomplete");
        $setting .= "Temp set $idxN{$lst}: ${day}_".$days[$day]." incomplete\n";
      }
      else{
        foreach (unpack '(A4)*',substr($tempRegs,$day *13*4,13*4)){
          my $h = hex($_);
          push @temp,($h >> 9)/2;
          $h = ($h & 0x1ff) * 5;
          $h = sprintf("%02d:%02d",int($h / 60),($h%60));
          push @time,$h;
        }
        for (my $idx = 0;$idx<13;$idx++){
          my $entry = sprintf(" %s %3.01f",$time[$idx],$temp[$idx]);
            $setting .= "Temp set $idxN{$lst}: ${day}_".$days[$day].$entry." C\n";
            $dayRead .= $entry;
          last if ($time[$idx] eq "24:00");
        }
        push (@changedRead,"R_$idxN{$lst}${day}_tempList$days[$day]:$dayRead");
      }
    }
  }
  CUL_HM_UpdtReadBulk($hash,1,@changedRead) if (@changedRead);
  return $setting;
}
sub CUL_HM_repReadings($) {   # parse repeater
  my ($hash)=@_;
  my %pCnt;
  my $cnt = 0;
  return "" if (!$hash->{helper}{peerIDsRaw});
  foreach my$pId(split',',$hash->{helper}{peerIDsRaw}){
    next if (!$pId || $pId eq "00000000");
    $pCnt{$pId.$cnt}{cnt}=$cnt++;
  }

  my @pS;
  my @pD;
  my @pB;
  foreach (split",",(AttrVal($hash->{NAME},"repPeers",undef))){
    my ($s,$d,$b) = split":",$_;
    push @pS,$s;
    push @pD,$d;
    push @pB,$b;
  }
  my @readList;
  push @readList,"repPeer_".sprintf("%02d",$_+1).":undefined" for(0..35);#set default empty
  my @retL;
  foreach my$pId(sort keys %pCnt){
    my ($pdID,$bdcst,$no) = unpack('A6A2A2',$pId);
    my $fNo = $no-1;#shorthand field number, often used
    my $sName = CUL_HM_id2Name($pdID);

    if ($sName eq $pdID && $pD[$fNo]){
      $sName = $defs{$pD[$fNo]}->{IODev}{NAME}
            if($attr{$defs{$pD[$fNo]}->{IODev}{NAME}}{hmId} eq $pdID);
    }
    my $eS = sprintf("%02d:%-15s %-15s %-3s %-4s",
               $no
              ,$sName
              ,((!$pS[$fNo] || $pS[$fNo] ne $sName)?"unknown":" dst>$pD[$fNo]")
              ,($bdcst eq "01"?"yes":"no ")
              ,($pB[$fNo] && (  ($bdcst eq "01" && $pB[$fNo] eq "y")
                              ||($bdcst eq "00" && $pB[$fNo] eq "n")) ?"ok":"fail")
              );
    push @retL,$eS;
    $readList[$fNo]="repPeer_".$eS;
  }
  CUL_HM_UpdtReadBulk($hash,0,@readList);
  return "No Source          Dest            Bcast\n". join"\n", sort @retL;
}
sub CUL_HM_ModRe8($$)     {   # repair FW bug
  #Register 18 may come with a wrong address - we will corrent that
  my ($hash,$regN)=@_;
  my $rl0 = ReadingsVal($hash->{NAME},$regN,"empty");
  return if(  $rl0 !~ m/00:00/ # not if List is incomplete
            ||$rl0 =~ m/12:/ ); # reg 18 present, dont touch
  foreach my $ad (split(" ",$rl0)){
    my ($a,$d) = split(":",$ad);
    my $ah = hex($a);
    if ($ah & 0xe0 && (($ah & 0x1F) == 0x12)){
      Log3 $hash,3,"CUL_HM replace address $a to 0x12";
      $hash->{READINGS}{$regN}{VAL} =~ s/ $a:/ 12:/;
      last;
    }
  }
}
sub CUL_HM_dimLog($) {# dimmer readings - support virtual chan - unused so far
  my ($hash)=@_;
  my $lComb = CUL_HM_Get($hash,$hash->{NAME},"reg","logicCombination");
  return if (!$lComb);
  my %logicComb=(
                      inactive=>{calc=>'$val=$val'                                      ,txt=>'unused'},
                      or      =>{calc=>'$val=$in>$val?$in:$val'                         ,txt=>'max(state,chan)'},
                      and     =>{calc=>'$val=$in<$val?$in:$val'                         ,txt=>'min(state,chan)'},
                      xor     =>{calc=>'$val=!($in!=0&&$val!=0)?($in>$val?$in:$val): 0' ,txt=>'0 if both are != 0, else max'},
                      nor     =>{calc=>'$val=100-($in>$val?$in : $val)'                 ,txt=>'100-max(state,chan)'},
                      nand    =>{calc=>'$val=100-($in<$val?$in : $val)'                 ,txt=>'100-min(state,chan)'},
                      orinv   =>{calc=>'$val=(100-$in)>$val?(100-$in) : $val'           ,txt=>'max((100-chn),state)'},
                      andinv  =>{calc=>'$val=(100-$in)<$val?(100-$in) : $val'           ,txt=>'min((100-chn),state)'},
                      plus    =>{calc=>'$val=($in + $val)<100?($in + $val) : 100'       ,txt=>'state + chan'},
                      minus   =>{calc=>'$val=($in - $val)>0?($in + $val) : 0'           ,txt=>'state - chan'},
                      mul     =>{calc=>'$val=($in * $val)<100?($in + $val) : 100'       ,txt=>'state * chan'},
                      plusinv =>{calc=>'$val=($val+100-$in)<100?($val+100-$in) : 100'   ,txt=>'state + 100 - chan'},
                      minusinv=>{calc=>'$val=($val-100+$in)>0?($val-100+$in) : 0'       ,txt=>'state - 100 + chan'},
                      mulinv  =>{calc=>'$val=((100-$in)*$val)<100?(100-$in)*$val) : 100',txt=>'state * (100 - chan)'},
                      invPlus =>{calc=>'$val=(100-$val-$in)>0?(100-$val-$in) : 0'       ,txt=>'100 - state - chan'},
                      invMinus=>{calc=>'$val=(100-$val+$in)<100?(100-$val-$in) : 100'   ,txt=>'100 - state + chan'},
                      invMul  =>{calc=>'$val=(100-$val*$in)>0?(100-$val*$in) : 0'       ,txt=>'100 - state * chan'},
                      );
  CUL_HM_UpdtReadBulk($hash,0,"R-logicCombTxt:".$logicComb{$lComb}{txt} 
                             ,"R-logicCombCalc:".$logicComb{$lComb}{calc});
  return "";
}

#+++++++++++++++++ Action Detector ++++++++++++++++++++++++++++++++++++++++++++
# verify that devices are seen in a certain period of time
# It will generate events if no message is seen sourced by the device during
# that period.
# ActionDetector will use the fixed HMid 000000
sub CUL_HM_ActGetCreateHash() {# get ActionDetector - create if necessary
  if (!$modules{CUL_HM}{defptr}{"000000"}){
    CommandDefine(undef,"ActionDetector CUL_HM 000000");
    $attr{ActionDetector}{actCycle} = 600;
    $attr{ActionDetector}{"event-on-change-reading"} = ".*";
  }
  my $actHash = $modules{CUL_HM}{defptr}{"000000"};
  my $actName = $actHash->{NAME} if($actHash);
  my $ac = AttrVal($actName,"actCycle",600);
  if (!$actHash->{helper}{actCycle} ||
      $actHash->{helper}{actCycle} != $ac){
    $actHash->{helper}{actCycle} = $ac;
    RemoveInternalTimer("ActionDetector");
    $actHash->{STATE} = "active";
    InternalTimer(gettimeofday()+$ac,"CUL_HM_ActCheck", "ActionDetector", 0);
  }
  return $actHash;
}
sub CUL_HM_time2sec($) {
  my ($timeout) = @_;
  my ($h,$m) = split(":",$timeout);
  no warnings 'numeric';
  $h = int($h);
  $m = int($m);
  use warnings 'numeric';
  return ((sprintf("%03s:%02d",$h,$m)),((int($h)*60+int($m))*60));
}
sub CUL_HM_ActAdd($$) {# add an HMid to list for activity supervision
  my ($devId,$timeout) = @_; #timeout format [hh]h:mm
  $timeout = 0 if (!$timeout);
  return $devId." is not an HM device - action detection cannot be added"
       if (length($devId) != 6);
  my ($cycleString,undef)=CUL_HM_time2sec($timeout);
  my $devName = CUL_HM_id2Name($devId);
  my $devHash = $defs{$devName};

  $attr{$devName}{actCycle} = $cycleString;
  $attr{$devName}{actStatus}=""; # force trigger
  my $actHash = CUL_HM_ActGetCreateHash();
  $actHash->{helper}{$devId}{start} = TimeNow();
  $actHash->{helper}{peers} = CUL_HM_noDupInString(
                       ($actHash->{helper}{peers}?$actHash->{helper}{peers}:"")
                       .",$devId");
  Log3 $actHash, 3,"Device ".$devName." added to ActionDetector with "
      .$cycleString." time";
  #run ActionDetector
  RemoveInternalTimer("ActionDetector");
  CUL_HM_ActCheck("add");
  return;
}
sub CUL_HM_ActDel($) {# delete HMid for activity supervision
  my ($devId) = @_;
  my $devName = CUL_HM_id2Name($devId);
  CUL_HM_setAttrIfCh($devName,"actStatus","deleted","Activity");#post trigger
  delete $attr{$devName}{actCycle};
  delete $attr{$devName}{actStatus};

  my $actHash = CUL_HM_ActGetCreateHash();
  delete ($actHash->{helper}{$devId});

  my $peerIDs = $actHash->{helper}{peers};
  $peerIDs =~ s/$devId//g if($peerIDs);
  $actHash->{helper}{peers} = CUL_HM_noDupInString($peerIDs);
  Log3 $actHash,3,"Device ".$devName." removed from ActionDetector";
  RemoveInternalTimer("ActionDetector");
  CUL_HM_ActCheck("del");
  return;
}
sub CUL_HM_ActCheck($) {# perform supervision
  my ($call) = @_;
  my $actHash = CUL_HM_ActGetCreateHash();
  my $tod = int(gettimeofday());
  my $actName = $actHash->{NAME};
  my $peerIDs = $actHash->{helper}{peers}?$actHash->{helper}{peers}:"";
  my @event;
  my ($cntUnkn,$cntAliv,$cntDead,$cnt_Off) =(0,0,0,0);
  my $autoTry = CUL_HM_getAttrInt($actName,"actAutoTry",0);
  
  foreach my $devId (split(",",$peerIDs)){
    next if (!$devId);
    my $devName = CUL_HM_id2Name($devId);
    
    if(AttrVal($devName,"ignore",0)){
      delete $actHash->{READINGS}{"status_".$devName};
      next;
    }
    
    if(!$devName || !defined($attr{$devName}{actCycle})){
      CUL_HM_ActDel($devId);
      next;
    }
    my $state;
    my $oldState = AttrVal($devName,"actStatus","unset");
    my (undef,$tSec)=CUL_HM_time2sec($attr{$devName}{actCycle});
    if ($tSec == 0){# detection switched off
      $cnt_Off++; $state = "switchedOff";
    }
    else{
      my $tLast = ReadingsVal($devName,".protLastRcv",0);
      my @t = localtime($tod - $tSec); #time since when a trigger is expected
      my $tSince = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                             $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);

      if (!$tLast                  #cannot determine time
          || $tSince gt $tLast){   #no message received in window
        if ($actHash->{helper}{$devId}{start} lt $tSince){  
          if($autoTry) { #try to send a statusRequest?
            if (!$actHash->{helper}{$devId}{try} || $actHash->{helper}{$devId}{try}<2){
              $actHash->{helper}{$devId}{try} = $actHash->{helper}{$devId}{try}
                                                 ? ($actHash->{helper}{$devId}{try} +1)
                                                 : 1;
              my $cmds = CUL_HM_Set($defs{$devName},$devName,"help");
              if ($cmds =~ m/(statusRequest|getSerial)/){
                # send statusrequest if possible
                CUL_HM_Set($defs{$devName},$devName,
                           ($cmds =~ m/statusRequest/?"statusRequest"
                                                     :"getSerial" ));
                $cntUnkn++; $state = "unknown";
              }
              else{
                $actHash->{helper}{$devId}{try} = 99;
                $cntDead++; $state = "dead";
              }
            }
            else{
              $cntDead++; $state = "dead";
            }
          }
          else{
            $cntDead++; $state = "dead";
          }
        }
        else{
          $cntUnkn++; $state = "unknown";
        }
      }
      else{                         #message in time
        $cntAliv++; $state = "alive";
        delete $actHash->{helper}{$devId}{try};
      }
    }
    if ($oldState ne $state){
      CUL_HM_UpdtReadSingle($defs{$devName},"Activity",$state,1);
      $attr{$devName}{actStatus} = $state;
      Log3 $actHash,4,"Device ".$devName." is ".$state;
    }
    push @event, "status_".$devName.":".$state;
  }
  push @event, "state:"."alive:".$cntAliv
                       ." dead:".$cntDead
                       ." unkn:".$cntUnkn
                       ." off:" .$cnt_Off;

  my $allState = join " ",@event;# search and remove outdated readings
  if ($call eq "ActionDetector"){#delete only in routine call 
    foreach (keys %{$actHash->{READINGS}}){
      delete $actHash->{READINGS}{$_} if ($allState !~ m/$_:/);
    }
  }

  CUL_HM_UpdtReadBulk($actHash,1,@event);

  $actHash->{helper}{actCycle} = AttrVal($actName,"actCycle",600);
  RemoveInternalTimer("ActionDetector");
  InternalTimer(gettimeofday()+$actHash->{helper}{actCycle}
                                      ,"CUL_HM_ActCheck", "ActionDetector", 0);
}
sub CUL_HM_ActInfo() {# print detailed status information
  my $actHash = CUL_HM_ActGetCreateHash();
  my $tod = int(gettimeofday());
  my $peerIDs = $actHash->{helper}{peers}?$actHash->{helper}{peers}:"";
  my @info;
  
  foreach my $devId (split(",",$peerIDs)){
    next if (!$devId);
    my $devName = CUL_HM_id2Name($devId);
    
    next if(!$devName || !defined($attr{$devName}{actCycle}));
    next if(AttrVal($devName,"ignore",0));

    my $state;
    my (undef,$tSec)=CUL_HM_time2sec($attr{$devName}{actCycle});
    if ($state ne "switchedOff"){
      my $tLast = ReadingsVal($devName,".protLastRcv",0);
      $tLast =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/;
      my $x =  $2*30*24*3600 + $3*24*3600 + $4*3600 + $5*60 +$6;
      my @t = localtime($tod - $tSec); #time since when a trigger is expected

      my $y =  $x -
               ((  $t[4]+1)*30*24*3600
                 + $t[3]*24*3600 
                 + $t[2]*3600 
                 + $t[1]*60 
                 + $t[0]);
      my $sign = "next  ";
      if ($y < 0){
        $sign = "late -";
        $y *= -1;
      }
      
      my @c;      
      $c[1] = int($y/3600);$y -= $c[1] * 3600;
      $c[0] = int($y/60)  ;$y -= $c[0] * 60;
      
      $state .= sprintf("%-8s %s %s %3d:%02d:%02d %s"
                              ,ReadingsVal($devName,"Activity","")
                              ,$tLast,$sign,$c[1],$c[0],$y
                              ,$devName);
   }
   else{
     $state = sprintf ("%-8s :%30s : "
                                      ,ReadingsVal($devName,"Activity","")
                                      ,$devName);
   }
   push @info,$state;
  }
  return sprintf ("%-8s %-19s %s %s\n\n","state"
                                              ,"last"
                                              ,"next     h:mm:ss"
                                              ,"name").
         join("\n", sort @info);
}

#+++++++++++++++++ helper +++++++++++++++++++++++++++++++++++++++++++++++++++++
sub CUL_HM_UpdtReadBulk(@) { #update a bunch of readings and trigger the events
  my ($hash,$doTrg,@readings) = @_;
  return if (!@readings);
  if($evtDly && $doTrg){#delay trigger if in parser and trigger ist requested
    push @evtEt,[$hash,1,"$_"] foreach(@readings);
  }
  else{
    readingsBeginUpdate($hash);
    foreach my $rd (CUL_HM_noDup(@readings)){
      next if (!$rd);
      my ($rdName, $rdVal) = split(":",$rd, 2); 
      readingsBulkUpdate($hash,$rdName,
                               ((defined($rdVal) && $rdVal ne "")?$rdVal:"-"));
    }
    readingsEndUpdate($hash,$doTrg);
  }
  return $hash->{NAME};
}
sub CUL_HM_UpdtReadSingle(@) { #update single reading and trigger the event
  my ($hash,$rName,$val,$doTrg) = @_;
  if($evtDly && $doTrg){#delay trigger if in parser and trigger ist requested
    push @evtEt,[$hash,1,"$rName:$val"];
  }
  else{
    readingsSingleUpdate($hash,$rName,$val,$doTrg);
  }
  return $hash->{NAME};
}
sub CUL_HM_setAttrIfCh($$$$) {
  my ($name,$att,$val,$trig) = @_;
  if(AttrVal($name,$att,"") ne $val){
    DoTrigger($name,$trig.":".$val) if($trig);
    $attr{$name}{$att} = $val;
  }
}
sub CUL_HM_noDup(@) {#return list with no duplicates
  my %all;
  return "" if (scalar(@_) == 0);
  $all{$_}=0 foreach (grep {defined $_ && $_ !~ m/^$/} @_);
  delete $all{""}; #remove empties if present
  return (sort keys %all);
}
sub CUL_HM_noDupInString($) {#return string with no duplicates, comma separated
  my ($str) = @_;
  return join ",",CUL_HM_noDup(split ",",$str);
}
sub CUL_HM_storeRssi(@){
  my ($name,$peerName,$val,$mNo) = @_;
  return if (!$val || !defined  $defs{$name});
  my $hash = $defs{$name};
  if (AttrVal($peerName,"subType","") eq "virtual"){
    my $h = InternalVal($name,"IODev","");#CUL_HM_name2IoName($peerName);
    return if (!$h);
    $peerName = $h->{NAME};
  }
  else{
    return if (length($peerName)<3);
  }
  
  if ($peerName =~ m/^at_/){
    if ($hash->{helper}{mRssi}{mNo} ne $mNo){# new message
      delete $hash->{helper}{mRssi};
      $hash->{helper}{mRssi}{mNo} = $mNo;
    }
    
    my ($mVal,$mPn) = ($val,substr($peerName,3));
    if ($mPn =~ m /^rpt_(.*)/){# map repeater to io device, use max rssi
      $mPn = $1;
      $mVal = $hash->{helper}{mRssi}{io}{$mPn} 
            if(   $hash->{helper}{mRssi}{io}{$mPn} 
               && $hash->{helper}{mRssi}{io}{$mPn} > $mVal);
    }
    $mVal +=2 if(CUL_HM_name2IoName($name) eq $mPn);
    $hash->{helper}{mRssi}{io}{$mPn} = $mVal;
  }
  
  $hash->{helper}{rssi}{$peerName}{lst} = $val;
  my $rssiP = $hash->{helper}{rssi}{$peerName};
  $rssiP->{min} = $val if (!$rssiP->{min} || $rssiP->{min} > $val);
  $rssiP->{max} = $val if (!$rssiP->{max} || $rssiP->{max} < $val);
  $rssiP->{cnt} ++;
  if ($rssiP->{cnt} == 1){
    $rssiP->{avg} = $val;
  }
  else{
    $rssiP->{avg} += ($val - $rssiP->{avg}) /$rssiP->{cnt};
  }
  my $rssi;
  foreach (keys %{$rssiP}){
    my $val = $rssiP->{$_}?$rssiP->{$_}:0;
    $rssi .= $_.":".(int($val*100)/100)." ";
  }
  $hash->{"rssi_".$peerName} = $rssi;
  CUL_HM_UpdtReadSingle($hash,"rssi_".$peerName,$val,1) 
        if (AttrVal($name,"rssiLog",undef));
 return ;
}

sub CUL_HM_UpdtCentral($){
  my $name = shift;
  my $id = CUL_HM_name2Id($name);
  return if(!$init_done || length($id) != 6);
  
  foreach (keys %defs){# remove existing IO assignements
    next if (   AttrVal($_,"hmId","")          ne $id 
             && InternalVal($_,"owner_CCU","") ne $name);
    delete $defs{$_}{owner_CCU}; 
  }

  $defs{$name}{assignedIOs} = join(",",devspec2array("hmId=$id"));
  
  foreach my $ioN(split",",AttrVal($name,"IOList","")){# set parameter in IO
    next if (!$defs{$ioN});
    if (  $defs{$ioN}{TYPE} eq "HMLAN"){;
    }
    elsif($defs{$ioN}{TYPE} eq "CUL"){
      CommandAttr(undef, "$ioN rfmode HomeMatic") 
            if (AttrVal($ioN,"rfmode","") ne "HomeMatic");
    }
    else {
      next;
    }
    CommandAttr(undef, "$ioN hmId $id")
            if (AttrVal($ioN,"hmId","") ne $id);
    $defs{$ioN}{owner_CCU} = $name;
  }

  # --- search for peers to CCU and potentially device this channel
  foreach my $ccuBId (CUL_HM_noDup(grep /$id/ ,map{split ",",AttrVal($_,"peerIDs","")}keys %defs)){
    next if (length($ccuBId) !=8);
    # now for each ccu Channel, that ist peered with someone. 
    my $btn = hex(substr($ccuBId,6,2)) + 0;
    next if (!$btn);
    CommandDefine(undef,$name."_Btn$btn CUL_HM $ccuBId")
        if (!$modules{CUL_HM}{defptr}{$ccuBId});
    my $ccuChnName = $modules{CUL_HM}{defptr}{$ccuBId}{NAME};
    foreach my $pn (grep !/^$/,
                    map{$_ if (AttrVal($_,"peerIDs","") =~ m/$ccuBId/)}
                    keys %defs){
      CUL_HM_ID2PeerList ($ccuChnName,unpack('A8',CUL_HM_name2Id($pn)."01"),1); 
    }
  }
  my @ioList = split(",",AttrVal($name,"IOList",""));# prepare array for quick access
  $defs{$name}{helper}{io}{ioList} = \@ioList;
  my $io = AttrVal($name,"IODev","empty");# assign IODev to vccu
  if (AttrVal($name,"IOList","") !~ m/$io/){
    foreach(@ioList){
      if ($defs{$_}){
        $attr{$name}{IODev} = $_;
        last;
      }
    }
  }
  
  CUL_HM_UpdtCentralState($name);
}
sub CUL_HM_UpdtCentralState($){
  my $name = shift;
  return if (!$defs{$name});
  my $state = "";
  my @IOl = split",",AttrVal($name,"IOList","");
  foreach my $e (split",",$defs{$name}{assignedIOs}){
    $state .= "$e:UAS," if (!grep /$e/,@IOl);
  }
  foreach my $ioN (@IOl){
    my $cnd = ReadingsVal($ioN,"cond","");
    if ($cnd){ # covering all HMLAN/USB
      $state .= "$ioN:$cnd,";
    }
    else{ # handling CUL
      my $st = InternalVal($ioN,"STATE","unknown");
      $state .= "$ioN:".($st ne "Initialized"?$st:"ok").",";
    }
    if (AttrVal($ioN,"hmId","") ne $defs{$name}{DEF}){
      Log 1,"CUL_HM correct hmId for assigned IO $ioN";
      $attr{$ioN}{hmId} = $defs{$name}{DEF};
    }
  };
  $state = "IOs_ok" if (!$state);
  $defs{$name}{STATE} = $state;
}
sub CUL_HM_assignIO($){ #check and assign IO
  # assign IO device
  my $hash = shift;
  if (   $hash->{helper}{prt}{sProc} == 1
      && defined $hash->{IODev} ){#don't change while send in process
    return; 
  }
    
  my $ioCCU = $hash->{helper}{io}{vccu};
  if (   $ioCCU
      && defined $defs{$ioCCU} && AttrVal($ioCCU,"model","") eq "CCU-FHEM"
      && ref($defs{$ioCCU}{helper}{io}{ioList}) eq 'ARRAY'){
    my @ioccu = @{$defs{$ioCCU}{helper}{io}{ioList}};
    my @ios = ((sort {$hash->{helper}{mRssi}{io}{$b} <=> 
                    $hash->{helper}{mRssi}{io}{$a} } 
                    grep {defined $hash->{helper}{mRssi}{io}{$_}} @ioccu)
                  ,(grep {!defined $hash->{helper}{mRssi}{io}{$_}} @ioccu));
    unshift @ios,@{$hash->{helper}{io}{prefIO}} if ($hash->{helper}{io}{prefIO});# set prefIO to first choice
    foreach my $iom (@ios){
      if (  !$defs{$iom}
          || $defs{$iom}{STATE} eq "disconnected" 
          || InternalVal($iom,"XmitOpen",1) == 0){# HMLAN/HMUSB?
        next;
      }
      if (   $hash->{IODev} 
          && $hash->{IODev} ne $defs{$iom}
          && $hash->{IODev}->{TYPE}
          && $hash->{IODev}->{TYPE} eq "HMLAN"){#if recent io is HMLAN and we have to remove the device from IO
        IOWrite($hash, "", "remove:".CUL_HM_hash2Id($hash));
      }
      $hash->{IODev} = $defs{$iom};
      return;
    }
  }
  # not assigned thru CCU - try normal
  my $dIo = AttrVal($hash->{NAME},"IODev","");
  if ($defs{$dIo}){
    if($dIo ne $hash->{IODev}->{NAME}){
      $hash->{IODev} = $defs{$dIo};
    }
  }
  else{
    AssignIoPort($hash);#let kernal decide
  }
}


sub CUL_HM_stateUpdatDly($$){#delayed queue of status-request
  my ($name,$time) = @_;
  CUL_HM_unQEntity($name,"qReqStat");#remove requests, wait for me.
  RemoveInternalTimer("sUpdt:$name");
  InternalTimer(gettimeofday()+$time,"CUL_HM_qStateUpdatIfEnab","sUpdt:$name",0);
}
sub CUL_HM_qStateUpdatIfEnab($@){#in:name or id, queue stat-request
  my ($name,$force) = @_;
  $name = substr($name,6) if ($name =~ m/^sUpdt:/);
  $name = CUL_HM_id2Name($name) if ($name =~ m/^[A-F0-9]{6,8}$/i);
  $name =~ s /_chn:..$//;
  return if (  !$defs{$name}                  #device unknown, ignore
             || CUL_HM_Set($defs{$name},$name,"help") !~ m/statusRequest/);
  if ($force || ((CUL_HM_getAttrInt($name,"autoReadReg") & 0x0f) > 3)){
    CUL_HM_qEntity($name,"qReqStat") ;
  }
}
sub CUL_HM_qAutoRead($$){
  my ($name,$lvl) = @_;
  CUL_HM_configUpdate($name);
  return if (!$defs{$name}
             ||$lvl >= (0x07 & CUL_HM_getAttrInt($name,"autoReadReg")));
  CUL_HM_qEntity($name,"qReqConf");
}
sub CUL_HM_unQEntity($$){# remove entity from q
  my ($name,$q) = @_;
  my $devN = CUL_HM_getDeviceName($name);
  return if (AttrVal($devN,"subType","") eq "virtual");
  my $dq = $defs{$devN}{helper}{q};
  RemoveInternalTimer("sUpdt:$name") if ($q eq "qReqStat");#remove delayed
  return if ($dq->{$q} eq "");

  if ($devN eq $name){#all channels included
    $dq->{$q}="";
  }
  else{
    my @chns = split(",",$dq->{$q});
    my $chn = substr(CUL_HM_name2Id($name),6,2);
    @chns = grep !/$chn/,@chns;
    $dq->{$q} = join",",@chns;
  }
  $q = $q."Wu" if (CUL_HM_getRxType($defs{$name}) & 0x1C);
  my $mQ = $modules{CUL_HM}{helper}{$q};
  return if(!$mQ || scalar(@{$mQ}) == 0);
  @{$mQ} = grep !/^$devN$/,@{$mQ} if ($dq->{$q} eq "");
}
sub CUL_HM_qEntity($$){  # add to queue
  my ($name,$q) = @_;
  return if ($modules{CUL_HM}{helper}{hmManualOper});#no autoaction when manual

  my $devN = CUL_HM_getDeviceName($name);
  return if (AttrVal($devN,"subType","") eq "virtual");
  $name =  $devN if ($defs{$devN}{helper}{q}{$q} eq "00"); #already requesting all
  if ($devN eq $name){#config for all device
    $defs{$devN}{helper}{q}{$q}="00";
  }
  else{
    $defs{$devN}{helper}{q}{$q} = CUL_HM_noDupInString(
                                      $defs{$devN}{helper}{q}{$q}
                                      .",".substr(CUL_HM_name2Id($name),6,2));
  }

  $q .= "Wu" if (!(CUL_HM_getRxType($defs{$name}) & 0x03));#normal or wakeup q?
  $q = $modules{CUL_HM}{helper}{$q};
  @{$q} = CUL_HM_noDup(@{$q},$devN);

  my $wT = (@{$modules{CUL_HM}{helper}{qReqStat}})?
                              "1":
                              $modules{CUL_HM}{hmAutoReadScan};
  RemoveInternalTimer("CUL_HM_procQs");
  InternalTimer(gettimeofday()+ $wT,"CUL_HM_procQs","CUL_HM_procQs", 0);
}

sub CUL_HM_procQs($){#process non-wakeup queues
  # --- verify send is possible

  my $mq = $modules{CUL_HM}{helper};
  foreach my $q ("qReqStat","qReqConf"){
    if   (@{$mq->{$q}}){
      my $devN = ${$mq->{$q}}[0];
      CUL_HM_assignIO($defs{$devN}); 
      next  if(!defined $defs{$devN}{IODev}{NAME});
      my $ioName = $defs{$devN}{IODev}{NAME};   

      if (   (   ReadingsVal($ioName,"cond","") =~ m /^(ok|Overload-released|init)$/
              && $q eq "qReqStat")
           ||(   CUL_HM_autoReadReady($ioName)
              && !$defs{$devN}{cmdStack}
              && $q eq "qReqConf")){
        my $dq = $defs{$devN}{helper}{q};
        my @chns = split(",",$dq->{$q});
        my $nOpen = scalar @chns;
        if (@chns > 1){$dq->{$q} = join ",",@chns[1..$nOpen-1];}
        else{          $dq->{$q} = "";
                       @{$mq->{$q}} = grep !/^$devN$/,@{$mq->{$q}};
        }
        my $dId = CUL_HM_name2Id($devN);
        my $eN=($chns[0] && $chns[0]ne "00")?CUL_HM_id2Name($dId.$chns[0]):$devN;
        if ($q eq "qReqConf"){
          $mq->{autoRdActive} = $devN;
          CUL_HM_Set($defs{$eN},$eN,"getConfig");
        }
        else{
           CUL_HM_Set($defs{$eN},$eN,"statusRequest");
        }
      }
      last; # execute only one!
    }
  }

  delete $mq->{autoRdActive}
        if ($mq->{autoRdActive} &&
            $defs{$mq->{autoRdActive}}{helper}{prt}{sProc} != 1);
  my $next;# how long to wait for next timer
  if    (@{$mq->{qReqStat}}){$next = 1}
  elsif (@{$mq->{qReqConf}}){$next = $modules{CUL_HM}{hmAutoReadScan}}
  InternalTimer(gettimeofday()+$next,"CUL_HM_procQs","CUL_HM_procQs",0)
      if ($next);
}
sub CUL_HM_appFromQ($$){#stack commands if pend in WuQ
  my ($name,$reason) = @_;
  my $devN = CUL_HM_getDeviceName($name);
  my $dId = CUL_HM_name2Id($devN);
  my $dq = $defs{$devN}{helper}{q};
  if ($reason eq "cf"){# reason is config. add all since User has control
    foreach my $q ("qReqStat","qReqConf"){
      if ($dq->{$q} ne ""){# need update
        my @eName;
        if ($dq->{$q} eq "00"){
          push @eName,$devN;
        }
        else{
          my @chns = split(",",$dq->{$q});
          push @eName,CUL_HM_id2Name($dId.$_)foreach (@chns);
        }
        $dq->{$q} = "";
        @{$modules{CUL_HM}{helper}{$q."Wu"}} =
                    grep !/^$devN$/,@{$modules{CUL_HM}{helper}{$q."Wu"}};
        foreach my $eN(@eName){
          next if (!$eN);
          CUL_HM_Set($defs{$eN},$eN,"getConfig")     if ($q eq "qReqConf");
          CUL_HM_Set($defs{$eN},$eN,"statusRequest") if ($q eq "qReqStat");
        }
      }
    }
  }
  elsif($reason eq "wu"){#wakeup - just add one step
    my $ioName = $defs{$devN}{IODev}{NAME};
    return if (!CUL_HM_autoReadReady($ioName));# no sufficient performance
    foreach my $q ("qReqStat","qReqConf"){
      if ($dq->{$q} ne ""){# need update
        my @chns = split(",",$dq->{$q});
        my $nOpen = scalar @chns;
        if ($nOpen > 1){$dq->{$q} = join ",",@chns[1..$nOpen-1];}
        else{           $dq->{$q} = "";
                      @{$modules{CUL_HM}{helper}{$q."Wu"}} =
                         grep !/^$devN$/,@{$modules{CUL_HM}{helper}{$q."Wu"}};
        }
        my $eN=($chns[0]ne "00")?CUL_HM_id2Name($dId.$chns[0]):$devN;
        CUL_HM_Set($defs{$eN},$eN,"getConfig")     if ($q eq "qReqConf");
        CUL_HM_Set($defs{$eN},$eN,"statusRequest") if ($q eq "qReqStat");
        return;# Only one per step - very defensive.
      }
    }
  }
}
sub CUL_HM_autoReadReady($){# capacity for autoread available?
  my $ioName = shift;
  my $mHlp = $modules{CUL_HM}{helper};
  if (   $mHlp->{autoRdActive}  # predecessor available
      && $defs{$mHlp->{autoRdActive}}){
    return 0 if ($defs{$mHlp->{autoRdActive}}{helper}{prt}{sProc} == 1); # predecessor still on
  }
  if (   !$ioName
      || ReadingsVal($ioName,"cond","init") !~ m /^(ok|Overload-released|init)$/#default init for CUL
      || ( defined $defs{$ioName}{helper}{q}
          && ($defs{$ioName}{helper}{q}{cap}{sum}/450)>
               AttrVal($ioName,"hmMsgLowLimit",40))){
    return 0;
  }
  return 1;
}

sub CUL_HM_readValIfTO($){# 
  my ($name,$rd,$val) = split(":",shift);#  uncertain:$name:$reading:$value
  readingsSingleUpdate($defs{$name},$rd,$val,1);
}

sub CUL_HM_getAttr($$$){#return attrValue - consider device if empty
  my ($name,$attrName,$default) = @_;
  my $val;
  if($defs{$name}){
    $val = (defined $attr{$name}{$attrName})
                 ? $attr{$name}{$attrName}
                 : undef;
    if (!defined $val){
      my $devN = $defs{$name}{device}?$defs{$name}{device}:$name;
      $val = (defined $attr{$devN}{$attrName})
                 ? $attr{$devN}{$attrName}
                 : $default;
    }
  }
  return $val;
}
sub CUL_HM_getAttrInt($@){#return attrValue as integer
  my ($name,$attrName,$default) = @_;
  $default = 0 if (!defined $default);
  if($defs{$name}){
    my $val = (defined $attr{$name}{$attrName})
                 ?$attr{$name}{$attrName}
                 :"";
    no warnings 'numeric';
    my $devN = $defs{$name}{device}?$defs{$name}{device}:$name;
    $val = int($attr{$devN}{$attrName}?$attr{$devN}{$attrName}:$default)+0
          if($val eq "");
    use warnings 'numeric';
    return substr($val,0,1);
  }
  else{
    return $default;
  }
}

#+++++++++++++++++ external use +++++++++++++++++++++++++++++++++++++++++++++++

sub CUL_HM_peerUsed($) {# are peers expected?
  # return 0: no peers expected 
  #        1: peers expected, list valid 
  #        2: peers expected, list invalid 
  #        3: peers possible (virtuall actor)
  my $name = shift;
  my $hash = $defs{$name};
  return 0 if (!$hash->{helper}{role}{chn});#device has no channels
  return 3 if ($hash->{helper}{role}{vrt});

  my $mId = CUL_HM_getMId($hash);
  my $cNo = hex(substr($hash->{DEF}."01",6,2))."p"; #default to channel 01
  return 0 if (!$mId || !$culHmModel->{$mId});
  foreach my $ls (split ",",$culHmModel->{$mId}{lst}){
    my ($l,$c) = split":",$ls;
    if (  ($l =~ m/^(p|3|4)$/ && !$c )  # 3,4,p without chanspec
        ||($c && $c =~ m/$cNo/       )){
      return (AttrVal($name,"peerIDs","") =~ m/00000000/?1:2);
    }
  }
}
sub CUL_HM_reglUsed($) {# provide data for HMinfo
  my $name = shift;
  my $hash = $defs{$name};
  my ($devId,$chn) =  unpack 'A6A2',$hash->{DEF}."01";
  return undef if (AttrVal(CUL_HM_id2Name($devId),"subType","") eq "virtual");

  my @pNames;
  push @pNames,CUL_HM_peerChName($_,$devId)
             foreach (grep !/00000000/,split(",",AttrVal($name,"peerIDs","")));

  my @lsNo;
  my $mId = CUL_HM_getMId($hash);
  return undef if (!$mId || !$culHmModel->{$mId});
  if ($hash->{helper}{role}{dev}){
    push @lsNo,"0:";
  }
  elsif ($hash->{helper}{role}{chn}){
    foreach my $ls (split ",",$culHmModel->{$mId}{lst}){
      my ($l,$c) = split":",$ls;
      if ($l ne "p"){# ignore peer-only entries
        if ($c){
          my $chNo = hex($chn);
          if   ($c =~ m/($chNo)p/){push @lsNo,"$l:$_" foreach (@pNames);}
          elsif($c =~ m/$chNo/   ){push @lsNo,"$l:";}
        }
        else{
          if ($l == 3 || $l == 4){push @lsNo,"$l:$_" foreach (@pNames);
          }else{                  push @lsNo,"$l:" ;}
        }
      }
    }
  }
  my $pre = (CUL_HM_getAttrInt($name,"expert") == 2)?"":".";

  $_ = $pre."RegL_0".$_ foreach (@lsNo);
  return @lsNo;
}

sub CUL_HM_complConfigTest($){# Q - check register consistancy some time later
  my $name = shift;
  return if ($modules{CUL_HM}{helper}{hmManualOper});#no autoaction when manual
  push @{$modules{CUL_HM}{helper}{confCheckArr}},$name;
  if (scalar @{$modules{CUL_HM}{helper}{confCheckArr}} == 1){
    RemoveInternalTimer("CUL_HM_complConfigTO");
    InternalTimer(gettimeofday()+ 1800,"CUL_HM_complConfigTO","CUL_HM_complConfigTO", 0);
  }
}
sub CUL_HM_complConfigTestRm($){# Q - check register consistancy some time later
  my $name = shift;
  my $devN = CUL_HM_getDeviceName($name);
  return if (AttrVal($devN,"subType","") eq "virtual");
  my $mQ = $modules{CUL_HM}{helper}{confCheckArr};
  @{$mQ} = grep !/^$name$/,@{$mQ};
}
sub CUL_HM_complConfigTO($)  {# now perform consistancy check of register
  my @arr = @{$modules{CUL_HM}{helper}{confCheckArr}};
  @{$modules{CUL_HM}{helper}{confCheckArr}} = ();
  CUL_HM_complConfig($_) foreach (CUL_HM_noDup(@arr));
}
sub CUL_HM_complConfig($;$)  {# read config if enabled and not complete
  my ($name,$dly) = @_;
  return if ($modules{CUL_HM}{helper}{hmManualOper});#no autoaction when manual
  return if ((CUL_HM_getAttrInt($name,"autoReadReg") & 0x07) < 5);
  if (CUL_HM_peerUsed($name) == 2){
    CUL_HM_qAutoRead($name,0) if(!$dly);
    CUL_HM_complConfigTest($name);
    delete $modules{CUL_HM}{helper}{cfgCmpl}{$name};
    Log3 $name,5,"CUL_HM $name queue configRead, peers incomplete";
    return;
  }
  my @regList = CUL_HM_reglUsed($name);
  foreach (@regList){
    if (ReadingsVal($name,$_,"") !~ m /00:00/){
      CUL_HM_qAutoRead($name,0) if(!$dly);
      CUL_HM_complConfigTest($name);
      delete $modules{CUL_HM}{helper}{cfgCmpl}{$name};
      Log3 $name,5,"CUL_HM $name queue configRead, register incomplete";
      last;
    }
  }
  $modules{CUL_HM}{helper}{cfgCmpl}{$name} = 1;#mark config as complete
}
sub CUL_HM_configUpdate($)   {# mark entities with changed data
  my $name = shift;
  @{$modules{CUL_HM}{helper}{confUpdt}} = 
           CUL_HM_noDup(@{$modules{CUL_HM}{helper}{confUpdt}},$name);
}

#+++++++++++++++++ templates ++++++++++++++++++++++++++++++++++++++++++++++++++
sub CUL_HM_tempListTmpl(@) { ##################################################
  # $name is comma separated list of names
  # $template is formated <file>:template - file is optional
  my ($name,$action,$template)=@_; 
  my %dl  = (Sat=>0,Sun=>1,Mon=>2,Tue=>3,Wed=>4,Thu=>5,Fri=>6);
  my %dlf = (1=>{Sat=>0,Sun=>0,Mon=>0,Tue=>0,Wed=>0,Thu=>0,Fri=>0},
             2=>{Sat=>0,Sun=>0,Mon=>0,Tue=>0,Wed=>0,Thu=>0,Fri=>0},
             3=>{Sat=>0,Sun=>0,Mon=>0,Tue=>0,Wed=>0,Thu=>0,Fri=>0});
  return "unused" if ($template =~ m/^(none|0) *$/);
  my $ret = "";
  my @el = split",",$name;
  my ($fName,$tmpl) = split":",$template;
  $tmpl = $name if(!$fName);
  ($fName,$tmpl) = ("tempList.cfg",$fName) if(!defined $tmpl && defined $fName);
  return "file: $fName for $name does not exist"  if (!(-e $fName));
  open(aSave, "$fName") || return("Can't open $fName: $!");
  my $found = 0;
  my @entryFail = ();
  my @exec = ();

  while(<aSave>){
    chomp;
    my $line = $_;
    $line =~ s/\r//g;
    next if($line =~ m/#/);
    if($line =~ m/^entities:/){
      last if ($found != 0);
      $line =~s/.*://;
      foreach my $eN (split(",",$line)){
        $eN =~ s/ //g;
        $found = 1 if ($eN eq $tmpl);
      }
    }

    elsif($found == 1 && $line =~ m/(R_)?(P[123])?(_?._)?tempList[SMFWT].*\>/){
      my $prg = $1 if($line =~ m/P(.)_/);
      $prg = 1 if (!$prg);
      my ($tln,$val) = ($1,$2)if($line =~ m/(.*)>(.*)/);
      $tln =~ s/ //g;
      $tln = "R_".$tln if($tln !~ m/^R_/);
      my $dayTxt = $1 if ($tln =~ m/tempList(...)/);
      if (!defined $dl{$dayTxt}){
        push @entryFail," undefined daycode:$dayTxt";
        next;
      }
      if ($dlf{$prg}{$dayTxt}){
        push @entryFail," duplicate daycode:$dayTxt";        
        next;
      }
      $dlf{$prg}{$dayTxt} = 1;
      my $day = $dl{$dayTxt};
      $tln =~s /tempList/${day}_tempList/ if ($tln !~ m/_[0-6]_/);
      if (AttrVal($name,"model","") =~ m/HM-TC-IT-WM-W/){
        $tln =~ s/^R_/R_P1_/ if ($tln !~ m/^R_P/);# add P1 as default
      }
      else{
        $tln =~ s/^R_P1_/R_/ if ($tln =~ m/^R_P/);# remove P1 default
      }
      $val =~ tr/ +/ /;
      $val =~ s/^ //;
      $val =~ s/ $//;
      @exec = ();
      foreach my $eN(@el){
        if ($action eq "verify"){
          $val = join(" ",split(" ",$val));
          my $nv = ReadingsVal($eN,$tln,"empty");
          $nv = join(" ",split(" ",$nv));
          push @entryFail,$eN." :".$tln." mismatch" if ($val ne $nv);
        }
        elsif($action eq "restore"){
          $val = lc($1)." ".$val if ($tln =~ m/(P.)_._tempList/);
          $tln =~ s/R_(P._)?._//;
          my $x = CUL_HM_Set($defs{$eN},$eN,$tln,"prep",split(" ",$val));
          push @entryFail,$eN." :".$tln." respose:$x" if ($x ne "1");
          push @exec,$eN." ".$tln." exec ".$val;
        }
      }
    }

    $ret = "failed Entries:\n     "   .join("\n     ",@entryFail) if (scalar@entryFail);
  }
  if (!$found){
    $ret .= "$tmpl not found in file $fName";
  }
  else{
    if(CUL_HM_Get($defs{$name},$name,"param","model") ne "HM-TC-IT-WM-W-EU02"){
      delete $dlf{2};
      delete $dlf{3};
    }
    foreach my $p (keys %dlf){
      my @unprg = grep !/^$/,map {$dlf{$p}{$_}?"":$_} keys %{$dlf{$p}};
      my $cnt = scalar @unprg;
      if ($cnt > 0 && $cnt < 7) {$ret .= "\n $name: incomplete template for prog $p days:".join(",",@unprg);}
      elsif ($cnt == 7)         {$ret .= "\n $name: unprogrammed prog $p ";}
      else{
        $ret .= "\n $name: tempList not verified " if (grep {$defs{$name}{READINGS}{$_}{VAL} ne "verified"}
                                                       grep /tempList_State/, 
                                                       keys %{$defs{$name}{READINGS}});
      }
    }
  }
  foreach (@exec){
    my @param = split(" ",$_);
    CUL_HM_Set($defs{$param[0]},@param);
  }
  close(aSave);
  return $ret;
}

1;

=pod
=begin html

  <a name="CUL_HM"></a><h3>CUL_HM</h3>
  <ul>
    Support for eQ-3 HomeMatic devices via the <a href="#CUL">CUL</a> or the <a href="#HMLAN">HMLAN</a>.<br>
    <br>
    <a name="CUL_HMdefine"></a><b>Define</b>
    <ul>
      <code><B>define &lt;name&gt; CUL_HM &lt;6-digit-hex-code|8-digit-hex-code&gt;</B></code>
  
      <br><br>
      Correct device definition is the key for HM environment simple maintenance.
      <br>
  
      Background to define entities:<br>
      HM devices has a 3 byte (6 digit hex value) HMid - which is key for
      addressing. Each device hosts one or more channels. HMid for a channel is
      the device's HMid plus the channel number (1 byte, 2 digit) in hex.
      Channels should be defined for all multi-channel devices. Channel entities
      cannot be defined if the hosting device does not exist<br> Note: FHEM
      mappes channel 1 to the device if it is not defined explicitely. Therefore
      it does not need to be defined for single channel devices.<br>
  
      Note: if a device is deleted all assotiated channels will be removed as
      well. <br> An example for a full definition of a 2 channel switch is given
      below:<br>
  
      <ul><code>
        define livingRoomSwitch CUL_HM 123456<br>
        define LivingroomMainLight CUL_HM 12345601<br>
        define LivingroomBackLight CUL_HM 12345602<br><br></code>
      </ul>
  
      livingRoomSwitch is the device managing communication. This device is
      defined prior to channels to be able to setup references. <br>
      LivingroomMainLight is channel 01 dealing with status of light, channel
      peers and channel assotiated register. If not defined channel 01 is covered
      by the device entity.<br> LivingRoomBackLight is the second 'channel',
      channel 02. Its definition is mandatory to operate this function.<br><br>
  
      Sender specials: HM threats each button of remotes, push buttons and
      similar as channels. It is possible (not necessary) to define a channel per
      button. If all channels are defined access to pairing informatin is
      possible as well as access to channel related register. Furthermore names
      make the traces better readable.<br><br>
  
      define may also be invoked by the <a href="#autocreate">autocreate</a>
      module, together with the necessary subType attribute.
      Usually you issue a <a href="#CULset">hmPairForSec</a> and press the
      corresponding button on the device to be paired, or issue a <a
      href="#CULset">hmPairSerial</a> set command if the device is a receiver
      and you know its serial number. Autocreate will then create a fhem
      device and set all necessary attributes. Without pairing the device
      will not accept messages from fhem. fhem may create the device even if
      the pairing is not successful. Upon a successful pairing you'll see a
      CommandAccepted entry in the details section of the CUL_HM device.<br><br>
  
      If you cannot use autocreate, then you have to specify:<br>
      <ul>
        <li>the &lt;6-digit-hex-code&gt;or HMid+ch &lt;8-digit-hex-code&gt;<br>
            It is the unique, hardcoded device-address and cannot be changed (no,
            you cannot choose it arbitrarily like for FS20 devices). You may
            detect it by inspecting the fhem log.</li>
        <li>the subType attribute<br>
            which is one of switch dimmer blindActuator remote sensor  swi
            pushButton threeStateSensor motionDetector  keyMatic winMatic
            smokeDetector</li>
      </ul>
      Without these attributes fhem won't be able to decode device messages
      appropriately. <br><br>
  
      <b>Notes</b>
      <ul>
        <li>If the interface is a CUL device, the <a href="#rfmode">rfmode </a>
            attribute of the corresponding CUL/CUN device must be set to HomeMatic.
            Note: this mode is BidCos/Homematic only, you will <b>not</b> receive
            FS20/HMS/EM/S300 messages via this device. Previously defined FS20/HMS
            etc devices must be assigned to a different input device (CUL/FHZ/etc).
            </li>
        <li>Currently supported device families: remote, switch, dimmer,
            blindActuator, motionDetector, smokeDetector, threeStateSensor,
            THSensor, winmatic. Special devices: KS550, HM-CC-TC and the KFM100.
            </li>
        <li>Device messages can only be interpreted correctly if the device type is
            known. fhem will extract the device type from a "pairing request"
            message, even if it won't respond to it (see <a
            href="#hmPairSerial">hmPairSerial</a> and <a
            href="#hmPairForSec">hmPairForSec</a> to enable pairing).
            As an alternative, set the correct subType and model attributes, for a
            list of possible subType values see "attr hmdevice ?".</li>
        <a name="HMAES"></a>
        <li>The so called "AES-Encryption" is in reality a signing request: if it is
            enabled, an actor device will only execute a received command, if a
            correct answer to a request generated by the actor is received.  This
            means:
            <ul>
              <li>Reaction to commands is noticably slower, as 3 messages are sent
                  instead of one before the action is processed by the actor.</li>
              <li>Every command and its final ack from the device is sent in clear,
                  so an outside observer will know the status of each device.</li>
              <li>The firmware implementation is buggy: the "toggle" event is executed
                  <b>before</b> the answer for the signing request is received, at
                  least by some switches (HM-LC-Sw1-Pl and HM-LC-SW2-PB-FM).</li>
              <li>The <a href="#HMLAN">HMLAN</a> configurator will answer signing
                  requests by itself, and if it is configured with the 3-byte address
                  of a foreign CCU which is still configurerd with the default
                  password, it is able to answer signing requests correctly.</li>
              <li>AES-Encryption is not useable with a CUL device as the interface,
                  but it is supported with a HMLAN. Due to the issues above I do not
                  recommend using Homematic encryption at all.</li>
            </ul>
        </li>
      </ul>
    </ul><br>
    <a name="CUL_HMset"></a><b>Set</b>
    <ul>
      Note: devices which are normally send-only (remote/sensor/etc) must be set
      into pairing/learning mode in order to receive the following commands.
      <br><br>
  
      Universal commands (available to most hm devices):
      <ul>
        <li><B>clear &lt;[rssi|readings|register|msgEvents|attack|all]&gt;</B><a name="CUL_HMclear"></a><br>
          A set of variables can be removed.<br>
          <ul>
            readings: all readings will be deleted. Any new reading will be added usual. May be used to eliminate old data<br>
            register: all captured register-readings in FHEM will be removed. This has NO impact to the values in the device.<br>
            msgEvents:  all message event counter will be removed. Also commandstack will be cleared. <br>
            rssi:  collected rssi values will be cleared. <br>
            attack:  information regarding an attack will be removed. <br>
            all:  all of the above. <br>
          </ul>
        </li>
        <li><B>getConfig</B><a name="CUL_HMgetConfig"></a><br>
          Will read major configuration items stored in the HM device. Executed
          on a channel it will read pair Inforamtion, List0, List1 and List3 of
          the 1st internal peer. Furthermore the peerlist will be retrieved for
          teh given channel. If executed on a device the command will get the
          above info or all assotated channels. Not included will be the
          configuration for additional peers.  <br> The command is a shortcut
          for a selection of other commands.
        </li>
        <li><B>getRegRaw [List0|List1|List2|List3|List4|List5|List6]&lt;peerChannel&gt; </B><a name="CUL_HMgetRegRaw"></a><br>
        
            Read registerset in raw format. Description of the registers is beyond
            the scope of this documentation.<br>
        
            Registers are structured in so called lists each containing a set of
            registers.<br>
        
            List0: device-level settings e.g. CUL-pairing or dimmer thermal limit
            settings.<br>
        
            List1: per channel settings e.g. time to drive the blind up and
            down.<br>
        
            List3: per 'link' settings - means per peer-channel. This is a lot of
            data!. It controlls actions taken upon receive of a trigger from the
            peer.<br>
        
           List4: settings for channel (button) of a remote<br><br>
        
            &lt;PeerChannel&gt; paired HMid+ch, i.e. 4 byte (8 digit) value like
            '12345601'. It is mendatory for List 3 and 4 and can be left out for
            List 0 and 1. <br>
        
           'all' can be used to get data of each paired link of the channel. <br>
        
           'selfxx' can be used to address data for internal channels (associated
           with the build-in switches if any). xx is the number of the channel in
           decimal.<br>
        
           Note1: execution depends on the entity. If List1 is requested on a
           device rather then a channel the command will retrieve List1 for all
           channels assotiated. List3 with peerChannel = all will get all link
           for all channel if executed on a device.<br>
        
           Note2: for 'sender' see <a href="#CUL_HMremote">remote</a> <br>
        
           Note3: the information retrieval may take a while - especially for
           devices with a lot of channels and links. It may be necessary to
           refresh the web interface manually to view the results <br>
        
           Note4: the direct buttons on a HM device are hidden by default.
           Nevertheless those are implemented as links as well. To get access to
           the 'internal links' it is necessary to issue <br>
           'set &lt;name&gt; <a href="#CUL_HMregSet">regSet</a> intKeyVisib visib'<br>
           or<br>
           'set &lt;name&gt; <a href="#CUL_HMregBulk">regBulk</a> RegL_0: 2:81'<br>
        
           Reset it by replacing '81' with '01'<br> example:<br>
        
           <ul><code>
             set mydimmer getRegRaw List1<br>
             set mydimmer getRegRaw List3 all <br>
           </code></ul>
         </li>
        <li><B>getSerial</B><a name="CUL_HMgetSerial"></a><br>
          Read serial number from device and write it to attribute serialNr.
        </li>
        <li><B>inhibit [on|off]</B><br>
          Block / unblock all changes to the actor channel, i.e. actor state is frozen
          until inhibit is set off again. Inhibit can be executed on any actor channel
          but obviously not on sensors - would not make any sense.<br>
          Practically it can be used to suspend any notifies as well as peered channel action
          temporarily without the need to delete them. <br>
          Examples:
          <ul><code>
            # Block operation<br>
            set keymatic inhibit on <br><br>
          </ul></code>
         </li>
        
        <li><B>pair</B><a name="CUL_HMpair"></a><br>
          Pair the device with a known serialNumber (e.g. after a device reset)
          to FHEM Central unit. FHEM Central is usualy represented by CUL/CUNO,
          HMLAN,...
          If paired, devices will report status information to
          FHEM. If not paired, the device won't respond to some requests, and
          certain status information is also not reported.  Paring is on device
          level. Channels cannot be paired to central separate from the device.
          See also <a href="#CUL_HMgetpair">getPair</a>  and
          <a href="#CUL_HMunpair">unpair</a>.<br>
          Don't confuse pair (to a central) with peer (channel to channel) with
          <a href="#CUL_HMpeerChan">peerChan</a>.<br>
        </li>
        <li><B>peerBulk</B> &lt;peerch1,peerch2,...&gt; [set|unset]<a name="CUL_HMpeerBulk"></a><br>
          peerBulk will add peer channels to the channel. All peers in the list will be added. <br>
          with unset option the peers in the list will be subtracted from the device's peerList.<br>
          peering sets the configuration of this link to its defaults. As peers are not
          added in pairs default will be as defined for 'single' by HM for this device. <br>
          More suffisticated funktionality is provided by
          <a href="#CUL_HMpeerChan">peerChan</a>.<br>
          peerBulk will not delete existing peers, just handle the given peerlist.
          Other already installed peers will not be touched.<br>
          peerBulk may be used to remove peers using <B>unset</B> option while default ist set.<br>
        
          Main purpose of this command is to re-store data to a device.
          It is recommended to restore register configuration utilising
          <a href="#CUL_HMregBulk">regBulk</a> subsequent. <br>
          Example:<br>
          <ul><code>
            set myChannel peerBulk 12345601,<br>
            set myChannel peerBulk self01,self02,FB_Btn_04,FB_Btn_03,<br>
            set myChannel peerBulk 12345601 unset # remove peer 123456 channel 01<br>
          </code></ul>
        </li>
        <li><B>regBulk  &lt;reg List&gt;:&lt;peer&gt; &lt;addr1:data1&gt; &lt;addr2:data2&gt;...</B><a name="CUL_HMregBulk"></a><br>
          This command will replace the former regRaw. It allows to set register
          in raw format. Its main purpose is to restore a complete register list
          to values secured before. <br>
          Values may be read by <a href="#CUL_HMgetConfig">getConfig</a>. The
          resulting readings can be used directly for this command.<br>
          &lt;reg List&gt; is the list data should be written to. Format could be
          '00', 'RegL_00', '01'...<br>
          &lt;peer&gt; is an optional adder in case the list requires a peer.
          The peer can be given as channel name or the 4 byte (8 chars) HM
          channel ID.<br>
          &lt;addr1:data1&gt; is the list of register to be written in hex
          format.<br>
          Example:<br>
          <ul><code>
            set myChannel regBulk RegL_00: 02:01 0A:17 0B:43 0C:BF 15:FF 00:00<br>
            RegL_03:FB_Btn_07
           01:00 02:00 03:00 04:32 05:64 06:00 07:FF 08:00 09:FF 0A:01 0B:44 0C:54 0D:93 0E:00 0F:00 11:C8 12:00 13:00 14:00 15:00 16:00 17:00 18:00 19:00 1A:00 1B:00 1C:00 1D:FF 1E:93 1F:00 81:00 82:00 83:00 84:32 85:64 86:00 87:FF 88:00 89:FF 8A:21 8B:44 8C:54 8D:93 8E:00 8F:00 91:C8 92:00 93:00 94:00 95:00 96:00 97:00 98:00 99:00 9A:00 9B:00 9C:00 9D:05 9E:93 9F:00 00:00<br>
            set myblind regBulk 01 0B:10<br>
            set myblind regBulk 01 0C:00<br>
          </code></ul>
          myblind will set the max drive time up for a blind actor to 25,6sec
        </li>
        <li><B>regSet [prep|exec] &lt;regName&gt; &lt;value&gt; &lt;peerChannel&gt;</B><a name="CUL_HMregSet"></a><br>
          For some major register a readable version is implemented supporting
          register names &lt;regName&gt; and value conversionsing. Only a subset
          of register can be supproted.<br>
          Optional parameter [prep|exec] allowes to pack the messages and therefore greatly
          improve data transmission.
          Usage is to send the commands with paramenter "prep". The data will be accumulated for send.
          The last command must have the parameter "exec" in order to transmitt the information.<br>
        
          &lt;value&gt; is the data in human readable manner that will be written
          to the register.<br>
          &lt;peerChannel&gt; is required if this register is defined on a per
          'peerChan' base. It can be set to '0' other wise.See <a
          href="#CUL_HMgetRegRaw">getRegRaw</a>  for full description<br>
          Supported register for a device can be explored using<br>
            <ul><code>set regSet ? 0 0</code></ul>
          Condensed register description will be printed
          using<br>
          <ul><code>set regSet &lt;regname&gt; ? 0</code></ul>
        </li>
        <li><B>reset</B><a name="CUL_HMreset"></a><br>
          Factory reset the device. You need to pair it again to use it with
          fhem.
        </li>
        <li><B>sign [on|off]</B><a name="CUL_HMsign"></a><br>
          Activate or deactivate signing (also called AES encryption, see the <a
          href="#HMAES">note</a> above). Warning: if the device is attached via
          a CUL, you won't be able to switch it (or deactivate signing) from
          fhem before you reset the device directly.
        </li>
        <li><B>statusRequest</B><a name="CUL_HMstatusRequest"></a><br>
          Update device status. For multichannel devices it should be issued on
          an per channel base
        </li>
        <li><B>unpair</B><a name="CUL_HMunpair"></a><br>
          "Unpair" the device, i.e. make it available to pair with other master
          devices. See <a href="#CUL_HMpair">pair</a> for description.</li>
        <li><B>virtual &lt;number of buttons&gt;</B><a name="CUL_HMvirtual"></a><br>
          configures a defined curcuit as virtual remote controll.  Then number
          of button being added is 1 to 255. If the command is issued a second
          time for the same entity additional buttons will be added. <br>
          Example for usage:
          <ul><code>
            define vRemote CUL_HM 100000  # the selected HMid must not be in use<br>
            set vRemote virtual 20        # define 20 button remote controll<br>
            set vRemote_Btn4 peerChan 0 &lt;actorchannel&gt;  # peers Button 4 and 5 to the given channel<br>
            set vRemote_Btn4 press<br>
            set vRemote_Btn5 press long<br>
          </code></ul>
          see also <a href="#CUL_HMpress">press</a>
        </li>
      </ul>
  
      <br>
      <B>subType dependent commands:</B>
      <ul>
        <br>
        <li>switch
          <ul>
            <li><B>on</B> <a name="CUL_HMon"> </a> - set level to 100%</li>
            <li><B>off</B><a name="CUL_HMoff"></a> - set level to 0%</li>
            <li><B>on-for-timer &lt;sec&gt;</B><a name="CUL_HMonForTimer"></a> -
              set the switch on for the given seconds [0-85825945].<br> Note:
              off-for-timer like FS20 is not supported. It may to be programmed
              thru channel register.</li>
            <li><B>on-till &lt;time&gt;</B><a name="CUL_HMonTill"></a> - set the switch on for the given end time.<br>
              <ul><code>set &lt;name&gt; on-till 20:32:10<br></code></ul>
              Currently a max of 24h is supported with endtime.<br>
            </li>
            <li><B>press &lt;[short|long]&gt; &lt;[on|off|&lt;peer&gt;]&gt; &lt;btnNo&gt;</B><a name="CUL_HMpress"></a><br>
                simulate a press of the local button or direct connected switch of the actor.<br>
                <B>[short|long]</B> select simulation of short or long press of the button.
                                    Parameter is optional, short is default<br>
                <B>[on|off|&lt;peer&gt;]</B> is relevant for devices with direct buttons per channel (blind or dimmer).
                Those are available for dimmer and blind-actor, usually not for switches<br>
                <B>&lt;peer&gt;</B> allows to stimulate button-press of any peer of the actor. 
                                    i.e. if the actor is peered to any remote, virtual or io (HMLAN/CUL) 
                                    press can trigger the action defined. <br>              
                <B>[noBurst]</B> relevant for virtual only <br>
                It will cause the command being added to the command queue of the peer. <B>No</B> burst is
                issued subsequent thus the command is pending until the peer wakes up. It therefore 
                <B>delays the button-press</B>, but will cause less traffic and performance cost. <br>
                <B>Example:</B>
                <code> 
                   set actor press # trigger short of internal peer self assotiated to the channel<br>
                   set actor press long # trigger long of internal peer self assotiated to the channel<br>
                   set actor press on # trigger short of internal peer self related to 'on'<br>
                   set actor press long off # trigger long of internal peer self related to 'of'<br>
                   set actor press long FB_Btn01 # trigger long peer FB button 01<br>
                   set actor press long FB_chn:8 # trigger long peer FB button 08<br>
                   set actor press self01 # trigger short of internal peer 01<br>
                   set actor press fhem02 # trigger short of FHEM channel 2<br>
                </code>
            </li>
            <li><B>toggle</B><a name="CUL_HMtoggle"></a> - toggle the Actor. It will switch from any current
                 level to off or from off to 100%</li>
          </ul>
          <br>
        </li>
        <li>dimmer, blindActuator<br>
           Dimmer may support virtual channels. Those are autocrated if applicable. Usually there are 2 virtual channels
           in addition to the primary channel. Virtual dimmer channels are inactive by default but can be used in
           in parallel to the primay channel to control light. <br>
           Virtual channels have default naming SW&lt;channel&gt;_V&lt;no&gt;. e.g. Dimmer_SW1_V1 and Dimmer_SW1_V2.<br>
           Dimmer virtual channels are completely different from FHEM virtual buttons and actors but
           are part of the HM device. Documentation and capabilities for virtual channels is out of scope.<br>
           <ul>
             <li><B>0 - 100 [on-time] [ramp-time]</B><br>
                 set the actuator to the given value (in percent)
                 with a resolution of 0.5.<br>
                 Optional for dimmer on-time and ramp time can be choosen, both in seconds with 0.1s granularity.<br>
                 On-time is analog "on-for-timer".<br>
                 Ramp-time default is 2.5s, 0 means instantanous<br>
             </li>
             <li><B><a href="#CUL_HMon">on</a></B></li>
             <li><B><a href="#CUL_HMoff">off</a></B></li>
             <li><B><a href="#CUL_HMpress">press &lt;[short|long]&gt;&lt;[on|off]&gt;</a></B></li>
             <li><B><a href="#CUL_HMtoggle">toggle</a></B></li>
             <li><B>toggleDir</B><a name="CUL_HMtoggleDir"></a> - toggled drive direction between up/stop/down/stop</li>
             <li><B><a href="#CUL_HMonForTimer">on-for-timer &lt;sec&gt;</a></B> - Dimmer only! <br></li>
             <li><B><a href="#CUL_HMonTill">on-till &lt;time&gt;</a></B> - Dimmer only! <br></li>
             <li><B>stop</B> - stop motion (blind) or dim ramp</li>
             <li><B>pct &lt;level&gt [&lt;ontime&gt] [&lt;ramptime&gt]</B> - set actor to a desired <B>absolut level</B>.<br>
                    Optional ontime and ramptime could be given for dimmer.<br>
                    ontime may be time in seconds. It may also be entered as end-time in format hh:mm:ss
             </li>
             <li><B>up [changeValue] [&lt;ontime&gt] [&lt;ramptime&gt]</B> dim up one step</li>
             <li><B>down [changeValue] [&lt;ontime&gt] [&lt;ramptime&gt]</B> dim up one step<br>
                 changeValue is optional an gives the level to be changed up or down in percent. Granularity is 0.5%, default is 10%. <br>
                 ontime is optional an gives the duration of the level to be kept. '0' means forever and is default.<br>
                 ramptime is optional an defines the change speed to reach the new level. It is meaningful only for dimmer.
             <br></li>
           </ul>
          <br>
        </li>
        <li>remotes, pushButton<a name="CUL_HMremote"></a><br>
             This class of devices does not react on requests unless they are put
             to learn mode. FHEM obeys this behavior by stacking all requests until
             learn mode is detected. Manual interaction of the user is necessary to
             activate learn mode. Whether commands are pending is reported on
             device level with parameter 'protCmdPend'.
        </li>
        <ul>
          <li><B>peerIODev [IO] &lt;btn_no&gt; [<u>set</u>|unset]</B><a name="CUL_HMpeerIODev"></a><br>
               The command is similar to <B><a href="#CUL_HMpeerChan">peerChan</a></B>. 
               While peerChan
               is executed on a remote and peers any remote to any actor channel peerIODev is 
               executed on an actor channel and peer this to an channel of an FHEM IO device.<br>
               An IO device according to eQ3 supports up to 50 virtual buttons. Those
               will be peered/unpeerd to the actor. <a href="CUL_HMpress">press</a> can be
               used to stimulate the related actions as defined in the actor register.
            <li><B>peerChan &lt;btn_no&gt; &lt;actChan&gt; [single|<u>dual</u>|reverse][<u>set</u>|unset] [<u>both</u>|actor|remote]</B>
                <a name="CUL_HMpeerChan"></a><br>
            
                 peerChan will establish a connection between a sender- <B>channel</B> and
                 an actuator-<B>channel</B> called link in HM nomenclatur. Peering must not be
                 confused with pairing.<br>
                 <B>Pairing</B> refers to assign a <B>device</B> to the central.<br>
                 <B>Peering</B> refers to virtally connect two <B>channels</B>.<br>
                 Peering allowes direkt interaction between sender and aktor without
                 the necessity of a CCU<br>
                 Peering a sender-channel causes the sender to expect an ack from -each-
                 of its peers after sending a trigger. It will give positive feedback (e.g. LED green)
                 only if all peers acknowledged.<br>
                 Peering an aktor-channel will setup a parameter set which defines the action to be
                 taken once a trigger from -this- peer arrived. In other words an aktor will <br>
                 - process trigger from peers only<br>
                 - define the action to be taken dedicated for each peer's trigger<br>
                 An actor channel will setup a default action upon peering - which is actor dependant.
                 It may also depend whether one or 2 buttons are peered <B>in one command</B>.
                 A swich may setup oen button for 'on' and the other for 'off' if 2 button are
                 peered. If only one button is peered the funktion will likely be 'toggle'.<br>
                 The funtion can be modified by programming the register (aktor dependant).<br>
            
                 Even though the command is executed on a remote or push-button it will
                 as well take effect on the actuator directly. Both sides' peering is
                 virtually independant and has different impact on sender and receiver
                 side.<br>
            
                 Peering of one actuator-channel to multiple sender-channel as
                 well as one sender-channel to multiple Actuator-channel is
                 possible.<br>
            
                 &lt;actChan&gt; is the actuator-channel to be peered.<br>
            
                 &lt;btn_no&gt; is the sender-channel (button) to be peered. If
                 'single' is choosen buttons are counted from 1. For 'dual' btn_no is
                 the number of the Button-pair to be used. I.e. '3' in dual is the
                 3rd button pair correcponding to button 5 and 6 in single mode.<br>
            
                 If the command is executed on a channel the btn_no is ignored.
                 It needs to be set, should be 0<br>
            
                 [single|dual]: this mode impacts the default behavior of the
                 Actuator upon using this button. E.g. a dimmer can be learned to a
                 single button or to a button pair. <br>
                 Defaults to dual.<br>
            
                 'dual' (default) Button pairs two buttons to one actuator. With a
                 dimmer this means one button for dim-up and one for dim-down. <br>
            
                 'reverse' identical to dual - but button order is reverse.<br>
            
                 'single' uses only one button of the sender. It is useful for e.g. for
                 simple switch actuator to toggle on/off. Nevertheless also dimmer can
                 be learned to only one button. <br>
            
                 [set|unset]: selects either enter a peering or remove it.<br>
                 Defaults to set.<br>
                 'set'   will setup peering for the channels<br>
                 'unset' will remove the peering for the channels<br>
            
                 [actor|remote|both] limits the execution to only actor or only remote.
                 This gives the user the option to redo the peering on the remote
                 channel while the settings in the actor will not be removed.<br>
                 Defaults to both.<br>
            
                 Example:
                 <ul><code>
                   set myRemote peerChan 2 mySwActChn single set       #peer second button to an actuator channel<br>
                   set myRmtBtn peerChan 0 mySwActChn single set       #myRmtBtn is a button of the remote. '0' is not processed here<br>
                   set myRemote peerChan 2 mySwActChn dual set         #peer button 3 and 4<br>
                   set myRemote peerChan 3 mySwActChn dual unset       #remove peering for button 5 and 6<br>
                   set myRemote peerChan 3 mySwActChn dual unset aktor #remove peering for button 5 and 6 in actor only<br>
                   set myRemote peerChan 3 mySwActChn dual set remote  #peer button 5 and 6 on remote only. Link settings il mySwActChn will be maintained<br>
                 </code></ul>
            </li>
          </li>
        </ul>
        <li>virtual<a name="CUL_HMvirtual"></a><br>
           <ul>
             <li><B><a href="#CUL_HMpeerChan">peerChan</a></B> see remote</li>
             <li><B><a name="CUL_HMpress"></a>press [long|short] [&lt;peer&gt;] [&lt;repCount&gt;] [&lt;repDelay&gt;] </B>
               <ul>
                 simulates button press for an actor from a peered sensor.
                 will be sent of type "long".
                 <li>[long|short] defines whether long or short press shall be simulated. Defaults to short</li>
                 <li>[&lt;peer&gt;] define which peer's trigger shall be simulated.Defaults to self(channelNo).</li>
                 <li>[&lt;repCount&gt;] Valid for long press only. How long shall the button be pressed? Number of repetition of the messages is defined. Defaults to 1</li>
                 <li>[&lt;repDelay&gt;] Valid for long press only. defines wait time between the single messages. </li>
               </ul>
             </li>
             <li><B>virtTemp &lt;[off -10..50]&gt;<a name="CUL_HMvirtTemp"></a></B>
               simulates a thermostat. If peered to a device it periodically sends the
               temperature until "off" is given. See also <a href="#CUL_HMvirtHum">virtHum</a><br>
             </li>
             <li><B>virtHum &lt;[off -10..50]&gt;<a name="CUL_HMvirtHum"></a></B>
               simulates the humidity part of a thermostat. If peered to a device it periodically sends 
               the temperature and humidity until both are "off". See also <a href="#CUL_HMvirtTemp">virtTemp</a><br>
             </li>
             <li><B>valvePos &lt;[off 0..100]&gt;<a name="CUL_HMvalvePos"></a></B>
               stimulates a VD<br>
             </li>
           </ul>
        </li>
        <li>smokeDetector<br>
          Note: All these commands work right now only if you have more then one
          smoekDetector, and you peered them to form a group. For issuing the
          commands you have to use the master of this group, and currently you
          have to guess which of the detectors is the master.<br>
          smokeDetector can be setup to teams using
          <a href="#CUL_HMpeerChan">peerChan</a>. You need to peer all
          team-members to the master. Don't forget to also peerChan the master
          itself to the team - i.e. peer it to itself! doing that you have full
          controll over the team and don't need to guess.<br>
          <ul>
            <li><B>teamCall</B> - execute a network test to all team members</li>
            <li><B>alarmOn</B> - initiate an alarm</li>
            <li><B>alarmOff</B> - switch off the alarm</li>
          </ul>
        </li>
        <li>4Dis (HM-PB-4DIS-WM)
          <ul>
            <li><B>text &lt;btn_no&gt; [on|off] &lt;text1&gt; &lt;text2&gt;</B><br>
              Set the text on the display of the device. To this purpose issue
              this set command first (or a number of them), and then choose from
              the teach-in menu of the 4Dis the "Central" to transmit the data.<br>
              If used on a channel btn_no and on|off must not be given but only pure text.<br>
              \_ will be replaced by blank character.<br>
              Example:
              <ul><code>
                set 4Dis text 1 on On Lamp<br>
                set 4Dis text 1 off Kitchen Off<br>
                <br>
                set 4Dis_chn4 text Kitchen Off<br>
              </code></ul>
            </li>
          </ul>
        <br></li>
        <li>Climate-Control (HM-CC-TC)
          <ul>
            <li><B>desired-temp &lt;temp&gt;</B><br>
              Set different temperatures. &lt;temp&gt; must be between 6 and 30
              Celsius, and precision is half a degree.</li>
            <li><B>tempListSat [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListSun [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListMon [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListTue [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListThu [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListWed [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListFri [prep|exec] HH:MM temp ... 24:00 temp</B><br>
              Specify a list of temperature intervals. Up to 24 intervals can be
              specified for each week day, the resolution is 10 Minutes. The
              last time spec must always be 24:00.<br>
              Example: until 6:00 temperature shall be 19, from then until 23:00 temperature shall be
              22.5, thereafter until midnight, 19 degrees celsius is desired.<br>
              <code> set th tempListSat 06:00 19 23:00 22.5 24:00 19<br></code>
            </li>
            <br>
            <li><B>tempListTmpl   =>"[verify|restore] [[ &lt;file&gt; :]templateName] ...</B><br>
              The tempList for one or more devices can be stored in a file. User can compare the
              tempList in the file with the data read from the device. <br>
              Restore will write the tempList to the device.<br>
              Default opeartion is verify.<br>
              Default file is tempList.cfg.<br>
              Default templateName is the name of the actor<br>
              Default for file and templateName can be set with attribut <B>tempListTmpl</B><br>
              Example for templist file. room1 and room2 are the names of the template: <br>
              <code>entities:room1
                 tempListSat>08:00 16.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListSun>08:00 16.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListMon>07:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListTue>07:00 16.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 15.0
                 tempListWed>07:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListThu>07:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListFri>07:00 16.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
              entities:room2
                 tempListSat>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListSun>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListMon>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListTue>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 15.0
                 tempListWed>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListThu>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListFri>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
              </code>
            </li>
            <li><B>partyMode &lt;HH:MM&gt;&lt;durationDays&gt;</B><br>
              set control mode to party and device ending time. Add the time it ends
              and the <b>number of days</b> it shall last. If it shall end next day '1'
              must be entered<br></li>
            <li><B>sysTime</B><br>
                set time in climate channel to system time</li>
          </ul><br>
        </li>
        <li>Climate-Control (HM-CC-RT-DN|HM-CC-RT-DN-BoM)
          <ul>
            <li><B>fwUpdate &lt;filename&gt; [&lt;waitTime&gt;] </B><br>
                update Fw of the device. User must provide the appropriate file. 
                waitTime can be given optional. In case the device needs to be set to 
                FW update mode manually this is the time the system will wait. </li>
            <li><B>controlMode &lt;auto|boost|day|night&gt;</B><br></li>
            <li><B>controlManu &lt;temp&gt;</B><br></li>
            <li><B>controlParty &lt;temp&gt;&lt;startDate&gt;&lt;startTime&gt;&lt;endDate&gt;&lt;endTime&gt;</B><br>
                set control mode to party, define temp and timeframe.<br>
                example:<br>
                <code>set controlParty 15 03.8.13 20:30 5.8.13 11:30</code></li>
            <li><B>sysTime</B><br>
                set time in climate channel to system time</li>
            <li><B>desired-temp &lt;temp&gt;</B><br>
                Set different temperatures. &lt;temp&gt; must be between 6 and 30
                Celsius, and precision is half a degree.</li>
            <li><B>tempListSat [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListSun [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListMon [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListTue [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListThu [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListWed [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListFri [prep|exec] HH:MM temp ... 24:00 temp</B><br>
                Specify a list of temperature intervals. Up to 24 intervals can be
                specified for each week day, the resolution is 10 Minutes. The
                last time spec must always be 24:00.<br>
                Optional parameter [prep|exec] allowes to pack the messages and therefore greatly
                improve data transmission. This is especially helpful if device is operated in wakeup mode.
                Usage is to send the commands with paramenter "prep". The data will be accumulated for send.
                The last command must have the parameter "exec" in order to transmitt the information.<br>
                Example: until 6:00 temperature shall be 19, from then until 23:00 temperature shall be
                22.5, thereafter until midnight, 19 degrees celsius is desired.<br>
                <code> set th tempListSat 06:00 19 23:00 22.5 24:00 19<br></code>
                <br>
                <code> set th tempListSat prep 06:00 19 23:00 22.5 24:00 19<br>
                       set th tempListSun prep 06:00 19 23:00 22.5 24:00 19<br>
                       set th tempListMon prep 06:00 19 23:00 22.5 24:00 19<br>
                       set th tempListTue exec 06:00 19 23:00 22.5 24:00 19<br></code>
            </li>
          </ul><br>
        </li>
        <li>OutputUnit (HM-OU-LED16)
          <ul>
            <li><B>led [off|red|green|yellow]</B><br>
              switches the LED of the channel to the color. If the command is
              executed on a device it will set all LEDs to the specified
              color.<br>
              For Expert all LEDs can be set individual by providing a 8-digit hex number to the device.<br></li>
            <li><B>ilum &lt;brightness&gt;&lt;duration&gt; </B><br>
              &lt;brightness&gt; [0-15] of backlight.<br>
              &lt;duration&gt; [0-127] in sec. 0 is permanent 'on'.<br></li>
          </ul><br>
        </li>
        <li>OutputUnit (HM-OU-CFM-PL)
          <ul>
            <li><B>led &lt;color&gt;[,&lt;color&gt;..] [&lt;repeat&gt..]</B><br>
              Possible colors are [redL|greenL|yellowL|redS|greenS|yellowS|pause]. A
              sequence of colors can be given separating the color entries by ','.
              White spaces must not be used in the list. 'S' indicates short and
              'L' long ilumination. <br>
              <b>repeat</b> defines how often the sequence shall be executed. Defaults to 1.<br>
            </li>
            <li><B>playTone &lt;MP3No&gt[,&lt;MP3No&gt..] [&lt;repeat&gt..]</B><br>
              Play a series of tones. List is to be entered separated by ','. White
              spaces must not be used in the list.<br>
              <b>replay</b> can be entered to repeat the last sound played once more.<br>
              <b>repeat</b> defines how often the sequence shall be played. Defaults to 1.<br>
              Example:
              <ul><code>
                 # "hello" in display, symb bulb on, backlight, beep<br>
                 set cfm_Mp3 playTone 3  # MP3 title 3 once<br>
                 set cfm_Mp3 playTone 3 3 # MP3 title 3  3 times<br>
                 set cfm_Mp3 playTone 3,6,8,3,4 # MP3 title list 3,6,8,3,4 once<br>
                 set cfm_Mp3 playTone 3,6,8,3,4 255# MP3 title list 3,6,8,3,4 255 times<br>
                 set cfm_Mp3 playTone replay # repeat last sequence<br>
                 <br>
                 set cfm_Led led redL 4 # led red blink 3 times long<br>
                 set cfm_Led led redS,redS,redS,redL,redL,redL,redS,redS,redS 255 # SOS 255 times<br>
              </ul></code>
          
            </li>
          </ul><br>
        </li>
        <li>HM-RC-19xxx
          <ul>
            <li><B>alarm &lt;count&gt;</B><br>
              issue an alarm message to the remote<br></li>
            <li><B>service &lt;count&gt;</B><br>
              issue an service message to the remote<br></li>
            <li><B>symbol &lt;symbol&gt; [set|unset]</B><br>
              activate a symbol as available on the remote.<br></li>
            <li><B>beep [off|1|2|3]</B><br>
              activate tone<br></li>
            <li><B>backlight [off|on|slow|fast]</B><br>
              activate backlight<br></li>
            <li><B>display &lt;text&gt; comma unit tone backlight &lt;symbol(s)&gt;
              </B><br>
              control display of the remote<br>
              &lt;text&gt; : up to 5 chars <br>
              comma : 'comma' activates the comma, 'no' leaves it off <br>
              [unit] : set the unit symbols.
              [off|Proz|Watt|x3|C|x5|x6|x7|F|x9|x10|x11|x12|x13|x14|x15]. Currently
              the x3..x15 display is not tested. <br>
              
              tone : activate one of the 3 tones [off|1|2|3]<br>
              
              backlight: activate backlight flash mode [off|on|slow|fast]<br>
              
              &lt;symbol(s)&gt; activate symbol display. Multople symbols can be
              acticated at the same time, concatinating them comma separated. Don't
              use spaces here. Possiblesymbols are
              
              [bulb|switch|window|door|blind|scene|phone|bell|clock|arrowUp|arrowDown]<br><br>
              Example:
              <ul><code>
                # "hello" in display, symb bulb on, backlight, beep<br>
                set FB1 display Hello no off 1 on bulb<br>
                # "1234,5" in display with unit 'W'. Symbols scene,phone,bell and
                # clock are active. Backlight flashing fast, Beep is second tone<br>
                set FB1 display 12345 comma Watt 2 fast scene,phone,bell,clock
              </ul></code>
            </li>
          </ul><br>
        </li>
        <li>HM-Dis-WM55
          <ul>
            <li><B>displayWM help </B>
              <B>displayWM [long|short] &lt;text1&gt; &lt;color1&gt; &lt;icon1&gt; ... &lt;text6&gt; &lt;color6&gt; &lt;icon6&gt;</B>
              <B>displayWM [long|short] &lt;lineX&gt; &lt;text&gt; &lt;color&gt; &lt;icon&gt;</B>
              <br>
              up to 6 lines can be addressed.<br>
              <B>lineX</B> line number that shall be changed. If this is set the 3 parameter of a line can be adapted. <br>
              <B>textNo</B> is the text to be dispalyed in line No. The text is assotiated with the text defined for the buttons.
              txt&lt;BtnNo&gt;_&lt;lineNo&gt; references channel 1 to 10 and their lines 1 or 2.
              Alternaly a free text of up to 12 char can be used<br>
              <B>color</B> is one white, red, orange, yellow, green, blue<br>
              <B>icon</B> is one off, on, open, closed, error, ok, noIcon<br>
              Example:
              <ul><code>
                set disp01 displayWM short txt02_2 green noIcon txt10_1 red error txt05_2 yellow closed txt02_2 orange open <br>
                set disp01 displayWM long line3 txt02_2 green noIcon<br>
                set disp01 displayWM long line2 nc yellow noIcon<br>
                set disp01 displayWM long line6 txt02_2<br>
                set disp01 displayWM long line1 nc nc closed<br>
              </ul></code>
            </li>
          </ul><br>
        </li>
        <li>keyMatic<br><br>
          <ul>The Keymatic uses the AES signed communication. Therefore the control
              of the Keymatic is only together with the HM-LAN adapter possible. But
              the CUL can read and react on the status information of the
              Keymatic.</ul><br>
          <ul>
            <li><B>lock</B><br>
               The lock bolt moves to the locking position<br></li>
            <li><B>unlock [sec]</B><br>
               The lock bolt moves to the unlocking position.<br>
               [sec]: Sets the delay in seconds after the lock automatically locked again.<br>
               0 - 65535 seconds</li>
            <li><B>open [sec]</B><br>
               Unlocked the door so that the door can be opened.<br>
               [sec]: Sets the delay in seconds after the lock automatically locked
               again.<br>0 - 65535 seconds</li>
          </ul>
        </li>
        <li>winMatic <br><br>
          <ul>winMatic provides 2 channels, one for the window control and a second
              for the accumulator.</ul><br>
          <ul>
            <li><B>level &lt;level&gt; &lt;relockDelay&gt; &lt;speed&gt;</B><br>
               set the level. <br>
               &lt;level&gt;:  range is 0 to 100%<br>
               &lt;relockDelay&gt;: range 0 to 65535 sec. 'ignore' can be used to igneore the value alternaly <br>
               &lt;speed&gt;: range is 0 to 100%<br>
            </li>
            <li><B>stop</B><br>
               stop movement<br>
            </li>
          </ul>
        </li>
        <li>CCU_FHEM<br>
          <ul>
            <li>defIgnUnknown<br>
              define unknown devices which are present in the readings. 
              set attr ignore and remove the readingfrom the list. <br>
            </li>
          </ul>
        </li>
        <li>HM-Sys-sRP-Pl<br><br>
          setup the repeater's entries. Up to 36entries can be applied.
          <ul>
            <li><B>setRepeat    &lt;entry&gt; &lt;sender&gt; &lt;receiver&gt; &lt;broadcast&gt;</B><br>
              &lt;entry&gt; [1..36] entry number in repeater table. The repeater can handle up to 36 entries.<br>
              &lt;sender&gt; name or HMID of the sender or source which shall be repeated<br>
              &lt;receiver&gt; name or HMID of the receiver or destination which shall be repeated<br>
              &lt;broadcast&gt; [yes|no] determines whether broadcast from this ID shall be repeated<br>
              <br>
              short application: <br>
              <code>setRepeat setAll 0 0 0<br></code>
              will rewrite the complete list to the deivce. Data will be taken from attribut repPeers. <br>
              attribut repPeers is formated:<br>
              src1:dst1:[y/n],src2:dst2:[y/n],src2:dst2:[y/n],...<br>
              <br>
              Reading repPeer is formated:<br>
              <ul>
                Number src dst broadcast verify<br>
                number: entry sequence number<br>
                src: message source device - read from repeater<br>
                dst: message destination device - assembled from attributes<br>
                broadcast: shall broadcast be repeated for this source - read from repeater<br>
                verify: do attributes and readings match?<br>
              </ul>
            </li>
          </ul>
        </li>
        <br>
        Debugging:
        <ul>
          <li><B>raw &lt;data&gt; ...</B><br>
              Only needed for experimentation.
              send a list of "raw" commands. The first command will be
              immediately sent, the next one after the previous one is acked by
              the target.  The length will be computed automatically, and the
              message counter will be incremented if the first two charcters are
              ++. Example (enable AES):
           <pre>
             set hm1 raw ++A001F100001234560105000000001\
                ++A001F10000123456010802010AF10B000C00\
                ++A001F1000012345601080801\
                ++A001F100001234560106</pre>
          </li>
        </ul>
    </ul>
    </ul>
    <br>
    <a name="CUL_HMget"></a><b>Get</b><br>
    <ul>
       <li><B>configSave &lt;filename&gt;</B><a name="CUL_HMconfigSave"></a><br>
           Saves the configuration of an entity into a file. Data is stored in a
           format to be executed from fhem command prompt.<br>
           The file is located in the fhem home directory aside of fhem.cfg. Data
           will be stored cumulative - i.e. new data will be appended to the
           file. It is up to the user to avoid duplicate storage of the same
           entity.<br>
           Target of the data is ONLY the HM-device information which is located
           IN the HM device. Explicitely this is the peer-list and the register.
           With the register also the peering is included.<br>
           The file is readable and editable by the user. Additionaly timestamps
           are stored to help user to validate.<br>
           Restrictions:<br>
           Even though all data of the entity will be secured to the file FHEM
           stores the data that is avalilable to FHEM at time of save!. It is up
           to the user to read the data from the HM-hardware prior to execution.
           See recommended flow below.<br>
           This command will not store any FHEM attributes o device definitions.
           This continues to remain in fhem.cfg.<br>
           Furthermore the secured data will not automatically be reloaded to the
           HM-hardware. It is up to the user to perform a restore.<br><br>
           As with other commands also 'configSave' is best executed on a device
           rather then on a channel. If executed on a device also the assotiated
           channel data will be secured. <br><br>
           <code>
           Recommended work-order for device 'HMdev':<br>
           set HMdev clear msgEvents  # clear old events to better check flow<br>
           set HMdev getConfig        # read device & channel inforamtion<br>
           # wait until operation is complete<br>
           # protState should be CMDs_done<br>
           #           there shall be no warnings amongst prot... variables<br>
           get configSave myActorFile<br>
           </code>
           </li>
       <li><B>param &lt;paramName&gt;</B><br>
           returns the content of the relevant parameter for the entity. <br>
           Note: if this command is executed on a channel and 'model' is
           requested the content hosting device's 'model' will be returned.
           </li>
       <li><B>reg &lt;addr&gt; &lt;list&gt; &lt;peerID&gt;</B><a name="CUL_HMget_reg"></a><br>
           returns the value of a register. The data is taken from the storage in FHEM and not 
  		 read directly outof the device. 
  		 If register content is not present please use getConfig, getReg in advance.<br>
  
           &lt;addr&gt; address in hex of the register. Registername can be used alternaly 
  		 if decoded by FHEM. "all" will return all decoded register for this entity in one list.<br>
           &lt;list&gt; list from which the register is taken. If rgistername is used list 
  		 is ignored and can be set to 0.<br>
           &lt;peerID&gt; identifies the registerbank in case of list3 and list4. It an be set to dummy if not used.<br>
           </li>
       <li><B>regVal &lt;addr&gt; &lt;list&gt; &lt;peerID&gt;</B><br>
           returns the value of a register. It does the same as <a href="#CUL_HMget_reg">reg</a> but strips off units<br>
           </li>
       <li><B>regList</B><br>
           returns a list of register that are decoded by FHEM for this device.<br>
           Note that there could be more register implemented for a device.<br>
           </li>
  
       <li><B>saveConfig &lt;file&gt;</B><a name="CUL_HMsaveConfig"></a><br>
           stores peers and register to the file.<br>
           Stored will be the data as available in fhem. It is necessary to read the information from the device prior to the save.<br>
           The command supports device-level action. I.e. if executed on a device also all related channel entities will be stored implicitely.<br>
           Storage to the file will be cumulative. 
           If an entity is stored multiple times to the same file data will be appended. 
           User can identify time of storage in the file if necessary.<br>
           Content of the file can be used to restore device configuration. 
           It will restore all peers and all register to the entity.<br>
           Constrains/Restrictions:<br>
           prior to rewrite data to an entity it is necessary to pair the device with FHEM.<br>
           restore will not delete any peered channels, it will just add peer channels.<br>
           </li>
       <li><B>listDevice</B><br>
           <ul>
                <li>when used with ccu it returns a list of Devices using the ccu service to assign an IO.<br>
                    </li>
                <li>when used with ActionDetector user will get a comma separated list of entities being assigned to the action detector<br>
                    get ActionDetector listDevice          # returns all assigned entities<br>
                    get ActionDetector listDevice notActive# returns entities which habe not status alive<br>
                    get ActionDetector listDevice alive    # returns entities with status alive<br>
                    get ActionDetector listDevice unknown  # returns entities with status unknown<br>
                    get ActionDetector listDevice dead     # returns entities with status dead<br>
                    </li> 
               </ul>
           </li>       
       <li><B>info</B><br>
           <ul>
                <li>provides information about entities using ActionDetector<br>
                    </li>
               </ul>
           </li>       
    </ul><br>
  
    <a name="CUL_HMattr"></a><b>Attributes</b>
    <ul>
      <li><a href="#eventMap">eventMap</a></li>
      <li><a href="#do_not_notify">do_not_notify</a></li>
      <li><a href="#ignore">ignore</a></li>
      <li><a href="#dummy">dummy</a></li>
      <li><a href="#showtime">showtime</a></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
      <li><a name="CUL_HMaesCommReq">aesCommReq</a>
           if set HMLAN/USB is forced to request AES signature before sending ACK to the device.<br>
           This funktion strictly works with HMLAN/USB - it doesn't work for CUL type IOs.<br>
          </li>
      <li><a name="#CUL_HMactAutoTry">actAutoTry</a>
           actAutoTry 0_off,1_on<br>
           setting this option enables Action Detector to send a statusrequest in case of a device is going to be marked dead.
           The attribut may be useful in case a device is being checked that does not send messages regularely - e.g. an ordinary switch. 
          </li>
      <li><a name="#CUL_HMactCycle">actCycle</a>
           actCycle &lt;[hhh:mm]|off&gt;<br>
           Supports 'alive' or better 'not alive' detection for devices. [hhh:mm] is the maximum silent time for the device. 
           Upon no message received in this period an event will be raised "&lt;device&gt; is dead". 
           If the device sends again another notification is posted "&lt;device&gt; is alive". <br>
           This actiondetect will be autocreated for each device with build in cyclic status report.<br>
           Controlling entity is a pseudo device "ActionDetector" with HMId "000000".<br>
           Due to performance considerations the report latency is set to 600sec (10min). 
           It can be controlled by the attribute "actCycle" of "ActionDetector".<br>
           Once entered to the supervision the HM device has 2 attributes:<br>
           <ul>
           actStatus: activity status of the device<br>
           actCycle:  detection period [hhh:mm]<br>
           </ul>
           The overall function can be viewed checking out the "ActionDetector" entity. The status of all entities is present in the READING section.<br>
           Note: This function can be enabled for devices with non-cyclic messages as well. It is up to the user to enter a reasonable cycletime.
          </li>
      <li><a name="#CUL_HMautoReadReg">autoReadReg</a><br>
          '0' autoReadReg will be ignored.<br>
          '1' will execute a getConfig for the device automatically after each reboot of FHEM. <br>
          '2' like '1' plus execute after power_on.<br>
          '3' includes '2' plus updates on writes to the device<br>
          '4' includes '3' plus tries to request status if it seems to be missing<br>
          '5' checks reglist and peerlist. If reading seems incomplete getConfig will be scheduled<br>
          '8_stateOnly' will only update status information but not configuration
                         data like register and peer<br>
          Execution will be delayed in order to prevent congestion at startup. Therefore the update
          of the readings and the display will be delayed depending on the size of the database.<br>
          Recommendations and constrains upon usage:<br>
          <ul>
              use this attribute on the device or channel 01. Do not use it separate on each channel
              of a multi-channel device to avoid duplicate execution<br>
              usage on devices which only react to 'config' mode is not recommended since executen will
              not start until config is triggered by the user<br>
              usage on devices which support wakeup-mode is usefull. But consider that execution is delayed
              until the device "wakes up".<br>
              </ul>
          </li>
      <li><a name="#CUL_HMburstAccess">burstAccess</a><br>
          can be set for the device entity if the model allowes conditionalBurst.
          The attribut will switch off burst operations (0_off) which causes less message load
          on HMLAN and therefore reduces the chance of HMLAN overload.<br>
          Setting it on (1_auto) allowes shorter reaction time of the device. User does not
          need to wait for the device to wake up. <br>
          Note that also the register burstRx needs to be set in the device.</li>
      <li><a name="#CUL_HMexpert">expert</a><br>
          This attribut controls the visibility of the readings. This attibute controlls
          the presentation of device parameter in the readings.<br>
          3 level can be choosen:<br>
          <ul>
          0_off: standart level. Display commonly used parameter<br>
          1_on: enhanced level. Display all decoded device parameter<br>
          2_full: display all parameter plus raw register information as well. <br>
          </ul>
          If expert is applied a device it is used for assotiated channels.
          It can be overruled if expert attibute is also applied to the channel device.<br>
          Make sure to check out attribut showInternalValues in the global values as well.
          extert takes benefit of the implementation.
          Nevertheless  - by definition - showInternalValues overrules expert.
          </li>
      <li><a name="#CUL_HMIOgrp">IOgrp</a><br>
          can be given to devices and shall point to a virtual CCU. As a consequence the
          CCU will take care of the assignment to the best suitable IO. It is necessary that a
          virtual CCU is defined and all relevant IO devices are assigned to it. Upon sending the CCU will
          check which IO is operational and has the best RSSI performance for this device.<br>
          Optional a prefered IO - perfIO can be given. In case this IO is operational it will be selected regardless
          of rssi values. <br>
          Example:<br>
          <ul><code>
            attr myDevice1 IOgrp vccu<br>
            attr myDevice2 IOgrp vccu:prefIO<br>
            attr myDevice2 IOgrp vccu:prefIO1,prefIO2,prefIO3<br>
          </code></ul>
          </li>
      <li><a name="#CUL_HMlevelRange">levelRange</a><br>
          can be used with dimmer only. It defines the dimmable range to be used with this dimmer-channel. 
          It is meant to support e.g. LED light that starts at 10% and reaches maxbrightness at 40%.
          levelrange will normalize the level to this range. I.e. set to 100% will physically set the 
          dimmer to 40%, 1% will set to 10% physically. 0% still switches physially off.<br>
          Impacted are commands on, up, down, toggle and pct. <b>Not</b> effected is the off command 
          which still set physically 0%.<br>
          To be considered:<br>
          dimmer level set by peers and buttons is not impacted. Those are controlled by device register<br>
          Readings level may go to negative or above 100%. This simply results from the calculation and reflects
          physical level is above or below the given range.<br>
          In case of virtual dimmer channels available present the attribut needs to be set for 
          each channel<br>
          User should be careful to set min level other then '0'<br>
          Example:<br>
          <ul><code>
            attr myChannel levelRange 0,40<br>
            attr myChannel levelRange 10,80<br>
          </code></ul>
          </li>
      <li><a name="#CUL_HMmodel">model</a>,
          <a name="subType">subType</a><br>
          These attributes are set automatically after a successful pairing.
          They are not supposed to be set by hand, and are necessary in order to
          correctly interpret device messages or to be able to send them.</li>
      <li><a name="#CUL_HMmsgRepeat">msgRepeat</a><br>
          defines number of repetitions if a device doesn't answer in time. <br>
          Devices which donly support config mode no repeat ist allowed. <br>
          For devices with wakeup mode the device will wait for next wakeup. Lonng delay might be 
          considered in this case. <br>
          Repeat for burst devices will impact HMLAN transmission capacity.</li>
      <li><a name="#CUL_HMparam">param</a><br>
          param defines model specific behavior or functions. See <a href="#CUL_HMparams"><b>available parameter</b></a> for details</li>
      <li><a name="#CUL_HMrawToReadable">rawToReadable</a><br>
          Used to convert raw KFM100 values to readable data, based on measured
          values. E.g.  fill slowly your container, while monitoring the
          values reported with <a href="#inform">inform</a>. You'll see:
          <ul>
            10 (at 0%)<br>
            50 (at 20%)<br>
            79 (at 40%)<br>
           270 (at 100%)<br>
          </ul>
          Apply these values with: "attr KFM100 rawToReadable 10:0 50:20 79:40 270:100".
          fhem will do a linear interpolation for values between the bounderies.
          </li>
      <li><a name="#CUL_HMrssiLog">rssiLog</a><br>
          can be given to devices, denied for channels. If switched '1' each RSSI entry will be
          written to a reading. User may use this to log and generate a graph of RSSI level.<br>
          Due to amount of readings and events it is NOT RECOMMENDED to switch it on by default.
          </li>
      <li><a name="#CUL_HMtempListTmpl">tempListTmpl</a><br>
          Sets the default template for a heating controller. If not given the detault template is taken from 
          file tempList.cfg using the enitity name as template name (e.g. ./tempLict.cfg:RT1_Clima <br> 
          To avoid template usage set this attribut to  '0'.<br> 
          Format is &lt;file&gt;:&lt;templatename&gt;. lt
          </li>
      <li><a name="unit">unit</a><br>
          set the reported unit by the KFM100 if rawToReadable is active. E.g.<br>
          attr KFM100 unit Liter
          </li>
    </ul>  <br>
    <a name="CUL_HMparams"><b>available parameter for attribut "param"</b></a>
    <ul>
      <li><B>HM-Sen-RD-O</B><br>
        <B>offAtPon</B> heat channel only: force heating off after powerOn<br>
        <B>onAtRain</B> heat channel only: force heating on while status changes to 'rain' and off when it changes to 'dry'<br>
      </li>
      <li><B>virtuals</B><br>
        <B>noOnOff</B> virtual entity will not toggle state when trigger is received. If this parameter is
        not given the entity will toggle its state between On and Off with each trigger<br>
        <B>msgReduce:&lt;No&gt;</B> if channel is used for <a ref="CUL_HMvalvePos"></a> it skips every No message
        in order to reduce transmit load. Numbers from 0 (no skip) up to 9 can be given. 
        VD will lose connection with more then 5 skips<br>
      </li>
      <li><B>blind</B><br>
        <B>levelInverse</B> while HM considers 100% as open and 0% as closed this may not be 
        intuitive to all user. Ny default 100%  is open and will be dislayed as 'on'. Setting this param the display will be inverted - 0% will be open and 100% is closed.<br>
        NOTE: This will apply to readings and set commands. <B>It does not apply to any register. </B><br>
      </li>
    </ul><br>
    <a name="CUL_HMevents"><b>Generated events:</b></a>
    <ul>
      <li><B>general</B><br>
          recentStateType:[ack|info] # cannot be used ti trigger notifies<br>
            <ul>
              <li>ack indicates that some statusinfo is derived from an acknowledge</li>  
              <li>info indicates an autonomous message from the device</li>  
              <li><a name="CUL_HMsabotageAttackId"><b>sabotageAttackId</b></a><br>
                Alarming configuration access to the device from a unknown source<br></li>
              <li><a name="CUL_HMsabotageAttack"><b>sabotageAttack</b></a><br>
                Alarming configuration access to the device that was not issued by our system<br></li>
              <li><a name="CUL_HMtrigDst"><b>trigDst_&lt;name&gt;: noConfig</b></a><br>
                A sensor triggered a Device which is not present in its peerList. Obviously the peerList is not up to date<br></li>
           </ul>
         </li>  
      <li><B>HM-CC-TC,ROTO_ZEL-STG-RM-FWT</B><br>
          T: $t H: $h<br>
          battery:[low|ok]<br>
          measured-temp $t<br>
          humidity $h<br>
          actuator $vp %<br>
          desired-temp $dTemp<br>
          desired-temp-manu $dTemp #temperature if switchen to manual mode<br>
          desired-temp-cent $dTemp #temperature if switchen to central mode<br>
          windowopen-temp-%d  %.1f (sensor:%s)<br>
          tempList$wd  hh:mm $t hh:mm $t ...<br>
          displayMode temp-[hum|only]<br>
          displayTemp [setpoint|actual]<br>
          displayTempUnit [fahrenheit|celsius]<br>
          controlMode [auto|manual|central|party]<br>
          tempValveMode [Auto|Closed|Open|unknown]<br>
          param-change  offset=$o1, value=$v1<br>
          ValveErrorPosition_for_$dname  $vep %<br>
          ValveOffset_for_$dname : $of %<br>
          ValveErrorPosition $vep %<br>
          ValveOffset $of %<br>
          time-request<br>
          trig_&lt;src&gt; &lt;value&gt; #channel was triggered by &lt;src&gt; channel.
          This event relies on complete reading of channels configuration, otherwise Data can be
          incomplete or incorrect.<br>
          trigLast &lt;channel&gt; #last receiced trigger<br>
      </li>
      <li><B>HM-CC-RT-DN and HM-CC-RT-DN-BoM</B><br>
          state:T: $actTemp desired: $setTemp valve: $vp %<br>
          motorErr: [ok|ValveTight|adjustRangeTooLarge|adjustRangeTooSmall|communicationERR|unknown|lowBat|ValveErrorPosition]
          measured-temp $actTemp<br>
          desired-temp $setTemp<br>
          ValvePosition $vp %<br>
          mode  [auto|manual|party|boost]<br>
          battery [low|ok]<br>
          batteryLevel $bat V<br>
          measured-temp $actTemp<br>
          desired-temp $setTemp<br>
          actuator $vp %<br>
          time-request<br>
          trig_&lt;src&gt; &lt;value&gt; #channel was triggered by &lt;src&gt; channel.
      </li>
      <li><B>HM-CC-VD,ROTO_ZEL-STG-RM-FSA</B><br>
          $vp %<br>
          battery:[critical|low|ok]<br>
          motorErr:[ok|blocked|loose|adjusting range too small|opening|closing|stop]<br>
          ValvePosition:$vp %<br>
          ValveErrorPosition:$vep %<br>
          ValveOffset:$of %<br>
          ValveDesired:$vp %            # set by TC <br>
          operState:[errorTargetNotMet|onTarget|adjusting|changed]  # operational condition<br>
          operStateErrCnt:$cnt          # number of failed settings<br>
      </li>
      <li><B>HM-CC-SCD</B><br>
          [normal|added|addedStrong]<br>
          battery [low|ok]<br>
      </li>
      <li><B>HM-SEC-SFA-SM</B><br>
          powerError [on|off]<br>
          sabotageError [on|off]<br>
          battery: [critical|low|ok]<br>
      </li>
      <li><B>HM-LC-BL1-PB-FM</B><br>
          motor: [opening|closing]<br>
      </li>
      <li><B>HM-LC-SW1-BA-PCB</B><br>
          battery: [low|ok]<br>
      </li>
      <li><B>HM-OU-LED16</B><br>
            color $value                  # hex - for device only<br>
          $value                        # hex - for device only<br>
          color [off|red|green|orange]  # for channel <br>
          [off|red|green|orange]        # for channel <br>
      </li>
      <li><B>HM-OU-CFM-PL</B><br>
          [on|off|$val]<br>
      </li>
      <li><B>HM-Sen-Wa-Od</B><br>
          $level%<br>
          level $level%<br>
      </li>
      <li><B>KFM100</B><br>
          $v<br>
          $cv,$unit<br>
          rawValue:$v<br>
          Sequence:$seq<br>
          content:$cv,$unit<br>
      </li>
      <li><B>KS550/HM-WDS100-C6-O</B><br>
          T: $t H: $h W: $w R: $r IR: $ir WD: $wd WDR: $wdr S: $s B: $b<br>
          temperature $t<br>
          humidity $h<br>
          windSpeed $w<br>
          windDirection $wd<br>
          windDirRange $wdr<br>
          rain $r<br>
          isRaining $ir<br>
          sunshine $s<br>
          brightness $b<br>
          unknown $p<br>
      </li>
      <li><B>HM-Sen-RD-O</B><br>
        lastRain: timestamp # no trigger generated. Begin of previous Rain -
                timestamp of the reading is the end of rain. <br>
      </li>
      <li><B>THSensor  and HM-WDC7000</B><br>
          T: $t H: $h AP: $ap<br>
          temperature $t<br>
          humidity $h<br>
          airpress $ap                   #HM-WDC7000 only<br>
      </li>
      <li><B>dimmer</B><br>
          overload [on|off]<br>
          overheat [on|off]<br>
          reduced [on|off]<br>
          dim: [up|down|stop]<br>
      </li>
      <li><B>motionDetector</B><br>
          brightness:$b<br>
          alive<br>
          motion on (to $dest)<br>
          motionCount $cnt _next:$nextTr"-"[0x0|0x1|0x2|0x3|15|30|60|120|240|0x9|0xa|0xb|0xc|0xd|0xe|0xf]<br>
          cover [closed|open]        # not for HM-Sec-MDIR<br>
          sabotageError [on|off]     # only HM-Sec-MDIR<br>
          battery [low|ok]<br>
          devState_raw.$d1 $d2<br>
      </li>
      <li><B>remote/pushButton/outputUnit</B><br>
          <ul> (to $dest) is added if the button is peered and does not send to broadcast<br>
          Release is provided for peered channels only</ul>
          Btn$x onShort<br>
          Btn$x offShort<br>
          Btn$x onLong $counter<br>
          Btn$x offLong $counter<br>
          Btn$x onLongRelease $counter<br>
          Btn$x offLongRelease $counter<br>
          Btn$x onShort (to $dest)<br>
          Btn$x offShort (to $dest)<br>
          Btn$x onLong $counter (to $dest)<br>
          Btn$x offLong $counter (to $dest)<br>
          Btn$x onLongRelease $counter (to $dest)<br>
          Btn$x offLongRelease $counter (to $dest)<br>
      </li>
      <li><B>remote/pushButton</B><br>
          battery [low|ok]<br>
          trigger [Long|Short]_$no trigger event from channel<br>
      </li>
      <li><B>swi</B><br>
            Btn$x Short<br>
            Btn$x Short (to $dest)<br>
            battery: [low|ok]<br>
         </li>
      <li><B>switch/dimmer/blindActuator</B><br>
          $val<br>
          powerOn [on|off|$val]<br>
          [unknown|motor|dim] [up|down|stop]:$val<br>
            timedOn [running|off]<br> # on is temporary - e.g. started with on-for-timer
      </li>
      <li><B>sensRain</B><br>
          $val<br>
          powerOn <br>
          level &lt;val&ge;<br>
            timedOn [running|off]<br> # on is temporary - e.g. started with on-for-timer
          trigger [Long|Short]_$no trigger event from channel<br>
      </li>
      <li><B>smokeDetector</B><br>
          [off|smoke-Alarm|alive]             # for team leader<br>
          [off|smoke-forward|smoke-alarm]     # for team members<br>
          [normal|added|addedStrong]          #HM-CC-SCD<br>
          SDteam [add|remove]_$dname<br>
          battery [low|ok]<br>
          smoke_detect [none|&lt;src&gt;]<br>
          teamCall:from $src<br>
      </li>
      <li><B>threeStateSensor</B><br>
          [open|tilted|closed]<br>
          [wet|damp|dry]                 #HM-SEC-WDS only<br>
          cover [open|closed]            #HM-SEC-WDS and HM-Sec-RHS<br>
          alive yes<br>
          battery [low|ok]<br>
          contact [open|tilted|closed]<br>
          contact [wet|damp|dry]         #HM-SEC-WDS only<br>
          sabotageError [on|off]         #HM-SEC-SC only<br>
      </li>
      <li><B>winMatic</B><br>
          [locked|$value]<br>
          motorErr [ok|TurnError|TiltError]<br>
          direction [no|up|down|undefined]<br>
          charge [trickleCharge|charge|dischange|unknown]<br>
          airing [inactiv|$air]<br>
          course [tilt|close]<br>
          airing [inactiv|$value]<br>
          contact tesed<br>
      </li>
      <li><B>keyMatic</B><br>
          unknown:40<br>
          battery [low|ok]<br>
          uncertain [yes|no]<br>
          error [unknown|motor aborted|clutch failure|none']<br>
          lock [unlocked|locked]<br>
          [unlocked|locked|uncertain]<br>
      </li>
    </ul>
    <a name="CUL_HMinternals"><b>Internals</b></a>
    <ul>
      <li><B>aesCommToDev</B><br>
        gives information about success or fail of AES communication between IO-device and HM-Device<br>
      </li>
    </ul><br>
    <br>
  </ul>
=end html
=begin html_DE

  <a name="CUL_HM"></a><h3>CUL_HM</h3>
  <ul>
    Unterst&uuml;tzung f&uuml;r eQ-3 HomeMatic Ger&auml;te via <a href="#CUL">CUL</a> oder <a href="#HMLAN">HMLAN</a>.<br>
    <br>
    <a name="CUL_HMdefine"></a><b>Define</b>
    <ul>
      <code><B>define &lt;name&gt; CUL_HM &lt;6-digit-hex-code|8-digit-hex-code&gt;</B></code>
      
      <br><br>
      Eine korrekte Ger&auml;tedefinition ist der Schl&uuml;ssel zur einfachen Handhabung der HM-Umgebung.
      <br>
      
      Hintergrund zur Definition:<br>
      HM-Ger&auml;te haben eine 3 Byte (6 stelliger HEX-Wert) lange HMid - diese ist Grundlage
      der Adressierung. Jedes Ger&auml;t besteht aus einem oder mehreren Kan&auml;len. Die HMid f&uuml;r einen
      Kanal ist die HMid des Ger&auml;tes plus die Kanalnummer (1 Byte, 2 Stellen) in
      hexadezimaler Notation.
      Kan&auml;le sollten f&uuml;r alle mehrkanaligen Ger&auml;te definiert werden. Eintr&auml;ge f&uuml;r Kan&auml;le
      k&ouml;nnen nicht angelegt werden wenn das zugeh&ouml;rige Ger&auml;t nicht existiert.<br> Hinweis: FHEM
      belegt das Ger&auml;t automatisch mit Kanal 1 falls dieser nicht explizit angegeben wird. Daher
      ist bei einkanaligen Ger&auml;ten keine Definition n&ouml;tig.<br>
      
      Hinweis: Wird ein Ger&auml;t gel&ouml;scht werden auch die zugeh&ouml;rigen Kan&auml;le entfernt. <br> Beispiel einer
      vollst&auml;ndigen Definition eines Ger&auml;tes mit 2 Kan&auml;len:<br>
      <ul><code>
        define livingRoomSwitch CUL_HM 123456<br>
        define LivingroomMainLight CUL_HM 12345601<br>
        define LivingroomBackLight CUL_HM 12345602<br><br>
      </code></ul>
      
      livingRoomSwitch bezeichnet das zur Kommunikation verwendete Ger&auml;t. Dieses wird
      vor den Kan&auml;len definiert um entsprechende Verweise einstellen zu k&ouml;nnen. <br>
      LivingroomMainLight hat Kanal 01 und behandelt den Lichtstatus, Kanal-Peers
      sowie zugeh&ouml;rige Kanalregister. Falls nicht definiert wird Kanal 01 durch die Ger&auml;teinstanz
      abgedeckt.<br> LivingRoomBackLight ist der zweite "Kanal", Kanal 02. Seine
      Definition ist verpflichtend um die Funktion ausf&uuml;hren zu k&ouml;nnen.<br><br>
      
      Sonderfall Sender: HM behandelt jeden Knopf einer Fernbedienung, Drucktaster und
      &auml;hnliches als Kanal . Es ist m&ouml;glich (nicht notwendig) einen Kanal pro Knopf zu
      definieren. Wenn alle Kan&auml;le definiert sind ist der Zugriff auf Pairing-Informationen
      sowie auf Kanalregister m&ouml;glich. Weiterhin werden Verkn&uuml;pfungen durch Namen besser
      lesbar.<br><br>
      
      define kann auch durch das <a href="#autocreate">autocreate</a>
      Modul aufgerufen werden, zusammen mit dem notwendigen subType Attribut.
      Normalerweise erstellt man <a href="#CULset">hmPairForSec</a> und dr&uuml;ckt dann den
      zugeh&ouml;rigen Knopf am Ger&auml;t um die Verkn&uuml;pfung herzustellen oder man verwendet <a
      href="#CULset">hmPairSerial</a> falls das Ger&auml;t ein Empf&auml;nger und die Seriennummer
      bekannt ist. Autocreate wird dann ein FHEM-Ger&auml;t mit allen notwendigen Attributen anlegen.
      Ohne Pairing wird das Ger&auml;t keine Befehle von FHEM akzeptieren. Selbst wenn das Pairing
      scheitert legt FHEM m&ouml;glicherweise das Ger&auml;t an. Erfolgreiches Pairen wird
      durch den Eintrag CommandAccepted in den Details zum CUL_HM Ger&auml;t angezeigt.<br><br>
      
      Falls autocreate nicht verwendet werden kann muss folgendes spezifiziert werden:<br>
      <ul>
        <li>Der &lt;6-stellige-Hex-Code&gt;oder HMid+ch &lt;8-stelliger-Hex-Code&gt;<br>
          Das ist eine einzigartige, festgelegte Ger&auml;teadresse die nicht ge&auml;ndert werden kann (nein,
          man kann sie nicht willk&uuml;rlich ausw&auml;hlen wie z.B. bei FS20 Ger&auml;ten). Man kann sie feststellen
          indem man das FHEM-Log durchsucht.</li>
        <li>Das subType Attribut<br>
          Dieses lautet: switch dimmer blindActuator remote sensor swi
          pushButton threeStateSensor motionDetector keyMatic winMatic
          smokeDetector</li>
        <li>Das model Attribut<br>
        ist entsprechend der HM Nomenklatur zu vergeben</li>
      </ul>
      Ohne diese Angaben kann FHEM nicht korrekt mit dem Ger&auml;t arbeiten.<br><br>
      
      <b>Hinweise</b>
      <ul>
        <li>Falls das Interface ein Ger&auml;t vom Typ CUL ist muss <a href="#rfmode">rfmode </a>
          des zugeh&ouml;rigen CUL/CUN Ger&auml;tes auf HomeMatic gesetzt werden.
          Achtung: Dieser Modus ist nur f&uuml;r BidCos/Homematic. Nachrichten von FS20/HMS/EM/S300
          werden durch diese Ger&auml;t <b>nicht</b> empfangen. Bereits definierte FS20/HMS
          Ger&auml;te m&uuml;ssen anderen Eing&auml;ngen zugeordnet werden (CUL/FHZ/etc).
        </li>
        <li>Nachrichten eines Ger&auml;ts werden nur richtig interpretiert wenn der Ger&auml;tetyp
          bekannt ist. FHEM erh&auml;lt den Ger&auml;tetyp aus einer"pairing request"
          Nachricht, selbst wenn es darauf keine Antwort erh&auml;lt (siehe <a
          href="#hmPairSerial">hmPairSerial</a> und <a
          href="#hmPairForSec">hmPairForSec</a> um Parinig zu erm&ouml;glichen).
          Alternativ, setzen des richtigen subType sowie Modelattributes, f&uuml;r eine Liste der
          m&ouml;glichen subType-Werte siehe "attr hmdevice ?".</li>
        <a name="HMAES"></a>
        <li>Die sogenannte "AES-Verschl&uuml;sselung" ist eigentlich eine Signaturanforderung: Ist sie
          aktiviert wird ein Aktor den erhaltenen Befehl nur ausf&uuml;hren falls er die korrekte
          Antwort auf eine zuvor durch den Aktor gestellte Anfrage erh&auml;lt. Das bedeutet:
          <ul>
            <li>Die Reaktion auf Befehle ist merklich langsamer, da 3 Nachrichten anstatt einer &uuml;bertragen
              werden bevor der Befehl vom Aktor ausgef&uuml;hrt wird.</li>
            <li>Jeder Befehl sowie seine Best&auml;tigung durch das Ger&auml;t wird in Klartext &uuml;bertragen, ein externer
              Beobachter kennt somit den Status jedes Ger&auml;ts.</li>
            <li>Die eingebaute Firmware ist fehlerhaft: Ein "toggle" Befehl wir ausgef&uuml;hrt <b>bevor</b> die
              entsprechende Antwort auf die Signaturanforderung empfangen wurde, zumindest bei einigen Schaltern
              (HM-LC-Sw1-Pl und HM-LC-SW2-PB-FM).</li>
            <li>Der <a href="#HMLAN">HMLAN</a> Konfigurator beantwortet Signaturanforderungen selbstst&auml;ndig,
              ist dabei die 3-Byte-Adresse einer anderen CCU eingestellt welche noch immer das Standardpasswort hat,
              kann dieser Signaturanfragen korrekt beantworten.</li>
            <li>AES-Verschl&uuml;sselung kann nicht bei einem CUL als Interface eingesetzt werden, wird allerdings
              durch HMLAN unterst&uuml;tzt. Aufgrund dieser Einschr&auml;nkungen ist der Einsatz der Homematic-Verschl&uuml;sselung
              nicht zu empfehlen!</li>
          </ul>
        </li>
      </ul>
    </ul><br>
    <a name="CUL_HMset"></a><b>Set</b>
    <ul>
      Hinweis: Ger&auml;te die normalerweise nur senden (Fernbedienung/Sensor/etc.) m&uuml;ssen in den
      Pairing/Lern-Modus gebracht werden um die folgenden Befehle zu empfangen.
      <br>
      <br>
      
      Allgemeine Befehle (verf&uuml;gbar f&uuml;r die meisten HM-Ger&auml;te):
      <ul>
        <li><B>clear &lt;[rssi|readings|register|msgEvents|attack|all]&gt;</B><a name="CUL_HMclear"></a><br>
            Eine Reihe von Variablen kann entfernt werden.<br>
          <ul>
            readings: Alle Messwerte werden gel&ouml;scht, neue Werte werden normal hinzugef&uuml;gt. Kann benutzt werden um alte Daten zu entfernen<br>
            register: Alle in FHEM aufgezeichneten Registerwerte werden entfernt. Dies hat KEINEN Einfluss auf Werte im Ger&auml;t.<br>
            msgEvents: Alle Anchrichtenz&auml;hler werden gel&ouml;scht. Ebenso wird der Befehlsspeicher zur&uuml;ckgesetzt. <br>
            rssi: gesammelte RSSI-Werte werden gel&ouml;scht.<br>
            attack: Einträge bezüglich einer Attack werden gelöscht.<br>
            all: alles oben genannte.<br>
          </ul>
        </li>
        <li><B>getConfig</B><a name="CUL_HMgetConfig"></a><br>
          Liest die Hauptkonfiguration eines HM_Ger&auml;tes aus. Angewendet auf einen Kanal
          erh&auml;lt man Pairing-Information, List0, List1 und List3 des ersten internen Peers.
          Außerdem erh&auml;lt man die Liste der Peers f&uuml;r den gegebenen Kanal. Wenn auf ein Ger&auml;t
          angewendet so bekommt man mit diesem Befehl die vorherigen Informationen f&uuml;r alle
          zugeordneten Kan&auml;le. Ausgeschlossen davon sind Konfigurationen zus&auml;tzlicher Peers.
          <br> Der Befehl ist eine Abk&uuml;rzung f&uuml;r eine Reihe anderer Befehle.
        </li>
        <li><B>getRegRaw [List0|List1|List2|List3|List4|List5|List6]&lt;peerChannel&gt; </B><a name="CUL_HMgetRegRaw"></a><br>
          Auslesen der Rohdaten des Registersatzes. Eine Beschreibung der Register sprengt
          den Rahmen dieses Dokuments.<br>
          
          Die Register sind in sog. Listen strukturiert welche einen Satz Register enthalten.<br>
          
          List0: Ger&auml;teeinstellungen z.B: Einstellungen f&uuml;r CUL-Pairing Temperaturlimit eines Dimmers.<br>
          
          List1: Kanaleinstellungen z.B. ben&ouml;tigte Zeit um Rollo hoch und runter zu fahren.<br>
          
          List3: "link" Einstellungen - d.h. Einstellungen f&uuml;r Peer-Kanal. Das ist eine große Datenmenge!
          Steuert Aktionen bei Empfang eines Triggers vom Peer.<br>
          
          List4: Einstellungen f&uuml;r den Kanal (Taster) einer Fernbedienung.<br><br>
          
          &lt;PeerChannel&gt; verkn&uuml;pfte HMid+ch, z.B. 4 byte (8 stellige) Zahl wie
          '12345601'. Ist verpflichtend f&uuml;r List3 und List4 und kann ausgelassen werden
          f&uuml;r List0 und 1. <br>
          
          'all' kann verwendet werden um Daten von jedem mit einem Kanal verkn&uuml;pften Link zu bekommen. <br>
          
          'selfxx' wird verwendet um interne Kan&auml;le zu adressieren (verbunden mit den eingebauten Schaltern
          falls vorhanden). xx ist die Kanalnummer in dezimaler Notation.<br>
          
          Hinweis 1: Ausf&uuml;hrung ist abh&auml;ngig vom Entity. Wenn List1 f&uuml;r ein Ger&auml;t statt einem Kanal
          abgefragt wird gibt der Befehl List1 f&uuml;r alle zugeh&ouml;rigen Kan&auml;le aus.
          List3 mit 'peerChannel = all' gibt alle Verbindungen f&uuml;r alle Kan&auml;le eines Ger&auml;tes zur&uuml;ck.<br>
          
          Hinweis 2: f&uuml;r 'Sender' siehe auch <a href="#CUL_HMremote">remote</a> <br>
          
          Hinweis 3: Das Abrufen von Informationen kann dauern - besonders f&uuml;r Ger&auml;te
          mit vielen Kan&auml;len und Verkn&uuml;pfungen. Es kann n&ouml;tig sein das Webinterface manuell neu zu laden
          um die Ergebnisse angezeigt zu bekommen.<br>
          
          Hinweis 4: Direkte Schalter eines HM-Ger&auml;ts sind standardm&auml;ßig ausgeblendet.
          Dennoch sind sie genauso als Verkn&uuml;pfungen implemetiert. Um Zugriff auf 'internal links'
          zu bekommen ist es notwendig folgendes zu erstellen:<br>
          'set &lt;name&gt; <a href="#CUL_HMregSet">regSet</a> intKeyVisib visib'<br>
          oder<br>
          'set &lt;name&gt; <a href="#CUL_HMregBulk">regBulk</a> RegL_0: 2:81'<br>
          Zur&uuml;cksetzen l&auml;sst es sich indem '81' mit '01' ersetzt wird.<br> example:<br>
          
          <ul><code>
            set mydimmer getRegRaw List1<br>
            set mydimmer getRegRaw List3 all <br>
          </code></ul>
          </li>
        <li><B>getSerial</B><a name="CUL_HMgetSerial"></a><br>
          Auslesen der Seriennummer eines ger&auml;ts und speichern in Attribut serialNr.
        </li>
        <li><B>inhibit [on|off]</B><br>
          Blockieren/Zulassen aller Kanal&auml;nderungen eines Aktors, d.h. Zustand des Aktors ist
          eingefroren bis 'inhibit' wieder deaktiviert wird. 'Inhibit' kann f&uuml;r jeden Aktorkanal
          ausgef&uuml;hrt werden aber nat&uuml;rlich nicht f&uuml;r Sensoren - w&uuml;rde auch keinen Sinn machen.<br>
          Damit ist es praktischerweise m&ouml;glich Nachrichten ebenso wie verkn&uuml;pfte Kanalaktionen
          tempor&auml;r zu unterdr&uuml;cken ohne sie l&ouml;schen zu m&uuml;ssen. <br>
          Beispiele:
          <ul><code>
            # Ausf&uuml;hrung blockieren<br>
            set keymatic inhibit on <br><br>
          </ul></code>
        </li>
        
        <li><B>pair</B><a name="CUL_HMpair"></a><br>
          Verbinden eines Ger&auml;ts bekannter Seriennummer (z.b. nach einem Reset)
          mit einer FHEM-Zentrale. Diese Zentrale wird normalerweise durch CUL/CUNO,
          HMLAN,... hergestellt.
          Wenn verbunden melden Ger&auml;te ihren Status and FHEM.
          Wenn nicht verbunden wird das Ger&auml;t auf bestimmte Anfragen nicht reagieren
          und auch bestimmte Statusinformationen nicht melden. Pairing geschieht auf
          Ger&auml;teebene. Kan&auml;le k&ouml;nnen nicht unabh&auml;ngig von einem Ger&auml;t mit der Zentrale
          verbunden werden.
          Siehe auch <a href="#CUL_HMgetpair">getPair</a> und
          <a href="#CUL_HMunpair">unpair</a>.<br>
          Nicht das Verbinden (mit einer Zentrale) mit verkn&uuml;pfen (Kanal zu Kanal) oder
          <a href="#CUL_HMpeerChan">peerChan</a> verwechseln.<br>
        </li>
        <li><B>peerBulk</B> &lt;peerch1,peerch2,...&gt; [set|unset]<a name="CUL_HMpeerBulk"></a><br>
          peerBulk f&uuml;gt Peer-Kan&auml;le zu einem Kanal hinzu. Alle Peers einer Liste werden
          dabei hinzugef&uuml;gt.<br>
          Peering setzt die Einstellungen einer Verkn&uuml;pfung auf Standardwerte. Da Peers nicht in Gruppen
          hinzugef&uuml;gt werden werden sie durch HM standardm&auml;ßig als'single' f&uuml;r dieses Ger&auml;t
          angelegt. <br>
          Eine ausgekl&uuml;geltere Funktion wird gegeben durch
          <a href="#CUL_HMpeerChan">peerChan</a>.<br>
          peerBulk l&ouml;scht keine vorhandenen Peers sondern bearbeitet nur die Peerliste.
          Andere bereits angelegt Peers werden nicht ver&auml;ndert.<br>
          peerBulk kann verwendet werden um Peers zu l&ouml;schen indem die <B>unset</B> Option
          mit Standardeinstellungen aufgerufen wird.<br>
          
          Verwendungszweck dieses Befehls ist haupts&auml;chlich das Wiederherstellen
          von Daten eines Ger&auml;ts.
          Empfehlenswert ist das anschließende Wiederherstellen der Registereinstellung
          mit <a href="#CUL_HMregBulk">regBulk</a>. <br>
          Beispiel:<br>
          <ul><code>
            set myChannel peerBulk 12345601,<br>
            set myChannel peerBulk self01,self02,FB_Btn_04,FB_Btn_03,<br>
            set myChannel peerBulk 12345601 unset # entferne Peer 123456 Kanal 01<br>
          </code></ul>
        </li>
        <li><B>regBulk &lt;reg List&gt;:&lt;peer&gt; &lt;addr1:data1&gt; &lt;addr2:data2&gt;...</B><a name="CUL_HMregBulk"></a><br>
          Dieser Befehl ersetzt das bisherige regRaw. Er erlaubt Register mit Rohdaten zu
          beschreiben. Hauptzweck ist das komplette Wiederherstellen eines zuvor gesicherten
          Registers. <br>
          Werte k&ouml;nnen mit <a href="#CUL_HMgetConfig">getConfig</a> ausgelesen werden. Die
          zur&uuml;ckgegebenen Werte k&ouml;nnen direkt f&uuml;r diesen Befehl verwendet werden.<br>
          &lt;reg List&gt; bezeichnet die Liste in die geschrieben werden soll. M&ouml;gliches Format
          '00', 'RegL_00', '01'...<br>
          &lt;peer&gt; ist eine optionale Angabe falls die Liste ein Peer ben&ouml;tigt.
          Der Peer kann als Kanalname oder als 4-Byte (8 chars) HM-Kanal ID angegeben
          werden.<br>
          &lt;addr1:data1&gt; ist die Liste der Register im Hex-Format.<br>
          Beispiel:<br>
          <ul><code>
            set myChannel regBulk RegL_00: 02:01 0A:17 0B:43 0C:BF 15:FF 00:00<br>
            RegL_03:FB_Btn_07
            01:00 02:00 03:00 04:32 05:64 06:00 07:FF 08:00 09:FF 0A:01 0B:44 0C:54 0D:93 0E:00 0F:00 11:C8 12:00 13:00 14:00 15:00 16:00 17:00 18:00 19:00 1A:00 1B:00 1C:00 1D:FF 1E:93 1F:00 81:00 82:00 83:00 84:32 85:64 86:00 87:FF 88:00 89:FF 8A:21 8B:44 8C:54 8D:93 8E:00 8F:00 91:C8 92:00 93:00 94:00 95:00 96:00 97:00 98:00 99:00 9A:00 9B:00 9C:00 9D:05 9E:93 9F:00 00:00<br>
            set myblind regBulk 01 0B:10<br>
            set myblind regBulk 01 0C:00<br>
            </code></ul>
          myblind setzt die maximale Zeit f&uuml;r das Hochfahren der Rollos auf 25,6 Sekunden
        </li>
        <li><B>regSet [prep|exec] &lt;regName&gt; &lt;value&gt; &lt;peerChannel&gt;</B><a name="CUL_HMregSet"></a><br>
          F&uuml;r einige Hauptregister gibt es eine lesbarere Version die Registernamen &lt;regName&gt;
          und Wandlung der Werte enth&auml;lt. Nur ein Teil der Register wird davon unterst&uuml;tzt.<br>
          Der optionale Parameter [prep|exec] erlaubt das Packen von Nachrichten und verbessert damit
          deutlich die Daten&uuml;bertragung.
          Benutzung durch senden der Befehle mit Parameter "prep". Daten werden dann f&uuml;r das Senden gesammelt.
          Der letzte Befehl muss den Parameter "exec" habe um die Information zu &uuml;bertragen.<br>
          &lt;value&gt; enth&auml;lt die Daten in menschenlesbarer Form die in das Register geschrieben werden.<br>
          &lt;peerChannel&gt; wird ben&ouml;tigt falls das Register 'peerChan' basiert definiert wird.
          Kann ansonsten auf '0' gesetzt werden. Siehe <a
          href="#CUL_HMgetRegRaw">getRegRaw</a> f&uuml;r komplette Definition.<br>
          Unterst&uuml;tzte Register eines Ger&auml;ts k&ouml;nnen wie folgt bestimmt werden:<br>
          <ul><code>set regSet ? 0 0</code></ul>
            Eine verk&uuml;rzte Beschreibung der Register wird zur&uuml;ckgegeben mit:<br>
          <ul><code>set regSet &lt;regname&gt; ? 0</code></ul>
        </li>
        <li><B>reset</B><a name="CUL_HMreset"></a><br>
          R&uuml;cksetzen des Ger&auml;ts auf Werkseinstellungen. Muss danach erneut verbunden werden um es
          mit FHEM zu nutzen.
        </li>
        <li><B>sign [on|off]</B><a name="CUL_HMsign"></a><br>
          Ein- oder ausschalten der Signierung (auch "AES-Verschl&uuml;sselung" genannt, siehe <a
          href="#HMAES">note</a>). Achtung: Wird das Ger&auml;t &uuml;ber einen CUL eingebunden ist schalten (oder
          deaktivieren der Signierung) nicht m&ouml;glich, das Ger&auml;t muss direkt zur&uuml;ckgesetzt werden.
        </li>
        <li><B>statusRequest</B><a name="CUL_HMstatusRequest"></a><br>
          Aktualisieren des Ger&auml;testatus. F&uuml;r mehrkanalige Ger&auml;te sollte dies kanalbasiert
          erfolgen.
        </li>
        <li><B>unpair</B><a name="CUL_HMunpair"></a><br>
          Aufheben des "Pairings", z.B. um das verbinden mit einem anderen Master zu erm&ouml;glichen.
          Siehe <a href="#CUL_HMpair">pair</a> f&uuml;r eine Beschreibung.</li>
        <li><B>virtual &lt;Anzahl an Kn&ouml;pfen&gt;</B><a name="CUL_HMvirtual"></a><br>
          Konfiguriert eine vorhandene Schaltung als virtuelle Fernbedienung. Die Anzahl der anlegbaren
          Kn&ouml;pfe ist 1 - 255. Wird der Befehl f&uuml;r die selbe Instanz erneut aufgerufen werden Kn&ouml;pfe
          hinzugef&uuml;gt. <br>
          Beispiel f&uuml;r die Anwendung:
          <ul><code>
            define vRemote CUL_HM 100000 # die gew&auml;hlte HMid darf nicht in Benutzung sein<br>
            set vRemote virtual 20 # definiere eine Fernbedienung mit 20 Kn&ouml;pfen<br>
            set vRemote_Btn4 peerChan 0 &lt;actorchannel&gt; # verkn&uuml;pft Knopf 4 und 5 mit dem gew&auml;hlten Kanal<br>
            set vRemote_Btn4 press<br>
            set vRemote_Btn5 press long<br>
          </code></ul>
          siehe auch <a href="#CUL_HMpress">press</a>
        </li>
      </ul>
      <br>

      <B>subType abh&auml;ngige Befehle:</B>
      <ul>
        <br>
        <li>switch
          <ul>
            <li><B>on</B> <a name="CUL_HMon"> </a> - setzt Wert auf 100%</li>
            <li><B>off</B><a name="CUL_HMoff"></a> - setzt Wert auf 0%</li>
            <li><B>on-for-timer &lt;sec&gt;</B><a name="CUL_HMonForTimer"></a> -
              Schaltet das Ger&auml;t f&uuml;r die gew&auml;hlte Zeit in Sekunden [0-85825945] an.<br> Hinweis:
              off-for-timer wie bei FS20 wird nicht unterst&uuml;tzt. Kann aber &uuml;ber Kanalregister
              programmiert werden.</li>
            <li><B>on-till &lt;time&gt;</B><a name="CUL_HMonTill"></a> - einschalten bis zum angegebenen Zeitpunkt.<br>
              <ul><code>set &lt;name&gt; on-till 20:32:10<br></code></ul>
              Das momentane Maximum f&uuml;r eine Endzeit liegt bei 24 Stunden.<br>
            </li>
            <li><B>press &lt;[short|long]&gt;&lt;[on|off]&gt;</B><a name="CUL_HMpress"></a><br>
              <B>press &lt;[short|long]&gt;&lt;[noBurst]&gt;</B></a>
              simuliert den Druck auf einen lokalen Knopf oder direkt verbundenen Knopf des Aktors.<br>
              <B>[short|long]</B> w&auml;hlt aus ob ein kurzer oder langer Tastendruck simuliert werden soll.<br>
              <B>[on|off]</B> ist relevant f&uuml;r Ger&auml;te mit direkter Bedienung pro Kanal.
              Verf&uuml;gbar f&uuml;r Dimmer und Rollo-Aktoren, normalerweise nicht f&uuml;r Schalter.<br>
              <B>[noBurst]</B> ist relevant f&uuml;r Peers die bedingte Bursts unterst&uuml;tzen.
              Dies bewirkt das der Befehl der Warteliste des Peers zugef&uuml;gt wird. Ein Burst wird anschließend
              <B>nicht </B> ausgef&uuml;hrt da der Befehl wartet bis der Peer aufgewacht ist. Dies f&uuml;hrt zu einer
              <B>Verz&ouml;gerung des Tastendrucks</B>, reduziert aber &Uuml;bertragungs- und Performanceaufwand. <br>
            </li>
            <li><B>toggle</B><a name="CUL_HMtoggle"></a> - toggled den Aktor. Schaltet vom aktuellen Level auf
              0% oder von 0% auf 100%</li>
          </ul>
          <br>
        </li>
        <li>dimmer, blindActuator<br>
          Dimmer k&ouml;nnen virtuelle Kan&auml;le unterst&uuml;tzen. Diese werden automatisch angelegt falls vorhanden.
          Normalerweise gibt es 2 virtuelle Kan&auml;le zus&auml;tzlich zum prim&auml;ren Kanal. Virtuelle Dimmerkan&auml;le sind
          standardm&auml;ßig deaktiviert, k&ouml;nnen aber parallel zum ersten Kanal benutzt werden um das Licht zu steuern. <br>
          Die virtuellen Kan&auml;le haben Standardnamen SW&lt;channel&gt;_V&lt;nr&gt; z.B. Dimmer_SW1_V1 and Dimmer_SW1_V2.<br>
          Virtuelle Dimmerkan&auml;le unterscheiden sich komplett von virtuellen Kn&ouml;pfen und Aktoren in FHEM, sind aber
          Teil des HM-Ger&auml;ts. Dokumentation und M&ouml;glichkeiten w&uuml;rde hier aber zu weit f&uuml;hren.<br>
          <ul>
            <li><B>0 - 100 [on-time] [ramp-time]</B><br>
              Setzt den Aktor auf den gegeben Wert (In Prozent)
              mit einer Aufl&ouml;sung von 0.5.<br>
              Bei Dimmern ist optional die Angabe von "on-time" und "ramp-time" m&ouml;glich, beide in Sekunden mit 0.1s Abstufung.<br>
              "On-time" verh&auml;lt sich analog dem "on-for-timer".<br>
              "Ramp-time" betr&auml;gt standardm&auml;ßig 2.5s, 0 bedeutet umgehend.<br>
            </li>
            <li><B><a href="#CUL_HMon">on</a></B></li>
            <li><B><a href="#CUL_HMoff">off</a></B></li>
            <li><B><a href="#CUL_HMpress">press &lt;[short|long]&gt;&lt;[on|off]&gt;</a></B></li>
            <li><B><a href="#CUL_HMtoggle">toggle</a></B></li>
            <li><B>toggleDir</B><a name="CUL_HMtoggleDir"></a> - toggelt die fahrtrichtung des Rollo-Aktors.
              Es wird umgeschaltet zwischen auf/stop/ab/stop</li>
            <li><B><a href="#CUL_HMonForTimer">on-for-timer &lt;sec&gt;</a></B> - Nur Dimmer! <br></li>
            <li><B><a href="#CUL_HMonTill">on-till &lt;time&gt;</a></B> - Nur Dimmer! <br></li>
            <li><B>stop</B> - Stopt Bewegung (Rollo) oder Dimmerrampe</li>
            <li><B>pct &lt;level&gt [&lt;ontime&gt] [&lt;ramptime&gt]</B> - setzt Aktor auf gew&uuml;nschten <B>absolut Wert</B>.<br>
              Optional k&ouml;nnen f&uuml;r Dimmer "ontime" und "ramptime" angegeben werden.<br>
              "Ontime" kann dabei in Sekunden angegeben werden. Kann auch als Endzeit angegeben werden im Format hh:mm:ss
            </li>
            <li><B>up [changeValue] [&lt;ontime&gt] [&lt;ramptime&gt]</B> Einen Schritt hochdimmen.</li>
            <li><B>down [changeValue] [&lt;ontime&gt] [&lt;ramptime&gt]</B> Einen Schritt runterdimmen.<br>
              "changeValue" ist optional und gibt den zu &auml;ndernden Wert in Prozent an. M&ouml;gliche Abstufung dabei ist 0.5%, Standard ist 10%. <br>
              "ontime" ist optional und gibt an wielange der Wert gehalten werden soll. '0' bedeutet endlos und ist Standard.<br>
              "ramptime" ist optional und definiert die Zeit bis eine &auml;nderung den neuen Wert erreicht. Hat nur f&uuml;r Dimmer Bedeutung.
            <br></li>
          </ul>
          <br>
        </li>
        <li>remotes, pushButton<a name="CUL_HMremote"></a><br>
          Diese Ger&auml;teart reagiert nicht auf Anfragen, außer sie befinden sich im Lernmodus. FHEM reagiert darauf
          indem alle Anfragen gesammelt werden bis der Lernmodus detektiert wird. Manuelles Eingreifen durch
          den Benutzer ist dazu n&ouml;tig. Ob Befehle auf Ausf&uuml;hrung warten kann auf Ger&auml;teebene mit dem Parameter
          'protCmdPend' abgefragt werden.
          <ul>
            <li><B>peerChan &lt;btn_no&gt; &lt;actChan&gt; [single|<u>dual</u>|reverse]
              [<u>set</u>|unset] [<u>both</u>|actor|remote]</B><a name="CUL_HMpeerChan"></a><br>
              "peerChan" richtet eine Verbindung zwischen Sender-<B>Kanal</B> und
              Aktor-<B>Kanal</B> ein, bei HM "link" genannt. "Peering" darf dabei nicht
              mit "pairing" verwechselt werden.<br>
              <B>Pairing</B> bezeichnet das Zuordnen eines <B>Ger&auml;ts</B> zu einer Zentrale.<br>
              <B>Peering</B> bezeichnet das faktische Verbinden von <B>Kan&auml;len</B>.<br>
              Peering erlaubt die direkte Interaktion zwischen Sender und Aktor ohne den Einsatz einer CCU<br>
              Peering eines Senderkanals veranlaßt den Sender nach dem Senden eines Triggers auf die
              Best&auml;tigung eines - jeden - Peers zu warten. Positives Feedback (z.B. gr&uuml;ne LED)
              gibt es dabei nur wenn alle Peers den Befehl best&auml;tigt haben.<br>
              Peering eines Aktorkanals richtet dabei einen Satz von Parametern ein welche die auszuf&uuml;hrenden Aktionen
              definieren wenn ein Trigger dieses Peers empfangen wird. Dies bedeutet: <br>
              - nur Trigger von Peers werden ausgef&uuml;hrt<br>
              - die auszuf&uuml;hrende Aktion muss f&uuml;r den zugeh&ouml;rigen Trigger eines Peers definiert werden<br>
              Ein Aktorkanal richtet dabei eine Standardaktion beim Peering ein - diese h&auml;ngt vom Aktor ab.
              Sie kann ebenfalls davon abh&auml;ngen ob ein oder zwei Tasten <B>ein einem Befehl</B> gepeert werden.
              Peert man einen Schalter mit 2 Tasten kann eine Taste f&uuml;r 'on' und eine andere f&uuml;r 'off' angelegt werden.
              Wenn nur eine Taste definiert wird ist die Funktion wahrscheinlich 'toggle'.<br>
              Die Funktion kann durch programmieren des Register (vom Aktor abh&auml;ngig) ge&auml;ndert werden.<br>
              
              Auch wenn der Befehl von einer Fernbedienung oder einem Taster kommt hat er direkten Effekt auf
              den Aktor. Das Peering beider Seiten ist quasi unabh&auml;ngig und hat unterschiedlich Einfluss auf
              Sender und Empf&auml;nger.<br>
              Peering eines Aktorkanals mit mehreren Senderkan&auml;len ist ebenso m&ouml;glich wie das eines Senderkanals
              mit mehreren Empf&auml;ngerkan&auml;len.<br>
              
              &lt;actChan&gt; ist der zu verkn&uuml;pfende Aktorkanal.<br>
              
              &lt;btn_no&gt; ist der zu verkn&uuml;pfende Senderkanal (Knopf). Wird
              'single' gew&auml;hlt werden die Tasten von 1 an gez&auml;hlt. F&uuml;r 'dual' ist btn_no
              die Nummer des zu verwendenden Tasterpaares. Z.B. ist '3' iim Dualmodus das
              dritte Tasterpaar welches mit Tasten 5 und 6 im Singlemodus &uuml;bereinstimmt.<br>
              
              Wird der Befehl auf einen Kanal angewendet wird btn_no igroriert.
              Muss gesetzt sein, sollte dabei 0 sein.<br>
              
              [single|dual]: Dieser Modus bewirkt das Standardverhalten des Aktors bei Benutzung eines Tasters. Ein Dimmer
              kann z.B. an einen einzelnen oder ein Paar von Tastern angelernt werden. <br>
              Standardeinstellung ist "dual".<br>
              
              'dual' (default) Schalter verkn&uuml;pft zwei Taster mit einem Aktor. Bei einem Dimmer
              bedeutet das ein Taster f&uuml;r hoch- und einer f&uuml;r runterdimmen. <br>
              
              'reverse' identisch zu dual - nur die Reihenfolge der Buttons ist gedreht<br>
              
              'single' benutzt nur einen Taster des Senders. Ist z.B. n&uuml;tzlich f&uuml;r einen einfachen Schalter
              der nur zwischen an/aus toggled. Aber auch ein Dimmer kann an nur einen Taster angelernt werden.<br>
              
              [set|unset]: W&auml;hlt aus ob Peer hinzugef&uuml;gt oder entfernt werden soll.<br>
              Hinzuf&uuml;gen ist Standard.<br>
              'set' stellt Peers f&uuml;r einen Kanal ein.<br>
              'unset' entfernt Peer f&uuml;r einen Kanal.<br>
              
              [actor|remote|both] beschr&auml;nkt die Ausf&uuml;hrung auf Aktor oder Fernbedienung.
              Das erm&ouml;glicht dem Benutzer das entfernen des Peers vom Fernbedienungskanal ohne
              die Einstellungen am Aktor zu entfernen.<br>
              Standardm&auml;ßig gew&auml;hlt ist "both" f&uuml;r beides.<br>
              
              Example:
              <ul><code>
                set myRemote peerChan 2 mySwActChn single set #Peer zweiten Knopf mit Aktorkanal<br>
                set myRmtBtn peerChan 0 mySwActChn single set #myRmtBtn ist ein Knopf der Fernbedienung. '0' wird hier nicht verarbeitet<br>
                set myRemote peerChan 2 mySwActChn dual set #Verkn&uuml;pfe Kn&ouml;pfe 3 und 4<br>
                set myRemote peerChan 3 mySwActChn dual unset #Entferne Peering f&uuml;r Kn&ouml;pfe 5 und 6<br>
                set myRemote peerChan 3 mySwActChn dual unset aktor #Entferne Peering f&uuml;r Kn&ouml;pfe 5 und 6 nur im Aktor<br>
                set myRemote peerChan 3 mySwActChn dual set remote #Verkn&uuml;pfe Kn&ouml;pfe 5 und 6 nur mit Fernbedienung. Linkeinstellungen mySwActChn werden beibehalten.<br>
              </code></ul>
            </li>
          </ul>
        
        </li>
        <li>virtual<a name="CUL_HMvirtual"></a><br>
          <ul>
            <li><B><a href="#CUL_HMpeerChan">peerChan</a></B> siehe remote</li>
            <li><B><a name="CUL_HMpress"></a>press [long|short] [&lt;peer&gt;] [&lt;repCount&gt;] [&lt;repDelay&gt;] </B>
              <ul>
                  Simuliert den Tastendruck am Aktor eines gepeerted Sensors
                 <li>[long|short] soll ein langer oder kurzer Taastendrucl simuliert werden? Default ist kurz. </li>
                 <li>[&lt;peer&gt;] legt fest, wessen peer's trigger simuliert werden soll.Default ist self(channelNo).</li>
                 <li>[&lt;repCount&gt;] nur gueltig fuer long. wie viele messages sollen gesendet werden? (Laenge des Button press). Default ist 1.</li>
                 <li>[&lt;repDelay&gt;] nur gueltig fuer long. definiert die Zeit zwischen den einzelnen Messages. </li>
              </ul>  
              </li>
            <li><B>virtTemp &lt;[off -10..50]&gt;<a name="CUL_HMvirtTemp"></a></B>
              Simuliert ein Thermostat. Wenn mit einem Ger&auml;t gepeert wird periodisch eine Temperatur gesendet,
              solange bis "off" gew&auml;hlt wird. Siehe auch <a href="#CUL_HMvirtHum">virtHum</a><br>
            </li>
            <li><B>virtHum &lt;[off -10..50]&gt;<a name="CUL_HMvirtHum"></a></B>
              Simuliert den Feuchtigkeitswert eines Thermostats. Wenn mit einem Ger&auml;t verkn&uuml;pft werden periodisch
              Luftfeuchtigkeit undTemperatur gesendet, solange bis "off" gew&auml;hlt wird. Siehe auch <a href="#CUL_HMvirtTemp">virtTemp</a><br>
            </li>
            <li><B>valvePos &lt;[off 0..100]&gt;<a name="CUL_HMvalvePos"></a></B>
              steuert einen Ventilantrieb<br>
            </li>
          </ul>
        </li>
        <li>smokeDetector<br>
          Hinweis: All diese Befehle funktionieren momentan nur wenn mehr als ein Rauchmelder
          vorhanden ist, und diese gepeert wurden um eine Gruppe zu bilden. Um die Befehle abzusetzen
          muss der Master dieser gruppe verwendet werden, und momentan muss man raten welcher der Master ist.<br>
          smokeDetector kann folgendermaßen in Gruppen eingeteilt werden:
          <a href="#CUL_HMpeerChan">peerChan</a>. Alle Mitglieder m&uuml;ssen mit dem Master verkn&uuml;pft werden. Auch der
          Master muss mit peerChan zur Gruppe zugef&uuml;gt werden - z.B. mit sich selbst verkn&uuml;pft! Dadurch hat man volle
          Kontrolle &uuml;ber die Gruppe und muss nicht raten.<br>
          <ul>
            <li><B>teamCall</B> - f&uuml;hrt einen Netzwerktest unter allen Gruppenmitgliedern aus</li>
            <li><B>alarmOn</B> - l&ouml;st einen Alarm aus</li>
            <li><B>alarmOff</B> - schaltet den Alarm aus</li>
          </ul>
        </li>
        <li>4Dis (HM-PB-4DIS-WM)
          <ul>
            <li><B>text &lt;btn_no&gt; [on|off] &lt;text1&gt; &lt;text2&gt;</B><br>
              Zeigt Text auf dem Display eines Ger&auml;ts an. F&uuml;r diesen Zweck muss zuerst ein set-Befehl
              (oder eine Anzahl davon) abgegeben werden, dann k&ouml;nnen im "teach-in" Men&uuml; des 4Dis mit
              "Central" Daten &uuml;bertragen werden.<br>
              Falls auf einen Kanal angewendet d&uuml;rfen btn_no und on|off nicht verwendet werden, nur
              reiner Text.<br>
              \_ wird durch ein Leerzeichen ersetzt.<br>
              Beispiel:
              <ul>
                <code>
                  set 4Dis text 1 on On Lamp<br>
                  set 4Dis text 1 off Kitchen Off<br>
                  <br>
                  set 4Dis_chn4 text Kitchen Off<br>
                </code>
              </ul>
            </li>
          </ul>
          <br>
        </li>
        <li>Climate-Control (HM-CC-TC)
          <ul>
            <li><B>fwUpdate &lt;filename&gt; [&lt;waitTime&gt;] </B><br>
                update Fw des Device. Der User muss das passende FW file bereitstellen. 
                waitTime ist optional. Es ist die Wartezeit, um das Device manuell in den FW-update-mode
                zu versetzen.</li>
            <li><B>desired-temp &lt;temp&gt;</B><br>
              Setzt verschiedene Temperaturen. &lt;temp&gt; muss zwischen 6°C und 30°C liegen, die Aufl&ouml;sung betr&auml;gt 0.5°C.</li>
            <li><B>tempListSat [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListSun [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListMon [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListTue [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListThu [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListWed [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListFri [prep|exec] HH:MM temp ... 24:00 temp</B><br>
              Gibt eine Liste mit Temperaturintervallen an. Bis zu 24 Intervall k&ouml;nnen pro Wochentag definiert werden, die
              Aufl&ouml;sung dabei sind 10 Minuten. Die letzte Zeitangabe muss 24:00 Uhr sein.<br>
              Beispiel: bis 6:00 soll die Temperatur 19°C sein, dann bis 23:00 Uhr 22.5°C, anschließend
              werden bis Mitternacht 19°C gew&uuml;nscht.<br>
              <code> set th tempListSat 06:00 19 23:00 22.5 24:00 19<br></code>
            </li>
            <li><B>partyMode &lt;HH:MM&gt;&lt;durationDays&gt;</B><br>
              setzt die Steuerung f&uuml;r die angegebene Zeit in den Partymodus. Dazu ist die Endzeit sowie <b>Anzahl an Tagen</b>
              die er dauern soll anzugeben. Falls er am n&auml;chsten Tag enden soll ist '1'
              anzugeben<br></li>
            <li><B>sysTime</B><br>
              setzt Zeit des Klimakanals auf die Systemzeit</li>
          </ul><br>
        </li>
        <li>Climate-Control (HM-CC-RT-DN|HM-CC-RT-DN-BoM)
          <ul>
            <li><B>controlMode &lt;auto|boost|day|night&gt;</B><br></li>
            <li><B>controlManu &lt;temp&gt;</B><br></li>
            <li><B>controlParty &lt;temp&gt;&lt;startDate&gt;&lt;startTime&gt;&lt;endDate&gt;&lt;endTime&gt;</B><br>
              setzt die Steuerung in den Partymodus, definiert Temperatur und Zeitrahmen.<br>
              Beispiel:<br>
              <code>set controlParty 15 03.8.13 20:30 5.8.13 11:30</code></li>
            <li><B>sysTime</B><br>
              setzt Zeit des Klimakanals auf die Systemzeit</li>
            <li><B>desired-temp &lt;temp&gt;</B><br>
              Setzt verschiedene Temperaturen. &lt;temp&gt; muss zwischen 6°C und 30°C liegen, die Aufl&ouml;sung betr&auml;gt 0.5°C.</li>
            <li><B>tempListSat [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListSun [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListMon [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListTue [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListThu [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListWed [prep|exec] HH:MM temp ... 24:00 temp</B><br></li>
            <li><B>tempListFri [prep|exec] HH:MM temp ... 24:00 temp</B><br>
              Gibt eine Liste mit Temperaturintervallen an. Bis zu 24 Intervall k&ouml;nnen pro Wochentag definiert werden, die
              Aufl&ouml;sung dabei sind 10 Minuten. Die letzte Zeitangabe muss immer 24:00 Uhr sein.<br>
              Der optionale Parameter [prep|exec] erlaubt das packen der Nachrichten und verbessert damit deutlich
              die Daten&uuml;bertragung. Besonders n&uuml;tzlich wenn das Ger&auml;t im "Wakeup"-modus betrieben wird.
              Benutzung durch senden der Befehle mit Parameter "prep". Daten werden dann f&uuml;r das Senden gesammelt.
              Der letzte Befehl muss den Parameter "exec" habe um die Information zu &uuml;bertragen.<br>
              Beispiel: bis 6:00 soll die Temperatur 19°C sein, dann bis 23:00 Uhr 22.5°C, anschließend
              werden bis Mitternacht 19°C gew&uuml;nscht.<br>
              <code> set th tempListSat 06:00 19 23:00 22.5 24:00 19<br></code>
              <br>
              <code> set th tempListSat prep 06:00 19 23:00 22.5 24:00 19<br>
                set th tempListSun prep 06:00 19 23:00 22.5 24:00 19<br>
                set th tempListMon prep 06:00 19 23:00 22.5 24:00 19<br>
                set th tempListTue exec 06:00 19 23:00 22.5 24:00 19<br></code>
            </li>
            <li><B>tempListTmpl   =>"[verify|restore] [[&lt;file&gt;:]templateName] ...</B><br>
              Die Temperaturlisten fr ein oder mehrere Devices k&ouml;nnen in einem File hinterlegt 
              werden. Es wird ein template f&uuml;r eine Woche hinterlegt. Der User kann dieses
              template in ein Device schreiben lassen (restore). Er kann auch pr&uuml;fen, ob das Device korrekt
              nach dieser Templist programmiert ist (verify). 
              Default Opeartion ist verify.<br>
              Default File ist tempList.cfg.<br>
              Default templateName ist der name der Entity<br>
              Default f&uuml;r file und templateName kann mit dem Attribut <B>tempListTmpl</B> gesetzt werden.<br>
              Beispiel f&uuml;r ein templist File. room1 und room2 sind die Namen 2er Tempaltes:<br>
              <code>entities:room1
                 tempListSat>08:00 16.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListSun>08:00 16.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListMon>07:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListTue>07:00 16.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 15.0
                 tempListWed>07:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListThu>07:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListFri>07:00 16.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
              entities:room2
                 tempListSat>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListSun>08:00 14.0 15:00 18.0 21:30 19.0 24:00 14.0
                 tempListMon>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListTue>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 15.0
                 tempListWed>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListThu>07:00 14.0 16:00 18.0 21:00 19.0 24:00 14.0
                 tempListFri>07:00 14.0 13:00 16.0 16:00 18.0 21:00 19.0 24:00 14.0
              </code>
            </li>
          </ul><br>
        </li>
        <li>OutputUnit (HM-OU-LED16)
          <ul>
            <li><B>led [off|red|green|yellow]</B><br>
              schaltet die LED des Kanals auf die gew&uuml;nschte Farbe. Wird der Befehl auf ein Ger&auml;t angewandt so
              werden alle LEDs auf diese Farbe gesetzt.<br>
              Experten k&ouml;nnen die LEDs separat durch eine 8-stellige Hex-Zahl ansteuern.<br></li>
            <li><B>ilum &lt;Helligkeit&gt;&lt;Dauer&gt; </B><br>
              &lt;Helligkeit&gt; [0-15] der Beleuchtung.<br>
              &lt;Dauer&gt; [0-127] in Sekunden, 0 bedeutet dauernd an.<br></li>
          </ul><br>
        </li>
        <li>OutputUnit (HM-OU-CFM-PL)
          <ul>
            <li><B>led &lt;color&gt;[,&lt;color&gt;..] [&lt;repeat&gt..]</B><br>
              M&ouml;gliche Farben sind [redL|greenL|yellowL|redS|greenS|yellowS|pause]. Eine Folge von Farben
              kann durch trennen der Farbeintr&auml;ge mit ',' eingestellt werden.
              Leerzeichen d&uuml;rfen in der Liste nicht benutzt werden. 'S' bezeichnet kurze und
              'L' lange Beleuchtungsdauer. <br>
              <b>repeat</b> definiert wie oft die Sequenz ausgef&uuml;hrt werden soll. Standard ist 1.<br>
            </li>
            <li><B>playTone &lt;MP3No&gt[,&lt;MP3No&gt..] [&lt;repeat&gt..]</B><br>
              Spielt eine Reihe von T&ouml;nen. Die Liste muss mit ',' getrennt werden. Leerzeichen
              d&uuml;rfen in der Liste nicht benutzt werden.<br>
              <b>replay</b> kann verwendet werden um den zuletzt gespielten Klang zu wiederholen.<br>
              <b>repeat</b> definiert wie oft die Sequenz ausgef&uuml;hrt werden soll. Standard ist 1.<br>
              Beispiel:
              <ul><code>
                set cfm_Mp3 playTone 3 # MP3 Titel 3 einmal<br>
                set cfm_Mp3 playTone 3 3 # MP3 Titel 3 dreimal<br>
                set cfm_Mp3 playTone 3,6,8,3,4 # MP3 Titelfolge 3,6,8,3,4 einmal<br>
                set cfm_Mp3 playTone 3,6,8,3,4 255# MP3 Titelfolge 3,6,8,3,4 255 mal<br>
                set cfm_Mp3 playTone replay # Wiederhole letzte Sequenz<br>
                <br>
                set cfm_Led led redL 4 # rote LED dreimal lang blinken<br>
                set cfm_Led led redS,redS,redS,redL,redL,redL,redS,redS,redS 255 # SOS 255 mal<br>
              </ul></code>
              
            </li>
          </ul><br>
        </li>
        <li>HM-RC-19xxx
          <ul>
            <li><B>alarm &lt;count&gt;</B><br>
              sendet eine Alarmnachricht an die Steuerung<br></li>
            <li><B>service &lt;count&gt;</B><br>
              sendet eine Servicenachricht an die Steuerung<br></li>
            <li><B>symbol &lt;symbol&gt; [set|unset]</B><br>
              aktiviert ein verf&uuml;gbares Symbol auf der Steuerung<br></li>
            <li><B>beep [off|1|2|3]</B><br>
              aktiviert T&ouml;ne<br></li>
            <li><B>backlight [off|on|slow|fast]</B><br>
              aktiviert Hintergrundbeleuchtung<br></li>
            <li><B>display &lt;text&gt; comma unit tone backlight &lt;symbol(s)&gt;
              </B><br>
              Steuert das Display der Steuerung<br>
              &lt;text&gt; : bis zu 5 Zeichen <br>
              comma : 'comma' aktiviert das Komma, 'no' l&auml;ßt es aus <br>
              [unit] : setzt Einheitensymbole.
              [off|Proz|Watt|x3|C|x5|x6|x7|F|x9|x10|x11|x12|x13|x14|x15]. Momentan sind
              x3..x15 nicht getestet. <br>
              tone : aktiviert einen von 3 T&ouml;nen [off|1|2|3]<br>
              backlight: l&auml;ßt die Hintergrundbeleuchtung aufblinken [off|on|slow|fast]<br>
              &lt;symbol(s)&gt; aktiviert die Anzeige von Symbolen. Mehrere Symbole
              k&ouml;nnen zu selben Zeit aktiv sein, Verkn&uuml;pfung erfolgt komma-getrennt. Dabei keine
              Leerzeichen verwenden. M&ouml;gliche Symbole:
              [bulb|switch|window|door|blind|scene|phone|bell|clock|arrowUp|arrowDown]<br><br>
              
              Beispiel:
              <ul><code>
                # "Hello" auf dem Display, Symbol bulb an, Hintergrundbeleuchtung, Ton ausgeben<br>
                set FB1 display Hello no off 1 on bulb<br>
                # "1234,5" anzeigen mit Einheit 'W'. Symbole scene,phone,bell und
                # clock sind aktiv. Hintergrundbeleuchtung blinikt schnell, Ausgabe von Ton 2<br>
                set FB1 display 12345 comma Watt 2 fast scene,phone,bell,clock
              </ul></code>
            </li>
          </ul><br>
        </li>
        <li>HM-Dis-WM55
          <ul>
            <li><B>displayWM help </B>
               <B>displayWM [long|short] &lt;text1&gt; &lt;color1&gt; &lt;icon1&gt; ... &lt;text6&gt; &lt;color6&gt; &lt;icon6&gt;</B>
               <B>displayWM [long|short] &lt;lineX&gt; &lt;text&gt; &lt;color&gt; &lt;icon&gt;</B>
               <br>
               es können bis zu 6 Zeilen programmiert werden.<br>
               <B>lineX</B> legt die zu ändernde Zeilennummer fest. Es können die 3 Parameter der Zeile geändert werden.<br>
               <B>textNo</B> ist der anzuzeigende Text. Der Inhalt des Texts wird in den Buttonds definiert. 
               txt&lt;BtnNo&gt;_&lt;lineNo&gt; referenziert den Button und dessn jeweiligen Zeile. 
               Alternativ kann ein bis zu 12 Zeichen langer Freitext angegeben werden<br>
               <B>color</B> kann sein white, red, orange, yellow, green, blue<br>
               <B>icon</B> kann sein off, on, open, closed, error, ok, noIcon<br>
            
               Example:
                 <ul><code>
                 set disp01 displayWM short txt02_2 green noIcon txt10_1 red error txt05_2 yellow closed txt02_2 orange open <br>
                 set disp01 displayWM long line3 txt02_2 green noIcon<br>
                 set disp01 displayWM long line2 nc yellow noIcon<br>
                 set disp01 displayWM long line6 txt02_2<br>
                 set disp01 displayWM long line1 nc nc closed<br>
                 </ul></code>
               </li>
          </ul><br>
        </li>
        <li>keyMatic<br><br>
          <ul>Keymatic verwendet eine AES-signierte Kommunikation. Deshalb ist die Steuerung von Keymatic
            nur mit dem HM-LAN m&ouml;glich. But
            Ein CUL kann aber Statusnachrichten von Keymatic mitlesen und darauf
            reagieren.</ul><br>
          <ul>
            <li><B>lock</B><br>
              Schließbolzen f&auml;hrt in Zu-Position<br></li>
            <li><B>unlock [sec]</B><br>
              Schließbolzen f&auml;hrt in Auf-Position.<br>
              [sec]: Stellt die Verz&ouml;gerung ein nach der sich das Schloss automatisch wieder verschließt.<br>
              0 - 65535 Sekunden</li>
            <li><B>open [sec]</B><br>
              Entriegelt die T&uuml;r sodass diese ge&ouml;ffnet werden kann.<br>
              [sec]: Stellt die Verz&ouml;gerung ein nach der sich das Schloss automatisch wieder
              verschließt.<br>0 - 65535 Sekunden</li>
          </ul>
        </li>
        <li>winMatic <br><br>
          <ul>winMatic arbeitet mit 2 Kan&auml;len, einem f&uuml;r die Fenstersteuerung und einem f&uuml;r den Akku.</ul><br>
          <ul>
            <li><B>level &lt;level&gt; &lt;relockDelay&gt; &lt;speed&gt;</B><br>
              stellt den Wert ein. <br>
              &lt;level&gt;: Bereich ist 0% bis 100%<br>
              &lt;relockDelay&gt;: Spanne reicht von 0 bis 65535 Sekunden. 'ignore' kann verwendet werden um den Wert zu ignorieren.<br>
              &lt;speed&gt;: Bereich ist 0% bis 100%<br>
            </li>
            <li><B>stop</B><br>
              stopt die Bewegung<br>
            </li>
          </ul>
        </li>
        <li>CCU_FHEM<br>
          <ul>
          <li>defIgnUnknown<br>
            Definieren die unbekannten Devices und setze das Attribut ignore. 
            Ddann loesche die Readings. <br>
          </li>
          </ul>
        </li>
        <li>HM-Sys-sRP-Pl<br>
          legt Eintr&auml;ge f&uuml;r den Repeater an. Bis zu 36 Eintr&auml;ge k&ouml;nnen angelegt werden.
          <ul>
            <li><B>setRepeat &lt;entry&gt; &lt;sender&gt; &lt;receiver&gt; &lt;broadcast&gt;</B><br>
              &lt;entry&gt; [1..36] Nummer des Eintrags in der Tabelle.<br>
              &lt;sender&gt; Name oder HMid des Senders oder der Quelle die weitergeleitet werden soll<br>
              &lt;receiver&gt; Name oder HMid des Empf&auml;ngers oder Ziels an das weitergeleitet werden soll<br>
              &lt;broadcast&gt; [yes|no] definiert ob Broadcasts von einer ID weitergeleitet werden sollen.<br>
              <br>
              Kurzanwendung: <br>
              <code>setRepeat setAll 0 0 0<br></code>
              schreibt die gesamte Liste der Ger&auml;te neu. Daten kommen vom Attribut repPeers. <br>
              Das Attribut repPeers hat folgendes Format:<br>
              src1:dst1:[y/n],src2:dst2:[y/n],src2:dst2:[y/n],...<br>
              <br>
              Formatierte Werte von repPeer:<br>
              <ul>
                Number src dst broadcast verify<br>
                number: Nummer des Eintrags in der Liste<br>
                src: Ursprungsger&auml;t der Nachricht - aus Repeater ausgelesen<br>
                dst: Zielger&auml;t der Nachricht - aus den Attributen abgeleitet<br>
                broadcast: sollen Broadcasts weitergeleitet werden - aus Repeater ausgelesen<br>
                verify: stimmen Attribute und ausgelesen Werte &uuml;berein?<br>
              </ul>
            </li>
          </ul>
        </li>
        
      </ul>
      <br>
      Debugging:
      <ul>
        <li><B>raw &lt;data&gt; ...</B><br>
          nur f&uuml;r Experimente ben&ouml;tigt.
          Sendet eine Liste von "Roh"-Befehlen. Der erste Befehl wird unmittelbar gesendet,
          die folgenden sobald der vorherige best&auml;tigt wurde. Die L&auml;nge wird automatisch
          berechnet und der Nachrichtenz&auml;hler wird erh&ouml;ht wenn die ersten beiden Zeichen ++ sind.
          
          Beispiel (AES aktivieren):
          <pre>
            set hm1 raw ++A001F100001234560105000000001\
            ++A001F10000123456010802010AF10B000C00\
            ++A001F1000012345601080801\
            ++A001F100001234560106
          </pre>
        </li>
      </ul>
    </ul>
    <br>
    <a name="CUL_HMget"></a><b>Get</b><br>
    <ul>
      <li><B>configSave &lt;filename&gt;</B><a name="CUL_HMconfigSave"></a><br>
        Sichert die Einstellungen eines Eintrags in einer Datei. Die Daten werden in
        einem von der FHEM-Befehlszeile ausf&uuml;hrbaren Format gespeichert.<br>
        Die Datei liegt im FHEM Home-Verzeichnis neben der fhem.cfg. Gespeichert wird
        kumulativ- d.h. neue Daten werden an die Datei angeh&auml;ngt. Es liegt am Benutzer das
        doppelte speichern von Eintr&auml;gen zu vermeiden.<br>
        Ziel der Daten ist NUR die Information eines HM-Ger&auml;tes welche IM Ger&auml;t gespeichert ist.
        Im Deteil sind das nur die Peer-Liste sowie die Register.
        Durch die Register wird also das Peering eingeschlossen.<br>
        Die Datei ist vom Benutzer les- und editierbar. Zus&auml;tzlich gespeicherte Zeitstempel
        helfen dem Nutzer bei der Validierung.<br>
        Einschr&auml;nkungen:<br>
        Auch wenn alle Daten eines Eintrags in eine Datei gesichert werden so sichert FHEM nur
        die zum Zeitpunkt des Speicherns verf&uuml;gbaren Daten! Der Nutzer muss also die Daten
        der HM-Hardware auslesen bevor dieser Befehl ausgef&uuml;hrt wird.
        Siehe empfohlenen Ablauf unten.<br>
        Dieser Befehl speichert keine FHEM-Attribute oder Ger&auml;tedefinitionen.
        Diese verbleiben in der fhem.cfg.<br>
        Desweiteren werden gesicherte Daten nicht automatisch zur&uuml;ck auf die HM-Hardware geladen.
        Der Benutzer muss die Wiederherstellung ausl&ouml;sen.<br><br>
        Ebenso wie ander Befehle wird 'configSave' am besten auf ein Ger&auml;t und nicht auf einen
        Kanal ausgef&uuml;hrt. Wenn auf ein Ger&auml;t angewendet werden auch die damit verbundenen Kan&auml;le
        gesichert. <br><br>
        <code>
          Empfohlene Arbeitsfolge f&uuml;r ein Ger&auml;t 'HMdev':<br>
          set HMdev clear msgEvents # alte Events l&ouml;schen um Daten besser kontrollieren zu k&ouml;nnen<br>
          set HMdev getConfig # Ger&auml;te- und Kanalinformation auslesen<br>
          # warten bis Ausf&uuml;hrung abgeschlossen ist<br>
          # "protState" sollte dann "CMDs_done" sein<br>
          # es sollten keine Warnungen zwischen "prot" und den Variablen auftauchen<br>
          get configSave myActorFile<br>
        </code>
      </li>
      <li><B>param &lt;paramName&gt;</B><br>
        Gibt den Inhalt der relevanten Parameter eines Eintrags zur&uuml;ck. <br>
        Hinweis: wird der Befehl auf einen Kanal angewandt und 'model' abgefragt so wird das Model
        des inhalteanbietenden Ger&auml;ts zur&uuml;ckgegeben.
      </li>
      <li><B>reg &lt;addr&gt; &lt;list&gt; &lt;peerID&gt;</B><br>
        liefert den Wert eines Registers zur&uuml;ck. Daten werden aus dem Speicher von FHEM und nicht direkt vom Ger&auml;t geholt.
        Falls der Registerinhalt nicht verf&uuml;gbar ist muss "getConfig" sowie anschließend "getReg" verwendet werden.<br>
        
        &lt;addr&gt; Adresse des Registers in HEX. Registername kann alternativ verwendet werden falls in FHEM bekannt.
        "all" gibt alle dekodierten Register eines Eintrags in einer Liste zur&uuml;ck.<br>
        &lt;list&gt; Liste aus der das Register gew&auml;hlt wird. Wird der REgistername verwendet wird "list" ignoriert und kann auf '0' gesetzt werden.<br>
        &lt;peerID&gt; identifiziert die Registerb&auml;nke f&uuml;r "list3" und "list4". Kann als Dummy gesetzt werden wenn nicht ben&ouml;tigt.<br>
      </li>
      <li><B>regList</B><br>
        gibt eine Liste der von FHEM f&uuml;r dieses Ger&auml;t dekodierten Register zur&uuml;ck.<br>
        Beachten dass noch mehr Register f&uuml;r ein Ger&auml;t implemetiert sein k&ouml;nnen.<br>
      </li>
      <li><B>saveConfig &lt;file&gt;</B><a name="CUL_HMsaveConfig"></a><br>
        speichert Peers und Register in einer Datei.<br>
        Gespeichert werden die Daten wie sie in FHEM verf&uuml;gbar sind. Es ist daher notwendig vor dem Speichern die Daten auszulesen.<br>
        Der Befehl unterst&uuml;tzt Aktionen auf Ger&auml;teebene. D.h. wird der Befehl auf ein Ger&auml;t angewendet werden auch alle verbundenen Kanaleintr&auml;ge gesichert.<br>
        Das Speichern der Datei erfolgt kumulativ. Wird ein Eintrag mehrfach in der selben Datei gespeichert so werden die Daten an diese angeh&auml;ngt.
        Der Nutzer kann den Zeitpunkt des Speichern bei Bedarf auslesen.<br>
        Der Inhalt der Datei kann verwendet werden um die Ger&auml;teeinstellungen wiederherzustellen. Er stellt alle Peers und Register des Eintrags wieder her.<br>
        Zw&auml;nge/Beschr&auml;nkungen:<br>
        vor dem zur&uuml;ckschreiben der Daten eines Eintrags muss das Ger&auml;t mit FHEM verbunden werden.<br>
        "restore" l&ouml;scht keine verkn&uuml;pften Kan&auml;le, es f&uuml;gt nur neue Peers hinzu.<br>
      </li>
      <li><B>listDevice</B><br>
          <ul>
              <li>bei einer CCU gibt es eine Liste der Devices, welche den ccu service zum zuweisen der IOs zurück<br>
                </li>
              <li>beim ActionDetector wird eine Komma geteilte Liste der Entities zurückgegeben<br>
                  get ActionDetector listDevice          # returns alle assigned entities<br>
                  get ActionDetector listDevice notActive# returns entities ohne status alive<br>
                  get ActionDetector listDevice alive    # returns entities mit status alive<br>
                  get ActionDetector listDevice unknown  # returns entities mit status unknown<br>
                  get ActionDetector listDevice dead     # returns entities mit status dead<br>
                  </li>
              </ul>
          </li>
    </ul><br>
    <a name="CUL_HMattr"></a><b>Attribute</b>
    <ul>
      <li><a href="#eventMap">eventMap</a></li>
      <li><a href="#do_not_notify">do_not_notify</a></li>
      <li><a href="#ignore">ignore</a></li>
      <li><a href="#dummy">dummy</a></li>
      <li><a href="#showtime">showtime</a></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
      <li><a name="#CUL_HMactAutoTry">actAutoTry</a>
         actAutoTry 0_off,1_on<br>
         setzen erlaubt dem ActionDetector ein statusrequest zu senden falls das Device dead markiert werden soll.
         Das Attribut kann fuer Devices nützlich sein, welche sich nicht von selbst zyklisch melden.
      </li>
      <li><a href="#actCycle">actCycle</a>
        actCycle &lt;[hhh:mm]|off&gt;<br>
        Bietet eine 'alive' oder besser 'not alive' Erkennung f&uuml;r Ger&auml;te. [hhh:mm] ist die maximale Zeit ohne Nachricht eines Ger&auml;ts. Wenn innerhalb dieser Zeit keine Nachricht empfangen wird so wird das Event"&lt;device&gt; is dead" generiert.
        Sendet das Ger&auml;t wieder so wird die Nachricht"&lt;device&gt; is alive" ausgegeben. <br>
        Diese Erkennung wird durch 'autocreate' f&uuml;r jedes Ger&auml;t mit zyklischer Statusmeldung angelegt.<br>
        Die Kontrollinstanz ist ein Pseudo-Ger&auml;t "ActionDetector" mit der HMId "000000".<br>
        Aufgrund von Performance&uuml;berlegungen liegt die Antwortverz&ouml;gerung bei 600 Sekunden (10min). Kann &uuml;ber das Attribut "actCycle" des "ActionDetector" kontrolliert werden.<br>
        Sobald die &Uuml;berwachung aktiviert wurde hat das HM-Ger&auml;t 2 Attribute:<br>
        <ul>
          actStatus: Aktivit&auml;tsstatus des Ger&auml;ts<br>
          actCycle: Detektionsspanne [hhh:mm]<br>
        </ul>
        Die gesamte Funktion kann &uuml;ber den "ActionDetector"-Eintrag &uuml;berpr&uuml;ft werden. Der Status aller Instanzen liegt im READING-Bereich.<br>
        Hinweis: Diese Funktion kann ebenfalls f&uuml;r Ger&auml;te ohne zyklische &Uuml;bertragung aktiviert werden. Es obliegt dem Nutzer eine vern&uuml;nftige Zeitspanne festzulegen.
      </li>

      <li><a name="#CUL_HMautoReadReg">autoReadReg</a><br>
        '0' autoReadReg wird ignorert.<br>
        '1' wird automatisch in getConfig ausgef&uuml;hrt f&uuml;r das Device nach jedem reboot von FHEM. <br>
        '2' wie '1' plus nach Power on.<br>
        '3' wie '2' plus update wenn auf das Device geschreiben wird.<br>
        '4' wie '3' plus fordert Status an, wenn es nicht korrekt erscheint<br>
        '5' pr&uuml;ft Registerlisten und peerlisten. Wenn diese nicht komplett sind wird ein update angefordert<br>
        '8_stateOnly' es wird nur der Status gepr&uuml;ft, updates f&uuml;r Register werden nicht gemacht.<br>
        Ausf&uuml;hrung wird verz&ouml;gert ausgef&uuml;hrt. Wenn das IO eine gewisse Last erreicht hat wird 
        das Kommando weiter verz&ouml;gert um eine &Uuml;berlast zu vermeiden.<br>
        Empfohlene Zusammenh&auml;nge bei Nutzung:<br>
        <ul>
          Benutze das Attribut f&uuml;r das Device, nicht f&uuml;r jeden einzelnen Kanal<br>
          Das Setzen auf Level 5 wird f&uuml;r alle Devices und Typen empfohlen, auch wakeup Devices.<br>
        </ul>
      </li>
      <li><a name="CUL_HMburstAccess">burstAccess</a><br>
        kann f&uuml;r eine Ger&auml;teinstanz gesetzt werden falls das Model bedingte Bursts erlaubt.
        Das Attribut deaktiviert den Burstbetrieb (0_off) was die Nachrichtenmenge des HMLAN reduziert
        und damit die Wahrscheinlichkeit einer &Uuml;berlast von HMLAN verringert.<br>
        Einschalten (1_auto) erlaubt k&uuml;rzere Reaktionszeiten eines Ger&auml;ts. Der Nutzer muss nicht warten
        bis das Ger&auml;t wach ist. <br>
        Zu beacht ist dass das Register "burstRx" im Ger&auml;t ebenfalls gesetzt werden muss.</li>
      <li><a name="CUL_HMexpert">expert</a><br>
        Dieses Attribut steuert die Sichtbarkeit der Werte. Damit wird die Darstellung der Ger&auml;teparameter kontrolliert.<br>
        3 Level k&ouml;nnen gew&auml;hlt werden:<br>
        <ul>
          0_off: Standard. Zeigt die h&auml;ufigst benutzten Paramter<br>
          1_on: Erweitert. Zeigt alle dekodierten Ger&auml;teparameter<br>
          2_full: Alles. Zeigt alle Parameter sowie Registerinformationen im Rohformat. <br>
        </ul>
        Wird 'expert' auf ein Ger&auml;t angewendet so gilt dies auch f&uuml;r alle verkn&uuml;pften Kan&auml;le.
        Kann &uuml;bergangen werden indem das Attribut ' expert' auch f&uuml;r den Ger&auml;tekanal gesetzt wird.<br>
        Das Attribut "showInternalValues" bei den globalen Werten muss ebenfalls &uuml;berpr&uuml;ft werden.
        "expert" macht sich diese Implementierung zu Nutze.
        Gleichwohl setzt "showInternalValues" - bei Definition - 'expert' außer Kraft .
      </li>
    <li><a name="#CUL_HMIOgrp">IOgrp</a><br>
        kann an Devices vergeben werden udn zeigt auf eine virtuelle ccu. Danach wird die ccu
        beim Senden das passende IO für das Device auswählen. Es ist notwendig, dass die virtuelle ccu
        definiert und alle erlaubten IOs eingetragen sind. Beim Senden wird die ccu prüfen
        welches IO operational ist und welches den besten rssi-faktor für das Device hat.<br>
        Optional kann ein bevorzugtes IO definiert werden. In diesem Fall wird es, wenn operational,
        genutzt - unabhängig von den rssi Werten.<br>
        Beispiel:<br>
        <ul><code>
          attr myDevice1 IOgrp vccu<br>
          attr myDevice2 IOgrp vccu:prefIO1,prefIO2,prefIO3<br>
        </code></ul>
        </li>
    <li><a name="#CUL_HMlevelRange">levelRange</a><br>
        nur f&uuml;r Dimmer! Der Dimmbereich wird eingeschr&auml;nkt. 
        Es ist gedacht um z.B. LED Lichter unterst&uuml;tzen welche mit 10% beginnen und bei 40% bereits das Maximum haben.
        levelrange normalisiert den Bereich entsprechend. D.h. set 100 wird physikalisch den Dimmer auf 40%, 
        1% auf 10% setzen. 0% schaltet physikalisch aus.<br>
        Beeinflusst werdne Kommndos on, up, down, toggle und pct. <b>Nicht</b> beeinflusst werden Kommandos
        die den Wert physikalisch setzen.<br>
        Zu beachten:<br>
        dimmer level von Peers gesetzt wird nicht beeinflusst. Dies wird durch Register konfiguriert.<br>
        Readings level k&ouml;nnte negative werden oder &uuml;ber 100%. Das kommt daher, dass physikalisch der Bereich 0-100%
        ist aber auf den logischen bereicht normiert wird.<br>
        Sind virtuelle Dimmer Kan&auml;le verf&uuml;gbar muss das Attribut f&uuml;r jeden Kanal gesetzt werden<br>
        Beispiel:<br>
        <ul><code>
          attr myChannel levelRange 0,40<br>
          attr myChannel levelRange 10,80<br>
        </code></ul>
        </li>
    <li><a name="#CUL_HMtempListTmpl">tempListTmpl</a><br>
        Setzt das Default f&uuml;r Heizungskontroller. Ist es nicht gesetzt wird der default filename genutzt und der name
        der entity als templatename. Z.B. ./tempList.cfg:RT_Clima<br> 
        Um das template nicht zu nutzen kann man es auf '0'setzen.<br>
        Format ist &lt;file&gt;:&lt;templatename&gt;. 
        </li>
      <li><a name="CUL_HMmodel">model</a>,
        <a name="subType">subType</a><br>
        Diese Attribute werden bei erfolgreichem Pairing automatisch gesetzt.
        Sie sollten nicht per Hand gesetzt werden und sind notwendig um Ger&auml;tenachrichten
        korrekt interpretieren oder senden zu k&ouml;nnen.</li>
      <li><a name="param">param</a><br>
        'param' definiert modelspezifische Verhalten oder Funktionen. Siehe "models" f&uuml;r Details.</li>
      <li><a name="CUL_HMmsgRepeat">msgRepeat</a><br>
        Definiert die Nummer an Wiederholungen falls ein Ger&auml;t nicht rechtzeitig antwortet. <br>
        F&uuml;r Ger&auml;te die nur den "Config"-Modus unterst&uuml;tzen sind Wiederholungen nicht erlaubt. <br>
        Bei Ger&auml;te mit wakeup-Modus wartet das Ger&auml;t bis zum n&auml;chsten Aufwachen. Eine l&auml;ngere Verz&ouml;gerung
        sollte in diesem Fall angedacht werden. <br>
        Wiederholen von Bursts hat Auswirkungen auf die HMLAN &Uuml;bertragungskapazit&auml;t.</li>
      <li><a name="rawToReadable">rawToReadable</a><br>
        Wird verwendet um Rohdaten von KFM100 in ein lesbares Fomrat zu bringen, basierend auf
        den gemessenen Werten. Z.B. langsames F&uuml;llen eines Tanks, w&auml;hrend die Werte mit <a href="#inform">inform</a>
        angezeigt werden. Man sieht:
        <ul>
          10 (bei 0%)<br>
          50 (bei 20%)<br>
          79 (bei 40%)<br>
          270 (bei 100%)<br>
        </ul>
        Anwenden dieser Werte: "attr KFM100 rawToReadable 10:0 50:20 79:40 270:100".
        FHEM f&uuml;r damit eine lineare Interpolation der Werte in den gegebenen Grenzen aus.
      </li>
      <li><a name="unit">unit</a><br>
        setzt die gemeldete Einheit des KFM100 falls 'rawToReadable' aktiviert ist. Z.B.<br>
        attr KFM100 unit Liter
      </li>
      <li><a name="autoReadReg">autoReadReg</a><br>
        '0' autoReadReg wird ignoriert.<br>
        '1' f&uuml;hrt ein "getConfig" f&uuml;r ein Ger&auml;t automatisch nach jedem Neustart von FHEM aus. <br>
        '2' verh&auml;lt sich wie '1',zus&auml;tzlich nach jedem power_on.<br>
        '3' wie '2', zus&auml;tzlich bei jedem Schreiben auf das Ger&auml;t<br>
        '4' wie '3' und versucht außerdem den Status abzufragen falls dieser nicht verf&uuml;gbar erscheint.<br>
        '5' kontrolliert 'reglist' und 'peerlist'. Falls das Auslesen unvollst&auml;ndig ist wird 'getConfig' ausgef&uuml;hrt<br>
        '8_stateOnly' aktualisiert nur Statusinformationen aber keine Konfigurationen wie Daten- oder
        Peerregister.<br>
        Ausf&uuml;hrung wird verz&ouml;gert um eine &Uuml;berlastung beim Start zu vermeiden . Daher werden Aktualisierung und Anzeige
        von Werten abh&auml;ngig von der Gr&ouml;ße der Datenbank verz&ouml;gert geschehen.<br>
        Empfehlungen und Einschr&auml;nkungen bei Benutzung:<br>
        <ul>
          Dieses Attribut nur auf ein Ger&auml;t oder Kanal 01 anwenden. Nicht auf einzelne Kan&auml;le eines mehrkanaligen
          Ger&auml;ts anwenden um eine doppelte Ausf&uuml;hrung zu vermeiden.<br>
          Verwendung bei Ger&auml;ten die nur auf den 'config'-Modus reagieren wird nicht empfohlen da die Ausf&uuml;hrung
          erst starten wird wenn der Nutzer die Konfiguration vornimmt<br>
          Anwenden auf Ger&auml;te mit 'wakeup'-Modus ist n&uuml;tzlich. Zu bedenken ist aber dass die Ausf&uuml;hrung
          bis zm "aufwachen" verz&ouml;gert wird.<br>
        </ul>
      </li>
      </ul> <br>
    <a name="CUL_HMparams"><b>verf&uuml;gbare Parameter f&uuml;r "param"</b></a>
    <ul>
      <li><B>HM-Sen-RD-O</B><br>
        offAtPon: nur Heizkan&auml;le: erzwingt Ausschalten der Heizung nach einem powerOn<br>
        onAtRain: nur Heizkan&auml;le: erzwingt Einschalten der Heizung bei Status 'rain' und Ausschalten bei Status 'dry'<br>
      </li>
      <li><B>virtuals</B><br>
        noOnOff: eine virtuelle Instanz wird den Status nicht &auml;ndern wenn ein Trigger empfangen wird. Ist dieser Paramter
        nicht gegeben so toggled die Instanz ihren Status mit jedem trigger zwischen An und Aus<br>
        msgReduce: falls gesetzt und der Kanal wird f&uuml;r <a ref="CUL_HMvalvePos"></a> genutzt wird jede Nachricht
        außer die der Ventilstellung verworfen um die Nachrichtenmenge zu reduzieren<br>
      </li>
      <li><B>blind</B><br>
        <B>levelInverse</B> w&auml;hrend HM 100% als offen und 0% als geschlossen behandelt ist dies evtl. nicht 
        intuitiv f&uuml;r den Nutzer. Defaut f&uuml;r 100% ist offen und wird als 'on'angezeigt. 
        Das Setzen des Parameters invertiert die Anzeige - 0% wird also offen und 100% ist geschlossen.<br>
        ACHTUNG: Die Anpassung betrifft nur Readings und Kommandos. <B>Register sind nicht betroffen.</B><br>
      </li>
    </ul><br>
    <a name="CUL_HMevents"><b>Erzeugte Events:</b></a>
    <ul>
      <li><B>Allgemein</B><br>
        recentStateType:[ack|info] # kann nicht verwendet werden um Nachrichten zu triggern<br>
        <ul>
          <li>ack zeigt an das eine Statusinformation aus einer Best&auml;tigung abgeleitet wurde</li>
          <li>info zeigt eine automatische Nachricht eines Ger&auml;ts an</li>
          <li><a name="CUL_HMsabotageAttackId"><b>sabotageAttackId</b></a><br>
            Alarmiert bei Konfiguration des Ger&auml;ts durch unbekannte Quelle<br></li>
          <li><a name="CUL_HMsabotageAttack"><b>sabotageAttack</b></a><br>
            Alarmiert bei Konfiguration des Ger&auml;ts welche nicht durch das System ausgel&ouml;st wurde<br></li>
          <li><a name="CUL_HMtrigDst"><b>trigDst_&lt;name&gt;: noConfig</b></a><br>
           Ein Sensor triggert ein Device welches nicht in seiner Peerliste steht. Die Peerliste ist nicht akuell<br></li>
        </ul>
      </li>
      <li><B>HM-CC-TC,ROTO_ZEL-STG-RM-FWT</B><br>
        T: $t H: $h<br>
        battery:[low|ok]<br>
        measured-temp $t<br>
        humidity $h<br>
        actuator $vp %<br>
        desired-temp $dTemp<br>
        desired-temp-manu $dTemp #Temperatur falls im manuellen Modus<br>
        desired-temp-cent $dTemp #Temperatur falls im Zentrale-Modus<br>
        windowopen-temp-%d %.1f (sensor:%s)<br>
        tempList$wd hh:mm $t hh:mm $t ...<br>
        displayMode temp-[hum|only]<br>
        displayTemp [setpoint|actual]<br>
        displayTempUnit [fahrenheit|celsius]<br>
        controlMode [auto|manual|central|party]<br>
        tempValveMode [Auto|Closed|Open|unknown]<br>
        param-change offset=$o1, value=$v1<br>
        ValveErrorPosition_for_$dname $vep %<br>
        ValveOffset_for_$dname : $of %<br>
        ValveErrorPosition $vep %<br>
        ValveOffset $of %<br>
        time-request<br>
        trig_&lt;src&gt; &lt;value&gt; #channel was triggered by &lt;src&gt; channel.
        Dieses Event h&auml;ngt vom kompletten Auslesen der Kanalkonfiguration ab, anderenfalls k&ouml;nnen Daten
        unvollst&auml;ndig oder fehlerhaft sein.<br>
        trigLast &lt;channel&gt; #letzter empfangener Trigger<br>
      </li>
      <li><B>HM-CC-RT-DN and HM-CC-RT-DN-BoM</B><br>
        state:T: $actTemp desired: $setTemp valve: $vp %<br>
        motorErr: [ok|ValveTight|adjustRangeTooLarge|adjustRangeTooSmall|communicationERR|unknown|lowBat|ValveErrorPosition]
        measured-temp $actTemp<br>
        desired-temp $setTemp<br>
        ValvePosition $vp %<br>
        mode [auto|manual|party|boost]<br>
        battery [low|ok]<br>
        batteryLevel $bat V<br>
        measured-temp $actTemp<br>
        desired-temp $setTemp<br>
        actuator $vp %<br>
        time-request<br>
        trig_&lt;src&gt; &lt;value&gt; #Kanal wurde durch &lt;src&gt; Kanal ausgel&ouml;ßt.
      </li>
      <li><B>HM-CC-VD,ROTO_ZEL-STG-RM-FSA</B><br>
        $vp %<br>
        battery:[critical|low|ok]<br>
        motorErr:[ok|blocked|loose|adjusting range too small|opening|closing|stop]<br>
        ValvePosition:$vp %<br>
        ValveErrorPosition:$vep %<br>
        ValveOffset:$of %<br>
        ValveDesired:$vp % # durch Temperatursteuerung gesetzt <br>
        operState:[errorTargetNotMet|onTarget|adjusting|changed] # operative Bedingung<br>
        operStateErrCnt:$cnt # Anzahl fehlgeschlagener Einstellungen<br>
      </li>
      <li><B>HM-CC-SCD</B><br>
        [normal|added|addedStrong]<br>
        battery [low|ok]<br>
      </li>
      <li><B>HM-SEC-SFA-SM</B><br>
        powerError [on|off]<br>
        sabotageError [on|off]<br>
        battery: [critical|low|ok]<br>
      </li>
      <li><B>HM-LC-BL1-PB-FM</B><br>
        motor: [opening|closing]<br>
      </li>
      <li><B>HM-LC-SW1-BA-PCB</B><br>
        battery: [low|ok]<br>
      </li>
      <li><B>HM-OU-LED16</B><br>
        color $value # in Hex - nur f&uuml;r Ger&auml;t<br>
        $value # in Hex - nur f&uuml;r Ger&auml;t<br>
        color [off|red|green|orange] # f&uuml;r Kanal <br>
        [off|red|green|orange] # f&uuml;r Kanal <br>
      </li>
      <li><B>HM-OU-CFM-PL</B><br>
        [on|off|$val]<br>
      </li>
      <li><B>HM-Sen-Wa-Od</B><br>
        $level%<br>
        level $level%<br>
      </li>
      <li><B>KFM100</B><br>
        $v<br>
        $cv,$unit<br>
        rawValue:$v<br>
        Sequence:$seq<br>
        content:$cv,$unit<br>
      </li>
      <li><B>KS550/HM-WDS100-C6-O</B><br>
        T: $t H: $h W: $w R: $r IR: $ir WD: $wd WDR: $wdr S: $s B: $b<br>
        temperature $t<br>
        humidity $h<br>
        windSpeed $w<br>
        windDirection $wd<br>
        windDirRange $wdr<br>
        rain $r<br>
        isRaining $ir<br>
        sunshine $s<br>
        brightness $b<br>
        unknown $p<br>
      </li>
      <li><B>HM-Sen-RD-O</B><br>
        lastRain: timestamp # kein Trigger wird erzeugt. Anfang des vorherigen Regen-Zeitstempels
        des Messwerts ist Ende des Regens. <br>
      </li>
      <li><B>THSensor und HM-WDC7000</B><br>
        T: $t H: $h AP: $ap<br>
        temperature $t<br>
        humidity $h<br>
        airpress $ap #nur HM-WDC7000<br>
      </li>
      <li><B>dimmer</B><br>
        overload [on|off]<br>
        overheat [on|off]<br>
        reduced [on|off]<br>
        dim: [up|down|stop]<br>
      </li>
      <li><B>motionDetector</B><br>
        brightness:$b<br>
        alive<br>
        motion on (to $dest)<br>
        motionCount $cnt _next:$nextTr"-"[0x0|0x1|0x2|0x3|15|30|60|120|240|0x9|0xa|0xb|0xc|0xd|0xe|0xf]<br>
        cover [closed|open] # nicht bei HM-Sec-MDIR<br>
        sabotageError [on|off] # nur bei HM-Sec-MDIR<br>
        battery [low|ok]<br>
        devState_raw.$d1 $d2<br>
      </li>
      <li><B>remote/pushButton/outputUnit</B><br>
        <ul> (to $dest) wird hinzugef&uuml;gt wenn der Knopf gepeert ist und keinen Broadcast sendet<br>
          Freigabe ist nur f&uuml;r verkn&uuml;pfte Kan&auml;le verf&uuml;gbar</ul>
        Btn$x onShort<br>
        Btn$x offShort<br>
        Btn$x onLong $counter<br>
        Btn$x offLong $counter<br>
        Btn$x onLongRelease $counter<br>
        Btn$x offLongRelease $counter<br>
        Btn$x onShort (to $dest)<br>
        Btn$x offShort (to $dest)<br>
        Btn$x onLong $counter (to $dest)<br>
        Btn$x offLong $counter (to $dest)<br>
        Btn$x onLongRelease $counter (to $dest)<br>
        Btn$x offLongRelease $counter (to $dest)<br>
      </li>
      <li><B>remote/pushButton</B><br>
        battery [low|ok]<br>
        trigger [Long|Short]_$no trigger event from channel<br>
      </li>
      <li><B>swi</B><br>
        Btn$x Short<br>
        Btn$x Short (to $dest)<br>
        battery: [low|ok]<br>
      </li>
      <li><B>switch/dimmer/blindActuator</B><br>
        $val<br>
        powerOn [on|off|$val]<br>
        [unknown|motor|dim] [up|down|stop]:$val<br>
        timedOn [running|off]<br> # "An" ist tempor&auml;r - z.B. mit dem 'on-for-timer' gestartet
      </li>
      <li><B>sensRain</B><br>
        $val<br>
        powerOn <br>
        level &lt;val&ge;<br>
        timedOn [running|off]<br> # "An" ist tempor&auml;r - z.B. mit dem 'on-for-timer' gestartet
        trigger [Long|Short]_$no trigger event from channel<br>
      </li>
      <li><B>smokeDetector</B><br>
        [off|smoke-Alarm|alive] # f&uuml;r Gruppen-Master<br>
        [off|smoke-forward|smoke-alarm] # f&uuml;r Gruppenmitglieder<br>
        [normal|added|addedStrong] #HM-CC-SCD<br>
        SDteam [add|remove]_$dname<br>
        battery [low|ok]<br>
        smoke_detect [none|&lt;src&gt;]<br>
        teamCall:from $src<br>
      </li>
      <li><B>threeStateSensor</B><br>
        [open|tilted|closed]<br>
        [wet|damp|dry] #nur HM-SEC-WDS<br>
        cover [open|closed] #HM-SEC-WDS und HM-Sec-RHS<br>
        alive yes<br>
        battery [low|ok]<br>
        contact [open|tilted|closed]<br>
        contact [wet|damp|dry] #nur HM-SEC-WDS<br>
        sabotageError [on|off] #nur HM-SEC-SC<br>
      </li>
      <li><B>winMatic</B><br>
        [locked|$value]<br>
        motorErr [ok|TurnError|TiltError]<br>
        direction [no|up|down|undefined]<br>
        charge [trickleCharge|charge|dischange|unknown]<br>
        airing [inactiv|$air]<br>
        course [tilt|close]<br>
        airing [inactiv|$value]<br>
        contact tesed<br>
      </li>
      <li><B>keyMatic</B><br>
        unknown:40<br>
        battery [low|ok]<br>
        uncertain [yes|no]<br>
        error [unknown|motor aborted|clutch failure|none']<br>
        lock [unlocked|locked]<br>
        [unlocked|locked|uncertain]<br>
      </li>
    </ul>
  <a name="CUL_HMinternals"><b>Internals</b></a>
  <ul>
    <li><B>aesCommToDev</B><br>
      Information über Erfolg und Fehler der AES Kommunikation zwischen IO-device und HM-Device<br>
    </li>
  </ul><br>
  <br>
  </ul>
=end html

=cut
