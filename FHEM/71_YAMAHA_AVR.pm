# $Id: 71_YAMAHA_AVR.pm 8124 2015-03-01 16:00:45Z markusbloch $
##############################################################################
#
#     71_YAMAHA_AVR.pm
#     An FHEM Perl module for controlling Yamaha AV-Receivers
#     via network connection. As the interface is standardized
#     within all Yamaha AV-Receivers, this module should work
#     with any receiver which has an ethernet or wlan connection.
#
#     Copyright by Markus Bloch
#     e-mail: Notausstieg0309@googlemail.com
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

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday sleep);
use HttpUtils;
 
sub YAMAHA_AVR_Get($@);
sub YAMAHA_AVR_Define($$);
sub YAMAHA_AVR_GetStatus($;$);
sub YAMAHA_AVR_Attr(@);
sub YAMAHA_AVR_ResetTimer($;$);
sub YAMAHA_AVR_Undefine($$);




###################################
sub
YAMAHA_AVR_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "YAMAHA_AVR_Get";
  $hash->{SetFn}     = "YAMAHA_AVR_Set";
  $hash->{DefFn}     = "YAMAHA_AVR_Define";
  $hash->{AttrFn}    = "YAMAHA_AVR_Attr";
  $hash->{UndefFn}   = "YAMAHA_AVR_Undefine";

  $hash->{AttrList}  = "do_not_notify:0,1 disable:0,1 request-timeout:1,2,3,4,5 volumeSteps:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20 model volume-smooth-change:0,1 volume-smooth-steps:1,2,3,4,5,6,7,8,9,10 ".
                      $readingFnAttributes;
}

###################################
sub
YAMAHA_AVR_GetStatus($;$)
{
    my ($hash, $local) = @_;
    my $name = $hash->{NAME};
    my $power;
   
    $local = 0 unless(defined($local));

    return "" if(!defined($hash->{helper}{ADDRESS}) or !defined($hash->{helper}{OFF_INTERVAL}) or !defined($hash->{helper}{ON_INTERVAL}));

    my $device = $hash->{helper}{ADDRESS};

    # get the model informations and available zones if no informations are available
    if(not defined($hash->{ACTIVE_ZONE}) or not defined($hash->{helper}{ZONES}) or not defined($hash->{MODEL}) or not defined($hash->{FIRMWARE}))
    {
		YAMAHA_AVR_getModel($hash);
        YAMAHA_AVR_ResetTimer($hash) unless($local == 1);
        return;
    }

    # get all available inputs and scenes if nothing is available
    if((not defined($hash->{helper}{INPUTS}) or length($hash->{helper}{INPUTS}) == 0))
    {
		YAMAHA_AVR_getInputs($hash);
    }
    
    my $zone = YAMAHA_AVR_getParamName($hash, $hash->{ACTIVE_ZONE}, $hash->{helper}{ZONES});
    
    if(not defined($zone))
    {
		YAMAHA_AVR_ResetTimer($hash) unless($local == 1);
		return "No Zone available";
    }
    
    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Basic_Status>GetParam</Basic_Status></$zone></YAMAHA_AV>", "statusRequest", "basicStatus");
    
    YAMAHA_AVR_ResetTimer($hash) unless($local == 1);
}

###################################
sub
YAMAHA_AVR_Get($@)
{
    my ($hash, @a) = @_;
    my $what;
    my $return;
	
    return "argument is missing" if(int(@a) != 2);
    
    $what = $a[1];
    
    if(exists($hash->{READINGS}{$what}))
    {
        if(defined($hash->{READINGS}{$what}))
        {
			return $hash->{READINGS}{$what}{VAL};
		}
		else
		{
			return "no such reading: $what";
		}
    }
    else
    {
		$return = "unknown argument $what, choose one of";
		
		foreach my $reading (keys %{$hash->{READINGS}})
		{
			$return .= " $reading:noArg";
		}
		
		return $return;
	}
}


