#!/usr/bin/perl

my $PROGRAM = 'eosTokFeat.pl' ;
my $AUTHOR  = 'Gabor Melli' ;
my $VERSION = '2.0.0' ;
my $VERSIONDATE = "2013.12.19" ;


# A [[EosTokFeat Program]] is a [[Perl program]].
# A [[EosTokFeat Program]] [[user]] can be a [[person]] using a [[command-line shell]] or another [[software program]].
# A [[EosTokFeat Progam]] can accept [[command-line input parameter]]s


use strict ;
use warnings ;
use utf8 ;
use Getopt::Long ;
use lib "." ;
use EOSTOKFEAT qw /processFile sentenceBoundaryDetector textTokenizer textTokenLabelDecorator textTokenFeaturizer derivedFeatures normalizeToken / ;


# Globals
my $debug       = 0 ;
my $printHeader = 0 ;


my $performEOSDetection         = 0 ;
my $performTokenization         = 0 ;
my $performDetokenization       = 0 ;
my $performFeaturization        = 0 ;
my $includeDerivedFeatures      = 0 ;
my $includeGlobalFeatures       = 0 ;
my $includeSimpleBigramFeatures = 0 ;
my $featuresToInclude ;
my $featuresToExclude ;
my $noLabel                     = 0 ;
my $doNotReportFeatureValues    = 0 ;


# set from input params if at all
my $inFile ;
my $outFile ;
my $logFile ;
my $dictFile ;


##########################################
# PROCESS INPUT PARAMETERS
my $help ;
my $verbose = 0 ;
die "ERROR in parameter processing.\n" if not GetOptions (
   'inFile:s'    => \$inFile,
   'outFile:s'	 => \$outFile,
   'logFile:s'	 => \$logFile,
   'dictFile:s'	 => \$dictFile,
   'debug:i'     => \$debug,
   'verbose+'    => \$verbose,
   'eos+'        => \$performEOSDetection,
   'tok+'        => \$performTokenization,
   'detok+'      => \$performDetokenization,
   'feat+'       => \$performFeaturization,
   'drvdfeats+'  => \$includeDerivedFeatures,
   'glblfeats+'  => \$includeGlobalFeatures,
   'bigrmfeats+' => \$includeSimpleBigramFeatures,
   'inclfeats:s' => \$featuresToInclude,
   'exclfeats:s' => \$featuresToExclude,
   'nfeat+'    	 => \$doNotReportFeatureValues,
   'noLabel+'		 => \$noLabel,
   'help'        => \$help,
) ;

# compose the USAGE reprot
my $USAGE ;
$USAGE .= "USAGE:\n" ;
$USAGE .= "   PARAMS: [--inFile=] [--outFile=] [--dictFile=] [--eos] [--tok] [--feat] [--drvdfeats] [--glblfeats] [--bigrmfeats] [--inclfeats] [--exclfeats] [--noLabel] [--debug=] [--verbose] [--help]\n" ;
$USAGE .= "   Example: ./$PROGRAM -inFile=master.txt -outFile=tok.dat -dictFile=syn.dat -d=1\n" ;
$USAGE .= "   Program info: Version: $VERSION($VERSIONDATE)   Contact: $AUTHOR\n" ;


# begin the debugging
$debug=$debug+$verbose ;

# if the user asked for --help
if (defined($help)) {
   print $USAGE ;
exit ;
}






EOSTOKFEAT::processFile(
        $inFile, $outFile, $logFile, $dictFile, $debug, $verbose,
        $performEOSDetection, $performTokenization, $performDetokenization, $performFeaturization,
        $includeDerivedFeatures, $includeGlobalFeatures, $includeSimpleBigramFeatures,
        $featuresToInclude, $featuresToExclude, $doNotReportFeatureValues,
        $noLabel ) ;


exit ;

####################################################