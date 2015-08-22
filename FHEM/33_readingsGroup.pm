# $Id: 33_readingsGroup.pm 8462 2015-04-22 15:22:22Z justme1968 $
##############################################################################
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

use vars qw($FW_ME);
use vars qw($FW_wname);
use vars qw($FW_subdir);
use vars qw(%FW_hiddenroom);
use vars qw(%FW_visibleDeviceHash);
use vars qw(%FW_webArgs); # all arguments specified in the GET

my @mapping_attrs = qw( commands:textField-long mapping:textField-long nameIcon:textField-long cellStyle:textField-long nameStyle:textField-long valueColumn:textField-long valueColumns:textField-long valueFormat:textField-long valuePrefix:textField-long valueSuffix:textField-long valueIcon:textField-long valueStyle:textField-long );

sub readingsGroup_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "readingsGroup_Define";
  $hash->{NotifyFn} = "readingsGroup_Notify";
  $hash->{UndefFn}  = "readingsGroup_Undefine";
  $hash->{SetFn}    = "readingsGroup_Set";
  $hash->{GetFn}    = "readingsGroup_Get";
  $hash->{AttrFn}   = "readingsGroup_Attr";
  $hash->{AttrList} = "disable:1,2,3 style timestampStyle ". join( " ", @mapping_attrs ) ." separator nolinks:1 noheading:1 nonames:1 notime:1 nostate:1 alwaysTrigger:1 sortDevices:1 visibility:hidden,hideable,collapsed,collapsible";

  $hash->{FW_detailFn}  = "readingsGroup_detailFn";
  $hash->{FW_summaryFn}  = "readingsGroup_detailFn";

  $hash->{FW_atPageEnd} = 1;
}