###################################
sub
YAMAHA_AVR_Set($@)
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    
    # get the model informations and available zones if no informations are available
    if(not defined($hash->{ACTIVE_ZONE}) or not defined($hash->{helper}{ZONES}))
    {
		YAMAHA_AVR_getModel($hash);
    }

    # get all available inputs if nothing is available
    if(not defined($hash->{helper}{INPUTS}) or length($hash->{helper}{INPUTS}) == 0)
    {
		YAMAHA_AVR_getInputs($hash);
    }
    
    my $zone = YAMAHA_AVR_getParamName($hash, $hash->{ACTIVE_ZONE}, $hash->{helper}{ZONES});
    
    my $inputs_piped = defined($hash->{helper}{INPUTS}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{INPUTS}), 0) : "" ;
    my $inputs_comma = defined($hash->{helper}{INPUTS}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{INPUTS}), 1) : "" ;

    my $scenes_piped = defined($hash->{helper}{SCENES}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{SCENES}), 0) : "" ;
    my $scenes_comma = defined($hash->{helper}{SCENES}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{SCENES}), 1) : "" ;
    
    my $dsp_modes_piped = defined($hash->{helper}{DSP_MODES}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{DSP_MODES}), 0) : "" ;
    my $dsp_modes_comma = defined($hash->{helper}{DSP_MODES}) ? YAMAHA_AVR_Param2Fhem(lc($hash->{helper}{DSP_MODES}), 1) : "" ;
    
       
    return "No Argument given" if(!defined($a[1]));     
    
    my $what = $a[1];
    my $usage = "Unknown argument $what, choose one of ". "on:noArg ".
                                                          "off:noArg ".
                                                          "volumeStraight:slider,-80,1,16 ".
                                                          "volume:slider,0,1,100 ".
                                                          "volumeUp ".
                                                          "volumeDown ".
                                                          (exists($hash->{helper}{INPUTS})?"input:".$inputs_comma." ":"").
                                                          "mute:on,off,toggle ".
                                                          "remoteControl:setup,up,down,left,right,return,option,display,tunerPresetUp,tunerPresetDown,enter ".
                                                          (exists($hash->{helper}{SCENES})?"scene:".$scenes_comma." ":"").
                                                          (exists($hash->{ACTIVE_ZONE}) and $hash->{ACTIVE_ZONE} eq "mainzone" ? "straight:on,off 3dCinemaDsp:off,auto adaptiveDrc:off,auto ".(exists($hash->{helper}{DIRECT_TAG}) ? "direct:on,off " : "").(exists($hash->{helper}{DSP_MODES}) ? "dsp:".$dsp_modes_comma." " : "")."enhancer:on,off " : "").
                                                          (exists($hash->{helper}{CURRENT_INPUT_TAG}) ? "play:noArg pause:noArg stop:noArg skip:reverse,forward ".(exists($hash->{helper}{PLAY_CONTROL}) ? "shuffle:on,off repeat:off,one,all " : "") : "").
                                                          "sleep:off,30min,60min,90min,120min,last ".
                                                          "statusRequest:noArg";

    Log3 $name, 5, "YAMAHA_AVR ($name) - set ".join(" ", @a);
    
    if($what eq "on")
    {		
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Power>On</Power></Power_Control></$zone></YAMAHA_AV>" ,$what,undef);
    }
    elsif($what eq "off")
    {
        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Power>Standby</Power></Power_Control></$zone></YAMAHA_AV>", $what, undef);
    }
    elsif($what eq "input")
    {
        if(defined($a[2]))
        {
            if($hash->{READINGS}{power}{VAL} eq "on")
            {
                if(not $inputs_piped eq "")
                {
                    if($a[2] =~ /^($inputs_piped)$/)
                    {
                        my $command = YAMAHA_AVR_getParamName($hash, $a[2], $hash->{helper}{INPUTS});
                        if(defined($command) and length($command) > 0)
                        {
                             YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Input><Input_Sel>".$command."</Input_Sel></Input></$zone></YAMAHA_AV>", $what, $a[2]);
                        }
                        else
                        {
                            return "invalid input: ".$a[2];
                        } 
                    }
                    else
                    {
                        return $usage;
                    }
                }
                else
                {
                    return "No inputs are avaible. Please try an statusUpdate.";
                }
            }
            else
            {
                return "input can only be used when device is powered on";
            }
        }
        else
        {
            return $inputs_piped eq "" ? "No inputs are available. Please try an statusUpdate." : "No input parameter was given";
        }
    }
    elsif($what eq "scene")
    {
        if(defined($a[2]))
        {
            
            if(not $scenes_piped eq "")
            {
                if($a[2] =~ /^($scenes_piped)$/)
                {
                    my $command = YAMAHA_AVR_getParamName($hash, $a[2], $hash->{helper}{SCENES});
                    
                    if(defined($command) and length($command) > 0)
                    {
                        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Scene><Scene_Sel>".$command."</Scene_Sel></Scene></$zone></YAMAHA_AV>", $what, $a[2]);
                    }
                    else
                    {
                        return "invalid input: ".$a[2];
                    }
                }
                else
                {
                    return $usage;
                }
            }
            else
            {
                return "No scenes are avaible. Please try an statusUpdate.";
            }
        }
        else
        {
            return $scenes_piped eq "" ? "No scenes are available. Please try an statusUpdate." : "No scene parameter was given";
        }
    }  
    elsif($what eq "mute")
    {
        if(defined($a[2]))
        {
            if($hash->{READINGS}{power}{VAL} eq "on")
            {
                # Depending on the status response, use the short or long Volume command
                my $volume_cmd = (exists($hash->{helper}{USE_SHORT_VOL_CMD}) and $hash->{helper}{USE_SHORT_VOL_CMD} eq "1" ? "Vol" : "Volume");
            
                if( $a[2] eq "on" or ($a[2] eq "toggle" and ReadingsVal($hash->{NAME}, "mute", "off") eq "off"))
                {
                    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Mute>On</Mute></$volume_cmd></$zone></YAMAHA_AV>", $what, "on");
                }
                elsif($a[2] eq "off" or ($a[2] eq "toggle" and ReadingsVal($hash->{NAME}, "mute", "off") eq "on"))
                {
                    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Mute>Off</Mute></$volume_cmd></$zone></YAMAHA_AV>", $what, "off"); 
                }
                else
                {
                    return $usage;
                }   
            }
            else
            {
                return "mute can only used when device is powered on";
            }
        }
    }
    elsif($what =~ /^(volumeStraight|volume|volumeUp|volumeDown)$/)
    {
        my $target_volume;
        
        if($what eq "volume" and $a[2] >= 0 &&  $a[2] <= 100)
        {
            $target_volume = YAMAHA_AVR_volume_rel2abs($a[2]);
        }
        elsif($what eq "volumeDown")
        {
            $target_volume = YAMAHA_AVR_volume_rel2abs($hash->{READINGS}{volume}{VAL} - ((defined($a[2]) and $a[2] =~ /^\d+$/) ? $a[2] : AttrVal($hash->{NAME}, "volumeSteps",5)));
        }
        elsif($what eq "volumeUp")
        {
            $target_volume = YAMAHA_AVR_volume_rel2abs($hash->{READINGS}{volume}{VAL} + ((defined($a[2]) and $a[2] =~ /^\d+$/) ? $a[2] : AttrVal($hash->{NAME}, "volumeSteps",5)));
        }
        else
        {
            $target_volume = $a[2];
        }
         
        # if lower than minimum (-80.5) or higher than max (16.5) set target volume to the corresponding boundary
        $target_volume = -80.5 if(defined($target_volume) and $target_volume < -80.5);
        $target_volume = 16.5 if(defined($target_volume) and $target_volume > 16.5);
        
        Log3 $name, 4, "YAMAHA_AVR ($name) - new target volume: $target_volume";
        
        if(defined($target_volume) )
        {
            if($hash->{READINGS}{power}{VAL} eq "on")
            {
                # Depending on the status response, use the short or long Volume command
                my $volume_cmd = (exists($hash->{helper}{USE_SHORT_VOL_CMD}) and $hash->{helper}{USE_SHORT_VOL_CMD} eq "1" ? "Vol" : "Volume");
                
                if(AttrVal($name, "volume-smooth-change", "0") eq "1")
                {
                
                    my $steps = AttrVal($name, "volume-smooth-steps", 5);
                    my $diff = int(($target_volume - $hash->{READINGS}{volumeStraight}{VAL}) / $steps / 0.5) * 0.5;
                    my $current_volume = $hash->{READINGS}{volumeStraight}{VAL};

                    if($diff > 0)
                    {
                        Log3 $name, 4, "YAMAHA_AVR ($name) - use smooth volume change (with $steps steps of +$diff volume change to reach $target_volume)";
                    }
                    else
                    {
                        Log3 $name, 4, "YAMAHA_AVR ($name) - use smooth volume change (with $steps steps of $diff volume change to reach $target_volume)";
                    }
            
                    # Only if a volume reading exists and smoohing is really needed (step difference is not zero)
                    if(defined($hash->{READINGS}{volumeStraight}{VAL}) and $diff != 0)
                    {        
                        Log3 $name, 4, "YAMAHA_AVR ($name) - set volume to ".($current_volume + $diff)." dB (target is $target_volume dB)";
                        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Lvl><Val>".(($current_volume + $diff)*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></$volume_cmd></$zone></YAMAHA_AV>", "volume", ($current_volume + $diff)."|$diff|$target_volume" );
                    }
                    else
                    {
                        # Set the desired volume
                        Log3 $name, 4, "YAMAHA_AVR ($name) - set volume to ".$target_volume." dB";
                        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Lvl><Val>".($target_volume*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></$volume_cmd></$zone></YAMAHA_AV>", "volume", "$target_volume|0|$target_volume");
                    }
                }
                else
                {
                    # Set the desired volume
                    Log3 $name, 4, "YAMAHA_AVR ($name) - set volume to ".$target_volume." dB";
                    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Lvl><Val>".($target_volume*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></$volume_cmd></$zone></YAMAHA_AV>", "volume", "$target_volume|0|$target_volume");
                }
            }
            else
            {
                return "volume can only be used when device is powered on";
            }
        }
    }
    elsif($what eq "dsp")
    {
        if(defined($a[2]))
        {
            if(not $dsp_modes_piped eq "")
            {
                if($a[2] =~ /^($dsp_modes_piped)$/)
                {
                    my $command = YAMAHA_AVR_getParamName($hash, $a[2],$hash->{helper}{DSP_MODES});
                    
                    if(defined($command) and length($command) > 0)
                    {
                        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><Program_Sel><Current><Sound_Program>$command</Sound_Program></Current></Program_Sel></Surround></$zone></YAMAHA_AV>", $what, $a[2]);
                    }
                    else
                    {
                        return "invalid dsp mode: ".$a[2];
                    }
                }
                else
                {
                    return $usage;
                }
            }
            else
            {
                return "No DSP presets are avaible. Please try an statusUpdate.";
            }
        }
        else
        {
            return $dsp_modes_piped eq "" ? "No dsp presets are available. Please try an statusUpdate." : "No dsp preset was given";
        }
    }
    elsif($what eq "straight")
    {
        if($a[2] eq "on")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><Program_Sel><Current><Straight>On</Straight></Current></Program_Sel></Surround></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><Program_Sel><Current><Straight>Off</Straight></Current></Program_Sel></Surround></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        } 
    }
    elsif($what eq "3dCinemaDsp")
    {  
        if($a[2] eq "auto")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><_3D_Cinema_DSP>Auto</_3D_Cinema_DSP></Surround></$zone></YAMAHA_AV>", "3dCinemaDsp", "auto");
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><_3D_Cinema_DSP>Off</_3D_Cinema_DSP></Surround></$zone></YAMAHA_AV>", "3dCinemaDsp", "off");
        }
        else
        {
            return $usage;
        }      
    }
    elsif($what eq "adaptiveDrc")
    {    
        if($a[2] eq "auto")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><Adaptive_DRC>Auto</Adaptive_DRC></Sound_Video></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><Adaptive_DRC>Off</Adaptive_DRC></Sound_Video></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "enhancer")
    {
        if($a[2] eq "on")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><Program_Sel><Current><Enhancer>On</Enhancer></Current></Program_Sel></Surround></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Surround><Program_Sel><Current><Enhancer>Off</Enhancer></Current></Program_Sel></Surround></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "direct" )
    {
        if(exists($hash->{helper}{DIRECT_TAG}))
        {                
            if($a[2] eq "on")
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><".$hash->{helper}{DIRECT_TAG}."><Mode>On</Mode></".$hash->{helper}{DIRECT_TAG}."></Sound_Video></$zone></YAMAHA_AV>", $what, $a[2]);
            }
            elsif($a[2] eq "off")
            {
                YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Sound_Video><".$hash->{helper}{DIRECT_TAG}."><Mode>Off</Mode></".$hash->{helper}{DIRECT_TAG}."></Sound_Video></$zone></YAMAHA_AV>", $what, $a[2]);
            }
            else
            {
                return $usage;
            }  
        }
        else
        {
            return "Unable to execute \"$what ".$a[2]."\" - please execute a statusUpdate first before you use this command";
        } 
    }
    elsif($what eq "sleep")
    {
        if($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Sleep>Off</Sleep></Power_Control></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "30min")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Sleep>30 min</Sleep></Power_Control></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "60min")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Sleep>60 min</Sleep></Power_Control></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "90min")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Sleep>90 min</Sleep></Power_Control></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "120min")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Sleep>120 min</Sleep></Power_Control></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "last")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Sleep>Last</Sleep></Power_Control></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        } 
    }
    elsif($what eq "remoteControl")
    {
        # the RX-Vx75 series use a different tag name to access the remoteControl commands
        my $control_tag = (exists($hash->{MODEL}) and $hash->{MODEL} =~ /RX-V\d75/ ? "Cursor_Control" : "List_Control");
        
        if($a[2] eq "up")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Cursor>Up</Cursor></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "down")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Cursor>Down</Cursor></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "left")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Cursor>Left</Cursor></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "right")
        {
            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Cursor>Right</Cursor></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "display")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Menu_Control>Display</Menu_Control></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "return")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Cursor>Return</Cursor></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "enter")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Cursor>Sel</Cursor></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "setup")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Menu_Control>On Screen</Menu_Control></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "option")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><$zone><$control_tag><Menu_Control>Option</Menu_Control></$control_tag></$zone></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "tunerPresetUp")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Preset><Preset_Sel>Up</Preset_Sel></Preset></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "tunerPresetDown")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Preset><Preset_Sel>Down</Preset_Sel></Preset></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "play" and exists($hash->{helper}{CURRENT_INPUT_TAG}))
    {
         YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><".$hash->{helper}{CURRENT_INPUT_TAG}."><Play_Control><Playback>Play</Playback></Play_Control></".$hash->{helper}{CURRENT_INPUT_TAG}."></YAMAHA_AV>", $what, $a[2]);
    }
    elsif($what eq "stop" and exists($hash->{helper}{CURRENT_INPUT_TAG}))
    {
         YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><".$hash->{helper}{CURRENT_INPUT_TAG}."><Play_Control><Playback>Stop</Playback></Play_Control></".$hash->{helper}{CURRENT_INPUT_TAG}."></YAMAHA_AV>", $what, $a[2]);
    }
    elsif($what eq "pause" and exists($hash->{helper}{CURRENT_INPUT_TAG}))
    {
         YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><".$hash->{helper}{CURRENT_INPUT_TAG}."><Play_Control><Playback>Pause</Playback></Play_Control></".$hash->{helper}{CURRENT_INPUT_TAG}."></YAMAHA_AV>", $what, $a[2]);
    }
    elsif($what eq "skip")
    {
        if($a[2] eq "forward")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><".$hash->{helper}{CURRENT_INPUT_TAG}."><Play_Control><Playback>Skip Fwd</Playback></Play_Control></".$hash->{helper}{CURRENT_INPUT_TAG}."></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "reverse")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><".$hash->{helper}{CURRENT_INPUT_TAG}."><Play_Control><Playback>Skip Rev</Playback></Play_Control></".$hash->{helper}{CURRENT_INPUT_TAG}."></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "shuffle")
    {
        if($a[2] eq "on")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><".$hash->{helper}{CURRENT_INPUT_TAG}."><Play_Control><Play_Mode><Shuffle>On</Shuffle></Play_Mode></Play_Control></".$hash->{helper}{CURRENT_INPUT_TAG}."></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><".$hash->{helper}{CURRENT_INPUT_TAG}."><Play_Control><Play_Mode><Shuffle>Off</Shuffle></Play_Mode></Play_Control></".$hash->{helper}{CURRENT_INPUT_TAG}."></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "repeat")
    {
        if($a[2] eq "one")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><".$hash->{helper}{CURRENT_INPUT_TAG}."><Play_Control><Play_Mode><Repeat>One</Repeat></Play_Mode></Play_Control></".$hash->{helper}{CURRENT_INPUT_TAG}."></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "off")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><".$hash->{helper}{CURRENT_INPUT_TAG}."><Play_Control><Play_Mode><Repeat>Off</Repeat></Play_Mode></Play_Control></".$hash->{helper}{CURRENT_INPUT_TAG}."></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "all")
        {
            YAMAHA_AVR_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><".$hash->{helper}{CURRENT_INPUT_TAG}."><Play_Control><Play_Mode><Repeat>All</Repeat></Play_Mode></Play_Control></".$hash->{helper}{CURRENT_INPUT_TAG}."></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
            return $usage;
        }
    }
    elsif($what eq "statusRequest")
    {
        YAMAHA_AVR_GetStatus($hash, 1);
    }
    else
    {
        return $usage;
    }
    
}

