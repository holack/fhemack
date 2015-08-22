##############################################
##############################################
# $Id: 98_ModbusSDM220M.pm 
#
#	fhem Modul für Stromzähler SDM220M von B+G E-Tech & EASTON
#	verwendet Modbus.pm als Basismodul für die eigentliche Implementation des Protokolls.
#
#	This file is part of fhem.
# 
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
# 
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#	Changelog:
#	2015-02-27	initial release
#	2015-03-14	Anpassungan an neues 98_Modbus.pm, defaultpoll --> poll, defaultpolldelay --> polldelay,
#				attribute für timing umbenannt,
#				parseInfo --> SDM220MparseInfo, deviceInfo --> SDM220MdeviceInfo

package main;

use strict;
use warnings;
use Time::HiRes qw( time );

sub ModbusSDM220M_Initialize($);

# deviceInfo defines properties of the device.
# some values can be overwritten in parseInfo, some defaults can even be overwritten by the user with attributes if a corresponding attribute is added to AttrList in _Initialize.
#
my %SDM220MdeviceInfo = (
	"timing"	=>	{
			timeout		=>	2,		# 2 seconds timeout when waiting for a response
			commDelay	=>	0.7,	# 0.7 seconds minimal delay between two communications e.g. a read a the next write,
									# can be overwritten with attribute commDelay if added to AttrList in _Initialize below
			sendDelay	=>	0.7,	# 0.7 seconds minimal delay between two sends, can be overwritten with the attribute
									# sendDelay if added to AttrList in _Initialize function below
			}, 
	"i"			=>	{				# details for "input registers" if the device offers them
			read		=>	4,		# use function code 4 to read discrete inputs. They can not be read by definition.
			defLen		=>	2,		# default length (number of registers) per value ((e.g. 2 for a float of 4 bytes that spans 2 registers)
									# can be overwritten in parseInfo per reading by specifying the key "len"
			combine		=>	40,		# allow combined read of up to 10 adjacent registers during getUpdate
#			combine		=>	1,		# no combined read (read more than one registers with one read command) during getUpdate
			defFormat	=>	"%.1f",	# default format string to use after reading a value in sprintf
									# can be overwritten in parseInfo per reading by specifying the key "format"
			defUnpack	=>	"f>",	# default pack / unpack code to convert raw values, e.g. "n" for a 16 bit integer oder
									# "f>" for a big endian float IEEE 754 floating-point numbers
									# can be overwritten in parseInfo per reading by specifying the key "unpack"
			defPoll		=>	1,		# All defined Input Registers should be polled by default unless specified otherwise in parseInfo or by attributes
			defShowGet	=>	1,		# default für showget Key in parseInfo
			},
	"h"			=>	{				# details for "holding registers" if the device offers them
			read		=>	3,		# use function code 3 to read holding registers.
			write		=>	16,		# use function code 6 to write holding registers (alternative could be 16)
			defLen		=>	2,		# default length (number of registers) per value (e.g. 2 for a float of 4 bytes that spans 2 registers)
									# can be overwritten in parseInfo per reading by specifying the key "len"
			combine		=>	10,		# allow combined read of up to 10 adjacent registers during getUpdate
			defUnpack	=>	"f>",	# default pack / unpack code to convert raw values, e.g. "n" for a 16 bit integer oder
									# "f>" for a big endian float IEEE 754 floating-point numbers
									# can be overwritten in parseInfo per reading by specifying the key "unpack"
			defShowGet	=>	1,		# default für showget Key in parseInfo
			},
);

