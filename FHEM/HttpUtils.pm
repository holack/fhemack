##############################################
# $Id: HttpUtils.pm 7155 2014-12-07 11:41:33Z rudolfkoenig $
package main;

use strict;
use warnings;
use IO::Socket::INET;
use MIME::Base64;
use vars qw($SSL_ERROR);

my %ext2MIMEType= qw{
  css   text/css
  gif   image/gif
  html  text/html
  ico   image/x-icon
  jpg   image/jpeg
  js    text/javascript
  pdf   application/pdf
  png   image/png
  svg   image/svg+xml
  txt   text/plain

};

sub
ext2MIMEType($) {
  my ($ext)= @_;
  return "text/plain" if(!$ext);
  my $MIMEType = $ext2MIMEType{lc($ext)};
  return ($MIMEType ? $MIMEType : "text/$ext");
}

sub
filename2MIMEType($) {
  my ($filename)= @_;
  $filename =~ m/^.*\.([^\.]*)$/;
  return ext2MIMEType($1);
}
  

##################
sub
urlEncode($) {
  $_= $_[0];
  s/([\x00-\x2F,\x3A-\x40,\x5B-\x60,\x7B-\xFF])/sprintf("%%%02x",ord($1))/eg;
  return $_;
}

##################
sub
urlDecode($) {
  $_= $_[0];
  s/%([0-9A-F][0-9A-F])/chr(hex($1))/egi;
  return $_;
}

sub
HttpUtils_ConnErr($)
{
  my ($hash) = @_;
  $hash = $hash->{hash};
  if(defined($hash->{FD})) {
    delete($hash->{FD});
    delete($selectlist{$hash});
    $hash->{conn}->close();
    $hash->{callback}($hash, "connect to $hash->{addr} timed out", "");
  }
}

sub
HttpUtils_ReadErr($)
{
  my ($hash) = @_;
  $hash = $hash->{hash};
  if(defined($hash->{FD})) {
    delete($hash->{FD});
    delete($selectlist{$hash});
    $hash->{callback}($hash, "read from $hash->{addr} timed out", "");
  }
}