sub
readingsGroup_updateDevices($;$)
{
  my ($hash,$def) = @_;
  $def = $hash->{helper}{DEF} if( !defined($def) );
  $hash->{helper}{DEF} = $def;
  $def = $hash->{DEF} if( !defined($def) );

  my %list;
  my %list2;
  my @devices;
  my @devices2;

  my @params = split(" ", $def);
  while (@params) {
    my $param = shift(@params);

    while ($param && $param =~ m/^</ && $param !~ m/>$/ ) {
      my $next = shift(@params);
      last if( !defined($next) );
      $param .= " ". $next;
    }

    # for backwards compatibility with weblink readings
    if( $param eq '*noheading' ) {
      $attr{$hash->{NAME}}{noheading} = 1;
      $hash->{DEF} =~ s/(\s*)\\$param((:\S+)?\s*)/ /g;
      $hash->{DEF} =~ s/^ //;
      $hash->{DEF} =~ s/ $//;
    } elsif( $param eq '*notime' ) {
      $attr{$hash->{NAME}}{notime} = 1;
      $hash->{DEF} =~ s/(\s*)\\$param((:\S+)?\s*)/ /g;
      $hash->{DEF} =~ s/^ //;
      $hash->{DEF} =~ s/ $//;
    } elsif( $param eq '*nostate' ) {
      $attr{$hash->{NAME}}{nostate} = 1;
      $hash->{DEF} =~ s/(\s*)\\$param((:\S+)?\s*)/ /g;
      $hash->{DEF} =~ s/^ //;
      $hash->{DEF} =~ s/ $//;
    } elsif( $param =~ m/^{/) {
      $attr{$hash->{NAME}}{mapping} = $param ." ". join( " ", @params );
      $hash->{DEF} =~ s/\s*[{].*$//g;
      last;
    } else {
      my @device = split(":", $param);

      if( $device[1] && $device[1] =~ m/^FILTER=/ ) {
        my $devspec = shift(@device);
        while( @device && $device[0] =~ m/^FILTER=/ ) {
          $devspec .= ":";
          $devspec .= shift(@device)
        }
        my $regex =  $device[0];
        foreach my $d (devspec2array($devspec)) {
          $list{$d} = 1;
          push @devices, [$d,$regex];
        }

      } elsif($device[0] =~ m/(.*)=(.*)/) {
        my ($lattr,$re) = ($1, $2);
        foreach my $d (sort keys %defs) {
          next if( IsIgnored($d) );
          next if( !defined($defs{$d}{$lattr}) );
          next if( $lattr ne 'IODev' && $defs{$d}{$lattr} !~ m/^$re$/);
          next if( $lattr eq 'IODev' && $defs{$d}{$lattr}{NAME} !~ m/^$re$/);
          $list{$d} = 1;
          push @devices, [$d,$device[1]];
        }

      } elsif($device[0] =~ m/(.*)&(.*)/) {
        my ($lattr,$re) = ($1, $2);
        foreach my $d (sort keys %attr) {
          next if( IsIgnored($d) );
          next if( !defined($attr{$d}{$lattr}) );
          next if( $attr{$d}{$lattr} !~ m/^$re$/);
          $list{$d} = 1;
          push @devices, [$d,$device[1]];
        }

      } elsif($device[0] =~ m/^<.*>$/) {
        push @devices, [$device[0]];

      } elsif( defined($defs{$device[0]}) ) {
        $list{$device[0]} = 1;
        push @devices, [@device];

      } else {
        foreach my $d (sort keys %defs) {
          next if( IsIgnored($d) );
          eval { $d =~ m/^$device[0]$/ };
          if( $@ ) {
            Log3 $hash->{NAME}, 3, $hash->{NAME} .": ". $device[0] .": ". $@;
            push @devices, ["<<ERROR>>"];
            last;
          }
          next if( $d !~ m/^$device[0]$/);
          $list{$d} = 1;
          push @devices, [$d,$device[1]];
        }
      }
    }
  }

  foreach my $device (@devices) {
    my $regex = $device->[1];
    my @list = (undef);
    @list = split(",",$regex) if( $regex );
    my $first = 1;
    my $multi = @list;
    for( my $i = 0; $i <= $#list; ++$i ) {
      my $regex = $list[$i];
      while ($regex
             && ( ($regex =~ m/^</ && $regex !~ m/>$/)          #handle , in <...>
                  || ($regex =~ m/@\{/ && $regex !~ m/}$/) )    #handle , in reading@{...}
             && defined($list[++$i]) ) {
        $regex .= ",". $list[$i];
      }

      next if( !$regex );

      if( $regex =~ m/^<.*>$/ ) {
      } elsif( $regex =~ m/(.*)@(.*)/ ) {
        $regex = $1;

        next if( $regex && $regex =~ m/^\+(.*)/ );
        next if( $regex && $regex =~ m/^\?(.*)/ );

        my $name = $2;
        if( $name =~ m/^{(.*)}$/ ) {
          my $DEVICE = $device->[0];
          $name = eval $name;
        }

        next if( !$name );
        next if( !defined($defs{$name}) );

        $list2{$name} = 1;

        @devices2 = @devices if( !@devices2 );

        my $found = 0;
        foreach my $device (@devices2) {

          $found = 1 if( $device->[0] eq $name && $device->[1] eq $regex );
          last if $found;
        }
        next if $found;

        push @devices2, [$name,$regex];
      }
    }
  }

  if( AttrVal( $hash->{NAME}, "sortDevices", 0 ) == 1 ) {
    @devices = sort { my $aa = @{$a}[0]; my $bb =  @{$b}[0];
                      $aa = "#" if( $aa =~ m/^</ );
                      $bb = "#" if( $bb =~ m/^</ );
                      lc(AttrVal($aa,"sortby",AttrVal($aa,"alias",$aa))) cmp
                      lc(AttrVal($bb,"sortby",AttrVal($bb,"alias",$bb))) } @devices;
  }

  $hash->{CONTENT} = \%list;
  $hash->{DEVICES} = \@devices;
  $hash->{CONTENT2} = \%list2;
  delete $hash->{DEVICES2};
  $hash->{DEVICES2} = \@devices2 if( @devices2 );

  $hash->{fhem}->{last_update} = gettimeofday();
  $hash->{fhem}->{lastDefChange} = $lastDefChange;
}

sub readingsGroup_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> readingsGroup <device>+"  if(@args < 3);

  my $name = shift(@args);
  my $type = shift(@args);

  readingsGroup_updateDevices($hash);

  $hash->{STATE} = 'Initialized';

  return undef;
}

sub readingsGroup_Undefine($$)
{
  my ($hash,$arg) = @_;

  return undef;
}

sub
lookup($$$$$$$$$)
{
  my($mapping,$name,$alias,$reading,$value,$room,$group,$row,$default) = @_;

  if( $mapping ) {
    if( !ref($mapping) && $mapping =~ m/^{.*}$/) {
      my $DEVICE = $name;
      my $READING = $reading;
      my $VALUE = $value;
      my $ROW = $row;
      my $m = eval $mapping;
      if( $@ ) {
        Log 2, $@ if( $@ );
      } else {
        $mapping = $m;
      }
    }

    if( ref($mapping) eq 'HASH' ) {
      $default = $mapping->{$name} if( defined($mapping->{$name}) );
      $default = $mapping->{$reading} if( defined($mapping->{$reading}) );
      $default = $mapping->{$name.".".$reading} if( defined($mapping->{$name.".".$reading}) );
      $default = $mapping->{$reading.".".$value} if( defined($mapping->{$reading.".".$value}) );
    } else {
      $default = $mapping;
    }

    if( !ref($default) && $default =~ m/^{.*}$/) {
      my $DEVICE = $name;
      my $READING = $reading;
      my $VALUE = $value;
      my $ROW = $row;
      $default = eval $default;
      $default = "" if( $@ );
      Log 2, $@ if( $@ );
    }

    return $default if( !defined($default) );

    $default =~ s/\%ALIAS/$alias/g;
    $default =~ s/\%DEVICE/$name/g;
    $default =~ s/\%READING/$reading/g;
    $default =~ s/\%VALUE/$value/g;
    $default =~ s/\%ROOM/$room/g;
    $default =~ s/\%GROUP/$group/g;
    $default =~ s/\%ROW/$row/g;

    $default =~ s/\$ALIAS/$alias/g;
    $default =~ s/\$DEVICE/$name/g;
    $default =~ s/\$READING/$reading/g;
    $default =~ s/\$VALUE/$value/g;
    $default =~ s/\$ROOM/$room/g;
    $default =~ s/\$GROUP/$group/g;
    $default =~ s/\$ROW/$row/g;
  }

  return $default;
}
sub
lookup2($$$$;$$)
{
  my($lookup,$name,$reading,$value,$row,$column) = @_;

  return "" if( !$lookup );

  if( !ref($lookup) && $lookup =~ m/^{.*}$/) {
    my $DEVICE = $name;
    my $READING = $reading;
    my $VALUE = $value;
    my $ROW = $row;
    my $COLUMN = $column;
    my $l = eval $lookup;
    if( $@ ) {
      Log 2, $@ if( $@ );
    } else {
      $lookup = $l;
    }
  }

  if( ref($lookup) eq 'HASH' ) {
    my $vf = "";
    $vf = $lookup->{$reading} if( defined($reading) && exists($lookup->{$reading}) );
    $vf = $lookup->{$name.".".$reading} if( defined($reading) && exists($lookup->{$name.".".$reading}) );
    $vf = $lookup->{$reading.".".$value} if( defined($value) && exists($lookup->{$reading.".".$value}) );
    $vf = $lookup->{"r:$row"} if( defined($row) && exists($lookup->{"r:$row"}) );
    $vf = $lookup->{"c:$column"} if( defined($column) && exists($lookup->{"c:$column"}) );
    $vf = $lookup->{"r:$row,c:$column"} if( defined($row) && defined($column) && exists($lookup->{"r:$row,c:$column"}) );
    $lookup = $vf;
  }

  return undef if( !defined($lookup) );

  if( !ref($lookup) && $lookup =~ m/^{.*}$/) {
    my $DEVICE = $name;
    my $READING = $reading;
    my $VALUE = $value;
    my $ROW = $row;
    my $COLUMN = $column;
    $lookup = eval $lookup;
    $lookup = "" if( $@ );
    Log 2, $@ if( $@ );
  }

  return undef if( !defined($lookup) );

  $lookup =~ s/\%DEVICE/$name/g;
  $lookup =~ s/\%READING/$reading/g;
  $lookup =~ s/\%VALUE/$value/g;

  $lookup =~ s/\$DEVICE/$name/g;
  $lookup =~ s/\$READING/$reading/g;
  $lookup =~ s/\$VALUE/$value/g;

  return $lookup;
}
sub
readingsGroup_makeLink($$$)
{
  my($v,$devStateIcon,$cmd) = @_;

  if( $cmd ) {
    my $txt = $v;
    $txt = $devStateIcon if( $devStateIcon );
    my $link = "cmd=$cmd";
    if( AttrVal($FW_wname, "longpoll", 1)) {
      $txt = "<a style=\"cursor:pointer\" onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$link')\">$txt</a>";
    } else {
      my $room = $FW_webArgs{room};
      $room = "&detail=$FW_webArgs{detail}" if( $FW_webArgs{"detail"} );
      my $srf = $room ? "&room=$room" : "";
      $srf = $room if( $room && $room =~ m/^&/ );
      $txt = "<a href=\"$FW_ME$FW_subdir?$link$srf\">$txt</a>";
    }
    if( !$devStateIcon ) {
      $v = $txt;
    } else {
      $devStateIcon = $txt;
    }
  }

  return ($v, $devStateIcon);
}

sub
readingsGroup_2html($;$)
{
  my($hash,$extPage) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );
  return undef if( !$hash );

  #if( $hash->{fhem}->{cached} && $hash->{fhem}->{lastDefChange} && $hash->{fhem}->{lastDefChange} == $lastDefChange ) {
  #  return $hash->{fhem}->{cached};
  #}

  my $def = $hash->{helper}{DEF};
  $def = $hash->{DEF} if( !defined($def) );

  if( $def && $def =~ m/=/
      || $hash->{fhem}->{lastDefChange} != $lastDefChange ) {
    if( !$hash->{fhem}->{last_update}
        || $hash->{fhem}->{lastDefChange} != $lastDefChange
        || gettimeofday() - $hash->{fhem}->{last_update} > 600 ) {
      readingsGroup_updateDevices($hash);
    }
  }

  my $d = $hash->{NAME};

  my $show_links = !AttrVal( $d, "nolinks", "0" );
  $show_links = 0 if($FW_hiddenroom{detail});

  my $show_heading = !AttrVal( $d, "noheading", "0" );
  my $show_names = !AttrVal($d, "nonames", "0" );

  my $disable = AttrVal($d,"disable", 0);
  if( AttrVal($d,"disable", 0) > 2 ) {
    return "";
  } elsif( AttrVal($d,"disable", 0) > 1 ) {
    my $ret;
    $ret .= "<table>";
    my $txt = AttrVal($d, "alias", $d);
    $txt = "<a href=\"$FW_ME$FW_subdir?detail=$d\">$txt</a>" if( $show_links );
    $ret .= "<tr><td><div class=\"devType\">$txt</a></div></td></tr>" if( $show_heading );
    $ret .= "<tr><td><table class=\"block wide\">";
    #$ret .= "<div class=\"devType\"><a style=\"color:#ff8888\" href=\"$FW_ME$FW_subdir?detail=$d\">readingsGroup $txt is disabled.</a></div>";
    $ret .= "<td><div style=\"color:#ff8888;text-align:center\">disabled</div></td>";
    $ret .= "</table></td></tr>";
    $ret .= "</table>";
    return $ret;
  }

  my $show_time = !AttrVal( $d, "notime", "0" );
  my $show_state = !AttrVal( $d, "nostate", "0" );

  my $separator = AttrVal( $d, "separator", ":" );

  my $style = AttrVal( $d, "style", "" );
  if( $style =~ m/^{.*}$/ ) {
    my $s = eval $style;
    $style = $s if( $s );
  }

  my $timestamp_style = AttrVal( $d, "timestampStyle", "" );

  my $devices = $hash->{DEVICES};

  my $group;
  $group = $extPage->{group} if( $extPage );
  $group = AttrVal( $d, "group", undef ) if( !$group );
  $group = "" if( !$group );
  $group =~ s/,/_/g;

  my $show_hide = "";
  my $visibility = AttrVal($d, "visibility", undef );
  if( !$FW_webArgs{"detail"} ) {
    if( $visibility && ( $visibility eq "hidden" || $visibility eq "hideable" ) ) {
      $style = 'style=""' if( !$style );
      $style =~ s/style=(.)/style=$1display:none;/ if( $visibility eq "hidden" );
      $show_hide .= "<a style=\"cursor:pointer\" onClick=\"FW_readingsGroupToggle('$d')\">&gt;</a>";
    }
  }

  my $row = 1;
  my $cell_row = 0;
  my $ret;
  $ret .= "<table>";
  my $txt = AttrVal($d, "alias", $d);
  $txt = "<a href=\"$FW_ME$FW_subdir?detail=$d\">$txt</a>" if( $show_links );
  $ret .= "<tr><td><div class=\"devType\">$show_hide&nbsp;$txt</div></td></tr>" if( $show_heading );
  $ret .= "<tr><td><table $style id='readingsGroup-$d' groupId=\"$group\" class=\"block wide readingsGroup\">";
  $ret .= "<tr><td colspan=\"99\"><div style=\"color:#ff8888;text-align:center\">updates disabled</div></tr>" if( $disable > 0 );

  foreach my $device (@{$devices}) {
    my $item = 0;
    my $h = $defs{$device->[0]};
    my $regex = $device->[1];
    if( !$h && $device->[0] =~ m/^<.*>$/ ) {
      $h = $hash if( !$h );
      $regex = $device->[0];
    }
    next if( !$h );
    my $name = $h->{NAME};  #FIXME: name/name2 confusion
    my $name2 = $h->{NAME};

    my @list = (undef);
    @list = split(",",$regex) if( $regex );
    my $first = 1;
    my $multi = @list;
    ++$cell_row;
    my $cell_column = 1;
    #foreach my $regex (@list) {
    for( my $i = 0; $i <= $#list; ++$i ) {
      my $name = $name;
      my $name2 = $name2;
      my $regex = $list[$i];
      while ($regex
             && ( ($regex =~ m/^</ && $regex !~ m/>$/)          #handle , in <...>
                  || ($regex =~ m/@\{/ && $regex !~ m/}$/) )    #handle , in reading@{...}
             && defined($list[++$i]) ) {
        $regex .= ",". $list[$i];
      }
      my $h = $h;
      my $force_show = 0;
      if( $regex && $regex =~ m/^<(.*)>$/ ) {
        my $txt = $1;
        my $readings;
        $item++;
        if( $txt =~ m/^{(.*)}(@[\w\-|.*]+)?$/ ) {
          $txt = "{$1}";
          $readings = $2;

          my $new_line = $first;
          my $DEVICE = $name;
          ($txt,$new_line) = eval $txt;
          $first = $new_line if( defined($new_line) );
          if( $@ ) {
            $txt = "<ERROR>";
            Log3 $d, 3, $d .": ". $regex .": ". $@;
          }
          next if( !defined($txt) );
        }

        my $row_style = lookup2($hash->{helper}{rowStyle},$name,$1,undef,$cell_row,undef);
        my $cell_style0 = lookup2($hash->{helper}{cellStyle},$name,$1,undef,$cell_row,0);
        my $cell_style = lookup2($hash->{helper}{cellStyle},$name,$1,undef,$cell_row,$cell_column);
        my $name_style = lookup2($hash->{helper}{nameStyle},$name,$1,undef,$cell_row,$cell_column);
        my $value_columns = lookup2($hash->{helper}{valueColumns},$name,$1,undef,$cell_row,$cell_column);

        if( !$FW_webArgs{"detail"} ) {
          if( $visibility && $visibility eq "collapsed" && $txt ne '-' && $txt ne '+' && $txt ne '+-' ) {
            $row_style = 'style=""' if( !$row_style );
            $row_style =~ s/style=(.)/style=$1display:none;/;
          }
        }

        if( $txt eq 'br' ) {
          $ret .= sprintf("<tr class=\"%s\">", ($row-1&1)?"odd":"even");
          $ret .= "<td $value_columns><div $cell_style $name_style class=\"dname\"></div></td>";
          $first = 0;
          ++$cell_row;
          $cell_column = 1;
          next;
        } elsif( $txt eq '-' || $txt eq '+' || $txt eq '+-' ) {
          my $collapsed = $visibility && ( $visibility eq "collapsed" ) && !$FW_webArgs{"detail"};

          my $id = '';
          if( ($txt eq '+' && !$collapsed)
              || ($txt eq '-' && $collapsed ) ) {
            $id = '';
            $row_style = 'style=""' if( !$row_style );
            $row_style =~ s/style=(.)/style=$1display:none;/;
          } elsif( $txt eq '+-' ) {
            if( $collapsed ) {
              $txt = '+';
            } else {
              $txt = '-';
            }
            $id = "id='plusminus'";
          } elsif( $txt ne '+' && $collapsed ) {
            $row_style = 'style=""' if( !$row_style );
            $row_style =~ s/style=(.)/style=$1display:none;/;
          }

          $ret .= sprintf("<tr $row_style class=\"%s\">", ($row-1&1)?"odd":"even") if( $first );
          if( $visibility && ( $visibility eq "collapsed" || $visibility eq "collapsible" ) ) {
            $ret .= "<td $value_columns><div $id style=\"cursor:pointer\" onClick=\"FW_readingsGroupToggle2('$d')\">$txt</div></td>";
          } else {
            $ret .= "<td $value_columns><div>$txt</div></td>";
          }
          $first = 0;
          ++$cell_column;
          next;
        } elsif( $txt && $txt =~ m/^%([^%]*)(%(.*))?/ ) {
          my $icon = $1;
          my $cmd = $3;
          $txt = FW_makeImage( $icon, $icon, "icon" );

          $cmd = lookup2($hash->{helper}{commands},$name,$d,$icon) if( !defined($cmd) );

          ($txt,undef) = readingsGroup_makeLink($txt,undef,$cmd);

          if( $first || $multi == 1 ) {
            $ret .= sprintf("<tr $row_style class=\"%s\">", ($row&1)?"odd":"even");
            $row++;
          }
        } elsif( $first || $multi == 1 ) {
          $ret .= sprintf("<tr $row_style class=\"%s\">", ($row&1)?"odd":"even");
          $row++;

          if( $h != $hash ) {
            my $a = AttrVal($name2, "alias", $name2);
            my $m = "$a";
            $m = $a if( $multi != 1 );
            $m = "" if( !$show_names );
            my $room = AttrVal($name2, "room", "");
            my $group = AttrVal($name2, "group", "");
            my $txt = lookup($hash->{helper}{mapping},$name2,$a,"","",$room,$group,$cell_row,$m);

            $ret .= "<td $value_columns><div $cell_style0 $name_style class=\"dname\">$txt</div></td>" if( $show_names );
          }
        } else {
          my $webCmdFn = 0;
          my $cmd = lookup2($hash->{helper}{commands},$name,$d,$txt);

          if( $cmd && $cmd =~ m/^([\w\/.-]*):(\S*)?(\s\S*)?$/ ) {
            my $set = $1;
            my $values = $2;
            $set .= $3 if( $3 );

            if( !$values ) {
              my %extPage = ();
              my ($allSets, undef, undef) = FW_devState($name, "", \%extPage);
              my ($set) = split( ' ', $set, 2 );
              if( $allSets && $allSets =~ m/\b$set:([^ ]*)/) {
                 $values = $1;
              }
            }

            my $room = $FW_webArgs{room};
            $room = "&detail=$FW_webArgs{detail}" if( $FW_webArgs{"detail"} );

            my $htmlTxt;
            foreach my $fn (sort keys %{$data{webCmdFn}}) {
              no strict "refs";
              $htmlTxt = &{$data{webCmdFn}{$fn}}($FW_wname,$name,$room,$set,$values);
              use strict "refs";
              last if(defined($htmlTxt));
            }

            if( $htmlTxt && $htmlTxt =~ m/^<td>(.*)<\/td>$/ ) {
              $htmlTxt = $1;
             }

            if( $htmlTxt ) {
              $txt = $htmlTxt;
              $webCmdFn = 1;
            }
          }
          ($txt,undef) = readingsGroup_makeLink($txt,undef,$cmd) if( !$webCmdFn );
        }

        my $informid = "";
        $informid = "informId=\"$d-$name.i$item.item\"" if( $readings );
        $ret .= "<td $value_columns><div $cell_style $name_style $informid>$txt</div></td>";
        $first = 0;
        ++$cell_column;
        next;
      } else {
        if( $regex && $regex =~ m/(.*)@([!]?)(.*)/ ) {
          $regex = $1;
          my $force_device = $2;
          $name = $3;
          if( $name =~ m/^{(.*)}$/ ) {
            my $DEVICE = $device->[0];
            $name = eval $name;
          }
          next if( !$name );

          $h = $defs{$name};

          next if( !$h && !$force_device );
        }

        $force_show = 0;
        my $modifier = "";
        if( $regex && $regex =~ m/^([+?!]*)(.*)/ ) {
          $modifier = $1;
          $regex = $2;
        }

        if( $modifier =~ m/\+/ ) {
        } elsif( $modifier =~ m/\?/ ) {
          $h = $attr{$name};
        } else {
          $h = $h->{READINGS} if( $h );
        }

        $force_show = 1 if( $modifier =~ m/\!/ );
      }

      my @keys = keys %{$h};
      push (@keys, $regex) if( $force_show && (!@keys || !defined($h->{$regex}) ) );
      foreach my $n (sort @keys) {
      #foreach my $n (sort keys %{$h}) {
        next if( $n =~ m/^\./);
        next if( $n eq "state" && !$show_state && (!defined($regex) || $regex ne "state") );
        if( defined($regex) ) {
          eval { $n =~ m/^$regex$/ };
          if( $@ ) {
            Log3 $name, 3, $name .": ". $regex .": ". $@;
            last;
          }
          next if( $n !~ m/^$regex$/);
        }
        my $val = $h->{$n};

        my ($v, $t);
        if(ref($val)) {
          next if( ref($val) ne "HASH" || !defined($val->{VAL}) );
          ($v, $t) = ($val->{VAL}, $val->{TIME});
          $v = FW_htmlEscape($v);
          $t = "" if(!$t);
          $t = "" if( $multi != 1 );
        } else {
          $val = $n if( !$val && $force_show );
          $v = FW_htmlEscape($val);
        }

        my $informid = "informId=\"$d-$name.$n\"";
        my $row_style = lookup2($hash->{helper}{rowStyle},$name,$n,$v,$cell_row,undef);
        my $cell_style0 = lookup2($hash->{helper}{cellStyle},$name,$n,$v,$cell_row,0);
        my $cell_style = lookup2($hash->{helper}{cellStyle},$name,$n,$v,$cell_row,$cell_column);
        my $name_style = lookup2($hash->{helper}{nameStyle},$name,$n,$v,$cell_row,$cell_column);
        my $value_style = lookup2($hash->{helper}{valueStyle},$name,$n,$v,$cell_row,$cell_column);

        if( !$FW_webArgs{"detail"} ) {
          if( $visibility && $visibility eq "collapsed" ) {
            $row_style = 'style=""' if( !$row_style );
            $row_style =~ s/style=(.)/style=$1display:none;/;
          }
        }

        my $value_format = lookup2($hash->{helper}{valueFormat},$name,$n,$v);
        next if( !defined($value_format) );
        if(  $value_format =~ m/%/ ) {
          $v = sprintf( $value_format, $v );
        } elsif( $value_format ne "" ) {
          $v = $value_format;
        }

        my $value_column = lookup2($hash->{helper}{valueColumn},$name,$n,undef);
        my $value_columns = lookup2($hash->{helper}{valueColumns},$name,$n,$v);

        my $a = AttrVal($name2, "alias", $name2);
        my $m = "$a$separator$n";
        $m = $a if( $multi != 1 );
        my $room = AttrVal($name2, "room", "");
        my $group = AttrVal($name2, "group", "");
        my $txt = lookup($hash->{helper}{mapping},$name2,$a,($multi!=1?"":$n),$v,$room,$group,$cell_row,$m);

        if( my $name_icon = $hash->{helper}{nameIcon}  ) {
          if( my $icon = lookup($name_icon ,$name,$a,$n,$v,$room,$group,$cell_row,"") ) {
            $txt = FW_makeImage( $icon, $txt, "icon" );
          }
        }

        my $cmd;
        my $devStateIcon;
        if( my $value_icon = $hash->{helper}{valueIcon} ) {
          if( my $icon = lookup($value_icon,$name,$a,$n,$v,$room,$group,$cell_row,"") ) {
            if( $icon =~ m/^[\%\$]devStateIcon$/ ) {
              my %extPage = ();
              my ($allSets, $cmdlist, $txt) = FW_devState($name, $room, \%extPage);
              $devStateIcon = $txt;
            } else {
              $devStateIcon = FW_makeImage( $icon, $v, "icon" );
              $cmd = lookup2($hash->{helper}{commands},$name,$n,$icon);
              $cmd = lookup2($hash->{helper}{commands},$name,$n,$v) if( !$cmd );
            }
          }
        }

        my $webCmdFn = 0;
        if( !$devStateIcon ) {
          $cmd = lookup2($hash->{helper}{commands},$name,$n,$v) if( !$devStateIcon );

          if( $cmd && $cmd =~ m/^([\w\/.-]*):(\S*)?(\s\S*)?$/ ) {
            my $set = $1;
            my $values = $2;
            $set .= $3 if( $3 );

            if( !$values ) {
              my %extPage = ();
              my ($allSets, undef, undef) = FW_devState($name, $room, \%extPage);
              my ($set) = split( ' ', $set, 2 );
              if( $allSets && $allSets =~ m/\b$set:([^ ]*)/) {
                $values = $1;
              }
            }

            my $room = $FW_webArgs{room};
            $room = "&detail=$FW_webArgs{detail}" if( $FW_webArgs{"detail"} );

            my $htmlTxt;
            foreach my $fn (sort keys %{$data{webCmdFn}}) {
              no strict "refs";
              $htmlTxt = &{$data{webCmdFn}{$fn}}($FW_wname,$name,$room,$set,$values);
              use strict "refs";
              last if(defined($htmlTxt));
            }

           if( $htmlTxt && $htmlTxt =~ m/^<td>(.*)<\/td>$/ ) {
              $htmlTxt = $1;
             }
           if( $htmlTxt && $htmlTxt =~ m/class='fhemWidget'/ ) {
             $htmlTxt =~ s/class='fhemWidget'/class='fhemWidget' informId='$d-$name.$n'/;
             $informid = "";
           }

           if( $htmlTxt ) {
              $v = $htmlTxt;
              $webCmdFn = 1;
            }
          }
        }
        ($v,$devStateIcon) = readingsGroup_makeLink($v,$devStateIcon,$cmd) if( !$webCmdFn );

        if( $hash->{helper}{valuePrefix} ) {
          if( my $value_prefix = lookup2($hash->{helper}{valuePrefix},$name,$n,$v) ) {
            $v = $value_prefix . $v;
            $devStateIcon = $value_prefix . $devStateIcon if( $devStateIcon );
          }
        }

        if( $hash->{helper}{valueSuffix} ) {
          if( my $value_suffix = lookup2($hash->{helper}{valueSuffix},$name,$n,$v) ) {
            $v .= $value_suffix;
            $devStateIcon .= $value_suffix if( $devStateIcon );
          }
        }

        if( $first || $multi == 1 ) {
          $ret .= sprintf("<tr $row_style class=\"%s\">", ($row&1)?"odd":"even");
          $row++;
        }

        $txt = "<div $cell_style0>$txt</div>" if( !$show_links );
        $txt = "<a $cell_style0 href=\"$FW_ME$FW_subdir?detail=$name\">$txt</a>" if( $show_links );
        $v = "<div $value_style>$v</div>" if( $value_style && !$devStateIcon );

        $ret .= "<td $value_columns><div $name_style class=\"dname\">$txt</div></td>" if( $show_names && ($first || $multi == 1) );

        if( $value_column && $multi ) {
          while ($cell_column < $value_column ) {
            $ret .= "<td></td>";
            ++$cell_column;
          }
        }

        $ret .= "<td $value_columns $informid>$devStateIcon</td>" if( $devStateIcon );
        $ret .= "<td $value_columns><div $cell_style $informid>$v</div></td>" if( !$devStateIcon );
        $ret .= "<td><div $timestamp_style informId=\"$d-$name.$n-ts\">$t</div></td>" if( $show_time && $t );

        $first = 0;
        ++$cell_column;
      }
    }
  }
  if( $disable > 0 ) {
    $ret .= sprintf("<tr class=\"%s\">", ($row&1)?"odd":"even");
    $ret .= "<td colspan=\"99\"><div style=\"color:#ff8888;text-align:center\">updates disabled</div></td></tr>";
  }
  $ret .= "</table></td></tr>";
  $ret .= "</table>";

  #$hash->{fhem}->{cached} = $ret;

  return $ret;
}
sub
readingsGroup_detailFn()
{
  my ($FW_wname, $d, $room, $extPage) = @_; # extPage is set for summaryFn.
  my $hash = $defs{$d};

  return undef if( ${hash}->{inDetailFn} );

  $hash->{mayBeVisible} = 1;

  ${hash}->{inDetailFn} = 1;
  my $html = readingsGroup_2html($d,$extPage);
  delete ${hash}->{inDetailFn};

  return $html;
}

