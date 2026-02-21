#!/usr/bin/perl
use warnings;

############################################################
# ====================== USER SETTINGS ======================
############################################################

# Cond field default for NON-branch instructions
# "default" => 1111
$DEFAULT_COND_NON_BRANCH_NAME = "al";

# NOP insertion controls
$ENABLE_INSERT_NOPS = 1;         # 1 to enable
$NOP_COUNT_AFTER_MATCH = 3;      # how many NOPs to insert
$INSERT_NOPS_AFTER_ALL = 1;      # 1 => after every instruction
@NOP_AFTER_MNEMONICS = ("ldr","str");  # used if AFTER_ALL=0

############################################################
# ====================== INPUT =============================
############################################################

$input_assembly_code = $ARGV[0];
open(R1, $input_assembly_code) or die "Cannot open assembly file\n";

############################################################
# ====================== ISA TABLES ========================
############################################################

%register_map = (
	r0=>"000", r1=>"001", r2=>"010", r3=>"011",
	r4=>"100", lr=>"101", fp=>"110", sp=>"111"
);

%opcode = (
	ldr => "00001",
	str => "00010",
	add => "00011",
	sub => "00100",
	and => "00101",
	or  => "00110",
	xor => "00111",
	mov => "01000",
	cmp => "01001",
	lsl => "01010",
	lsr => "01011",
 	b   => "01100",
 	jump=> "01101"
);

%cond = (
	eq=>"0000", ne=>"0001", cs=>"0010", cc=>"0011",
	mi=>"0100", pl=>"0101", vs=>"0110", vc=>"0111",
	hi=>"1000", ls=>"1001", ge=>"1010", lt=>"1011",
	gt=>"1100", le=>"1101", al=>"1110",
	default=>"1111"
);

############################################################
# ====================== STORAGE ===========================
############################################################

@all_text_lines = ();

%label_no_nops   = ();
%label_with_nops = ();

@annotated_lines = ();
@imem_hex_only   = ();
@imem_addr_hex   = ();

@debug_lines     = ();

@imem_hex_with_nops = ();

############################################################
# ====================== HELPERS ===========================
############################################################

sub clean {
	my $l = shift;
	$l =~ s/\@.*$//;
	$l =~ s/\r$//;
	$l =~ s/^\s+|\s+$//g;
	return $l;
}

sub reg3 {
	my $r = shift;
	$r =~ s/,//g;
	die "Unknown reg '$r'\n" unless exists $register_map{$r};
	return $register_map{$r};
}

sub imm {
	my $v = shift;
	$v =~ s/[#,]//g;
	$v =~ s/\]//g;
	return int($v);
}

sub bin32 { return sprintf("%032b", $_[0] & 0xFFFFFFFF); }
sub hex32 { return sprintf("%08X", $_[0] & 0xFFFFFFFF); }
sub hex9  { return sprintf("%03X", $_[0] & 0x1FF); }

sub imm9_twos {
	my $x = shift; # signed
	return ($x & 0x1FF);
}

sub bits {
	my ($word, $hi, $lo) = @_;
	my $mask = (1 << ($hi-$lo+1)) - 1;
	return ($word >> $lo) & $mask;
}

sub pack_instr_new {
	my ($opc5,$cond4,$alusrc,$rs1,$rs2,$rd,$imm9,$uf) = @_;

	die "Internal error: missing opcode bits\n"
		unless defined $opc5 && $opc5 ne "";

	my $w = 0;
	$w |= (oct("0b$opc5")  << 0);   # [4:0]
	$w |= (oct("0b$cond4") << 5);   # [8:5]
	$w |= (($alusrc & 1)   << 9);   # [9]
	$w |= (oct("0b$rs1")   << 10);  # [12:10]
	$w |= (oct("0b$rs2")   << 13);  # [15:13]
	$w |= (oct("0b$rd")    << 16);  # [18:16]
	$w |= (($imm9 & 0x1FF) << 19);  # [27:19]
	# [28] unused -> 0
	$w |= (($uf & 1)       << 29);  # [29] update flags
	# [30] user_stall -> 0
	# [31] LA_trigger -> 0
	return $w;
}

