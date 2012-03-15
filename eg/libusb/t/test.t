#!/usr/bin/env perl
$|=1;

use strict;
use warnings;
use Devel::Peek;

use LibUSB;

my $ctx_p = LibUSB::libusb_context_Pointer->__allocate;
my $ctx_pp  = $ctx_p->__enreference;

# print "ctx_p, before init: \n",
# Dump($ctx_p);

# print "ctx_pp, before init: \n";
# Dump($ctx_pp);

my $start = LibUSB::libusb_init($ctx_pp);
# print "Started: $start\n";

# print "ctx_pp, after init: \n";
# Dump($ctx_pp);

# print "ctx_p, after init: \n",
# Dump($ctx_p);

LibUSB::libusb_set_debug($ctx_p, 3);

my $dev_pp = LibUSB::libusb_device_Pointer_Pointer->__allocate;

#my $dev_p = bless(\do {0xDEADBEEE}, "LibUSB::libusb_device_Pointer_Pointer");
my $dev_ppp = $dev_pp->__enreference;
my $count = LibUSB::libusb_get_device_list($ctx_p, $dev_ppp);

print STDERR "Count devs: $count\n";
my $dev = $dev_ppp->__dereference->__dereference;
#my $desc = LibUSB::struct_libusb_device_descriptor->__allocate;
#my $r = LibUSB::libusb_get_device_descriptor($dev, $desc->__enreference);
#print $r;
