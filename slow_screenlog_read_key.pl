#!/usr/bin/perl -w

$| = 1;

use Term::ReadKey;
use Time::HiRes qw(time);

my ($delay_ms, $delay_seconds);
set_delay(400);

my $screenlog_file;
if (defined($ARGV[0]) && -f $ARGV[0]){
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
my $marked_position = 0;

my $paused = 0;
my $eof_reached = 0;

# enable key press detection.. 
ReadMode('cbreak');

while (1){
   unless ($eof_reached){
      while (read(SCREENLOG,$buf,1000)){
         $buf = $buf_leftovers . $buf; 
         #print $buf;
      
         while ($buf =~ /^((.*?)(\x1b\[((\d+?);(\d+?))?([Hf])))/s){
            #print $1;
      
            my $add_to_framebuffer = $1;
      
            my $length_match = length($1);
            my ($row, $col, $type) = ($5, $6, $7);
      
            # filter out unwanted sequences from stream before adding to frame buffer:
            # ESC[?2004h / ESC[?2004l: Turn on/off bracketed paste mode. Assumed that it caused trouble but wasn't the case in the end
            # still here as example
            # $add_to_framebuffer =~ s/\x1b\[\?2004[hl]//g;
            #
            # vt100: ESC[?1h -> "Set cursor key to application": cursor controls of this script brake when this printed
            $add_to_framebuffer =~ s/\x1b\[\?1h//g;
            $frame_buffer .= $add_to_framebuffer;
      
            my $cur_screen_pos = 0;
            my $force_update   = 0;
            if (defined($row)){
               # regex matched ESC[H with row and column numbers
               $cur_screen_pos = $row * 1000 + $col; 
            } else {
               # regex matched ESC[H without row and column: cursor moved to position 0;0
               $force_update = 1;
               $row = 0;
               $col = 0;
            }  
            #print "$row -> $col -> $type\n";
            #print "$cur_screen_pos\n";
      
            if ($force_update || $cur_screen_pos < $prev_screen_pos){
               print $frame_buffer;
               $bytes_displayed += length($frame_buffer);
               $frame_buffer     = "";
               
               if ($bytes_displayed > $fast_forward_bytes){
                  process_key_input();
               }
            }
      
            $prev_screen_pos = $cur_screen_pos;
      
            $buf = substr($buf, $length_match);      
         }
      
         $buf_leftovers = $buf;
      }
   
      $eof_reached = 1;

      # print any left over bytes of last page
      print $frame_buffer if ($frame_buffer);
   }

   flash_screen();
   print_message(40, "end of file reached");
   $paused = 1;

   # process_key_input() returns when $paused is no longer set
   process_key_input();
}

sub cleanup_before_exit {
   # ReadMode('restore') to return into functional terminal with keyboard echo..
   ReadMode('restore');
   print "\x1b[?25h"; # display cursor: it might have been turned off in the stream
   print "\x1b[42;0f"; # move cursor down
}

sub process_key_input {
    my $entry_time = time();
    my $exit_time  = $entry_time + $delay_seconds;

    while (time() < $exit_time || $paused){
       my $key = ReadKey($delay_seconds); 
       if (defined($key)){
          print_message(40, "$key pressed");

          if ($key eq " "){
             if ($paused){
               $paused = 0;
             } else {
               $paused = 1;
             }
          } elsif ($key eq "m"){
             $marked_position = $bytes_displayed;
             print_message(40, "marked position $marked_position");
          } elsif ($key eq "n"){
             # load next frame (exiting this loop leads to desired effect)
             last;
          } elsif ($key eq "q"){
             # exit programm
             cleanup_before_exit();
             exit;
          } elsif ($key eq "g"){
             print_message(40, "replaying from beginning");
             select(undef,undef,undef,0.5);
             $fast_forward_bytes = 0;
             $paused = 0;
             replay_from_beginning();
             last;
          } elsif ($key eq "r"){
             if ($marked_position){
                print_message(40, "replaying...");
                select(undef,undef,undef,0.05);
                $fast_forward_bytes = $marked_position;
                replay_from_beginning();
             } else {
                print_message(40, "replay: first mark position with m");
             }

             last;
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
                 # everything must be replayed from the beginning
                 # fast forward to previous position 
                 $fast_forward_bytes = $bytes_displayed - 1024 * 10;
                 replay_from_beginning();
                 last;
               }
      
               print_message(41, "special key.. $msg");
            }
          } else {
             print_message(41, "");
          }
       }

    }
}

sub reinit_registers {
   $buf             = "";
   $buf_leftovers   = "";
   $prev_screen_pos = 0;
   $frame_buffer    = "";
   $bytes_displayed = 0;
   $eof_reached     = 0;
}

sub set_delay {
   $delay_ms      = shift;
   $delay_seconds = $delay_ms * 0.001;
}

sub slow_down {
   if ($delay_ms < 1000){
      set_delay($delay_ms + 100);
   } 
}

sub go_faster {
   if ($delay_ms > 110){
      set_delay($delay_ms - 100);
   } 
}

sub move_forward {
   $fast_forward_bytes = $bytes_displayed + 1024 * 20;
}

sub replay_from_beginning {
   reinit_registers();

   seek(SCREENLOG, 0, 0);

   # clear screen
   print "\x1b[2J";
}

sub print_message {
   # move cursor to display message at fixed position, clear area before writing new message
   my ($line, $msg) = @_;

   print "\x1b[s";
   print "\x1b[$line;0f";
   print "                                                   ";
   print "\x1b[$line;0f";
   print "$msg";
   print "\x1b[u";
}

sub flash_screen {
   print "\x1b[?5h";
   select(undef,undef,undef,0.1);
   print "\x1b[?5l";
}
