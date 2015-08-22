##############################################
# $Id: 98_FReplacer.pm 
#
# Basiert auf der Idee Fhem Daten auf einem Kindle anzuzeigen
# wie im Forum beschrieben
#
##############################################################################
#   Changelog:
#
#   2014-07-12  initial version
#   2014-10-02  fixed some minor issues and added documentation
#   2014-10-19  fixed a typo and some minor issues
#   2014-11-04  renamed some attributes and added PostCommand to make the module more flexible
#   2014-11-08  added the attributes Reading.*, MaxAge.*, MinValue.*, MaxValue.* and Format.*
#   2014-11-15  fixed bugs related to RepReading and InternalTimer
#   2014-12-05  definierte Attribute werden der userattr list der Instanz hinzugefügt

package main;

use strict;
use warnings;

use Time::HiRes qw( time );
use POSIX qw(strftime);
use Encode qw(decode encode);

sub FReplacer_Initialize($);
sub FReplacer_Define($$);
sub FReplacer_Undef($$);
sub FReplacer_Update($);
sub FReplacer_Attr(@);

require "$attr{global}{modpath}/FHEM/99_Utils.pm";

#####################################
sub FReplacer_Initialize($)
{
    my ($hash) = @_;

    $hash->{DefFn}   =  "FReplacer_Define";
    $hash->{UndefFn} =  "FReplacer_Undef";
    $hash->{AttrFn}  =  "FReplacer_Attr";
    $hash->{SetFn}   =  "FReplacer_Set";
    $hash->{AttrList}=  "Rep[0-9]+Regex " .         # Match für Ersetzungen
                        "Rep[0-9]+Reading " .       # Reading for Replacement
                        "Rep[0-9]+MaxAge " .        # optional Max age of Reading
                        "Rep[0-9]+MinValue " .      # optional Min Value of Reading
                        "Rep[0-9]+MaxValue " .      # optional Max Value of Reading
                        "Rep[0-9]+Format " .        # optional Format string for Replacement
                        "Rep[0-9]+Expr " .          # optional Expression to be evaluated before using the replacement
                        "ReplacementEncode " .      # Ergebnis einer Ersetzung z.B. in UTF-8 Encoden
                        "PostCommand " .            # Systembefehl, der nach der Ersetzung ausgeführt wird
                        $readingFnAttributes;  
}


#####################################
sub FReplacer_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t]+", $def);
    my ($name, $FReplacer, $template, $output, $interval) = @a;
    return "wrong syntax: define <name> FReplacer [Template] [Output] [interval]"
        if(@a < 4);
    $hash->{TEMPLATE} = $template;
    $hash->{OUTPUT}   = $output;    
    if (!defined($interval)) {
        $hash->{INTERVAL} = 60; 
    } else {
        $hash->{INTERVAL} = $interval;
    }
    RemoveInternalTimer ($hash);
    InternalTimer(gettimeofday()+1, "FReplacer_Update", $hash, 0);
    return undef;
}


#####################################
sub
FReplacer_Undef($$)
{
    my ($hash, $arg) = @_;
    #my $name = $hash->{NAME};
    RemoveInternalTimer ($hash);
    return undef;
}


#
# Attr command 
##############################################################
sub
FReplacer_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

    # Attributes are Regexp.*, Expr.*
    # Regex.* and Expr.* need validation
    
    if ($cmd eq "set") {
        if ($aName =~ "Regex") {
            eval { qr/$aVal/ };
            if ($@) {
                Log3 $name, 3, "$name: Invalid regex in attr $name $aName $aVal: $@";
                return "Invalid Regex $aVal in $aName";
            }
        } elsif ($aName =~ "Expr") {
            my $replacement = "";
            eval $aVal;
            if ($@) {
                Log3 $name, 3, "$name: Invalid Expression in attr $name $aName $aVal: $@";
                return "Invalid Expression $aVal in $aName";
            }
        } elsif ($aName =~ "MaxAge") {
            if ($aVal !~ '([0-9]+):(.+)') {
                Log3 $name, 3, "$name: wrong format in attr $name $aName $aVal";
                return "Invalid Format $aVal in $aName";
            }
        } elsif ($aName =~ "MinValue") {
            if ($aVal !~ '(^-?\d+\.?\d*):(.+)') {
                Log3 $name, 3, "$name: wrong format in attr $name $aName $aVal";
                return "Invalid Format $aVal in $aName";
            }
        } elsif ($aName =~ "MaxValue") {
            if ($aVal !~ '(^-?\d+\.?\d*):(.+)') {
                Log3 $name, 3, "$name: wrong format in attr $name $aName $aVal";
                return "Invalid Format $aVal in $aName";
            }
        } elsif ($aName =~ "Format") {
            my $useless = eval { sprintf ($aVal, 1) };
            if ($@) {
                Log3 $name, 3, "$name: Invalid Format in attr $name $aName $aVal: $@";
                return "Invalid Format $aVal";
            }
        } 
        addToDevAttrList($name, $aName)
    }
    return undef;
}