# %parseInfo:
# r/c/i+adress => objHashRef (h = holding register, c = coil, i = input register, d = discrete input)
# the address is a decimal number without leading 0
#
# Explanation of the parseInfo hash sub-keys:
# name			internal name of the value in the modbus documentation of the physical device
# reading		name of the reading to be used in Fhem
# set			can be set to 1 to allow writing this value with a Fhem set-command
# setmin		min value for input validation in a set command
# setmax		max value for input validation in a set command
# hint			string for fhemweb to create a selection or slider
# expr			perl expression to convert a string after it has bee read
# map			a map string to convert an value from the device to a more readable output string 
# 				or to convert a user input to the machine representation
#				e.g. "0:mittig, 1:oberhalb, 2:unterhalb"				
# setexpr		per expression to convert an input string to the machine format before writing
#				this is typically the reverse of the above expr
# format		a format string for sprintf to format a value read
# len			number of Registers this value spans
# poll			defines if this value is included in the read that the module does every defined interval
#				this can be changed by a user with an attribute
# unpack		defines the translation between data in the module and in the communication frame
#				see the documentation of the perl pack function for details.
#				example: "n" for an unsigned 16 bit value or "f>" for a float that is stored in two registers
# showget		can be set to 1 to allow a Fhem get command to read this value from the device
# polldelay		if a value should not be read in each iteration after interval has passed, 
#				this value can be set to a multiple of interval

