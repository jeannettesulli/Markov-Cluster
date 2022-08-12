#!/usr/bin/perl

# Copyright 2022 Stijn van Dongen

# This program is free software; you can redistribute it and/or modify it
# under the terms of version 3 of the GNU General Public License as published
# by the Free Software Foundation. It should be shipped with MCL in the top
# level directory as the file COPYING.

# Only reads STDIN, which should be the output of clm close in --sl mode.  That
# output encodes the single-linkage join order of a tree.  The script further
# requires a prefix for file output and a list of resolution sizes.
#
# The output is a list of flat clusterings, one for each resolution size.
# These clusterings usually share clusters between them (i.e. clusters do not
# always split at each resolution level), but do form a (not strictly) nesting
# set of clusterings.  Also output is the 'dot' specification of a plot that
# shows the structure of the hierarchy (ignoring clusters below the smallest
# resolution size).  This file can be put through GraphViz dot to obtain the
# plot.
#
# A cluster corresponds to a tree node. The cluster consists of all associated
# leaf nodes below this node. For a given resolution size R each cluster C must
# either be of size at least R without a sub-split below C's tree node into two
# other clusters of size at least R, or C is smaller than R and was split off
# in order to allow another such split to happen elsewhere. In the last case
# C will not have been split any further.
#
# For decreasing resolution sizes, the code descends each node in the tree, as
# long as it finds two independent components below the node that are both of
# size >= resolution.  For each resolution size the internal nodes that encode
# the clustering for that resolution are marked.  After this stage, the
# clusterings for the different resolutions are output, going back up the tree
# from small resolution / fine-grained clusters to larger resolution /
# coarse-grained clusters, and merging or copying clusters from the previous
# stage.

# rcl.sh incorporates rcl-res.pl, see there for comprehensive usage example.
# Use e.g.
#     rcl-res.pl pfx 50 100 200 < sl.join-order
#     mcxload -235-ai pfx50.info -o pfx50.cls

# TODO: detect circular/nonDAG input to prevent memory/forever issues.

use strict;
use warnings;
use List::Util qw(min max);
use Scalar::Util qw(looks_like_number);

$::prefix = shift || die "Need prefix for file names";
die "Need at least one resolution parameter\n" unless @ARGV;
for my $r (@ARGV) {
  die "Resolution check: strange number $r\n" unless looks_like_number($r);
}
@::resolution = sort { $a <=> $b } @ARGV;
$::reslimit = $::resolution[0];
$::resolutiontag = join '-', @::resolution;

@ARGV = ();
%::nodes = ();
$::nodes{dummy}{items} = [];     # used for singletons; see below
$::nodes{dummy}{size}  = 0;      #
$::nodes{dummy}{lss}   = 0;      #

$::L=1;
%::topoftree = ();
print STDERR "-- constructing tree:\n";

my $epsilon = 0.000001;
my $header = <>;
chomp $header;

die "Join order header line not recognised" unless $header =~ /^link.*bobid$/;