# SET command
#########################################################################
sub FReplacer_Set($@)
{
    my ( $hash, @a ) = @_;
    return "\"set $a[0]\" needs at least an argument" if ( @a < 2 );
    
    # @a is an array with DeviceName, SetName, Rest of Set Line
    my ($name, $setName, $setVal) = @a;
    
    if($setName eq "ReplaceNow") {
        Log3 $name, 5, "$name: Set ReplaceNow is calling FReplacer_Update";
        RemoveInternalTimer ($hash);
        FReplacer_Update($hash);
    } else {
        return "Unknown argument $setName, choose one of ReplaceNow";
    }
}
    
    
    
#####################################
sub
FReplacer_Update($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "FReplacer_Update", $hash, 0);
    Log3 $name, 5, "$name: Update: Internal timer set for hash $hash to call update again in $hash->{INTERVAL} seconds";
    
    my ($tmpl, $out);
    if (!open($tmpl, "<", $hash->{TEMPLATE})) {
        Log3 $name, 3, "$name: Cannot open template file $hash->{TEMPLATE}";
        return;
    };
    if (!open($out, ">", $hash->{OUTPUT})) {
        Log3 $name, 3, "$name: Cannot create output file $hash->{OUTPUT}";
        return;
    };
    my $content = "";
    while (<$tmpl>) {
        $content .= $_;
    }
    
    my $time = strftime("%d.%m.%Y   %T", localtime);
    readingsSingleUpdate($hash, "LastUpdate", $time, 1 );
    
    foreach my $key (keys %{$attr{$name}}) {
        if ($key =~ /Rep([0-9]+)Regex/) {
            my $index = $1;
            my $regex = $attr{$name}{"Rep${index}Regex"};
            my $replacement = "";
            my $skip = 0;
            
            if ($attr{$name}{"Rep${index}Reading"}) {
                if ($attr{$name}{"Rep${index}Reading"} !~ '([^\:]+):([^\:]+):?(.*)') {
                    Log3 $name, 3, "$name: wrong format in attr Rep${index}Reading";
                    next;
                }
                my $device  = $1;
                my $rname   = $2;
                my $default = ($3 ? $3 : 0);
                my $timestamp = ReadingsTimestamp ($device, $rname, 0);
                $replacement  = ReadingsVal($device, $rname, $default);
                Log3 $name, 5, "$name: got reading $rname of device $device with default $default as $replacement with timestamp $timestamp";
                if ($attr{$name}{"Rep${index}MaxAge"}) {
                    if ($attr{$name}{"Rep${index}MaxAge"} !~ '([0-9]+):(.+)') {
                        Log3 $name, 3, "$name: wrong format in attr Rep${index}MaxAge";
                        next;
                    }
                    my $max = $1;
                    my $rep = $2;
                    Log3 $name, 5, "$name: check max age $max";
                    if (gettimeofday() - time_str2num($timestamp) > $max) {
                        Log3 $name, 5, "$name: reading too old - using $rep instead and skipping optional Expr and Format attributes";
                        $replacement = $rep;
                        $skip = 1;
                    }
                }
                if ($attr{$name}{"Rep${index}MinValue"} && !$skip) {
                    if ($attr{$name}{"Rep${index}MinValue"} !~ '(^-?\d+\.?\d*):(.+)') {
                        Log3 $name, 3, "$name: wrong format in attr Rep${index}MinValue";
                        next;
                    }
                    my $lim = $1;
                    my $rep = $2;
                    Log3 $name, 5, "$name: check min value $lim";
                    if ($replacement < $lim) {
                        Log3 $name, 5, "$name: reading too small - using $rep instead and skipping optional Expr and Format attributes";
                        $replacement = $rep;
                        $skip = 1;
                    }
                }
                if ($attr{$name}{"Rep${index}MaxValue"} && !$skip) {
                    if ($attr{$name}{"Rep${index}MaxValue"} !~ '(^-?\d+\.?\d*):(.+)') {
                        Log3 $name, 3, "$name: wrong format in attr Rep${index}MaxValue";
                        next;
                    }
                    my $lim = $1;
                    my $rep = $2;
                    Log3 $name, 5, "$name: check max value $lim";
                    if ($replacement > $lim) {
                        Log3 $name, 5, "$name: reading too big - using $rep instead and skipping optional Expr and Format attributes";
                        $replacement = $rep;
                        $skip = 1;
                    }
                }
            }
            if ($attr{$name}{"Rep${index}Expr"} && !$skip) {
                Log3 $name, 5, "$name: Evaluating Expr" . $attr{$name}{"Rep${index}Expr"} .
                    "\$replacement = $replacement";
                $replacement = eval($attr{$name}{"Rep${index}Expr"});
                Log3 $name, 5, "$name: result is $replacement";
                if ($@) {
                    Log3 $name, 3, "$name: error evaluating attribute Rep${index}Expr: $@";
                    next;
                }
            }
            if ($attr{$name}{"Rep${index}Format"} && !$skip) {
                Log3 $name, 5, "$name: doing sprintf with format" . $attr{$name}{"Rep${index}Format"} .
                    "value is $replacement";
                $replacement = sprintf($attr{$name}{"Rep${index}Format"}, $replacement);
                Log3 $name, 5, "$name: result is $replacement";
            }
            
            Log3 $name, 5, "$name: Replacing $regex with $replacement";
            $replacement = encode(AttrVal($name, "ReplacementEncode", undef), $replacement) 
                if (AttrVal($name, "ReplacementEncode", undef));
            Log3 $name, 5, "$name: Replacement encoded as $replacement";
            $content =~ s/$regex/$replacement/g;
        }
    }
    print $out $content;
    
    if (AttrVal($name, "PostCommand", undef)) {
        my $convCmd = (AttrVal($name, "PostCommand", undef));
        Log3 $name, 5, "$name: Start conversion as $convCmd";
        system ($convCmd);
        Log3 $name, 5, "$name: Conversion started";
    }
}

