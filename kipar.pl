#!/usr/bin/perl

##############################
## pragmas & encoding setup

use strict;
use warnings;

use utf8; # Process strings within this script as utf-8
binmode(STDOUT, ":utf8"); # write to STDOUT as utf-8

##############################
## Variables

my $outfolder = "/home/bo/n/kipar";

my $outfd; # file descriptor for outfile
my $outfile; # temp storage for book file we're writing to

my $tempfd; # file descriptor for tempfile
my $tempfile; # backup copy of outfile

my $kb; # keyboard file descriptor
my $kbinput; # temp storage for data from above

my $indexfd; # index file descriptor
my $indexfile = "$outfolder/.index.txt"; # index filename

my %tr; # index TRanslator

# temp storage
my ($rawtitle, $title, $author, $key, $type, $loc, $page, $content, $num) = '';
my $state;

##############################
## loadIndex: parse .index.txt to generate %tr
## %tr has a list of keys which are each a raw title
## each key maps to a cleaner/simplified title and author

sub loadIndex {

  my %output = (); # translation hash
  my @index; # temp storage for index data
  my $state = 1; # 0-raw, 1-title, 2-authors, 3-restart & raw
  my ($rawtitle, $title, $author) = '';

  # Create an empty index file if one doesn't already exist
  unless ( -e $indexfile) {
    open($indexfd, "> $indexfile") or die "Error: couldn't open $indexfile. $!\n";
    print $indexfd "\n";
    close($indexfd) or die "Error: couldn't close '$indexfile' $!\n";
  }

  open($indexfd, "< $indexfile") or die "Error: couldn't open '$indexfile' $!\n";
  @index = <$indexfd>;
  close($indexfd) or die "Error: couldn't close '$indexfile' $!\n";

  foreach (@index) {

    s/[\s]*$//g; # remove trailing whitespace
    s/^[\xef\xbb\xbf]*//g; # remove leading BOM
  
    if ($_ eq '') { next; }                # skip empty rows  
    elsif ($state == 1) { $rawtitle = $_; } # first line is the raw title aka hash key
    elsif ($state == 2) { $title = $_; }    # second line is the clean title
    elsif ($state == 3) { $author = $_;     # third line is the clean author

      # at the third line, it's time to save the data we've gathered
      $output{$rawtitle} = {title => $title, author => $author};
      # and reset in preparation for the next index entry
      $rawtitle = ""; $title = "", $author = ""; $state = 0;
    }
    $state += 1;
  }
  return %output;
}
%tr = loadIndex();

# # debug index: print all %tr keys and values
# foreach (sort keys %tr) {
#   print "'$_' : '$tr{$_}->{'title'}' by '$tr{$_}->{'author'}'\n";
# }
# exit;

##############################
## Read My Clippings from stdin

# reset temp storage
($rawtitle, $title, $author, $key, $type, $loc, $page, $content, $num) = '';
$state = 1; # state: 1-title/author, 2-type/location/date, 3-highlight/note

