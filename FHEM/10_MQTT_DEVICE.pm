##############################################
#
# fhem bridge to mqtt (see http://mqtt.org)
#
# Copyright (C) 2014 Norbert Truchsess
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
# $Id: 10_MQTT_DEVICE.pm 6935 2014-11-09 20:35:34Z ntruchsess $
#
##############################################

use strict;
use warnings;

my %gets = (
  "version"   => "",
);

sub MQTT_DEVICE_Initialize($) {

  my $hash = shift @_;

  # Consumer
  $hash->{DefFn}    = "MQTT::DEVICE::Define";
  $hash->{UndefFn}  = "MQTT::Client_Undefine";
  $hash->{SetFn}    = "MQTT::DEVICE::Set";
  $hash->{AttrFn}   = "MQTT::DEVICE::Attr";
  
  $hash->{AttrList} =
    "IODev ".
    "qos:".join(",",keys %MQTT::qos)." ".
    "retain:0,1 ".
    "publishSet ".
    "publishSet_.* ".
    "subscribeReading_.* ".
    "autoSubscribeReadings ".
    $main::readingFnAttributes;
    
    main::LoadModule("MQTT");
}

package MQTT::DEVICE;

use strict;
use warnings;
use GPUtils qw(:all);

use Net::MQTT::Constants;

BEGIN {
  MQTT->import(qw(:all));

  GP_Import(qw(
    CommandDeleteReading
    CommandAttr
    readingsSingleUpdate
    Log3
  ))
};

sub Define() {
  my ( $hash, $def ) = @_;
  $hash->{sets} = {};
  return MQTT::Client_Define($hash,$def);
};

sub Set($$$@) {
  my ($hash,$name,$command,@values) = @_;
  return "Need at least one parameters" unless defined $command;
  return "Unknown argument $command, choose one of " . join(" ", map {$hash->{sets}->{$_} eq "" ? $_ : "$_:".$hash->{sets}->{$_}} sort keys %{$hash->{sets}})
    if(!defined($hash->{sets}->{$command}));
  my $msgid;
  if (@values) {
    my $value = join " ",@values;
    $msgid = send_publish($hash->{IODev}, topic => $hash->{publishSets}->{$command}->{topic}, message => $value, qos => $hash->{qos}, retain => $hash->{retain});
    readingsSingleUpdate($hash,$command,$value,1);
  } else {
    $msgid = send_publish($hash->{IODev}, topic => $hash->{publishSets}->{""}->{topic}, message => $command, qos => $hash->{qos}, retain => $hash->{retain});
    readingsSingleUpdate($hash,"state",$command,1);
  }
  $hash->{message_ids}->{$msgid}++ if defined $msgid;
  readingsSingleUpdate($hash,"transmission-state","outgoing publish sent",1);
  return undef;
}

sub Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;

  my $hash = $main::defs{$name};
  ATTRIBUTE_HANDLER: {
    $attribute =~ /^subscribeReading_(.+)/ and do {
      if ($command eq "set") {
        unless (defined $hash->{subscribeReadings}->{$value} and $hash->{subscribeReadings}->{$value} eq $1) {
          unless (defined $hash->{subscribeReadings}->{$value}) {
            client_subscribe_topic($hash,$value);
          }
          $hash->{subscribeReadings}->{$value} = $1;
        }
      } else {
        foreach my $topic (keys %{$hash->{subscribeReadings}}) {
          if ($hash->{subscribeReadings}->{$topic} eq $1) {
            client_unsubscribe_topic($hash,$topic);
            delete $hash->{subscribeReadings}->{$topic};
            CommandDeleteReading(undef,"$hash->{NAME} $1");
            last;
          }
        }
      }
      last;
    };
    $attribute eq "autoSubscribeReadings" and do {
      if ($command eq "set") {
        unless (defined $hash->{'.autoSubscribeTopic'} and $hash->{'.autoSubscribeTopic'} eq $value) {
          if (defined $hash->{'.autoSubscribeTopic'}) {
            client_unsubscribe_topic($hash,$hash->{'.autoSubscribeTopic'});
          }
          $hash->{'.autoSubscribeTopic'} = $value;
          $hash->{'.autoSubscribeExpr'} = topic_to_regexp($value);
          client_subscribe_topic($hash,$value);
        }
      } else {
        if (defined $hash->{'.autoSubscribeTopic'}) {
          client_unsubscribe_topic($hash,$hash->{'.autoSubscribeTopic'});
          delete $hash->{'.autoSubscribeTopic'};
          delete $hash->{'.autoSubscribeExpr'};
        }
      }
      last;
    };
    $attribute =~ /^publishSet(_?)(.*)/ and do {
      if ($command eq "set") {
        my @values = split ("[ \t]+",$value);
        my $topic = pop @values;
        $hash->{publishSets}->{$2} = {
          'values' => \@values,
          topic    => $topic,
        };
        if ($2 eq "") {
          foreach my $set (@values) {
            $hash->{sets}->{$set}="";
          }
        } else {
          $hash->{sets}->{$2}=join(",",@values);
        }
      } else {
        if ($2 eq "") {
          foreach my $set (@{$hash->{publishSets}->{$2}->{'values'}}) {
            delete $hash->{sets}->{$set};
          }
        } else {
          CommandDeleteReading(undef,"$hash->{NAME} $2");
          delete $hash->{sets}->{$2};
        }
        delete $hash->{publishSets}->{$2};
      }
      last;
    };
    client_attr($hash,$command,$name,$attribute,$value);
  }
}

