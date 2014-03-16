#!/usr/bin/perl
package EOSTOKFEAT ;

# [EOSTOKFEAT.pm] is a [Perl library] that can prepare a [text_string_list] into [tokenized_text_feature_dataset]

use strict ;
use warnings ;

use vars qw($VERSION $PACKAGEFILE $CONTACT $VERSIONDATE @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS) ;

$VERSION	   = '1.2.0' ;
$VERSIONDATE = "2014.03.15" ;
$PACKAGEFILE = 'EOSTOKFEAT.pm' ;
$CONTACT	   = 'eostokfeat@gabormelli.com' ;


# A [text_input] can be from [STDIN] or a [file].
# A [text_input] can include data from HTML pages from the Web
# A [text_input] can be in UNIX or DOS end-of-line format.
# A [text_input] has zero or more [tab_separated] [text_record] terminated by an [end-of-line].
# A [text_record] must have a [text_string] as its [first_record_element].
# A [text_record] can have zero or more [other_record_element]s.
# A [text_string] must have fewer than 2048 characters (user settable in the future).
# A [text_string] must have more than 5 characters (user settable in the future).
# A [text_string] must have more than 3 raw tokens (user settable in the future).
# A [text_string] [first_charater] must be a [non-whitespace_character].
# A [text_string] [last_charater] must be a [non-whitespace_character].
# An [annotated_text_string] is a [text_string] that can contain [wikitext] [hyperlink_markup] (e.g. "...the [CE PRODUCT|Sony XZ-54] is..." or "... the [Sony_XZ-54] is..."
# An [end-of-sentence_character] is the last [non-whitespace_character] in a [linguistic_sentence].
# A [text_token] is a [non-whitespace_character_string] that is a [meaning_bearing_unit] - either semantic meaning (like a word or name) or syntactic meaning like (punctuation or parentheses).
# A [sentence_annotated_text_string] is a [text_string] with a [sentence_start_marker] in front of each sentence.
# A [text_input] with consecutive whitespaces will be compressed to not have consecutive whitespaces. This is a code simplifying assumption.
#
# Current function that is not yet formally described in the spec:
# * behavior of feature generation
#
# Future Requirements
# * Support UTF-8. For example ... of У[Emotional_Infidelity.]Ф ... Currently excluded from input
# * Improve existing features
# ** exact match on multi-token gazeetter terms
# * Add more features
# ** partial match on a dictionary name
# ** currency symbol count
# * Enhance featurization to report a document identifier element (e.g. DOC92721) before its set of tokens
# * Allow for the feature definitions (currently hardcoded) to be defined outside of the program. (e.g. an input file that contains the regular expressions).



# A set of subroutines to manage EOSTOKFEAT
#
# SUBROUTINES
sub sentenceBoundaryDetector($) ;
sub textTokenizer($) ;
sub textDetokenizer($) ;
sub textTokenLabelDecorator($) ;
sub textTokenFeaturizer(@) ;
sub derivedFeatures(@) ;
sub normalizeToken($) ;
sub processFile($$$$$$$$$$$$$$$$$) ;

##########
use Exporter ;
@ISA = qw(Exporter AutoLoader) ;


# Items to export into callers namespace by default. Note: do not export names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
sub compressFeature($) ;
sub trim($) ;
sub normalizeToken($) ;

my $debug = 0 ;
my $maxCompressValue = 15 ;

my $logFH ;
my %TermTypeTokenCount ; # hash of the number of times a token is seen in the dictionary {by placement} {by type|
my %TermTypeTerm       ; # hash of the number of times a term is seen in the dictionary (by type) - typically only once

@EXPORT = qw($debug processFile sentenceBoundaryDetector textTokenizer textDetokenizer textTokenLabelDecorator textTokenFeaturizer derivedFeatures normalizeToken
) ;

#@EXPORT_OK   = qw(func1 func2) ;
#%EXPORT_TAGS = ( DEFAULT => [qw(&func1)],
#                 Both    => [qw(&func1 &func2)]) ;


use POSIX ; # ceil() 
use Lingua::Stem::Snowball ;
#use Algorithm::AhoCorasick qw(find_all); # used to find token substrings in the (leaderboard) text_items that match the product terms mentioned in the training dataset.


# Global Variables - ideally configurabe from input parameters
my $tokSep	= " " ; # default separator between tokens - not (yet) user configurable.
my $featSep	= " " ; # default separator between features - not (yet) user configurable.
my $Olabel	= "O" ; # Token label for "outside term token".
my $Blabel	= "B" ; # Token label for "beginning of a term token".
my $Ilabel	= "I" ; # Token label for "inteveneing term token" (and possibly end of term in label).
my $Elabel	= "E" ; # Token label for "end of a term token".
my $whiteSpace = " " ;
my $maxTextStringChars  = 112048 ; # default value - not (yet) user configurable.
my $minTextStringChars  =      0 ; # default value - not (yet) user configurable.
my $minTextStringTokens =      4 ; # default value - not (yet) user configurable.
my $stemmer = Lingua::Stem::Snowball->new(lang => 'en', encoding => 'ISO-8859-1', ); die $@ if $@ ;


# set from input params if at all
my $inFile ;
my $outFile ;
my $logFile ;
my $dictFile ;

my $performEOSDetection  = 0 ;
my $performTokenization  = 0 ;
my $performFeaturization = 0 ;
my $includeDerivedFeatures      = 0 ;
my $includeGlobalFeatures       = 0 ;
my $includeSimpleBigramFeatures = 0 ;
my $noLabel = 0 ;
my $doNotReportFeatureValues = 0 ;



# The default is not to include all features
my ($inclFeature_FRSTCHR, $inclFeature_CHARCNT, $inclFeature_UCCNT, $inclFeature_NUMCNT, $inclFeature_LCCNT,
	$inclFeature_DSHCNT, $inclFeature_SLSHCNT, $inclFeature_PERIODCNT, 
	 $inclFeature_BLWRDCNT,  $inclFeature_BRNDWRDCNT,  $inclFeature_PLWRDCNT,  $inclFeature_PRODCATWRDCNT,  $inclFeature_PRODFEATWRDCNT, $inclFeature_PRODWRDCNT, $inclFeature_BPCWRDCNT,
	 $inclFeature_BLWRD1CNT, $inclFeature_BRNDWRD1CNT, $inclFeature_PLWRD1CNT, $inclFeature_PRODCATWRD1CNT, $inclFeature_PRODFEATWRD1CNT, $inclFeature_PRODWRD1CNT, $inclFeature_BPCWRD1CNT,
	 $inclFeature_BLWRDnCNT, $inclFeature_BRNDWRDnCNT, $inclFeature_PLWRDnCNT, $inclFeature_PRODCATWRDnCNT, $inclFeature_PRODFEATWRDnCNT, $inclFeature_PRODWRDnCNT, $inclFeature_BPCWRDnCNT,
	 $inclFeature_GRWRDCNT, $inclFeature_ENWRDCNT, $inclFeature_SPWRDCNT,
	 $inclFeature_STMDTOK,
	 $inclFeature_LEFTOFFSET, $inclFeature_RIGHTOFFSET, $inclFeature_TERMPATTERN, $inclFeature_TRMPTRNCMPR
	) = (1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1) ;



# The default is not to exclude any feature
my ($exclFeature_FRSTCHR, $exclFeature_CHARCNT, $exclFeature_UCCNT, $exclFeature_NUMCNT, $exclFeature_LCCNT,
	$exclFeature_DSHCNT, $exclFeature_SLSHCNT, $exclFeature_PERIODCNT, $exclFeature_GRWRDCNT,
	$exclFeature_BLWRDCNT, $exclFeature_BRNDWRDCNT, $exclFeature_PLWRDCNT, $exclFeature_PRODCATWRDCNT, $exclFeature_PRODFEATWRDCNT, $exclFeature_BPCWRDCNT, $exclFeature_PRODWRDCNT,
  $exclFeature_BLWRD1CNT, $exclFeature_BRNDWRD1CNT, $exclFeature_PLWRD1CNT, $exclFeature_PRODCATWRD1CNT, $exclFeature_PRODFEATWRD1CNT, $exclFeature_BPCWRD1CNT, $exclFeature_PRODWRD1CNT,
  $exclFeature_BLWRDnCNT, $exclFeature_BRNDWRDnCNT, $exclFeature_PLWRDnCNT, $exclFeature_PRODCATWRDnCNT, $exclFeature_PRODFEATWRDnCNT, $exclFeature_BPCWRDnCNT, $exclFeature_PRODWRDnCNT,
	$exclFeature_ENWRDCNT, $exclFeature_SPWRDCNT, $exclFeature_STMDTOK, $exclFeature_RIGHTOFFSET, $exclFeature_LEFTOFFSET, $exclFeature_TERMPATTERN, $exclFeature_TRMPTRNCMPR
        ) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0) ;



############################################################

