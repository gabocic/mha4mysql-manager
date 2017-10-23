#!/usr/bin/env perl

#  Copyright (C) 2011 DeNA Co.,Ltd.
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#  Foundation, Inc.,
#  51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

## Note: This is a sample script and is not complete. Modify the script based on your environment.

use strict;
use warnings FATAL => 'all';

use Getopt::Long;
use MHA::DBHelper;

my $bash_error;

my (
  $command,        $ssh_user,         $orig_master_host,
  $orig_master_ip, $orig_master_port, $new_master_host,
  $new_master_ip,  $new_master_port,  $new_master_user,
  $new_master_password
);
GetOptions(
  'command=s'             => \$command,
  'ssh_user=s'            => \$ssh_user,
  'orig_master_host=s'    => \$orig_master_host,
  'orig_master_ip=s'      => \$orig_master_ip,
  'orig_master_port=i'    => \$orig_master_port,
  'new_master_host=s'     => \$new_master_host,
  'new_master_ip=s'       => \$new_master_ip,
  'new_master_port=i'     => \$new_master_port,
  'new_master_user=s'     => \$new_master_user,
  'new_master_password=s' => \$new_master_password
);

exit &main();

sub main {
  if ( $command eq "stop" || $command eq "stopssh" ) {

    # $orig_master_host, $orig_master_ip, $orig_master_port are passed.
    # If you manage master ip address at global catalog database,
    # invalidate orig_master_ip here.
    my $exit_code = 1;
    eval {
	$bash_error=`/opt/mha_software/scripts/vipmanager_mt.sh stop -h $orig_master_ip `
    };
    if ($bash_error) {
      warn "Got Error: $bash_error\n";
      exit $exit_code;
    }
    exit 0;
  }
  elsif ( $command eq "start" ) {

    # all arguments are passed.
    # If you manage master ip address at global catalog database,
    # activate new_master_ip here.
    # You can also grant write access (create user, set read_only=0, etc) here.
    my $exit_code = 10;
    eval {
      my $new_master_handler = new MHA::DBHelper();

      # args: hostname, port, user, password, raise_error_or_not
      $new_master_handler->connect( $new_master_ip, $new_master_port,
        $new_master_user, $new_master_password, 1 );

      ## Set read_only=0 on the new master
      $new_master_handler->disable_log_bin_local();
      print "Set read_only=0 on the new master.\n";
      $new_master_handler->disable_read_only();

      ## Creating an app user on the new master
      #print "Creating app user on the new master..\n";
      #FIXME_xxx_create_user( $new_master_handler->{dbh} );
      $new_master_handler->enable_log_bin_local();
      $new_master_handler->disconnect();
    };
	if($@)
	{
		warn $@;
		print "****** Exit before Starting VIP **************";
		# If you want to continue failover, exit 10.
		exit $exit_code;
    }
      ## Update master ip on the catalog database, etc
	  $bash_error="";
      $bash_error = `/opt/mha_software/scripts/vipmanager_mt.sh start -h $new_master_ip `;
	  # print  "/opt/mha_software/scripts/vipmanager_mt.sh start -h $new_master_ip\n AAA $bash_error AA \n";
	if ($bash_error) {
	warn $bash_error;
      # If you want to continue failover, exit 10.
      exit $exit_code;
    }
	else{
		exit 0;
	}
    exit $exit_code;
  }
  elsif ( $command eq "status" ) {
    my $exit_code = 1;
	
	# print "/opt/mha_software/scripts/vipmanager_mt.sh check -h $orig_master_ip ";
    eval {
      $bash_error= `/opt/mha_software/scripts/vipmanager_mt.sh check -h $orig_master_ip `
    }; 
    if ($bash_error) { 
      warn "Got Error: $bash_error\n";
      exit $exit_code;
    }
    exit 0;
  }
  else {
    &usage();
    exit 1;
  }
}

sub usage {
  print
"Usage: master_ip_failover --command=start|stop|stopssh|status --orig_master_host=host --orig_master_ip=ip --orig_master_port=port --new_master_host=host --new_master_ip=ip --new_master_port=port\n";
}