sub
readingsGroup_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};

  my $events = deviceEvents($dev,1);
  return if( !$events );

  if( grep(m/^INITIALIZED$/, @{$events}) ) {
    readingsGroup_updateDevices($hash);
    return undef;
  }
  elsif( grep(m/^REREADCFG$/, @{$events}) ) {
    readingsGroup_updateDevices($hash);
    return undef;
  }

  return if( AttrVal($name,"disable", 0) > 0 );

  return if($dev->{TYPE} eq $hash->{TYPE});
  #return if($dev->{NAME} eq $name);

  my $devices = $hash->{DEVICES};
  $devices = $hash->{DEVICES2} if( $hash->{DEVICES2} );

  my $max = int(@{$events});
  for (my $i = 0; $i < $max; $i++) {
    my $s = $events->[$i];
    $s = "" if(!defined($s));

    if( $dev->{NAME} eq "global" && $s =~ m/^RENAMED ([^ ]*) ([^ ]*)$/) {
      my ($old, $new) = ($1, $2);
      if( defined($hash->{CONTENT}{$old}) ) {

        $hash->{DEF} =~ s/(\s*)$old((:\S+)?\s*)/$1$new$2/g;
      }
      readingsGroup_updateDevices($hash);
    } elsif( $dev->{NAME} eq "global" && $s =~ m/^DELETED ([^ ]*)$/) {
      my ($name) = ($1);

      if( defined($hash->{CONTENT}{$name}) ) {

        $hash->{DEF} =~ s/(\s*)$name((:\S+)?\s*)/ /g;
        $hash->{DEF} =~ s/^ //;
        $hash->{DEF} =~ s/ $//;
      }
      readingsGroup_updateDevices($hash);
    } elsif( $dev->{NAME} eq "global" && $s =~ m/^DEFINED ([^ ]*)$/) {
      readingsGroup_updateDevices($hash);
    } else {
      next if(AttrVal($name,"disable", undef));

      next if (!$hash->{CONTENT}->{$dev->{NAME}} && !$hash->{CONTENT2}->{$dev->{NAME}});

      if( $hash->{alwaysTrigger} ) {
      } elsif( !defined($hash->{mayBeVisible}) ) {
        Log3 $name, 5, "$name: not on any display, ignoring notify";
        return undef;
      } else {
        if( defined($FW_visibleDeviceHash{$name}) ) {
        } else {
          Log3 $name, 5, "$name: no longer visible, ignoring notify";
          delete( $hash->{mayBeVisible} );
          return undef;
        }
      }

      my ($reading,$value) = split(": ",$events->[$i],2);
      next if( !defined($value) );
      next if( $reading =~ m/^\./);
      $reading = "" if( !defined($reading) );
      $value = "" if( !defined($value) );
      my $show_state = !AttrVal( $name, "nostate", "0" );

      foreach my $device (@{$devices}) {
        my $item = 0;
        my $h = $defs{@{$device}[0]};
        next if( !$h );
        next if( $dev->{NAME} ne $h->{NAME} );
        my $n = $h->{NAME};
        my $regex = @{$device}[1];
        my @list = (undef);
        @list = split(",",$regex) if( $regex );
        #foreach my $regex (@list) {
        for( my $i = 0; $i <= $#list; ++$i ) {
        my $regex = $list[$i];
          while ($regex
                 && ( ($regex =~ m/^</ && $regex !~ m/>$/)          #handle , in <...>
                      || ($regex =~ m/@\{/ && $regex !~ m/}$/) )    #handle , in reading@{...}
                 && defined($list[++$i]) ) {
            $regex .= ",". $list[$i];
          }
          next if( $reading eq "state" && !$show_state && (!defined($regex) || $regex ne "state") );
          my $modifier = "";
          if( $regex && $regex =~ m/^([+?!]*)(.*)/ ) {
            $modifier = $1;
            $regex = $2;
          }
          next if( $modifier =~ m/\+/ );
          next if( $modifier =~ m/\?/ );

          if( $regex && $regex =~ m/^<(.*)>$/ ) {
            my $txt = $1;
            my $readings;
            $item++;
            if( $txt =~ m/^{(.*)}(@([\w\-|.*]+))?$/ ) {
              $txt = "{$1}";
              $readings = $3;

              next if( !$readings );
              next if( $reading !~ m/^$readings$/);

              my $new_line;
              my $DEVICE = $n;
              ($txt,$new_line) = eval $txt;
              if( $@ ) {
                $txt = "<ERROR>";
                Log3 $name, 3, $name .": ". $regex .": ". $@;
              }
              $txt = "" if( !defined($txt) );

              if( $txt && $txt =~ m/^%([^%]*)(%(.*))?/ ) {
                my $icon = $1;
                my $cmd = $3;

                $cmd = lookup2($hash->{helper}{commands},$name,$n,$icon) if( !defined($cmd) );
                $txt = FW_makeImage( $icon, $icon, "icon" );
                ($txt,undef) = readingsGroup_makeLink($txt,undef,$cmd);
              }

              DoTrigger( $name, "$n.i$item.item: $txt" );
            }

            next;
          }

          next if( defined($regex) && $reading !~ m/^$regex$/);

          my $value_style = lookup2($hash->{helper}{valueStyle},$n,$reading,$value);

          my $value = $value;
          if( my $value_format = $hash->{helper}{valueFormat} ) {
            my $value_format = lookup2($hash->{helper}{valueFormat},$n,$reading,$value);

            if( !defined($value_format) ) {
              $value = "";
            } elsif( $value_format =~ m/%/ ) {
              $value = sprintf( $value_format, $value );
            } elsif( $value_format ne "" ) {
              $value = $value_format;
            }
          }

          my $cmd;
          my $devStateIcon;
          if( my $value_icon = $hash->{helper}{valueIcon} ) {
            my $a = AttrVal($n, "alias", $n);
            my $room = AttrVal($n, "room", "");
            my $group = AttrVal($n, "group", "");
            if( my $icon = lookup($value_icon,$n,$a,$reading,$value,$room,$group,1,"") ) {
              if( $icon eq "%devStateIcon" ) {
                my %extPage = ();
                my ($allSets, $cmdlist, $txt) = FW_devState($n, $room, \%extPage);
                $devStateIcon = $txt;
              } else {
                $devStateIcon = FW_makeImage( $icon, $value, "icon" );
                $cmd = lookup2($hash->{helper}{commands},$n,$reading,$icon);
                $cmd = lookup2($hash->{helper}{commands},$n,$reading,$value) if( !$cmd );
              }
            }

            if( $devStateIcon ) {
              (undef,$devStateIcon) = readingsGroup_makeLink(undef,$devStateIcon,$cmd);

              if( $hash->{helper}{valuePrefix} ) {
                if( my $value_prefix = lookup2($hash->{helper}{valuePrefix},$n,$reading,$value) ) {
                  $devStateIcon = $value_prefix . $devStateIcon if( $devStateIcon );
                }
              }

              if( $hash->{helper}{valueSuffix} ) {
                if( my $value_suffix = lookup2($hash->{helper}{valueSuffix},$n,$reading,$value) ) {
                  $devStateIcon .= $value_suffix if( $devStateIcon );
                }
              }

              DoTrigger( $name, "$n.$reading: $devStateIcon" );
              next;
            }
          }

          $cmd = lookup2($hash->{helper}{commands},$n,$reading,$value);
          if( $cmd && $cmd =~ m/^(\w.*):(\S.*)?$/ ) {
            if( $reading eq "state" ) {
              DoTrigger( $name, "$n: $value" );
            } else {
              DoTrigger( $name, "$n.$reading: $value" );
            }
            next;
          }

          ($value,undef) = readingsGroup_makeLink($value,undef,$cmd);

          if( $hash->{helper}{valuePrefix} ) {
            if( my $value_prefix = lookup2($hash->{helper}{valuePrefix},$n,$reading,$value) ) {
              $value = $value_prefix . $value;
              $devStateIcon = $value_prefix . $devStateIcon if( $devStateIcon );
            }
          }

          if( $hash->{helper}{valueSuffix} ) {
            if( my $value_suffix = lookup2($hash->{helper}{valueSuffix},$n,$reading,$value) ) {
              $value .= $value_suffix;
              $devStateIcon .= $value_suffix if( $devStateIcon );
            }
          }

          $value = "<div $value_style>$value</div>" if( $value_style );

          DoTrigger( $name, "$n.$reading: $value" );
        }
      }
    }
  }

  return undef;
}