#############################
sub
YAMAHA_AVR_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    my $name = $hash->{NAME};
    
    if(! @a >= 4)
    {
        my $msg = "wrong syntax: define <name> YAMAHA_AVR <ip-or-hostname> [<zone>] [<ON-statusinterval>] [<OFF-statusinterval>] ";
        Log3 $name, 2, $msg;
        return $msg;
    }

    my $address = $a[2];
  
    $hash->{helper}{ADDRESS} = $address;

    # if a zone was given, use it, otherwise use the mainzone
    if(defined($a[3]))
    {
        $hash->{helper}{SELECTED_ZONE} = $a[3];
    }
    else
    {
		$hash->{helper}{SELECTED_ZONE} = "mainzone";
    }
    
    # if an update interval was given which is greater than zero, use it.
    if(defined($a[4]) and $a[4] > 0)
    {
		$hash->{helper}{OFF_INTERVAL} = $a[4];
    }
    else
    {
		$hash->{helper}{OFF_INTERVAL} = 30;
    }
      
    if(defined($a[5]) and $a[5] > 0)
    {
		$hash->{helper}{ON_INTERVAL} = $a[5];
    }
    else
    {
		$hash->{helper}{ON_INTERVAL} = $hash->{helper}{OFF_INTERVAL};
    }
    
    
    # In case of a redefine, check the zone parameter if the specified zone exist, otherwise use the main zone
    if(defined($hash->{helper}{ZONES}) and length($hash->{helper}{ZONES}) > 0)
    {
		if(defined(YAMAHA_AVR_getParamName($hash, lc $hash->{helper}{SELECTED_ZONE}, $hash->{helper}{ZONES})))
		{
		    $hash->{ACTIVE_ZONE} = lc $hash->{helper}{SELECTED_ZONE};
		    YAMAHA_AVR_getInputs($hash); 
		}
		else
		{
		    Log3 $name, 2, "YAMAHA_AVR ($name) - selected zone >>".$hash->{helper}{SELECTED_ZONE}."<< is not available on device ".$hash->{NAME}.". Using Main Zone instead";
		    $hash->{ACTIVE_ZONE} = "mainzone";
		    YAMAHA_AVR_getInputs($hash);
		}
    }
    
    # set the volume-smooth-change attribute only if it is not defined, so no user values will be overwritten
    #
    # own attribute values will be overwritten anyway when all attr-commands are executed from fhem.cfg
    $attr{$name}{"volume-smooth-change"} = "1" unless(exists($attr{$name}{"volume-smooth-change"}));

    unless(exists($hash->{helper}{AVAILABLE}) and ($hash->{helper}{AVAILABLE} == 0))
    {
    	$hash->{helper}{AVAILABLE} = 1;
    	readingsSingleUpdate($hash, "presence", "present", 1);
    }

    # start the status update timer
    $hash->{helper}{DISABLED} = 0 unless(exists($hash->{helper}{DISABLED}));
	YAMAHA_AVR_ResetTimer($hash,0);
  
    return undef;
}


##########################
sub
YAMAHA_AVR_Attr(@)
{
    my @a = @_;
    my $hash = $defs{$a[1]};

    if($a[0] eq "set" && $a[2] eq "disable")
    {
        if($a[3] eq "0")
        {
            $hash->{helper}{DISABLED} = 0;
            YAMAHA_AVR_GetStatus($hash, 1);
        }
        elsif($a[3] eq "1")
        {
            $hash->{helper}{DISABLED} = 1;
        }
    }
    elsif($a[0] eq "del" && $a[2] eq "disable")
    {
        $hash->{helper}{DISABLED} = 0;
        YAMAHA_AVR_GetStatus($hash, 1);
    }

    # Start/Stop Timer according to new disabled-Value
    YAMAHA_AVR_ResetTimer($hash);
    
    return undef;
}

#############################
sub
YAMAHA_AVR_Undefine($$)
{
    my($hash, $name) = @_;

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);
    return undef;
}


############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################



#############################
# sends a command to the receiver via HTTP
sub
YAMAHA_AVR_SendCommand($@)
{
    my ($hash, $data,$cmd,$arg,$can_fail) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    my $blocking = 0;
    
    if($cmd ne "statusRequest" and $hash->{helper}{AVAILABLE} == 1)
    {
        $blocking = 1;
    }

     
    # In case any URL changes must be made, this part is separated in this function".
    
    if($blocking == 1)
    {
        Log3 $name, 5, "YAMAHA_AVR ($name) - execute blocking \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\" on $name: $data";
        my $param = {
                                    url        => "http://".$address."/YamahaRemoteControl/ctrl",
                                    timeout    => AttrVal($name, "request-timeout", 4),
                                    noshutdown => 1,
                                    data       => "<?xml version=\"1.0\" encoding=\"utf-8\"?>".$data,
                                    loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
                                    hash       => $hash,
                                    cmd        => $cmd,
                                    arg        => $arg,
                                    can_fail   => $can_fail
                                };
                                
        my ($err, $data) = HttpUtils_BlockingGet($param);
        YAMAHA_AVR_ParseResponse($param, $err, $data);
    }
    else
    {
         Log3 $name, 5, "YAMAHA_AVR ($name) - execute nonblocking \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\" on $name: $data";
           
         HttpUtils_NonblockingGet({
                                    url        => "http://".$address."/YamahaRemoteControl/ctrl",
                                    timeout    => AttrVal($name, "request-timeout", 4),
                                    noshutdown => 1,
                                    data       => "<?xml version=\"1.0\" encoding=\"utf-8\"?>".$data,
                                    loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
                                    hash       => $hash,
                                    cmd        => $cmd,
                                    arg        => $arg,
                                    can_fail   => $can_fail,
                                    callback   => \&YAMAHA_AVR_ParseResponse
                                }
        ); 
    }
}