1;

=pod
=begin html

<a name="FReplacer"></a>
<h3>FReplacer</h3>

<ul>
    This module provides a generic way to modify the contents of a file with Readings of other devices or the result of Perl expressions.<br>
    The typical use case is a custom designed SVG graphics template file which contains place holders that will be replaced with actual values.<br>
    The resulting SVG file can then optionally be converted to a PNG file which can be used as an online screensaver for Kindle devices for example.
    <br><br>

    <a name="FReplacerdefine"></a>
    <b>Define</b>
    <ul>
        <br>
        <code>define &lt;name&gt; FReplacer &lt;InputFile&gt; &lt;OutputFile&gt; &lt;Interval&gt;</code>
        <br><br>
        The module reads the given InputFile every Interval seconds, replaces strings with the results of expressions as defined in attributes and writes the result to the OutputFile<br>
        <br>
        Example:<br>
        <ul><code>define fr FReplacer /opt/fhem/www/images/template.svg /opt/fhem/www/images/status.svg 60</code></ul>
    </ul>
    <br>

    <a name="FReplacerconfiguration"></a>
    <b>Configuration of FReplacer Devices</b><br><br>
    <ul>
        Specify pairs of <code>attr FxxRegex</code> and <code>attr FxxReading</code> or <code>attr FxxExpr</code> to define which strings / placeholders in the InputFile should be replaced with which redings / expressions
        <br><br>
        Example:<br>
        <ul><code>
        define fr FReplacer /opt/fhem/www/images/template.svg /opt/fhem/www/images/status.svg 60 <br>
        attr fr Rep01Regex HeizungStat<br>
        attr fr Rep01Reading WP:Status<br>
        attr fr Rep01MaxAge 600:Heizung Aus<br>
        attr fr Rep02Regex AbluftTemp<br>
        attr fr Rep02Reading Lueftung:Temp_Abluft<br> 
        attr fr Rep02Format "%.1f"<br>
        attr fr Rep03Regex AussenTemp<br>
        attr fr Rep03Expr sprintf("%.1f", ReadingsVal("Lueftung", "Temp_Aussen", 0))<br>
        </code></ul>
        <br>
        If you want to convert a resulting SVG file to a PNG e.g. for use as online screen saver on a Kindle device, <br>
        you have to specify the external conversion command with the attribute PostCommand, for Example:<br>
        <ul><code>
        attr fr PostCommand convert /opt/fhem/www/images/status.svg -type GrayScale -depth 8 /opt/fhem/www/images/status.png 2>/dev/null &
        </code></ul>
        <br>
        If you want to convert the replacement text from Readings to UTF8, e.g. to make special characters / umlauts display correctly, specify 
        <ul><code>
        attr fr ReplacementEncode UTF-8
        </code></ul>
        <br>
    </ul>
    
    <a name="FReplacerset"></a>
    <b>Set-Commands</b><br>
    <ul>
        <li><b>ReplaceNow</b></li>
            starts a replace without waiting for the interval
    </ul>
    <br>
    <a name="FReplacerget"></a>
    <b>Get-Commands</b><br>
    <ul>
        none
    </ul>
    <br>
    <a name="FReplacerattr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><b>Rep[0-9]+Regex</b></li>
            defines the regex to be used for finding the right string to be replaced with the corresponding Reading / Expr result
        <li><b>Rep[0-9]+Reading</b></li>
            defines a device and reading to be used as replacement value. It is specified as devicename:readingname:default_value.<br>
            The default_value is optional and defaults to 0. If the reading doesn't exist, default_value is used.
        <li><b>Rep[0-9]+MaxAge</b></li>
            this can optionally be used together with RepReading to define a maximum age of the reading. It is specified as seconds:replacement. If the corresponding reading has not been updated for the specified number of seconds, then the replacement string is used instead of the reading to do the replacement and further RepExpr or RepFormat attributes will be ignored for this value<br>
        <li><b>Rep[0-9]+MinValue</b></li>
            this can optionally be used together with RepReading to define a minimum value of the reading. It is specified as min:replacement. If the corresponding reading is too small, then the replacement string is used instead of the reading to do the replacement and further RepExpr or RepFormat attributes will be ignored for this value<br>
        <li><b>Rep[0-9]+MaxValue</b></li>
            this can optionally be used together with RepReading to define a maximum value of the reading. It is specified as max:replacement. If the corresponding reading is too big, then the replacement string is used instead of the reading to do the replacement and further RepExpr or RepFormat attributes will be ignored for this value<br>
        <li><b>Rep[0-9]+Expr</b></li>
            defines an optional expression that can be used to compute the replacement value. If RepExpr is used together with RepReading then the expression is evaluated after getting the reading and the value of the reading can be used in the expression as $replacement. <br>
            If only RepExpr is specified then readings can be retrieved with the perl function ReadingsVal() inside the expression. <br>
            If neither RepExpr nor RepReading is specified then the match for the correspondig regex will be replaced with an empty string.
        <li><b>Rep[0-9]+Format</b></li>
            defines an optional format string to be used in a sprintf statement to format the replacement before it is applied.<br>
            Can be used with RepReading or RepExpr or both.
        <li><b>PostCommand</b></li>
            Execute an external command after writing the output file, e.g. to convert a resulting SVG file to a PNG file.
            For an eInk Kindle you need a PNG in 8 bit greyscale format. A simple example to call the convert utility from ImageMagick would be <br>
            <code> attr fr PostCommand convert /opt/fhem/www/images/status.svg 
                -type GrayScale -depth 8 /opt/fhem/www/images/status.png 2>/dev/null & </code><br>
            a more advanced example that starts inkscape before Imagemagick to make sure that embedded Icons in a SVG file are converted 
            correctly could be <br>
            <code> attr fr PostCommand bash -c 'inkscape /opt/fhem/www/images/status.svg -e=tmp.png;; convert tmp.png -type GrayScale -depth 8 /opt/fhem/www/images/status.png' >/dev/null 2>&1 & </code><br>
            or even <br>
            <code> attr fr PostCommand bash -c 'inkscape /opt/fhem/www/images/status.svg -e=tmp.png -b=rgb\(255,255,255\) --export-height=1024 --export-width=758;; convert tmp.png -type GrayScale -depth 8 /opt/fhem/www/images/status.png' >/dev/null 2>&1 & </code><br>
            Inkscape might be needed because ImageMagick seems to have problems convertig SVG files with embedded icons. However a PNG file created by Inkscape is not in 8 bit greyscale so Imagemagick can be run after Inkscape to convert to 8 bit greyscale
        <li><b>ReplacementEncode</b></li>
            defines an encoding to apply to the replacement string, e.g. UTF-8
    </ul>
</ul>

=end html
=cut
