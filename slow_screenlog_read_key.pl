#!/usr/bin/perl -w

$| = 1;

use Term::ReadKey;
use Time::HiRes qw(time);

my ($delay_ms, $delay_seconds);
set_delay(400);


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

# enable key press detection.. 
ReadMode('cbreak');
# run ReadMode('restore') befor exiting programm to return into functional terminal with keyboard echo..

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
            process_key_input();
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

sub process_key_input {
    my $entry_time = time();
    my $exit_time  = $entry_time + $delay_seconds;

    my $paused = 0;

    while (time() < $exit_time || $paused){
       my $key = ReadKey($delay_seconds); 
       if (defined($key)){
          # move cursor to display message at fixed position, clear area before writing new message
          print "\x1b[s";
          print "\x1b[40;0f";
          print "                                                   ";
          print "\x1b[40;0f";
          print "$key pressed\n";
          print "\x1b[u";

          if ($key eq " "){
             if ($paused){
               $paused = 0;
             } else {
               $paused = 1;
             }
          } elsif ($key eq "q"){
             # exit programm
             print "\x1b[42;0f";
             ReadMode('restore');
             exit;
          } elsif ($key eq "["){
            my $special_key = ReadKey($delay_seconds); 
            if (defined($special_key)){
               my $msg = "";
               if ($special_key eq "A"){  
                 $msg = "A cursor up";
                 go_faster();
               } elsif ($special_key eq "B"){  
                 $msg = "B cursor down";
                 slow_down();
               } elsif ($special_key eq "C"){  
                 $msg = "C cursor forward";
                 move_forward();
                 last;
               } elsif ($special_key eq "D"){  
                 $msg = "D cursor back";
                 move_backwards();
               }
      
               # move cursor to display message at fixed position, clear area before writing new message
               print "\x1b[s";
               print "\x1b[41;0f";
               print "                                                   ";
               print "\x1b[41;0f";
               print "special key.. $msg\n";
               print "\x1b[u";
            }
          } else {
             print "\x1b[s";
             print "\x1b[41;0f";
             print "                                                   ";
             print "\x1b[41;0f";
             print "\x1b[u";
          }
       }

    }
}

ReadMode('restore');

sub reinit_registers {
   $buf             = "";
   $buf_leftovers   = "";
   $prev_screen_pos = 0;
   $frame_buffer    = "";
   $bytes_displayed = 0;
}

sub set_delay {
   $delay_ms      = shift;
   $delay_seconds = $delay_ms * 0.001;
}

sub slow_down {
   if ($delay_ms < 800){
      set_delay($delay_ms + 100);
   } 
}

sub go_faster {
   if ($delay_ms > 110){
      set_delay($delay_ms - 100);
   } 
}

sub move_forward {
   $fast_forward_bytes = $bytes_displayed + 1024 * 10;
}

sub move_backwards {
   # everything must be replayed from the beginning
   # fast forward to previous position 
   $fast_forward_bytes = $bytes_displayed - 1024 * 2;
   reinit_registers();

   seek(SCREENLOG, 0, 0);

   # clear screen
   print "\x1b[2J";
}