sub processFile($$$$$$$$$$$$$$$$$) {
	
	my $inFile   = shift() ;
	my $outFile  = shift() ;
	my $logFile  = shift() ;
	my $dictFile = shift() ;
	$debug       = shift() ;
	my $verbose  = shift() ;
	my $performEOSDetection         = shift() ;
	my $performTokenization         = shift() ;
	my $performDetokenization       = shift() ;
	my $performFeaturization        = shift() ;
	my $includeDerivedFeatures      = shift() ;
	my $includeGlobalFeatures       = shift() ;
	my $includeSimpleBigramFeatures = shift() ;
	my $featuresToInclude           = shift() ;
	my $featuresToExclude           = shift() ;
	my $doNotReportFeatureValues    = shift() ;
	my $noLabel = shift() ;
	
  $featuresToInclude = "" if (not defined $featuresToInclude) ;
	$featuresToExclude = "" if (not defined $featuresToExclude) ;
  
  $doNotReportFeatureValues=0 if not defined $doNotReportFeatureValues ;
  $featuresToInclude="" if $doNotReportFeatureValues ;

	
	########################################
	# create the handle to the log file
	my $isSTDOUTlog = 0 ;
	# Test the --logFile parameter
	if (defined $logFile){
		die("\nERROR: --logFile must be a file not a directory. [$logFile]\n") if -d $logFile ;
		open $logFH, ">", $logFile or die "ERROR: when opening the log file [$logFile]:\n   $!" ;
	} else {
	  $logFH = *STDOUT ;
	  $isSTDOUTlog++ ;
	  $logFile="-" ;
	}
	
	if ($debug>0) {
	   print $logFH "DEBUG: Debugging enabled and set to level: $debug.\n" ;
	}

	
	
	#######################################
	# create the handle to the input file
	my $isSTDIN = 0 ;
	my $inputFH ;
	# Test the --inFile parameter
	if (defined $inFile){
		die("\nERROR: --inFile must be a file not a directory. [$inFile]\n") if -d $inFile ;
		open $inputFH, "<", $inFile or die "ERROR: when opening the input file [$inFile]:\n   $!" ;
	} else {
	  $inputFH = *STDIN ;
	  $isSTDIN++ ;
	  $inFile="-" ;
	}
	
	
	########################################
	# create the handle to the output file
	my $isSTDOUT = 0 ;
	my $outputFH ;
	# Test the --outFile parameter
	if (defined $outFile){
		die("\nERROR: --outFile must be a file not a directory. [$outFile]\n") if -d $outFile ;
		open $outputFH, ">", $outFile or die "ERROR: when opening the output file [$outFile]:\n   $!" ;
	} else {
	  $outputFH = *STDOUT ;
		$isSTDOUT++ ;
	  $outFile="-" ;
	}



	if (length($featuresToInclude)>1) {
		$inclFeature_FRSTCHR        = 0 if not $featuresToInclude =~ m/FRSTCHR/ ;
		$inclFeature_CHARCNT        = 0 if not $featuresToInclude =~ m/CHARCNT/ ;
		$inclFeature_UCCNT          = 0 if not $featuresToInclude =~ m/UCCNT/ ;
		$inclFeature_NUMCNT         = 0 if not $featuresToInclude =~ m/NUMCNT/ ;
		$inclFeature_LCCNT          = 0 if not $featuresToInclude =~ m/LCCNT/ ;
		$inclFeature_DSHCNT         = 0 if not $featuresToInclude =~ m/DSHCNT/ ;
		$inclFeature_SLSHCNT        = 0 if not $featuresToInclude =~ m/SLSHCNT/ ;
		$inclFeature_PERIODCNT      = 0 if not $featuresToInclude =~ m/PERIODCNT/ ;
		
		$inclFeature_BLWRDCNT        = 0 if not $featuresToInclude =~ m/BLWRDCNT/ ;
		$inclFeature_BRNDWRDCNT      = 0 if not $featuresToInclude =~ m/BRNDWRDCNT/ ;
		$inclFeature_PLWRDCNT        = 0 if not $featuresToInclude =~ m/PLWRDCNT/ ;
		$inclFeature_PRODCATWRDCNT   = 0 if not $featuresToInclude =~ m/PRODCATWRDCNT/ ;
		$inclFeature_PRODFEATWRDCNT  = 0 if not $featuresToInclude =~ m/PRODFEATWRDCNT/ ;
		$inclFeature_BPCWRDCNT       = 0 if not $featuresToInclude =~ m/BPCWRDCNT/ ;
		$inclFeature_PRODWRDCNT      = 0 if not $featuresToInclude =~ m/PRODWRDCNT/ ;
		$inclFeature_BLWRD1CNT       = 0 if not $featuresToInclude =~ m/BLWRD1CNT/ ;
		$inclFeature_BRNDWRD1CNT     = 0 if not $featuresToInclude =~ m/BRNDWRD1CNT/ ;
		$inclFeature_PLWRD1CNT       = 0 if not $featuresToInclude =~ m/PLWRD1CNT/ ;
		$inclFeature_PRODCATWRD1CNT  = 0 if not $featuresToInclude =~ m/PRODCATWRD1CNT/ ;
		$inclFeature_PRODFEATWRD1CNT = 0 if not $featuresToInclude =~ m/PRODFEATWRD1CNT/ ;
		$inclFeature_PRODWRD1CNT     = 0 if not $featuresToInclude =~ m/PRODWRD1CNT/ ;
		$inclFeature_BPCWRD1CNT      = 0 if not $featuresToInclude =~ m/BPCWRD1CNT/ ;
		$inclFeature_BLWRDnCNT       = 0 if not $featuresToInclude =~ m/BLWRDnCNT/ ;
		$inclFeature_BRNDWRDnCNT     = 0 if not $featuresToInclude =~ m/BRNDWRDnCNT/ ;
		$inclFeature_PLWRDnCNT       = 0 if not $featuresToInclude =~ m/PLWRDnCNT/ ;
		$inclFeature_PRODCATWRDnCNT  = 0 if not $featuresToInclude =~ m/PRODCATWRDnCNT/ ;
		$inclFeature_PRODFEATWRDnCNT = 0 if not $featuresToInclude =~ m/PRODFEATWRDnCNT/ ;
		$inclFeature_PRODWRDnCNT     = 0 if not $featuresToInclude =~ m/PRODWRDnCNT/ ;
		$inclFeature_BPCWRDnCNT      = 0 if not $featuresToInclude =~ m/BPCWRDnCNT/ ;
	
		$inclFeature_GRWRDCNT       = 0 if not $featuresToInclude =~ m/GRWRDCNT/ ;
		$inclFeature_ENWRDCNT       = 0 if not $featuresToInclude =~ m/ENWRDCNT/ ;
		$inclFeature_SPWRDCNT       = 0 if not $featuresToInclude =~ m/SPWRDCNT/ ;
		
		$inclFeature_STMDTOK        = 0 if not $featuresToInclude =~ m/STMDTOK/ ;
			
		$inclFeature_LEFTOFFSET     = 0 if not $featuresToInclude =~ m/LEFTOFFSET/ ;
		$inclFeature_RIGHTOFFSET    = 0 if not $featuresToInclude =~ m/RIGHTOFFSET/ ;
			
		$inclFeature_TERMPATTERN    = 0 if not $featuresToInclude =~ m/TERMPATTERN/ ;
		$inclFeature_TRMPTRNCMPR    = 0 if not $featuresToInclude =~ m/TRMPTRNCMPR/ ;

    print $logFH "DEBUG:   featuresToExclude=[$featuresToExclude]\n" if $debug>=3 ;
    print $logFH "DEBUG:   featuresToInclude=>($inclFeature_FRSTCHR, $inclFeature_CHARCNT, $inclFeature_UCCNT, $inclFeature_NUMCNT, $inclFeature_LCCNT, $inclFeature_DSHCNT, $inclFeature_SLSHCNT, $inclFeature_PERIODCNT, $inclFeature_BLWRDCNT,  $inclFeature_BRNDWRDCNT,  $inclFeature_PLWRDCNT,  $inclFeature_PRODCATWRDCNT,  $inclFeature_PRODFEATWRDCNT, $inclFeature_PRODWRDCNT, $inclFeature_BPCWRDCNT, $inclFeature_BLWRD1CNT, $inclFeature_BRNDWRD1CNT, $inclFeature_PLWRD1CNT, $inclFeature_PRODCATWRD1CNT, $inclFeature_PRODFEATWRD1CNT, $inclFeature_PRODWRD1CNT, $inclFeature_BPCWRD1CNT, $inclFeature_BLWRDnCNT, $inclFeature_BRNDWRDnCNT, $inclFeature_PLWRDnCNT, $inclFeature_PRODCATWRDnCNT, $inclFeature_PRODFEATWRDnCNT, $inclFeature_PRODWRDnCNT, $inclFeature_BPCWRDnCNT, $inclFeature_GRWRDCNT, $inclFeature_ENWRDCNT, $inclFeature_SPWRDCNT, $inclFeature_STMDTOK, $inclFeature_LEFTOFFSET, $inclFeature_RIGHTOFFSET, $inclFeature_TERMPATTERN, $inclFeature_TRMPTRNCMPR)\n" if $debug>=4 ;

	} else {
		print $logFH "DEBUG:   featuresToExclude NOT DEFINED\n" if $debug>=3 ;
	}
	

  # sense the which features to exclude
	if (defined($featuresToExclude) and length($featuresToExclude)>1) {
		$exclFeature_FRSTCHR         = 1 if  $featuresToExclude =~ m/FRSTCHR/ ;
		$exclFeature_CHARCNT         = 1 if  $featuresToExclude =~ m/CHARCNT/ ;
		$exclFeature_UCCNT           = 1 if  $featuresToExclude =~ m/UCCNT/ ;
		$exclFeature_NUMCNT          = 1 if  $featuresToExclude =~ m/NUMCNT/ ;
		$exclFeature_LCCNT           = 1 if  $featuresToExclude =~ m/LCCNT/ ;
		$exclFeature_DSHCNT          = 1 if  $featuresToExclude =~ m/DSHCNT/ ;
		$exclFeature_SLSHCNT         = 1 if  $featuresToExclude =~ m/SLSHCNT/ ;
		$exclFeature_PERIODCNT       = 1 if  $featuresToExclude =~ m/PERIODCNT/ ;

		$exclFeature_BLWRDCNT        = 1 if  $featuresToExclude =~ m/BLWRDCNT/ ;
		$exclFeature_BRNDWRDCNT      = 1 if  $featuresToExclude =~ m/BRNDWRDCNT/ ;
		$exclFeature_PLWRDCNT        = 1 if  $featuresToExclude =~ m/PLWRDCNT/ ;
		$exclFeature_PRODCATWRDCNT   = 1 if  $featuresToExclude =~ m/PRODCATWRDCNT/ ;
		$exclFeature_PRODFEATWRDCNT  = 1 if  $featuresToExclude =~ m/PRODCATWRDCNT/ ;
		$exclFeature_PRODWRDCNT      = 1 if  $featuresToExclude =~ m/PRODWRDCNT/ ;
		$exclFeature_BPCWRDCNT       = 1 if  $featuresToExclude =~ m/BPCWRDCNT/ ;
		
		$exclFeature_BLWRD1CNT       = 1 if  $featuresToExclude =~ m/BLWRD1CNT/ ;
		$exclFeature_BRNDWRD1CNT     = 1 if  $featuresToExclude =~ m/BRNDWRD1CNT/ ;
		$exclFeature_PLWRD1CNT       = 1 if  $featuresToExclude =~ m/PLWRD1CNT/ ;
		$exclFeature_PRODCATWRD1CNT  = 1 if  $featuresToExclude =~ m/PRODCATWRD1CNT/ ;
		$exclFeature_PRODFEATWRD1CNT = 1 if  $featuresToExclude =~ m/PRODCATWRD1CNT/ ;
		$exclFeature_PRODWRD1CNT     = 1 if  $featuresToExclude =~ m/PRODWRD1CNT/ ;
		$exclFeature_BPCWRD1CNT      = 1 if  $featuresToExclude =~ m/BPCWRD1CNT/ ;
		$exclFeature_BLWRDnCNT       = 1 if  $featuresToExclude =~ m/BLWRDnCNT/ ;
		$exclFeature_BRNDWRDnCNT     = 1 if  $featuresToExclude =~ m/BRNDWRDnCNT/ ;
		$exclFeature_PLWRDnCNT       = 1 if  $featuresToExclude =~ m/PLWRDnCNT/ ;
		$exclFeature_PRODCATWRDnCNT  = 1 if  $featuresToExclude =~ m/PRODCATWRDnCNT/ ;
		$exclFeature_PRODFEATWRDnCNT = 1 if  $featuresToExclude =~ m/PRODCATWRDnCNT/ ;
		$exclFeature_PRODWRDnCNT     = 1 if  $featuresToExclude =~ m/PRODWRDnCNT/ ;
		$exclFeature_BPCWRDnCNT      = 1 if  $featuresToExclude =~ m/BPCWRDnCNT/ ;
	
	
		$exclFeature_GRWRDCNT       = 1 if  $featuresToExclude =~ m/GRWRDCNT/ ;
		$exclFeature_ENWRDCNT       = 1 if  $featuresToExclude =~ m/ENWRDCNT/ ;
		$exclFeature_SPWRDCNT       = 1 if  $featuresToExclude =~ m/SPWRDCNT/ ;
	
		$exclFeature_STMDTOK        = 1 if  $featuresToExclude =~ m/STMDTOK/ ;
	
		$exclFeature_RIGHTOFFSET    = 1 if  $featuresToExclude =~ m/RIGHTOFFSET/ ;
		$exclFeature_LEFTOFFSET     = 1 if  $featuresToExclude =~ m/LEFTOFFSET/ ;
	
		$exclFeature_TERMPATTERN    = 1 if  $featuresToExclude =~ m/TERMPATTERN/ ;
		$exclFeature_TRMPTRNCMPR    = 1 if  $featuresToExclude =~ m/TRMPTRNCMPR/ ;

    print $logFH "DEBUG:   featuresToExclude=[$featuresToExclude]\n" if $debug>=3 ;
    print $logFH "DEBUG:   featuresToExclude=>($exclFeature_FRSTCHR, $exclFeature_CHARCNT, $exclFeature_UCCNT, $exclFeature_NUMCNT, $exclFeature_LCCNT, $exclFeature_DSHCNT, $exclFeature_SLSHCNT, $exclFeature_PERIODCNT, $exclFeature_GRWRDCNT, $exclFeature_BLWRDCNT, $exclFeature_BRNDWRDCNT, $exclFeature_PLWRDCNT, $exclFeature_PRODCATWRDCNT, $exclFeature_PRODFEATWRDCNT, $exclFeature_BPCWRDCNT, $exclFeature_PRODWRDCNT, $exclFeature_BLWRD1CNT, $exclFeature_BRNDWRD1CNT, $exclFeature_PLWRD1CNT, $exclFeature_PRODCATWRD1CNT, $exclFeature_PRODFEATWRD1CNT, $exclFeature_BPCWRD1CNT, $exclFeature_PRODWRD1CNT, $exclFeature_BLWRDnCNT, $exclFeature_BRNDWRDnCNT, $exclFeature_PLWRDnCNT, $exclFeature_PRODCATWRDnCNT, $exclFeature_PRODFEATWRDnCNT, $exclFeature_BPCWRDnCNT, $exclFeature_PRODWRDnCNT, $exclFeature_ENWRDCNT, $exclFeature_SPWRDCNT, $exclFeature_STMDTOK, $exclFeature_RIGHTOFFSET, $exclFeature_LEFTOFFSET, $exclFeature_TERMPATTERN, $exclFeature_TRMPTRNCMPR)\n" if $debug>=4 ;

	} else {
		print $logFH "DEBUG:   featuresToExclude NOT DEFINED\n" if $debug>=3 ;
	}
	
	
	
	##########################################
	# Read in the dictionary file (if provided)
	my %TermTypes ;
	if ($dictFile) {
	  print $logFH "DEBUG: Read in the dictionary file into the DictionaryId array.\n" if $debug>=1 ;
	  open my $dictFH, "<$dictFile" or die "ERROR: Could not open dictFile[$dictFile]\n" ;
	  while (<$dictFH>) {
	    chomp ;
	    next if /^#/ ; # dispose of the header (or comment) record
	
			s/\\//g ; # Java property files escape space characters
			s/=([^=]+?)$/\t$1/ ; # replace the (last) '=' with a \tab
			my ($termName, $termType) = split(/\t/) ; # Java property files separate with '='
			die ("ERROR: empty dictionary record\n") if not defined $termName ;
			die ("ERROR: undefined termType for term[$termName] [$_].\n") if not defined $termType ;
			print $logFH "DEBUG:    (termName, termType) = ($termName, $termType) \n" if $debug>=6 ;
			$TermTypes{$termType}++ ;
			my @Tokens = split(/ /,$termName) ;
			# next if $#Tokens > 1 ;
			push @{$TermTypeTerm{$termType}}, lc($termName) ;
			$TermTypeTokenCount{'first'}{$termType}{lc($Tokens[0])}++ ;
			print $logFH "DEBUG:    first token[$Tokens[0] from termName[$termName] termType[$termType] $#Tokens $TermTypeTokenCount{'first'}{$termType}{lc($Tokens[0])}\n" if $debug>=5 and lc($Tokens[0]) =~ m/\bclassic\b/i ;
			$TermTypeTokenCount{'last'}{$termType}{lc($Tokens[$#Tokens])}++ ;
			print $logFH "DEBUG:    last token[$Tokens[$#Tokens] from termName[$termName] termType[$termType] $#Tokens $TermTypeTokenCount{'last'}{$termType}{lc($Tokens[$#Tokens])}\n" if $debug>=5 and lc($Tokens[$#Tokens]) =~ m/\bclassic\b/i ;
	
			for my $token (@Tokens) { # count each token in the term
				print $logFH "DEBUG:    any token[$token] from termName[$termName] termType[$termType] $#Tokens $TermTypeTokenCount{'any'}{$termType}{lc($token)}\n" if $debug>=5 and $token =~ m/\bclassic\b/i ;
				$TermTypeTokenCount{'any'}{$termType}{lc($token)}++ ;
			}
		}
	  close $dictFH ;
	  
	  for my $termType (keys %TermTypes) {
	  	print $logFH "DEBUG:    termType:$termType\n" if $debug>=3 ;
	  }
	}
	else {
	  print $logFH "DEBUG: No dictionary file provided\n" if $debug>=1 ;
	  $dictFile="" ;
	}
	
	
  if ($debug>=1) {
     print $logFH "DEBUG: processFile(inFile=$inFile outFile=$outFile logFile=$logFile dictFile=$dictFile debug=$debug verbose=$verbose performEOSDetection=$performEOSDetection performTokenization=$performTokenization performFeaturization=$performFeaturization includeDerivedFeatures=$includeDerivedFeatures includeGlobalFeatures=$includeGlobalFeatures includeSimpleBigramFeatures=$includeSimpleBigramFeatures featuresToInclude=$featuresToInclude featuresToExclude=$featuresToExclude doNotReportFeatureValues=$doNotReportFeatureValues noLabel=$noLabel)\n" ;
	}
	if ($debug>=2) {
	   print $logFH "DEBUG:   Perform end-of-sentence detection? [$performEOSDetection].\n" ;
	   print $logFH "DEBUG:   Perform tokenization? [$performTokenization].\n" ;
	   print $logFH "DEBUG:   Perform token featurization? [$performFeaturization]\n" ;
	   print $logFH "DEBUG:   Include derived features? [$includeDerivedFeatures]\n" ;
	   print $logFH "DEBUG:   include: ($inclFeature_FRSTCHR, $inclFeature_CHARCNT, $inclFeature_UCCNT, $inclFeature_NUMCNT, $inclFeature_LCCNT, $inclFeature_DSHCNT, $inclFeature_SLSHCNT, $inclFeature_PERIODCNT, $inclFeature_BLWRDCNT,  $inclFeature_BRNDWRDCNT,  $inclFeature_PLWRDCNT,  $inclFeature_PRODCATWRDCNT,  $inclFeature_PRODFEATWRDCNT, $inclFeature_PRODWRDCNT, $inclFeature_BPCWRDCNT, $inclFeature_BLWRD1CNT, $inclFeature_BRNDWRD1CNT, $inclFeature_PLWRD1CNT, $inclFeature_PRODCATWRD1CNT, $inclFeature_PRODFEATWRD1CNT, $inclFeature_PRODWRD1CNT, $inclFeature_BPCWRD1CNT, $inclFeature_BLWRDnCNT, $inclFeature_BRNDWRDnCNT, $inclFeature_PLWRDnCNT, $inclFeature_PRODCATWRDnCNT, $inclFeature_PRODFEATWRDnCNT, $inclFeature_PRODWRDnCNT, $inclFeature_BPCWRDnCNT, $inclFeature_GRWRDCNT, $inclFeature_ENWRDCNT, $inclFeature_SPWRDCNT, $inclFeature_STMDTOK, $inclFeature_LEFTOFFSET, $inclFeature_RIGHTOFFSET, $inclFeature_TERMPATTERN, $inclFeature_TRMPTRNCMPR)\n" ;
	   print $logFH "DEBUG:   exclude ($exclFeature_FRSTCHR, $exclFeature_CHARCNT, $exclFeature_UCCNT, $exclFeature_NUMCNT, $exclFeature_LCCNT, $exclFeature_DSHCNT, $exclFeature_SLSHCNT, $exclFeature_PERIODCNT, $exclFeature_GRWRDCNT, $exclFeature_BLWRDCNT, $exclFeature_BRNDWRDCNT, $exclFeature_PLWRDCNT, $exclFeature_PRODCATWRDCNT, $exclFeature_PRODFEATWRDCNT, $exclFeature_BPCWRDCNT, $exclFeature_PRODWRDCNT, $exclFeature_BLWRD1CNT, $exclFeature_BRNDWRD1CNT, $exclFeature_PLWRD1CNT, $exclFeature_PRODCATWRD1CNT, $exclFeature_PRODFEATWRD1CNT, $exclFeature_BPCWRD1CNT, $exclFeature_PRODWRD1CNT, $exclFeature_BLWRDnCNT, $exclFeature_BRNDWRDnCNT, $exclFeature_PLWRDnCNT, $exclFeature_PRODCATWRDnCNT, $exclFeature_PRODFEATWRDnCNT, $exclFeature_BPCWRDnCNT, $exclFeature_PRODWRDnCNT, $exclFeature_ENWRDCNT, $exclFeature_SPWRDCNT, $exclFeature_STMDTOK, $exclFeature_RIGHTOFFSET, $exclFeature_LEFTOFFSET, $exclFeature_TERMPATTERN, $exclFeature_TRMPTRNCMPR)\n" ;
	}
	
	
	
	#############################################################
	# For each text string perform the requested transformations
	my $lineNum=0 ;
	while (<$inputFH>) {
	  $lineNum++ ;
	
	  chomp($_) ;
	  print $logFH "DEBUG: raw[$_] (minus possible newline)\n" if $debug>=2 ;
	  next if length($_) <= 0 ;
	  s/[ ]*<p>//gi ; # remove any paragraph markers and previous space
	  
	  if (m/^#/) {next; } # in the future the first column will be optionally started with a # symbol to indicate that it contains names for each of the column
	
	  my @TextRecord = split (/\t/) ;
	  my $textString = $TextRecord[0] ; # first element
	  my $otherElements = "" ;
	  for my $i (1 .. $#TextRecord) {$otherElements .= "\t" if $otherElements; $otherElements .= $TextRecord[$i]} 
	  print $logFH "DEBUG:   elements[$textString]\t[$otherElements]\n" if $debug>=3 ;
	
	  die "ERROR: a TextString is too long [" . length($textString) . "> $maxTextStringChars] in [$textString]\n" if not length($textString) < $maxTextStringChars ;
	  die "ERROR: a TextString is too short [" . length($textString) . "< $minTextStringChars] in [$textString]\n" if not length($textString) > $minTextStringChars ;
	  print "WARNING: a TextString starts with a whitespace at lineNum[$lineNum] i.e. [$textString]\n" if $debug>=1 and substr($textString,  0, 1) =~ m/\s/ ;
	  print "WARNING: a TextString ends with a whitespace at lineNum[$lineNum] i.e. [$textString]\n"   if $debug>=1 and substr($textString, -1, 1) =~ m/\s/ ;
	
	
	  # perform the end-of-sentence detection (if requested)
	  my $eosTextString = $textString ;
	  if ($performEOSDetection) {
			$eosTextString = sentenceBoundaryDetector($textString) ;
			print $logFH "DEBUG: eosOut:[$eosTextString]\n" if $debug>=2 ;
		}
	
	  # perform the tokenization (if requested)
	  my $tokenizedTextString = $eosTextString ;
	  if ($performTokenization) {
			$tokenizedTextString = textTokenizer($eosTextString) ;
			print $logFH "DEBUG: tokOut:[$tokenizedTextString]\n" if $debug>=2 ;
		}

	  if ($performDetokenization) {
			$tokenizedTextString = textDetokenizer($eosTextString) ;
			print $logFH "DEBUG: detokOut:[$tokenizedTextString]\n" if $debug>=2 ;
		}
	
	  # perform the token featurization (if requested)
	  if ($performFeaturization) { 
			my @labeledTokens = textTokenLabelDecorator($tokenizedTextString) ;
			my @TokenFeaturesRaw = textTokenFeaturizer(@labeledTokens) ;
			my @TokenFeaturesDerived ;
			@TokenFeaturesDerived = derivedFeatures(@TokenFeaturesRaw) if ($includeDerivedFeatures) ;
	
	  	# join and print the results
	  	for my $i (0 .. $#labeledTokens) {
	  		if (not defined $labeledTokens[$i] or length($labeledTokens[$i])<1) {
	     		  print $outputFH "\n" ;
	     		  next ;
	  		}
				my ($tokenClean, $label) = split($featSep, $labeledTokens[$i]) ;
	  		my $rawFeatures = $TokenFeaturesRaw[$i] ;
	  		my $derivedFeatures = $TokenFeaturesDerived[$i] ;
	  		$derivedFeatures = "" if not defined $derivedFeatures ;
	
	      my $globalFeatures = "" ;
	      $globalFeatures .= " $otherElements" if $includeGlobalFeatures ;
	      $globalFeatures =~ s/ / GLOBAL_/g ;
	
	      my $simpleBigramFeatures ;
	      if ($includeSimpleBigramFeatures) {
	      	my @rawFeaturesList = split(/ /, $rawFeatures) ;
	      	for my $i (0 .. $#rawFeaturesList) {
	      	  for my $j (1 .. $#rawFeaturesList) {
	      	  	next if $i==$j ;
	      	  	$simpleBigramFeatures .= $featSep if defined $simpleBigramFeatures ;
	      	  	$simpleBigramFeatures .= "$rawFeaturesList[$i]+$rawFeaturesList[$j]" ;
	      	  }
	      	}
	      } 
				my $sepLabel = $featSep . $label ; $sepLabel = "" if $noLabel ; # sometimes no label is provided
				print $outputFH $tokenClean . $featSep . $rawFeatures . $globalFeatures ;
				print $outputFH $featSep . $derivedFeatures       if $includeDerivedFeatures ;
				print $outputFH $featSep . $simpleBigramFeatures  if $includeSimpleBigramFeatures ;
	  		print $outputFH $sepLabel . "\n" ;
	  	} # for
	  }
	  else {
	  	print $outputFH $tokenizedTextString ;
			for my $i (1 .. $#TextRecord) {
	  		print $outputFH "\t$TextRecord[$i]"
	  	}
	    print $outputFH "\n" ;
	  }
	  
			
	}
	
	# Exit gracefully
	close $inputFH  unless $isSTDIN ;
	close $outputFH unless $isSTDOUT ;
	close $logFH    unless $isSTDOUTlog ;

}






###############################################################################
#########################         SUBROUTINES         ##########################
###############################################################################




#############################################################
############				 DERIVED FEATURES					 ##############
#############################################################
# return an array of the featurs derived for a token

sub derivedFeatures(@) {

  my @TokensFeatures = @_ ;
  if ($debug>=3) {print $logFH "DEBUG: derivedFeatures("; print @TokensFeatures; print ")[$#TokensFeatures]\n";}

  # populate the empty featureSet needed for the first and last token.
  my $emptyFeatures = $TokensFeatures[0] ;
  $emptyFeatures =~ s/_[\w]*/_0/g ; # assume MALLET-style features
  print $logFH "DEBUG:    emptyFeatures[$emptyFeatures]\n" if $debug>=3 ;

  my @TokenFeaturesDerived	 ;
  for my $i (0 .. $#TokensFeatures) {
		
     # test for empty string (end of sentence) and debug
     my @tokensFeatures = split($featSep, $TokensFeatures[$i]) ;
     print $logFH "DEBUG:   token[$i]: [@tokensFeatures]\n" if $debug>=3 ;
     if (not defined $tokensFeatures[0]) {push @TokenFeaturesDerived, ""; next; }
   
     # add derived features based on the previous token(s).
     my $featsPrev = $emptyFeatures ;
     $featsPrev = $TokensFeatures[$i-1] if $i!=0 and length($TokensFeatures[$i-1])>0 ;
     $featsPrev =~ s/_/p_/g ; # assume MALLET-style features
     my @prevTokFeatures = split($featSep, $featsPrev) ;
     if ($debug>=3) {print $logFH "DEBUG:    previous token[$i]'s features: [$#prevTokFeatures] [$featsPrev] ["; print length($TokensFeatures[$i-1]); print "]\n";}
   
     # add derived features based on the subsequent token(s).
     my $featsSbsq = $emptyFeatures ;
     $featsSbsq = $TokensFeatures[$i+1] if $i!=$#TokensFeatures and length($TokensFeatures[$i+1])>0 ;
     $featsSbsq =~ s/_/s_/g ; # assume MALLET-style features
     my @sbsqTokFeatures = split($featSep, $featsSbsq) ;
     if ($debug>=3) {print $logFH "DEBUG:    subsequent token[$i]'s features: [$#sbsqTokFeatures] [$featsSbsq] ["; print length($TokensFeatures[$i+1]); print "]\n";}
   
     my $drvdFeaturesString ;
     for my $feature(@prevTokFeatures) {
       	$drvdFeaturesString .= $featSep if defined $drvdFeaturesString ;
       	$drvdFeaturesString .= $feature ;
     }
     for my $feature(@sbsqTokFeatures) {
       	$drvdFeaturesString .= $featSep if defined $drvdFeaturesString ;
       	$drvdFeaturesString .= $feature ;
     }
   
     push @TokenFeaturesDerived, $drvdFeaturesString ;
  }

  return @TokenFeaturesDerived ;
}




#############################################################
############	           FEATURIZE             ##############
#############################################################

# Take a whitespace separated (and </s> terminated) linguistic passage, transpose its tokens, and add features.
sub textTokenFeaturizer (@) {

   print $logFH "DEBUG: textTokenFeaturizer(@_)\n" if $debug>=3 ;
   my @tokenString ;
   my $stringifiedText ; # a reconstituted whitespace-separated version of the string.
   my $stringifiedTextNorml ;
   for my $i (0 .. $#_) { # for each token
     my $record = $_[$i] ;
     my ($token, $label) = split($featSep, $record) ;
     $token="" if not defined $token ;
  	 print $logFH "DEBUG:     i[$i] token[$token] label[$label]\n" if $debug>=4 ;
  	 push @tokenString, $token ;
  	 $stringifiedText .= " " if defined $stringifiedText ; # 
  	 $token="" if not defined $token ;
  	 $stringifiedText .= $token ;
  	 $stringifiedTextNorml .= " " if defined  $stringifiedTextNorml ;
  	 $stringifiedTextNorml .= normalizeToken($token) ;
   }
   $stringifiedText = trim($stringifiedText) ;
   print $logFH "DEBUG:   stringifiedText[$stringifiedText]\n" if $debug>=3 ;
   print $logFH "DEBUG:   stringifiedTextNorml[$stringifiedTextNorml]\n" if $debug>=3 ;


   # for future dictionary-lookup detection
 	 for my $termType (keys %TermTypeTerm) {
      # Next, now that we have a normalized string and a mapping to the original string, find the matches
      print $logFH "DEBUG:     find products in normlString[$stringifiedTextNorml] for termType[$termType]\n" if $debug >= 5 ;

      #my $found = find_all($stringifiedTextNorml, @{$TermTypeTerm{$termType}}) ;
      # fix AhoCorasick
      my $found = 0 ;
      if (not $found) {
        print $logFH "DEBUG:     no terms found in text_item.\n" if $debug>=5 ;
        next ;
      } else {
        my @charPositions = keys %$found ;
        my $charPosCount=$#charPositions + 1 ;
        print $logFH "DEBUG:     found $charPosCount product terms found in text_item.\n" if $debug>=4 ;
      }

   }


   # 
   my @featurizedTokens ;
   for my $offset (0 .. $#tokenString) {

   my $record = $_[$offset] ;
	 if (length($record)<=0) { # empty tokens result in ...
		 push @featurizedTokens, "" ;
		 next ;
	 }
		
	 my ($tokenClean, $label) = split($featSep, $record) ;
	 my $tokenCleanLc = lc($tokenClean) ;
	 print $logFH "DEBUG:      tokenCleanLc=$tokenCleanLc\n" if $debug>=3 ;

	 # Compose the feature space
	 # In the future these tests will be specified in an input file with regular expressions

   # What is the offset
   my $leftOffset = $offset ;
   my $rightOffset = $#_ - $offset ;
    
    
   # first char is upper case?
   my $fcUC  = 0 ;	$fcUC=1  if $tokenClean !~ m/^[^A-Z]/ ;

   # first char is a number?
	 my $fcNum = 0 ; $fcNum=1 if $tokenClean !~ m/^[^0-9]/ ;

   # first char is lower case?
	 my $fclc  = 0 ; $fclc=1  if $tokenClean !~ m/^[^a-z]/ ;
		

		# number of characters
		my $chars = length($tokenClean) ;
		$chars = "max13" if $chars >=13 ; # large category ceiling
	
	  # number of uppercase letters
		my $ucLs = ($tokenClean =~tr/[^A-Z]//) ; # count the number of surviving chars. Use () to not clobber @_.
		$ucLs = "max05" if $ucLs >= 5 ;
		# print STDOUT "\n[$tokenClean => $ucLs]\n" ;
			
	  # number of lowercase letters
		my $lcLs = ($tokenClean =~tr/[^a-z]//) ; # count the number of surviving chars. Use () to not clobber @_.
		$lcLs = "max11" if $lcLs >= 11 ; # fewer than 0.5% of tokens are longer, but some problematic tokens like URLs are longer than 11.
	
		# number of number characters
		my $nums = ($tokenClean =~tr/[^0-9]//) ; # count the number of surviving chars
	  $nums = 906 if $nums>=6 ; # large category ceiling
			
		# number of dashes
		my $dashes = ($tokenClean =~tr/[^\-]//) ; # count the number of surviving chars
		$dashes = 902 if $dashes >=2 ; # large category ceiling
	
		# number of slashes
		my $slashes = ($tokenClean =~tr/[^\/]//) ; # count the number of surviving chars
		$slashes = 902 if $slashes >=2 ; # large category ceiling
	
		# number of periods
		my $periods = ($tokenClean =~tr/[^\.]//) ; # count the number of surviving chars
		$periods = 902 if $periods >=2 ; # large category ceiling
	
	    # tokenPattern
		my $TERMPATTERN = $tokenClean ;
		$TERMPATTERN =~ s/[A-Z]/A/g ;
		$TERMPATTERN =~ s/[a-z]/a/g ;
		$TERMPATTERN =~ s/[\d]/0/g ;
		$TERMPATTERN =~ s/[\W]/-/g ;
		# print STDOUT "\n[$tokenClean => $TERMPATTERN]\n" ;
			
		my $TRMPTRNCMPR = $TERMPATTERN ;
		$TRMPTRNCMPR =~ s/A+/A/g ;
		$TRMPTRNCMPR =~ s/a+/a/g ;
		$TRMPTRNCMPR =~ s/0+/0/g ;
		$TRMPTRNCMPR =~ s/-+/-/g ;
	
	
	  # is this token found in the dictionary
	  my $dictBLCNT        = defined $TermTypeTokenCount{'any'}{BLACKLISTED}{$tokenCleanLc} ? compressFeature($TermTypeTokenCount{'any'}{BLACKLISTED}{$tokenCleanLc}) : 0 ;
	  my $dictBNCNT        = defined $TermTypeTokenCount{'any'}{BRANDNAME}{$tokenCleanLc}   ? compressFeature($TermTypeTokenCount{'any'}{BRANDNAME}{$tokenCleanLc}) : 0 ;
	  my $dictPLCNT        = defined $TermTypeTokenCount{'any'}{PRODLINE}{$tokenCleanLc}    ? compressFeature($TermTypeTokenCount{'any'}{PRODLINE}{$tokenCleanLc}) : 0 ;
	  my $dictProdCatCNT   = defined $TermTypeTokenCount{'any'}{PRODUCTCAT}{$tokenCleanLc}  ? compressFeature($TermTypeTokenCount{'any'}{PRODUCTCAT}{$tokenCleanLc}) : 0 ;
	  my $dictProdFeatCNT  = defined $TermTypeTokenCount{'any'}{PRODUCTFEAT}{$tokenCleanLc} ? compressFeature($TermTypeTokenCount{'any'}{PRODUCTFEAT}{$tokenCleanLc}) : 0 ;
	  my $dictPRODCNT      = defined $TermTypeTokenCount{'any'}{PRODUCT}{$tokenCleanLc}     ? compressFeature($TermTypeTokenCount{'any'}{PRODUCT}{$tokenCleanLc}) : 0 ;
	  my $dictBPCCNT       = defined $TermTypeTokenCount{'any'}{BRANDEDPC}{$tokenCleanLc}   ? compressFeature($TermTypeTokenCount{'any'}{BRANDEDPC}{$tokenCleanLc}) : 0 ;
	
	  # is this token found in the dictionary (as a first token)
	  my $dictBL1CNT       = defined $TermTypeTokenCount{'first'}{BLACKLISTED}{$tokenCleanLc} ? compressFeature($TermTypeTokenCount{'first'}{BLACKLISTED}{$tokenCleanLc}) : 0 ;
	  my $dictBN1CNT       = defined $TermTypeTokenCount{'first'}{BRANDNAME}{$tokenCleanLc}   ? compressFeature($TermTypeTokenCount{'first'}{BRANDNAME}{$tokenCleanLc}) : 0 ;
	  my $dictPL1CNT       = defined $TermTypeTokenCount{'first'}{PRODLINE}{$tokenCleanLc}    ? compressFeature($TermTypeTokenCount{'first'}{PRODLINE}{$tokenCleanLc}) : 0 ;
	  my $dictProdCat1CNT  = defined $TermTypeTokenCount{'first'}{PRODUCTCAT}{$tokenCleanLc}  ? compressFeature($TermTypeTokenCount{'first'}{PRODUCTCAT}{$tokenCleanLc}) : 0 ;
	  my $dictProdFeat1CNT = defined $TermTypeTokenCount{'first'}{PRODUCTFEAT}{$tokenCleanLc} ? compressFeature($TermTypeTokenCount{'first'}{PRODUCTFEAT}{$tokenCleanLc}) : 0 ;
	  my $dictPROD1CNT     = defined $TermTypeTokenCount{'first'}{PRODUCT}{$tokenCleanLc}     ? compressFeature($TermTypeTokenCount{'first'}{PRODUCT}{$tokenCleanLc}) : 0 ;
	  my $dictBPC1CNT      = defined $TermTypeTokenCount{'first'}{BRANDEDPC}{$tokenCleanLc}   ? compressFeature($TermTypeTokenCount{'first'}{BRANDEDPC}{$tokenCleanLc}) : 0 ;
	
	  # is this token found in the dictionary (as a last token)
	  my $dictBLnCNT       = defined $TermTypeTokenCount{'last'}{BLACKLISTED}{$tokenCleanLc} ? compressFeature($TermTypeTokenCount{'last'}{BLACKLISTED}{$tokenCleanLc}) : 0 ;
	  my $dictBNnCNT       = defined $TermTypeTokenCount{'last'}{BRANDNAME}{$tokenCleanLc}   ? compressFeature($TermTypeTokenCount{'last'}{BRANDNAME}{$tokenCleanLc}) : 0 ;
	  my $dictPLnCNT       = defined $TermTypeTokenCount{'last'}{PRODLINE}{$tokenCleanLc}    ? compressFeature($TermTypeTokenCount{'last'}{PRODLINE}{$tokenCleanLc}) : 0 ;
	  my $dictProdCatnCNT  = defined $TermTypeTokenCount{'last'}{PRODUCTCAT}{$tokenCleanLc}  ? compressFeature($TermTypeTokenCount{'last'}{PRODUCTCAT}{$tokenCleanLc}) : 0 ;
	  my $dictProdFeatnCNT = defined $TermTypeTokenCount{'last'}{PRODUCTFEAT}{$tokenCleanLc} ? compressFeature($TermTypeTokenCount{'last'}{PRODUCTFEAT}{$tokenCleanLc}) : 0 ;
	  my $dictPRODnCNT     = defined $TermTypeTokenCount{'last'}{PRODUCT}{$tokenCleanLc}     ? compressFeature($TermTypeTokenCount{'last'}{PRODUCT}{$tokenCleanLc}) : 0 ;
	  my $dictBPCnCNT      = defined $TermTypeTokenCount{'last'}{BRANDEDPC}{$tokenCleanLc}   ? compressFeature($TermTypeTokenCount{'last'}{BRANDEDPC}{$tokenCleanLc}) : 0 ;
	
	  my $dictGWCNT        = defined $TermTypeTokenCount{'any'}{GRAMMATICALWORD}{$tokenCleanLc}   ? compressFeature($TermTypeTokenCount{'any'}{GRAMMATICALWORD}{$tokenCleanLc}) : 0 ;
	  my $enComWrdCNT      = defined $TermTypeTokenCount{'any'}{ENCOMMONWORD}{$tokenCleanLc}   ? compressFeature($TermTypeTokenCount{'any'}{ENCOMMONWORD}{$tokenCleanLc}) : 0 ;
	  my $spComWrdCNT      = defined $TermTypeTokenCount{'any'}{SPCOMMONWORD}{$tokenCleanLc}   ? compressFeature($TermTypeTokenCount{'any'}{SPCOMMONWORD}{$tokenCleanLc}) : 0 ;
	
	
	  # In the future additional term types will be tested against....
	  my $stmdtok = $stemmer->stem($tokenClean) ;
	
	  # All feature values determined. Now commit them to the feature string.
	  my $featureTupleStr = "" ;
	
	  if (not $doNotReportFeatureValues) {		
		# add a feature and a separator

  		if ($inclFeature_FRSTCHR and not $exclFeature_FRSTCHR) {
	   		if ($fcUC)       { $featureTupleStr .= "FRSTCHR_UC"
	   		} elsif ($fcNum) { $featureTupleStr .= "FRSTCHR_num"    
	   		} elsif ($fclc)  { $featureTupleStr .= "FRSTCHR_lc"    
	   		} else           { $featureTupleStr .= "FRSTCHR_oth" }
 			}

			$featureTupleStr .= "${featSep}CHARCNT_$chars"     if (defined $chars   and $inclFeature_CHARCNT   and not $exclFeature_CHARCNT) ;
			$featureTupleStr .= "${featSep}UCCNT_$ucLs"        if (defined $ucLs    and $inclFeature_UCCNT     and not $exclFeature_UCCNT) ;
			$featureTupleStr .= "${featSep}NUMCNT_$nums"       if (defined $nums    and $inclFeature_NUMCNT    and not $exclFeature_NUMCNT) ;
			$featureTupleStr .= "${featSep}LCCNT_$lcLs"        if (defined $lcLs    and $inclFeature_LCCNT     and not $exclFeature_LCCNT) ;
			$featureTupleStr .= "${featSep}DSHCNT_$dashes"     if (defined $dashes  and $inclFeature_DSHCNT    and not $exclFeature_DSHCNT) ;
			$featureTupleStr .= "${featSep}SLSHCNT_$slashes"   if (defined $slashes and $inclFeature_SLSHCNT   and not $exclFeature_SLSHCNT) ;
			$featureTupleStr .= "${featSep}PERIODCNT_$periods" if (defined $periods and $inclFeature_PERIODCNT and not $exclFeature_PERIODCNT) ;
			$featureTupleStr .= "${featSep}TERMPATTERN_$TERMPATTERN" if (defined $TERMPATTERN and $inclFeature_TERMPATTERN     and not $exclFeature_TERMPATTERN) ;
			$featureTupleStr .= "${featSep}TRMPTRNCMPR_$TRMPTRNCMPR" if (defined $TERMPATTERN and $inclFeature_TRMPTRNCMPR and not $exclFeature_TRMPTRNCMPR) ;

			$featureTupleStr .= "${featSep}BRNDWRDCNT_$dictBNCNT"           if (defined $dictBNCNT       and $inclFeature_BRNDWRDCNT     and not $exclFeature_BRNDWRDCNT) ;
			$featureTupleStr .= "${featSep}BLACKLISTED_$dictBLCNT"          if (defined $dictBLCNT       and $inclFeature_BLWRDCNT       and not $exclFeature_BLWRDCNT) ;
			$featureTupleStr .= "${featSep}PLWRDCNT_$dictPLCNT"             if (defined $dictPLCNT       and $inclFeature_PLWRDCNT       and not $exclFeature_PLWRDCNT) ;
			$featureTupleStr .= "${featSep}PRODCATWRDCNT_$dictProdCatCNT"   if (defined $dictProdCatCNT  and $inclFeature_PRODCATWRDCNT  and not $exclFeature_PRODCATWRDCNT) ;
			$featureTupleStr .= "${featSep}PRODFEATWRDCNT_$dictProdFeatCNT" if (defined $dictProdFeatCNT and $inclFeature_PRODFEATWRDCNT and not $exclFeature_PRODFEATWRDCNT) ;
			$featureTupleStr .= "${featSep}PRODWRDCNT_$dictPRODCNT"         if (defined $dictPRODCNT     and $inclFeature_PRODWRDCNT     and not $exclFeature_PRODWRDCNT) ;
			$featureTupleStr .= "${featSep}BPCWRDCNT_$dictBPCCNT"           if (defined $dictBPCCNT      and $inclFeature_BPCWRDCNT      and not $exclFeature_BPCWRDCNT) ;

			$featureTupleStr .= "${featSep}BRNDWRD1CNT_$dictBN1CNT"           if (defined $dictBN1CNT       and $inclFeature_BRNDWRD1CNT     and not $exclFeature_BRNDWRD1CNT) ;
			$featureTupleStr .= "${featSep}BLACKLISTED1_$dictBL1CNT"          if (defined $dictBL1CNT       and $inclFeature_BLWRD1CNT       and not $exclFeature_BLWRD1CNT) ;
			$featureTupleStr .= "${featSep}PLWRD1CNT_$dictPL1CNT"             if (defined $dictPL1CNT       and $inclFeature_PLWRD1CNT       and not $exclFeature_PLWRD1CNT) ;
			$featureTupleStr .= "${featSep}PRODCATWRD1CNT_$dictProdCat1CNT"   if (defined $dictProdCat1CNT  and $inclFeature_PRODCATWRD1CNT  and not $exclFeature_PRODCATWRD1CNT) ;
			$featureTupleStr .= "${featSep}PRODFEATWRD1CNT_$dictProdFeat1CNT" if (defined $dictProdFeat1CNT and $inclFeature_PRODFEATWRD1CNT and not $exclFeature_PRODFEATWRD1CNT) ;
			$featureTupleStr .= "${featSep}PRODWRD1CNT_$dictPROD1CNT"         if (defined $dictPROD1CNT     and $inclFeature_PRODWRD1CNT     and not $exclFeature_PRODWRD1CNT) ;
			$featureTupleStr .= "${featSep}BPCWRD1CNT_$dictBPCCNT"            if (defined $dictBPCCNT       and $inclFeature_BPCWRD1CNT      and not $exclFeature_BPCWRD1CNT) ;

			$featureTupleStr .= "${featSep}BRNDWRDnCNT_$dictBNnCNT"           if (defined $dictBNnCNT       and $inclFeature_BRNDWRDnCNT     and not $exclFeature_BRNDWRDnCNT) ;
			$featureTupleStr .= "${featSep}BLACKLISTEDn_$dictBLnCNT"          if (defined $dictBLnCNT       and $inclFeature_BLWRDnCNT       and not $exclFeature_BLWRDnCNT) ;
			$featureTupleStr .= "${featSep}PLWRDnCNT_$dictPLnCNT"             if (defined $dictPLnCNT       and $inclFeature_PLWRDnCNT       and not $exclFeature_PLWRDnCNT) ;
			$featureTupleStr .= "${featSep}PRODCATWRDnCNT_$dictProdCatnCNT"   if (defined $dictProdCatnCNT  and $inclFeature_PRODCATWRDnCNT  and not $exclFeature_PRODCATWRDnCNT) ;
			$featureTupleStr .= "${featSep}PRODFEATWRDnCNT_$dictProdFeatnCNT" if (defined $dictProdFeatnCNT and $inclFeature_PRODFEATWRDnCNT and not $exclFeature_PRODFEATWRDnCNT) ;
			$featureTupleStr .= "${featSep}PRODWRDnCNT_$dictPRODnCNT"         if (defined $dictPRODnCNT     and $inclFeature_PRODWRDnCNT     and not $exclFeature_PRODWRDnCNT) ;
			$featureTupleStr .= "${featSep}BPCWRDnCNT_$dictBPCCNT"            if (defined $dictBPCnCNT      and $inclFeature_BPCWRDnCNT      and not $exclFeature_BPCWRDnCNT) ;

			$featureTupleStr .= "${featSep}GRWRDCNT_$dictGWCNT"             if (defined $dictGWCNT       and $inclFeature_GRWRDCNT       and not $exclFeature_GRWRDCNT) ;
			$featureTupleStr .= "${featSep}ENWRDCNT_$enComWrdCNT"           if (defined $enComWrdCNT     and $inclFeature_ENWRDCNT       and not $exclFeature_ENWRDCNT) ;
			$featureTupleStr .= "${featSep}SPWRDCNT_$spComWrdCNT"           if (defined $spComWrdCNT     and $inclFeature_SPWRDCNT       and not $exclFeature_SPWRDCNT) ;

			$featureTupleStr .= "${featSep}STMDTOK_$stmdtok"       if (defined $stmdtok and $inclFeature_STMDTOK and not $exclFeature_STMDTOK) ;
			
			$featureTupleStr .= "${featSep}LEFTOFF_$leftOffset"    if (defined $leftOffset and $inclFeature_LEFTOFFSET and not $exclFeature_LEFTOFFSET) ;
			$featureTupleStr .= "${featSep}RIGHTOFF_$rightOffset"  if (defined $rightOffset and $inclFeature_RIGHTOFFSET and not $exclFeature_RIGHTOFFSET) ;
    }

    print $logFH "DEBUG:     featureTupleStr[$tokenClean][$featureTupleStr]\n" if $debug>=3 ;
    push @featurizedTokens, $featureTupleStr ;

  }

  print $logFH "DEBUG:    end of textTokenFeaturizer()\n" if $debug>=4 ;
  return @featurizedTokens ;

}








#############################################################
############	        LABEL DECORATOR          ##############
#############################################################

# Transforms a whiteSpace separated linguistic passage into transposed tokens and includes the labels.
sub textTokenLabelDecorator ($) {
	
  local($_) = @_;  # looks a lot like my
  print $logFH "DEBUG: textTokenLabelDecorator($_).\n" if $debug>=2 ;
  my @labeledTokens ;

  my $tokLabel = $Olabel ; # initialize
  my $annoMentionType = "" ; # the current mention's annotated type - if provided. Empty when outside of a mention.

  # Process each token in the string separately
  for my $tokenRaw (split (/[ ]+/)) {
		
	if ($tokenRaw =~ /<[\\]*[s|p]>/i) { # specialCases end-of-sentence and end-of-paragraph results in a newline
	   push @labeledTokens, "" ;
	   next ;
	}

	my $tokenClean = $tokenRaw ; # it will be "Clean" after we remove any present markup
	my $tokenLabelString = "" ; # it will be "Clean" after we remove any present markup

	# Does the token begin an annotation?
	if ($tokenClean =~ s/^\[\[//) {  # remove the annotation also
		print $logFH "DEBUG:    begin of annotation at [$tokenClean].\n" if $debug>=4 ;

		# Does the token also end an annotation?
		my $alsoEnd_=0 ;
   	$alsoEnd_=1 if ($tokenClean =~ s/\]\]$//) ; # remove the end demarcator along the way

		my $labeledMention_=0 ;
   	$labeledMention_=1 if ($tokenClean =~ m/\|/) ;
		if ($labeledMention_) { # 
			($annoMentionType, $tokenClean) = split (/[ ]*\|[ ]*/, $tokenClean) ;
			$annoMentionType = "-" . $annoMentionType ; # prepend a dash to separate the BIO from the LABEL
			print $logFH "DEBUG:     a labeledMention ($annoMentionType, $tokenClean)\n" if $debug>=4 ;
		}

		print $logFH "DEBUG:     at LXK8s90 tokenClean=$tokenClean  annoMentionType=$annoMentionType\n" if $debug>=4 ;
		# commit the label
		$tokenLabelString = $Blabel . $annoMentionType ;

		$tokLabel=$Ilabel ; # assume that the annotated mention is multi-token
		if ($alsoEnd_) {
			$tokLabel=$Olabel ;
			$annoMentionType="" ; # reset the type
		}
	}
	# Does the token end an annotation?
	elsif ($tokenClean =~ s/\]\]$//) {
		print $logFH "DEBUG:    begin of annotation at [$tokenClean] [$tokLabel] [$annoMentionType].\n" if $debug>=3 ;
		$tokenLabelString = $tokLabel . $annoMentionType ;
		$annoMentionType="" ; # reset the type
		$tokLabel=$Olabel ; # the next token is "O"utside (unless it "B"egins a new mention)
	}
	else {
		print $logFH "DEBUG:    no annotation at [$tokenClean].\n" if $debug>=4 ;
		$tokenLabelString = $tokLabel . $annoMentionType ;
	}

	# commit the label
	print $logFH "DEBUG:    tokenClean=[$tokenClean] featSet[$featSep] tokenLabelString[$tokenLabelString]\n" if $debug>=4 ;

	push @labeledTokens, "$tokenClean${featSep}$tokenLabelString" ;
  }
  
  print $logFH "DEBUG:    end of textTokenLabelDecorator()\n" if $debug>=4 ;
  return @labeledTokens ;

}





#############################################################
############					 EOS DETECTOR		        ###############
#############################################################
# A simple end-of-sentence-detector (inserts a <\s> between detected "sentences")
#
# For now, it is nearly identical to textTokenizer()>
# 
# TODO:

sub sentenceBoundaryDetector ($) {

  local($_) = shift(@_) ; # get the parameter
  die ("ERROR: asked to demarcate end-of-sentences on an undefined string.\n") if not defined $_ ;

  print $logFH "DEBUG:  sentenceBoundaryDetector($_)\n" if $debug>=3 ;

  # force a end-of-sentence as the beginning
  s/$/ <\/s> / ;

  s/\]\]\. /]] _DoIrEp <\/s> /g ;

  # Annotated segments CANNOT contain end-of-sentences - so hide tell-tale chars. Only helps when processing annotated data.
  s/\[\[([^\]]+?)\.(.*?)\]\]/[[$1_DoIrEp$2]]/g ;  
  s/\[\[([^\]]+?)\!(.*?)\]\]/[[$1_MaLcXe$2]]/g ;  
  s/\[\[([^\]]+?)\?(.*?)\]\]/[[$1_KrAmQ$2]]/g ;  

  print $logFH "DEBUG: hals88   [$_\n" if $debug>=4 ;

  # identify tokens with embedded period characters  
  s/ (ph)\.(d)\./ $1_DoIrEp$2_DoIrEp /gi ;  # Ph.D.
  s/ (al)\./ $1_DoIrEp /gi ;  # et al.
  s/ ([d|m][r|s])\./ $1_DoIrEp/gi ;  # Mr., Ms. Mrs. and Dr., Drs.
  s/ (bros|corp|dia|etc|gen|inc|vol|vs|pr|phd|wt)\./ $1_DoIrEp/gi ;  # e.g.  ... Super Bros. Brawl, ...  vol. 1 had ... Sony Inc. is ...
  s/ (\d+)([ ]*)(ft|in|kg|lbs|lb|pc|oz)\./ $1$2$3_DoIrEp/gi ;  # 6ft. 17 kg.
  s/([\w])\.([\w])\.([\w])\./$1_DoIrEp$2_DoIrEp$3_DoIrEp/g ; # e.g.  ... cleverly titled [Flesh_M.U.S.C.L.E._Poster], is ... 
  s/\.\.\./_DoIrEp_DoIrEp_DoIrEp/g ; # e.g.  ... elipsis

  print $logFH "DEBUG: x9as7d   [$_\n" if $debug>=4 ;

	s/\.\./_DoIrEp_DoIrEp/g ; # any two consecutive periods
  s/([^ ])\.([^ ])/$1_DoIrEp$2/g ;
  # s/\.([^\.])\. /.$1_DoIrEp /g ; # any two periods with one intervening (real) character (e.g. i.e. )

  # PRODUCT-DOMAIN - near the end
  # identify tokens with embedded exclamation characters  
  s/ahoo\! /ahoo_MaLcXe /g ;
  s/rarara\!\! /rarara_MaLcXe_MaLcXe /g ;

  print $logFH "DEBUG: IDlss81   [$_\n" if $debug>=4 ;
  
  # Finally - proceed to 'recognize' end-of-sentences
  # demarcate end-of-sentence based on eos-characters followed by space
  # challenging cases:
  #     ... a [KidKraft_Suite_Elite_Kitchen!]!__...
  #     ... Men's Underwear?] The ... 
  s/([\.\?\!])\]\] / $1]] <\/s> /g ; # handle the unusual case of an EOS occuring at the end of the annotation

  s/([\.\?\!]) /$1 <\/s> /g ; # do not also try to tokenize - just insert the <\/s>

  # compress whitespaces because we may have entered too many (see no two consecutive whitespaces assumption)
  s/[ ]+/ /g ;

  # reinsert legimate end-of-sentence indicating symbols
  s/_DoIrEp/./g ;
  s/_MaLcXe/!/g ;
  s/_KrAmQ/?/g ;

  s/<\/s>[ ]*<\/s>/<\/s>/g ;


  return trim($_) ;

}







#############################################################
############				 TOKENIZER					 ##############
#############################################################
# A simple rules-based tokenizer
#
# For now, it is nearly identical to sentenceBoundaryDetector()>
# 
# TODO:

sub textTokenizer ($) {
	
	local($_) = shift(@_) ; # get the parameter
  die ("ERROR: asked to tokenize on an undefined string.\n") if not defined $_ ;
  print $logFH "DEBUG:  textTokenizer($_)\n" if $debug>=2 ;

  s/$/ ENDOFSTRING/ ;
  s/^/STARTOFSTRING / ;

  # force spaces around double square-brackets and pipes
  s/\]\] / ]] /g ;
  print "DEBUG:   at Bbgak8: $_\n" if $debug>=4 ;
  s/\]\]/ ]] /g ;
  s/\[\[/ [[ /g ;
  s/\|/ | /g ; # so that tokens before and after are treated equality with out with the pipe e.g. PC|CD/DVD

  s/<([a-zA-Z][\/]?)>/ <$1> /g ;  # single-char HTML markup e.g. <b></B>
  
  
  # Simplest cases
  # - not the colon char e.g. http:// nor square-brackets e.g. because of wikitext, nor dash because of product codes dm-183
  # - not if preceeded by a pipe. e.g. [[BL|'s]].
  s/([^|\t])([,;\(\)+\ой\?\!])/$1 $2 /g  ;  # will remove extra-spaces later

  print "DEBUG:   at aklHHd: $_\n" if $debug>=4 ;
  
  # SPECIAL PERIOD HANDLING
  s/(Ph)\.(D)\./$1_DoIrEp$2_DoIrEp/gi ; #Ph.D.
  s/(U)\.(S)\./$1_DoIrEp$2_DoIrEp/gi ; #U.S.
  s/\b([d|m][r|s])\.\b/$1_DoIrEp/gi ;  # Mr., Ms. Mrs. and Dr., Drs.
  s/\b(etc|vol|vs|inc|bros|wt|oz|al)\./$1_DoIrEp /gi ;  # e.g.  ... Super Bros. Brawl, ...  vol. 1 had ... Sony Inc. is ...
  s/\b(\d+)([ ]*)(in|lbs|kg)\./$1$2$3_DoIrEp /gi ;  # 
  s/([^ ])\.([^ ])\. /$1_DoIrEp$2_DoIrEp /g ; # e.g.  ... cleverly titled [Flesh_M.U.S.C.L.E._Poster], is ... 
  
  # challenge example(s):
  #    the Func F30.r. I had - apparently product mentions themselves can have embedded periods
  #    the [Panasonic_45mm_f/2.8].. Later ...
  s/([^\.])\.\./$1 _DoIrEp_DoIrEp/g ; # any two 
  s/_DoIrEp\./_DoIrEp_DoIrEp/g ; # any two consecutive periods


  s/ w\/([^ ])/ w\/ $1/g ;

  print "DEBUG:   at 90a0as: $_\n" if $debug>=4 ;

  # Two or more slashes treated as special (e.g. http://x)
  s/\/\//_hsalS_hsalS/g ;

  # Two or more slashes treated as special (e.g. http://x)
  s/http:/http_noloC/g ;

  # identify tokens with embedded exclamation characters  
  s/ahoo\! /ahoo_MaLcXe /g ;

  print "DEBUG:   at iiYDAa: $_\n" if $debug>=4 ;

  # almost always-separable characters (be sure to avoid http:// ).
  s/http/\t/g ;

  # set aside repeated single quotes. (because that can mean something as WikiText ''italics'' '''bold''' '''''italbold'''''). 
  # hmmm 
  s/ \'\'\'\'\'[^\']/ WIKIITALBOLDSTRT/g;
  s/[^\']\'\'\'\'\' /WIKIITALBOLDEND /g;
  s/ \'\'\'[^\']/ WIKIBOLDSTRT/g;
  s/[^\']\'\'\' /WIKIBOLDEND /g;
  s/ \'\'[^\']/ WIKIITALSTRT/g;
  s/[^\']\'\' /WIKIITALEND /g;
  # set aside repeated double quotes.  
  # hmmm

  # separate sequential: stars
  s/([^|\t])([\*\-\.\/]{2,})/$1 $2 /g  ;

  print "DEBUG:   at 08s8sjh: $_\n" if $debug>=4 ;
  
  # internal periods must be skipped (e.g. IP addresses)
  s/([^ ])\.([^ ])/$1_DoIrEp$2/g ;

  # special chars at the start of a token: colon or dash or period
  s/ ([\'\"\:\&\-\.\/\\]*)([\S])/ $1 $2/g ;

  # special chars at the end of a token: colon, dash, back-slash, or forward-slash
  s/([\S|])([\;\"\:\&\-\.\/\\]+) /$1 $2 /g ;

  # tokenize embedded slashes
  s/ ([^\t])([^ ]*?)([\w]{2,})\/([\w]{3,})/ $1$2$3 \/ $4/g ;
  s/ ([^\t])([^ ]*?)([\w]{2,})\/([\w]{3,})/ $1$2$3 \/ $4/g ;
  s/ ([^\t])([^ ]*?)([\w]{2,})\/([\w]{3,})/ $1$2$3 \/ $4/g ;
  s/ ([^\t])([^ ]*?)([\w]{2,})\/([\w]{3,})/ $1$2$3 \/ $4/g ;
  s/\/([\w]{5,}) / \/ $1 /g ;  # e.g. 2.0/FireWire\s
  s/ ([\d]{3,})\/([\d]{3,})\b/ $1 \/ $2/g ;  # 800/400  
  s/ ([\d]{3,})\/([\d]{3,})\b/ $1 \/ $2/g ;  # 800/400/200
  s/ ([\d]{3,})\/([\d]{3,})\b/ $1 \/ $2/g ;  # 800/400/200/100
  s/\t/http/g ;

  print "DEBUG:   at xuxks7: $_\n" if $debug>=4 ;

  # Double-square brackets Cable (6ft)]") .. and ... the [V1220]- and ...
  # tokenize starting double quotes
  s/ ([\"\#])/ $1 /g ;    # if a space precedes the double quote
  s/\[\[\"/[[_touQd /g ;  # handle special case of staring an annotation
  s/\[\[\#/[[_mySmun /g ; # handle special case of staring an annotation
  s/\[\[/ [[/g  ;  # extra-spaces removed later

  # tokenize ending double quotes
  # challenging cases:
  #   ... is 16" long ...
  #   ... the [SAMSUNG P2770HD Rose Black 27"] also ...
  #   ... the DDP-1" is ...
  s/ ([\d]+?)"/ $1_touQd/g ; # handle the special inches case e.g. ... 16" ...
  s/([^\s]+)" /$1 " /g ; # if a space follows
  s/ ([\d]+)"\]\]/ $1 "] /g ; # if just-inside the annotation


  print "DEBUG:   at 729yds: $_\n" if $debug>=4 ;

  # tokenize other punctuation followed by space (must occur after the double quote test)
  # challenging case(s):
  #   ... A Christmas Classic (1991)]". Here ...
  #   ... (see "[Belkin_DS-71_Cable_(6ft)]") to  ... 
  s/[^\|]([,\)])\]\]/ $1]]/g  ; # the unusual case where the punctuation is inside the brackets
  s/[^\|]([,]) / $1 /g ;
  s/([\)])([ \b])/ $1$2/g  ; # separate in case that the comma occurs immediate after parentheses, such as <U> ... [PXAMG_(PAC_iSimple)], ... </U>


  # tokenize embedded open-square brackets
  s/([^\[|])\[([^\[])/$1 [ $2/g ;
  s/^\[([^\[])/[ $1/g ; # starting single open square-bracket
  # tokenize closing square-brackets  (these two cases may be able to combined)
  s/([^\]])\] /$1 ] /g ;
  s/([^\]])\]$/$1 ]/g ;

  # tokenize possesives
  # challenge example(s):
  # "... Adidas' ..." but not "... 'Adidas' ..."
  #s/'s([ \[])/ 's$1/g ;  # n/a because ealier we injected a space after a single-quote
  s/ \'[ ]+s\b/ \'s/g ;

  print "DEBUG:   at Ijliis: $_\n" if $debug>=4 ;

  # PRODUCT-DOMAIN - near the end
  s/ (\d+)x(\d+) / $1 x $2 /g ; # e.g. 1920x1080 8x4 2x1000 5x1

  # compress whitespaces because we may have entered too many (see no two consecutive whitespaces assumption)
  s/[ ]+/ /g ;

  # remove spaces inside double square-brackets  
  s/ \]\]/]]/g ;
  s/\[\[ /[[/g ;
  s/ \| /|/g ;
  
  # trim
  s/^\s+|\s+$//g ;

  # reinsert legimate symbols
  s/_DoIrEp/./g ;
  s/_MaLcXe/!/g ;
  s/_hsalS/\//g ;
  s/_touQd/"/g ; # "
  s/_noloC/:/g ;
  s/_mySmun/#/g ;
  s/WIKIITALBOLDSTRT/ <B><i> /g;
  s/WIKIITALBOLDEND/ <\/i><\/B>/g;
  s/WIKIBOLDSTRT/ <B> /g;
  s/WIKIBOLDEND/ <\/B> /g;
  s/WIKIITALSTRT/ <i> /g;
  s/WIKIITALEND/ <\/i> /g;

  s/ENDOFSTRING/ / ;
  s/STARTOFSTRING/ / ;

  
  return trim($_) ;
}




#############################################################
############				 DETOKENIZER					 ##############
#############################################################
# A simple rules-based detokenizer
#
# For now, simple
# 
# TODO:

sub textDetokenizer ($) {
	
	local($_) = shift(@_) ; # get the parameter
  die ("ERROR: asked to tokenize on an undefined string.\n") if not defined $_ ;
  print $logFH "DEBUG:  textTokenizer($_)\n" if $debug>=2 ;


  s/[ ]+([\,\;\.\:])/$1/g ;

  # detokenize possesives
  # challenge: "... Adidas ' ..." but not "... ' Adidas ' ..."
  s/ \'s/\'s/g ;

  s/$/ <\/s>/ if length($_)>5 ; # not just after, for example, a </P>

  return trim($_) ;
}







###########################################
# Simple transformations on a string to increase the matches (recall) of terms with minimal impact on precision.
# accounts for some characteristics of user-generated text such as differences in capitalizations and dash-usage.

sub compressFeature($) {
   my $value = shift() ; # assume not empty
   print "DEBUG: compressFeature($value) =>" if $debug>=5 ;
   $value = ceil(0.01 + log($value * $value)) if $value > 0 ;
   $value = $maxCompressValue if $value >= $maxCompressValue ; # large category ceiling
   print " $value\n" if $debug>=5 ;
   return $value ;
}



sub normalizeToken($) {
   my $string = shift() ;
   $string = lc($string) ;
   $string =~ s/[^a-zA-Z0-9 \[\]]/_/g ; # squash special charaters. # exclude [ and ] in order to retaion [wikiTexted_terms]
   $string =~ s/_+/_/g ; # compress repeats
   $string =~ s/(\S)_/$1/g ; # remove if attached to a string
   $string =~ s/_(\S)/$1/g ; # compress spaces
   return $string ;
}



sub trim($) {
   my $string = shift ;
   $string =~ s/^\s+|\s+$//g ;
   return $string ;
}



#################################################################################
##################################### THE END ###################################
#################################################################################
