##############################################
##############################################
# $Id: 98_ModbusSDM630M.pm 
#
#	fhem Modul für Stromzähler SDM630M von B+G E-Tech & EASTON
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
#	2015-01-15	initial release
#	2015-01-29	mit register-len, neue Namen für readings
#	2015-01-31	command reference angepasst
#	2015-02-01	fCodeMap -> devicveInfo Hash, Defaults für: timeouts, delays, Längen, Unpack und Format
#	2015-02-14	führende Nullen entfernt; defaultpolldelay, hint, map eingebaut
#	2015-02-17	defPoll, defShowGet Standards in deviceInfo eingebaut, showget und defaultpoll aus parseInfo entfernt 
#				defaultpoll=once verwendet, x[0-9] Format für defaultpolldelay verwendet
#	2015-02-23	ModbusSDM630M_Define & ModbusSDM630M_Undef entfernt
#				ModbusSDM630M_Initialize angepasst
#				%SDM630MparseInfo --> %parseInfo
#	2015-02-27	alle Register vom SDM630M eingebaut, Zyklenzeiten überarbeitet
#	2015-03-14	Anpassungan an neues 98_Modbus.pm, defaultpoll --> poll, defaultpolldelay --> polldelay,
#				attribute für timing umbenannt,
#				parseInfo --> SDM630MparseInfo, deviceInfo --> SDM630MdeviceInfo
#	2015-06-01	Register 160-164 für Erzeugung L1-L3 hinzugefügt

package main;

use strict;
use warnings;
use Time::HiRes qw( time );

sub ModbusSDM630M_Initialize($);