sub
HttpUtils_File($)
{
  my ($hash) = @_;

  return 0 if($hash->{url} !~ m+^file://(.*)$+);

  my $fName = $1;
  return (1, "Absolute URL is not supported") if($fName =~ m+^/+);
  return (1, ".. in URL is not supported") if($fName =~ m+\.\.+);
  open(FH, $fName) || return(1, "$fName: $!");
  my $data = join("", <FH>);
  close(FH);
  return (1, undef, $data);
}

sub
HttpUtils_Connect($)
{
  my ($hash) = @_;

  $hash->{timeout}    = 4 if(!defined($hash->{timeout}));
  $hash->{loglevel}   = 4 if(!$hash->{loglevel});
  $hash->{redirects}  = 0 if(!$hash->{redirects});
  $hash->{displayurl} = $hash->{hideurl} ? "<hidden>" : $hash->{url};

  Log3 $hash, $hash->{loglevel}, "HttpUtils url=$hash->{displayurl}";

  if($hash->{url} !~
           /^(http|https):\/\/(([^:\/]+):([^:\/]+)@)?([^:\/]+)(:\d+)?(\/.*)$/) {
    return "$hash->{displayurl}: malformed or unsupported URL";
  }

  my ($authstring,$user,$pwd,$port,$host);
  ($hash->{protocol},$authstring,$user,$pwd,$host,$port,$hash->{path})
        = ($1,$2,$3,$4,$5,$6,$7);
  $hash->{host} = $host;
  
  if(defined($port)) {
    $port =~ s/^://;
  } else {
    $port = ($hash->{protocol} eq "https" ? 443: 80);
  }
  $hash->{path} = '/' unless defined($hash->{path});
  $hash->{addr} = "$hash->{protocol}://$host:$port";
  $hash->{auth} = encode_base64("$user:$pwd","") if($authstring);

  if($hash->{callback}) { # Nonblocking staff
    $hash->{conn} = IO::Socket::INET->new(Proto=>'tcp', Blocking=>0);
    if($hash->{conn}) {
      my $iaddr = inet_aton($host);
      if(!defined($iaddr)) {
        my @addr = gethostbyname($host); # This is still blocking
        return "gethostbyname $host failed" if(!$addr[0]);
        $iaddr = $addr[4];
      }
      my $ret = connect($hash->{conn}, sockaddr_in($port, $iaddr));
      if(!$ret) {
        if($!{EINPROGRESS} || int($!)==10035) { # Nonblocking connect

          $hash->{FD} = $hash->{conn}->fileno();
          my %timerHash = ( hash => $hash );
          $hash->{directWriteFn} = sub() {
            delete($hash->{FD});
            delete($hash->{directWriteFn});
            delete($selectlist{$hash});

            RemoveInternalTimer(\%timerHash);
            my $packed = getsockopt($hash->{conn}, SOL_SOCKET, SO_ERROR);
            my $errno = unpack("I",$packed);
            return $hash->{callback}($hash, "$host: ".strerror($errno), "")
                if($errno);

            return HttpUtils_Connect2($hash);
          };
          $hash->{NAME} = "" if(!defined($hash->{NAME})); #Delete might check it
          $selectlist{$hash} = $hash;
          InternalTimer(gettimeofday()+$hash->{timeout},
                        "HttpUtils_ConnErr", \%timerHash, 0);
          return undef;
        } else {
          return "connect: $!";
        }
      }
    }
                
  } else {
    $hash->{conn} = IO::Socket::INET->new(
                PeerAddr=>"$host:$port", Timeout=>$hash->{timeout});
    return "$hash->{displayurl}: Can't connect(1) to $hash->{addr}: $@"
      if(!$hash->{conn});
  }
  return HttpUtils_Connect2($hash);
}

sub
HttpUtils_Connect2($)
{
  my ($hash) = @_;

  if($hash->{protocol} eq "https" && $hash->{conn}) {
    eval "use IO::Socket::SSL";
    if($@) {
      Log3 $hash, $hash->{loglevel}, $@;
    } else {
      $hash->{conn}->blocking(1);
      IO::Socket::SSL->start_SSL($hash->{conn}, {
          Timeout     => $hash->{timeout},
          SSL_version => 'SSLv23:!SSLv3:!SSLv2', #Forum #27565
        }) || undef $hash->{conn};
    }
  }

  if(!$hash->{conn}) {
    undef $hash->{conn};
    my $err = $@;
    if($hash->{protocol} eq "https") {
      $err = "" if(!$err);
      $err .= " ".($SSL_ERROR ? $SSL_ERROR : IO::Socket::SSL::errstr());
    }
    return "$hash->{displayurl}: Can't connect(2) to $hash->{addr}: $err"; 
  }

  my $data;
  if(defined($hash->{data})) {
    if( ref($hash->{data}) eq 'HASH' ) {
      foreach my $key (keys %{$hash->{data}}) {
        $data .= "&" if( $data );
        $data .= "$key=". urlEncode($hash->{data}{$key});
      }
    } else {
      $data = $hash->{data};
    }
  }

  $hash->{host} =~ s/:.*//;
  my $method = $hash->{method};
  $method = ($data ? "POST" : "GET") if( !$method );

  my $httpVersion = $hash->{httpversion} ? $hash->{httpversion} : "1.0";
  my $hdr = "$method $hash->{path} HTTP/$httpVersion\r\n";
  $hdr .= "Host: $hash->{host}\r\n";
  $hdr .= "Connection: Close\r\n" if($httpVersion ne "1.0");
  $hdr .= "Authorization: Basic $hash->{auth}\r\n" if(defined($hash->{auth}));
  $hdr .= $hash->{header}."\r\n" if(defined($hash->{header}));
  if(defined($data)) {
    $hdr .= "Content-Length: ".length($data)."\r\n";
    $hdr .= "Content-Type: application/x-www-form-urlencoded\r\n"
                if ($hdr !~ "Content-Type:");
  }
  $hdr .= "\r\n";
  syswrite $hash->{conn}, $hdr;
  syswrite $hash->{conn}, $data if(defined($data));

  my $s = $hash->{shutdown};
  $s =(defined($hash->{noshutdown}) && $hash->{noshutdown}==0) if(!defined($s));
  $s = 0 if($hash->{protocol} eq "https");
  shutdown($hash->{conn}, 1) if($s);

  if($hash->{callback}) { # Nonblocking read
    $hash->{FD} = $hash->{conn}->fileno();
    $hash->{buf} = "";
    $hash->{NAME} = "" if(!defined($hash->{NAME})); 
    my %timerHash = ( hash => $hash );
    $hash->{directReadFn} = sub() {
      my $buf;
      my $len = sysread($hash->{conn},$buf,65536);
      $hash->{buf} .= $buf if(defined($len) && $len > 0);
      if(!defined($len) || $len <= 0 || HttpUtils_DataComplete($hash->{buf})) {
        delete($hash->{FD});
        delete($hash->{directReadFn});
        delete($selectlist{$hash});
        RemoveInternalTimer(\%timerHash);
        my ($err, $ret, $redirect) = HttpUtils_ParseAnswer($hash, $hash->{buf});
        $hash->{callback}($hash, $err, $ret) if(!$redirect);
        return;
      }
    };
    $selectlist{$hash} = $hash;
    InternalTimer(gettimeofday()+$hash->{timeout},
                  "HttpUtils_ReadErr", \%timerHash, 0);
    return undef;
  }

  return undef;
}

sub
HttpUtils_DataComplete($)
{
  my ($ret) = @_;
  return 0 if($ret !~ m/^(.*?)\r\n\r\n(.*)$/s);
  my $hdr = $1;
  my $data = $2;
  return 0 if($hdr !~ m/Content-Length:\s*(\d+)/s);
  return 0 if(length($data) < $1);
  return 1;
}

sub
HttpUtils_ParseAnswer($$)
{
  my ($hash, $ret) = @_;

  $hash->{conn}->close();
  undef $hash->{conn};

  if(!$ret) {
    return ("$hash->{displayurl}: empty answer received", "");
  }

  $ret=~ s/(.*?)\r\n\r\n//s; # Not greedy: switch off the header.
  return ("", $ret) if(!defined($1));

  $hash->{httpheader} = $1;
  my @header= split("\r\n", $1);
  my @header0= split(" ", shift @header);
  my $code= $header0[1];

  if(!defined($code) || $code eq "") {
    return ("$hash->{displayurl}: empty answer received", "");
  }
  Log3 $hash,$hash->{loglevel}, "$hash->{displayurl}: HTTP response code $code";
  $hash->{code} = $code;
  if(($code==301 || $code==302 || $code==303) 
	&& !$hash->{ignoreredirects}) { # redirect
    if(++$hash->{redirects} > 5) {
      return ("$hash->{displayurl}: Too many redirects", "");

    } else {
      my $ra;
      map { $ra=$1 if($_ =~ m/Location:\s*(\S+)$/) } @header;
      $hash->{url} = ($ra =~ m/^http/) ? $ra: $hash->{addr}.$ra;
      Log3 $hash, $hash->{loglevel}, "HttpUtils $hash->{displayurl}: ".
          "Redirect to ".($hash->{hideurl} ? "<hidden>" : $hash->{url});
      if($hash->{callback}) {
        HttpUtils_NonblockingGet($hash);
        return ("", "", 1);
      } else {
        return HttpUtils_BlockingGet($hash);
      }
    }
  }
  
  # Debug
  Log3 $hash, $hash->{loglevel},
       "HttpUtils $hash->{displayurl}: Got data, length: ".  length($ret);
  if(!length($ret)) {
    Log3 $hash, $hash->{loglevel}, "HttpUtils $hash->{displayurl}: ".
         "Zero length data, header follows:";
    for (@header) {
      Log3 $hash, $hash->{loglevel}, "  $_";
    }
  }
  return ("", $ret);
}

# Parameters in the hash:
#  mandatory:
#    url, callback
#  optional(default):
#    hideurl(0),timeout(4),data(""),loglevel(4),header(""),
#    noshutdown(1),shutdown(0),httpversion("1.0"),ignoreredirects(0)
#    method($data ? "POST" : "GET")
# Example:
#   HttpUtils_NonblockingGet({
#     url=>"http://192.168.178.112:8888/fhem",
#     myParam=>7,
#     callback=>sub($$$){ Log 1,"$_[0]->{myParam} ERR:$_[1] DATA:$_[2]" }
#   })
sub
HttpUtils_NonblockingGet($)
{
  my ($hash) = @_;
  my ($isFile, $fErr, $fContent) = HttpUtils_File($hash);
  return $hash->{callback}($hash, $fErr, $fContent) if($isFile);
  my $err = HttpUtils_Connect($hash);
  $hash->{callback}($hash, $err, "") if($err);
}

#################
# Parameters same as HttpUtils_NonblockingGet up to callback
# Returns (err,data)
sub
HttpUtils_BlockingGet($)
{
  my ($hash) = @_;
  my ($isFile, $fErr, $fContent) = HttpUtils_File($hash);
  return ($fErr, $fContent) if($isFile);
  my $err = HttpUtils_Connect($hash);
  return ($err, undef) if($err);
  
  my ($buf, $ret) = ("", "");
  $hash->{conn}->timeout($hash->{timeout});
  for(;;) {
    my ($rout, $rin) = ('', '');
    vec($rin, $hash->{conn}->fileno(), 1) = 1;
    my $nfound = select($rout=$rin, undef, undef, $hash->{timeout});
    if($nfound <= 0) {
      undef $hash->{conn};
      return ("$hash->{displayurl}: Select timeout/error: $!", undef);
    }

    my $len = sysread($hash->{conn},$buf,65536);
    last if(!defined($len) || $len <= 0);
    $ret .= $buf;
    last if(HttpUtils_DataComplete($ret));
  }
  return HttpUtils_ParseAnswer($hash, $ret);
}

# Deprecated, use GetFileFromURL/GetFileFromURLQuiet
sub
CustomGetFileFromURL($$@)
{
  my ($hideurl, $url, $timeout, $data, $noshutdown, $loglevel) = @_;
  $loglevel = 4 if(!defined($loglevel));
  my $hash = { hideurl   => $hideurl,
               url       => $url,
               timeout   => $timeout,
               data      => $data,
               noshutdown=> $noshutdown,
               loglevel  => $loglevel,
             };
  my ($err, $ret) = HttpUtils_BlockingGet($hash);
  if($err) {
    Log3 undef, $hash->{loglevel}, "CustomGetFileFromURL $err";
    return undef;
  }
  return $ret;
}


##################
# Parameter: $url, $timeout, $data, $noshutdown, $loglevel
# - if data (which is urlEncoded) is set, then a POST is performed, else a GET.
# - noshutdown must be set e.g. if calling the Fritz!Box Webserver
sub
GetFileFromURL($@)
{
  my ($url, @a)= @_;
  return CustomGetFileFromURL(0, $url, @a);
}

##################
# Same as GetFileFromURL, but the url is not displayed in the log.
sub
GetFileFromURLQuiet($@)
{
  my ($url, @a)= @_;
  return CustomGetFileFromURL(1, $url, @a);
}

sub
GetHttpFile($$)
{
  my ($host,$file) = @_;
  return GetFileFromURL("http://$host$file");
}

1;
