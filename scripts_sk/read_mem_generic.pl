#!/usr/bin/perl
use strict;
use warnings;

# ============================================================================
# imem_read.pl - Generic Memory Reader for NetFPGA BRAM
# ============================================================================
# Usage: ./imem_read.pl <start_addr> <num_lines> <dout_reg>
#
# Arguments:
#   start_addr - Starting BRAM address to read from (e.g., 0x00000010 or 16)
#   num_lines  - Number of memory locations to read (e.g., 512)
#   dout_reg   - Data output register address (e.g., 0x2000310)
#
# Example (IMEM with registered output, read 512 lines from address 0):
#   ./imem_read.pl 0x0 512 0x2000310
#
# Example (read 64 lines starting from address 128):
#   ./imem_read.pl 128 64 0x200030C
# ============================================================================

# ============================================================================
# CONSTANTS - Edit these as needed
# ============================================================================
use constant ADDR_REG   => 0x2000304;   # Address input register
use constant OUTPUT_FILE => 'dump_read.hex'; # Output hex dump file
# ============================================================================

# Check command-line arguments
if (@ARGV != 3) {
    print STDERR "ERROR: Incorrect number of arguments!\n\n";
    print STDERR "Usage: $0 <start_addr> <num_lines> <dout_reg>\n\n";
    print STDERR "Arguments:\n";
    print STDERR "  start_addr - Starting BRAM address (hex or decimal, e.g., 0x10 or 16)\n";
    print STDERR "  num_lines  - Number of memory locations to read\n";
    print STDERR "  dout_reg   - Data output register address (hex, e.g., 0x2000310)\n\n";
    print STDERR "Example:\n";
    print STDERR "  $0 0x0 512 0x2000310\n";
    print STDERR "\nConfigurable constants (edit inside script):\n";
    print STDERR "  ADDR_REG    = " . sprintf("0x%08X", ADDR_REG) . "\n";
    print STDERR "  OUTPUT_FILE = " . OUTPUT_FILE . "\n";
    exit 1;
}

my ($start_addr_str, $num_lines, $dout_reg_str) = @ARGV;

# Parse addresses (accept both hex 0x... and decimal)
my $start_addr = parse_address($start_addr_str, "start_addr");
my $dout_reg   = parse_hex_address($dout_reg_str, "dout_reg");

# Validate num_lines
if ($num_lines !~ /^\d+$/ || $num_lines <= 0) {
    die "ERROR: Invalid num_lines '$num_lines'. Must be a positive integer.\n";
}

# Open output file
open(my $out_fh, '>', OUTPUT_FILE) or
    die "ERROR: Cannot create output file '" . OUTPUT_FILE . "': $!\n";

# Print summary
print "=" x 70 . "\n";
print "Memory Read Script\n";
print "=" x 70 . "\n";
print "Output file:    " . OUTPUT_FILE . "\n";
print "Start address:  0x" . sprintf("%08X", $start_addr) . "\n";
print "Reading:        $num_lines locations\n";
print "Address reg:    0x" . sprintf("%08X", ADDR_REG) . "\n";
print "Data out reg:   0x" . sprintf("%08X", $dout_reg) . "\n";
print "=" x 70 . "\n\n";

# Read data from memory
my $errors = 0;
my @read_data;

for (my $i = 0; $i < $num_lines; $i++) {
    my $bram_addr = $start_addr + $i;

    # Set address
    if (!regwrite(ADDR_REG, $bram_addr)) {
        print STDERR "ERROR: Failed to write address $bram_addr to address register\n";
        $errors++;
        last;
    }

    # Small delay for BRAM read latency (optional, uncomment if needed)
    # select(undef, undef, undef, 0.001);  # 1ms delay

    # Read data
    my $data = regread($dout_reg);
    if (!defined $data) {
        print STDERR "ERROR: Failed to read data from BRAM address $bram_addr\n";
        $errors++;
        last;
    }

    # Store and write data
    push @read_data, $data;
    printf $out_fh "%08X\n", $data;

    # Print progress every 64 addresses
    if ($i % 64 == 0) {
        printf "Read up to BRAM address %d (0x%08X)...\n", $bram_addr, $bram_addr;
    }
}

close($out_fh);

# Print some sample data
print "\n" . "-" x 70 . "\n";
print "Sample data (first 10 locations):\n";
print "-" x 70 . "\n";
my $sample_count = ($num_lines < 10) ? $num_lines : 10;
for (my $i = 0; $i < $sample_count && $i < scalar(@read_data); $i++) {
    printf "Address %3d (0x%08X): 0x%08X\n",
        $start_addr + $i, $start_addr + $i, $read_data[$i];
}
if ($num_lines > 10) {
    print "...\n";
    print "(See " . OUTPUT_FILE . " for complete dump)\n";
}

# Final summary
print "\n" . "=" x 70 . "\n";
if ($errors == 0) {
    print "SUCCESS! Read $num_lines locations from memory.\n";
    print "Output written to: " . OUTPUT_FILE . "\n";
    print "=" x 70 . "\n";
    exit 0;
} else {
    print "FAILURE! Encountered $errors error(s) during read.\n";
    print "Partial output may be in: " . OUTPUT_FILE . "\n";
    print "=" x 70 . "\n";
    exit 1;
}

# ============================================================================
# Helper Functions
# ============================================================================

sub parse_hex_address {
    my ($addr_str, $name) = @_;

    if ($addr_str =~ /^0x([0-9A-Fa-f]+)$/) {
        return hex($1);
    } else {
        die "ERROR: Invalid hex address for $name: '$addr_str'\n" .
            "       Expected format: 0xXXXXXXXX (e.g., 0x2000304)\n";
    }
}

sub parse_address {
    my ($addr_str, $name) = @_;

    if ($addr_str =~ /^0x([0-9A-Fa-f]+)$/) {
        return hex($1);             # Hex input
    } elsif ($addr_str =~ /^\d+$/) {
        return int($addr_str);      # Decimal input
    } else {
        die "ERROR: Invalid address for $name: '$addr_str'\n" .
            "       Expected hex (e.g., 0x10) or decimal (e.g., 16)\n";
    }
}

sub regwrite {
    my ($reg_addr, $value) = @_;

    my $cmd = sprintf("regwrite 0x%X 0x%X 2>&1", $reg_addr, $value);
    my $output = `$cmd`;
    my $exit_code = $? >> 8;

    if ($exit_code != 0) {
        print STDERR "regwrite command failed: $cmd\n";
        print STDERR "Output: $output\n" if $output;
        return 0;
    }

    return 1;
}

sub regread {
    my ($reg_addr) = @_;

    my $cmd = sprintf("regread 0x%X 2>&1", $reg_addr);
    my $output = `$cmd`;
    my $exit_code = $? >> 8;

    if ($exit_code != 0) {
        print STDERR "regread command failed: $cmd\n";
        print STDERR "Output: $output\n" if $output;
        return undef;
    }

    # Parse output - regread typically returns "0x12345678" or "12345678"
    chomp($output);
    $output =~ s/^\s+//;
    $output =~ s/\s+$//;

    if ($output =~ /(?:0x)?([0-9A-Fa-f]{1,8})/i) {
        return hex($1);
    } else {
        print STDERR "ERROR: Could not parse regread output: '$output'\n";
        return undef;
    }
}
