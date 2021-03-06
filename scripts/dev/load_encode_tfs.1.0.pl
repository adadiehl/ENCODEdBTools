#!/usr/bin/perl

# Load ChIP-Seq records for a given species and cell type from a .csv flat
# file generated by get_encode_tfs.pl into the ChIPDB database.

use strict;
use warnings;
use DBI;

my $usage =
"\nload_encode_tfs.pl <input.csv>

Loads transcription factor ChIP-seq experiment records previously retrieved
from the ENCODE repository at https://www.encodeproject.org by
get_encode_tfs.pl. Comma-separated values in <input.csv> are read in and
loaded into the database, unless an identical value already exists.

ARGUMENTS:\n
<input.csv> -- A .csv file generated by get_encode_tfs.pl\n";

if ($#ARGV < 0) {
    die "$usage\n";
}

# Connect to the database (server must be running!)
my $dsn = "DBI:mysql:ChIPDB";
my $username = "root";
my $password = '';
my $dbh = DBI->connect($dsn, $username, $password);

my $infile = $ARGV[0];

open INFILE, $infile || die "Cannot read $infile: $!\n";

my $i = 1;
while (<INFILE>) {

    chomp;
    my @strvals = split(',', $_);

    my $species = $strvals[0];
    my $cell = $strvals[1];
    my $factor = $strvals[2];
    my $author = $strvals[3];
    my $affiliation = $strvals[4];
    my $project = $strvals[5];
    my $url = $strvals[6];

    # Check for existing records for species, factor, cell, author and project,
    # inserting any records we need and/or storing values as we go along.
    my @fields;
    my @values;

    # Species
    $species = &get_id_wrapper($dbh, "species", "sname", $species, 0, 0);
#    print STDERR "Species: $species\n";

    # Factor
    # Currently this does NOT check for species -- allows this field in the
    # DB to default to 4: "NULL SPECIES".
    $factor = &get_id_wrapper($dbh, "factors", "fname", $factor, 0, 0);
#    print STDERR "Factor: $factor\n";

    # Cell
    @fields = ("cname","species");
    @values = ($cell,$species);
    $cell = &get_id_wrapper($dbh, "cells", "NULL", 0, \@fields, \@values);
#    print STDERR "Cell: $cell\n";

    # Project
    $project = &get_id_wrapper($dbh, "projects","project", $project, 0, 0);
#    print STDERR "Project: $project\n";

    # Author
    @fields = ("author","affiliation");
    @values = ($author, $affiliation);
    $author = &get_id_wrapper($dbh, "authors","NULL", 0, \@fields, \@values);
#    print STDERR "Author: $author\n";

    # Now that we have all the information we need, build an experiment row,
    # double-check that it does not already exist and create a new one if not.
    @fields = ("species_idspecies", "cells_idcells", "authors_idauthors",
	       "projects_idprojects", "factors_idfactors", "url");
    @values = ($species, $cell, $author, $project, $factor, $url);

    # Check for existing row
    my $experiment = &check_if_exists($dbh, "experiments", 0, \@fields,
				      \@values);
    if ($experiment != 0) {
	print STDERR "Existing record found for experiment at row $i of input file.\n";
    } else {
	$experiment = &insert_row($dbh, "experiments", \@fields, \@values);
    }
	
	$i++;
}


sub insert_row{
    # Insert a row with given fields and values into the given table. Returns
    # a statement handle reference to the resulting row.

    my $dbh = $_[0];
    my $table = $_[1];
    my @fields = @{$_[2]};
    my @values = @{$_[3]};

    my $fields_str = join('`,`', @fields);
    $fields_str = '`' . $fields_str . '`';

    my $vals_str = join("','", @values);
    $vals_str= "'" . $vals_str . "'";

    my $statement = "INSERT INTO " .
	            $table .
		    "($fields_str)" .
		    " VALUES($vals_str);";

#    print STDERR "$statement\n";

    my $sth = $dbh->prepare($statement);
    $sth->execute();

    my $retval = &check_if_exists($dbh, $table, 0, \@fields, \@values);
    return $retval;
}

sub check_if_exists{
    # Run a query against the database for row(s) matching the supplied fields
    # and values. Returns 0 if no rows found or a pointer to a statement handle
    # object if row(s) are found.

    my $dbh = $_[0];
    my $table = $_[1];  
    my $columns = $_[2];  # Optional array of columns to select. Set to 0 if
	                   # not using, array pointer to enable.
    my $fields = $_[3]; # Optional array of fields to check against values.
                           # Set to 0 if not being used, supply pointer to
                           # array to enable.
    my $values = $_[4]; # Optional array of values for fields given above. Set
                           # in same manner as $fields.

    my $cols_str = '*';
    if ($columns != 0) {
	$cols_str = join(',', @$columns);
    }

    my $statement = "SELECT $cols_str FROM $table";

#    print STDERR "$statement\n";

    if ($fields != 0) {

	$statement = $statement . " WHERE ";

	if ($#{$values} != $#{$fields}) {
	    print STDERR "WARNING: fields and values arrays must be of matching length!\n";
	}

	my $i = 0;
	while ($i < ($#{$fields} + 1)) {
	    if ($i > 0 && $i <= $#{$fields}) {
		$statement = $statement . " AND ";
	    }
	    my $clause = ${$fields}[$i] . '="' . ${$values}[$i] . '"';
	    $statement = $statement . $clause;
	    $i++;
	}
    }
    
    $statement = $statement . ';';

#    print STDERR "$statement\n";

    my $sth = $dbh->prepare($statement);
    $sth->execute();

#    while (my @row = $sth->fetchrow_array()) {
#	print "@row\n";
#    }

    if ($sth->rows() > 0) {
	return $sth;
    } else {
	return 0;
    }

}

sub process_results{
    # Pull out and the id* from a table row.
    my $result = $_[0];  # Statement handle object containing result
    # $fields and $values are used only to make errors/warnings easily readable
    my $fields = $_[1];
    my $values = $_[2];

    if ($result->rows() > 1) {
            print STDERR "WARNING: More than one result found for fields @$fields and values @$values. Only the first result will be used!\n";
    }

    my @row= $result->fetchrow_array();
    return $row[0];
    
}

sub get_id_wrapper{
    # Check for a given record in a given field and return the result, calling
    # the insert function if needed, and return the primary key id.
    my $dbh = $_[0];
    my $table = $_[1];
    my $field = $_[2];
    my $value = $_[3];
    # Pointers to pre-built fields and values arrays, used if multiple fields
    # need to be checked/set. Set to 0 to ignore.
    my $fields_mul = $_[4];
    my $vals_mul = $_[5];

    my @fields;
    my @values;
    if ($fields_mul != 0) {
	@fields = @$fields_mul;
	@values = @$vals_mul;
    } else {
	@fields = ($field);
	@values = ($value);
    }

    my $result = &check_if_exists($dbh, $table, 0, \@fields, \@values);

    my $retval;
    # Currently does not check validity of results. Need to fix this in future.
    if ($result != 0) {
	$retval = &process_results($result, \@fields, \@values);
    } else {
	# Need to insert a record.
	$result = &insert_row($dbh, $table, \@fields, \@values);
	$retval = &process_results($result, \@fields, \@values);
    }

    return $retval;
}
