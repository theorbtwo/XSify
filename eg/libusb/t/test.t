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

print "Count devs: $count\n";
my $dev = $dev_ppp->__dereference->__dereference;

my $desc = LibUSB::struct_libusb_device_descriptor->__allocate;
my $desc_p = $desc->__enreference;
my $r = LibUSB::libusb_get_device_descriptor($dev, $desc_p);
# FIXME: Why the hell is this neccessary?  I thought we fixed this?
$desc = $desc_p->__dereference;

print "Result of get_device_descriptor: $r\n";
print "Desc: $desc\n";
print "\$\$desc: $$desc\n";
print " bLength: ", $desc->__get_bLength, "\n";
printf " bDescriptorType: %d\n", $desc->__get_bDescriptorType;
printf " bcdUSB: 0x%x\n", $desc->__get_bcdUSB;
printf " bDeviceClass: 0x%x\n", $desc->__get_bDeviceClass;
printf " bDeviceSubClass: 0x%x\n", $desc->__get_bDeviceProtocol;
printf " bMaxPacketSize0: 0x%x\n", $desc->__get_bMaxPacketSize0;
printf " idVendor: 0x%x\n", $desc->__get_idVendor;