while (<>) {

   chomp;
   my @F = split "\t";

   die "Expect 14 elements (have \"@F\")\n" unless @F == 14;
   my ($i, $val, $upname, $ann, $bob, $xcsz, $ycsz, $xycsz, $nedge, $ctr, $lss, $nsg,$annid, $bobid) = @F;
   die "Checks failed on line $.\n" unless
         looks_like_number($xcsz) && looks_like_number($ycsz)
      && looks_like_number($lss) && looks_like_number($nsg);
   print STDERR '.' if $. % 1000 == 1;

                      # leaves have to be introduced into our tree/node listing
   if ($xcsz == 1) {
      $ann =~ /leaf_(\d+)/ || die "Missing leaf (Ann) on line $.\n";
      my $leafid = $1;
      $::nodes{$ann} =
      {  name => $ann
      ,  size =>  1
      ,  items => [ $leafid ]
      ,  ann => "null"
      ,  bob => "null"
      ,  csizes => []
      ,  lss => 0
      ,  nsg => 0
      ,  val => 1000
      } ;
   }
   if ($ycsz == 1) {
      $bob =~ /leaf_(\d+)/ || die "Missing leaf (Bob) on line $.\n";
      my $leafid = $1;
      $::nodes{$bob} =
      {  name => $bob
      ,  size =>  1
      ,  items => [ $leafid ]
      ,  ann => "null"
      ,  bob => "null"
      ,  csizes => []
      ,  lss => 0
      ,  nsg => 0
      ,  val => 1000
      } ;
   }

   # LSS: largest sub split. keep track of the maximum size of the smaller of
   # any pair of nodes below the current node that are not related by
   # descendancy.  Given a node N the max min size of two non-nesting
   # nodes below it is max(mms(desc1), mms(desc2), min(|desc1|, |desc2|)).
   # clm close and rcl-res.pl both compute it - a bit pointless but lets just
   # call it a sanity check.

   # $ann eq $bob is how clm close denotes a singleton in the network - the
   # only type of node that does not participate in a join.
   # A dummy node exists (see above) that has only size, items and lss with none
   # of the other fields set. Currently that node is only accessed when
   # items are picked up in the cluster aggregation step. If code is added
   # and pokes at other attributes they will be undefined and we will know.

   $bob = 'dummy' if $ann eq $bob;
   die "Parent node $upname already exists\n" if defined($::nodes{$upname});

   my $equijoin_report = defined($ENV{RCL_EQUIJOIN}) ? $ENV{RCL_EQUIJOIN} : 0;
   my $equijoin = 0;
   $equijoin = $val + $epsilon >= $::nodes{$ann}{val} && $val + $epsilon >= $::nodes{$bob}{val} unless $upname =~ /^sgl_/;

   my $properjoin = $equijoin ? 0 : 1;
   if ($equijoin && $equijoin_report && $::nodes{$ann}{size} >= $equijoin_report && $::nodes{$bob}{size} >= $equijoin_report) {
      print STDERR "-- equijoin $val $::nodes{$ann}{val} $::nodes{$bob}{val} $::nodes{$ann}{size} $::nodes{$bob}{size}\n";
   }

   $::nodes{$upname} =
   {  name  => $upname
   ,  parent => undef
   ,  size  => $::nodes{$ann}{size} + $::nodes{$bob}{size}
   ,  ann   => $ann
   ,  bob   => $bob
   ,  csizes => [ $::nodes{$ann}{size}, $::nodes{$bob}{size}]
   ,  lss   => max( $::nodes{$ann}{lss}, $::nodes{$bob}{lss}, $properjoin * min($::nodes{$ann}{size}, $::nodes{$bob}{size}))
   ,  nsg   => $nsg
   ,  val   => $val
   } ;

   # clm close outputs a line with ann eq bob for all singleton nodes.
#  print STDERR "LSS error check failed ($ann $bob)\n" if $::nodes{$upname}{lss} != $lss && $ann ne $bob;

   delete($::topoftree{$ann});
   delete($::topoftree{$bob});

   $::topoftree{$upname} = 1;
   $::L++;
}
print STDERR "\n" if $. >= 1000;


if (defined($ENV{RCL_RES_DOT_TREE}) && $ENV{RCL_RES_DOT_TREE} == $::L) {
  open(DOTTREE, ">$::prefix.joindot") || die "Cannot open $::prefix.joindot";
  for my $node
  ( grep { $::nodes{$_}{size} > 1 }
    sort { $::nodes{$b}{val} <=> $::nodes{$a}{val} }
    keys %::nodes
  ) {
    my $val = $::nodes{$node}{val};
    my $ann = $::nodes{$node}{ann};
    my $bob = $::nodes{$node}{bob};
    print DOTTREE "$node\t$::nodes{$node}{ann}\t$val\t$::nodes{$ann}{size}\n";
    print DOTTREE "$node\t$::nodes{$node}{bob}\t$val\t$::nodes{$bob}{size}\n";
  }
  close(DOTTREE);
}

my @inputstack = ( sort { $::nodes{$b}{size} <=> $::nodes{$a}{size} } keys %::topoftree );
my @clustering = ();
my %resolutionstack = ();

print STDERR "-- computing tree nodes for resolution";
 # Start from top of tree(s), so we find the larger-size-resolution nodes
 # first.  inputstack is a set of nodes for which we know that they are
 # higher (or equal) in the tree relative to the nodes that answer our
 # resolution request.  At a resolution step, we can use the answer obtained
 # for the previous step as the new inputstack.
 #
for my $res (sort { $b <=> $a } @::resolution) { print STDERR " .. $res";

  while (@inputstack) {

    my $name = pop @inputstack;
    my $ann  = $::nodes{$name}{ann};
    my $bob  = $::nodes{$name}{bob};
 
    if ($::nodes{$name}{lss} >= $res) {
      push @inputstack, $ann;
      push @inputstack, $bob;
    }
    else {
      push @clustering, $name;
    }
  }

   # make copy, as we re-use clustering as inputstack.
   #
  $resolutionstack{$res} = [ @clustering ];
  @inputstack = @clustering;
  @clustering = ();
}

print STDERR "\n-- collecting clusters for resolution\n";
 # when collecting items, proceed from fine-grained to coarser clusterings,
 # so with low resolution first.
 #
my %maplinks = ();   # collect links for dot plot
my %hasparent = ();
my @datasizes = ();