# deviceInfo defines properties of the device.
# some values can be overwritten in parseInfo, some defaults can even be overwritten by the user with attributes if a corresponding attribute is added to AttrList in _Initialize.
#
my %SDM630MdeviceInfo = (
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

my %SDM630MparseInfo = (
#	Spannung der Phasen, nur bei jedem 5. Zyklus
	"i0"	=>	{	# input register 0x0000
					name		=> "Phase 1 line to neutral volts",	# internal name of this register in the hardware doc
					reading		=> "Voltage_L1__V",			# name of the reading for this value
					format		=> '%.1f V',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},
	"i2"	=>	{	# input register 0x0002
					name		=> "Phase 2 line to neutral volts",	# internal name of this register in the hardware doc
					reading		=> "Voltage_L2__V",			# name of the reading for this value
					format		=> '%.1f V',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},
	"i4"	=>	{	# input register 0x0004
					name		=> "Phase 1 line to neutral volts",	# internal name of this register in the hardware doc
					reading		=> "Voltage_L3__V",			# name of the reading for this value
					format		=> '%.1f V',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},

#	Strom der Phasen
	"i6"	=>	{	# input register 0x0006
					name		=> "Phase 1 current",		# internal name of this register in the hardware doc
					reading		=> "Current_L1__A",			# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
				},
	"i8"	=>	{	# input register 0x0008
					name		=> "Phase 2 current",		# internal name of this register in the hardware doc
					reading		=> "Current_L2__A",			# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
				},
	"i10"	=>	{	# input register 0x000A
					name		=> "Phase 3 current",		# internal name of this register in the hardware doc
					reading		=> "Current_L3__A",			# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
				},

#	Leistung in W der Phasen
	"i12"	=>	{	# input register 0x000C, Phase 1: Leistung
					name		=> "Phase 1 power",			# internal name of this register in the hardware doc
					reading		=> "Power_L1__W",			# name of the reading for this value
					format		=> '%.f W',					# format string for sprintf
				},
	"i14"	=>	{	# input register 0x000E, Phase 2: Leistung
					name		=> "Phase 2 power",			# internal name of this register in the hardware doc
					reading		=> "Power_L2__W",			# name of the reading for this value
					format		=> '%.f W',					# format string for sprintf
				},
	"i16"	=>	{	# input register 0x0010, Phase 3: Leistung
					name		=> "Phase 3 power",			# internal name of this register in the hardware doc
					reading		=> "Power_L3__W",			# name of the reading for this value
					format		=> '%.f W',					# format string for sprintf
				},

#	Scheinleistung in VA der Phasen
	"i18"	=>	{	# input register 0x0012, Phase 1: Volt Ampere
					name		=> "Phase 1 volt amps",		# internal name of this register in the hardware doc
					reading		=> "Power_L1__VA",			# name of the reading for this value
					format		=> '%.1f VA',				# format string for sprintf
				},
	"i20"	=>	{	# input register 0x0014, Phase 2: Volt Ampere
					name		=> "Phase 2 volt amps",		# internal name of this register in the hardware doc
					reading		=> "Power_L2__VA",			# name of the reading for this value
					format		=> '%.1f VA',				# format string for sprintf
				},
	"i22"	=>	{	# input register 0x0016, Phase 3: Volt Ampere
					name		=> "Phase 3 volt amps",		# internal name of this register in the hardware doc
					reading		=> "Power_L3__VA",			# name of the reading for this value
					format		=> '%.1f VA',				# format string for sprintf
				},

#	Blindleistung in VAr
	"i24"	=>	{	# input register 0x0018
					name		=> "Phase 1 volt amps reactive",	# internal name of this register in the hardware doc
					reading		=> "Power_L1__VAr",			# name of the reading for this value
					format		=> '%.1f VAr',				# format string for sprintf
				},
	"i26"	=>	{	# input register 0x001A
					name		=> "Phase 2 volt amps reactive",	# internal name of this register in the hardware doc
					reading		=> "Power_L2__VAr",			# name of the reading for this value
					format		=> '%.1f VAr',				# format string for sprintf
				},
	"i28"	=>	{	# input register 0x001C
					name		=> "Phase 3 volt amps reactive",	# internal name of this register in the hardware doc
					reading		=> "Power_L3__VAr",			# name of the reading for this value
					format		=> '%.1f VAr',				# format string for sprintf
				},

# Leistungsfaktor der Phasen, nur jeden 10. Zyklus
	"i30"	=>	{	# input register 0x001E
					# The power factor has its sign adjusted to indicate the nature of the load.
					# Positive for capacitive and negative for inductive
					name		=> "Phase 1 power factor",	# internal name of this register in the hardware doc
					reading		=> "PowerFactor_L1",		# name of the reading for this value
					format		=> '%.1f',					# format string for sprintf
					polldelay	=> "x10",					# only poll this Value if last read is older than 10*Iteration, otherwiese getUpdate will skip it
				},
	"i32"	=>	{	# input register 0x0020
					# The power factor has its sign adjusted to indicate the nature of the load.
					# Positive for capacitive and negative for inductive
					name		=> "Phase 2 power factor",	# internal name of this register in the hardware doc
					reading		=> "PowerFactor_L2",		# name of the reading for this value
					format		=> '%.1f',					# format string for sprintf
					polldelay	=> "x10",					# only poll this Value if last read is older than 10*Iteration, otherwiese getUpdate will skip it
				},
	"i34"	=>	{	# input register 0x0022
					# The power factor has its sign adjusted to indicate the nature of the load.
					# Positive for capacitive and negative for inductive
					name		=> "Phase 3 power factor",	# internal name of this register in the hardware doc
					reading		=> "PowerFactor_L3",		# name of the reading for this value
					format		=> '%.1f',					# format string for sprintf
					polldelay	=> "x10",					# only poll this Value if last read is older than 10*Iteration, otherwiese getUpdate will skip it
				},

# Phasenverschiebung, nur jeden 3. Zyklus
	"i36"	=>	{	# input register 0x0024
					name		=> "Phase 1 phase angle",	# internal name of this register in the hardware doc
					reading		=> "CosPhi_L1",				# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x3",					# only poll this Value if last read is older than 3*Iteration, otherwiese getUpdate will skip it
				},
	"i38"	=>	{	# input register 0x0026
					name		=> "Phase 2 phase angle",	# internal name of this register in the hardware doc
					reading		=> "CosPhi_L2",				# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x3",					# only poll this Value if last read is older than 3*Iteration, otherwiese getUpdate will skip it
				},
	"i40"	=>	{	# input register 0x0028
					name		=> "Phase 3 phase angle",	# internal name of this register in the hardware doc
					reading		=> "CosPhi_L3",				# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x3",					# only poll this Value if last read is older than 3*Iteration, otherwiese getUpdate will skip it
				},

# Durchschnittswerte, nur bei jedem 2. Zyklus
	"i42"	=>	{	# input register 0x002A
					name		=> "Average line to neutral volts",	# internal name of this register in the hardware doc
					reading		=> "Voltage_Avr__V",		# name of the reading for this value
					format		=> '%.1f V',				# format string for sprintf
					polldelay	=> "x2",					# only poll this Value if last read is older than 2*Iteration, otherwiese getUpdate will skip it
				},
	"i46"	=>	{	# input register 0x002E
					name		=> "Average line current",	# internal name of this register in the hardware doc
					reading		=> "Current_Avr__A",		# name of the reading for this value
					format		=> '%.1f V',				# format string for sprintf
					polldelay	=> "x2",					# only poll this Value if last read is older than 2*Iteration, otherwiese getUpdate will skip it
				},

# Summenwerte
	"i48"	=>	{	# input register 0x0030
					name		=> "Sum of line currents",	# internal name of this register in the hardware doc
					reading		=> "Current_Sum__A",		# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
				},
	"i52"	=>	{	# input register 0x0034
					name		=> "Total system power",	# internal name of this register in the hardware doc
					reading		=> "Power_Sum__W",			# name of the reading for this value
					format		=> '%.1f W',				# format string for sprintf
				},
	"i56"	=>	{	# input register 0x0038
					name		=> "Total system Volt Ampere",	# internal name of this register in the hardware doc
					reading		=> "Power_Sum__VA",			# name of the reading for this value
					format		=> '%.1f VA',				# format string for sprintf
				},
	"i60"	=>	{	# input register 0x003C
					name		=> "Total system Volt Ampere reactive",	# internal name of this register in the hardware doc
					reading		=> "Power_Sum__VAr",		# name of the reading for this value
					format		=> '%.1f VAr',				# format string for sprintf
				},
	"i62"	=>	{	# input register 0x003E
					name		=> "Total system power factor",	# internal name of this register in the hardware doc
					reading		=> "PowerFactor",			# name of the reading for this value
					format		=> '%.1f',					# format string for sprintf
					polldelay	=> "x10",					# only poll this Value if last read is older than 10*Iteration, otherwiese getUpdate will skip it
				},
	"i66"	=>	{	# input register 0x0042
					name		=> "Total system phase angle",	# internal name of this register in the hardware doc
					reading		=> "CosPhi",				# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x3",					# only poll this Value if last read is older than 3*Iteration, otherwiese getUpdate will skip it
				},

# Frequenz, nur bei jedem 10. Zyklus
	"i70"	=>	{	# input register 0x0046
					name		=> "Frequency of supply voltages",	# internal name of this register in the hardware doc
					reading		=> "Frequency__Hz",			# name of the reading for this value
					format		=> '%.1f Hz',				# format string for sprintf
					polldelay	=> "x10",					# only poll this Value if last read is older than 10*Iteration, otherwiese getUpdate will skip it
				},

# Arbeit, Zyklus: jede Minute
	"i72"	=>	{	# input register 0x0048
					name		=> "Import Wh since last reset",	# internal name of this register in the hardware doc
					reading		=> "Energy_import__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i74"	=>	{	# input register 0x004A
					name		=> "Export Wh since last reset",	# internal name of this register in the hardware doc
					reading		=> "Energy_export__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i76"	=>	{	# input register 0x004C
					name		=> "Import VArh since last reset",	# internal name of this register in the hardware doc
					reading		=> "Energy_import__kVArh",	# name of the reading for this value
					format		=> '%.3f kVArh',			# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i78"	=>	{	# input register 0x004E
					name		=> "Export VArh since last reset",	# internal name of this register in the hardware doc
					reading		=> "Energy_export__kVArh",	# name of the reading for this value
					format		=> '%.3f kVArh',			# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},

# Scheinleistung
	"i80"	=>	{	# input register 0x0050
					name		=> "VAh since last reset",	# internal name of this register in the hardware doc
					reading		=> "Energy_apparent__kVAh",	# name of the reading for this value
					format		=> '%.3f kVAh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},

# Ladung
	"i82"	=>	{	# input register 0x0052
					name		=> "kAh since last reset",	# internal name of this register in the hardware doc
					reading		=> "Charge__kAh",			# name of the reading for this value
					format		=> '%.3f kAh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},

# Bezug
	"i84"	=>	{	# input register 0x0054
					name		=> "Total system power demand",	# internal name of this register in the hardware doc
					reading		=> "Power_Sum_demand__W",	# name of the reading for this value
					format		=> '%.1f W',				# format string for sprintf
				},
	"i86"	=>	{	# input register 0x0056
					name		=> "Maximum total system power demand",	# internal name of this register in the hardware doc
					reading		=> "Power_Max_demand__W",	# name of the reading for this value
					format		=> '%.1f W',				# format string for sprintf
					polldelay	=> 900,						# request only if last read is older than 15 minutes
				},
	"i100"	=>	{	# input register 0x0064
					name		=> "Total system VA demand",	# internal name of this register in the hardware doc
					reading		=> "Power_Sum_demand__VA",	# name of the reading for this value
					format		=> '%.1f VA',				# format string for sprintf
				},
	"i102"	=>	{	# input register 0x0066
					name		=> "Maximum total system VA demand",	# internal name of this register in the hardware doc
					reading		=> "Power_Max_demand__VA",	# name of the reading for this value
					format		=> '%.1f VA',				# format string for sprintf
					polldelay	=> 900,						# request only if last read is older than 15 minutes
				},
	"i104"	=>	{	# input register 0x0068
					name		=> "Neutral current demand",	# internal name of this register in the hardware doc
					reading		=> "Current_N_demand__A",	# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
				},
	"i106"	=>	{	# input register 0x006A
					name		=> "Maximum neutral current demand",	# internal name of this register in the hardware doc
					reading		=> "Current_Max_N_demand__A",	# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
					polldelay	=> 900,						# request only if last read is older than 15 minutes
				},

# Spannung zwischen den Phasen, nur bei jedem 5. Zyklus
	"i200"	=>	{	# input register 0x00C8
					name		=> "Line1 to Line2 volts",	# internal name of this register in the hardware doc
					reading		=> "Voltage_L1_to_L2__V",	# name of the reading for this value
					format		=> '%.1f V',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},
	"i202"	=>	{	# input register 0x00CA
					name		=> "Line2 to Line3 volts",	# internal name of this register in the hardware doc
					reading		=> "Voltage_L2_to_L3__V",	# name of the reading for this value
					format		=> '%.1f V',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},
	"i204"	=>	{	# input register 0x00CC
					name		=> "Line3 to Line1 volts",	# internal name of this register in the hardware doc
					reading		=> "Voltage_L3_to_L1__V",	# name of the reading for this value
					format		=> '%.1f V',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},
	"i206"	=>	{	# input register 0x00CE
					name		=> "Average line to line volts",	# internal name of this register in the hardware doc
					reading		=> "Voltage_Avr_L_to_L__V",	# name of the reading for this value
					format		=> '%.1f V',				# format string for sprintf
					polldelay	=> "x10",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},

# Strom
	"i224"	=>	{	# input register 0x00E0
					name		=> "Neutral current",		# internal name of this register in the hardware doc
					reading		=> "Current_N__A",			# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
				},

# Verzerrung Spannung, nur bei jedem 5. Zyklus
	"i234"	=>	{	# input register 0x00EA
					name		=> "Phase 1 L/N volts THD",	# internal name of this register in the hardware doc
					reading		=> "THD_Voltage_L1_N__%",	# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},
	"i236"	=>	{	# input register 0x00EC
					name		=> "Phase 2 L/N volts THD",	# internal name of this register in the hardware doc
					reading		=> "THD_Voltage_L2_N__%",	# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},
	"i238"	=>	{	# input register 0x00EE
					name		=> "NPhase 3 L/N volts THD",# internal name of this register in the hardware doc
					reading		=> "THD_Voltage_L2_N__%",	# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},

# Verzerrung Strom, nur bei jedem 5. Zyklus
	"i240"	=>	{	# input register 0x00F0
					name		=> "Phase 1 Current THD",	# internal name of this register in the hardware doc
					reading		=> "THD_Current_L1__%",		# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},
	"i242"	=>	{	# input register 0x00F2
					name		=> "Phase 2 Current THD",	# internal name of this register in the hardware doc
					reading		=> "THD_Current_L2__%",		# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},
	"i244"	=>	{	# input register 0x00F4
					name		=> "Phase 3 Current THD",	# internal name of this register in the hardware doc
					reading		=> "THD_Current_L3__%",		# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},

# Verzerrung Durchschnitt, nur bei jedem 15. Zyklus
	"i248"	=>	{	# input register 0x00F8
					name		=> "Average line to neutral volts THD",	# internal name of this register in the hardware doc
					reading		=> "THD_Voltage_avr_LN__%",	# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x15",					# only poll this Value if last read is older than 2*Iteration, otherwiese getUpdate will skip it
				},
	"i250"	=>	{	# input register 0x00FA
					name		=> "Average line current THD",	# internal name of this register in the hardware doc
					reading		=> "THD_Current_avr__%",	# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x15",					# only poll this Value if last read is older than 2*Iteration, otherwiese getUpdate will skip it
				},

	"i254"	=>	{	# input register 0x00FE
					name		=> "Total system power factor",	# internal name of this register in the hardware doc
					reading		=> "PowerFactor_inverted",	# name of the reading for this value
					format		=> '%.1f',					# format string for sprintf
					polldelay	=> "x10",					# only poll this Value if last read is older than 10*Iteration, otherwiese getUpdate will skip it
				},

# Strom: aktueller Strombezug
	"i258"	=>	{	# input register 0x0102
					name		=> "Phase 1 current demand",# internal name of this register in the hardware doc
					reading		=> "Current_L1_demand__A",	# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
				},
	"i260"	=>	{	# input register 0x0104
					name		=> "Phase 2 current demand",# internal name of this register in the hardware doc
					reading		=> "Current_L2_demand__A",	# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
				},
	"i262"	=>	{	# input register 0x0106
					name		=> "Phase 3 current demand",# internal name of this register in the hardware doc
					reading		=> "Current_L3_demand__A",	# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
				},

# Maximum Strombezug, nur aller 15 Minuten
	"i264"	=>	{	# input register 0x0108
					name		=> "Maximum phase 1 current demand",	# internal name of this register in the hardware doc
					reading		=> "Current_Max_L1_demand__A",	# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
					polldelay	=> 900,						# request only if last read is older than 15 minutes
				},
	"i266"	=>	{	# input register 0x010A
					name		=> "Maximum phase 2 current demand",	# internal name of this register in the hardware doc
					reading		=> "Current_Max_L2_demand__A",	# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
					polldelay	=> 900,						# request only if last read is older than 15 minutes
				},
	"i268"	=>	{	# input register 0x010C
					name		=> "Maximum phase 3 current demand",	# internal name of this register in the hardware doc
					reading		=> "Current_Max_L3_demand__A",	# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
					polldelay	=> 900,						# request only if last read is older than 15 minutes
				},

# Verzerrung Spannung, nur bei jedem 5. Zyklus
	"i334"	=>	{	# input register 0x014E
					name		=> "Line 1 to line 2 volts THD",	# internal name of this register in the hardware doc
					reading		=> "THD_Voltage_L1_L2__%",	# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},
	"i336"	=>	{	# input register 0x0150
					name		=> "Line 2 to line 3 volts THD",	# internal name of this register in the hardware doc
					reading		=> "THD_Voltage_L2_L3__%",	# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},
	"i338"	=>	{	# input register 0x0152
					name		=> "Line 3 to line 1 volts THD",	# internal name of this register in the hardware doc
					reading		=> "THD_Voltage_L3_L1__%",	# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x5",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},
	"i340"	=>	{	# input register 0x0154
					name		=> "Average line to line volts THD",	# internal name of this register in the hardware doc
					reading		=> "THD_Voltage_avr_LL__%",	# name of the reading for this value
					format		=> '%.1f %',				# format string for sprintf
					polldelay	=> "x15",					# only poll this Value if last read is older than 5*Iteration, otherwiese getUpdate will skip it
				},

# kWh Gesamtwerte, Zyklus: jede Minute
	"i342"	=>	{	# input register 0x0156
					name		=> "Total kWh",				# internal name of this register in the hardware doc
					reading		=> "Energy_total__kWh",		# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i344"	=>	{	# input register 0x0158
					name		=> "Total VArh",			# internal name of this register in the hardware doc
					reading		=> "Energy_total__kVArh",	# name of the reading for this value
					format		=> '%.3f kVArh',			# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},

# kWh Bezug, Zyklus: jede Minute
	"i346"	=>	{	# input register 0x015A
					name		=> "L1 import kWh",			# internal name of this register in the hardware doc
					reading		=> "Energy_L1_import__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i348"	=>	{	# input register 0x015C
					name		=> "L2 import kWh",			# internal name of this register in the hardware doc
					reading		=> "Energy_L2_import__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i350"	=>	{	# input register 0x015E
					name		=> "L3 import kWh",			# internal name of this register in the hardware doc
					reading		=> "Energy_L3_import__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},

# kWh Erzeugung, Zyklus: jede Minute
	"i352"	=>	{	# input register 0x0160
					name		=> "L1 export kWh",			# internal name of this register in the hardware doc
					reading		=> "Energy_L1_export__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i354"	=>	{	# input register 0x0162
					name		=> "L2 export kWh",			# internal name of this register in the hardware doc
					reading		=> "Energy_L2_export__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i356"	=>	{	# input register 0x0164
					name		=> "L3 export kWh",			# internal name of this register in the hardware doc
					reading		=> "Energy_L3_export__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},

# kWh Gesamtwerte, Zyklus: jede Minute
	"i358"	=>	{	# input register 0x0166
					name		=> "L1 total kWh",			# internal name of this register in the hardware doc
					reading		=> "Energy_L1_total__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i360"	=>	{	# input register 0x0168
					name		=> "L2 total kWh",			# internal name of this register in the hardware doc
					reading		=> "Energy_L2_total__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},
	"i362"	=>	{	# input register 0x016A
					name		=> "L3 total kWh",			# internal name of this register in the hardware doc
					reading		=> "Energy_L3_total__kWh",	# name of the reading for this value
					format		=> '%.3f kWh',				# format string for sprintf
					polldelay	=> 60,						# request only if last read is older than 60 seconds
				},


###############################################################################################################
# Holding Register
###############################################################################################################
	"h0"	=>	{	# holding register 0x0000
					# Read minutes into first demand calculation.
					# When the Demand Time reaches the Demand Period then the demand values are valid.
					name		=> "Demand Time",			# internal name of this register in the hardware doc
					reading		=> "Demand_Time__minutes",	# name of the reading for this value
					format		=> '%.f min',				# format string for sprintf
					poll		=> "once",					# only poll once after define (or after a set)
				},

	"h2"	=>	{	# holding register 0x0002
					# Write demand period: 0,5,8,10,15,20,30 or 60 minutes, default 60
					# Setting the period to 0 will cause the demand to show the current parameter value,
					# and demand max to show the maximum parameter value since last demand reset.
					name		=> "Demand Period",			# internal name of this register in the hardware doc
					reading		=> "Demand_Period__minutes",# name of the reading for this value
					format		=> '%.f min',				# format string for sprintf
					hint		=> "0,5,8,10,15,20,30,60",	# string for fhemweb to create a selection or slider
					min			=> 0,						# input validation for set: min value
					max			=> 60,						# input validation for set: max value
					poll		=> "once",					# only poll once after define (or after a set)
					set			=> 1,						# this value can be set
				},

	"h6"	=>	{	# holding register 0x0006
					name		=> "system voltage",		# internal name of this register in the hardware doc
					reading		=> "System_Voltage__V",		# name of the reading for this value
					format		=> '%.1f V',				# format string for sprintf
					poll		=> "once",					# only poll once after define (or after a set)
				},

	"h8"	=>	{	# holding register 0x0008
					name		=> "system current",		# internal name of this register in the hardware doc
					reading		=> "System_Current__A",		# name of the reading for this value
					format		=> '%.2f A',				# format string for sprintf
					poll		=> "once",					# only poll once after define (or after a set)
				},

	"h10"	=>	{	# holding register 0x000A
					# Write system type: 1=1p2w, 2=3p3w, 3=3p4w
					# Requires password, see register Password 0x0018
					name		=> "System Type",			# internal name of this register in the hardware doc
					reading		=> "System_Type",			# name of the reading for this value
					map			=> "1:1p2w, 2:3p3w, 3:3p4w",# map to convert visible values to internal numbers (for reading and writing)
					hint		=> "1,2,3",					# string for fhemweb to create a selection or slider
					poll		=> "once",					# only poll once after define (or after a set)
					set			=> 1,						# this value can be set
				},

	"h12"	=>	{	# holding register 0x000C
					# Write relay on period in milliseconds: 60, 100 or 200, default 200
					name		=> "Relay 1 Pulse Width",	# internal name of this register in the hardware doc
					reading		=> "System_Pulse_Width__ms",# name of the reading for this value
					format		=> '%.f ms',				# format string for sprintf
					hint		=> "60,100,200",			# string for fhemweb to create a selection or slider
					poll		=> "once",					# only poll once after define (or after a set)
					set			=> 1,						# this value can be set
				},

	"h14"	=>	{	# holding register 0x000E
					# Write any value to password lock protected registers.
					# Read password lock status: 0=locked, 1=unlocked
					# Reading will also reset the password timeout back to one minute.
					name		=> "Password Lock",			# internal name of this register in the hardware doc
					reading		=> "System_Password_Lock",	# name of the reading for this value
					map			=> "0:locked, 1:unlocked",	# map to convert visible values to internal numbers (for reading and writing)
					hint		=> "0,1",					# string for fhemweb to create a selection or slider
					poll		=> "once",					# only poll once after define (or after a set)
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

	"h22"	=>	{	# holding register 0x0016
					# Write pulse divisor index: n= 1 to 5
					# 1=0.01kw/imp; 2=0.1kw/imp; 3=1kw/imp; 4=10kw/imp; 5=100kw/imp
					name		=> "Pulse Divisor1",		# internal name of this register in the hardware doc
					reading		=> "Pulse_Divisor_1",		# name of the reading for this value
					map			=> "1:0.01kw/imp, 2:0.1kw/imp, 3:1kw/imp, 4:10kw/imp, 5:100kw/imp",	# map to convert visible values to internal numbers (for reading and writing)
					hint		=> "1,2,3,4,5",				# string for fhemweb to create a selection or slider
					poll		=> "once",					# only poll once after define (or after a set)
					set			=> 1,						# this value can be set
				},

	"h24"	=>	{	# holding register 0x0018
					# Write password for access to protected registers.
					name		=> "Password",				# internal name of this register in the hardware doc
					reading		=> "System_Password",		# name of the reading for this value
					set			=> 1,						# this value can be set
				},

	"h28"	=>	{	# holding register 0x001C
					# Write the network port baud rate for MODBUS Protocol, where:
					# 0=2400; 1=4800; 2=9600; 3=19200; 4=38400;
					# Requires no restart, wird sofort active!
					name		=> "Network Baud Rate",		# internal name of this register in the hardware doc
					reading		=> "Modbus_Speed__baud",	# name of the reading for this value
					map			=> "0:2400, 1:4800, 2:9600, 3:19200, 4:38400",	# map to convert visible values to internal numbers (for reading and writing)
					hint		=> "0,1,2,3,4",				# string for fhemweb to create a selection or slider
					poll		=> "once",					# only poll once after define (or after a set)
					set			=> 1,						# this value can be set
				},

	"h36"	=>	{	# holding register 0x0024
					# Read the total system power, e.g. for 3p4w returns System Volts x System Amps x 3.
					name		=> "System Power",			# internal name of this register in the hardware doc
					reading		=> "System_Power__W",		# name of the reading for this value
					format		=> '%.f W',					# format string for sprintf
					poll		=> "once",					# only poll once after define (or after a set)
				},

	"h42"	=>	{	# holding register 0x002A
					name		=> "Serial Number",			# internal name of this register in the hardware doc
					reading		=> "System_Serial_Nr",		# name of the reading for this value
					format		=> '%.f',					# format string for sprintf
					poll		=> "once",					# only poll once after define (or after a set)
				},

	"h86"	=>	{	# holding register 0x0056
					# Write MODBUS Protocol input parameter for pulse relay 1:
					# 37 = Total Wh or 39 = Total VArh, default 39
					name		=> "Relay l Energy Type",	# internal name of this register in the hardware doc
					reading		=> "Relay1_Energy_Type",	# name of the reading for this value
					map			=> "37:Total Wh, 39:Total VArh",	# map to convert visible values to internal numbers (for reading and writing)
					format		=> '%.f',					# format string for sprintf
					poll		=>	0,						# not be polled by default, unless specified otherwise by attributes
					set			=> 1,						# this value can be set
				},

	"h88"	=>	{	# holding register 0x0058
					name		=> "Relay 2 Energy Type",	# internal name of this register in the hardware doc
					reading		=> "Relay2_Energy_Type",	# name of the reading for this value
					format		=> '%.f',					# format string for sprintf
					poll		=> "once",					# only poll once after define (or after a set)
				},

# Ende parseInfo
);


#####################################
sub
ModbusSDM630M_Initialize($)
{
    my ($modHash) = @_;

	require "$attr{global}{modpath}/FHEM/98_Modbus.pm";

	$modHash->{parseInfo}  = \%SDM630MparseInfo;			# defines registers, inputs, coils etc. for this Modbus Defive

	$modHash->{deviceInfo} = \%SDM630MdeviceInfo;			# defines properties of the device like 
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

<a name="ModbusSDM630M"></a>
<h3>ModbusSDM630M</h3>
<ul>
    ModbusSDM630M uses the low level Modbus module to provide a way to communicate with SDM630M smart electrical meter from B+G E-Tech & EASTON.
	It defines the modbus input and holding registers and reads them in a defined interval.
	
	<br>
    <b>Prerequisites</b>
    <ul>
        <li>
          This module requires the basic Modbus module which itsef requires Device::SerialPort or Win32::SerialPort module.
        </li>
    </ul>
    <br>

    <a name="ModbusSDM630MDefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; ModbusSDM630M &lt;Id&gt; &lt;Interval&gt;</code>
        <br><br>
        The module connects to the smart electrical meter with Modbus Id &lt;Id&gt; through an already defined modbus device and actively requests data from the 
        smart electrical meter every &lt;Interval&gt; seconds <br>
        <br>
        Example:<br>
        <br>
        <ul><code>define SDM630M ModbusSDM630M 1 60</code></ul>
    </ul>
    <br>

    <a name="ModbusSDM630MConfiguration"></a>
    <b>Configuration of the module</b><br><br>
    <ul>
        apart from the modbus id and the interval which both are specified in the define command there is nothing that needs to be defined.
		However there are some attributes that can optionally be used to modify the behavior of the module. <br><br>
        
        The attributes that control which messages are sent / which data is requested every &lt;Interval&gt; seconds are:

        <pre>
		poll-Energy_total__kWh
		poll-Energy_import__kWh
		poll-Energy_L1_total__kWh
		poll-Energy_L2_total__kWh
		poll-Energy_L3_total__kWh
		</pre>
        
        if the attribute is set to 1, the corresponding data is requested every &lt;Interval&gt; seconds. If it is set to 0, then the data is not requested.
        by default the temperatures are requested if no attributes are set.
        <br><br>
        Example:
        <pre>
        define SDM630M ModbusSDM630M 1 60
        attr SDM630M poll-Energy_total__kWh 0
        </pre>
    </ul>

    <a name="ModbusSDM630M"></a>
    <b>Set-Commands</b><br>
    <ul>
        The following set options are available:
        <pre>
        </pre>
    </ul>
	<br>
    <a name="ModbusSDM630MGet"></a>
    <b>Get-Commands</b><br>
    <ul>
        All readings are also available as Get commands. Internally a Get command triggers the corresponding 
        request to the device and then interprets the data and returns the right field value. To avoid huge option lists in FHEMWEB, only the most important Get options
        are visible in FHEMWEB. However this can easily be changed since all the readings and protocol messages are internally defined in the modue in a data structure 
        and to make a Reading visible as Get option only a little option (e.g. <code>showget => 1</code> has to be added to this data structure
    </ul>
	<br>
    <a name="ModbusSDM630Mattr"></a>
    <b>Attributes</b><br><br>
    <ul>
	<li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
		<li><b>poll-Energy_total__kWh</b></li> 
		<li><b>poll-Energy_import__kWh</b></li> 
		<li><b>poll-Energy_L1_total__kWh</b></li> 
		<li><b>poll-Energy_L2_total__kWh</b></li> 
		<li><b>poll-Energy_L3_total__kWh</b></li> 
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