#############################
# parses the receiver response
sub
YAMAHA_AVR_ParseResponse ($$$)
{
    my ( $param, $err, $data ) = @_;    
    
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $cmd = $param->{cmd};
    my $arg = $param->{arg};
    my $can_fail = $param->{can_fail};
    
    if(exists($param->{code}))
    {
        Log3 $name, 5, "YAMAHA_AVR ($name) - received HTTP code ".$param->{code}." for command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\"";
        
        if($cmd eq "statusRequest" and $arg eq "playShuffle" and $param->{code} ne "200")
        {
            delete($hash->{helper}{PLAY_CONTROL}) if(exists($hash->{helper}{PLAY_CONTROL}));
        }
    }
    
    if($err ne "" and not $can_fail)
    {
        Log3 $name, 5, "YAMAHA_AVR ($name) - could not execute command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": $err";

		if((not exists($hash->{helper}{AVAILABLE})) or (exists($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 1))
		{
			Log3 $name, 3, "YAMAHA_AVR ($name) - could not execute command on device $name. Please turn on your device in case of deactivated network standby or check for correct hostaddress.";
			readingsSingleUpdate($hash, "presence", "absent", 1);
            readingsSingleUpdate($hash, "state", "absent", 1);
		}  

        $hash->{helper}{AVAILABLE} = 0;
    }
    elsif($data ne "")
    {
        Log3 $name, 5, "YAMAHA_AVR ($name) - got response for \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": $data";
    
		if (defined($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 0)
		{
			Log3 $name, 3, "YAMAHA_AVR ($name) - device $name reappeared";
			readingsSingleUpdate($hash, "presence", "present", 1);            
		}
        
        $hash->{helper}{AVAILABLE} = 1;
        
        if(not $data =~ / RC="0"/ and $data =~ / RC="(\d+)"/)
		{
			# if the returncode isn't 0, than the command was not successful
			Log3 $name, 3, "YAMAHA_AVR ($name) - Could not execute \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": received return code $1";
		}
        
        readingsBeginUpdate($hash);
        
        if($cmd eq "statusRequest")
        {
            if($arg eq "unitDescription")
            {
                if($data =~ /<URL>(.+?)<\/URL>/)
                { 
                    $hash->{helper}{XML} = $1;
                }
                else
                {
                    $hash->{helper}{XML} = "/YamahaRemoteControl/desc.xml";
                }
                
                Log3 $name, 5, "YAMAHA_AVR ($name) - requesting unit description XML: http://".$hash->{helper}{ADDRESS}.$hash->{helper}{XML};
                
                HttpUtils_NonblockingGet({
                            url        => "http://".$hash->{helper}{ADDRESS}.$hash->{helper}{XML} ,
                            timeout    => AttrVal($name, "request-timeout", 4),
                            noshutdown => 1,
                            loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
                            hash       => $hash,
                            callback   => \&YAMAHA_AVR_ParseXML
                        }
                );  
            }
            elsif($arg eq "systemConfig")
            {
                if($data =~ /<Model_Name>(.+?)<\/Model_Name>.*<System_ID>(.+?)<\/System_ID>.*<Version>.*<Main>(.+?)<\/Main>.*<Sub>(.+?)<\/Sub>.*?<\/Version>/)
                {
                    $hash->{MODEL} = $1;
                    $hash->{SYSTEM_ID} = $2;
                    $hash->{FIRMWARE} = $3."  ".$4;
                }
                elsif($data =~ /<Model_Name>(.+?)<\/Model_Name>.*<System_ID>(.+?)<\/System_ID>.*<Version>(.+?)<\/Version>/)
                {
                    $hash->{MODEL} = $1;
                    $hash->{SYSTEM_ID} = $2;
                    $hash->{FIRMWARE} = $3;
                }
                
                $attr{$name}{"model"} = $hash->{MODEL};
            }
            elsif($arg eq "getInputs")
            {
                delete($hash->{helper}{INPUTS}) if(exists($hash->{helper}{INPUTS}));

                while($data =~ /<Param>(.+?)<\/Param>/gc)
                {
                    if(defined($hash->{helper}{INPUTS}) and length($hash->{helper}{INPUTS}) > 0)
                    {
                        $hash->{helper}{INPUTS} .= "|";
                    }
                    Log3 $name, 4, "YAMAHA_AVR ($name) - found input: $1";
                    $hash->{helper}{INPUTS} .= $1;
                }
                
                $hash->{helper}{INPUTS} = join("|", sort split("\\|", $hash->{helper}{INPUTS}));  
            }
            elsif($arg eq "getScenes")
            {
                delete($hash->{helper}{SCENES}) if(exists($hash->{helper}{SCENES}));
             
                # get all available scenes from response
                while($data =~ /<Item_\d+>.*?<Param>(.+?)<\/Param>.*?<RW>(\w+)<\/RW>.*?<\/Item_\d+>/gc)
                {
                  # check if the RW-value is "W" (means: writeable => can be set through FHEM)
                    if($2 eq "W")
                    {
                        if(defined($hash->{helper}{SCENES}) and length($hash->{helper}{SCENES}) > 0)
                        {
                            $hash->{helper}{SCENES} .= "|";
                        }
                        Log3 $name, 4, "YAMAHA_AVR ($name) - found scene: $1";
                        $hash->{helper}{SCENES} .= $1;
                    }
                }
            }
            elsif($arg eq "basicStatus")
            {
                if($data =~ /<Power>(.+?)<\/Power>/)
                {
                    my $power = $1;
                   
                    if($power eq "Standby")
                    {	
                        $power = "off";
                    }
                    readingsBulkUpdate($hash, "power", lc($power));
                    readingsBulkUpdate($hash, "state", lc($power));
                }
                
                # current volume and mute status
                if($data =~ /<Volume><Lvl><Val>(.+?)<\/Val><Exp>(.+?)<\/Exp><Unit>.+?<\/Unit><\/Lvl><Mute>(.+?)<\/Mute>.*?<\/Volume>/)
                {
                    readingsBulkUpdate($hash, "volumeStraight", ($1 / 10 ** $2));
                    readingsBulkUpdate($hash, "volume", YAMAHA_AVR_volume_abs2rel(($1 / 10 ** $2)));
                    readingsBulkUpdate($hash, "mute", lc($3));
                    
                    $hash->{helper}{USE_SHORT_VOL_CMD} = "0";
                }
                elsif($data =~ /<Vol><Lvl><Val>(.+?)<\/Val><Exp>(.+?)<\/Exp><Unit>.+?<\/Unit><\/Lvl><Mute>(.+?)<\/Mute>.*?<\/Vol>/)
                {
                    readingsBulkUpdate($hash, "volumeStraight", ($1 / 10 ** $2));
                    readingsBulkUpdate($hash, "volume", YAMAHA_AVR_volume_abs2rel(($1 / 10 ** $2)));
                    readingsBulkUpdate($hash, "mute", lc($3));
                    
                    $hash->{helper}{USE_SHORT_VOL_CMD} = "1";
                }
                
                # (only available in zones other than mainzone) absolute or relative volume change to the mainzone
                if($data =~ /<Volume>.*?<Output>(.+?)<\/Output>.*?<\/Volume>/)
                {
                    readingsBulkUpdate($hash, "output", lc($1));
                }
                elsif($data =~ /<Vol>.*?<Output>(.+?)<\/Output>.*?<\/Vol>/)
                {
                    readingsBulkUpdate($hash, "output", lc($1));
                }
                else
                {
                    # delete the reading if this information is not available
                    delete($hash->{READINGS}{output}) if(defined($hash->{READINGS}{output}));
                }
                
                # current input same as the corresponding set command name
                if($data =~ /<Input_Sel>(.+?)<\/Input_Sel>/)
                {
                    $hash->{helper}{CURRENT_INPUT_TAG} = $1;
                    
                    readingsBulkUpdate($hash, "input", YAMAHA_AVR_Param2Fhem(lc($1), 0));
                    
                    if($data =~ /<Src_Name>(.+?)<\/Src_Name>/)
                    {
                        Log3 $name, 4, "YAMAHA_AVR ($name) - check for extended input informations on <$1>";
                    
                        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$1><Play_Info>GetParam</Play_Info></$1></YAMAHA_AV>", "statusRequest", "playInfo", 1);
                        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$1><Play_Control><Play_Mode><Repeat>GetParam</Repeat></Play_Mode></Play_Control></$1></YAMAHA_AV>", "statusRequest", "playRepeat", 1);
                        YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$1><Play_Control><Play_Mode><Shuffle>GetParam</Shuffle></Play_Mode></Play_Control></$1></YAMAHA_AV>", "statusRequest", "playShuffle", 1);
                    }
                    else
                    {
                        readingsBulkUpdate($hash, "currentAlbum", "", 0);
                        readingsBulkUpdate($hash, "currentTitle", "", 0);
                        readingsBulkUpdate($hash, "currentChannel", "", 0);
                        readingsBulkUpdate($hash, "currentStation", "", 0);
                        readingsBulkUpdate($hash, "currentArtist", "", 0);
                    }
                }
                
                # input name as it is displayed on the receivers front display
                if($data =~ /<Input>.*?<Title>\s*(.+?)\s*<\/Title>.*?<\/Input>/)
                {
                    readingsBulkUpdate($hash, "inputName", $1);
                }
                elsif($data =~ /<Input>.*?<Input_Sel_Title>\s*(.+?)\s*<\/Input_Sel_Title>.*?<\/Input>/)
                {
                    readingsBulkUpdate($hash, "inputName", $1);
                }
                
                if($data =~ /<Surround>.*?<Current>.*?<Straight>(.+?)<\/Straight>.*?<\/Current>.*?<\/Surround>/)
                {
                    readingsBulkUpdate($hash, "straight", lc($1));
                }
                
                if($data =~ /<Surround>.*?<Current>.*?<Enhancer>(.+?)<\/Enhancer>.*?<\/Current>.*?<\/Surround>/)
                {
                    readingsBulkUpdate($hash, "enhancer", lc($1));
                }
                
                if($data =~ /<Surround>.*?<Current>.*?<Sound_Program>(.+?)<\/Sound_Program>.*?<\/Current>.*?<\/Surround>/)
                {
                    readingsBulkUpdate($hash, "dsp", YAMAHA_AVR_Param2Fhem($1, 0));
                }
               
                if($data =~ /<Surround>.*?<_3D_Cinema_DSP>(.+?)<\/_3D_Cinema_DSP>.*?<\/Surround>/)
                {
                    readingsBulkUpdate($hash, "3dCinemaDsp", lc($1));
                }
                
                if($data =~ /<Sound_Video>.*?<Adaptive_DRC>(.+?)<\/Adaptive_DRC>.*?<\/Sound_Video>/)
                {
                    readingsBulkUpdate($hash, "adaptiveDrc", lc($1));
                }
                
                if($data =~ /<Power_Control>.*?<Sleep>(.+?)<\/Sleep>.*?<\/Power_Control>/)
                {
                    readingsBulkUpdate($hash, "sleep", YAMAHA_AVR_Param2Fhem($1, 0));
                }
                
                if($data =~ /<Sound_Video>.*?<Direct>.*?<Mode>(.+?)<\/Mode>.*?<\/Direct>.*?<\/Sound_Video>/)
                {
                    readingsBulkUpdate($hash, "direct", lc($1));
                    $hash->{helper}{DIRECT_TAG} = "Direct"; 
                }
                elsif($data =~ /<Sound_Video>.*?<Pure_Direct>.*?<Mode>(.+?)<\/Mode>.*?<\/Pure_Direct>.*?<\/Sound_Video>/)
                {
                    readingsBulkUpdate($hash, "direct", lc($1));
                    $hash->{helper}{DIRECT_TAG} = "Pure_Direct";
                }
                else
                {
                    delete($hash->{helper}{DIRECT_TAG}) if(exists($hash->{helper}{DIRECT_TAG}));
                }
            }
            elsif($arg eq "playInfo")
            {
                if($data =~ /<Meta_Info>.*?<Artist>(.+?)<\/Artist>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentArtist", YAMAHA_AVR_html2txt($1));
                }
                else
                {
                    readingsBulkUpdate($hash, "currentArtist", "", 0);
                }

                if($data =~ /<Meta_Info>.*?<Station>(.+?)<\/Station>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentStation", YAMAHA_AVR_html2txt($1));
                }
                elsif($data =~ /<Meta_Info>.*?<Program_Service>(.+?)<\/Program_Service>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentStation", YAMAHA_AVR_html2txt($1));
                }
                else
                {
                    readingsBulkUpdate($hash, "currentStation", "", 0);
                }  
                
                if($data =~ /<Meta_Info>.*?<Channel>(.+?)<\/Channel>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentChannel", YAMAHA_AVR_html2txt($1));
                }
                else
                {
                    readingsBulkUpdate($hash, "currentChannel", "", 0);
                }
                
                if($data =~ /<Meta_Info>.*?<Album>(.+?)<\/Album>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentAlbum", YAMAHA_AVR_html2txt($1));
                }
                else
                {
                    readingsBulkUpdate($hash, "currentAlbum", "", 0);
                }
                
                if($data =~ /<Meta_Info>.*?<Song>(.+?)<\/Song>.*?<\/Meta_Info>/)
                {
                    readingsBulkUpdate($hash, "currentTitle", YAMAHA_AVR_html2txt($1));
                }
                elsif($data =~ /<Meta_Info>.*?<Radio_Text_A>(.+?)<\/Radio_Text_A>.*?<\/Meta_Info>/)	
                {		
                    my $tmp = $1;
                    
                    if($data =~ /<Meta_Info>.*?<Radio_Text_A>(.+?)<\/Radio_Text_A>.*?<Radio_Text_B>(.+?)<\/Radio_Text_B>.*?<\/Meta_Info>/)	
                    {											
                        readingsBulkUpdate($hash, "currentTitle", YAMAHA_AVR_html2txt($1." ".$2));		
                    }	
                    else
                    {
                        readingsBulkUpdate($hash, "currentTitle", YAMAHA_AVR_html2txt($tmp));		
                    }
                }	
                elsif($data =~ /<Meta_Info>.*?<Radio_Text_B>(.+?)<\/Radio_Text_B>.*?<\/Meta_Info>/)	
                {		 
                    readingsBulkUpdate($hash, "currentTitle", YAMAHA_AVR_html2txt($1));		
                }	
                else
                {
                    readingsBulkUpdate($hash, "currentTitle", "", 0);
                }
                
                if($data =~ /<Playback_Info>(.+?)<\/Playback_Info>/)
                {
                    readingsBulkUpdate($hash, "playStatus", lc($1));
                }
            }
            elsif($arg eq "playShuffle")
            {
                if($data =~ /<Shuffle>(.+?)<\/Shuffle>/)
                {
                    $hash->{helper}{PLAY_CONTROL} = 1;
                    readingsBulkUpdate($hash, "shuffle", lc($1));
                }
            }
            elsif($arg eq "playRepeat")
            {
                if($data =~ /<Repeat>(.+?)<\/Repeat>/)
                {
                    $hash->{helper}{PLAY_CONTROL} = 1;
                    readingsBulkUpdate($hash, "repeat", lc($1));
                }
            }
        }
        elsif($cmd eq "on")
        {
            if($data =~ /RC="0"/ and $data =~ /<Power><\/Power>/)
            {
				# As the receiver startup takes about 5 seconds, the status will be already set, if the return code of the command is 0.
				readingsBulkUpdate($hash, "power", "on");
				readingsBulkUpdate($hash, "state","on");
                
                readingsEndUpdate($hash, 1);
                
                YAMAHA_AVR_ResetTimer($hash, 5);
                
                return undef;
            }
        }
        elsif($cmd eq "off")
        {
            if($data =~ /RC="0"/ and $data =~ /<Power><\/Power>/)
            {
				readingsBulkUpdate($hash, "power", "off");
				readingsBulkUpdate($hash, "state","off");
                
                readingsEndUpdate($hash, 1);
                
                YAMAHA_AVR_ResetTimer($hash, 3);
                
                return undef;
			}
        }
        elsif($cmd eq "volume")
        {
            my ($current_volume, $diff,$target_volume ) = split("\\|", $arg);
            
            # Depending on the status response, use the short or long Volume command
            my $volume_cmd = (exists($hash->{helper}{USE_SHORT_VOL_CMD}) and $hash->{helper}{USE_SHORT_VOL_CMD} eq "1" ? "Vol" : "Volume");
            
            my $zone = YAMAHA_AVR_getParamName($hash, $hash->{ACTIVE_ZONE}, $hash->{helper}{ZONES});

            readingsBulkUpdate($hash, "volumeStraight", $current_volume);
            readingsBulkUpdate($hash, "volume", YAMAHA_AVR_volume_abs2rel($current_volume));
            
            if(not $current_volume == $target_volume)
            {
                readingsEndUpdate($hash, 1);  
     
                if($diff == 0)
                {
                            Log3 $name, 4, "YAMAHA_AVR ($name) - set volume to ".$target_volume." dB (target is $target_volume dB)";
                            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Lvl><Val>".($target_volume*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></$volume_cmd></$zone></YAMAHA_AV>", "volume", "$target_volume|0|$target_volume" );
                            return undef;
                }
                else
                {
                    if(abs($current_volume - $target_volume) < abs($diff))
                    {
                            Log3 $name, 4, "YAMAHA_AVR ($name) - set volume to ".$target_volume." dB (target is $target_volume dB)";
                            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Lvl><Val>".($target_volume*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></$volume_cmd></$zone></YAMAHA_AV>", "volume", "$target_volume|0|$target_volume" );
                            return undef;
                    }
                    else
                    {
                            Log3 $name, 4, "YAMAHA_AVR ($name) - set volume to ".($current_volume + $diff)." dB (target is $target_volume dB)";
                            YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><$zone><$volume_cmd><Lvl><Val>".(($current_volume + $diff)*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></$volume_cmd></$zone></YAMAHA_AV>", "volume", ($current_volume + $diff)."|$diff|$target_volume" );
                            return undef;
                    }
                }
            }
        }
        
        readingsEndUpdate($hash, 1);
         
        YAMAHA_AVR_ResetTimer($hash, 0) if($cmd ne "statusRequest" and $cmd ne "on");
    }
}