sub base_mnemonic {
	my $m = shift;
	return "b" if $m =~ /^b[a-z][a-z]$/;
	return $m;
}

sub should_insert_nops_after {
	my $base = shift;
	return 0 unless $ENABLE_INSERT_NOPS;
	return 0 if $NOP_COUNT_AFTER_MATCH <= 0;
	return 1 if $INSERT_NOPS_AFTER_ALL;

	for my $m (@NOP_AFTER_MNEMONICS) {
		return 1 if $m eq $base;
	}
	return 0;
}

sub emit_debug_label_maps {
	push @debug_lines, "====================== LABEL MAPS ======================";
	push @debug_lines, "NO NOPS (word addresses):";
	for my $k (sort keys %label_no_nops) {
		push @debug_lines, sprintf(
			"  %-12s dec=%-4d hex9=0x%s",
			$k, $label_no_nops{$k}, hex9($label_no_nops{$k})
		);
	}
	push @debug_lines, "";
	push @debug_lines, "WITH NOPS (expanded word addresses):";
	for my $k (sort keys %label_with_nops) {
		push @debug_lines, sprintf(
			"  %-12s dec=%-4d hex9=0x%s",
			$k, $label_with_nops{$k}, hex9($label_with_nops{$k})
		);
	}
	push @debug_lines, "========================================================";
	push @debug_lines, "";
}

sub emit_debug_instruction_block {
	my (%h) = @_;

	$h{opc_bits}  = "(undef)" unless defined $h{opc_bits};
	$h{cond_bits} = "(undef)" unless defined $h{cond_bits};

	push @debug_lines, "--------------------------------------------------------------------------------";
	push @debug_lines, sprintf(
		"PC(no_nops)=%d (0x%s)   PC(expanded)=%d (0x%s)",
		$h{pc_no}, hex9($h{pc_no}), $h{pc_ex}, hex9($h{pc_ex})
	);

	push @debug_lines, "ASM: $h{asm}";
	push @debug_lines, "FINAL: bin=$h{bin32}";
	push @debug_lines, "FINAL: hex=0x$h{hex32}";
	push @debug_lines, "";

	push @debug_lines, "FIELDS (NEW bit ranges):";
	push @debug_lines, sprintf(
		"  [31] LA_Trigger=%d   [30] User_stall=%d   [29] update_flags=%d   [28] unused=%d",
		$h{la_trigger}, $h{user_stall}, $h{uflag}, $h{unused28}
	);

	push @debug_lines, sprintf(
		"  [27:19] imm9_tc=%3d (0x%03X, b%09b)   imm_signed=%d",
		$h{imm9_tc}, $h{imm9_tc}, ($h{imm9_tc} & 0x1FF), $h{imm_signed}
	);

	if($h{opc_name} eq "str") {
		push @debug_lines, sprintf(
			"  [18:16] rd_unused=%s (%s)   [15:13] store_data(rs2)=%s (%s)   [12:10] base(rs1)=%s (%s)",
			$h{rd_name},  $h{rd_bits},
			$h{rs2_name}, $h{rs2_bits},
			$h{rs1_name}, $h{rs1_bits}
		);
	} else {
		push @debug_lines, sprintf(
			"  [18:16] rd=%s (%s)         [15:13] rs2=%s (%s)             [12:10] rs1=%s (%s)",
			$h{rd_name},  $h{rd_bits},
			$h{rs2_name}, $h{rs2_bits},
			$h{rs1_name}, $h{rs1_bits}
		);
	}

	push @debug_lines, sprintf(
		"  [9] alusrc=%d    [8:5] cond=%s (%s)    [4:0] opcode=%s (%s)",
		$h{alusrc}, $h{cond_name}, $h{cond_bits}, $h{opc_name}, $h{opc_bits}
	);
	push @debug_lines, "";

	if($h{is_branch}) {
		push @debug_lines, "BRANCH/OFFSET DETAILS:";
		push @debug_lines, sprintf("  branch mnemonic  : %s", $h{branch_mn});
		push @debug_lines, sprintf("  label name       : %s", $h{target_label});
		push @debug_lines, sprintf("  label addr source: %s", $h{label_map_used});
		push @debug_lines, sprintf(
			"  target addr      : dec=%d hex9=0x%s",
			$h{target_addr}, hex9($h{target_addr})
		);
		push @debug_lines, sprintf(
			"  pc used          : dec=%d (pc+1=%d)",
			$h{branch_pc_used}, ($h{branch_pc_used}+1)
		);
		push @debug_lines, sprintf(
			"  offset (words)   : target - (pc+1) = %d",
			$h{offset_signed}
		);
		push @debug_lines, sprintf(
			"  imm9_tc written  : %d (0x%03X)",
			$h{imm9_tc}, $h{imm9_tc}
		);
		push @debug_lines, "";
	}

	if($h{nops_after} > 0) {
		push @debug_lines, sprintf(
			"NOP INSERTION: after this instruction, inserted %d NOP(s)",
			$h{nops_after}
		);
		push @debug_lines, "  NOP encoding: 0x00000000";
		push @debug_lines, "";
	}

	push @debug_lines, "EXPLAIN:";
	push @debug_lines, "  $h{explain}";
	push @debug_lines, "";
}

