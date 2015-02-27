#!/usr/bin/perl

# Retrieve ChIP-Seq records for a given species and cell type from the
# ENCODE portal and store records as a .csv flat file for loading into the
# ChIPDB.

use strict;
use warnings;

# ENCODE output is in JSON format
use JSON;

use WWW::Mechanize;
use IO::Socket::SSL;

my $usage =
"\nget_encode_tfs.pl <species> <cell line>

Retrieves transcription factor ChIP-seq experiment records from the ENCODE
repository at https://www.encodeproject.org. Writes output to STDOUT as
comma-separated values, with each experiment on a new line.

ARGUMENTS:\n
<species> -- Two-word species name. Must be quoted and must be a species
\trecognized by the ENCODE portal!\n
<cell line> -- Name of the cell line to retrieve experiments for. Must be a
\trecognized cell line!\n";

if (($#ARGV + 1) < 2) {
    die "$usage\n";
}

my $species = $ARGV[0]; # Must be a format recognized by ENCODE, e.g., "Homo sapiens"
my $cell = $ARGV[1];

my $URL = 'http://www.encodeproject.org/search/?searchTerm=' .
    $cell .
    '&type=experiment&assay_term_name=ChIP-seq&replicates.library.biosample.donor.organism.scientific_name=' . 
    $species .
    '&target.investigated_as=transcription factor&limit=all&format=json';

my $mech = WWW::Mechanize->new(
    ssl_opts => {
        verify_hostname => 0,
	# Quick and dirty way to avoid errors about missing certificates. This
	# should probably be fixed properly at some point!
    },
    );

$mech->get( $URL );

# Content of the page, in JSON format.
my $content = $mech->content();

# print "$content\n";

# Parse the JSON to get the values we need...
my $json = decode_json($content);

#my @keys = keys %$json;

#foreach my $key (@keys) {
#    print "$key:\n${$json}{$key}\n\n";
#}

print STDERR "${$json}{notification}: ${$json}{total} results found.\n\n";

foreach my $row (@{${$json}{'@graph'}}) {

#    print "$row\n";

    # Each row of the array contains a hash reference.

    my %experiment = %{$row};

    my $project = ${$experiment{award}}{project};
    my $factor = ${$experiment{target}}{label};
    my $author_str = ${$experiment{lab}}{title};
    my @tmp = split /\,/, $author_str;
    $tmp[1] =~ s/ //g;
    my $author = $tmp[0];
    my $institution = $tmp[1];
    my $url = $experiment{accession};
    
    # pad out the url with the complete experiment url...
    $url = "https://www.encodeproject.org/experiments/" . $url;


    # Print the complete row to STDOUT as a csv row
    my $out_str = join(',', $species, $cell, $factor, $author, $institution,
		       $project, $url);

    print "$out_str\n";
}