#############################
# Converts all Values to FHEM usable command lists
sub YAMAHA_AVR_Param2Fhem($$)
{
    my ($param, $replace_pipes) = @_;

   
    $param =~ s/\s+//g;
    $param =~ s/,//g;
    $param =~ s/_//g;
    $param =~ s/\(/_/g;
    $param =~ s/\)//g;
    $param =~ s/\|/,/g if($replace_pipes == 1);

    return lc $param;
}

#############################
# Returns the Yamaha Parameter Name for the FHEM like aquivalents
sub YAMAHA_AVR_getParamName($$$)
{
	my ($hash, $name, $list) = @_;
	my $item;
   
	return undef if(not defined($list));
  
	my @commands = split("\\|",  $list);

    foreach $item (@commands)
    {
		if(YAMAHA_AVR_Param2Fhem($item, 0) eq $name)
		{
			return $item;
		}
    }
    
    return undef;
}

#############################
# queries the receiver model, system-id, version and all available zones
sub YAMAHA_AVR_getModel($)
{
    my ($hash) = @_;
   
    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Unit_Desc>GetParam</Unit_Desc></System></YAMAHA_AV>", "statusRequest","unitDescription");
    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Config>GetParam</Config></System></YAMAHA_AV>", "statusRequest","systemConfig");
}	
	
