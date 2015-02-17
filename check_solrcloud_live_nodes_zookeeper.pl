#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-02-14 20:36:54 +0000 (Sat, 14 Feb 2015)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the number of live SolrCloud servers via ZooKeeper

Thresholds for warning / critical apply to the minimum number of live nodes found in ZooKeeper

See also adjacent plugin check_solrcloud_live_nodes which does the same as this check but directly against the Solr API

Tested on ZooKeeper 3.4.5 and 3.4.6 with SolrCloud 4.x

API / BUGS / Limitations:

Uses the Net::ZooKeeper perl module which leverages the ZooKeeper Client C API. Instructions for installing Net::ZooKeeper are found at https://github.com/harisekhon/nagios-plugins

1. Net::ZooKeeper API is slow, takes 5 seconds to create a connection object per ZooKeeper node specified (before it even tries to connect to ZooKeeper which happenes sub-second). Unfortunately this is a limitation of the Net::ZooKeeper API
2. API segfaults if you try to check the contents of a null znode such as those kept by SolrCloud servers eg. /solr/live_nodes/<hostname>:8983_solr - ie this will occur if you supply the incorrect base znode and it happens to be null
";

$VERSION = "0.1";

use strict;
use warnings;
use IO::Socket;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::ZooKeeper;
use Net::ZooKeeper qw/:DEFAULT :errors :log_levels/;

my $znode = "/live_nodes";
my $base  = "/solr";

%options = (
    %zookeeper_options,
    "b|base=s" => [ \$base, "Base Znode for Solr in ZooKeeper (default: /solr, should be just / for embedded or non-chrooted zookeeper)" ],
    %thresholdoptions,
);
@usage_order = qw/host port user password base random-conn-order session-timeout warning critical/;

get_options();

my @hosts = validate_hosts($host, $port);
$znode = validate_filename($base, 0, "base znode") . $znode;
$znode =~ s/\/+/\//g;
$znode = validate_filename($znode, 0, "live nodes znode");
validate_thresholds(1, 1, { 'simple' => 'lower', 'positive' => 1, 'integer' => 1});

$user     = validate_user($user)         if defined($user);
$password = validate_password($password) if defined($password);

vlog2;
set_timeout();

$status = "UNKNOWN";

connect_zookeepers(@hosts);

check_znode_exists($znode);

$status = "OK";

vlog2 "checking for child znodes / live nodes";
my @child_znodes = $zkh->get_children($znode);
my $live_nodes = scalar @child_znodes;

vlog2 "live nodes:\n\n" . join("\n", sort @child_znodes);
vlog2 "\ntotal live nodes: $live_nodes\n";

plural $live_nodes;
$msg = "$live_nodes live SolrCloud node$plural detected in ZooKeeper";
check_thresholds($live_nodes);
if($verbose){
    $msg .= " [";
    foreach(@child_znodes){
        s/_solr$//;
        $msg .= "$_, ";
    }
    $msg =~ s/, $//;
    $msg .= "]";
}

# The live_nodes znode age doesn't change when live ephemeral child znodes are added / removed

$msg .= " | live_nodes=$live_nodes";
msg_perf_thresholds(0, "lower");

quit $status, $msg;