############################################################
# PASS 1: COLLECT .text LINES (GCC style)
############################################################

$text = 0;
while($line = <R1>) {
	$line = clean($line);
	next if $line eq "";

	if($line =~ /^\.(text|section\s+\.text)\b/) { $text = 1; next; }
	next unless $text;

	next if ($line =~ /^\.(align|global|syntax|arm|type|size|ident|file|cpu|arch|fpu|eabi_attribute)\b/);

	push @all_text_lines, $line;
}
close R1;

############################################################
# r0 replacement (keep r0 hard-wired to 0)
############################################################

$R0_REPLACE = "";

$seen_r1 = 0; $seen_r2 = 0; $seen_r3 = 0; $seen_r4 = 0;
for my $l (@all_text_lines) {
	$seen_r1 = 1 if $l =~ /\br1\b/;
	$seen_r2 = 1 if $l =~ /\br2\b/;
	$seen_r3 = 1 if $l =~ /\br3\b/;
	$seen_r4 = 1 if $l =~ /\br4\b/;
}

if(!$seen_r4) { $R0_REPLACE = "r4"; }
elsif(!$seen_r3) { $R0_REPLACE = "r3"; }
elsif(!$seen_r2) { $R0_REPLACE = "r2"; }
elsif(!$seen_r1) { $R0_REPLACE = "r1"; }
else { die "No free register available to replace r0\n"; }

print "INFO: Replacing all occurrences of r0 with $R0_REPLACE (r0 assumed hard-wired to 0 in your CPU)\n";

@fixed_text_lines = ();
for my $l (@all_text_lines) {
	$l =~ s/\br0\b/$R0_REPLACE/g;
	push @fixed_text_lines, $l;
}
@all_text_lines = @fixed_text_lines;

############################################################
# ====================== ADDED CODE: EXPANSIONS ============
# 1) Split lsl/lsr #N into N times #1
# 2) Split ARM writeback/postindex for ldr/str into two insns
#    - pre-index writeback: [rn, #imm]!  => memop + add/sub rn,#abs(imm)
#    - post-index:          [rn], #imm   => memop([rn,#0]) + add/sub rn,#abs(imm)
############################################################

@expanded_text_lines = ();

