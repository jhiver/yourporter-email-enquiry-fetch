#!/usr/bin/perl
use warnings;
use strict;
use Carp;
use Email::MIME;
use File::Basename;
use Net::POP3;
use Data::Dumper;
use Redis;
use JSON;
use Digest::SHA qw(sha256_hex);

use lib qw /. ../;

my $server         = 'mail.gandi.net:995';
my $receiveruname  = 'yourporter@bnblogic.com';
my $password       = '244172FC';
my $attachment_dir = '/tmp';
my $redis = Redis->new(server => 'redis:6379');


# ----------------------------------------------------------------------------
# Check that it's not already running.
# (only one instance at a time)
# ----------------------------------------------------------------------------
sub run_only_once {
  if(-e "/tmp/email.running") {
    print "$0 seems to be running already. Exiting.\n";
    exit(0);
  }
  else {
    open TOUCH, ">/tmp/email.running";
    print TOUCH $$;
    close(TOUCH);
  }
}


# ----------------------------------------------------------------------------
# Connect to the mail box.
# ----------------------------------------------------------------------------
run_only_once();
my $pop = Net::POP3->new($server, SSL => 1) or do { unlink "/tmp/email.running"; die "Couldn't connect to the server.\n\n"; };

my $num_messages = $pop->login( $receiveruname, $password );
defined $num_messages or do { unlink "/tmp/email.running"; die "Connection trouble network password user\n\n"; };

print "got $num_messages new messages\n";


sub extract_sender {
  while (@_) {
    next unless lc(shift(@_)) eq 'from';
    my $res = shift(@_);
    $res = $res->[0] if (ref $res and ref($res) eq 'ARRAY');
    return $res;
  }
  return '';
}


sub extract_reply_to {
  while (@_) {
    next unless lc(shift(@_)) eq 'reply-to';
    my $res = shift(@_);
    $res = $res->[0] if (ref $res and ref($res) eq 'ARRAY');
    return $res;
  }
  return '';
}


sub extract_subject {
  while (@_) {
    next unless lc(shift(@_)) eq 'subject';
    my $res = shift(@_);
    $res = $res->[0] if (ref $res and ref($res) eq 'ARRAY');
    return $res;
  }
  return '';
}


sub check_sender_ok {
  my ($sender) = @_;
  return 1 if $sender =~ /jhiver\@gmail\.com/;
  return 1 if $sender =~ /welcome\@rusty-pelican\.com/;
  return 1 if $sender =~ /hello\@yourporter\.com/;
  return;
}


sub check_message {
  my ($em, $i) = @_;
  unless ($em->{header} and $em->{header}->{headers}) {
    return;
  }
  return 1;
}


sub extract_and_check_sender {
  my ($em, $i) = @_;
  my $sender = extract_sender(@{$em->{header}->{headers}});
  $sender =~ s/.*\<//;
  $sender =~ s/\>.*//;
  unless (check_sender_ok($sender)) {
    print "Sender $sender isn't correct - ignoring";
    return;
  }
  return $sender;
}


# for each message...
for my $i ( 1 .. $num_messages ) {
  my $aref = $pop->get($i);

  unless ($aref) {
    $pop->delete($i);
    next;
  }


  my $em = Email::MIME->new( join '', @$aref );

  print "Deleting POP message $i/$num_messages\n";
  $pop->delete($i);


  # checks that the message looks correct, otherwise skip.
  check_message($em) || do {
    next;
  };

  # checks that the sender looks fine, otherwise skip.
  my $sender  = extract_and_check_sender($em) || do {
    next;
  };

  # checks that the subject looks fine, otherwise skip.
  my $subject = extract_subject(@{$em->{header}->{headers}});
  print "+ processing #{$subject}...\n";
  my $body_raw = $em->body_raw();

  # find check-in date
  my ($checkin) = $body_raw =~ /<td>Check-in:<\/td>.*?<td.*?>(.*?)<\/td>/gism;
  $checkin =~ s/\D//gism;
  my @checkin = $checkin =~ /(....)(..)(..)/;
  $checkin = join '-', @checkin;

  # find check-out date
  my ($checkout) = $body_raw =~ /<td>Check-out:<\/td>.*?<td.*?>(.*?)<\/td>/gism;
  $checkout =~ s/\D//gism;
  my @checkout = $checkout =~ /(....)(..)(..)/;
  $checkout = join '-', @checkout;

  # find listing
  my ($listing) = $body_raw =~ /<td>Listing:<\/td>.*?<td.*?>(.*?)<\/td>/gism;
  $listing = lc($listing);
  $listing =~ s/[^a-z0-9]//gism;

  # find guest name
  my ($guest_name) = $body_raw =~ /<td>Guest Name:<\/td>.*?<td.*?>(.*?)<\/td>/gism;
  $guest_name = lc($guest_name);
  $guest_name =~ s/[^A-Z-a-z ]//gism;

  # find number of guests
  my ($guests) = $body_raw =~ /<td>Adults:<\/td>.*?<td.*?>(.*?)<\/td>/gism;
  $guests = lc($guests);
  $guests =~ s/[^0-9]//gism;

  # find phone
  my ($phone) = $body_raw =~ /<td>Phone:<\/td>.*?<td.*?>(.*?)<\/td>/gism;
  $phone = lc($phone);
  $phone =~ s/[^0-9]//gism;

  # find price
  my ($price) = $body_raw =~ /<td>Total Price:<\/td>.*?<td.*?>(.*?)<\/td>/gism;
  $price = lc($price);
  $price =~ s/[^0-9.]//gism;

  # find email address
  my $email = extract_reply_to(@{$em->{header}->{headers}}) || extract_sender(@{$em->{header}->{headers}});
  $email =~ s/.*\<//;
  $email =~ s/\>.*//;

  my $json = {
    guest_name => "$guest_name",
    checkin => "$checkin",
    checkout => "$checkout",
    listing => "$listing",
    guests => 0 + $guests,
    phone => "+$phone",
    email => "$email"
  };

  $json = encode_json($json);
  my $hash = sha256_hex("$guest_name:$checkin:$checkout:$listing:$guests:$phone:$email");
  my $is_done = $redis->get("seen:$hash");
  if ($is_done) {
    print "already inserted - skipping\n";
  }
  else {
    $redis->setex("seen:$hash", 3600, 1);
    $redis->rpush("yourporter-email-enquiry-fetch", $json);
    print "$json\n";
    print "\n";
  }
  unlink "/tmp/email.running";
  $pop->quit;
}