#############################
# parses the HTTP response for unit description XML file
sub
YAMAHA_AVR_ParseXML($$$)
{
    my ($param, $err, $data) = @_;    
    
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
   
    Log3 $name, 3, "YAMAHA_AVR ($name) - could not get unit description. Please turn on the device or check for correct hostaddress!" if ($err ne "" and defined($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 1);
    
    return undef if($data eq "");

    delete($hash->{helper}{ZONES}) if(exists($hash->{helper}{ZONES}));
    
    Log3 $name, 4, "YAMAHA_AVR ($name) - checking available zones"; 
    
    while($data =~ /<Menu Func="Subunit" Title_1="(.+?)" YNC_Tag="(.+?)">/gc)
    {
        if(defined($hash->{helper}{ZONES}) and length($hash->{helper}{ZONES}) > 0)
        {
            $hash->{helper}{ZONES} .= "|";
        }
        Log3 $name, 4, "YAMAHA_AVR ($name) - adding zone: $2";
        $hash->{helper}{ZONES} .= $2;
    }
    
    delete( $hash->{helper}{DSP_MODES}) if(exists($hash->{helper}{DSP_MODES}));
    
    if($data =~ /<Menu Func_Ex="Surround" Title_1="Surround">.*?<Get>(.+?)<\/Get>/)
    {
        my $modes = $1;
        
        Log3 $name, 4, "YAMAHA_AVR ($name) - found DSP modes in XML";
        
        while($modes =~ /<Direct.*?>(.+?)<\/Direct>/gc)
        {
            if(defined($hash->{helper}{DSP_MODES}) and length($hash->{helper}{DSP_MODES}) > 0)
            {
                $hash->{helper}{DSP_MODES} .= "|";
            }
            Log3 $name, 4, "YAMAHA_AVR ($name) - adding DSP mode $1";
            $hash->{helper}{DSP_MODES} .= $1;
        }
    }
    else
    {
        Log3 $name, 4, "YAMAHA_AVR ($name) - no DSP modes found in XML";
    }
    
    # uncommented line for zone detection testing
    #
    # $hash->{helper}{ZONES} .= "|Zone_2";
    
    $hash->{ZONES_AVAILABLE} = YAMAHA_AVR_Param2Fhem($hash->{helper}{ZONES}, 1);
   
    # if explicitly given in the define command, set the desired zone
    if(defined(YAMAHA_AVR_getParamName($hash, lc $hash->{helper}{SELECTED_ZONE}, $hash->{helper}{ZONES})))
    {
		Log3 $name, 4, "YAMAHA_AVR ($name) - using ".YAMAHA_AVR_getParamName($hash, lc $hash->{helper}{SELECTED_ZONE}, $hash->{helper}{ZONES})." as active zone";
		$hash->{ACTIVE_ZONE} = lc $hash->{helper}{SELECTED_ZONE};
    }
    else
    {
		Log3 $name, 2, "YAMAHA_AVR ($name) - selected zone >>".$hash->{helper}{SELECTED_ZONE}."<< is not available. Using Main Zone instead";
		$hash->{ACTIVE_ZONE} = "mainzone";
    }
}

#############################
# converts decibal volume in percentage volume (-80.5 .. 16.5dB => 0 .. 100%)
sub YAMAHA_AVR_volume_rel2abs($)
{
	my ($percentage) = @_;
	
	#  0 - 100% -equals 80.5 to 16.5 dB
	return int((($percentage / 100 * 97) - 80.5) / 0.5) * 0.5;
}

#############################
# converts percentage volume in decibel volume (0 .. 100% => -80.5 .. 16.5dB)
sub YAMAHA_AVR_volume_abs2rel($)
{
	my ($absolute) = @_;
	
	# -80.5 to 16.5 dB equals 0 - 100%
	return int(($absolute + 80.5) / 97 * 100);
}

#############################
# queries all available inputs and scenes
sub YAMAHA_AVR_getInputs($)
{
    my ($hash) = @_;  
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
   
    my $zone = YAMAHA_AVR_getParamName($hash, $hash->{ACTIVE_ZONE}, $hash->{helper}{ZONES});
    
    return undef if (not defined($zone) or $zone eq "");
    
    # query all inputs
    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Input><Input_Sel_Item>GetParam</Input_Sel_Item></Input></$zone></YAMAHA_AV>", "statusRequest","getInputs");

    # query all available scenes (only in mainzone available)
    YAMAHA_AVR_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><$zone><Scene><Scene_Sel_Item>GetParam</Scene_Sel_Item></Scene></$zone></YAMAHA_AV>", "statusRequest","getScenes", 1) if($hash->{ACTIVE_ZONE} eq "mainzone");
}

#############################
# Restarts the internal status request timer according to the given interval or current receiver state
sub YAMAHA_AVR_ResetTimer($;$)
{
    my ($hash, $interval) = @_;
    
    RemoveInternalTimer($hash);
    
    if($hash->{helper}{DISABLED} == 0)
    {
        if(defined($interval))
        {
            InternalTimer(gettimeofday()+$interval, "YAMAHA_AVR_GetStatus", $hash, 0);
        }
        elsif((exists($hash->{READINGS}{presence}{VAL}) and $hash->{READINGS}{presence}{VAL} eq "present") and (exists($hash->{READINGS}{power}{VAL}) and $hash->{READINGS}{power}{VAL} eq "on"))
        {
            InternalTimer(gettimeofday()+$hash->{helper}{ON_INTERVAL}, "YAMAHA_AVR_GetStatus", $hash, 0);
        }
        else
        {
            InternalTimer(gettimeofday()+$hash->{helper}{OFF_INTERVAL}, "YAMAHA_AVR_GetStatus", $hash, 0);
        }
    }
    
    return undef;
}

#############################
# convert all HTML entities into UTF-8 aquivalents
sub YAMAHA_AVR_html2txt($)
{
    my ($string) = @_;

    $string =~ s/&amp;/&/g;
    $string =~ s/&amp;/&/g;
    $string =~ s/&nbsp;/ /g;
    $string =~ s/&apos;/'/g;
    $string =~ s/(\xe4|&auml;)/�/g;
    $string =~ s/(\xc4|&Auml;)/�/g;
    $string =~ s/(\xf6|&ouml;)/�/g;
    $string =~ s/(\xd6|&Ouml;)/�/g;
    $string =~ s/(\xfc|&uuml;)/�/g;
    $string =~ s/(\xdc|&Uuml;)/�/g;
    $string =~ s/(\xdf|&szlig;)/�/g;
    
    $string =~ s/<.+?>//g;
    $string =~ s/(^\s+|\s+$)//g;

    return $string;
}
1;

=pod
=begin html

<a name="YAMAHA_AVR"></a>
<h3>YAMAHA_AVR</h3>
<ul>

  <a name="YAMAHA_AVRdefine"></a>
  <b>Define</b>
  <ul>
    <code>
    define &lt;name&gt; YAMAHA_AVR &lt;ip-address&gt; [&lt;zone&gt;] [&lt;status_interval&gt;]
    <br><br>
    define &lt;name&gt; YAMAHA_AVR &lt;ip-address&gt; [&lt;zone&gt;] [&lt;off_status_interval&gt;] [&lt;on_status_interval&gt;]
    </code>
    <br><br>

    This module controls AV receiver from Yamaha via network connection. You are able
    to power your AV reveiver on and off, query it's power state,
    select the input (HDMI, AV, AirPlay, internet radio, Tuner, ...), select the volume
    or mute/unmute the volume.<br><br>
    Defining a YAMAHA_AVR device will schedule an internal task (interval can be set
    with optional parameter &lt;status_interval&gt; in seconds, if not set, the value is 30
    seconds), which periodically reads the status of the AV receiver (power state, selected
    input, volume and mute status) and triggers notify/filelog commands.
    <br><br>
    Different status update intervals depending on the power state can be given also. 
    If two intervals are given in the define statement, the first interval statement stands for the status update 
    interval in seconds in case the device is off, absent or any other non-normal state. The second 
    interval statement is used when the device is on.
   
    Example:<br><br>
    <ul><code>
       define AV_Receiver YAMAHA_AVR 192.168.0.10
       <br><br>
       # With custom status interval of 60 seconds<br>
       define AV_Receiver YAMAHA_AVR 192.168.0.10 mainzone 60 
       <br><br>
       # With custom "off"-interval of 60 seconds and "on"-interval of 10 seconds<br>
       define AV_Receiver YAMAHA_AVR 192.168.0.10 mainzone 60 10
    </code></ul>
   
  </ul>
  <br><br>
  <b>Zone Selection</b><br>
  <ul>
    If your receiver supports zone selection (e.g. RX-V671, RX-V673,... and the AVANTAGE series) 
    you can select the zone which should be controlled. The RX-V3xx and RX-V4xx series for example 
    just have a "Main Zone" (which is the whole receiver itself). In general you have the following
    possibilities for the parameter &lt;zone&gt; (depending on your receiver model).<br><br>
    <ul>
    <li><b>mainzone</b> - this is the main zone (standard)</li>
    <li><b>zone2</b> - The second zone (Zone 2)</li>
    <li><b>zone3</b> - The third zone (Zone 3)</li>
    <li><b>zone4</b> - The fourth zone (Zone 4)</li>
    </ul>
    <br>
    Depending on your receiver model you have not all inputs available on these different zones.
    The module just offers the real available inputs.
    <br><br>
    Example:
    <br><br>
     <ul><code>
        define AV_Receiver YAMAHA_AVR 192.168.0.10 &nbsp;&nbsp;&nbsp; # If no zone is specified, the "Main Zone" will be used.<br>
        attr AV_Receiver YAMAHA_AVR room Livingroom<br>
        <br>
        # Define the second zone<br>
        define AV_Receiver_Zone2 YAMAHA_AVR 192.168.0.10 zone2<br>
        attr AV_Receiver_Zone2 room Bedroom
     </code></ul><br><br>
     For each Zone you will need an own YAMAHA_AVR device, which can be assigned to a different room.
     Each zone can be controlled separatly from all other available zones.
     <br><br>
  </ul>
  
  <a name="YAMAHA_AVRset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>
    Currently, the following commands are defined; the available inputs are depending on the used receiver.
    The module only offers the real available inputs and scenes. The following input commands are just an example and can differ.
<br><br>
<ul>
<li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device</li>
<li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; shuts down the device </li>
<li><b>input</b> hdm1,hdmX,... &nbsp;&nbsp;-&nbsp;&nbsp; selects the input channel (only the real available inputs were given)</li>
<li><b>scene</b> scene1,sceneX &nbsp;&nbsp;-&nbsp;&nbsp; select the scene</li>
<li><b>volume</b> 0...100 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in percentage</li>
<li><b>volumeStraight</b> -80...15 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in decibel</li>
<li><b>volumeUp</b> [0-100] &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume level by 5% or the value of attribute volumeSteps (optional the increasing level can be given as argument, which will be used instead)</li>
<li><b>volumeDown</b> [0-100] &nbsp;&nbsp;-&nbsp;&nbsp; decreases the volume level by 5% or the value of attribute volumeSteps (optional the decreasing level can be given as argument, which will be used instead)</li>
<li><b>mute</b> on|off|toggle &nbsp;&nbsp;-&nbsp;&nbsp; activates volume mute</li>
<li><b>dsp</b> hallinmunich,hallinvienna,... &nbsp;&nbsp;-&nbsp;&nbsp; sets the DSP mode to the given preset</li>
<li><b>enhancer</b> on|off &nbsp;&nbsp;-&nbsp;&nbsp; controls the internal sound enhancer</li>
<li><b>3dCinemaDsp</b> auto|off &nbsp;&nbsp;-&nbsp;&nbsp; controls the CINEMA DSP 3D mode</li>
<li><b>adaptiveDrc</b> auto|off &nbsp;&nbsp;-&nbsp;&nbsp; controls the Adaptive DRC</li>
<li><b>straight</b> on|off &nbsp;&nbsp;-&nbsp;&nbsp; bypasses the internal codec converter and plays the original sound codec</li>
<li><b>direct</b> on|off &nbsp;&nbsp;-&nbsp;&nbsp; bypasses all internal sound enhancement features and plays the sound straight directly</li> 
<li><b>sleep</b> off,30min,60min,...,last &nbsp;&nbsp;-&nbsp;&nbsp; activates the internal sleep timer</li>
<li><b>shuffle</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; activates the shuffle mode on the current input</li>
<li><b>repeat</b> one,all,off &nbsp;&nbsp;-&nbsp;&nbsp; activates the repeat mode on the current input for one or all titles</li>
<li><b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; pause playback on current input</li>
<li><b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; start playback on current input</li>
<li><b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; stop playback on current input</li>
<li><b>skip</b> reverse,forward &nbsp;&nbsp;-&nbsp;&nbsp; skip track on current input</li>
<li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device</li>
<li><b>remoteControl</b> up,down,... &nbsp;&nbsp;-&nbsp;&nbsp; sends remote control commands as listed below</li>

</ul>
</ul><br><br>
<u>Remote control (not in all zones available, depending on your model)</u><br><br>
<ul>
    In many receiver models, inputs exist, which can't be used just by selecting them. These inputs needs
    a manual interaction with the remote control to activate the playback (e.g. Internet Radio, Network Streaming).<br><br>
    For this application the following commands are available:<br><br>

    <u>Cursor Selection:</u><br><br>
    <ul><code>
    remoteControl up<br>
    remoteControl down<br>
    remoteControl left<br>
    remoteControl right<br>
    remoteControl enter<br>
    remoteControl return<br>
    </code></ul><br><br>

    <u>Menu Selection:</u><br><br>
    <ul><code>
    remoteControl setup<br>
    remoteControl option<br>
    remoteControl display<br>
    </code></ul><br><br>
	
	<u>Tuner Control:</u><br><br>
	<ul><code>
	remoteControl tunerPresetUp<br>
	remoteControl tunerPresetDown<br>
	</code></ul><br><br>

    The button names are the same as on your remote control.<br><br>
    
    A typical example is the automatical turn on and play an internet radio broadcast:<br><br>
    <ul><code>
    # the initial definition.<br>
    define AV_receiver YAMAHA_AVR 192.168.0.3
    </code></ul><br><br>
    And in your myUtils.pm (based on myUtilsTemplate.pm) the following function:<br><br>
    <ul><code>
        sub startNetRadio()<br>
        {<br>
        &nbsp;&nbsp;fhem("set AV_Receiver on;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;sleep 5;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;set AV_Receiver input netradio;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;sleep 4;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;set AV_Receiver remoteControl enter;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;sleep 2;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;set AV_Receiver remoteControl enter;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;sleep 2;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;set AV_Receiver remoteControl enter");<br>
        }<br>
    </code></ul><br><br>
    The remote control commands must be separated with a sleep, because the receiver is loading meanwhile and don't accept commands. These commands will be executed in background and does not harm the FHEM main process.<br><br>
    
    Now you can use this function by typing the following line in your FHEM command line or in your notify-definitions:<br><br>
    <ul><code>
    {startNetRadio()}
    </code></ul><br><br>
    
    
    
  </ul>

  <a name="YAMAHA_AVRget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt;</code>
    <br><br>
    Currently, the get command only returns the reading values. For a specific list of possible values, see section "Generated Readings/Events".
	<br><br>
  </ul>
  <a name="YAMAHA_AVRattr"></a>
  <b>Attributes</b>
  <ul>
  
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
	<li><a name="request-timeout">request-timeout</a></li>
	Optional attribute change the response timeout in seconds for all queries to the receiver.
	<br><br>
	Possible values: 1-5 seconds. Default value is 4 seconds.<br><br>
    <li><a name="disable">disable</a></li>
	Optional attribute to disable the internal cyclic status update of the receiver. Manual status updates via statusRequest command is still possible.
	<br><br>
	Possible values: 0 => perform cyclic status update, 1 => don't perform cyclic status updates.<br><br>
    <li><a name="volume-smooth-change">volume-smooth-change</a></li>
	Optional attribute to activate a smooth volume change.
	<br><br>
	Possible values: 0 => off , 1 => on<br><br>
    <li><a name="volume-smooth-steps">volume-smooth-steps</a></li>
	Optional attribute to define the number of volume changes between the
    current and the desired volume. Default value is 5 steps<br><br>
	<li><a name="volume-smooth-steps">volumeSteps</a></li>
	Optional attribute to define the default increasing and decreasing level for the volumeUp and volumeDown set command. Default value is 5%<br>
  <br>
  </ul>
  <b>Generated Readings/Events:</b><br>
  <ul>
  <li><b>3dCinemaDsp</b> - The status of the CINEMA DSP 3D mode (can be "auto" or "off")</li>
  <li><b>adaptiveDrc</b> - The status of the Adaptive DRC (can be "auto" or "off")</li>
  <li><b>dsp</b> - The current selected DSP mode for sound output</li>
  <li><b>direct</b> - indicates if all sound enhancement features are bypassed or not ("on" =&gt; all features are bypassed, "off" =&gt; sound enhancement features are used).</li>
  <li><b>enhancer</b> - The status of the internal sound enhancer (can be "on" or "off")</li>
  <li><b>input</b> - The selected input source according to the FHEM input commands</li>
  <li><b>inputName</b> - The input description as seen on the receiver display</li>
  <li><b>mute</b> - Reports the mute status of the receiver or zone (can be "on" or "off")</li>
  <li><b>power</b> - Reports the power status of the receiver or zone (can be "on" or "off")</li>
  <li><b>presence</b> - Reports the presence status of the receiver or zone (can be "absent" or "present"). In case of an absent device, it cannot be controlled via FHEM anymore.</li>
  <li><b>volume</b> - Reports the current volume level of the receiver or zone in percentage values (between 0 and 100 %)</li>
  <li><b>volumeStraight</b> - Reports the current volume level of the receiver or zone in decibel values (between -80.5 and +15.5 dB)</li>
  <li><b>sleep</b> - indicates if the internal sleep timer is activated or not.</li>
  <li><b>straight</b> - indicates if the internal sound codec converter is bypassed or not (can be "on" or "off")</li>
  <li><b>state</b> - Reports the current power state and an absence of the device (can be "on", "off" or "absent")</li>
  <br><br><u>Input dependent Readings/Events:</u><br>
  <li><b>currentChannel</b> - Number of the input channel (SIRIUS only)</li>
  <li><b>currentStation</b> - Station name of the current radio station (available on NET RADIO, PANDORA</li>
  <li><b>currentAlbum</b> - Album name of the current song</li>
  <li><b>currentArtist</b> - Artist name of the current song</li>
  <li><b>currentTitle</b> - Title of the current song</li>
  <li><b>playStatus</b> - indicates if the input plays music or not</li>
  <li><b>shuffle</b> - indicates the shuffle status for the current input</li>
  <li><b>repeat</b> - indicates the repeat status for the current input</li>
  </ul>
<br>
  <b>Implementator's note</b><br>
  <ul>
    The module is only usable if you activate "Network Standby" on your receiver. Otherwise it is not possible to communicate with the receiver when it is turned off.
  </ul>
  <br>
</ul>


=end html
=begin html_DE

<a name="YAMAHA_AVR"></a>
<h3>YAMAHA_AVR</h3>
<ul>

  <a name="YAMAHA_AVRdefine"></a>
  <b>Definition</b>
  <ul>
    <code>define &lt;name&gt; YAMAHA_AVR &lt;IP-Addresse&gt; [&lt;Zone&gt;] [&lt;Status_Interval&gt;]
    <br><br>
    define &lt;name&gt; YAMAHA_AVR &lt;IP-Addresse&gt; [&lt;Zone&gt;] [&lt;Off_Interval&gt;] [&lt;On_Interval&gt;]
    </code>
    <br><br>

    Dieses Modul steuert AV-Receiver des Herstellers Yamaha &uuml;ber die Netzwerkschnittstelle.
    Es bietet die M&ouml;glichkeit den Receiver an-/auszuschalten, den Eingangskanal zu w&auml;hlen,
    die Lautst&auml;rke zu &auml;ndern, den Receiver "Stumm" zu schalten, sowie den aktuellen Status abzufragen.
    <br><br>
    Bei der Definition eines YAMAHA_AVR-Moduls wird eine interne Routine in Gang gesetzt, welche regelm&auml;&szlig;ig 
    (einstellbar durch den optionalen Parameter <code>&lt;Status_Interval&gt;</code>; falls nicht gesetzt ist der Standardwert 30 Sekunden)
    den Status des Receivers abfragt und entsprechende Notify-/FileLog-Ger&auml;te triggert.
    <br><br>
    Sofern 2 Interval-Argumente &uuml;bergeben werden, wird der erste Parameter <code>&lt;Off_Interval&gt;</code> genutzt
    sofern der Receiver ausgeschaltet oder nicht erreichbar ist. Der zweiter Parameter <code>&lt;On_Interval&gt;</code> 
    wird verwendet, sofern der Receiver eingeschaltet ist. 
    <br><br>
    Beispiel:<br><br>
    <ul><code>
       define AV_Receiver YAMAHA_AVR 192.168.0.10
       <br><br>
       # Mit modifiziertem Status Interval (60 Sekunden)<br>
       define AV_Receiver YAMAHA_AVR 192.168.0.10 mainzone 60
       <br><br>
       # Mit gesetztem "Off"-Interval (60 Sekunden) und "On"-Interval (10 Sekunden)<br>
       define AV_Receiver YAMAHA_AVR 192.168.0.10 mainzone 60 10
    </code></ul><br><br>
  </ul>
  <b>Zonenauswahl</b><br>
  <ul>
    Wenn der zu steuernde Receiver mehrere Zonen besitzt (z.B. RX-V671, RX-V673,... sowie die AVANTAGE Modellreihe) 
    kann die zu steuernde Zone explizit angegeben werden. Die Modellreihen RX-V3xx und RX-V4xx als Beispiel
    haben nur eine Zone (Main Zone). Je nach Receiver-Modell stehen folgende Zonen zur Verf&uuml;gung, welche mit
    dem optionalen Parameter &lt;Zone&gt; angegeben werden k&ouml;nnen.<br><br>
    <ul>
    <li><b>mainzone</b> - Das ist die Hauptzone (Standard)</li>
    <li><b>zone2</b> - Die zweite Zone (Zone 2)</li>
    <li><b>zone3</b> - Die dritte Zone (Zone 3)</li>
    <li><b>zone4</b> - Die vierte Zone (Zone 4)</li>
    </ul>
    <br>
    Je nach Receiver-Modell stehen in den verschiedenen Zonen nicht immer alle Eing&auml;nge zur Verf&uuml;gung. 
    Dieses Modul bietet nur die tats&auml;chlich verf&uuml;gbaren Eing&auml;nge an.
    <br><br>
    Beispiel:<br><br>
     <ul><code>
        define AV_Receiver YAMAHA_AVR 192.168.0.10 &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; # Wenn keine Zone angegeben ist, wird<br>
        attr AV_Receiver YAMAHA_AVR room Wohnzimmer &nbsp;&nbsp;&nbsp;&nbsp; # standardm&auml;&szlig;ig "mainzone" verwendet<br>
        <br>
        # Definition der zweiten Zone<br>
        define AV_Receiver_Zone2 YAMAHA_AVR 192.168.0.10 zone2<br>
        attr AV_Receiver_Zone2 room Schlafzimmer<br>
     </code></ul><br><br>
     F&uuml;r jede Zone muss eine eigene YAMAHA_AVR Definition erzeugt werden, welche dann unterschiedlichen R&auml;umen zugeordnet werden kann.
     Jede Zone kann unabh&auml;ngig von allen anderen Zonen (inkl. der Main Zone) gesteuert werden.
     <br><br>
  </ul>
  
  <a name="YAMAHA_AVRset"></a>
  <b>Set-Kommandos </b>
  <ul>
    <code>set &lt;Name&gt; &lt;Kommando&gt; [&lt;Parameter&gt;]</code>
    <br><br>
    Aktuell werden folgende Kommandos unterst&uuml;tzt. Die verf&uuml;gbaren Eing&auml;nge und Szenen k&ouml;nnen je nach Receiver-Modell variieren.
    Die folgenden Eing&auml;nge stehen beispielhaft an einem RX-V473 Receiver zur Verf&uuml;gung.
    Aktuell stehen folgende Kommandos zur Verf&uuml;gung.
<br><br>
<ul>
<li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet den Receiver ein</li>
<li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet den Receiver aus</li>
<li><b>dsp</b> hallinmunich,hallinvienna,... &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert das entsprechende DSP Preset</li>
<li><b>enhancer</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert den Sound Enhancer f&uuml;r einen verbesserten Raumklang</li>
<li><b>3dCinemaDsp</b> auto,off &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert den CINEMA DSP 3D Modus</li>
<li><b>adaptiveDrc</b> auto,off &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert Adaptive DRC</li>
<li><b>direct</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; Umgeht alle internen soundverbessernden Ma&szlig;nahmen (Equalizer, Enhancer, Adaptive DRC,...) und gibt das Signal unverf&auml;lscht wieder</li>
<li><b>input</b> hdmi1,hdmiX,... &nbsp;&nbsp;-&nbsp;&nbsp; W&auml;hlt den Eingangskanal (es werden nur die tats&auml;chlich verf&uuml;gbaren Eing&auml;nge angeboten)</li>
<li><b>scene</b> scene1,sceneX &nbsp;&nbsp;-&nbsp;&nbsp; W&auml;hlt eine vorgefertigte Szene aus</li>
<li><b>volume</b> 0...100 &nbsp;&nbsp;-&nbsp;&nbsp; Setzt die Lautst&auml;rke in Prozent (0 bis 100%)</li>
<li><b>volumeStraight</b> -87...15 &nbsp;&nbsp;-&nbsp;&nbsp; Setzt die Lautst&auml;rke in Dezibel (-80.5 bis 15.5 dB) so wie sie am Receiver auch verwendet wird.</li>
<li><b>volumeUp</b> [0...100] &nbsp;&nbsp;-&nbsp;&nbsp; Erh&ouml;ht die Lautst&auml;rke um 5% oder entsprechend dem Attribut volumeSteps (optional kann der Wert auch als Argument angehangen werden, dieser hat dann Vorang) </li>
<li><b>volumeDown</b> [0...100] &nbsp;&nbsp;-&nbsp;&nbsp; Veringert die Lautst&auml;rke um 5% oder entsprechend dem Attribut volumeSteps (optional kann der Wert auch als Argument angehangen werden, dieser hat dann Vorang) </li>
<li><b>mute</b> on,off,toggle &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet den Receiver stumm</li>
<li><b>straight</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; Umgeht die interne Codec-Umwandlung und gibt den Original-Codec wieder.</li>
<li><b>sleep</b> off,30min,60min,...,last &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert den internen Sleep-Timer zum automatischen Abschalten</li>
<li><b>shuffle</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert die Zufallswiedergabe des aktuellen Eingangs (ist nur eingangsabh&auml;ngig verf&uuml;gbar)</li>
<li><b>repeat</b> one,all,off &nbsp;&nbsp;-&nbsp;&nbsp; Wiederholt den aktuellen (one) oder alle (all) Titel des aktuellen Eingangs (ist nur eingangsabh&auml;ngig verf&uuml;gbar)</li>
<li><b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; Wiedergabe pausieren (ist nur eingangsabh&auml;ngig verf&uuml;gbar)</li>
<li><b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; Wiedergabe starten (ist nur eingangsabh&auml;ngig verf&uuml;gbar)</li>
<li><b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; Wiedergabe stoppen (ist nur eingangsabh&auml;ngig verf&uuml;gbar)</li>
<li><b>skip</b> reverse,forward &nbsp;&nbsp;-&nbsp;&nbsp; Aktuellen Titel &uuml;berspringen (ist nur eingangsabh&auml;ngig verf&uuml;gbar)</li>
<li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; Fragt den aktuell Status des Receivers ab</li>
<li><b>remoteControl</b> up,down,... &nbsp;&nbsp;-&nbsp;&nbsp; Sendet Fernbedienungsbefehle wie im n&auml;chsten Abschnitt beschrieben</li>
</ul>
<br><br>
</ul>
<u>Fernbedienung (je nach Modell nicht in allen Zonen verf&uuml;gbar)</u><br><br>
<ul>
    In vielen Receiver-Modellen existieren Eing&auml;nge, welche nach der Auswahl keinen Sound ausgeben. Diese Eing&auml;nge
    bed&uuml;rfen manueller Interaktion mit der Fernbedienung um die Wiedergabe zu starten (z.B. Internet Radio, Netzwerk Streaming, usw.).<br><br>
    F&uuml;r diesen Fall gibt es folgende Befehle:<br><br>

    <u>Cursor Steuerung:</u><br><br>
    <ul><code>
    remoteControl up<br>
    remoteControl down<br>
    remoteControl left<br>
    remoteControl right<br>
    remoteControl enter<br>
    remoteControl return<br>
    </code></ul><br><br>

    <u>Men&uuml; Auswahl:</u><br><br>
    <ul><code>
    remoteControl setup<br>
    remoteControl option<br>
    remoteControl display<br>
    </code></ul><br><br>
	
	<u>Radio Steuerung:</u><br><br>
	<ul><code>
	remoteControl tunerPresetUp<br>
	remoteControl tunerPresetDown<br>
	</code></ul><br><br>
    Die Befehlsnamen entsprechen den Tasten auf der Fernbedienung.<br><br>
    
    Ein typisches Beispiel ist das automatische Einschalten und Abspielen eines Internet Radio Sender:<br><br>
    <ul><code>
    # Die Ger&auml;tedefinition<br><br>
    define AV_receiver YAMAHA_AVR 192.168.0.3
    </code></ul><br><br>
    Und in der myUtils.pm (basierend auf der myUtilsTemplate.pm) die folgende Funktion:<br><br>
    <ul><code>
        sub startNetRadio()<br>
        {<br>
        &nbsp;&nbsp;fhem("set AV_Receiver on;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;sleep 5;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;set AV_Receiver input netradio;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;sleep 4;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;set AV_Receiver remoteControl enter;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;sleep 2;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;set AV_Receiver remoteControl enter;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;sleep 2;<br>
        &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;set AV_Receiver remoteControl enter");<br>
        }<br>
    </code></ul><br><br>
    Die Kommandos der Fernbedienung m&uuml;ssen mit einem sleep pausiert werden, da der Receiver in der Zwischenzeit arbeitet und keine Befehle annimmt. Diese Befehle werden alle im Hintergrund ausgef&uuml;hrt, so dass f&uuml;r den FHEM Hauptprozess keine Verz&ouml;gerung entsteht.<br><br>
    
    Nun kann man diese Funktion in der FHEM Kommandozeile oder in notify-Definitionen wie folgt verwenden.:<br><br>
    <ul><code>
    {startNetRadio()}
    </code></ul><br><br>
  </ul>

  <a name="YAMAHA_AVRget"></a>
  <b>Get-Kommandos</b>
  <ul>
    <code>get &lt;Name&gt; &lt;Readingname&gt;</code>
    <br><br>
    Aktuell stehen via GET lediglich die Werte der Readings zur Verf&uuml;gung. Eine genaue Auflistung aller m&ouml;glichen Readings folgen unter "Generierte Readings/Events".
  </ul>
  <br><br>
  <a name="YAMAHA_AVRattr"></a>
  <b>Attribute</b>
  <ul>
  
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
	<li><a name="request-timeout">request-timeout</a></li>
	Optionales Attribut. Maximale Dauer einer Anfrage in Sekunden zum Receiver.
	<br><br>
	M&ouml;gliche Werte: 1-5 Sekunden. Standardwert ist 4 Sekunden<br><br>
    <li><a name="disable">disable</a></li>
	Optionales Attribut zur Deaktivierung des zyklischen Status-Updates. Ein manuelles Update via statusRequest-Befehl ist dennoch m&ouml;glich.
	<br><br>
	M&ouml;gliche Werte: 0 => zyklische Status-Updates, 1 => keine zyklischen Status-Updates.<br><br>
    <li><a name="volume-smooth-change">volume-smooth-change</a></li>
	Optionales Attribut, welches einen weichen Lautst&auml;rke&uuml;bergang aktiviert..
	<br><br>
	M&ouml;gliche Werte: 0 => deaktiviert , 1 => aktiviert<br><br>
    <li><a name="volume-smooth-steps">volume-smooth-steps</a></li>
	Optionales Attribut, welches angibt, wieviele Schritte zur weichen Lautst&auml;rkeanpassung
	durchgef&uuml;hrt werden sollen. Standardwert ist 5 Anpassungschritte<br><br>
	<li><a name="volumeSteps">volumeSteps</a></li>
	Optionales Attribut, welches den Standardwert zur Lautst&auml;rkenerh&ouml;hung (volumeUp) und Lautst&auml;rkenveringerung (volumeDown) konfiguriert. Standardwert ist 5%<br>
  <br>
  </ul>
  <b>Generierte Readings/Events:</b><br>
  <ul>
  <li><b>3dCinemaDsp</b> - Der Status des CINEMA DSP 3D-Modus ("auto" =&gt; an, "off" =&gt; aus)</li>
  <li><b>adaptiveDrc</b> - Der Status des Adaptive DRC ("auto" =&gt; an, "off" =&gt; aus)</li>
  <li><b>dsp</b> - Das aktuell aktive DSP Preset</li>
  <li><b>enhancer</b> - Der Status des Enhancers ("on" =&gt; an, "off" =&gt; aus)</li>
  <li><b>input</b> - Der ausgew&auml;hlte Eingang entsprechend dem FHEM-Kommando</li>
  <li><b>inputName</b> - Die Eingangsbezeichnung, so wie sie am Receiver eingestellt wurde und auf dem Display erscheint</li>
  <li><b>mute</b> - Der aktuelle Stumm-Status ("on" =&gt; Stumm, "off" =&gt; Laut)</li>
  <li><b>power</b> - Der aktuelle Betriebsstatus ("on" =&gt; an, "off" =&gt; aus)</li>
  <li><b>presence</b> - Die aktuelle Empfangsbereitschaft ("present" =&gt; empfangsbereit, "absent" =&gt; nicht empfangsbereit, z.B. Stromausfall)</li>
  <li><b>volume</b> - Der aktuelle Lautst&auml;rkepegel in Prozent (zwischen 0 und 100 %)</li>
  <li><b>volumeStraight</b> - Der aktuelle Lautst&auml;rkepegel in Dezibel (zwischen -80.0 und +15 dB)</li>
  <li><b>direct</b> - Zeigt an, ob soundverbessernde Features umgangen werden oder nicht ("on" =&gt; soundverbessernde Features werden umgangen, "off" =&gt; soundverbessernde Features werden benutzt)</li>
  <li><b>straight</b> - Zeigt an, ob die interne Codec Umwandlung umgangen wird oder nicht ("on" =&gt; Codec Umwandlung wird umgangen, "off" =&gt; Codec Umwandlung wird benutzt)</li>
  <li><b>sleep</b> - Zeigt den Status des internen Sleep-Timers an</li>
  <li><b>state</b> - Der aktuelle Schaltzustand (power-Reading) oder die Abwesenheit des Ger&auml;tes (m&ouml;gliche Werte: "on", "off" oder "absent")</li>
  <br><br><u>Eingangsabh&auml;ngige Readings/Events:</u><br>
  <li><b>currentChannel</b> - Nummer des Eingangskanals (nur bei SIRIUS)</li>
  <li><b>currentStation</b> - Name des Radiosenders (nur bei TUNER, NET RADIO und PANDORA)</li>
  <li><b>currentAlbum</b> - Album es aktuell gespielten Titel</li>
  <li><b>currentArtist</b> - Interpret des aktuell gespielten Titel</li>
  <li><b>currentTitle</b> - Name des aktuell gespielten Titel</li>
  <li><b>playStatus</b> - Wiedergabestatus des Eingangs</li>
  <li><b>shuffle</b> - Status der Zufallswiedergabe des aktuellen Eingangs</li>
  <li><b>repeat</b> - Status der Titelwiederholung des aktuellen Eingangs</li>
  </ul>
<br>
  <b>Hinweise des Autors</b>
  <ul>
    Dieses Modul ist nur nutzbar, wenn die Option "Network Standby" am Receiver aktiviert ist. Ansonsten ist die Steuerung nur im eingeschalteten Zustand m&ouml;glich.
  </ul>
  <br>
</ul>
=end html_DE

=cut
