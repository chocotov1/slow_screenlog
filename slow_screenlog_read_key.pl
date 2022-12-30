#!/usr/bin/perl -w

$| = 1;

use Term::ReadKey;


$delay = 400;

my $screenlog_file;
if (defined($ARGV[0]) && -f $ARGV[0] ){
  $screenlog_file = $ARGV[0]; 
} else {
   die "usage: $0 <filename> <skip_bytes>\n";
}

open (SCREENLOG, $screenlog_file) || die "coudln't open file $screenlog_file: $!\n";

my $fast_forward_bytes = 0;

if (defined($ARGV[1]) && $ARGV[1] =~ /^\d+$/){
   # input is kB
   $fast_forward_bytes = $ARGV[1] * 1024;
}

# escape sequence: ESC[ -> 0x1b 0x5b
# 0x1b: ESC
# 0x5b: [
# 0x30: 0
# 0x3b: ;
#
# https://en.wikipedia.org/wiki/ANSI_escape_code
# CSI (Control Sequence Introducer) sequences
#
# hide cursor:
# mike@penguin:~/slowcat_testing$ echo -e "\x1b[?25l"
# show cursor:
# mike@penguin:~/slowcat_testing$ echo -e "\x1b[?25h"

my $buf             = "";
my $buf_leftovers   = "";
my $prev_screen_pos = 0;
my $frame_buffer    = "";
my $bytes_displayed = 0;


ReadMode('cbreak');

#while (read(STDIN,$buf,1000)){
while (read(SCREENLOG,$buf,1000)){
   $buf = $buf_leftovers . $buf; 
   #print $buf;

   # todo: match vanaf begin -> doorlopend buffer verwerken -> gelezen deel verwijderen
   #while ($buf =~ /\x1b\x5b(\d+?);(\d+)/g){
   #while ($buf =~ /\x1b\x5b(\d+?);(\d+?)([Hf])/sg){
   #while ($buf =~ /^(.*?)(\x1b\[(\d+?);(\d+?)([Hf]))/sg){
   while ($buf =~ /^((.*?)(\x1b\[(\d+?);(\d+?)([Hf])))/s){
      #print $1;
      $frame_buffer .= $1;

      my $length_match = length($1);
      my ($row, $col, $type) = ($4, $5, $6);
      my $cur_screen_pos = $row * 1000 + $col; 

      if ($cur_screen_pos < $prev_screen_pos){
         print $frame_buffer;
         $bytes_displayed += length($frame_buffer);
         $frame_buffer     = "";
         
         if ($bytes_displayed > $fast_forward_bytes){
            #select(undef,undef,undef,0.40);
            my $key = ReadKey($delay * 0.001); 
            #todo: move cursor to corner and print
            print "\x1b[s";
            print "\x1b[40;0f";
            print "                                                   ";
            print "\x1b[40;0f";
            print "$key pressed\n" if (defined($key));
            print "\x1b[u";
         }
      }
      $prev_screen_pos = $cur_screen_pos;

      #my ($row, $col, $type) = ($2, $3, $4);
      #print "match: $row;$col$type\n";
      #print "match: $row;$col$type -> $length_match\n";
      #printf("match: %d;%d%s -> %d\n", $row,$col, $type,  $length_match);
      #printf("match: %8s -> %-3d -> %4d\n", "$row;$col$type", $length_match, length($buf));
      # remove matches bytes beginning $buf: 
      $buf = substr($buf, $length_match);      

      #select(undef,undef,undef,0.20);
      #select(undef,undef,undef,0.01);
   }

   #print "=" x 10 . "\n";

   $buf_leftovers = $buf;
}

print $frame_buffer;

