##############################################
# $Id: Blocking.pm 8265 2015-03-22 13:58:15Z rudolfkoenig $
package main;

=pod
### Usage:
Define the following in your 99_myUtils.pm
sub TestBlocking($){ BlockingCall("DoSleep", shift, "SleepDone", 5, "AbortFn", "AbortArg"); }
sub DoSleep($)     { sleep(shift); return "I'm done"; }
sub SleepDone($)   { Log 1, "SleepDone: " . shift; }
sub AbortFn($)     { Log 1, "Aborted: " . shift; }
Then call from the fhem prompt
{ TestBlocking(3) }
{ TestBlocking(6) }
and watch the fhem log.
=cut


use strict;
use warnings;
use IO::Socket::INET;

sub BlockingCall($$@);
sub BlockingExit();
sub BlockingKill($);
sub BlockingInformParent($;$$);

my $telnetDevice;
my $telnetClient;

sub
BlockingCall($$@)
{
  my ($blockingFn, $arg, $finishFn, $timeout, $abortFn, $abortArg) = @_;

  # Look for the telnetport
  # must be done before forking to be able to create a temporary device
  my $tName = "telnetForBlockingFn";
  $telnetDevice = $tName if($defs{$tName});

  if(!$telnetDevice) {
    foreach my $d (sort keys %defs) {
      my $h = $defs{$d};
      next if(!$h->{TYPE} || $h->{TYPE} ne "telnet" || $h->{SNAME});
      next if($attr{$d}{SSL} || $attr{$d}{password} ||
              AttrVal($d, "allowfrom", "127.0.0.1") ne "127.0.0.1");
      next if($h->{DEF} =~ m/IPV6/);
      $telnetDevice = $d;
      last;
    }
  }

  # If not suitable telnet device found, create a temporary one
  if(!$telnetDevice) {
    if(!CommandDefine(undef, "$tName telnet 0")) {
      CommandAttr(undef, "$tName room hidden");
      $telnetDevice = $tName;
      $defs{$tName}{TEMPORARY} = 1;
      $attr{$tName}{allowfrom} = "127.0.0.1";
    }
  }

  if(!$telnetDevice) {
    my $msg = "CallBlockingFn: No telnet port found and cannot create one.";
    Log 1, $msg;
    return $msg;
  }

  # do fork
  my $pid = fhemFork;
  if(!defined($pid)) {
    Log 1, "Cannot fork: $!";
    return undef;
  }

  if($pid) {
    Log 4, "BlockingCall created child ($pid), uses $tName to connect back";
    my %h = ( pid=>$pid, fn=>$blockingFn, finishFn=>$finishFn, 
              abortFn=>$abortFn, abortArg=>$abortArg );
    if($timeout) {
      InternalTimer(gettimeofday()+$timeout, "BlockingKill", \%h, 0);
    }
    return \%h;
  }

  # Child here
  no strict "refs";
  my $ret = &{$blockingFn}($arg);
  use strict "refs";

  BlockingExit() if(!$finishFn);

  # Write the data back, calling the function
  BlockingInformParent($finishFn, $ret, 0);
  BlockingExit();
}

sub
BlockingInformParent($;$$)
{
  my ($informFn, $param, $waitForRead) = @_;
  my $ret = undef;
  $waitForRead = 1 if (!defined($waitForRead));
	
  # Write the data back, calling the function
  if(!$telnetClient) {
    my $addr = "localhost:$defs{$telnetDevice}{PORT}";
    $telnetClient = IO::Socket::INET->new(PeerAddr => $addr);
    Log 1, "CallBlockingFn: Can't connect to $addr: $@" if(!$telnetClient);
  }

  if(defined($param)) {
    if(ref($param) eq "ARRAY") {
      $param = join(",", map { $_ =~ s/'/\\'/g; "'$_'" } @{$param});

    } else {
      $param =~ s/'/\\'/g;
      $param = "'$param'"
    }
  } else {
    $param = "";
  }
  $param =~ s/;/;;/g;

  syswrite($telnetClient, "{$informFn($param)}\n");

  if ($waitForRead) {
    my $len = sysread($telnetClient, $ret, 4096);
    chop($ret);
    $ret = undef if(!defined($len));
  }

  return $ret;
}

# Parent
sub
BlockingKill($)
{
  my $h = shift;
  if($^O !~ m/Win/) {
    if($h->{pid} && kill(9, $h->{pid})) {
      Log 1, "Timeout for $h->{fn} reached, terminated process $h->{pid}";
      if($h->{abortFn}) {
        no strict "refs";
        my $ret = &{$h->{abortFn}}($h->{abortArg});
        use strict "refs";

      } elsif($h->{finishFn}) {
        no strict "refs";
        my $ret = &{$h->{finishFn}}();
        use strict "refs";

      }
    }
  }
}

# Child
sub
BlockingExit()
{
  close($telnetClient) if($telnetClient);

  if($^O =~ m/Win/) {
    eval "require threads;";
    threads->exit();

  } else {
    POSIX::_exit(0);

  }
}


1;