while (<>) {

  ##############################
  ## line cleanup

  s/[\s]*$//g; # remove trailing whitespace
  s/^[\xef\xbb\xbf]*//g; # remove leading BOM

  if ($_ eq '') { next; } # ignore empty lines

  ##############################
  ## Divider Line: Write out our current data and reset variables

  if ($_ eq "==========") { 

    $outfile = lc "$outfolder/$title.txt";
    $outfile =~ s/\s/-/g;

    # print "GOT\ntitle: $title\nauthor: $author\ntype: $type\nloc: $loc\npage: $page\ncontent: $content\n\n";

    ##############################
    ## Add this content to an existing file

    if ( -e $outfile) {

      # read file until we hit
      open($outfd, "< $outfile") or die "Error: couldn't open $outfile. $!\n";

      while (<$outfd>) {
        if (/\s((?:pg)|(?:loc))\s(\d+)\s-\s(.*)/) {
          $num = ($1 eq "pg") ? $page : $loc;

          if ($2 == $num && $3 eq $content) {
            print "duplicate detected!\n";
            last;
          } elsif ($2 <= $num) {
            print "new info at $num comes after $2\n";
          } else {
            print "new info at $num goes here: $2\n";
          }

        }
      }

      close($outfd) or die "Error: couldn't close $outfile. $!\n";

    ##############################
    ## Create a new file and initialize it with this content

    } else {
      # initialize a file for this new book
      open($outfd, "> $outfile") or die "Error: couldn't open $outfile. $!\n";

      # Add the title & author to the file header
      print $outfd "______________________________\n\n";
      print $outfd "  $title\n  by $author";
      print $outfd "\n______________________________\n\n";

      # Add this file's first piece of content
      if ($page ne "") { print $outfd " pg $page - $content\n\n"; }
      else { print $outfd " loc $loc - $content\n\n"; }  
      close($outfd) or die "Error: couldn't close $outfile. $!\n";
    }

    ##############################
    ## Reset in preparation for the next piece of content

    ($rawtitle, $title, $author, $key, $type, $loc, $page, $content) = "";
    $state = 0; 
  }

  ##############################
  ## 1st Line: Title & Author
  elsif ($state == 1) {

    # extract the title and maybe the author
    if (/^(.*)\((.*)\)\s*$/) { 
      $key = $1; $author = $2;
      $key =~ s/[\s]*$//;
    } else {
      $key = $_; $author = "";
    }

    ##############################
    ## Old book? Replace extracted title/author w data from Index

    if (exists $tr{$key}) {
      $author = $tr{$key}->{'author'};
      $title = $tr{$key}->{'title'};
      # print "Fetched from index: '$title' by '$author'\n";
    }

    ##############################
    ## New book? Add a new entry to our index
    else {

      print "New book: '$key' by '$author'\n";
      open($kb, "< /dev/tty") or die "Error: couldn't open keyboard. $!\n";

      # Ask the user what the TITLE of this book should be displayed as
      print "Display title: "; chomp($kbinput = <$kb>);
      # set title to input unless the input is empty (in which case use default)
      if ($kbinput ne '') { $title = $kbinput; }
      else { $title = $key; }

      # Ask the user what the AUTHOR of this book should be displayed as
      print "Display author: "; chomp($kbinput = <$kb>);
      # set author to input unless the input is empty (in which case use default)
      if ($kbinput ne '') { $author = $kbinput; }

      close($kb) or die "Error: couldn't close keyboard. $!\n";

      # Save this info to our index
      open($indexfd, ">> $indexfile") or die "Error: couldn't open '$indexfile' $!\n";
      print $indexfd "\n$key\n$title\n$author\n";
      close($indexfd) or die "Error: couldn't close '$indexfile' $!\n";

      %tr = loadIndex();

    }
  }

  ##############################
  ## 2nd Line: Type & Location & Date
  elsif ($state == 2) {

    # Get Type
    if (/^-\sYour\s((?:Highlight)|(?:Note)|(?:Bookmark))/) {
      $type = $1; # print "type: $type\n";
    } else {
      die "Error: could not get type for: '$_'\n";
    }  

    # Get Page
    if (/page\s([\d]+)/) {
      $page = $1; # print "page: $page\n";
    } else {
      $page = ""; # print "no page..\n";
    }

    # Get Location
    if (/Location\s([\d]+)/) {
      $loc = $1; # print "location: $loc\n";
    } else {
      $loc = ""; # print "no location..\n";
    }

  }

  ##############################
  ## 3rd line: Note/Highlight Content
  elsif ($state == 3) { $content = $_; }

  ##############################
  ## More than 3 lines or less than 1: something's wrong
  else { die "Error: invalid state: $state on line '$_'\n"; }

  ##############################
  ## Increment state after parsing each line
  $state += 1;

}