for my $l (@all_text_lines) {

	# keep labels/directives untouched
	if($l =~ /^([.\w]+):$/ || $l =~ /^\./ || $l eq "main:") {
		push @expanded_text_lines, $l;
		next;
	}

	# ---------- (A) WRITEBACK/PREINDEX: ldr/str Rt, [Rn, #imm]! ----------
	if($l =~ /^\s*(ldr|str)\s+(\w+)\s*,\s*\[(\w+)\s*,\s*#(-?\d+)\]\!\s*$/) {
		my $mn = $1;
		my $rt = $2;
		my $rn = $3;
		my $off = int($4);

		push @expanded_text_lines, "$mn $rt, [$rn, #$off]";

		if($off >= 0) {
			push @expanded_text_lines, "add $rn, $rn, #$off";
		} else {
			my $abs = -$off;
			push @expanded_text_lines, "sub $rn, $rn, #$abs";
		}
		next;
	}

	# ---------- (B) WRITEBACK/PREINDEX without explicit imm: [Rn]! ----------
	if($l =~ /^\s*(ldr|str)\s+(\w+)\s*,\s*\[(\w+)\]\!\s*$/) {
		my $mn = $1;
		my $rt = $2;
		my $rn = $3;
		push @expanded_text_lines, "$mn $rt, [$rn, #0]";
		next;
	}

	# ---------- (C) POST-INDEX: ldr/str Rt, [Rn], #imm ----------
	if($l =~ /^\s*(ldr|str)\s+(\w+)\s*,\s*\[(\w+)\]\s*,\s*#(-?\d+)\s*$/) {
		my $mn = $1;
		my $rt = $2;
		my $rn = $3;
		my $off = int($4);

		push @expanded_text_lines, "$mn $rt, [$rn, #0]";

		if($off >= 0) {
			push @expanded_text_lines, "add $rn, $rn, #$off";
		} else {
			my $abs = -$off;
			push @expanded_text_lines, "sub $rn, $rn, #$abs";
		}
		next;
	}

	# ---------- (D) SHIFT SPLIT: lsl/lsr rd, rs, #N (N>1) ----------
	if($l =~ /^\s*(lsl|lsr)\s+(\w+)\s*,\s*(\w+)\s*,\s*#(-?\d+)\s*$/) {
		my $mn = $1;
		my $rd = $2;
		my $rs = $3;
		my $sh = int($4);

		if($sh <= 1) {
			push @expanded_text_lines, $l;
			next;
		}

		push @expanded_text_lines, "$mn $rd, $rs, #1";
		for(my $k=1; $k<$sh; $k++) {
			push @expanded_text_lines, "$mn $rd, $rd, #1";
		}
		next;
	}

	push @expanded_text_lines, $l;
}

@all_text_lines = @expanded_text_lines;

############################################################
# ADDED OUTPUT FILE: show modified/expanded assembly stream
############################################################

open(WASM,">modified_assembly_expanded.s") or die "Cannot write modified_assembly_expanded.s\n";
print WASM "$_\n" for @all_text_lines;
close WASM;

############################################################
# PASS 2A: LABEL MAP WITHOUT NOPS
############################################################

$pc_no = 0;
$main_seen = 0;

for my $l (@all_text_lines) {
	if($l eq "main:") { $main_seen = 1; next; }
	next unless $main_seen;

	if($l =~ /^([.\w]+):$/) {
		$label_no_nops{$1} = $pc_no;
		next;
	}
	next if $l =~ /^\./;
	$pc_no++;
}

############################################################
# PASS 2B: LABEL MAP WITH NOPS (expanded)
############################################################

$pc_ex = 0;
$main_seen = 0;

for my $l (@all_text_lines) {
	if($l eq "main:") { $main_seen = 1; next; }
	next unless $main_seen;

	if($l =~ /^([.\w]+):$/) {
		$label_with_nops{$1} = $pc_ex;
		next;
	}
	next if $l =~ /^\./;

	my ($mn) = split(/\s+/, $l);
	my $base = base_mnemonic($mn);
	my $nops = should_insert_nops_after($base) ? $NOP_COUNT_AFTER_MATCH : 0;

	$pc_ex += 1 + $nops;
}

emit_debug_label_maps();

############################################################
# PASS 3: ENCODE INSTRUCTIONS
############################################################

$pc_no = 0;
$pc_ex = 0;
$main_seen = 0;

for my $orig (@all_text_lines) {

	if($orig eq "main:") { $main_seen = 1; next; }
	next unless $main_seen;

	next if $orig =~ /^([.\w]+):$/;
	next if $orig =~ /^\./;

	my $line = $orig;
	$line =~ s/,/ /g;
	$line =~ s/\[/ [ /g;
	$line =~ s/\]/ ] /g;
	$line =~ s/\s+/ /g;

	my @t = split(/\s+/, $line);
	my $mn = shift @t;

	my $base = base_mnemonic($mn);
	my $nops_after = should_insert_nops_after($base) ? $NOP_COUNT_AFTER_MATCH : 0;

	my $opc_bits = "";
	my $opc_name = "";

	my $cond_name = $DEFAULT_COND_NON_BRANCH_NAME;
	my $cond_bits = $cond{$cond_name};

	my ($rs1_bits,$rs2_bits,$rd_bits) = ("000","000","000");
	my ($rs1_name,$rs2_name,$rd_name) = ("(none)","(none)","(none)");

	my $alusrc = 0;
	my $imm_signed = 0;
	my $imm9 = 0;
	my $uf = 0;

	my $is_branch = 0;
	my $target_label = "";
	my $target_addr = 0;
	my $offset_signed = 0;

	my $explain = "";

	# bx -> jump
	if($mn eq "bx") {
		$opc_name = "jump";
		$opc_bits = $opcode{jump};
		$rs1_name = $t[0];
		$rs1_bits = reg3($rs1_name);
		$explain = "JUMP: PC <- $rs1_name";
	}

	# branches
	elsif($mn =~ /^b/) {
		$opc_name = "b";
		$opc_bits = $opcode{b};

		my $cc = "al";
		$cc = $1 if $mn =~ /^b([a-z][a-z])$/;
		$cond_name = $cc;
		$cond_bits = $cond{$cc};

		$target_label = $t[0];

		my $label_map_used = $ENABLE_INSERT_NOPS
			? "label_with_nops (expanded PC space)"
			: "label_no_nops (no-NOP PC space)";

		my $tgt = $ENABLE_INSERT_NOPS
			? $label_with_nops{$target_label}
			: $label_no_nops{$target_label};

		die "Unknown label '$target_label'\n" unless defined $tgt;

		my $branch_pc_used = $ENABLE_INSERT_NOPS ? $pc_ex : $pc_no;

		$offset_signed = $tgt - ($branch_pc_used + 1);

		die "Branch offset out of range: $offset_signed\n"
			if $offset_signed < -256 || $offset_signed > 255;

		$is_branch = 1;
		$alusrc = 1;
		$imm_signed = $offset_signed;
		$imm9 = imm9_twos($imm_signed);

		$target_addr = $tgt;

		$explain =
		  "BRANCH: target=$target_label tgt=$tgt ".
		  "pc_used=$branch_pc_used off=tgt-(pc+1)=$offset_signed";

		$branch_mn_dbg = $mn;
		$label_map_used_dbg = $label_map_used;
		$branch_pc_used_dbg = $branch_pc_used;
	}

	# add/sub/and/or/xor
	elsif($mn eq "add" || $mn eq "sub" || $mn eq "and" || $mn eq "or" || $mn eq "xor") {
		$opc_name = $mn;
		$opc_bits = $opcode{$mn};

		$rd_name  = $t[0]; $rd_bits  = reg3($rd_name);
		$rs1_name = $t[1]; $rs1_bits = reg3($rs1_name);

		if(defined $t[2] && $t[2] =~ /^#/) {
			$alusrc = 1;
			my $v = imm($t[2]);
			$imm_signed = $v;
			$imm9 = imm9_twos($imm_signed);
		} else {
			$rs2_name = $t[2]; $rs2_bits = reg3($rs2_name);
		}

		$explain =
		  "$mn: rd=$rd_name rs1=$rs1_name ".
		  ($alusrc ? "imm=$imm_signed" : "rs2=$rs2_name");
	}

	# lsl/lsr
	elsif($mn eq "lsl" || $mn eq "lsr") {
		$opc_name = $mn;
		$opc_bits = $opcode{$mn};

		$rd_name  = $t[0]; $rd_bits  = reg3($rd_name);
		$rs1_name = $t[1]; $rs1_bits = reg3($rs1_name);

		die "$mn needs immediate\n" unless defined $t[2] && $t[2] =~ /^#/;
		$alusrc = 1;
		$imm_signed = imm($t[2]);
		$imm9 = imm9_twos($imm_signed);

		$explain = "$mn: rd=$rd_name rs1=$rs1_name shamt=$imm_signed";
	}

	# mov
	elsif($mn eq "mov") {
		$opc_name = "mov";
		$opc_bits = $opcode{mov};

		$rd_name = $t[0]; $rd_bits = reg3($rd_name);

		if(defined $t[1] && $t[1] =~ /^#/) {
			$alusrc = 1;
			$imm_signed = imm($t[1]);
			$imm9 = imm9_twos($imm_signed);
			$explain = "mov: rd=$rd_name imm=$imm_signed";
		} else {
			$rs1_name = $t[1]; $rs1_bits = reg3($rs1_name);
			$explain = "mov: rd=$rd_name rs1=$rs1_name";
		}
	}

	# cmp
	elsif($mn eq "cmp") {
		$opc_name = "cmp";
		$opc_bits = $opcode{cmp};

		$rs1_name = $t[0]; $rs1_bits = reg3($rs1_name);
		$uf = 1;

		if(defined $t[1] && $t[1] =~ /^#/) {
			$alusrc = 1;
			$imm_signed = imm($t[1]);
			$imm9 = imm9_twos($imm_signed);
			$explain = "cmp: rs1=$rs1_name imm=$imm_signed (flags updated)";
		} else {
			$rs2_name = $t[1]; $rs2_bits = reg3($rs2_name);
			$explain = "cmp: rs1=$rs1_name rs2=$rs2_name (flags updated)";
		}
	}

	# ldr
	elsif($mn eq "ldr") {
		$opc_name = "ldr";
		$opc_bits = $opcode{ldr};

		die "Bad ldr syntax\n" unless defined $t[1] && $t[1] eq "[";

		$rd_name  = $t[0]; $rd_bits  = reg3($rd_name);
		$rs1_name = $t[2]; $rs1_bits = reg3($rs1_name);

		# ===== FIX: for any ldr, even [rn] with no #imm, force alusrc=1 and imm=0 =====
		$alusrc = 1;
		$imm_signed = 0;
		$imm9 = imm9_twos(0);

		if(defined $t[3] && $t[3] =~ /^#/) {
			$imm_signed = imm($t[3]);
			$imm9 = imm9_twos($imm_signed);
		}

		$explain =
		  "ldr: rd=$rd_name base=$rs1_name off=$imm_signed";
	}

	# str (store-data in rs2)
	elsif($mn eq "str") {
		$opc_name = "str";
		$opc_bits = $opcode{str};

		die "Bad str syntax\n" unless defined $t[1] && $t[1] eq "[";

		$rs2_name = $t[0]; $rs2_bits = reg3($rs2_name);
		$rs1_name = $t[2]; $rs1_bits = reg3($rs1_name);

		$rd_name = "(unused)"; $rd_bits = "000";

		# ===== FIX: for any str, even [rn] with no #imm, force alusrc=1 and imm=0 =====
		$alusrc = 1;
		$imm_signed = 0;
		$imm9 = imm9_twos(0);

		if(defined $t[3] && $t[3] =~ /^#/) {
			$imm_signed = imm($t[3]);
			$imm9 = imm9_twos($imm_signed);
		}

		$explain =
		  "str: store_data=$rs2_name base=$rs1_name off=$imm_signed";
	}

	else {
		die "Unsupported instruction: $orig\n";
	}

	die "Unsupported instruction: $orig\n" unless defined $opc_bits && $opc_bits ne "";

	my $word = pack_instr_new(
		$opc_bits,$cond_bits,$alusrc,
		$rs1_bits,$rs2_bits,$rd_bits,
		$imm9,$uf
	);

	my $bin = bin32($word);
	my $hex = hex32($word);

	# ===== ORIGINAL FILES (NO-NOP stream) =====
	push @annotated_lines, sprintf("%-40s | %s | 0x%s", $orig, $bin, $hex);
	push @imem_hex_only, $hex;
	push @imem_addr_hex, sprintf("%s %s", hex9($pc_no), $hex);

	# ===== NOP STREAM FILE (ONLY if enabled) =====
	if($ENABLE_INSERT_NOPS) {
		push @imem_hex_with_nops, $hex;
		for(my $k=0; $k<$nops_after; $k++) {
			push @imem_hex_with_nops, "00000000";
		}
	}

	# ===== DETAILED DEBUG =====
	emit_debug_instruction_block(
		pc_no      => $pc_no,
		pc_ex      => $pc_ex,
		asm        => $orig,
		bin32      => $bin,
		hex32      => $hex,

		la_trigger => bits($word,31,31),
		user_stall => bits($word,30,30),
		uflag      => bits($word,29,29),
		unused28   => bits($word,28,28),

		imm9_tc    => bits($word,27,19),
		imm_signed => $imm_signed,

		rd_name    => $rd_name,
		rd_bits    => $rd_bits,
		rs2_name   => $rs2_name,
		rs2_bits   => $rs2_bits,
		rs1_name   => $rs1_name,
		rs1_bits   => $rs1_bits,

		alusrc     => bits($word,9,9),

		cond_name  => $cond_name,
		cond_bits  => $cond_bits,

		opc_name   => $opc_name,
		opc_bits   => $opc_bits,

		is_branch     => $is_branch,
		branch_mn     => ($is_branch ? $branch_mn_dbg : ""),
		target_label  => $target_label,
		label_map_used=> ($is_branch ? $label_map_used_dbg : ""),
		target_addr   => $target_addr,
		branch_pc_used=> ($is_branch ? $branch_pc_used_dbg : 0),
		offset_signed => $offset_signed,

		nops_after  => $nops_after,
		explain     => $explain
	);

	# advance pcs
	$pc_no++;
	$pc_ex += 1 + $nops_after;
}

############################################################
# WRITE OUTPUT FILES (same filenames / formats as before)
############################################################

open(W1,">imem_annotated.lst") or die "Cannot write imem_annotated.lst\n";
print W1 "$_\n" for @annotated_lines;
close W1;

open(W2,">imem_hex.txt") or die "Cannot write imem_hex.txt\n";
print W2 "$_\n" for @imem_hex_only;
close W2;

open(W3,">imem_addr_hex.txt") or die "Cannot write imem_addr_hex.txt\n";
print W3 "$_\n" for @imem_addr_hex;
close W3;

open(W4,">imem_debug_fields.lst") or die "Cannot write imem_debug_fields.lst\n";
print W4 "$_\n" for @debug_lines;
close W4;

if($ENABLE_INSERT_NOPS) {
	open(W5,">imem_hex_with_nops.txt") or die "Cannot write imem_hex_with_nops.txt\n";
	print W5 "$_\n" for @imem_hex_with_nops;
	close W5;
}

print "Generated:\n";
print "  modified_assembly_expanded.s\n";
print "  imem_annotated.lst\n";
print "  imem_hex.txt\n";
print "  imem_addr_hex.txt\n";
print "  imem_debug_fields.lst\n";
if($ENABLE_INSERT_NOPS) { print "  imem_hex_with_nops.txt\n"; }