sub onmessage($$$) {
  my ($hash,$topic,$message) = @_;
  if (defined (my $reading = $hash->{subscribeReadings}->{$topic})) {
    Log3($hash->{NAME},5,"calling readingsSingleUpdate($hash->{NAME},$reading,$message,1");
    readingsSingleUpdate($hash,$reading,$message,1);
  } elsif ($topic =~ $hash->{'.autoSubscribeExpr'}) {
    Log3($hash->{NAME},5,"calling readingsSingleUpdate($hash->{NAME},$1,$message,1");
    CommandAttr(undef,"$hash->{NAME} subscribeReading_$1 $topic");
    readingsSingleUpdate($hash,$1,$message,1);
  }
}

1;

=pod
=begin html

<a name="MQTT_DEVICE"></a>
<h3>MQTT_DEVICE</h3>
<ul>
  <p>acts as a fhem-device that is mapped to <a href="http://mqtt.org/">mqtt</a>-topics.</p>
  <p>requires a <a href="#MQTT">MQTT</a>-device as IODev<br/>
     Note: this module is based on <a href="https://metacpan.org/pod/distribution/Net-MQTT/lib/Net/MQTT.pod">Net::MQTT</a> which needs to be installed from CPAN first.</p>
  <a name="MQTT_DEVICEdefine"></a>
  <p><b>Define</b></p>
  <ul>
    <p><code>define &lt;name&gt; MQTT_DEVICE</code><br/>
       Specifies the MQTT device.</p>
  </ul>
  <a name="MQTT_DEVICEset"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <p><code>set &lt;name&gt; &lt;command&gt;</code><br/>
         sets reading 'state' and publishes the command to topic configured via attr publishSet</p>
    </li>
    <li>
      <p><code>set &lt;name&gt; &lt;h;reading&gt; &lt;value&gt;</code><br/>
         sets reading &lt;h;reading&gt; and publishes the command to topic configured via attr publishSet_&lt;h;reading&gt;</p>
    </li>
  </ul>
  <a name="MQTT_DEVICEattr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <p><code>attr &lt;name&gt; publishSet [&lt;commands&gt;] &lt;topic&gt;</code><br/>
         configures set commands that may be used to both set reading 'state' and publish to configured topic</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; publishSet_&lt;reading&gt; [&lt;values&gt;] &lt;topic&gt;</code><br/>
         configures reading that may be used to both set 'reading' (to optionally configured values) and publish to configured topic</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; autoSubscribeReadings &lt;topic&gt;</code><br/>
         specify a mqtt-topic pattern with wildcard (e.c. 'myhouse/kitchen/+') and MQTT_DEVICE automagically creates readings based on the wildcard-match<br/>
         e.g a message received with topic 'myhouse/kitchen/temperature' would create and update a reading 'temperature'</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; subscribeReading_&lt;reading&gt; &lt;topic&gt;</code><br/>
         mapps a reading to a specific topic. The reading is updated whenever a message to the configured topic arrives</p>
    </li>
  </ul>
</ul>

=end html
=cut