for my $res (sort { $a <=> $b } @::resolution) { print STDERR " .. $res";

  my $clsstack = $resolutionstack{$res};
  my $datasize = 0;

  local $" = ' ';
  my $fname = "$::prefix.res$res.info";
  open(OUT, ">$fname") || die "Cannot write to $fname";

  for my $name ( sort { $::nodes{$b}{size} <=> $::nodes{$a}{size} } @$clsstack ) {

    my $size = $::nodes{$name}{size};
    my $ival = int(0.5 + $::nodes{$name}{val});
    my @nodestack = ( $name );
    my @items = ();
    $maplinks{$name} = {} unless defined($maplinks{$name});
          # this is to force nodes that are not a parent to exist in the map.

    while (@nodestack) {

      my $nodename = pop(@nodestack);
          # Below items are either cached from a previous more fine-grained clustering
          # or they are leaf nodes
      if (defined($::nodes{$nodename}{items})) {

        push @items, @{$::nodes{$nodename}{items}};

        if ($nodename ne $name && $::nodes{$nodename}{size} >= $::reslimit) {
          $maplinks{$name}{$nodename} = 1;
          $hasparent{$nodename} = 1;
        }
      }
      else {
        push @nodestack, ($::nodes{$nodename}{ann}, $::nodes{$nodename}{bob});
      }
    }
    @items = sort { $a <=> $b } @items;
    $::nodes{$name}{items} = \@items unless defined($::nodes{$name}{items});
 
    my $nitems = @items;
    print STDERR "Error res $res size difference $size / $nitems\n" unless $nitems == $size;
 
    print OUT "$name\t$ival\t$size\t@items\n";
    $datasize += $size;
  }
  push @datasizes, $datasize;
  close(OUT);
}


my $dotname = "$::prefix.hi.$::resolutiontag.resdot";
open(RESDOT, ">$dotname") || die "Cannot open $dotname for writing";

for my $n (sort { $::nodes{$b}{size} <=> $::nodes{$a}{size} } keys %maplinks) {
  my $size = $::nodes{$n}{size};
  my $sum  = 0;
  my $pctloss = "0";
  $sum += $::nodes{$_}{size} for keys %{$maplinks{$n}};
  $pctloss = sprintf("%d", 100 * ($size - $sum) / $size) if $sum;
  print RESDOT "node\t$n\t$::nodes{$n}{val}\t$size\t$pctloss\n";
}
for my $n1 (sort { $::nodes{$b}{size} <=> $::nodes{$a}{size} } keys %maplinks) {
  for my $n2 (sort { $::nodes{$b}{size} <=> $::nodes{$a}{size} } keys %{$maplinks{$n1}} ) {
    print RESDOT "link\t$n1\t$n2\n"; # Could implement filter here
                                     # to avoid printing out the very smallest stuff.
  }
}
close(RESDOT);

my $listname = "$::prefix.hi.$::resolutiontag.txt";
open(RESLIST, ">$listname") || die "Cannot open $listname for writing";
print RESLIST "level\tsize\tjoinval\tpctloss\tnesting\tnodes\n";
   # This output encodes the top-level hierarchy of the RCL clustering,
   # with explicit levels, descendancy encoded in concatenated labels,
   # and all the nodes contained within each cluster.
sub printlistnode {
  my ($level, $nodelist, $ni) = @_;
  my $size = $::nodes{$ni}{size};
  my $ival = int(0.5 + $::nodes{$ni}{val});
  my $sumofchildren = 0;
  return unless $size >= $::reslimit;       # perhaps argumentise.
  $sumofchildren += $::nodes{$_}{size} for keys %{$maplinks{$ni}};
  my $nloss = $sumofchildren ? sprintf("%d", 100 * ($size - $sumofchildren) / $size) : "-";
  my $tag = join('::', (@{$nodelist}, $ni));
  local $" = ' ';
  print RESLIST "$level\t$size\t$ival\t$nloss\t$tag\t@{$::nodes{$ni}{items}}\n";
  for my $nj (sort { $::nodes{$b}{size} <=> $::nodes{$a}{size} } keys %{$maplinks{$ni}} ) {
    printlistnode($level+1, [ @$nodelist, $ni ], $nj);
  }
}

my $toplevelsum = 0;
for (grep { $::nodes{$_}{size} >= $::reslimit && !defined($hasparent{$_}) } keys %maplinks) {
  $toplevelsum += $::nodes{$_}{size};
# print STDERR "$_ $::nodes{$_}{size}\n";
}
my $nloss = $toplevelsum ? sprintf("%d", 100 * ($datasizes[0] - $toplevelsum) / $datasizes[0]) : "-";
print RESLIST "0\t$datasizes[0]\t0\t$nloss\troot\t-\n";

my $level = 1;
for my $n
( sort { $::nodes{$b}{size} <=> $::nodes{$a}{size} }
  grep { !defined($hasparent{$_}) }
  keys %maplinks
)
{   printlistnode(1, [], $n);
}
close(RESLIST);