my %SDM220MparseInfo = (
#	Spannung, nur bei jedem 5. Zyklus
	"i0"	=>	{	# input register 0x0000
					name		=> "Line to neutral volts",	# internal name of this register in the hardware doc
					reading		=> "Voltage__V",			# name of the reading for this value
					format		=> '%.1f V',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},

#	Strom
	"i6"	=>	{	# input register 0x0006
					name		=> "current",				# internal name of this register in the hardware doc
					reading		=> "Current__A",			# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
				},

#	Leistung in W
	"i12"	=>	{	# input register 0x000C, Phase 1: Leistung
					name		=> "Active power",			# internal name of this register in the hardware doc
					reading		=> "Power__W",				# name of the reading for this value
					format		=> '%.f W',					# format string for sprintf
				},

#	Scheinleistung in VA
	"i18"	=>	{	# input register 0x0012, Phase 1: Volt Ampere
					name		=> "Apparent power",		# internal name of this register in the hardware doc
					reading		=> "Power__VA",				# name of the reading for this value
					format		=> '%.1f VA',				# format string for sprintf
				},

#	Blindleistung in VAr
	"i24"	=>	{	# input register 0x0018
					name		=> "Reactive power",		# internal name of this register in the hardware doc
					reading		=> "Power__VAr",			# name of the reading for this value
					format		=> '%.1f VAr',				# format string for sprintf
				},

# Leistungsfaktor, nur jeden 10. Zyklus
	"i30"	=>	{	# input register 0x001E
					# The power factor has its sign adjusted to indicate the nature of the load.
					# Positive for capacitive and negative for inductive
					name		=> "Power factor",			# internal name of this register in the hardware doc
					reading		=> "PowerFactor",			# name of the reading for this value
					format		=> '%.1f',					# format string for sprintf
					polldelay	=> "x10",					# only poll this Value if last read is older than 10*Iteration, otherwiese getUpdate will skip it
				},

# Phasenverschiebung, nur jeden 3. Zyklus
	"i36"	=>	{	# input register 0x0024
					name		=> "Phase angle",			# internal name of this register in the hardware doc
					reading		=> "CosPhi",				# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x3",					# only poll this Value if last read is older than 3*Iteration, otherwiese getUpdate will skip it
				},

# Frequenz, nur bei jedem 10. Zyklus
	"i70"	=>	{	# input register 0x0046
					name		=> "Frequency",				# internal name of this register in the hardware doc
					reading		=> "Frequency__Hz",			# name of the reading for this value
					format		=> '%.1f Hz',				# format string for sprintf
					polldelay	=> "x10",					# only poll this Value if last read is older than 10*Iteration, otherwiese getUpdate will skip it
				},

# Arbeit, Zyklus: jede Minute
	"i72"	=>	{	# input register 0x0048
					name		=> "Import active energy",	# internal name of this register in the hardware doc
					reading		=> "Energy_import__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i74"	=>	{	# input register 0x004A
					name		=> "Export active energy",	# internal name of this register in the hardware doc
					reading		=> "Energy_export__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i76"	=>	{	# input register 0x004C
					name		=> "Import reactive energy",# internal name of this register in the hardware doc
					reading		=> "Energy_import__kVArh",	# name of the reading for this value
					format		=> '%.3f kVArh',			# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i78"	=>	{	# input register 0x004E
					name		=> "Export reactive energy",# internal name of this register in the hardware doc
					reading		=> "Energy_export__kVArh",	# name of the reading for this value
					format		=> '%.3f kVArh',			# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},

# kWh Gesamtwerte, Zyklus: jede Minute
	"i342"	=>	{	# input register 0x0156
					name		=> "Total active energy",	# internal name of this register in the hardware doc
					reading		=> "Energy_total__kWh",		# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i344"	=>	{	# input register 0x0158
					name		=> "Total reactive energy",	# internal name of this register in the hardware doc
					reading		=> "Energy_total__kVArh",	# name of the reading for this value
					format		=> '%.3f kVArh',			# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},


###############################################################################################################
# Holding Register
###############################################################################################################
	"h12"	=>	{	# holding register 0x000C
					# Write relay on period in milliseconds: 60, 100 or 200, default 100
					name		=> "Relay Pulse Width",		# internal name of this register in the hardware doc
					reading		=> "System_Pulse_Width__ms",# name of the reading for this value
					format		=> '%.f ms',				# format string for sprintf
					hint		=> "60,100,200",			# string for fhemweb to create a selection or slider
					poll		=> "once",					# only poll once after define (or after a set)
					set			=> 1,						# this value can be set
				},

	"h18"	=>	{	# holding register 0x0012
					# Write the network port parity/stop bits for MODBUS Protocol, where:
					# 0 = One stop bit and no parity, default.
					# 1 = One stop bit and even parity.
					# 2 = One stop bit and odd parity.
					# 3 = Two stop bits and no parity.
					# Requires a restart to become effective.
					name		=> "Network Parity Stop",	# internal name of this register in the hardware doc
					reading		=> "Modbus_Parity_Stop",	# name of the reading for this value
					map			=> "0:1stop.bit_no.parity, 1:1stop.bit_even.parity, 2:1stop.bit_odd.parity, 3:2stop.bits_no.parity",	# map to convert visible values to internal numbers (for reading and writing)
					hint		=> "0,1,2,3",				# string for fhemweb to create a selection or slider
					poll		=> "once",					# only poll once after define (or after a set)
					set			=> 1,						# this value can be set
				},

	"h20"	=>	{	# holding register 0x0014
					# Write the network port node address: 1 to 247 for MODBUS Protocol, default 1.
					# Requires a restart to become effective.
					name		=> "Network Node",			# internal name of this register in the hardware doc
					reading		=> "Modbus_Node_adr",		# name of the reading for this value
					min			=> 1,						# input validation for set: min value
					max			=> 247,						# input validation for set: max value
					poll		=> "once",					# only poll once after define (or after a set)
					set			=> 1,						# this value can be set
				},

	"h28"	=>	{	# holding register 0x001C
					# Write the network port baud rate for MODBUS Protocol, where:
					# 0=2400; 1=4800; 2=9600; 5=1200
					# Requires no restart, wird sofort active!
					name		=> "Network Baud Rate",		# internal name of this register in the hardware doc
					reading		=> "Modbus_Speed__baud",	# name of the reading for this value
					map			=> "0:2400, 1:4800, 2:9600, 5:1200",	# map to convert visible values to internal numbers (for reading and writing)
					hint		=> "0,1,2,5",				# string for fhemweb to create a selection or slider
					poll		=> "once",					# only poll once after define (or after a set)
					set			=> 1,						# this value can be set
				},

	"h86"	=>	{	# holding register 0x0056
					# 0001: Import active energy
					# 0002: Import + export active energy
					# 0004: Export active energy, (default)
					# 0005: Import reactive energy
					# 0006: Import + export reactive energy
					# 0008: Export reactive energy
					name		=> "Pulse1 output",			# internal name of this register in the hardware doc
					reading		=> "Relay1_Energy_Type",	# name of the reading for this value
					unpack		=>	"f>",					# ??? pack / unpack code to convert raw values
					map			=> "1:import.active.energy, 2:import+export.active.energy, 4:export.active.energy, 6:import+export.reactive.energy, 8:export.reactive.energy",	# map to convert visible values to internal numbers (for reading and writing)
					hint		=> "0,1,4,5,6,8",			# string for fhemweb to create a selection or slider
					format		=> '%.f',					# format string for sprintf
					poll		=> "once",					# only poll once after define (or after a set)
					set			=> 1,						# this value can be set
				},

	"h62720" =>	{	# holding register 0xF500
					# Demand interval , slide time, automatic scroll display interval(scroll Time)， Backlight time
					# Data Format: BCD min-min-s-min 10-01 -00-60
					# scroll time=0： the display does not scroll automatically.
					# Backlight time=0 Backlight always on
					name		=> "Demand interval",		# internal name of this register in the hardware doc
					reading		=> "system_demand_interval",# name of the reading for this value
					unpack		=>	"N",					# BCD pack / unpack code to convert raw values
					format		=> '',						# format string for sprintf
					poll		=> "once",					# only poll once after define (or after a set)
					set			=> 1,						# this value can be set
				},

	"h63760" =>	{	# holding register 0xF910
					# Data Format： Hex
					# 0000: 0.001kwh（ kvarh） /imp（ default）
					# 0001: 0.01kwh（ kvarh） /imp
					# 0002: 0.1kwh（ kvarh） /imp
					# 0003: 1kwh（ kvarh） /imp
					name		=> "Pulse 1 constant",		# internal name of this register in the hardware doc
					reading		=> "System_Pulse_constant",	# name of the reading for this value
					unpack		=>	"H*",					# Hex pack / unpack code to convert raw values
					map			=> "0:0.001/imp, 1:0.01/imp, 2:0.1/imp, 3:1/imp",	# map to convert visible values to internal numbers (for reading and writing)
					hint		=> "0,1,2,3",				# string for fhemweb to create a selection or slider
					format		=> '',						# format string for sprintf
					poll		=> "once",					# only poll once after define after define (or after a set)
					set			=> 1,						# this value can be set
				},

	"h63776" =>	{	# holding register 0xF920
					# Data Format： Hex
					# 0001:mode 1(total = import)
					# 0002:mode 2(total = import + export) （ default）
					# 0003:mode 3 (total = import - export)
					name		=> "Measurement mode",		# internal name of this register in the hardware doc
					reading		=> "System_Measurement_mode",	# name of the reading for this value
					unpack		=>	"H*",					# Hex pack / unpack code to convert raw values
					map			=> "1:import, 2:import+export, 3:import-export",	# map to convert visible values to internal numbers (for reading and writing)
					hint		=> "1,2,3",					# string for fhemweb to create a selection or slider
					format		=> '',						# format string for sprintf
					poll		=> "once",					# only poll once after define (or after a set)
					set			=> 1,						# this value can be set
				},

# Ende parseInfo
);


#####################################
sub
ModbusSDM220M_Initialize($)
{
    my ($modHash) = @_;

	require "$attr{global}{modpath}/FHEM/98_Modbus.pm";

	$modHash->{parseInfo}  = \%SDM220MparseInfo;			# defines registers, inputs, coils etc. for this Modbus Defive

	$modHash->{deviceInfo} = \%SDM220MdeviceInfo;			# defines properties of the device like 
															# defaults and supported function codes

	ModbusLD_Initialize($modHash);							# Generic function of the Modbus module does the rest

	$modHash->{AttrList} = $modHash->{AttrList} . " " .		# Standard Attributes like IODEv etc 
		$modHash->{ObjAttrList} . " " .						# Attributes to add or overwrite parseInfo definitions
		$modHash->{DevAttrList} . " " .						# Attributes to add or overwrite devInfo definitions
		"poll-.* " .										# overwrite poll with poll-ReadingName
		"polldelay-.* ";									# overwrite polldelay with polldelay-ReadingName
}


1;

=pod
=begin html

<a name="ModbusSDM220M"></a>
<h3>ModbusSDM220M</h3>
<ul>
    ModbusSDM220M uses the low level Modbus module to provide a way to communicate with SDM220M smart electrical meter from B+G E-Tech & EASTON.
	It defines the modbus input and holding registers and reads them in a defined interval.
	
	<br>
    <b>Prerequisites</b>
    <ul>
        <li>
          This module requires the basic Modbus module which itsef requires Device::SerialPort or Win32::SerialPort module.
        </li>
    </ul>
    <br>

    <a name="ModbusSDM220MDefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; ModbusSDM220M &lt;Id&gt; &lt;Interval&gt;</code>
        <br><br>
        The module connects to the smart electrical meter with Modbus Id &lt;Id&gt; through an already defined modbus device and actively requests data from the 
        smart electrical meter every &lt;Interval&gt; seconds <br>
        <br>
        Example:<br>
        <br>
        <ul><code>define SDM220M ModbusSDM220M 1 60</code></ul>
    </ul>
    <br>

    <a name="ModbusSDM220MConfiguration"></a>
    <b>Configuration of the module</b><br><br>
    <ul>
        apart from the modbus id and the interval which both are specified in the define command there is nothing that needs to be defined.
		However there are some attributes that can optionally be used to modify the behavior of the module. <br><br>
        
        The attributes that control which messages are sent / which data is requested every &lt;Interval&gt; seconds are:

        <pre>
		poll-Energy_total__kWh
		poll-Energy_import__kWh
		</pre>
        
        if the attribute is set to 1, the corresponding data is requested every &lt;Interval&gt; seconds. If it is set to 0, then the data is not requested.
        by default the temperatures are requested if no attributes are set.
        <br><br>
        Example:
        <pre>
        define SDM220M ModbusSDM220M 1 60
        attr SDM220M poll-Energy_total__kWh 0
        </pre>
    </ul>

    <a name="ModbusSDM220M"></a>
    <b>Set-Commands</b><br>
    <ul>
        The following set options are available:
        <pre>
        </pre>
    </ul>
	<br>
    <a name="ModbusSDM220MGet"></a>
    <b>Get-Commands</b><br>
    <ul>
        All readings are also available as Get commands. Internally a Get command triggers the corresponding 
        request to the device and then interprets the data and returns the right field value. To avoid huge option lists in FHEMWEB, only the most important Get options
        are visible in FHEMWEB. However this can easily be changed since all the readings and protocol messages are internally defined in the modue in a data structure 
        and to make a Reading visible as Get option only a little option (e.g. <code>showget => 1</code> has to be added to this data structure
    </ul>
	<br>
    <a name="ModbusSDM220Mattr"></a>
    <b>Attributes</b><br><br>
    <ul>
	<li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
		<li><b>poll-Energy_total__kWh</b></li> 
		<li><b>poll-Energy_import__kWh</b></li> 
            include a read request for the corresponding registers when sending requests every interval seconds <br>
        <li><b>timeout</b></li> 
            set the timeout for reads, defaults to 2 seconds <br>
		<li><b>minSendDelay</b></li> 
			minimal delay between two requests sent to this device
		<li><b>minCommDelay</b></li>  
			minimal delay between requests or receptions to/from this device
    </ul>
    <br>
</ul>

=end html
=cut