sub
readingsGroup_Set($@)
{
  my ($hash, $name, $cmd, $param, @a) = @_;

  my $list = "visibility:toggle,toggle2,show,hide";

  if( $cmd eq "refresh" ) {
    readingsGroup_updateDevices($hash);
    return undef;
  } elsif( $cmd eq "visibility" ) {
    readingsGroup_updateDevices($hash);
    DoTrigger( $hash->{NAME}, "visibility: $param" );
    return undef;
  }


  return "Unknown argument $cmd, choose one of $list";
}

sub
readingsGroup_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];
  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];

  my $ret = "";
  if( $cmd eq "html" ) {
    return readingsGroup_2html($hash);
  }

  return undef;
  return "Unknown argument $cmd, choose one of html:noArg";
}

sub
readingsGroup_Attr($$$;$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $orig = $attrVal;

  if( $attrName eq "alwaysTrigger" ) {
    my $hash = $defs{$name};
    $attrVal = 1 if($attrVal);

    if( $cmd eq "set" ) {
      $hash->{alwaysTrigger} = $attrVal;
    } else {
      delete $hash->{alwaysTrigger};
    }

  } elsif( grep { $_ =~ m/$attrName(:.*)?/ }  @mapping_attrs ) {
    my $hash = $defs{$name};

    if( $cmd eq "set" ) {
      my $attrVal = $attrVal;
      if( $attrVal =~ m/^{.*}$/ && $attrVal =~ m/=>/ && $attrVal !~ m/\$/ ) {
        my $av = eval $attrVal;
        if( $@ ) {
          Log3 $hash->{NAME}, 3, $hash->{NAME} .": ". $@;
        } else {
          $attrVal = $av if( ref($av) eq "HASH" );
        }
      }
      $hash->{helper}{$attrName} = $attrVal;
    } else {
      delete $hash->{helper}{$attrName};
    }

  } elsif( $attrName eq "sortDevices" ) {
    if( $cmd eq "set" ) {
      $attrVal = 1 if($attrVal);
      $attr{$name}{$attrName} = $attrVal;
    } else {
      delete $attr{$name}{$attrName};
    }

    my $hash = $defs{$name};
    readingsGroup_updateDevices($hash);
  }

  if( $cmd eq "set" ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}

1;

=pod
=begin html

<a name="readingsGroup"></a>
<h3>readingsGroup</h3>
<ul>
  Displays a collection of readings from on or more devices.

  <br><br>
  <a name="readingsGroup_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; readingsGroup &lt;device&gt;[:regex] [&lt;device-2&gt;[:regex-2]] ... [&lt;device-n&gt;[:regex-n]]</code><br>
    <br>

    Notes:
    <ul>
      <li>&lt;device&gt; can be of the form INTERNAL=VALUE where INTERNAL is the name of an internal value and VALUE is a regex.</li>
      <li>&lt;device&gt; can be of the form ATTRIBUTE&VALUE where ATTRIBUTE is the name of an attribute and VALUE is a regex.</li>
      <li>&lt;device&gt; can be of the form &lt;STRING&gt; or &lt;{perl}&gt; where STRING or the string returned by perl is
          inserted as a line in the readings list. skipped if STRING is undef.</li>
      <li>&lt;device&gt; can be a devspec (see <a href="#devspec">devspec</a>) with at least one FILTER expression.</li>
      <li>If regex is a comma separatet list the reading values will be shown on a single line.</li>
      <li>If regex starts with a '+' it will be matched against the internal values of the device instead of the readings.</li>
      <li>If regex starts with a '?' it will be matched against the attributes of the device instead of the readings.</li>
      <li>If regex starts with a '!' the display of the value will be forced even if no reading with this name is available.</li>
      <li>regex can be of the form &lt;regex&gt;@device to use readings from a different device.<br>
          if the device name part starts with a '!' the display will be foreced.
          use in conjunction with ! in front of the reading name.</li>
      <li>regex can be of the form &lt;regex&gt;@{perl} to use readings from a different device.</li>
      <li>regex can be of the form &lt;STRING&gt; or &lt;{perl}[@readings]&gt; where STRING or the string returned by perl is
          inserted as a reading or:
          <ul><li>the item will be skipped if STRING is undef</li>
              <li>if STRING is br a new line will be started</li>
              <li>if STRING is of the form %ICON[%CMD] ICON will be used as the name of an icon instead of a text and CMD
                  as the command to be executed if the icon is clicked. also see the commands attribute.</li></ul>
          if readings is given the perl expression will be reevaluated during longpoll updates.</li>
      <li>For internal values and attributes longpoll update is not possible. Refresh the page to update the values.</li>
      <li>the &lt;{perl}&gt; expression is limited to expressions without a space. it is best just to call a small sub
          in 99_myUtils.pm instead of having a compex expression in the define.</li>
    </ul><br>

    Examples:
    <ul>
      <code>
        define batteries readingsGroup .*:battery</code><br>
      <br>
        <code>define temperatures readingsGroup s300th.*:temperature</code><br>
        <code>define temperatures readingsGroup TYPE=CUL_WS:temperature</code><br>
      <br>
        <code>define culRSSI readingsGroup cul_RSSI=.*:+cul_RSSI</code><br>
      <br>
        <code>define heizung readingsGroup t1:temperature t2:temperature t3:temperature<br>
        attr heizung notime 1<br>
        attr heizung mapping {'t1.temperature' => 'Vorlauf', 't2.temperature' => 'R&amp;uuml;cklauf', 't3.temperature' => 'Zirkulation'}<br>
        attr heizung style style="font-size:20px"<br>
      <br>
        define systemStatus readingsGroup sysstat<br>
        attr systemStatus notime 1<br>
        attr systemStatus nostate 1<br>
        attr systemStatus mapping {'load' => 'Systemauslastung', 'temperature' => 'Systemtemperatur in &amp;deg;C'}<br>
      <br>
        define Verbrauch readingsGroup TYPE=PCA301:state,power,consumption<br>
        attr Verbrauch mapping %ALIAS<br>
        attr Verbrauch nameStyle style="font-weight:bold"<br>
        attr Verbrauch style style="font-size:20px"<br>
        attr Verbrauch valueFormat {power => "%.1f W", consumption => "%.2f kWh"}<br>
        attr Verbrauch valueIcon { state => '%devStateIcon' }<br>
        attr Verbrauch valueStyle {($READING eq "power" && $VALUE > 150)?'style="color:red"':'style="color:green"'}<br>
      <br>
        define rg_battery readingsGroup TYPE=LaCrosse:[Bb]attery<br>
        attr rg_battery alias Batteriestatus<br>
        attr rg_battery commands { "battery.low" => "set %DEVICE replaceBatteryForSec 60" }<br>
        attr rg_battery valueIcon {'battery.ok' => 'batterie', 'battery.low' => 'batterie@red'}<br>
      <br>
        define rgMediaPlayer readingsGroup myMediaPlayer:currentTitle,<>,totaltime,<br>,currentAlbum,<>,currentArtist,<br>,volume,<{if(ReadingsVal($DEVICE,"playStatus","")eq"paused"){"%rc_PLAY%set+$DEVICE+play"}else{"%rc_PAUSE%set+$DEVICE+pause"}}@playStatus>,playStatus<br>
        attr rgMediaPlayer commands { "playStatus.paused" => "set %DEVICE play", "playStatus.playing" => "set %DEVICE pause" }<br>
        attr rgMediaPlayer mapping &nbsp;<br>
        attr rgMediaPlayer notime 1<br>
        attr rgMediaPlayer valueFormat { "volume" => "Volume: %i" }<br>
        #attr rgMediaPlayer valueIcon { "playStatus.paused" => "rc_PLAY", "playStatus.playing" => "rc_PAUSE" }<br>
      </code><br>
    </ul>
  </ul><br>

  <a name="readingsGroup_Set"></a>
    <b>Set</b>
    <ul>
      <li>hide<br>
      will hide all visible instances of this readingsGroup</li>
      <li>show<br>
      will show all visible instances of this readingsGroup</li>
      <li>toggle<br>
      will toggle the hidden/shown state of all visible instances of this readingsGroup</li>
      <li>toggle2<br>
      will toggle the expanded/collapsed state of all visible instances of this readingsGroup</li>
    </ul><br>

  <a name="readingsGroup_Get"></a>
    <b>Get</b>
    <ul>
    </ul><br>

  <a name="readingsGroup_Attr"></a>
    <b>Attributes</b>
    <ul>
      <li>alwaysTrigger<br>
        1 -> alwaysTrigger update events. even if not visible.</li><br>
      <li>disable<br>
        1 -> disable notify processing and longpoll updates. Notice: this also disables rename and delete handling.<br>
        2 -> also disable html table creation<br>
        3 -> also disable html creation completely</li><br>
      <li>sortDevices<br>
        1 -> sort the device lines alphabetically. use the first of sortby or alias or name that is defined for each device.</li>
      <li>noheading<br>
        If set to 1 the readings table will have no heading.</li><br>
      <li>nolinks<br>
        Disables the html links from the heading and the reading names.</li><br>
      <li>nostate<br>
        If set to 1 the state reading is excluded.</li><br>
      <li>nonames<br>
        If set to 1 the reading name / row title is not displayed.</li><br>
      <li>notime<br>
        If set to 1 the reading timestamp is not displayed.</li><br>
      <li>mapping<br>
        Can be a simple string or a perl expression enclosed in {} that returns a hash that maps reading names
        to the displayed name.  The keys can be either the name of the reading or &lt;device&gt;.&lt;reading&gt;.
        %DEVICE, %ALIAS, %ROOM, %GROUP, %ROW and %READING are replaced by the device name, device alias, room attribute,
        group attribute and reading name respectively. You can also prefix these keywords with $ instead of %. Examples:<br>
          <code>attr temperatures mapping $DEVICE-$READING</code><br>
          <code>attr temperatures mapping {temperature => "%DEVICE Temperatur"}</code>
        </li><br>
      <li>separator<br>
        The separator to use between the device alias and the reading name if no mapping is given. Defaults to ':'
        a space can be enteread as <code>&amp;nbsp;</code></li><br>
      <li>style<br>
        Specify an HTML style for the readings table, e.g.:<br>
          <code>attr temperatures style style="font-size:20px"</code></li><br>
      <li>cellStyle<br>
        Specify an HTML style for a cell of the readings table. regular rows and colums are counted starting with 1,
        the row headings are column number 0. perl code has access to $ROW and $COLUMN. keys for hash lookup can be
        r:#, c:# or r:#,c:# , e.g.:<br>
          <code>attr temperatures cellStyle { "c:0" => 'style="text-align:right"' }</code></li><br>
      <li>nameStyle<br>
        Specify an HTML style for the reading names, e.g.:<br>
          <code>attr temperatures nameStyle style="font-weight:bold"</code></li><br>
      <li>valueStyle<br>
        Specify an HTML style for the reading values, e.g.:<br>
          <code>attr temperatures valueStyle style="text-align:right"</code></li><br>
      <li>valueColumn<br>
        Specify the minimum column in which a reading should appear. <br>
          <code>attr temperatures valueColumn { temperature => 2 }</code></li><br>
      <li>valueColumns<br>
        Specify an HTML colspan for the reading values, e.g.:<br>
          <code>attr wzReceiverRG valueColumns { eventdescription => 'colspan="4"' }</code></li><br>
      <li>valueFormat<br>
        Specify an sprintf style format string used to display the reading values. If the format string is undef
        this reading will be skipped. Can be given as a string, a perl expression returning a hash or a perl
        expression returning a string, e.g.:<br>
          <code>attr temperatures valueFormat %.1f &deg;C</code><br>
          <code>attr temperatures valueFormat { temperature => "%.1f &deg;C", humidity => "%i %" }</code><br>
          <code>attr temperatures valueFormat { ($READING eq 'temperature')?"%.1f &deg;C":undef }</code></li><br>
      <li>valuePrefix<br>
        text to be prepended to the reading value</li><br>
      <li>valueSuffix<br>
        text to be appended after the reading value<br>
          <code>attr temperatures valueFormat { temperature => "%.1f", humidity => "%i" }</code><br>
          <code>attr temperatures valueSuffix { temperature => "&deg;C", humidity => " %" }</code></li><br>
      <li>nameIcon<br>
        Specify the icon to be used instead of the reading name. Can be a simple string or a perl expression enclosed
        in {} that returns a hash that maps reading names to the icon name. e.g.:<br>
          <code>attr devices nameIcon $DEVICE</code></li><br>
      <li>valueIcon<br>
        Specify an icon to be used instead of the reading value. Can be a simple string or a perl expression enclosed
        in {} that returns a hash that maps reading value to the icon name. e.g.:<br>
          <code>attr devices valueIcon $VALUE</code><br>
          <code>attr devices valueIcon {state => '%VALUE'}</code><br>
          <code>attr devices valueIcon {state => '%devStateIcon'}</code>
          <code>attr rgMediaPlayer valueIcon { "playStatus.paused" => "rc_PLAY", "playStatus.playing" => "rc_PAUSE" }</code></li><br>
      <li>commands<br>
        Can be used in to different ways:
        <ul>
        <li>To make a reading or icon clickable by directly specifying the command that should be executed. eg.:<br>
        <code>attr rgMediaPlayer commands { "playStatus.paused" => "set %DEVICE play", "playStatus.playing" => "set %DEVICE pause" }</code></li>
        <li>Or if the mapped command is of the form &lt;command&gt;:[&lt;modifier&gt;] then the normal <a href="#FHEMWEB">FHEMWEB</a>
        webCmd widget for &lt;modifier&gt; will be used for this command. if &lt;modifier&gt; is omitted then the FHEMWEB lookup mechanism for &lt;command&gt; will be used. eg:<br>
        <code>attr rgMediaPlayer commands { volume => "volume:slider,0,1,100" }</code><br>
        <code>attr lights commands { pct => "pct:", dim => "dim:" }</code></li><br>
        </ul></li>
      <li>visibility<br>
        if set to hidden or hideable will display a small button to the left of the readingsGroup name to expand/hide the contents of the readingsGroup. if a readingsGroup is expanded then all others in the same group will be hidden.<br>
        <ul>
        hidden -> default state is hidden but can be expanded<br>
        hideable -> default state is visible but can be hidden<br><br>
        </ul>
        if set to collapsed or collapsible will recognise the specials &lt;-&gt;,&lt;+&gt; and &lt;+-&gt; as the first elements of
        a line to add a + or - symbol to this line. clicking on the + or - symbol will toggle between expanded and collapsed state. if a readingsGroup is expanded then all others in the same group will be collapsed.
        <ul>
        - -> line will be visible in expanded state<br>
        + -> line will be visible in collapsed state<br>
        +- -> line will be visible in both states<br>
        <br>
        collapsed-> default state is collapsed but can be expanded<br>
        collapsible -> default state is visible but can be collapsed </li>
        </ul>
    </ul><br>

      The style, nameStyle and valueStyle attributes can also contain a perl expression enclosed in {} that returns the style
      string to use. For nameStyle and valueStyle The perl code can use $DEVICE,$READING and $VALUE, e.g.:<br>
    <ul>
          <code>attr batteries valueStyle {($VALUE ne "ok")?'style="color:red"':'style="color:green"'}</code><br>
          <code>attr temperatures valueStyle {($DEVICE =~ m/aussen/)?'style="color:green"':'style="color:red"'}</code>
    </ul>
      Note: Only valueStyle, valueFomat, valueIcon and <{...}@reading> are evaluated during longpoll updates
      and valueStyle has to return a non empty style for every possible value. All other perl expressions are
      evaluated only once during html creation and will not reflect value updates with longpoll.
      Refresh the page to update the dynamic style. For nameStyle the color attribut is not working at the moment,
      the font-... and background attributes do work.
</ul>

=end html
=cut
