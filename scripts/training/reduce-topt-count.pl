#!/usr/bin/env perl

# given a moses.ini, filter the phrase tables to contain
# only ttable-limit options per source phrase
#
# outputs new phrase tables and updated moses.ini into targetdir
#
# usage: reduce-topt-count.pl moses.ini targetdir

use strict;
use warnings;
use File::Basename;
use File::Path;
use POSIX;
use List::Util qw( min sum );

my ($ini_file, $targetdir) = @ARGV;

if (! defined $targetdir) {
  die "usage: reduce-topt-count.pl moses.ini targetdir\n"
}

my %ttables;
my $ini_hdl = my_open($ini_file);
my $outini_hdl = my_save("$targetdir/moses.ini");

my $section = "";

my %section_handlers = (
  'ttable-file' => read_ttable_file(),
  'ttable-limit' => read_ttable_limit(),
  'weight-t' => read_weight_t()
);

# print header for updated moses.ini
my $timestamp = POSIX::strftime("%m/%d/%Y %H:%M:%S", localtime);
print $outini_hdl <<"END";
# Generated by reduce-topt-count.pl at $timestamp
# Original file: $ini_file

END

# load original moses.ini & generate new moses.ini
while (<$ini_hdl>) {
  chomp(my $line = $_);
  my $do_print = 1;
  if ($line =~ m/^\s*#/ || $line =~ m/^\s*$/) {
    #ignore empty and commented lines
  } elsif ($line =~ m/^\[(.*)\]/) {
    $section = $1; # start of a new section
  } else {
    if (defined $section_handlers{$section}) {
      # call appropriate section handler;
      # handlers are also responsible for printing out
      # (possibly modified) line into new moses.ini
      $do_print = 0;
      $section_handlers{$section}->($line, $outini_hdl);
    }
  }

  if ($do_print) {
    print $outini_hdl "$line\n";
  }
}
close $outini_hdl;

# write filtered phrase tables
for my $ttable (keys %ttables) {
  filter_table($ttables{$ttable});
}

# filter phrase tables

## subroutines

sub read_ttable_file
{
  my $ttable_id = 0;
  return sub {
    my ($line, $outhdl) = @_;
    if ($line !~ m/^(\d+) ([\d\,\-]+) ([\d\,\-]+) (\d+) (\S+)$/) {
      die "Format not recognized: $line";
    }
    my ($type, $srcfacts, $tgtfacts, $numscores, $file) = ($1, $2, $3, $4, $5);
    if ($type != 0) {
      die "Cannot work with ttables of type $type";
    }
    $ttables{$ttable_id} = {
      file => $file,
      scores => $numscores
    };

    print $outhdl
      "$type $srcfacts $tgtfacts $numscores $targetdir/", basename($file), "\n";
    $ttable_id++;
  }
}

sub read_ttable_limit
{
  my $ttable_id = 0;
  return sub {
    my ($line, $outhdl) = @_;
    $ttables{$ttable_id}->{limit} = $line;
    print $outhdl "$line\n";
    $ttable_id++;
  }
}

sub read_weight_t
{
  my $weight_idx = 0;
  my $ttable_id = 0;
  return sub {
    my ($line, $outhdl) = @_;
    if ($ttables{$ttable_id}->{scores} == $weight_idx) {
      $weight_idx = 0;
      $ttable_id++;
    }
    push @{ $ttables{$ttable_id}->{weights} }, $line;
    print $outhdl "$line\n";
    $weight_idx++;
  }
}

sub filter_table
{
  my $ttable = shift;
  my $in = my_open($ttable->{file});
  my $out = my_save($targetdir . "/" . basename($ttable->{file}));
  my $limit = $ttable->{limit};
  my @weights = @{ $ttable->{weights} };

  print STDERR "Filtering ", $ttable->{file}, ", using limit $limit\n";
  my $kept = 0;
  my $total = 0;

  my $src_phrase = "";
  my @tgt_phrases;
  while (<$in>) {
    chomp(my $line = $_);
    $total++;
    print STDERR '.' if $total % 1000 == 0;
    my @cols = split / \|\|\| /, $line;
    if ($cols[0] ne $src_phrase) {
      my @sorted = sort { $b->{score} <=> $a->{score} } @tgt_phrases;
      for my $phrase (@sorted[0 .. min($#sorted, $limit - 1)]) {
        $kept++;
        print $out $phrase->{str}, "\n";
      }
      $src_phrase = $cols[0];
      @tgt_phrases = ();
    }
    my @scores = split ' ', $cols[2];
    push @tgt_phrases, {
      str => $line,
      score => sum(map { $weights[$_] * log $scores[$_] } (0 .. $#weights))
    };
  }
  printf STDERR "Finished, kept %d%% of phrases\n", $kept / $total * 100;
  close $in;
  close $out;
}

sub my_open {
  my $f = shift;
  die "Not found: $f" if ! -e $f;

  my $opn;
  my $hdl;
  my $ft = `file $f`;
  # file might not recognize some files!
  if ($f =~ /\.gz$/ || $ft =~ /gzip compressed data/) {
    $opn = "zcat $f |";
  } elsif ($f =~ /\.bz2$/ || $ft =~ /bzip2 compressed data/) {
    $opn = "bzcat $f |";
  } else {
    $opn = "$f";
  }
  open $hdl, $opn or die "Can't open '$opn': $!";
  binmode $hdl, ":utf8";
  return $hdl;
}

sub my_save {
  my $f = shift;
  if ($f eq "-") {
    binmode(STDOUT, ":utf8");
    return *STDOUT;
  }

  my $opn;
  my $hdl;
  # file might not recognize some files!
  if ($f =~ /\.gz$/) {
    $opn = "| gzip -c > '$f'";
  } elsif ($f =~ /\.bz2$/) {
    $opn = "| bzip2 > '$f'";
  } else {
    $opn = ">$f";
  }
  mkpath( dirname($f) );
  open $hdl, $opn or die "Can't write to '$opn': $!";
  binmode $hdl, ":utf8";
  return $hdl;
}

